import FirebaseAuth
import FirebaseFirestore
import Foundation
import SwiftData

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

    private func memberRef(slug: String, uid: String) -> DocumentReference {
        db.collection("publicHarbors").document(slug)
            .collection("members").document(uid)
    }

    // MARK: - 参加

    func refresh() async {
        guard let uid else { joined = []; return }
        var found: Set<String> = []
        // 5港固定なので個別に引く(コレクショングループ不要・ルールも単純に保てる)。
        for harbor in PublicHarbor.all {
            let doc = try? await memberRef(slug: harbor.slug, uid: uid).getDocument()
            if doc?.exists == true { found.insert(harbor.slug) }
        }
        joined = found
        cacheJoined()
    }

    /// 参加: プレイヤーカードを置き、当月の記録をすぐ公開する。
    func join(_ slug: String, context: ModelContext) async throws {
        guard let uid else { throw RoomError.notSignedIn }
        var data = PlayerProfile.harborProfileData()
        data["joinedAt"] = FieldValue.serverTimestamp()
        try await memberRef(slug: slug, uid: uid).setData(data)
        joined.insert(slug)
        cacheJoined()
        publishCurrentMonth(context: context)
    }

    /// 退港: 自分の共有分(全記録+プロフィール)を消してから抜ける。
    /// 消せるのは本人だけ(ルールで強制)。
    func leave(_ slug: String) async {
        guard let uid else { return }
        let ref = memberRef(slug: slug, uid: uid)
        if let months = try? await ref.collection("months").getDocuments() {
            for doc in months.documents { try? await doc.reference.delete() }
        }
        try? await ref.delete()
        joined.remove(slug)
        cacheJoined()
    }

    /// アカウント削除時: 全パブリック港から自分の痕跡を消す。
    func leaveAll() async {
        await refresh()
        for slug in joined {
            await leave(slug)
        }
    }

    /// プレイヤーカードの変更を参加中の全パブリック港へも反映する。
    func pushProfile() {
        guard let uid else { return }
        for slug in joined {
            memberRef(slug: slug, uid: uid)
                .setData(PlayerProfile.harborProfileData(), merge: true)
        }
    }

    private func cacheJoined() {
        UserDefaults.standard.set(Array(joined).sorted(), forKey: Self.joinedCacheKey)
    }

    // MARK: - 記録の公開(自分の分だけ)

    /// 当月の記録を参加中の全パブリック港に書く。記録の保存・編集・削除のたびに呼ばれる。
    /// 月のドキュメントは上書き型なので、ローカルでの削除もそのまま反映される
    /// (=本人の操作だけがデータを変える)。
    func publishCurrentMonth(context: ModelContext) {
        guard let uid, !joined.isEmpty else { return }
        guard let payload = RoomService.monthPayload(context: context) else { return }
        for slug in joined {
            memberRef(slug: slug, uid: uid)
                .collection("months").document(payload.docID)
                .setData(payload.data)
        }
    }

    // MARK: - 港のメンバー

    /// 在港の船乗り(プロフィール一覧)。読みはサインイン済みなら誰でも。
    func members(of slug: String) async -> [HarborMember] {
        guard uid != nil else { return [] }
        guard let snap = try? await db.collection("publicHarbors").document(slug)
            .collection("members")
            .order(by: "joinedAt", descending: true)
            .limit(to: 200)
            .getDocuments() else { return [] }
        return snap.documents.compactMap { doc in
            let data = doc.data()
            guard let name = data["displayName"] as? String else { return nil }
            return HarborMember(
                id: doc.documentID,
                displayName: name,
                styleToken: data["styleToken"] as? String ?? TileStyle.midnight.rawValue,
                symbolToken: data["symbolToken"] as? String ?? TileSymbol.phoenix.rawValue,
                resolve: data["resolve"] as? String ?? ""
            )
        }
    }
}
