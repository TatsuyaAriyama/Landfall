import FirebaseAuth
import FirebaseFirestore
import Foundation

/// 最大4人で使うプライベートルームの共通タイマー。
///
/// Web版と同じFirestore契約:
/// rooms/{roomId}/crewSessions/{sessionId}
/// rooms/{roomId}/crewSessions/{sessionId}/plans/{uid}
///
/// ルーム・メンバー・最新セッション・各自の準備を購読し、参加した端末すべてに
/// 同じ船団・同じ開始時刻・同じ残り時間が届く。
struct CrewSession: Identifiable, Equatable {
    let id: String
    let durationMinutes: Int
    let createdAt: Date
    let createdBy: String
    let startedAt: Date?

    var finishAt: Date? {
        startedAt?.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }
}

struct CrewPlan: Identifiable, Equatable {
    var id: String { uid }

    let uid: String
    let itemID: String
    let itemName: String
    let itemStyle: String
    let itemSymbol: String
    let intention: String
    let preparedAt: Date
    let recall: String?
    let recordedAt: Date?
}

@MainActor
final class CrewSessionService: ObservableObject {
    @Published private(set) var room: HarborRoom?
    @Published private(set) var members: [HarborMember] = []
    @Published private(set) var session: CrewSession?
    @Published private(set) var plans: [CrewPlan] = []
    @Published private(set) var errorMessage: String?

    private var roomListener: ListenerRegistration?
    private var membersListener: ListenerRegistration?
    private var sessionListener: ListenerRegistration?
    private var plansListener: ListenerRegistration?
    private var listeningRoomID: String?
    private var listeningSessionID: String?

    private var db: Firestore { Firestore.firestore() }
    private var uid: String? { Auth.auth().currentUser?.uid }
    var currentUID: String? {
        #if DEBUG
        if Self.previewEnabled { return "preview-self" }
        #endif
        return uid
    }

    deinit {
        roomListener?.remove()
        membersListener?.remove()
        sessionListener?.remove()
        plansListener?.remove()
    }

    func listen(room initialRoom: HarborRoom) {
        guard listeningRoomID != initialRoom.id else { return }
        stop()
        listeningRoomID = initialRoom.id
        room = initialRoom

        #if DEBUG
        if Self.previewEnabled {
            seedPreview(room: initialRoom)
            return
        }
        #endif

        let roomRef = db.collection("rooms").document(initialRoom.id)
        roomListener = roomRef.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let snapshot, snapshot.exists, let data = snapshot.data(),
                      let name = data["name"] as? String,
                      let memberIDs = data["memberIds"] as? [String] else { return }
                self.room = HarborRoom(
                    id: snapshot.documentID,
                    name: name,
                    memberIds: memberIDs,
                    ownerUid: data["ownerUid"] as? String
                )
            }
        }

        membersListener = roomRef.collection("members").addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.members = snapshot?.documents
                    .map(Self.member)
                    .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                    ?? []
            }
        }

        sessionListener = roomRef.collection("crewSessions")
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    let next = snapshot?.documents.first.map(Self.crewSession)
                    self.session = next
                    self.listenToPlans(roomID: initialRoom.id, sessionID: next?.id)
                }
            }
    }

    func stop() {
        roomListener?.remove()
        membersListener?.remove()
        sessionListener?.remove()
        plansListener?.remove()
        roomListener = nil
        membersListener = nil
        sessionListener = nil
        plansListener = nil
        listeningRoomID = nil
        listeningSessionID = nil
        room = nil
        members = []
        session = nil
        plans = []
        errorMessage = nil
    }

    func openSession(roomID: String, durationMinutes: Int = 25) async throws {
        #if DEBUG
        if Self.previewEnabled {
            let now = Date()
            session = CrewSession(
                id: "preview-\(Int(now.timeIntervalSince1970))",
                durationMinutes: Self.clampedDuration(durationMinutes),
                createdAt: now,
                createdBy: currentUID ?? "preview-self",
                startedAt: nil
            )
            plans = []
            return
        }
        #endif
        guard let uid = currentUID else { throw RoomError.notSignedIn }
        let duration = Self.clampedDuration(durationMinutes)
        try await db.collection("rooms").document(roomID)
            .collection("crewSessions")
            .addDocument(data: [
                "durationMinutes": duration,
                "createdAt": FieldValue.serverTimestamp(),
                "createdBy": uid,
            ])
    }

    func updateDuration(roomID: String, sessionID: String, durationMinutes: Int) async throws {
        #if DEBUG
        if Self.previewEnabled, let current = session, current.id == sessionID {
            session = CrewSession(
                id: current.id,
                durationMinutes: Self.clampedDuration(durationMinutes),
                createdAt: current.createdAt,
                createdBy: current.createdBy,
                startedAt: current.startedAt
            )
            return
        }
        #endif
        try await sessionRef(roomID: roomID, sessionID: sessionID)
            .updateData(["durationMinutes": Self.clampedDuration(durationMinutes)])
    }

    func prepare(
        roomID: String,
        sessionID: String,
        itemID: String,
        itemName: String,
        itemStyle: String,
        itemSymbol: String,
        intention: String
    ) async throws {
        guard let uid = currentUID else { throw RoomError.notSignedIn }
        let cleanIntention = String(
            intention.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)
        )
        guard !cleanIntention.isEmpty else { throw CrewSessionError.emptyIntention }
        #if DEBUG
        if Self.previewEnabled {
            let plan = CrewPlan(
                uid: uid,
                itemID: itemID,
                itemName: String(itemName.prefix(60)),
                itemStyle: String(itemStyle.prefix(24)),
                itemSymbol: String(itemSymbol.prefix(24)),
                intention: cleanIntention,
                preparedAt: Date(),
                recall: nil,
                recordedAt: nil
            )
            plans.removeAll { $0.uid == uid }
            plans.append(plan)
            plans.sort { $0.preparedAt < $1.preparedAt }
            return
        }
        #endif
        try await plansRef(roomID: roomID, sessionID: sessionID)
            .document(uid)
            .setData([
                "itemId": itemID,
                "itemName": String(itemName.prefix(60)),
                "itemStyle": String(itemStyle.prefix(24)),
                "itemSymbol": String(itemSymbol.prefix(24)),
                "intention": cleanIntention,
                "preparedAt": FieldValue.serverTimestamp(),
            ])
    }

    func start(roomID: String, sessionID: String) async throws {
        #if DEBUG
        if Self.previewEnabled, let current = session, current.id == sessionID {
            session = CrewSession(
                id: current.id,
                durationMinutes: current.durationMinutes,
                createdAt: current.createdAt,
                createdBy: current.createdBy,
                startedAt: Date()
            )
            return
        }
        #endif
        try await sessionRef(roomID: roomID, sessionID: sessionID)
            .updateData(["startedAt": FieldValue.serverTimestamp()])
    }

    func markRecorded(
        roomID: String,
        sessionID: String,
        recall: String
    ) async throws {
        guard let uid = currentUID else { throw RoomError.notSignedIn }
        let cleanRecall = String(
            recall.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)
        )
        guard cleanRecall.count >= 20 else { throw CrewSessionError.recallTooShort }
        #if DEBUG
        if Self.previewEnabled, let index = plans.firstIndex(where: { $0.uid == uid }) {
            let current = plans[index]
            plans[index] = CrewPlan(
                uid: current.uid,
                itemID: current.itemID,
                itemName: current.itemName,
                itemStyle: current.itemStyle,
                itemSymbol: current.itemSymbol,
                intention: current.intention,
                preparedAt: current.preparedAt,
                recall: cleanRecall,
                recordedAt: Date()
            )
            return
        }
        #endif
        try await plansRef(roomID: roomID, sessionID: sessionID)
            .document(uid)
            .setData([
                "recall": cleanRecall,
                "recordedAt": FieldValue.serverTimestamp(),
            ], merge: true)
    }

    private func listenToPlans(roomID: String, sessionID: String?) {
        guard listeningSessionID != sessionID else { return }
        plansListener?.remove()
        plansListener = nil
        listeningSessionID = sessionID
        plans = []
        guard let sessionID else { return }

        plansListener = plansRef(roomID: roomID, sessionID: sessionID)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.plans = snapshot?.documents
                        .map(Self.plan)
                        .sorted { $0.preparedAt < $1.preparedAt }
                        ?? []
                }
            }
    }

    private func sessionRef(roomID: String, sessionID: String) -> DocumentReference {
        db.collection("rooms").document(roomID)
            .collection("crewSessions").document(sessionID)
    }

    private func plansRef(roomID: String, sessionID: String) -> CollectionReference {
        sessionRef(roomID: roomID, sessionID: sessionID).collection("plans")
    }

    private static func clampedDuration(_ minutes: Int) -> Int {
        min(max(minutes, 1), 240)
    }

    private static func crewSession(_ document: QueryDocumentSnapshot) -> CrewSession {
        let data = document.data()
        return CrewSession(
            id: document.documentID,
            durationMinutes: integer(data["durationMinutes"]) ?? 25,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            createdBy: data["createdBy"] as? String ?? "",
            startedAt: (data["startedAt"] as? Timestamp)?.dateValue()
        )
    }

    private static func plan(_ document: QueryDocumentSnapshot) -> CrewPlan {
        let data = document.data()
        return CrewPlan(
            uid: document.documentID,
            itemID: data["itemId"] as? String ?? "",
            itemName: data["itemName"] as? String ?? "",
            itemStyle: data["itemStyle"] as? String ?? TileStyle.midnight.rawValue,
            itemSymbol: data["itemSymbol"] as? String ?? TileSymbol.compass.rawValue,
            intention: data["intention"] as? String ?? "",
            preparedAt: (data["preparedAt"] as? Timestamp)?.dateValue() ?? Date(),
            recall: data["recall"] as? String,
            recordedAt: (data["recordedAt"] as? Timestamp)?.dateValue()
        )
    }

    private static func member(_ document: QueryDocumentSnapshot) -> HarborMember {
        let data = document.data()
        let rawName = (data["displayName"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return HarborMember(
            id: document.documentID,
            displayName: rawName.isEmpty ? LF.text("Sailor") : rawName,
            styleToken: data["styleToken"] as? String ?? TileStyle.midnight.rawValue,
            symbolToken: data["symbolToken"] as? String ?? TileSymbol.phoenix.rawValue,
            resolve: data["resolve"] as? String ?? "",
            sinceDay: data["sinceDay"] as? String ?? "",
            boatSail: data["boatSail"] as? String,
            boatJib: data["boatJib"] as? String,
            boatHull: data["boatHull"] as? String,
            boatStripe: data["boatStripe"] as? String,
            boatFlag: data["boatFlag"] as? String
        )
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        return (value as? NSNumber)?.intValue
    }

    #if DEBUG
    private static var previewEnabled: Bool {
        ProcessInfo.processInfo.environment["LANDFALL_PRIVATE_PREVIEW"] == "1"
    }

    private func seedPreview(room initialRoom: HarborRoom) {
        let previewMembers: [String: HarborMember] = [
            "preview-self": HarborMember(
                id: "preview-self",
                displayName: "ミラ",
                styleToken: TileStyle.midnight.rawValue,
                symbolToken: TileSymbol.compass.rawValue,
                resolve: "今日の一歩を、同じ海で。",
                boatSail: "sand",
                boatJib: "sand",
                boatHull: "walnut",
                boatStripe: "dark",
                boatFlag: "sand"
            ),
            "preview-akari": HarborMember(
                id: "preview-akari",
                displayName: "灯",
                styleToken: TileStyle.coral.rawValue,
                symbolToken: TileSymbol.lighthouse.rawValue,
                resolve: "静かに、でも止まらず。",
                boatSail: "coral",
                boatJib: "coral",
                boatHull: "walnut",
                boatStripe: "dark",
                boatFlag: "coral"
            ),
            "preview-nagi": HarborMember(
                id: "preview-nagi",
                displayName: "凪",
                styleToken: TileStyle.seaGreen.rawValue,
                symbolToken: TileSymbol.anchor.rawValue,
                resolve: "焦らず、今日の風で。",
                boatSail: "seaGreen",
                boatJib: "seaGreen",
                boatHull: "walnut",
                boatStripe: "dark",
                boatFlag: "seaGreen"
            ),
        ]
        members = initialRoom.memberIds.compactMap { previewMembers[$0] }

        let phase = ProcessInfo.processInfo.environment["LANDFALL_CREW_PHASE"] ?? "prepare"
        guard phase != "opening" else {
            session = nil
            plans = []
            return
        }

        let createdAt = Date().addingTimeInterval(-180)
        let duration = phase == "prepare" ? 25 : 1
        let startedAt: Date?
        switch phase {
        case "underway":
            startedAt = Date().addingTimeInterval(-18)
        case "arrival":
            startedAt = Date().addingTimeInterval(-90)
        default:
            startedAt = nil
        }
        session = CrewSession(
            id: "preview-session",
            durationMinutes: duration,
            createdAt: createdAt,
            createdBy: "preview-self",
            startedAt: startedAt
        )

        let preparedAt = createdAt.addingTimeInterval(30)
        let samplePlans: [CrewPlan] = [
            CrewPlan(
                uid: "preview-akari",
                itemID: "preview-reading",
                itemName: "読書",
                itemStyle: TileStyle.coral.rawValue,
                itemSymbol: TileSymbol.book.rawValue,
                intention: "第3章を読み、要点を三つ残す",
                preparedAt: preparedAt,
                recall: phase == "arrival" ? "重要な考えを、自分の言葉で三つ思い出して書き残した。" : nil,
                recordedAt: phase == "arrival" ? Date() : nil
            ),
            CrewPlan(
                uid: "preview-nagi",
                itemID: "preview-writing",
                itemName: "記事作成",
                itemStyle: TileStyle.seaGreen.rawValue,
                itemSymbol: TileSymbol.pen.rawValue,
                intention: "導入から最初の節まで書き切る",
                preparedAt: preparedAt.addingTimeInterval(8),
                recall: phase == "arrival" ? "導入の流れと見出しのつながりを、見ずに組み直せた。" : nil,
                recordedAt: phase == "arrival" ? Date() : nil
            ),
        ]
        var seededPlans = samplePlans
        if phase == "underway" || phase == "arrival" {
            seededPlans.insert(
                CrewPlan(
                    uid: "preview-self",
                    itemID: "00000000-0000-0000-0000-000000000042",
                    itemName: "開発",
                    itemStyle: TileStyle.midnight.rawValue,
                    itemSymbol: TileSymbol.phoenix.rawValue,
                    intention: "並走ルームの動きを仕上げる",
                    preparedAt: preparedAt.addingTimeInterval(-8),
                    recall: nil,
                    recordedAt: nil
                ),
                at: 0
            )
        }
        plans = seededPlans
    }
    #endif
}

enum CrewSessionError: LocalizedError {
    case emptyIntention
    case recallTooShort

    var errorDescription: String? {
        switch self {
        case .emptyIntention:
            LF.text("Write what you will do before getting ready.")
        case .recallTooShort:
            LF.text("Write at least 20 characters before finishing the voyage log.")
        }
    }
}
