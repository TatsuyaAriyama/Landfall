import FirebaseAuth
import FirebaseFirestore
import Foundation

/// パブリックの港。参加(members/{uid})と潮位(pulse)だけを Firestore に持つ。
/// 潮位 = その日、港のメンバーのうち何人が海に出たか。個人は一切書かない。
/// publicHarbors/{slug}/members/{uid}          … 参加(本人のみ読み書き)
/// publicHarbors/{slug}/pulse/{yyyy-MM}/days/{dd} … {count} 匿名の合算のみ
@MainActor
final class PublicHarborService: ObservableObject {
    static let shared = PublicHarborService()
    private init() {
        joined = Set(UserDefaults.standard.stringArray(forKey: Self.joinedCacheKey) ?? [])
    }

    /// 参加中のスラッグ。即時表示のためローカルにも控える(真実はFirestore)。
    @Published private(set) var joined: Set<String> = []
    /// 港ごとの「今日の出航」数。港タブを開いたときに読む。
    @Published private(set) var todaySail: [String: Int] = [:]

    private static let joinedCacheKey = "publicHarbor.joined"
    private var db: Firestore { Firestore.firestore() }
    private var uid: String? { Auth.auth().currentUser?.uid }

    // MARK: - 参加

    func refresh() async {
        guard let uid else { joined = []; return }
        var found: Set<String> = []
        // 5港固定なので個別に引く(コレクショングループ不要・ルールも単純に保てる)。
        for harbor in PublicHarbor.all {
            let doc = try? await db.collection("publicHarbors").document(harbor.slug)
                .collection("members").document(uid).getDocument()
            if doc?.exists == true { found.insert(harbor.slug) }
        }
        joined = found
        cacheJoined()
        await refreshTodaySail()
    }

    func join(_ slug: String) async throws {
        guard let uid else { throw RoomError.notSignedIn }
        try await db.collection("publicHarbors").document(slug)
            .collection("members").document(uid)
            .setData(["joinedAt": FieldValue.serverTimestamp()])
        joined.insert(slug)
        cacheJoined()
    }

    func leave(_ slug: String) async {
        guard let uid else { return }
        try? await db.collection("publicHarbors").document(slug)
            .collection("members").document(uid).delete()
        joined.remove(slug)
        cacheJoined()
    }

    private func cacheJoined() {
        UserDefaults.standard.set(Array(joined).sorted(), forKey: Self.joinedCacheKey)
    }

    // MARK: - 潮位(書く)

    /// 今日はじめて記録したとき、参加中の各港の潮位を+1する(1日1回・港ごと)。
    /// 個人を書かない=公開面に晒されるものが存在しない。
    func bumpPulseIfNeeded() {
        guard uid != nil, !joined.isEmpty else { return }
        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.year, .month, .day], from: now)
        guard let y = comps.year, let m = comps.month, let d = comps.day else { return }
        let todayKey = String(format: "%04d-%02d-%02d", y, m, d)

        for slug in joined {
            let dedupeKey = "publicHarbor.pulse.\(slug)"
            guard UserDefaults.standard.string(forKey: dedupeKey) != todayKey else { continue }
            // increment は未作成なら count=1 の create、既存なら +1 の update として評価され、
            // どちらもルールの検証(=ちょうど1増)を満たす。
            dayRef(slug: slug, year: y, month: m, day: d)
                .setData(["count": FieldValue.increment(Int64(1))], merge: true)
            UserDefaults.standard.set(todayKey, forKey: dedupeKey)
        }
    }

    // MARK: - 潮位(読む)

    /// 今日の出航数をまとめて読む(港タブ用)。
    func refreshTodaySail() async {
        guard uid != nil else { return }
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        guard let y = comps.year, let m = comps.month, let d = comps.day else { return }
        var result: [String: Int] = [:]
        for harbor in PublicHarbor.all {
            let snap = try? await dayRef(slug: harbor.slug, year: y, month: m, day: d).getDocument()
            result[harbor.slug] = (snap?.data()?["count"] as? Int) ?? 0
        }
        todaySail = result
    }

    /// 当月の潮位(日→人数)。詳細画面の潮の描画に使う。
    func monthTide(slug: String) async -> [Int: Int] {
        guard uid != nil else { return [:] }
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        guard let y = comps.year, let m = comps.month else { return [:] }
        let monthID = String(format: "%04d-%02d", y, m)
        guard let snap = try? await db.collection("publicHarbors").document(slug)
            .collection("pulse").document(monthID)
            .collection("days").getDocuments() else { return [:] }
        var tide: [Int: Int] = [:]
        for doc in snap.documents {
            if let day = Int(doc.documentID), let count = doc.data()["count"] as? Int {
                tide[day] = count
            }
        }
        return tide
    }

    private func dayRef(slug: String, year: Int, month: Int, day: Int) -> DocumentReference {
        db.collection("publicHarbors").document(slug)
            .collection("pulse").document(String(format: "%04d-%02d", year, month))
            .collection("days").document(String(format: "%02d", day))
    }
}
