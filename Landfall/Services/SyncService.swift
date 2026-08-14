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
final class SyncService {
    static let shared = SyncService()
    private init() {}

    private var db: Firestore { Firestore.firestore() }
    private var uid: String? { Auth.auth().currentUser?.uid }

    private var listeners: [ListenerRegistration] = []

    // MARK: - Push / delete (fire-and-forget)

    func push(_ item: StudyItem) {
        guard let uid else { return }
        let dto = ItemDTO(
            name: item.name, styleToken: item.styleToken, symbolToken: item.symbolToken,
            sortOrder: item.sortOrder, createdAt: item.createdAt, updatedAt: Date()
        )
        try? itemsCollection(uid).document(item.uuid.uuidString).setData(from: dto)
    }

    func delete(_ item: StudyItem) {
        guard let uid else { return }
        itemsCollection(uid).document(item.uuid.uuidString).delete()
    }

    func push(_ session: StudySession) {
        guard let uid else { return }
        let dto = SessionDTO(
            date: session.date, minutes: session.minutes, note: session.note,
            itemUUID: session.item?.uuid.uuidString, updatedAt: Date()
        )
        try? sessionsCollection(uid).document(session.uuid.uuidString).setData(from: dto)
    }

    func delete(_ session: StudySession) {
        guard let uid else { return }
        sessionsCollection(uid).document(session.uuid.uuidString).delete()
    }

    func push(_ day: StudyDay) {
        guard let uid else { return }
        let dto = DayDTO(date: day.date, note: day.note, updatedAt: Date())
        try? daysCollection(uid).document(Self.dayDocID(day.date)).setData(from: dto)
    }

    func deleteDay(_ date: Date) {
        guard let uid else { return }
        daysCollection(uid).document(Self.dayDocID(date)).delete()
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

    /// サインイン直後と前景復帰で呼ぶ。初回だけローカルをまとめて push し、
    /// 以降はリスナーで追加・編集・削除をリアルタイムに受信する。多重呼び出しに耐える。
    func performInitialSync(context: ModelContext) async {
        guard uid != nil else { return }
        migrationPushIfNeeded(context: context)
        startListening(context: context)
    }

    /// サインアウト時に呼ぶ。リスナーを外す。
    func stopSync() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }

    /// v1.0→v1.1 の移行(および新規サインイン)で、この uid につき一度だけローカルを push する。
    /// 一度だけにすることで、後の削除が「未 push の新規」と誤認されて復活するのを防ぐ。
    private func migrationPushIfNeeded(context: ModelContext) {
        guard let uid else { return }
        let key = "didInitialPush_\(uid)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        for item in (try? context.fetch(FetchDescriptor<StudyItem>())) ?? [] { push(item) }
        for session in (try? context.fetch(FetchDescriptor<StudySession>())) ?? [] { push(session) }
        for day in (try? context.fetch(FetchDescriptor<StudyDay>())) ?? [] { push(day) }
        for dest in (try? context.fetch(FetchDescriptor<Destination>())) ?? [] { push(dest) }
        UserDefaults.standard.set(true, forKey: key)
    }

    private func startListening(context: ModelContext) {
        guard let uid, listeners.isEmpty else { return }
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
            switch change.type {
            case .added, .modified:
                guard let dto = try? change.document.data(as: ItemDTO.self) else { continue }
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
        if changed { try? context.save() }
    }

    private func applySessions(_ snap: QuerySnapshot, context: ModelContext) {
        var changed = false
        for change in snap.documentChanges {
            let id = change.document.documentID
            switch change.type {
            case .added, .modified:
                guard let dto = try? change.document.data(as: SessionDTO.self) else { continue }
                let remoteAt = dto.updatedAt ?? .distantPast
                let item = dto.itemUUID.flatMap { fetchItem($0, context) }
                if let existing = fetchSession(id, context) {
                    if remoteAt > existing.updatedAt {
                        existing.date = dto.date; existing.minutes = dto.minutes
                        existing.note = dto.note; existing.item = item; existing.updatedAt = remoteAt
                        changed = true
                    }
                } else {
                    let session = StudySession(date: dto.date, minutes: dto.minutes, note: dto.note, item: item)
                    if let u = UUID(uuidString: id) { session.uuid = u }
                    session.updatedAt = remoteAt
                    context.insert(session); changed = true
                }
            case .removed:
                if let existing = fetchSession(id, context) { context.delete(existing); changed = true }
            }
        }
        if changed { try? context.save() }
    }

    private func applyDays(_ snap: QuerySnapshot, context: ModelContext) {
        var changed = false
        for change in snap.documentChanges {
            let id = change.document.documentID
            switch change.type {
            case .added, .modified:
                guard let dto = try? change.document.data(as: DayDTO.self) else { continue }
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
        HarborChatService.shared.stop()

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
        RoomService.shared.resetLocalState()
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
