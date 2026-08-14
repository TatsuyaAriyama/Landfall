import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation

/// An invite-only visit to the host's Home Island.
///
/// This deliberately uses a new Firestore root instead of `rooms`, so the old
/// shared-timer/private-harbor data can be retired without leaking into island
/// visits. The six-character document ID remains the invite code.
struct PrivateIslandRoom: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let hostUid: String
    let memberIds: [String]
    let createdAt: Date

    var code: String { id }

    static let maxMembers = 8
    static let maxJoined = 3
}

/// Short-lived state used to render another sailor on the host's island.
/// Stale documents are ignored client-side, so a force-quit cannot leave a
/// permanent duplicate sailor behind.
struct PrivateIslandPresence: Identifiable, Equatable {
    let id: String
    let uid: String
    let x: Float
    let z: Float
    let yaw: Float
    let pose: String
    let scene: String
    let phase: String
    let seatPlacementID: UUID?
    let seatSlotID: String?
    let arrivalNonce: String?
    let updatedAt: Date
}

/// Private-island chat is text-only. Arrival and departure lines are derived
/// from presence changes in the UI instead of accepting forgeable system posts.
struct PrivateIslandChatMessage: Identifiable, Equatable {
    let id: String
    let senderID: String
    let senderName: String
    let text: String
    let createdAt: Date
}

enum PrivateIslandError: LocalizedError {
    case notSignedIn
    case invalidName
    case invalidCode
    case islandNotFound
    case codeUnavailable
    case islandFull
    case tooManyIslands
    case alreadyOwnsIsland
    case hostCannotLeave
    case closeFailed
    case notHost
    case invalidPresence
    case emptyMessage
    case unsafeMessage
    case notMessageOwner
    case invalidBlockTarget

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            LF.text("Sign in to visit a private island.")
        case .invalidName:
            LF.text("Give your island a name.")
        case .invalidCode, .islandNotFound:
            LF.text("No private island was found for this invite code.")
        case .codeUnavailable:
            LF.text("An invite code could not be created. Please try again.")
        case .islandFull:
            LF.text("This private island is full (up to 8 sailors).")
        case .tooManyIslands:
            LF.text("You can join up to 3 private islands.")
        case .alreadyOwnsIsland:
            LF.text("You already host a private island.")
        case .hostCannotLeave:
            LF.text("The host cannot leave their own island. Close the island instead.")
        case .closeFailed:
            LF.text("The private island could not be closed. Please try again.")
        case .notHost:
            LF.text("Only the island host can publish this island.")
        case .invalidPresence:
            LF.text("Your sailor's position could not be shared.")
        case .emptyMessage:
            LF.text("Write a message first.")
        case .unsafeMessage:
            LF.text("That message cannot be sent.")
        case .notMessageOwner:
            LF.text("You can only delete your own messages.")
        case .invalidBlockTarget:
            LF.text("This sailor's block setting could not be changed.")
        }
    }
}

@MainActor
final class PrivateIslandService: ObservableObject {
    static let shared = PrivateIslandService()

    @Published private(set) var islands: [PrivateIslandRoom] = []
    @Published private(set) var currentIsland: PrivateIslandRoom?
    @Published private(set) var islandSnapshot: HomeIslandSnapshot?
    @Published private(set) var hasResolvedIslandSnapshot = false
    @Published private(set) var presences: [PrivateIslandPresence] = []
    @Published private(set) var errorMessage: String?

    private var islandsListener: ListenerRegistration?
    private var islandsListenerUserID: String?
    private var islandListener: ListenerRegistration?
    private var snapshotListener: ListenerRegistration?
    private var presenceListener: ListenerRegistration?
    private var presencePruneTimer: Timer?
    private var presenceHeartbeatTimer: Timer?
    private var presenceTrailingTask: Task<Void, Never>?
    private var listeningCode: String?
    private var lastPresenceWriteAt = Date.distantPast
    private var lastPresenceCode: String?
    private var lastPresenceDraft: PresenceDraft?
    private var visitArrivalNonce: String?
    private var pendingOwnedSnapshot: HomeIslandSnapshot?
    private var ownedSnapshotPublishTask: Task<Void, Never>?

    private struct PresenceDraft {
        let code: String
        let uid: String
        let x: Float
        let z: Float
        let yaw: Float
        let pose: String
        let scene: String
        let phase: String
        let seat: HomeIslandSeatAddress?
        let arrivalNonce: String?
    }

    private var db: Firestore { Firestore.firestore() }
    var currentUserID: String? { Auth.auth().currentUser?.uid }

    private enum Limit {
        static let islandName = 80
        static let displayName = 60
        static let presenceString = 40
        static let placementCoordinate: Float = 10_000
        static let presenceCoordinate: Float = 80
        static let stalePresence: TimeInterval = 45
        static let presenceWriteInterval: TimeInterval = 0.8
    }

    private enum TransactionFailure: Int {
        case notFound = 1
        case full = 2
        case hostCannotLeave = 3
    }

    private static let transactionErrorDomain = "com.keelmira.private-island.transaction"
    /// Keep these values identical to `PhoenixPose.rawValue`. Unknown values
    /// are rendered as idle, but are never written to Firestore.
    private static let allowedPoses: Set<String> = [
        "idle", "walk", "lookout", "raise", "hail", "point", "stargaze", "rest", "sit",
    ]
    /// Keep these values identical to HomeIslandSceneView's visit phases.
    private static let allowedPhases: Set<String> = [
        "arrival", "explore", "edit", "camera", "departure",
    ]

    init() {}

    deinit {
        islandsListener?.remove()
        islandListener?.remove()
        snapshotListener?.remove()
        presenceListener?.remove()
        presencePruneTimer?.invalidate()
        presenceHeartbeatTimer?.invalidate()
        presenceTrailingTask?.cancel()
        ownedSnapshotPublishTask?.cancel()
    }

    // MARK: - Island list

    func listenToJoinedIslands() {
        let previousUserID = islandsListenerUserID
        islandsListener?.remove()
        islandsListener = nil
        guard let uid = currentUserID else {
            islandsListenerUserID = nil
            islands = []
            return
        }
        islandsListenerUserID = uid
        if previousUserID != uid {
            islands = []
            errorMessage = nil
        }

        islandsListener = db.collection("privateIslands")
            .whereField("memberIds", arrayContains: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.islandsListenerUserID == uid else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.islands = snapshot?.documents
                        .compactMap(Self.decodeRoom)
                        .sorted(by: Self.sortRooms) ?? []
                }
            }
    }

    func refreshIslands() async {
        guard let uid = currentUserID else {
            islands = []
            errorMessage = nil
            return
        }
        errorMessage = nil
        do {
            let refreshed = try await fetchJoinedIslands(uid: uid)
            guard currentUserID == uid else { return }
            islands = refreshed
            errorMessage = nil
        } catch {
            guard currentUserID == uid else { return }
            errorMessage = error.localizedDescription
        }
    }

    func stopJoinedIslandsListener() {
        islandsListener?.remove()
        islandsListener = nil
        islandsListenerUserID = nil
    }

    /// Fetches the current sailor's hosted island without depending on a
    /// lobby listener. Used by Home Island autosave publishing.
    func ownedIsland() async throws -> PrivateIslandRoom? {
        guard let uid = currentUserID else { throw PrivateIslandError.notSignedIn }
        // Firestore rules authorize list queries through memberIds. A
        // hostUid-only query cannot prove membership and is therefore denied.
        return try await fetchJoinedIslands(uid: uid)
            .first(where: { $0.hostUid == uid })
    }

    /// Coalesces ordinary Home Island edits and publishes them in one serial
    /// stream. A slow earlier Firestore write can therefore never land after a
    /// newer snapshot and visually roll a visitor's island backwards.
    func enqueueOwnedSnapshot(_ snapshot: HomeIslandSnapshot) {
        pendingOwnedSnapshot = snapshot
        guard ownedSnapshotPublishTask == nil else { return }
        ownedSnapshotPublishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(360))
            guard let self else { return }
            while !Task.isCancelled, let snapshot = pendingOwnedSnapshot {
                pendingOwnedSnapshot = nil
                do {
                    if let island = try await ownedIsland() {
                        try await publishSnapshot(snapshot, to: island.code)
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
                if pendingOwnedSnapshot != nil {
                    try? await Task.sleep(for: .milliseconds(240))
                }
            }
            ownedSnapshotPublishTask = nil
        }
    }

    // MARK: - Create / join / leave

    /// Opens a private island and returns its six-character invite code.
    /// Creating remains a Voyage Pass benefit; entering with a code remains free.
    func createIsland(
        name rawName: String,
        initialSnapshot: HomeIslandSnapshot? = nil
    ) async throws -> String {
        guard let uid = currentUserID else { throw PrivateIslandError.notSignedIn }
        let name = String(
            rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(Limit.islandName)
        )
        guard !name.isEmpty else { throw PrivateIslandError.invalidName }

        // A previous attempt may have committed the island and host card, then
        // lost its connection while publishing the first layout. Recover that
        // durable island instead of making the sailor hit "already hosts" on
        // every retry while the lobby listener is still catching up.
        let joined = try await fetchJoinedIslands(uid: uid)
        if let existing = joined.first(where: { $0.hostUid == uid }) {
            if let initialSnapshot {
                enqueueOwnedSnapshot(initialSnapshot)
            }
            await refreshIslands()
            return existing.code
        }

        try await VoyagePassStore.shared.preparePrivateHarborCreation()
        guard joined.count < PrivateIslandRoom.maxJoined else {
            throw PrivateIslandError.tooManyIslands
        }

        let memberData = Self.memberProfileData(joinedAt: true)
        for _ in 0..<8 {
            let code = Self.generateCode()
            let islandRef = db.collection("privateIslands").document(code)
            let memberRef = islandRef.collection("members").document(uid)
            let result = try await db.runTransaction { transaction, errorPointer -> Any? in
                do {
                    let existing = try transaction.getDocument(islandRef)
                    guard !existing.exists else { return false }
                    transaction.setData([
                        "schemaVersion": 2,
                        "name": name,
                        "hostUid": uid,
                        "memberIds": [uid],
                        "createdAt": FieldValue.serverTimestamp(),
                    ], forDocument: islandRef)
                    transaction.setData(memberData, forDocument: memberRef)
                    return true
                } catch let error as NSError {
                    errorPointer?.pointee = error
                    return nil
                }
            }
            if Self.boolValue(result) {
                if let initialSnapshot {
                    do {
                        try await publishSnapshot(initialSnapshot, to: code)
                    } catch {
                        // The parent island and host membership are already
                        // committed. Do not report creation as failed just
                        // because the first layout publication was interrupted;
                        // Home Island autosave retries it after entry.
                        errorMessage = error.localizedDescription
                        enqueueOwnedSnapshot(initialSnapshot)
                    }
                }
                await refreshIslands()
                return code
            }
        }
        throw PrivateIslandError.codeUnavailable
    }

    /// Joins the island identified by the existing six-character invite code.
    /// Room membership and the visitor profile are committed atomically.
    func joinIsland(code rawCode: String) async throws -> PrivateIslandRoom {
        guard let uid = currentUserID else { throw PrivateIslandError.notSignedIn }
        let code = Self.normalizedCode(rawCode)
        guard code.count == 6 else { throw PrivateIslandError.invalidCode }

        let joined = try await fetchJoinedIslands(uid: uid)
        guard joined.contains(where: { $0.id == code }) || joined.count < PrivateIslandRoom.maxJoined else {
            throw PrivateIslandError.tooManyIslands
        }

        let islandRef = db.collection("privateIslands").document(code)
        let memberRef = islandRef.collection("members").document(uid)
        let newMemberData = Self.memberProfileData(joinedAt: true)
        let existingMemberData = Self.memberProfileData(joinedAt: false)

        do {
            _ = try await db.runTransaction { transaction, errorPointer -> Any? in
                do {
                    let document = try transaction.getDocument(islandRef)
                    guard document.exists else {
                        errorPointer?.pointee = Self.transactionError(.notFound)
                        return nil
                    }
                    var memberIDs = document.data()?["memberIds"] as? [String] ?? []
                    if !memberIDs.contains(uid) {
                        guard memberIDs.count < PrivateIslandRoom.maxMembers else {
                            errorPointer?.pointee = Self.transactionError(.full)
                            return nil
                        }
                        memberIDs.append(uid)
                        transaction.updateData(["memberIds": memberIDs], forDocument: islandRef)
                        transaction.setData(newMemberData, forDocument: memberRef, merge: true)
                    } else {
                        // Preserve the original joinedAt on repeat deep links.
                        transaction.setData(existingMemberData, forDocument: memberRef, merge: true)
                    }
                    return true
                } catch let error as NSError {
                    errorPointer?.pointee = error
                    return nil
                }
            }
        } catch {
            throw Self.mappedTransactionError(error)
        }

        guard let document = try? await islandRef.getDocument(),
              let room = Self.decodeRoom(document)
        else { throw PrivateIslandError.islandNotFound }
        await refreshIslands()
        return room
    }

    /// Leaves a visited island. A host must close their island through the
    /// server-side close flow so nested chat and presence data are removed too.
    func leaveIsland(_ rawCode: String) async throws {
        guard let uid = currentUserID else { throw PrivateIslandError.notSignedIn }
        let code = Self.normalizedCode(rawCode)
        guard code.count == 6 else { throw PrivateIslandError.invalidCode }

        let islandRef = db.collection("privateIslands").document(code)
        let memberRef = islandRef.collection("members").document(uid)
        let presenceRef = islandRef.collection("presence").document(uid)

        do {
            _ = try await db.runTransaction { transaction, errorPointer -> Any? in
                do {
                    let document = try transaction.getDocument(islandRef)
                    guard document.exists else {
                        errorPointer?.pointee = Self.transactionError(.notFound)
                        return nil
                    }
                    let data = document.data() ?? [:]
                    guard data["hostUid"] as? String != uid else {
                        errorPointer?.pointee = Self.transactionError(.hostCannotLeave)
                        return nil
                    }
                    var memberIDs = data["memberIds"] as? [String] ?? []
                    memberIDs.removeAll { $0 == uid }
                    transaction.updateData(["memberIds": memberIDs], forDocument: islandRef)
                    transaction.deleteDocument(memberRef)
                    transaction.deleteDocument(presenceRef)
                    return true
                } catch let error as NSError {
                    errorPointer?.pointee = error
                    return nil
                }
            }
        } catch {
            throw Self.mappedTransactionError(error)
        }

        if listeningCode == code { stopIslandListeners() }
        await refreshIslands()
    }

    /// Permanently closes a hosted island. Nested members, snapshots,
    /// presence and chat are removed by the trusted server function.
    func closeIsland(_ rawCode: String) async throws {
        guard currentUserID != nil else { throw PrivateIslandError.notSignedIn }
        let code = Self.normalizedCode(rawCode)
        guard code.count == 6 else { throw PrivateIslandError.invalidCode }

        let callable = Functions.functions(region: "asia-northeast1")
            .httpsCallable("closePrivateIsland")
        do {
            _ = try await callable.call(["code": code])
        } catch {
            throw PrivateIslandError.closeFailed
        }
        if listeningCode == code { stopIslandListeners() }
        await refreshIslands()
    }

    /// Refreshes the visitor card without publishing study records.
    func publishProfile(to rawCode: String) async throws {
        guard let uid = currentUserID else { throw PrivateIslandError.notSignedIn }
        let code = Self.normalizedCode(rawCode)
        guard code.count == 6 else { throw PrivateIslandError.invalidCode }
        try await db.collection("privateIslands").document(code)
            .collection("members").document(uid)
            .setData(Self.memberProfileData(joinedAt: false), merge: true)
    }

    /// Republishes the current player/boat card to every joined private island.
    ///
    /// The joined-island query is intentionally refreshed at write time instead
    /// of trusting a screen's listener cache. This prevents profile edits made
    /// outside the lobby from writing to retired or already-left rooms. A
    /// missing member card is repaired only when the parent island still lists
    /// this user as a member; Firestore rules enforce that membership again.
    func publishProfileToJoinedIslands() async {
        guard let uid = currentUserID else { return }
        do {
            let joined = try await fetchJoinedIslands(uid: uid)
            for island in joined {
                let memberRef = db.collection("privateIslands").document(island.code)
                    .collection("members").document(uid)
                let member = try await memberRef.getDocument()
                try await memberRef.setData(
                    Self.memberProfileData(joinedAt: !member.exists),
                    merge: member.exists
                )
            }
        } catch {
            // Profile synchronization is best-effort and must never roll back a
            // local player-card or boat customization change.
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Current island listeners

    /// Starts the room, read-only island snapshot, and live-presence listeners
    /// as one visit session. Use a separate service instance for simultaneous UI.
    func listenToIsland(code rawCode: String) {
        let code = Self.normalizedCode(rawCode)
        guard code.count == 6 else {
            errorMessage = PrivateIslandError.invalidCode.localizedDescription
            return
        }
        stopIslandListeners()
        listeningCode = code
        visitArrivalNonce = UUID().uuidString.lowercased()
        errorMessage = nil
        listenToRoom(code: code)
        listenToSnapshot(code: code)
        listenToPresence(code: code)
    }

    func stopIslandListeners() {
        if let draft = lastPresenceDraft {
            db.collection("privateIslands").document(draft.code)
                .collection("presence").document(draft.uid).delete()
        }
        islandListener?.remove()
        snapshotListener?.remove()
        presenceListener?.remove()
        presencePruneTimer?.invalidate()
        presenceHeartbeatTimer?.invalidate()
        presenceTrailingTask?.cancel()
        islandListener = nil
        snapshotListener = nil
        presenceListener = nil
        presencePruneTimer = nil
        presenceHeartbeatTimer = nil
        presenceTrailingTask = nil
        lastPresenceDraft = nil
        lastPresenceCode = nil
        lastPresenceWriteAt = .distantPast
        visitArrivalNonce = nil
        listeningCode = nil
        currentIsland = nil
        islandSnapshot = nil
        hasResolvedIslandSnapshot = false
        presences = []
    }

    private func listenToRoom(code: String) {
        islandListener = db.collection("privateIslands").document(code)
            .addSnapshotListener { [weak self] document, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.errorMessage = nil
                    self.currentIsland = document.flatMap(Self.decodeRoom)
                }
            }
    }

    // MARK: - Host island snapshot

    /// Publishes only the sanitized placement payload. The local persistence
    /// `ownerKey` never leaves the host's device.
    func publishSnapshot(_ snapshot: HomeIslandSnapshot, to rawCode: String) async throws {
        guard let uid = currentUserID else { throw PrivateIslandError.notSignedIn }
        let code = Self.normalizedCode(rawCode)
        guard code.count == 6 else { throw PrivateIslandError.invalidCode }
        let islandRef = db.collection("privateIslands").document(code)
        let room = try await islandRef.getDocument()
        guard room.exists else { throw PrivateIslandError.islandNotFound }
        guard room.data()?["hostUid"] as? String == uid else { throw PrivateIslandError.notHost }

        let placements = Self.sanitizedPlacements(snapshot.placements)
        let payload = placements.map(Self.placementPayload)
        try await islandRef.collection("island").document("current").setData([
            "schemaVersion": snapshot.schemaVersion,
            "revision": FieldValue.increment(Int64(1)),
            "placements": payload,
            "updatedAt": FieldValue.serverTimestamp(),
        ], merge: true)
    }

    private func listenToSnapshot(code: String) {
        hasResolvedIslandSnapshot = false
        snapshotListener = db.collection("privateIslands").document(code)
            .collection("island").document("current")
            .addSnapshotListener { [weak self] document, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.errorMessage = nil
                    guard let document, document.exists else {
                        self.islandSnapshot = nil
                        self.hasResolvedIslandSnapshot = true
                        return
                    }
                    self.islandSnapshot = Self.decodeSnapshot(document, code: code)
                    self.hasResolvedIslandSnapshot = true
                }
            }

        // A cached host snapshot can be painted immediately even if the live
        // watch stream is reconnecting after the full-screen world transition.
        Task { [weak self] in
            guard let self else { return }
            do {
                let document = try await db.collection("privateIslands").document(code)
                    .collection("island").document("current")
                    .getDocument(source: .cache)
                guard listeningCode == code,
                      !hasResolvedIslandSnapshot,
                      document.exists
                else { return }
                islandSnapshot = Self.decodeSnapshot(document, code: code)
                hasResolvedIslandSnapshot = true
            } catch {
                // A cache miss is expected for a first visit. The live listener
                // remains authoritative and will resolve either data or absence.
            }
        }
    }

    // MARK: - Live presence

    /// Publishes at most about once per second during movement. Set `force` for
    /// arrival, sitting, standing, and departure transitions.
    func publishPresence(
        code rawCode: String,
        x: Float,
        z: Float,
        yaw: Float,
        pose rawPose: String,
        scene rawScene: String = "island",
        phase rawPhase: String = "explore",
        seat: HomeIslandSeatAddress? = nil,
        arrivalNonce: String? = nil,
        force: Bool = false
    ) async throws {
        guard let uid = currentUserID else { throw PrivateIslandError.notSignedIn }
        let code = Self.normalizedCode(rawCode)
        guard code.count == 6,
              listeningCode == code,
              x.isFinite, z.isFinite, yaw.isFinite,
              abs(x) <= Limit.presenceCoordinate, abs(z) <= Limit.presenceCoordinate
        else { throw PrivateIslandError.invalidPresence }

        let pose = Self.allowedPoses.contains(rawPose) ? rawPose : "idle"
        let scene = Self.normalizedPresenceScene(rawScene)
        let phase = Self.allowedPhases.contains(rawPhase) ? rawPhase : "explore"
        let normalizedYaw = atan2(sin(yaw), cos(yaw))
        let resolvedArrivalNonce = arrivalNonce ?? (phase == "arrival" ? visitArrivalNonce : nil)
        let draft = PresenceDraft(
            code: code,
            uid: uid,
            x: x,
            z: z,
            yaw: normalizedYaw,
            pose: pose,
            scene: scene,
            phase: phase,
            seat: seat,
            arrivalNonce: resolvedArrivalNonce
        )
        lastPresenceDraft = draft
        ensurePresenceHeartbeat()

        let now = Date()
        let elapsed = now.timeIntervalSince(lastPresenceWriteAt)
        if !force,
           lastPresenceCode == code,
           elapsed < Limit.presenceWriteInterval {
            scheduleTrailingPresenceWrite(after: Limit.presenceWriteInterval - elapsed)
            return
        }
        presenceTrailingTask?.cancel()
        presenceTrailingTask = nil

        do {
            try await writePresence(draft)
            lastPresenceCode = code
            lastPresenceWriteAt = Date()
        } catch {
            lastPresenceWriteAt = .distantPast
            throw error
        }
    }

    private func writePresence(_ draft: PresenceDraft) async throws {
        guard listeningCode == draft.code else { return }
        var data: [String: Any] = [
            "uid": draft.uid,
            "x": Double(draft.x),
            "z": Double(draft.z),
            "yaw": Double(draft.yaw),
            "pose": String(draft.pose.prefix(Limit.presenceString)),
            "scene": draft.scene,
            "phase": String(draft.phase.prefix(Limit.presenceString)),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let seat = draft.seat {
            data["seatPlacementId"] = seat.placementID.uuidString.lowercased()
            data["seatSlotId"] = String(seat.slotID.prefix(Limit.presenceString))
        } else {
            data["seatPlacementId"] = FieldValue.delete()
            data["seatSlotId"] = FieldValue.delete()
        }
        if let arrivalNonce = draft.arrivalNonce, !arrivalNonce.isEmpty {
            data["arrivalNonce"] = String(arrivalNonce.prefix(Limit.presenceString))
        } else {
            data["arrivalNonce"] = FieldValue.delete()
        }

        try await db.collection("privateIslands").document(draft.code)
            .collection("presence").document(draft.uid)
            .setData(data, merge: true)
    }

    private func ensurePresenceHeartbeat() {
        guard presenceHeartbeatTimer == nil else { return }
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let draft = self.lastPresenceDraft else { return }
                do {
                    try await self.writePresence(draft)
                    self.lastPresenceWriteAt = Date()
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        presenceHeartbeatTimer = timer
    }

    /// A pure throttle can lose the final transform when the player stops
    /// during the throttle window. This trailing write commits that last pose.
    private func scheduleTrailingPresenceWrite(after delay: TimeInterval) {
        presenceTrailingTask?.cancel()
        let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
        presenceTrailingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled,
                  let self,
                  let draft = self.lastPresenceDraft
            else { return }
            do {
                try await self.writePresence(draft)
                self.lastPresenceCode = draft.code
                self.lastPresenceWriteAt = Date()
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.presenceTrailingTask = nil
        }
    }

    func removePresence(from rawCode: String) async {
        guard let uid = currentUserID else { return }
        let code = Self.normalizedCode(rawCode)
        guard code.count == 6 else { return }
        if lastPresenceDraft?.code == code {
            presenceHeartbeatTimer?.invalidate()
            presenceTrailingTask?.cancel()
            presenceHeartbeatTimer = nil
            presenceTrailingTask = nil
            lastPresenceDraft = nil
            lastPresenceCode = nil
            lastPresenceWriteAt = .distantPast
        }
        try? await db.collection("privateIslands").document(code)
            .collection("presence").document(uid).delete()
    }

    private func listenToPresence(code: String) {
        presenceListener = db.collection("privateIslands").document(code)
            .collection("presence")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.presences = snapshot?.documents
                        .compactMap(Self.decodePresence)
                        .filter(Self.isFreshPresence) ?? []
                }
            }
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.presences.removeAll { !Self.isFreshPresence($0) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        presencePruneTimer = timer
    }

    // MARK: - Decode / sanitize

    private func fetchJoinedIslands(uid: String) async throws -> [PrivateIslandRoom] {
        let snapshot = try await db.collection("privateIslands")
            .whereField("memberIds", arrayContains: uid)
            .getDocuments()
        return snapshot.documents.compactMap(Self.decodeRoom).sorted(by: Self.sortRooms)
    }

    private static func sortRooms(_ lhs: PrivateIslandRoom, _ rhs: PrivateIslandRoom) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private static func decodeRoom(_ document: DocumentSnapshot) -> PrivateIslandRoom? {
        guard document.exists,
              let data = document.data(),
              let name = data["name"] as? String,
              let hostUid = data["hostUid"] as? String,
              let memberIds = data["memberIds"] as? [String]
        else { return nil }
        return PrivateIslandRoom(
            id: document.documentID,
            name: name,
            hostUid: hostUid,
            memberIds: memberIds,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
        )
    }

    private static func decodeSnapshot(
        _ document: DocumentSnapshot,
        code: String
    ) -> HomeIslandSnapshot? {
        guard let data = document.data(),
              let rawPlacements = data["placements"] as? [[String: Any]]
        else { return nil }
        let placements = sanitizedPlacements(rawPlacements.compactMap(decodePlacement))
        return HomeIslandSnapshot(
            schemaVersion: intValue(data["schemaVersion"]) ?? 1,
            ownerKey: "private-island:\(code)",
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast,
            placements: placements
        )
    }

    private static func decodePlacement(_ data: [String: Any]) -> HomeIslandPlacement? {
        guard let idString = data["id"] as? String,
              let id = UUID(uuidString: idString),
              let assetID = data["assetID"] as? String,
              let transform = data["transform"] as? [String: Any],
              let x = floatValue(transform["x"]),
              let z = floatValue(transform["z"]),
              let yaw = floatValue(transform["yaw"]),
              let scale = floatValue(transform["scale"])
        else { return nil }
        return HomeIslandPlacement(
            id: id,
            assetID: assetID,
            transform: HomeIslandTransform(x: x, z: z, yaw: yaw, scale: scale)
        )
    }

    private static func placementPayload(_ placement: HomeIslandPlacement) -> [String: Any] {
        [
            "id": placement.id.uuidString.lowercased(),
            "assetID": placement.assetID,
            "transform": [
                "x": Double(placement.transform.x),
                "z": Double(placement.transform.z),
                "yaw": Double(placement.transform.yaw),
                "scale": Double(placement.transform.scale),
            ],
        ]
    }

    private static func sanitizedPlacements(
        _ placements: [HomeIslandPlacement]
    ) -> [HomeIslandPlacement] {
        var counts: [String: Int] = [:]
        var seenIDs: Set<UUID> = []
        var result: [HomeIslandPlacement] = []
        result.reserveCapacity(min(placements.count, HomeIslandMetrics.maximumPlacements))

        for placement in placements {
            guard result.count < HomeIslandMetrics.maximumPlacements,
                  HomeIslandAssetCatalog.approvedIDs.contains(placement.assetID),
                  seenIDs.insert(placement.id).inserted,
                  placement.transform.x.isFinite,
                  placement.transform.z.isFinite,
                  placement.transform.yaw.isFinite,
                  placement.transform.scale.isFinite,
                  abs(placement.transform.x) <= Limit.placementCoordinate,
                  abs(placement.transform.z) <= Limit.placementCoordinate
            else { continue }

            let count = counts[placement.assetID, default: 0]
            guard count < HomeIslandAssetCatalog.placementLimit(for: placement.assetID) else { continue }

            var copy = placement
            copy.transform.scale = HomeIslandAssetCatalog.persistedScale(
                assetID: copy.assetID,
                storedScale: min(2, max(0.25, copy.transform.scale))
            )
            copy.transform.yaw = atan2(sin(copy.transform.yaw), cos(copy.transform.yaw))
            guard let transform = HomeIslandAssetCatalog.placementTransform(
                assetID: copy.assetID,
                x: copy.transform.x,
                z: copy.transform.z,
                yaw: copy.transform.yaw,
                scale: copy.transform.scale,
                requireValidCoastPoint: false
            ) else { continue }
            copy.transform = transform
            result.append(copy)
            counts[copy.assetID] = count + 1
        }
        return result
    }

    private static func decodePresence(_ document: QueryDocumentSnapshot) -> PrivateIslandPresence? {
        let data = document.data()
        guard let uid = data["uid"] as? String,
              uid == document.documentID,
              let x = floatValue(data["x"]),
              let z = floatValue(data["z"]),
              let yaw = floatValue(data["yaw"]),
              let pose = data["pose"] as? String,
              allowedPoses.contains(pose),
              let scene = data["scene"] as? String,
              isAllowedPresenceScene(scene),
              let phase = data["phase"] as? String,
              allowedPhases.contains(phase),
              let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue(),
              x.isFinite, z.isFinite, yaw.isFinite,
              abs(x) <= Limit.presenceCoordinate, abs(z) <= Limit.presenceCoordinate
        else { return nil }

        let placementID = (data["seatPlacementId"] as? String).flatMap(UUID.init(uuidString:))
        return PrivateIslandPresence(
            id: document.documentID,
            uid: uid,
            x: x,
            z: z,
            yaw: yaw,
            pose: pose,
            scene: scene,
            phase: phase,
            seatPlacementID: placementID,
            seatSlotID: data["seatSlotId"] as? String,
            arrivalNonce: data["arrivalNonce"] as? String,
            updatedAt: updatedAt
        )
    }

    private static func isFreshPresence(_ presence: PrivateIslandPresence) -> Bool {
        Date().timeIntervalSince(presence.updatedAt) <= Limit.stalePresence
    }

    private static func normalizedPresenceScene(_ raw: String) -> String {
        let trimmed = String(raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(Limit.presenceString))
        return isAllowedPresenceScene(trimmed) ? trimmed : "island"
    }

    private static func isAllowedPresenceScene(_ value: String) -> Bool {
        value == "island"
            || value == "interior:weathered_cottage"
            || value == "interior:navigator_tent"
    }

    private static func memberProfileData(joinedAt: Bool) -> [String: Any] {
        var data = PlayerProfile.harborProfileData()
        data["displayName"] = String(PlayerProfile.displayName.prefix(Limit.displayName))
        if joinedAt { data["joinedAt"] = FieldValue.serverTimestamp() }
        return data
    }

    private static func generateCode() -> String {
        let characters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).compactMap { _ in characters.randomElement() })
    }

    static func normalizedCode(_ rawCode: String) -> String {
        let allowed = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let compact = rawCode.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard compact.allSatisfy(allowed.contains) else { return "" }
        return compact
    }

    private static func transactionError(_ failure: TransactionFailure) -> NSError {
        NSError(domain: transactionErrorDomain, code: failure.rawValue)
    }

    private static func mappedTransactionError(_ error: Error) -> Error {
        let error = error as NSError
        guard error.domain == transactionErrorDomain,
              let failure = TransactionFailure(rawValue: error.code)
        else { return error }
        switch failure {
        case .notFound: return PrivateIslandError.islandNotFound
        case .full: return PrivateIslandError.islandFull
        case .hostCannotLeave: return PrivateIslandError.hostCannotLeave
        }
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return false
    }

    private static func intValue(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue ?? value as? Int
    }

    private static func floatValue(_ value: Any?) -> Float? {
        if let value = value as? NSNumber { return value.floatValue }
        if let value = value as? Double { return Float(value) }
        return value as? Float
    }
}

/// Per-screen chat service. Unlike the old singleton, one island's listener
/// cannot silently stop another island or harbor listener.
@MainActor
final class PrivateIslandChatService: ObservableObject {
    let islandCode: String

    @Published private(set) var messages: [PrivateIslandChatMessage] = []
    @Published private(set) var blockedUserIDs: Set<String> = []
    @Published private(set) var errorMessage: String?

    private var allMessages: [PrivateIslandChatMessage] = []
    private var listener: ListenerRegistration?
    private var hasResolvedBlocks = false

    private var db: Firestore { Firestore.firestore() }
    var currentUserID: String? { Auth.auth().currentUser?.uid }

    init(islandCode rawCode: String) {
        islandCode = PrivateIslandService.normalizedCode(rawCode)
    }

    deinit {
        listener?.remove()
    }

    func start() {
        stop(clearMessages: false)
        errorMessage = nil
        guard islandCode.count == 6 else {
            errorMessage = PrivateIslandError.invalidCode.localizedDescription
            return
        }
        hasResolvedBlocks = false
        messages = []
        Task {
            await loadBlockedUsers()
            guard !Task.isCancelled, listener == nil else { return }
            hasResolvedBlocks = true
            attachChatListener()
        }
    }

    func stop(clearMessages: Bool = true) {
        listener?.remove()
        listener = nil
        if clearMessages {
            allMessages = []
            messages = []
        }
    }

    private func attachChatListener() {
        listener = chatReference
            .order(by: "createdAt", descending: false)
            .limit(toLast: 120)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.errorMessage = nil
                    self.allMessages = snapshot?.documents.compactMap(Self.decodeMessage) ?? []
                    if self.hasResolvedBlocks { self.applyBlocks() }
                }
            }
    }

    func send(_ rawText: String) async throws {
        guard let uid = currentUserID else { throw PrivateIslandError.notSignedIn }
        let text = String(
            rawText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)
        )
        guard !text.isEmpty else { throw PrivateIslandError.emptyMessage }
        guard PrivateIslandChatSafety.isAllowed(text) else { throw PrivateIslandError.unsafeMessage }

        // Use the shared member card as the canonical name. A locally edited
        // name that has not been published yet must not forge another display.
        let member = try await db.collection("privateIslands").document(islandCode)
            .collection("members").document(uid).getDocument()
        guard let storedName = member.data()?["displayName"] as? String else {
            throw PrivateIslandError.islandNotFound
        }
        let senderName = String(
            storedName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)
        )
        guard !senderName.isEmpty else { throw PrivateIslandError.islandNotFound }

        // Echo the line immediately instead of leaving a successful tap with
        // no visible result while Firestore waits for the server round-trip.
        // The snapshot listener replaces this provisional copy after commit.
        let messageReference = chatReference.document()
        let optimisticMessage = PrivateIslandChatMessage(
            id: messageReference.documentID,
            senderID: uid,
            senderName: senderName,
            text: text,
            createdAt: Date()
        )
        allMessages.removeAll { $0.id == optimisticMessage.id }
        allMessages.append(optimisticMessage)
        applyBlocks()

        do {
            try await messageReference.setData([
                "uid": uid,
                "senderName": senderName,
                "kind": "text",
                "text": text,
                "createdAt": FieldValue.serverTimestamp(),
            ])
        } catch {
            allMessages.removeAll { $0.id == optimisticMessage.id }
            applyBlocks()
            throw error
        }
    }

    func delete(_ message: PrivateIslandChatMessage) async throws {
        guard let uid = currentUserID else { throw PrivateIslandError.notSignedIn }
        guard message.senderID == uid else { throw PrivateIslandError.notMessageOwner }
        try await chatReference.document(message.id).delete()
    }

    /// Writes a restricted moderation report. Chat content is capped to the
    /// same 500-character maximum used by the message rules.
    func report(_ message: PrivateIslandChatMessage, targetUserID: String) async throws {
        guard let uid = currentUserID else { throw PrivateIslandError.notSignedIn }
        guard !targetUserID.isEmpty, targetUserID != uid else {
            throw PrivateIslandError.invalidBlockTarget
        }
        try await db.collection("reports").addDocument(data: [
            "source": "privateIsland",
            "privateIslandCode": islandCode,
            "reporterUid": uid,
            "targetUid": targetUserID,
            "messageId": message.id,
            "text": String(message.text.prefix(500)),
            "createdAt": FieldValue.serverTimestamp(),
        ])
    }

    func loadBlockedUsers() async {
        guard let uid = currentUserID else {
            blockedUserIDs = []
            applyBlocks()
            return
        }
        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("blocks").getDocuments()
            blockedUserIDs = Set(snapshot.documents.map(\.documentID))
            applyBlocks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func block(_ targetUserID: String) async throws {
        guard let uid = currentUserID else { throw PrivateIslandError.notSignedIn }
        guard !targetUserID.isEmpty, targetUserID != uid else {
            throw PrivateIslandError.invalidBlockTarget
        }
        try await db.collection("users").document(uid).collection("blocks")
            .document(targetUserID).setData(["createdAt": FieldValue.serverTimestamp()])
        blockedUserIDs.insert(targetUserID)
        applyBlocks()
    }

    func unblock(_ targetUserID: String) async throws {
        guard let uid = currentUserID else { throw PrivateIslandError.notSignedIn }
        guard !targetUserID.isEmpty, targetUserID != uid else {
            throw PrivateIslandError.invalidBlockTarget
        }
        try await db.collection("users").document(uid).collection("blocks")
            .document(targetUserID).delete()
        blockedUserIDs.remove(targetUserID)
        applyBlocks()
    }

    private var chatReference: CollectionReference {
        db.collection("privateIslands").document(islandCode).collection("chat")
    }

    private func applyBlocks() {
        messages = allMessages.filter { !blockedUserIDs.contains($0.senderID) }
    }

    private static func decodeMessage(
        _ document: QueryDocumentSnapshot
    ) -> PrivateIslandChatMessage? {
        let data = document.data()
        guard data["kind"] as? String == "text",
              let senderID = data["uid"] as? String,
              let text = data["text"] as? String,
              !text.isEmpty,
              text.count <= 500
        else { return nil }
        return PrivateIslandChatMessage(
            id: document.documentID,
            senderID: senderID,
            senderName: data["senderName"] as? String ?? LF.text("Sailor"),
            text: text,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }
}

private enum PrivateIslandChatSafety {
    private static let blockedFragments = [
        "killyourself", "kys", "nigger", "faggot",
        "死ね", "しね", "殺す", "ころす", "自殺しろ",
    ]

    static func isAllowed(_ text: String) -> Bool {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let compact = folded.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || $0.value > 0x7F }
            .map(String.init)
            .joined()
            .lowercased()
        return !blockedFragments.contains { compact.contains($0) }
    }
}
