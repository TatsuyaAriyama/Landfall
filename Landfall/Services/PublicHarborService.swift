import FirebaseAuth
import FirebaseFirestore
import Foundation
import SwiftData

struct PublicHarborMonthDetail {
    let days: Set<Int>
    let sessions: [SharedSession]
}

/// Keeps Firestore's live listener private to the service while giving SwiftUI
/// an explicit lifetime to cancel when the selected sailor or month changes.
final class PublicHarborMonthSubscription {
    private var registration: ListenerRegistration?

    init(_ registration: ListenerRegistration) {
        self.registration = registration
    }

    func cancel() {
        registration?.remove()
        registration = nil
    }

    deinit { cancel() }
}

final class PublicHarborMembersSubscription {
    private var registration: ListenerRegistration?

    init(_ registration: ListenerRegistration) {
        self.registration = registration
    }

    func cancel() {
        registration?.remove()
        registration = nil
    }

    deinit { cancel() }
}

/// パブリックの港。参加すると、名前・アイコン・作業記録がその港に表示される。
/// 記録は月ごとに積み上がって残り、**書いた本人だけ**が消せる(ルールで強制)。
/// 退港すると自分の共有分(プロフィール+全記録)が消える。
///
/// publicHarbors/{slug}/members/{uid}                 … プロフィール(本人のみ書ける・読みは全員)
/// publicHarbors/{slug}/members/{uid}/months/{yyyy-MM} … 共有記録(本人のみ書ける・読みは全員)
@MainActor
final class PublicHarborService: ObservableObject {
    static let shared = PublicHarborService()
    private init() {
        joined = Set(UserDefaults.standard.stringArray(forKey: Self.joinedCacheKey) ?? [])
    }

    /// 参加中のスラッグ。即時表示のためローカルにも控える(真実はFirestore)。
    @Published private(set) var joined: Set<String> = []

    private static let joinedCacheKey = "publicHarbor.joined"
    private var db: Firestore { Firestore.firestore() }
    private var uid: String? { Auth.auth().currentUser?.uid }
    private struct PendingMonthPublish {
        let uid: String
        let slugs: Set<String>
        let docID: String
        let data: [String: Any]
    }
    private var pendingMonthPublish: PendingMonthPublish?
    private var monthPublishTask: Task<Void, Never>?

    private func memberRef(slug: String, uid: String) -> DocumentReference {
        db.collection("publicHarbors").document(slug)
            .collection("members").document(uid)
    }

    // MARK: - 参加

    func refresh() async {
        guard let uid else { joined = []; return }
        var resolved = joined
        var refreshedAny = false
        // 5港固定なので個別に引く(コレクショングループ不要・ルールも単純に保てる)。
        for harbor in PublicHarbor.all {
            do {
                let document = try await memberRef(slug: harbor.slug, uid: uid)
                    .getDocument(source: .server)
                refreshedAny = true
                if document.exists {
                    resolved.insert(harbor.slug)
                } else {
                    resolved.remove(harbor.slug)
                }
            } catch {
                // 一時的な通信失敗で、正しかった参加状態を空に戻さない。
                continue
            }
        }
        if refreshedAny {
            joined = resolved
            cacheJoined()
        }
    }

    /// 参加: プレイヤーカードを置き、当月の記録をすぐ公開する。
    func join(_ slug: String, context: ModelContext) async throws {
        guard let uid else { throw RoomError.notSignedIn }
        // カードを置く前に「航海のはじまり」を取り直す(入港直後の1枚目から正しい日を載せる)。
        PlayerProfile.rememberVoyageStart(context: context, accountCreatedAt: Auth.auth().currentUser?.metadata.creationDate)
        var data = PlayerProfile.harborProfileData()
        data["joinedAt"] = FieldValue.serverTimestamp()
        try await memberRef(slug: slug, uid: uid).setData(data)
        joined.insert(slug)
        cacheJoined()
        publishCurrentMonth(context: context)
    }

    /// 退港: 自分の共有分(全記録+プロフィール)を消してから抜ける。
    /// 消せるのは本人だけ(ルールで強制)。
    func leave(_ slug: String) async throws {
        guard let uid else { throw RoomError.notSignedIn }
        await stopMonthPublishing(for: slug)
        try await deleteMembership(slug: slug, uid: uid)

        // While the request was in flight another account may have signed in. Do not mutate that
        // account's local cache with the result of the previous account's deletion.
        guard self.uid == uid else { return }
        joined.remove(slug)
        cacheJoined()
    }

    /// アカウント削除時: 全パブリック港から自分の痕跡を消す。
    func leaveAll() async throws {
        guard let uid else { throw RoomError.notSignedIn }
        pendingMonthPublish = nil
        monthPublishTask?.cancel()
        await monthPublishTask?.value
        monthPublishTask = nil
        var deletedSlugs = Set<String>()
        var firstError: Error?

        // The device cache can be stale or empty after joining on the web. Deleting a missing
        // Firestore document is harmless, so inspect every official harbor during account cleanup.
        for harbor in PublicHarbor.all {
            do {
                try await deleteMembership(slug: harbor.slug, uid: uid)
                deletedSlugs.insert(harbor.slug)
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        if self.uid == uid, !deletedSlugs.isEmpty {
            joined.subtract(deletedSlugs)
            cacheJoined()
        }
        if let firstError { throw firstError }
    }

    /// プレイヤーカードの変更を参加中の全パブリック港へも反映する。
    func pushProfile() {
        Task { await syncProfile() }
    }

    /// Web版の保存処理と同じく、全パブリック港への書込み完了を待てる経路。
    /// 保存直後の再取得が書込みを追い越して古いカードを表示する競合を防ぐ。
    func syncProfile() async {
        // Webから参加した直後など、端末キャッシュにまだ無い港も保存対象へ含める。
        await refresh()
        guard let uid else { return }
        for slug in joined {
            try? await memberRef(slug: slug, uid: uid)
                .setData(PlayerProfile.harborProfileData(), merge: true)
        }
    }

    private func cacheJoined() {
        UserDefaults.standard.set(Array(joined).sorted(), forKey: Self.joinedCacheKey)
    }

    /// Remove all nested records before deleting the member card. Every operation is awaited so a
    /// failed network/rules write cannot be presented locally as a successful departure.
    private func deleteMembership(slug: String, uid: String) async throws {
        let ref = memberRef(slug: slug, uid: uid)
        let months = try await ref.collection("months").getDocuments(source: .server)
        for document in months.documents {
            try await document.reference.delete()
        }
        try await ref.delete()
    }

    func resetLocalState() {
        joined = []
        pendingMonthPublish = nil
        monthPublishTask?.cancel()
        monthPublishTask = nil
        UserDefaults.standard.removeObject(forKey: Self.joinedCacheKey)
    }

    // MARK: - 記録の公開(自分の分だけ)

    /// 当月の記録を参加中の全パブリック港に書く。記録の保存・編集・削除のたびに呼ばれる。
    /// 月のドキュメントは上書き型なので、ローカルでの削除もそのまま反映される。
    /// 書き込みは必ず直列化し、保存が続いた場合は最後の全量をもう一度送る。
    /// これにより古い3件時点のリクエストが新しい全件の後から到着して巻き戻す競合を防ぐ。
    func publishCurrentMonth(context: ModelContext) {
        guard let uid, !joined.isEmpty else { return }
        guard let payload = RoomService.monthPayload(context: context) else { return }
        pendingMonthPublish = PendingMonthPublish(
            uid: uid,
            slugs: joined,
            docID: payload.docID,
            data: payload.data
        )
        guard monthPublishTask == nil else { return }
        monthPublishTask = Task { await drainMonthPublishes() }
    }

    private func drainMonthPublishes() async {
        var encounteredError = false
        while !Task.isCancelled, let publish = pendingMonthPublish {
            pendingMonthPublish = nil
            guard uid == publish.uid else { continue }
            for slug in publish.slugs.sorted() {
                guard !Task.isCancelled, uid == publish.uid else { break }
                do {
                    try await memberRef(slug: slug, uid: publish.uid)
                        .collection("months").document(publish.docID)
                        .setData(publish.data)
                } catch {
                    // Keep the newest complete payload queued for one later pass. A subsequent
                    // local or cloud-sync change replaces it with an even newer complete copy.
                    if pendingMonthPublish == nil, uid == publish.uid {
                        pendingMonthPublish = publish
                    }
                    encounteredError = true
                    break
                }
            }
            if encounteredError { break }
        }
        let shouldRestart = !Task.isCancelled && !encounteredError && pendingMonthPublish != nil
        monthPublishTask = nil
        if shouldRestart {
            monthPublishTask = Task { await drainMonthPublishes() }
        }
    }

    private func stopMonthPublishing(for slug: String) async {
        monthPublishTask?.cancel()
        await monthPublishTask?.value
        monthPublishTask = nil
        if let pending = pendingMonthPublish {
            let remaining = pending.slugs.subtracting([slug])
            pendingMonthPublish = remaining.isEmpty ? nil : PendingMonthPublish(
                uid: pending.uid,
                slugs: remaining,
                docID: pending.docID,
                data: pending.data
            )
        }
        if pendingMonthPublish != nil {
            monthPublishTask = Task { await drainMonthPublishes() }
        }
    }

    // MARK: - 港のメンバー

    /// 在港の船乗り(プロフィール一覧)。60件ずつ全ページを読み、最初のページから
    /// 画面へ渡す。以前の固定200件打ち切りを避けつつ、全件待ちで画面を止めない。
    func members(
        of slug: String,
        onPage: (([HarborMember]) -> Void)? = nil
    ) async throws -> [HarborMember] {
        guard uid != nil else { throw RoomError.notSignedIn }
        let pageSize = 60
        let collection = db.collection("publicHarbors").document(slug)
            .collection("members")
        var query: Query = collection
            .order(by: FieldPath.documentID())
            .limit(to: pageSize)
        var documents: [QueryDocumentSnapshot] = []

        // Paint a warm cache immediately when available; the authoritative server pages below
        // replace it moments later, so speed never comes at the cost of remaining stale.
        if let cached = try? await query.getDocuments(source: .cache), !cached.documents.isEmpty {
            onPage?(
                cached.documents
                    .sorted(by: Self.memberDocumentNewestFirst)
                    .map(Self.member)
            )
        }

        while true {
            let snapshot = try await query.getDocuments(source: .server)
            documents.append(contentsOf: snapshot.documents)
            let resolved = documents
                .sorted(by: Self.memberDocumentNewestFirst)
                .map(Self.member)
            onPage?(resolved)
            guard snapshot.documents.count == pageSize, let last = snapshot.documents.last else { break }
            query = collection
                .order(by: FieldPath.documentID())
                .start(afterDocument: last)
                .limit(to: pageSize)
        }

        // order(by: joinedAt) は古いクライアントが作った joinedAt 無しのカードを
        // 結果から除外するため、全カードを読み、存在する日時でクライアント側ソートする。
        return documents
            .sorted(by: Self.memberDocumentNewestFirst)
            .map(Self.member)
    }

    /// Keeps the list current while the harbor is open. A join, departure, or player-card edit
    /// now appears without closing the board or manually pulling to refresh.
    func observeMembers(
        of slug: String,
        onChange: @escaping (Result<[HarborMember], Error>) -> Void
    ) -> PublicHarborMembersSubscription? {
        guard uid != nil else { return nil }
        let registration = db.collection("publicHarbors").document(slug)
            .collection("members")
            .addSnapshotListener { snapshot, error in
                Task { @MainActor in
                    if let error {
                        onChange(.failure(error))
                        return
                    }
                    guard let snapshot else { return }
                    let members = snapshot.documents
                        .sorted(by: Self.memberDocumentNewestFirst)
                        .map(Self.member)
                    onChange(.success(members))
                }
            }
        return PublicHarborMembersSubscription(registration)
    }

    /// 詳細を開くたびにメンバーカードを取り直す。
    /// 一覧から遷移する間に他端末で名前やアイコンが変わっても、古い値を表示し続けない。
    func member(of slug: String, id memberID: String) async throws -> HarborMember? {
        guard uid != nil else { throw RoomError.notSignedIn }
        let document = try await memberRef(slug: slug, uid: memberID)
            .getDocument(source: .server)
        guard document.exists else { return nil }
        return Self.member(document)
    }

    /// パブリック港の月別記録。Web版と同じく、月を移動するたびにその月を取得する。
    func monthDetail(
        slug: String,
        memberID: String,
        year: Int,
        month: Int
    ) async throws -> PublicHarborMonthDetail {
        guard uid != nil else { throw RoomError.notSignedIn }
        let docID = String(format: "%04d-%02d", year, month)
        let document = try await memberRef(slug: slug, uid: memberID)
            .collection("months").document(docID)
            .getDocument(source: .server)
        return Self.monthDetail(from: document.data())
    }

    /// Streams the selected month while it is open. New sessions from another
    /// device appear without leaving and reopening the sailor's page.
    func observeMonthDetail(
        slug: String,
        memberID: String,
        year: Int,
        month: Int,
        onChange: @escaping (Result<PublicHarborMonthDetail, Error>) -> Void
    ) -> PublicHarborMonthSubscription? {
        guard uid != nil else { return nil }
        let docID = String(format: "%04d-%02d", year, month)
        let registration = memberRef(slug: slug, uid: memberID)
            .collection("months").document(docID)
            .addSnapshotListener { document, error in
                Task { @MainActor in
                    if let error {
                        onChange(.failure(error))
                    } else if document?.metadata.isFromCache == true {
                        // The screen has already loaded the authoritative server copy. Do not
                        // let an older disk cache briefly replace it while the listener connects.
                        return
                    } else {
                        onChange(.success(Self.monthDetail(from: document?.data())))
                    }
                }
            }
        return PublicHarborMonthSubscription(registration)
    }

    private static func monthDetail(from data: [String: Any]?) -> PublicHarborMonthDetail {
        guard let data else { return PublicHarborMonthDetail(days: [], sessions: []) }

        var days = Set((data["days"] as? [Any] ?? []).compactMap(Self.integer))
        let sessions = (data["sessions"] as? [[String: Any]] ?? [])
            .map(Self.sharedSession)
            .filter { $0.day > 0 && $0.minutes > 0 }
            .sorted {
                if let lhs = $0.date, let rhs = $1.date { return lhs > rhs }
                if $0.date != nil { return true }
                if $1.date != nil { return false }
                return $0.day > $1.day
        }
        // days の更新だけが欠けた旧データでも、存在する記録へ辿れるよう補完する。
        days.formUnion(sessions.map(\.day))
        return PublicHarborMonthDetail(days: days, sessions: sessions)
    }

    private static func member(_ document: DocumentSnapshot) -> HarborMember {
        let data = document.data() ?? [:]
        let rawName = data["displayName"] as? String ?? ""
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        // 名前が未設定の旧カードも一覧から消さず、Web版と同じ既定名で表示する。
        let name = trimmedName.isEmpty ? LF.text("Sailor") : trimmedName
        let rawSince = data["sinceDay"] as? String ?? ""
        let since = PlayerProfile.sinceDayFormatter.date(from: rawSince) == nil ? "" : rawSince
        return HarborMember(
            id: document.documentID,
            displayName: name,
            styleToken: data["styleToken"] as? String ?? TileStyle.midnight.rawValue,
            symbolToken: data["symbolToken"] as? String ?? TileSymbol.phoenix.rawValue,
            resolve: data["resolve"] as? String ?? "",
            sinceDay: since,
            boatSail: data["boatSail"] as? String,
            boatJib: data["boatJib"] as? String,
            boatHull: data["boatHull"] as? String,
            boatStripe: data["boatStripe"] as? String,
            boatFlag: data["boatFlag"] as? String
        )
    }

    private static func sharedSession(_ raw: [String: Any]) -> SharedSession {
        SharedSession(
            day: integer(raw["day"]) ?? 0,
            minutes: integer(raw["minutes"]) ?? 0,
            date: (raw["date"] as? Timestamp)?.dateValue(),
            note: (raw["note"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            itemName: raw["itemName"] as? String,
            styleToken: raw["styleToken"] as? String ?? TileStyle.midnight.rawValue,
            symbolToken: raw["symbolToken"] as? String ?? TileSymbol.phoenix.rawValue
        )
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        return (value as? NSNumber)?.intValue
    }

    private static func memberDocumentNewestFirst(
        _ lhs: QueryDocumentSnapshot,
        _ rhs: QueryDocumentSnapshot
    ) -> Bool {
        let left = (lhs.data()["joinedAt"] as? Timestamp)?.dateValue()
        let right = (rhs.data()["joinedAt"] as? Timestamp)?.dateValue()
        switch (left, right) {
        case let (left?, right?): return left > right
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return lhs.documentID < rhs.documentID
        }
    }
}
