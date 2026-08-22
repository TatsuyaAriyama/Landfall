import Combine
import FirebaseAuth
import FirebaseFirestore
import Foundation
import SwiftData

/// SwiftData ↔ Firestore の同期。
/// ローカル(SwiftData)が常に真実の情報源。Firestore は「サインイン中のバックアップ/端末間コピー」。
/// v1.1: リアルタイムのスナップショットリスナー＋updatedAtによるLast-Write-Winsで、
/// 追加だけでなく「編集」「削除」も端末間に伝わるようにした。同期に失敗してもローカル利用は継続できる。
///
/// 注意: 旧版の表紙写真(StudyItem.photoData)は同期対象外で、現在のUIでも使用しない。
/// 既知の制約: 両端末がオフライン中に同一記録を編集した競合、片方がオフライン中に行われた削除は、
/// 確実には反映されない場合がある(タイムスタンプ順の解決＋トゥームストーン無しのため)。
@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()
    private init() {}

    /// アカウントの記録をこの端末へ初めて取り込んでいる間だけ true。
    /// 取り込み前の空っぽの一覧を「まだ何も無い」と見せると、利用者が同じ作業項目を
    /// もう一度作ってしまい、それがそのまま重複になる。待っていることを伝えるための印。
    @Published private(set) var isRestoringAccountData = false

    private var db: Firestore { Firestore.firestore() }
    private var uid: String? { Auth.auth().currentUser?.uid }

    private var listeners: [ListenerRegistration] = []
    private var gameDataPreparation: Task<Void, Never>?
    private var gameDataPreparationUID: String?
    private var reconciliation: Task<Void, Never>?
    private var reconciliationUID: String?

    // MARK: - Push / delete (fire-and-forget)

    func push(_ item: StudyItem) {
        guard let uid, let dto = Self.validatedItemDTO(from: item) else { return }
        item.updatedAt = dto.updatedAt ?? item.updatedAt
        try? itemsCollection(uid).document(item.uuid.uuidString).setData(from: dto)
    }

    func delete(_ item: StudyItem) {
        guard let uid else { return }
        itemsCollection(uid).document(item.uuid.uuidString).delete()
    }

    func push(_ session: StudySession) {
        guard let uid, let dto = Self.validatedSessionDTO(from: session) else { return }
        session.updatedAt = dto.updatedAt ?? session.updatedAt
        try? sessionsCollection(uid).document(session.uuid.uuidString).setData(from: dto)
    }

    func delete(_ session: StudySession) {
        guard let uid else { return }
        sessionsCollection(uid).document(session.uuid.uuidString).delete()
    }

    func push(_ day: StudyDay) {
        guard let uid, let dto = Self.validatedDayDTO(from: day) else { return }
        day.updatedAt = dto.updatedAt ?? day.updatedAt
        try? daysCollection(uid).document(Self.dayDocID(day.date)).setData(from: dto)
    }

    func deleteDay(_ date: Date) {
        guard let uid else { return }
        daysCollection(uid).document(Self.dayDocID(date)).delete()
    }

    /// ローカル保存に成功した作業記録を、バックアップ・共有月間記録・Widget・
    /// 通知へ一度だけ反映する。記録画面ごとに同じ後処理を持たせない。
    func publishPersistedSessionChanges(
        _ sessions: [StudySession],
        insertedDays: [StudyDay] = [],
        context: ModelContext
    ) {
        guard !sessions.isEmpty || !insertedDays.isEmpty else { return }
        sessions.forEach(push)
        insertedDays.forEach(push)
        PublicHarborService.shared.publishCurrentMonth(context: context)
        WidgetBridge.refresh(context: context)
        let recordedToday = StudyDayStore.recordedToday(context: context)
        Task { await NotificationService.reschedule(recordedToday: recordedToday) }
    }

    func push(_ dest: Destination) {
        guard let uid else { return }
        // 目標は排他。Webで作られた旧目標も、iOSから保存して消さない。
        let steps = dest.steps.isEmpty
            ? nil
            : dest.steps.prefix(Destination.maxSteps).map {
                DestinationStepDTO(
                    id: $0.id,
                    name: $0.name,
                    scheduledAt: $0.scheduledAt,
                    doneAt: $0.doneAt
                )
            }
        let dto = DestinationWriteDTO(
            name: dest.name,
            itemUUID: dest.itemUUID,
            targetMinutes: dest.steps.isEmpty ? dest.targetMinutes : nil,
            targetDate: dest.steps.isEmpty ? dest.targetDate : nil,
            targetHasTime: dest.steps.isEmpty && dest.targetDate != nil ? dest.targetHasTime : nil,
            manual: dest.steps.isEmpty && dest.manual ? true : nil,
            manualDone: dest.steps.isEmpty && dest.manualDone ? true : nil,
            steps: steps,
            createdAt: dest.createdAt,
            achievedAt: dest.achievedAt,
            updatedAt: Date()
        )
        try? destinationsCollection(uid).document(dest.uuid.uuidString).setData(from: dto)
    }

    func delete(_ dest: Destination) {
        guard let uid else { return }
        destinationsCollection(uid).document(dest.uuid.uuidString).delete()
    }

    // MARK: - 同期の開始/停止

    /// サインイン直後と前景復帰で呼ぶ。受信(リスナー)を張ってから、この端末のローカル記録を
    /// アカウントの記録と突き合わせる。多重呼び出しに耐える。
    func performInitialSync(context: ModelContext) async {
        guard let currentUID = uid else { return }
        // 取り込みが要る端末では、最初の一瞬から「取り込み中」を立てておく。
        if needsReconciliation(uid: currentUID) { isRestoringAccountData = true }
        await prepareAccountGameData(for: currentUID)
        guard uid == currentUID else { return }
        // 購読より先に突き合わせる。「アカウントに今なにがあるか」を読む前に受信も送信も
        // 始めてしまうと、同じ作業項目が一瞬でも二重に並び、送信すればそのまま複製になる。
        // 既存の prepareAccountGameData と同じく、ここもサーバー応答を待つ。
        await reconcileWithAccount(uid: currentUID, context: context)
        guard uid == currentUID else { return }
        startListening(context: context)
    }

    /// サインアウト時に呼ぶ。リスナーを外す。
    func stopSync() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        gameDataPreparation?.cancel()
        gameDataPreparation = nil
        gameDataPreparationUID = nil
        reconciliation?.cancel()
        reconciliation = nil
        reconciliationUID = nil
        isRestoringAccountData = false
    }

    // MARK: - Player card / Home Island

    /// Saves the private, account-owned copy before public harbor member cards
    /// are updated. A durable pending bit prevents a failed/offline write from
    /// being replaced by an older server copy at the next launch.
    func pushPlayerProfile() async {
        guard let uid else { return }
        let now = max(PlayerProfile.updatedAt, Date())
        if PlayerProfile.updatedAt == .distantPast {
            PlayerProfile.save(
                name: PlayerProfile.name,
                styleToken: PlayerProfile.styleToken,
                symbolToken: PlayerProfile.symbolToken,
                resolve: PlayerProfile.resolve,
                updatedAt: now
            )
        }
        UserDefaults.standard.set(true, forKey: profilePendingKey(uid))
        // Do not await server acknowledgement: Firestore persists the write
        // locally and replays it after reconnection. Awaiting here would leave
        // the editor's Save button spinning forever while offline.
        let document = profileDocument(uid)
        let payload = profilePayload()
        Task { try? await document.setData(payload, merge: false) }
    }

    /// Slots with a cloud backup today. Mirrors `HomeIslandSlot`
    /// (Views/HomeIsland/HomeIslandSlots.swift): index 1 is the original
    /// island every existing install already has; index 2 is the
    /// Voyage-Pass-gated second one.
    private static let islandSlotIndices = [1, 2]

    /// The account-scoped owner key for one slot, built the same way
    /// `HomeIslandSlot.ownerID(base:)` builds the on-disk identity, so a
    /// pushed snapshot's ownerKey always lines up with exactly one slot's
    /// document. Slot 1 keeps the bare "firebase:<uid>" identity untouched.
    private func islandOwnerKey(uid: String, slot: Int) -> String {
        HomeIslandPersistence.ownerKey(for: HomeIslandSlot(index: slot).ownerID(base: "firebase:\(uid)"))
    }

    /// Accepts a snapshot from either slot and routes it to that slot's own
    /// document. A snapshot whose ownerKey matches neither slot cannot be
    /// attributed safely, so — exactly as before — it is dropped rather than
    /// risking a write under the wrong identity.
    func pushHomeIslandSnapshot(_ snapshot: HomeIslandSnapshot) async {
        guard let uid,
              let slot = Self.islandSlotIndices.first(where: {
                  islandOwnerKey(uid: uid, slot: $0) == snapshot.ownerKey
              })
        else { return }
        UserDefaults.standard.set(true, forKey: islandPendingKey(uid, slot: slot))
        let document = islandDocument(uid, slot: slot)
        let payload = islandPayload(snapshot)
        Task { try? await document.setData(payload, merge: false) }
    }

    private func prepareAccountGameData(for uid: String) async {
        if gameDataPreparationUID == uid, let gameDataPreparation {
            await gameDataPreparation.value
            return
        }

        gameDataPreparation?.cancel()
        gameDataPreparationUID = uid
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.resolveInitialProfile(for: uid)
            guard !Task.isCancelled, self.uid == uid else { return }
            await self.resolveInitialIsland(for: uid)
        }
        gameDataPreparation = task
        await task.value
        if gameDataPreparationUID == uid {
            gameDataPreparation = nil
            gameDataPreparationUID = nil
        }
    }

    private func resolveInitialProfile(for uid: String) async {
        if UserDefaults.standard.bool(forKey: profilePendingKey(uid)) {
            await pushPlayerProfile()
            return
        }
        do {
            let document = try await profileDocument(uid).getDocument(source: .server)
            guard self.uid == uid, !Task.isCancelled else { return }
            if document.exists, let remote = decodeProfile(document.data()) {
                if remote.updatedAt >= PlayerProfile.updatedAt {
                    applyProfile(remote)
                } else {
                    await pushPlayerProfile()
                }
            } else {
                // One-time upgrade migration: the old local-only player card
                // is uploaded only after the server confirms no backup exists.
                await pushPlayerProfile()
            }
        } catch {
            // Never interpret network/auth failure as "missing". The cached
            // card stays usable and a foreground retry will resolve the server.
        }
    }

    /// Runs the same first-run reconcile independently for every slot, so a
    /// stale or missing slot 2 backup can never block — or be blocked by —
    /// slot 1's.
    private func resolveInitialIsland(for uid: String) async {
        for slot in Self.islandSlotIndices {
            guard self.uid == uid, !Task.isCancelled else { return }
            await resolveInitialIsland(for: uid, slot: slot)
        }
    }

    private func resolveInitialIsland(for uid: String, slot: Int) async {
        let ownerKey = islandOwnerKey(uid: uid, slot: slot)
        let local = HomeIslandPersistence.load(ownerKey: ownerKey)
        if UserDefaults.standard.bool(forKey: islandPendingKey(uid, slot: slot)) {
            await pushHomeIslandSnapshot(local)
            return
        }
        do {
            let document = try await islandDocument(uid, slot: slot).getDocument(source: .server)
            guard self.uid == uid, !Task.isCancelled else { return }
            if document.exists, let remote = decodeIsland(document.data(), uid: uid, slot: slot) {
                if remote.updatedAt > local.updatedAt {
                    applyIsland(remote)
                } else if local.updatedAt > remote.updatedAt {
                    await pushHomeIslandSnapshot(local)
                }
            } else {
                // The empty island is also a valid snapshot. Creating the
                // document now makes subsequent devices deterministic.
                await pushHomeIslandSnapshot(local)
            }
        } catch {
            // Keep local authoring available; importantly, do not overwrite a
            // possibly existing remote island when the lookup itself failed.
        }
    }

    private func profilePayload() -> [String: Any] {
        var payload: [String: Any] = [
            "schemaVersion": 1,
            "name": PlayerProfile.name,
            "styleToken": TileStyle.from(PlayerProfile.styleToken).rawValue,
            "symbolToken": TileSymbol.from(PlayerProfile.symbolToken).rawValue,
            "resolve": String(PlayerProfile.resolve.prefix(60)),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if !PlayerProfile.sinceDay.isEmpty {
            payload["sinceDay"] = PlayerProfile.sinceDay
        }
        return payload
    }

    private struct RemoteProfile {
        let name: String
        let styleToken: String
        let symbolToken: String
        let resolve: String
        let sinceDay: String
        let updatedAt: Date
    }

    private func decodeProfile(_ data: [String: Any]?) -> RemoteProfile? {
        guard let data,
              (data["schemaVersion"] as? NSNumber)?.intValue == 1,
              let rawName = data["name"] as? String,
              let rawStyle = data["styleToken"] as? String,
              let style = TileStyle(rawValue: rawStyle),
              let rawSymbol = data["symbolToken"] as? String,
              let symbol = TileSymbol(rawValue: rawSymbol),
              let rawResolve = data["resolve"] as? String,
              let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        else { return nil }
        let since = data["sinceDay"] as? String ?? ""
        return RemoteProfile(
            name: PlayerProfile.normalizedName(rawName),
            styleToken: style.rawValue,
            symbolToken: symbol.rawValue,
            resolve: String(rawResolve.prefix(60)),
            sinceDay: PlayerProfile.sinceDayFormatter.date(from: since) == nil ? "" : since,
            updatedAt: updatedAt
        )
    }

    private func applyProfile(_ remote: RemoteProfile, forceTimestampReconciliation: Bool = false) {
        guard forceTimestampReconciliation || remote.updatedAt >= PlayerProfile.updatedAt else {
            return
        }
        PlayerProfile.save(
            name: remote.name,
            styleToken: remote.styleToken,
            symbolToken: remote.symbolToken,
            resolve: remote.resolve,
            updatedAt: remote.updatedAt
        )
        if remote.sinceDay.isEmpty {
            UserDefaults.standard.removeObject(forKey: PlayerProfile.sinceDayKey)
        } else {
            UserDefaults.standard.set(remote.sinceDay, forKey: PlayerProfile.sinceDayKey)
        }
        Task {
            await PrivateIslandService.shared.publishProfileToJoinedIslands()
            await PublicHarborService.shared.syncProfile()
        }
    }

    /// A stable per-install identity, written onto every island document so
    /// this device can recognise the echo of its own push. Without it, the
    /// server-stamped echo of an older push can land after a newer local edit
    /// and — being "newer" by timestamp — drag already-placed props back to
    /// where they used to stand. That is the teleport players saw whenever
    /// they placed something.
    static let installationID: String = {
        let key = "sync.installationID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }()

    private func islandPayload(_ snapshot: HomeIslandSnapshot) -> [String: Any] {
        let placements: [[String: Any]] = HomeIslandPersistence
            .sanitizedForAccountSync(snapshot.placements)
            .map { placement in
                [
                    "id": placement.id.uuidString,
                    "assetID": placement.assetID,
                    "x": Double(placement.transform.x),
                    "z": Double(placement.transform.z),
                    "yaw": Double(placement.transform.yaw),
                    "scale": Double(placement.transform.scale),
                ]
            }
        return [
            "schemaVersion": 1,
            "placements": placements,
            "updatedAt": FieldValue.serverTimestamp(),
            "origin": Self.installationID,
        ]
    }

    private func decodeIsland(_ data: [String: Any]?, uid: String, slot: Int) -> HomeIslandSnapshot? {
        guard let data,
              (data["schemaVersion"] as? NSNumber)?.intValue == 1,
              let rawPlacements = data["placements"] as? [[String: Any]],
              rawPlacements.count <= HomeIslandMetrics.maximumPlacements,
              let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        else { return nil }

        let placements = rawPlacements.compactMap { raw -> HomeIslandPlacement? in
            guard let idValue = raw["id"] as? String,
                  let id = UUID(uuidString: idValue),
                  let assetID = raw["assetID"] as? String,
                  let x = (raw["x"] as? NSNumber)?.floatValue,
                  let z = (raw["z"] as? NSNumber)?.floatValue,
                  let yaw = (raw["yaw"] as? NSNumber)?.floatValue,
                  let scale = (raw["scale"] as? NSNumber)?.floatValue
            else { return nil }
            return HomeIslandPlacement(
                id: id,
                assetID: assetID,
                transform: HomeIslandTransform(x: x, z: z, yaw: yaw, scale: scale)
            )
        }
        return HomeIslandSnapshot(
            ownerKey: islandOwnerKey(uid: uid, slot: slot),
            updatedAt: updatedAt,
            placements: HomeIslandPersistence.sanitizedForAccountSync(placements)
        )
    }

    private func applyIsland(_ remote: HomeIslandSnapshot) {
        let local = HomeIslandPersistence.load(ownerKey: remote.ownerKey)
        guard remote.updatedAt > local.updatedAt else { return }
        persistIsland(remote)
    }

    private func persistIsland(_ remote: HomeIslandSnapshot) {
        do {
            try HomeIslandPersistence.save(snapshot: remote)
            NotificationCenter.default.post(name: .homeIslandDidChange, object: remote.ownerKey)
        } catch {
            // Keep the previous verified primary/recovery pair intact.
        }
    }

    private func profilePendingKey(_ uid: String) -> String {
        "accountGameData.profilePending.\(uid)"
    }

    private func islandPendingKey(_ uid: String, slot: Int) -> String {
        // Slot 1 keeps the exact key existing installs already hold a value
        // under; changing it would strand that flag mid-flight and briefly
        // reintroduce the stale-echo teleport this flag exists to prevent.
        slot == 1 ? "accountGameData.islandPending.\(uid)" : "accountGameData.islandPending.\(uid).slot\(slot)"
    }

    // MARK: - アカウントとの突き合わせ(同じ実体を二重に作らない)

    /// v1.1 までは「この uid で初回なら、ローカルを全件 push」だった。
    /// そのため、サインインせずに使っていた端末や、まだ同期の届いていない端末で
    /// 同じ作業項目を持ったままログインすると、同じ項目がもう一組アカウントへ増え、
    /// 全端末で作業項目が丸ごと複製されてしまった。
    ///
    /// ここでは順に、
    /// 1. アカウントの現状を**必ず読んでから**判断する(読めなければ何も送らない)、
    /// 2. 同じ実体(同名の作業項目・同じ記録)は、アカウント側のIDへ寄せる、
    /// 3. 本当に手元にしか無い記録だけを送る、
    /// 4. すでに複製されてしまったアカウントは、一度だけ畳んで元に戻す。
    ///
    /// どの端末が実行しても残す側の選び方は同じなので、実機でもシミュレータでも
    /// 同時に走って構わない(同じ結果へ収束する)。
    private func reconcileWithAccount(uid: String, context: ModelContext) async {
        guard needsReconciliation(uid: uid) else {
            isRestoringAccountData = false
            return
        }
        if reconciliationUID == uid, let reconciliation {
            await reconciliation.value
            return
        }
        reconciliation?.cancel()
        reconciliationUID = uid
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRestoringAccountData = false }
            // ここだけはサーバーの現物を読む。手元のキャッシュを信じて送ると、
            // 「アカウントには既にある」ことを見落として複製を作ってしまう。
            guard let snapshot = await self.fetchAccountSnapshot(uid: uid),
                  !Task.isCancelled,
                  self.uid == uid
            else { return }

            let defaults = UserDefaults.standard
            if !defaults.bool(forKey: Self.initialUploadKey(uid)) {
                self.uploadLocalData(mergingWith: snapshot, context: context)
                defaults.set(true, forKey: Self.initialUploadKey(uid))
            }
            guard !Task.isCancelled, self.uid == uid else { return }
            if !defaults.bool(forKey: Self.duplicateRepairKey(uid)) {
                if await self.collapseDuplicateItems(in: snapshot, uid: uid, context: context) {
                    defaults.set(true, forKey: Self.duplicateRepairKey(uid))
                }
            }
        }
        reconciliation = task
        await task.value
        if reconciliationUID == uid {
            reconciliation = nil
            reconciliationUID = nil
        }
    }

    private func needsReconciliation(uid: String) -> Bool {
        let defaults = UserDefaults.standard
        return !defaults.bool(forKey: Self.initialUploadKey(uid))
            || !defaults.bool(forKey: Self.duplicateRepairKey(uid))
    }

    /// v1.1 と同じキー。既にアップロード済みの端末を、もう一度アップロードさせない。
    private static func initialUploadKey(_ uid: String) -> String { "didInitialPush_\(uid)" }
    private static func duplicateRepairKey(_ uid: String) -> String { "didCollapseDuplicateItems.v1.\(uid)" }

    /// このアカウント自身の記録。件数は本人のデータ量にしか比例しない
    /// (購読も同じ範囲を読むため、読み取りが利用者数に比例することはない)。
    private struct AccountSnapshot {
        var items: [String: ItemDTO] = [:]
        var sessions: [String: SessionDTO] = [:]
        var days: [String: DayDTO] = [:]
        var destinations: [String: DestinationDTO] = [:]
    }

    private func fetchAccountSnapshot(uid: String) async -> AccountSnapshot? {
        do {
            async let items = itemsCollection(uid).getDocuments(source: .server)
            async let sessions = sessionsCollection(uid).getDocuments(source: .server)
            async let days = daysCollection(uid).getDocuments(source: .server)
            async let destinations = destinationsCollection(uid).getDocuments(source: .server)
            var snapshot = AccountSnapshot()
            for document in try await items.documents {
                if UUID(uuidString: document.documentID) != nil,
                   let dto = try? document.data(as: ItemDTO.self),
                   let valid = Self.validated(dto) {
                    snapshot.items[document.documentID] = valid
                }
            }
            for document in try await sessions.documents {
                if UUID(uuidString: document.documentID) != nil,
                   let dto = try? document.data(as: SessionDTO.self),
                   let valid = Self.validated(dto) {
                    snapshot.sessions[document.documentID] = valid
                }
            }
            for document in try await days.documents {
                if Self.dateFromDayDocID(document.documentID) != nil,
                   let dto = try? document.data(as: DayDTO.self),
                   let valid = Self.validated(dto) {
                    snapshot.days[document.documentID] = valid
                }
            }
            for document in try await destinations.documents {
                if let dto = try? document.data(as: DestinationDTO.self) { snapshot.destinations[document.documentID] = dto }
            }
            return snapshot
        } catch {
            // 圏外・一時的な失敗を「アカウントは空」と読み違えない。次の前景復帰で出直す。
            return nil
        }
    }

    // MARK: 初回アップロード(手元にしか無い記録だけを送る)

    private func uploadLocalData(mergingWith snapshot: AccountSnapshot, context: ModelContext) {
        // 目的地を先に寄せてから項目を寄せる。逆にすると、付け替えで送り直した目的地が
        // 古いIDのまま書類として残り、それ自体が重複になる。
        mergeLocalDestinations(with: snapshot, context: context)
        let relinked = mergeLocalItems(with: snapshot, context: context)
        mergeLocalSessions(with: snapshot, relinked: relinked, context: context)
        mergeLocalDays(with: snapshot, context: context)
        try? context.save()
    }

    /// 戻り値は、畳んだ結果として繋ぎ先が変わった記録。アカウントに既にある記録でも、
    /// この分だけは送り直さないと、他端末で行き先を失う。
    @discardableResult
    private func mergeLocalItems(with snapshot: AccountSnapshot, context: ModelContext) -> Set<UUID> {
        let locals = (try? context.fetch(FetchDescriptor<StudyItem>())) ?? []
        guard !locals.isEmpty else { return [] }

        let plan = AccountMergePlan.decisions(
            local: locals.map {
                AccountMergePlan.Row(
                    key: AccountMergePlan.nameKey($0.name),
                    id: $0.uuid.uuidString,
                    createdAt: $0.createdAt
                )
            },
            remote: snapshot.items.map {
                AccountMergePlan.Row(
                    key: AccountMergePlan.nameKey($0.value.name),
                    id: $0.key,
                    createdAt: $0.value.createdAt
                )
            },
            accountIDs: Set(snapshot.items.keys)
        )

        var relinked: Set<UUID> = []
        var localByID: [String: StudyItem] = [:]
        for item in locals {
            let id = item.uuid.uuidString
            switch plan[id] ?? .push {
            case .keep:
                localByID[id] = item
            case .adopt(let remoteID):
                // 同じ作業項目なので、アカウント側のIDへ寄せる。新しい書類は作らない。
                adopt(remoteID, for: item, context: context)
                localByID[remoteID] = item
                if item.updatedAt > (snapshot.items[remoteID]?.updatedAt ?? .distantPast) { push(item) }
            case .absorb(let remoteID):
                // アカウント側の同じ項目を、手元の別の行が既に受け持っている。重複を畳む。
                if let keeper = localByID[remoteID] {
                    relinked.formUnion(absorb(item, into: keeper, context: context))
                } else {
                    push(item)
                }
            case .push:
                push(item)  // 本当に手元にしか無い作業項目
            }
        }
        return relinked
    }

    private func mergeLocalDestinations(with snapshot: AccountSnapshot, context: ModelContext) {
        let locals = (try? context.fetch(FetchDescriptor<Destination>())) ?? []
        guard !locals.isEmpty else { return }

        let plan = AccountMergePlan.decisions(
            local: locals.map {
                AccountMergePlan.Row(
                    key: AccountMergePlan.nameKey($0.name),
                    id: $0.uuid.uuidString,
                    createdAt: $0.createdAt
                )
            },
            remote: snapshot.destinations.map {
                AccountMergePlan.Row(
                    key: AccountMergePlan.nameKey($0.value.name),
                    id: $0.key,
                    createdAt: $0.value.createdAt
                )
            },
            accountIDs: Set(snapshot.destinations.keys)
        )

        for dest in locals {
            // 目的地は畳まない。同名でも別の目標なので、行き場を失わせずに送る。
            guard case .adopt(let remoteID) = plan[dest.uuid.uuidString] ?? .push,
                  let remoteUUID = UUID(uuidString: remoteID)
            else {
                if plan[dest.uuid.uuidString] != .keep { push(dest) }
                continue
            }
            dest.uuid = remoteUUID
            if dest.updatedAt > (snapshot.destinations[remoteID]?.updatedAt ?? .distantPast) { push(dest) }
        }
    }

    private func mergeLocalSessions(
        with snapshot: AccountSnapshot, relinked: Set<UUID>, context: ModelContext
    ) {
        let locals = (try? context.fetch(FetchDescriptor<StudySession>())) ?? []
        guard !locals.isEmpty else { return }

        let plan = AccountMergePlan.decisions(
            local: locals.map {
                AccountMergePlan.Row(
                    key: AccountMergePlan.sessionKey(
                        date: $0.date, minutes: $0.minutes, extraSeconds: $0.extraSeconds,
                        note: $0.note, itemUUID: $0.item?.uuid.uuidString ?? $0.pendingItemUUID
                    ),
                    id: $0.uuid.uuidString,
                    createdAt: $0.date
                )
            },
            remote: snapshot.sessions.map {
                AccountMergePlan.Row(
                    key: AccountMergePlan.sessionKey(
                        date: $0.value.date, minutes: $0.value.minutes,
                        extraSeconds: $0.value.extraSeconds ?? 0,
                        note: $0.value.note, itemUUID: $0.value.itemUUID
                    ),
                    id: $0.key,
                    createdAt: $0.value.date
                )
            },
            accountIDs: Set(snapshot.sessions.keys)
        )

        for session in locals {
            switch plan[session.uuid.uuidString] ?? .push {
            case .keep:
                // 繋ぎ先を移した記録だけは、アカウント側にも新しい行き先を伝える。
                if relinked.contains(session.uuid) { push(session) }
            case .adopt(let remoteID):
                // 同じ記録がアカウントにもある。IDを寄せて1件に収める。
                if let remoteUUID = UUID(uuidString: remoteID) { session.uuid = remoteUUID }
            case .absorb, .push:
                // 記録は決して畳まない。取り違えて消すより、1件多く残す方を選ぶ。
                push(session)
            }
        }
    }

    private func mergeLocalDays(with snapshot: AccountSnapshot, context: ModelContext) {
        // 日の書類IDは日付そのものなので重複しない。航海誌が消えないよう、
        // アカウント側が新しいときは送らずに任せる。
        for day in (try? context.fetch(FetchDescriptor<StudyDay>())) ?? [] {
            let id = Self.dayDocID(day.date)
            guard let remote = snapshot.days[id] else {
                push(day)
                continue
            }
            if day.updatedAt > (remote.updatedAt ?? .distantPast) { push(day) }
        }
    }

    /// 作業項目のIDをアカウント側へ寄せる。IDを文字列で覚えている場所も一緒に付け替える。
    private func adopt(_ remoteID: String, for item: StudyItem, context: ModelContext) {
        guard let remoteUUID = UUID(uuidString: remoteID) else { return }
        let previous = item.uuid.uuidString
        item.uuid = remoteUUID
        repointItemReferences(from: previous, to: remoteID, context: context)
    }

    /// 手元の重複した作業項目を1つに畳む。記録は必ず残す側へ引き継ぐ。
    @discardableResult
    private func absorb(_ duplicate: StudyItem, into keeper: StudyItem, context: ModelContext) -> Set<UUID> {
        let previous = duplicate.uuid.uuidString
        var moved: Set<UUID> = []
        for session in Array(duplicate.sessions) {
            session.item = keeper
            session.pendingItemUUID = nil
            session.updatedAt = Date()
            moved.insert(session.uuid)
        }
        repointItemReferences(from: previous, to: keeper.uuid.uuidString, context: context)
        // 送信済みだったとしても取り下げる(書類が無ければ何も起きない)。
        delete(duplicate)
        context.delete(duplicate)
        return moved
    }

    /// 作業項目のIDを文字列で持っている場所(記録の繋ぎ先・目的地・計測中のタイマー)を付け替える。
    private func repointItemReferences(from previous: String, to newID: String, context: ModelContext) {
        for session in (try? context.fetch(FetchDescriptor<StudySession>())) ?? []
        where session.pendingItemUUID == previous {
            session.pendingItemUUID = newID
        }
        for dest in (try? context.fetch(FetchDescriptor<Destination>())) ?? []
        where dest.itemUUID == previous {
            dest.itemUUID = newID
            dest.updatedAt = Date()
            push(dest)
        }
        if StudyTimer.defaults.string(forKey: StudyTimer.itemKey) == previous {
            StudyTimer.defaults.set(newID, forKey: StudyTimer.itemKey)
        }
    }

    // MARK: 既にできてしまった複製を畳む

    /// 同じ姿(同名・同じ配色・同じ印)の作業項目がアカウントに複数あるとき、
    /// 最初に作られた1件へ記録をすべて寄せ、残りを取り下げる。
    /// 記録(セッション)自体は1件も消さない。全端末で同じ結果になる。
    /// 完了できたときだけ true(圏外などで書き切れなければ次回やり直す)。
    private func collapseDuplicateItems(
        in snapshot: AccountSnapshot, uid: String, context: ModelContext
    ) async -> Bool {
        // 同じ姿(同名・同じ配色・同じ印)の項目だけを同一視する。名前だけ同じで
        // 見た目の違う項目は、利用者が意図して分けたものとして触らない。
        let duplicates = AccountMergePlan.duplicates(
            in: snapshot.items.map {
                AccountMergePlan.Row(
                    key: "\(AccountMergePlan.nameKey($0.value.name))|\($0.value.styleToken)|\($0.value.symbolToken)",
                    id: $0.key,
                    createdAt: $0.value.createdAt
                )
            }
        )
        guard !duplicates.isEmpty else { return true }

        // 1. アカウント側の記録と目的地を、残す側の項目へ繋ぎ替える。
        var writes: [(document: DocumentReference, payload: [String: Any]?)] = []
        for (id, dto) in snapshot.sessions {
            guard let itemUUID = dto.itemUUID, let keeper = duplicates[itemUUID] else { continue }
            writes.append((sessionsCollection(uid).document(id), ["itemUUID": keeper, "updatedAt": Date()]))
        }
        for (id, dto) in snapshot.destinations {
            guard let itemUUID = dto.itemUUID, let keeper = duplicates[itemUUID] else { continue }
            writes.append((destinationsCollection(uid).document(id), ["itemUUID": keeper, "updatedAt": Date()]))
        }
        guard await commitInChunks(writes) else { return false }
        guard self.uid == uid, !Task.isCancelled else { return false }

        // 2. 手元も同じ形にする。先に記録を移すので、項目を消しても記録は巻き込まれない。
        for (duplicateID, keeperID) in duplicates {
            guard let duplicate = fetchItem(duplicateID, context) else { continue }
            let keeper = fetchItem(keeperID, context)
            for session in Array(duplicate.sessions) {
                session.item = keeper
                session.pendingItemUUID = keeper == nil ? keeperID : nil
                session.updatedAt = Date()
            }
            repointItemReferences(from: duplicateID, to: keeperID, context: context)
            context.delete(duplicate)
        }
        try? context.save()

        // 3. 繋ぎ替えが済んだので、複製された作業項目だけを取り下げる。
        let deletions = duplicates.keys.map {
            (document: itemsCollection(uid).document($0), payload: [String: Any]?.none)
        }
        return await commitInChunks(deletions)
    }

    /// Firestore の1バッチ上限(500)に余裕を持たせて書き込む。payload が nil なら削除。
    /// 1件でも失敗したら false を返し、呼び出し側はやり直せる。
    private func commitInChunks(
        _ writes: [(document: DocumentReference, payload: [String: Any]?)]
    ) async -> Bool {
        for start in stride(from: 0, to: writes.count, by: 400) {
            let batch = db.batch()
            for write in writes[start..<min(start + 400, writes.count)] {
                if let payload = write.payload {
                    batch.setData(payload, forDocument: write.document, merge: true)
                } else {
                    batch.deleteDocument(write.document)
                }
            }
            do {
                try await batch.commit()
            } catch {
                return false
            }
        }
        return true
    }

    private func startListening(context: ModelContext) {
        guard let uid, listeners.isEmpty else { return }
        listeners.append(profileDocument(uid).addSnapshotListener(includeMetadataChanges: true) {
            [weak self] snapshot, _ in
            Task { @MainActor [weak self] in
                guard let self,
                      self.uid == uid,
                      let snapshot,
                      snapshot.exists,
                      !snapshot.metadata.hasPendingWrites,
                      let remote = self.decodeProfile(snapshot.data())
                else { return }
                let wasPending = UserDefaults.standard.bool(
                    forKey: self.profilePendingKey(uid)
                )
                UserDefaults.standard.set(false, forKey: self.profilePendingKey(uid))
                let matchesLocal = remote.name == PlayerProfile.name
                    && remote.styleToken == TileStyle.from(PlayerProfile.styleToken).rawValue
                    && remote.symbolToken == TileSymbol.from(PlayerProfile.symbolToken).rawValue
                    && remote.resolve == String(PlayerProfile.resolve.prefix(60))
                    && remote.sinceDay == PlayerProfile.sinceDay
                self.applyProfile(
                    remote,
                    forceTimestampReconciliation: wasPending && matchesLocal
                )
            }
        })
        // Each slot gets its own listener, its own pending flag and its own
        // echo check: a slot 2 write must never be mistaken for slot 1's echo
        // (or vice versa) just because both happen to land around the same time.
        for slot in Self.islandSlotIndices {
            listeners.append(islandDocument(uid, slot: slot).addSnapshotListener(includeMetadataChanges: true) {
                [weak self] snapshot, _ in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.uid == uid,
                          let snapshot,
                          snapshot.exists,
                          !snapshot.metadata.hasPendingWrites,
                          let remote = self.decodeIsland(snapshot.data(), uid: uid, slot: slot)
                    else { return }
                    UserDefaults.standard.set(false, forKey: self.islandPendingKey(uid, slot: slot))
                    let local = HomeIslandPersistence.load(ownerKey: remote.ownerKey)
                    guard snapshot.data()?["origin"] as? String != Self.installationID else {
                        // Our own write coming back. The only thing worth taking
                        // from it is the server timestamp, and only while the saved
                        // layout still matches what we sent — an echo that arrives
                        // after a newer edit is stale by definition.
                        if remote.placements == local.placements {
                            self.persistIsland(remote)
                        }
                        return
                    }
                    self.applyIsland(remote)
                }
            })
        }
        listeners.append(itemsCollection(uid).addSnapshotListener { [weak self] snap, _ in
            guard let self, let snap else { return }
            MainActor.assumeIsolated { self.applyItems(snap, context: context) }
        })
        listeners.append(sessionsCollection(uid).addSnapshotListener { [weak self] snap, _ in
            guard let self, let snap else { return }
            MainActor.assumeIsolated { self.applySessions(snap, context: context) }
        })
        listeners.append(daysCollection(uid).addSnapshotListener { [weak self] snap, _ in
            guard let self, let snap else { return }
            MainActor.assumeIsolated { self.applyDays(snap, context: context) }
        })
        listeners.append(destinationsCollection(uid).addSnapshotListener { [weak self] snap, _ in
            guard let self, let snap else { return }
            MainActor.assumeIsolated { self.applyDestinations(snap, context: context) }
        })
    }

    // MARK: - リモート変更をローカルへ反映(Last-Write-Wins)

    private func applyItems(_ snap: QuerySnapshot, context: ModelContext) {
        var changed = false
        for change in snap.documentChanges {
            let id = change.document.documentID
            // 書類IDがUUIDでなければ、手元の行と一対一に結べない。取り込むと
            // 起動のたびに同じ項目が増え続けるので、触らずに見送る。
            guard UUID(uuidString: id) != nil else { continue }
            switch change.type {
            case .added, .modified:
                guard let decoded = try? change.document.data(as: ItemDTO.self),
                      let dto = Self.validated(decoded)
                else { continue }
                let remoteAt = dto.updatedAt ?? .distantPast
                if let existing = fetchItem(id, context) {
                    if remoteAt > existing.updatedAt {
                        existing.name = dto.name; existing.styleToken = dto.styleToken
                        existing.symbolToken = dto.symbolToken; existing.sortOrder = dto.sortOrder
                        existing.createdAt = dto.createdAt; existing.updatedAt = remoteAt
                        changed = true
                    }
                } else {
                    let item = StudyItem(name: dto.name, styleToken: dto.styleToken,
                                         symbolToken: dto.symbolToken, sortOrder: dto.sortOrder, createdAt: dto.createdAt)
                    if let u = UUID(uuidString: id) { item.uuid = u }
                    item.updatedAt = remoteAt
                    context.insert(item); changed = true
                }
            case .removed:
                // 別端末から項目が削除された場合も、その項目を指す端末ローカルの
                // タイマーだけが走り続けないよう同時に畳む。
                StudyTimer.clear(ifMatching: id)
                if let existing = fetchItem(id, context) { context.delete(existing); changed = true }
            }
        }
        if relinkPendingSessions(context) { changed = true }
        if changed { try? context.save() }
    }

    /// 項目より先に届いてしまい、宙に浮いた記録を繋ぎ直す。
    /// 項目が手元へ揃った後に呼ぶ。
    @discardableResult
    private func relinkPendingSessions(_ context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<StudySession>(
            predicate: #Predicate { $0.pendingItemUUID != nil }
        )
        guard let orphans = try? context.fetch(descriptor), !orphans.isEmpty else { return false }
        var changed = false
        for session in orphans {
            guard let pending = session.pendingItemUUID else { continue }
            guard let item = fetchItem(pending, context) else { continue }
            session.item = item
            session.pendingItemUUID = nil
            changed = true
        }
        return changed
    }

    private func applySessions(_ snap: QuerySnapshot, context: ModelContext) {
        var changed = false
        for change in snap.documentChanges {
            let id = change.document.documentID
            guard UUID(uuidString: id) != nil else { continue }
            switch change.type {
            case .added, .modified:
                guard let decoded = try? change.document.data(as: SessionDTO.self),
                      let dto = Self.validated(decoded)
                else { continue }
                let remoteAt = dto.updatedAt ?? .distantPast
                let item = dto.itemUUID.flatMap { fetchItem($0, context) }
                // 作業項目がまだ届いていなければ、繋ぎ先を覚えておく。
                let pending = item == nil ? dto.itemUUID : nil
                if let existing = fetchSession(id, context) {
                    if remoteAt > existing.updatedAt {
                        existing.date = dto.date; existing.minutes = dto.minutes
                        existing.extraSeconds = dto.extraSeconds ?? 0
                        existing.note = dto.note; existing.item = item
                        existing.pendingItemUUID = pending
                        existing.updatedAt = remoteAt
                        changed = true
                    } else if existing.item == nil, dto.itemUUID != nil {
                        // 更新時刻が進んでいなくても、項目との紐付けが切れたままの
                        // 記録は繋ぎ直す。これを飛ばすと、購読の到着順で一度でも
                        // 外れた記録が永久に「0分」の項目として残る。
                        existing.item = item
                        existing.pendingItemUUID = pending
                        changed = true
                    }
                } else {
                    let session = StudySession(
                        date: dto.date,
                        minutes: dto.minutes,
                        extraSeconds: dto.extraSeconds ?? 0,
                        note: dto.note,
                        item: item
                    )
                    if let u = UUID(uuidString: id) { session.uuid = u }
                    session.pendingItemUUID = pending
                    session.updatedAt = remoteAt
                    context.insert(session); changed = true
                }
            case .removed:
                if let existing = fetchSession(id, context) { context.delete(existing); changed = true }
            }
        }
        if changed {
            try? context.save()
            // A session created or edited on another device must also refresh the public
            // harbor snapshot. Otherwise only the device that recorded it would publish it.
            PublicHarborService.shared.publishCurrentMonth(context: context)
        }
    }

    private func applyDays(_ snap: QuerySnapshot, context: ModelContext) {
        var changed = false
        for change in snap.documentChanges {
            let id = change.document.documentID
            switch change.type {
            case .added, .modified:
                guard Self.dateFromDayDocID(id) != nil,
                      let decoded = try? change.document.data(as: DayDTO.self),
                      let dto = Self.validated(decoded)
                else { continue }
                let remoteAt = dto.updatedAt ?? .distantPast
                if let existing = fetchDay(dto.date, context) {
                    if remoteAt > existing.updatedAt { existing.note = dto.note; existing.updatedAt = remoteAt; changed = true }
                } else {
                    let day = StudyDay(date: dto.date, note: dto.note)
                    day.updatedAt = remoteAt
                    context.insert(day); changed = true
                }
            case .removed:
                if let date = Self.dateFromDayDocID(id), let existing = fetchDay(date, context) {
                    context.delete(existing); changed = true
                }
            }
        }
        if changed { try? context.save() }
    }

    private func applyDestinations(_ snap: QuerySnapshot, context: ModelContext) {
        var changed = false
        for change in snap.documentChanges {
            let id = change.document.documentID
            guard UUID(uuidString: id) != nil else { continue }
            switch change.type {
            case .added, .modified:
                guard let dto = try? change.document.data(as: DestinationDTO.self) else { continue }
                let remoteAt = dto.updatedAt ?? .distantPast
                let steps = (dto.steps ?? []).prefix(Destination.maxSteps).map {
                    DestinationStep(
                        id: $0.id,
                        name: $0.name,
                        scheduledAt: $0.scheduledAt,
                        doneAt: $0.doneAt
                    )
                }
                if let existing = fetchDestination(id, context) {
                    if remoteAt > existing.updatedAt {
                        existing.name = dto.name; existing.createdAt = dto.createdAt
                        existing.targetDate = dto.targetDate; existing.achievedAt = dto.achievedAt
                        existing.targetHasTime = dto.targetHasTime == true
                        existing.itemUUID = dto.itemUUID
                        existing.targetMinutes = dto.targetMinutes
                        existing.manual = dto.manual == true
                        existing.manualDone = dto.manualDone == true
                        existing.steps = steps; existing.updatedAt = remoteAt
                        changed = true
                    }
                } else {
                    let dest = Destination(
                        name: dto.name,
                        createdAt: dto.createdAt,
                        targetDate: dto.targetDate,
                        targetHasTime: dto.targetHasTime == true,
                        itemUUID: dto.itemUUID,
                        targetMinutes: dto.targetMinutes,
                        manual: dto.manual == true,
                        manualDone: dto.manualDone == true,
                        steps: steps
                    )
                    if let u = UUID(uuidString: id) { dest.uuid = u }
                    dest.achievedAt = dto.achievedAt
                    dest.updatedAt = remoteAt
                    context.insert(dest); changed = true
                }
            case .removed:
                if let existing = fetchDestination(id, context) { context.delete(existing); changed = true }
            }
        }
        if changed { try? context.save() }
    }

    private func fetchItem(_ id: String, _ context: ModelContext) -> StudyItem? {
        guard let u = UUID(uuidString: id) else { return nil }
        var d = FetchDescriptor<StudyItem>(predicate: #Predicate { $0.uuid == u }); d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }
    private func fetchSession(_ id: String, _ context: ModelContext) -> StudySession? {
        guard let u = UUID(uuidString: id) else { return nil }
        var d = FetchDescriptor<StudySession>(predicate: #Predicate { $0.uuid == u }); d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }
    private func fetchDay(_ date: Date, _ context: ModelContext) -> StudyDay? {
        let dayStart = Calendar.current.startOfDay(for: date)
        var d = FetchDescriptor<StudyDay>(predicate: #Predicate { $0.date == dayStart }); d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }
    private func fetchDestination(_ id: String, _ context: ModelContext) -> Destination? {
        guard let u = UUID(uuidString: id) else { return nil }
        var d = FetchDescriptor<Destination>(predicate: #Predicate { $0.uuid == u }); d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    // MARK: - アカウント削除時: リモートの記録を全て消す

    func deleteAllRemoteData() async throws {
        guard let uid else { return }
        for collection in [itemsCollection(uid), sessionsCollection(uid), daysCollection(uid), destinationsCollection(uid)] {
            let snapshot = try await collection.getDocuments()
            for doc in snapshot.documents { try await doc.reference.delete() }
        }
    }

    // MARK: - Firestore パス

    private func itemsCollection(_ uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("items")
    }
    private func sessionsCollection(_ uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("sessions")
    }
    private func daysCollection(_ uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("days")
    }
    private func destinationsCollection(_ uid: String) -> CollectionReference {
        db.collection("users").document(uid).collection("destinations")
    }
    private func profileDocument(_ uid: String) -> DocumentReference {
        db.collection("users").document(uid).collection("gameData").document("profile")
    }
    private func islandDocument(_ uid: String, slot: Int) -> DocumentReference {
        db.collection("users").document(uid).collection("gameData").document(Self.islandDocumentName(slot: slot))
    }

    /// Slot 1 is the exact document name every existing install already
    /// backs up to; later slots get their own numbered sibling so a second
    /// island can never collide with — or overwrite — the first.
    private static func islandDocumentName(slot: Int) -> String {
        slot == 1 ? "homeIsland" : "homeIsland\(slot)"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static func dayDocID(_ date: Date) -> String { dayFormatter.string(from: date) }
    private static func dateFromDayDocID(_ id: String) -> Date? { dayFormatter.date(from: id) }

    // MARK: - Private-record validation

    /// Missing `updatedAt` remains readable for v1.0 compatibility. Values written by
    /// current clients are bounded so a poisoned future timestamp cannot win LWW forever.
    private static func validRecordDate(_ date: Date, now: Date = Date()) -> Bool {
        WorkRecordPolicy.isValidRecordDate(date, now: now)
    }

    private static func validUpdatedAt(_ date: Date?, now: Date = Date()) -> Bool {
        WorkRecordPolicy.isValidUpdatedAt(date, now: now)
    }

    private static func validOptionalUUID(_ value: String?) -> Bool {
        guard let value else { return true }
        return UUID(uuidString: value) != nil
    }

    private static func validatedItemDTO(from item: StudyItem) -> ItemDTO? {
        let name = String(
            item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(WorkRecordPolicy.maximumItemNameCharacters)
        )
        guard !name.isEmpty,
              item.styleToken.count <= 32,
              item.symbolToken.count <= 24,
              (-1...100_000).contains(item.sortOrder),
              validRecordDate(item.createdAt)
        else { return nil }
        return ItemDTO(
            name: name,
            styleToken: item.styleToken,
            symbolToken: item.symbolToken,
            sortOrder: item.sortOrder,
            createdAt: item.createdAt,
            updatedAt: Date()
        )
    }

    private static func validatedSessionDTO(from session: StudySession) -> SessionDTO? {
        let itemUUID = session.item?.uuid.uuidString ?? session.pendingItemUUID
        guard WorkRecordPolicy.isValidSession(
            minutes: session.minutes,
            extraSeconds: session.extraSeconds
        ), validRecordDate(session.date),
           validOptionalUUID(itemUUID)
        else { return nil }
        return SessionDTO(
            date: session.date,
            minutes: session.minutes,
            extraSeconds: session.extraSeconds,
            note: WorkRecordPolicy.normalizedNote(session.note),
            // 項目がまだ手元へ届いていない記録も、繋ぎ先を落とさない。
            itemUUID: itemUUID,
            updatedAt: Date()
        )
    }

    private static func validatedDayDTO(from day: StudyDay) -> DayDTO? {
        guard validRecordDate(day.date) else { return nil }
        let trimmed = day.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = (trimmed?.isEmpty ?? true)
            ? nil
            : String(trimmed!.prefix(WorkRecordPolicy.maximumDayNoteCharacters))
        return DayDTO(date: day.date, note: note, updatedAt: Date())
    }

    private static func validated(_ dto: ItemDTO) -> ItemDTO? {
        let name = dto.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name.count <= WorkRecordPolicy.maximumItemNameCharacters,
              !dto.styleToken.isEmpty, dto.styleToken.count <= 32,
              !dto.symbolToken.isEmpty, dto.symbolToken.count <= 24,
              (-1...100_000).contains(dto.sortOrder),
              validRecordDate(dto.createdAt),
              validUpdatedAt(dto.updatedAt)
        else { return nil }
        return dto
    }

    private static func validated(_ dto: SessionDTO) -> SessionDTO? {
        let extraSeconds = dto.extraSeconds ?? 0
        guard WorkRecordPolicy.isValidSession(minutes: dto.minutes, extraSeconds: extraSeconds),
              validRecordDate(dto.date),
              validUpdatedAt(dto.updatedAt),
              (dto.note?.count ?? 0) <= WorkRecordPolicy.maximumSessionNoteCharacters,
              validOptionalUUID(dto.itemUUID)
        else { return nil }
        var clean = dto
        clean.extraSeconds = extraSeconds
        clean.note = WorkRecordPolicy.normalizedNote(dto.note)
        return clean
    }

    private static func validated(_ dto: DayDTO) -> DayDTO? {
        guard validRecordDate(dto.date),
              validUpdatedAt(dto.updatedAt),
              (dto.note?.count ?? 0) <= WorkRecordPolicy.maximumDayNoteCharacters
        else { return nil }
        var clean = dto
        let trimmed = dto.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.note = (trimmed?.isEmpty ?? true) ? nil : trimmed
        return clean
    }
}

// MARK: - Firestore DTO(Codable)
// updatedAt は Optional。v1.0 で書かれた updatedAt を持たない書類も読めるようにする。

private struct ItemDTO: Codable {
    var name: String
    var styleToken: String
    var symbolToken: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date?
}

private struct SessionDTO: Codable {
    var date: Date
    var minutes: Int
    /// 秒の端数。この項目を持たない古い記録・他プラットフォームからは 0 で読む。
    var extraSeconds: Int?
    var note: String?
    var itemUUID: String?
    var updatedAt: Date?
}

private struct DayDTO: Codable {
    var date: Date
    var note: String?
    var updatedAt: Date?
}

/// ステップ1件(Firestore の steps 配列要素 = map)。日時は Timestamp に自動変換。
private struct DestinationStepDTO: Codable {
    var id: String
    var name: String
    var scheduledAt: Date?
    var doneAt: Date?
}

/// Webと共通の目的地シェイプ。旧目標も表示・同期で失わない。
private struct DestinationDTO: Codable {
    var name: String
    var itemUUID: String?
    var targetMinutes: Int?
    var targetDate: Date?
    var targetHasTime: Bool?
    var manual: Bool?
    var manualDone: Bool?
    var steps: [DestinationStepDTO]?
    var createdAt: Date
    var achievedAt: Date?
    var updatedAt: Date?
}

/// 書き込み用。Webと同じシェイプを保つ。
private struct DestinationWriteDTO: Codable {
    var name: String
    var itemUUID: String?
    var targetMinutes: Int?
    var targetDate: Date?
    var targetHasTime: Bool?
    var manual: Bool?
    var manualDone: Bool?
    var steps: [DestinationStepDTO]?
    var createdAt: Date
    var achievedAt: Date?
    var updatedAt: Date?
}

// MARK: - 端末内データのアカウント境界

/// SwiftData・UserDefaults・Firestoreの永続キャッシュを別アカウントへ持ち越さない。
/// Firestore公式は、利用者を切り替えるアプリで機微なキャッシュを残す場合、
/// セッション間の開示を避けるため永続領域の破棄を推奨している。
@MainActor
enum LocalAccountData {
    private static let ownerKey = "localData.ownerUID"
    private static var clearing = false

    static func prepareForSignedInUser(uid: String, context: ModelContext) async {
        let defaults = UserDefaults.standard
        if let previous = defaults.string(forKey: ownerKey), previous != uid {
            await clearOwnedData(context: context)
        }
        defaults.set(uid, forKey: ownerKey)
    }

    static func prepareForLocalMode(context: ModelContext) async {
        guard UserDefaults.standard.string(forKey: ownerKey) != nil else { return }
        await clearOwnedData(context: context)
    }

    static func clearAfterSignOut(context: ModelContext) async {
        guard UserDefaults.standard.string(forKey: ownerKey) != nil else {
            SyncService.shared.stopSync()
            return
        }
        await clearOwnedData(context: context)
    }

    private static func clearOwnedData(context: ModelContext) async {
        guard !clearing else { return }
        clearing = true
        defer { clearing = false }

        SyncService.shared.stopSync()
        BlockedSailors.shared.reset()

        for session in (try? context.fetch(FetchDescriptor<StudySession>())) ?? [] {
            context.delete(session)
        }
        for item in (try? context.fetch(FetchDescriptor<StudyItem>())) ?? [] {
            context.delete(item)
        }
        for day in (try? context.fetch(FetchDescriptor<StudyDay>())) ?? [] {
            context.delete(day)
        }
        for destination in (try? context.fetch(FetchDescriptor<Destination>())) ?? [] {
            context.delete(destination)
        }
        try? context.save()

        StudyTimer.clearAll()
        PlayerProfile.reset()
        BoatCustomization.reset()
        PhoenixPose.resetSelection()
        NavigatorCustomization.reset()
        PublicHarborService.shared.resetLocalState()
        UserDefaults.standard.removeObject(forKey: ownerKey)
        WidgetBridge.refresh(context: context)

        await resetFirestoreCache()
    }

    private static func resetFirestoreCache() async {
        let current = Firestore.firestore()
        try? await current.terminate()
        try? await current.clearPersistence()

        // terminate後の取得は新しいFirestoreインスタンスになる。次のサインインでも
        // オフライン書き込みを保てるよう、同じ永続キャッシュ設定を戻す。
        let fresh = Firestore.firestore()
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        fresh.settings = settings
    }
}
