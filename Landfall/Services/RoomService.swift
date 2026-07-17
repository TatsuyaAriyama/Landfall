import FirebaseAuth
import FirebaseFirestore
import Foundation
import SwiftData

/// 港(ルーム)。当月の学習記録を、同じ港のメンバーと共有する。
/// 共有されるのは「学んだ日」に加えて、各セッションの項目名・ひとこと・時間。
struct HarborRoom: Identifiable, Equatable {
    let id: String          // 6文字の招待コードがそのままID
    let name: String
    let memberIds: [String]
}

/// 港で共有される1セッション(相手の記録を読むための非正規化データ)。
struct SharedSession: Identifiable {
    let id = UUID()
    let day: Int
    let minutes: Int
    let note: String?
    let itemName: String?
    let styleToken: String
    let symbolToken: String
}

struct HarborMember: Identifiable, Hashable {
    let id: String          // uid
    let displayName: String
    /// プレイヤーカード(アイコン配色・シンボル・決意)。未設定は既定値で描く。
    var styleToken: String = TileStyle.midnight.rawValue
    var symbolToken: String = TileSymbol.phoenix.rawValue
    var resolve: String = ""
}

@MainActor
final class RoomService: ObservableObject {
    static let shared = RoomService()
    private init() {}

    @Published private(set) var rooms: [HarborRoom] = []
    @Published var errorMessage: String?

    private var db: Firestore { Firestore.firestore() }
    private var uid: String? { Auth.auth().currentUser?.uid }

    /// 表示名。プレイヤーカードの名前 > Authの表示名 > 「船乗り」。
    private var displayName: String {
        if !PlayerProfile.name.isEmpty { return PlayerProfile.name }
        let name = Auth.auth().currentUser?.displayName?.trimmingCharacters(in: .whitespaces)
        return (name?.isEmpty == false ? name! : String(localized: "Sailor"))
    }

    /// メンバードキュメントに書くプロフィール一式。
    private var profileData: [String: Any] {
        [
            "displayName": displayName,
            "styleToken": PlayerProfile.styleToken,
            "symbolToken": PlayerProfile.symbolToken,
            "resolve": PlayerProfile.resolve,
        ]
    }

    // MARK: - ルーム一覧

    func refreshRooms() async {
        guard let uid else { rooms = []; return }
        do {
            let snap = try await db.collection("rooms")
                .whereField("memberIds", arrayContains: uid)
                .getDocuments()
            rooms = snap.documents.compactMap { doc in
                let data = doc.data()
                guard let name = data["name"] as? String,
                      let members = data["memberIds"] as? [String] else { return nil }
                return HarborRoom(id: doc.documentID, name: name, memberIds: members)
            }
            .sorted { $0.name < $1.name }
        } catch {
            // 取得に失敗しても既存表示を維持する(オフライン等)。
        }
    }

    // MARK: - 作成・参加・退出

    /// 港を作る。招待コード(=ルームID)を返す。
    func createRoom(named name: String, context: ModelContext) async throws -> String {
        guard let uid else { throw RoomError.notSignedIn }
        let code = try await reserveUnusedCode()
        try await db.collection("rooms").document(code).setData([
            "name": name,
            "memberIds": [uid],
            "createdAt": FieldValue.serverTimestamp(),
        ])
        try await joinedRoomSetup(roomId: code, uid: uid, context: context)
        await refreshRooms()
        return code
    }

    /// 未使用の招待コードを引き当てる。既存の港を上書きしないよう、
    /// 生成のたびに存在確認し、衝突したら引き直す。
    private func reserveUnusedCode() async throws -> String {
        for _ in 0..<8 {
            let code = Self.generateCode()
            let snap = try await db.collection("rooms").document(code).getDocument()
            if !snap.exists { return code }
        }
        throw RoomError.codeUnavailable
    }

    /// 招待コードで港に入る。
    func joinRoom(code rawCode: String, context: ModelContext) async throws {
        guard let uid else { throw RoomError.notSignedIn }
        let code = rawCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard !code.isEmpty else { throw RoomError.roomNotFound }
        let ref = db.collection("rooms").document(code)
        guard let snap = try? await ref.getDocument(), snap.exists else {
            throw RoomError.roomNotFound
        }
        let members = snap.data()?["memberIds"] as? [String] ?? []
        if !members.contains(uid) {
            try await ref.updateData(["memberIds": FieldValue.arrayUnion([uid])])
        }
        try await joinedRoomSetup(roomId: code, uid: uid, context: context)
        await refreshRooms()
    }

    /// 港を出る。自分のプロフィール・軌跡を消してからメンバーを外れる。
    func leaveRoom(_ roomId: String) async {
        guard let uid else { return }
        let memberRef = db.collection("rooms").document(roomId)
            .collection("members").document(uid)
        if let months = try? await memberRef.collection("months").getDocuments() {
            for doc in months.documents { try? await doc.reference.delete() }
        }
        try? await memberRef.delete()
        try? await db.collection("rooms").document(roomId)
            .updateData(["memberIds": FieldValue.arrayRemove([uid])])
        await refreshRooms()
    }

    /// アカウント削除時: 参加中の全港から自分を外す(プロフィール・共有記録も消える)。
    /// 港に幽霊メンバーを残さないため、リモートデータ削除の前に呼ぶ。失敗しても続行する。
    func leaveAllRooms() async {
        await refreshRooms()
        for id in rooms.map(\.id) {
            await leaveRoom(id)
        }
    }

    /// 入港直後: プレイヤーカードを置き、当月の軌跡を公開する。
    private func joinedRoomSetup(roomId: String, uid: String, context: ModelContext) async throws {
        var data = profileData
        data["joinedAt"] = FieldValue.serverTimestamp()
        try await db.collection("rooms").document(roomId)
            .collection("members").document(uid).setData(data)
        publishCurrentMonth(context: context, roomIds: [roomId])
    }

    /// プレイヤーカードの変更を参加中の全港へ反映する(プロフィール保存時に呼ぶ)。
    /// 失敗してもローカルのカードには影響しない。
    func pushProfileToAllRooms() {
        guard let uid else { return }
        for room in rooms {
            db.collection("rooms").document(room.id)
                .collection("members").document(uid)
                .setData(profileData, merge: true)
        }
    }

    // MARK: - 記録の公開(自分の分だけ)

    /// 当月の学んだ日 + 各セッション(項目名・ひとこと・時間)を、参加中の全港(または指定の港)に書き込む。
    /// 記録の保存・削除のたびに呼ばれる。失敗してもローカルの動作には影響しない。
    func publishCurrentMonth(context: ModelContext, roomIds: [String]? = nil) {
        guard let uid else { return }
        let targets = roomIds ?? rooms.map(\.id)
        guard !targets.isEmpty else { return }

        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.year, .month], from: now)
        guard let year = comps.year, let month = comps.month else { return }
        let docID = String(format: "%04d-%02d", year, month)

        let entries = (try? context.fetch(FetchDescriptor<StudyDay>())) ?? []
        let days = MonthStats.studiedDaySet(year: year, month: month, entries: entries, calendar: calendar)

        // 当月のセッションを項目情報ごと非正規化して共有する。
        let allSessions = (try? context.fetch(FetchDescriptor<StudySession>())) ?? []
        let monthSessions: [[String: Any]] = allSessions.compactMap { session in
            let c = calendar.dateComponents([.year, .month, .day], from: session.date)
            guard c.year == year, c.month == month, let day = c.day else { return nil }
            var dict: [String: Any] = ["day": day, "minutes": session.minutes, "date": session.date]
            if let note = session.note, !note.isEmpty { dict["note"] = note }
            if let item = session.item {
                dict["itemName"] = item.name
                dict["styleToken"] = item.styleToken
                dict["symbolToken"] = item.symbolToken
            }
            return dict
        }

        for roomId in targets {
            db.collection("rooms").document(roomId)
                .collection("members").document(uid)
                .collection("months").document(docID).setData([
                    "days": days.sorted(),
                    "sessions": monthSessions,
                    "updatedAt": FieldValue.serverTimestamp(),
                ])
        }
    }

    // MARK: - メンバーとその軌跡の取得

    func members(of roomId: String) async -> [HarborMember] {
        guard uid != nil else { return [] }
        guard let snap = try? await db.collection("rooms").document(roomId)
            .collection("members").getDocuments() else { return [] }
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
        .sorted { $0.displayName < $1.displayName }
    }

    /// メンバーの当月の記録(学んだ日 + セッション一覧)。未公開なら空。
    func monthDetail(roomId: String, memberId: String, year: Int, month: Int) async -> (days: Set<Int>, sessions: [SharedSession]) {
        let docID = String(format: "%04d-%02d", year, month)
        guard let snap = try? await db.collection("rooms").document(roomId)
            .collection("members").document(memberId)
            .collection("months").document(docID).getDocument(),
            let data = snap.data() else { return ([], []) }

        let days = Set(data["days"] as? [Int] ?? [])
        let sessions: [SharedSession] = (data["sessions"] as? [[String: Any]] ?? []).map { raw in
            SharedSession(
                day: raw["day"] as? Int ?? 0,
                minutes: raw["minutes"] as? Int ?? 0,
                note: (raw["note"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                itemName: raw["itemName"] as? String,
                styleToken: raw["styleToken"] as? String ?? TileStyle.midnight.rawValue,
                symbolToken: raw["symbolToken"] as? String ?? TileSymbol.phoenix.rawValue
            )
        }
        return (days, sessions)
    }

    // MARK: - ヘルパ

    /// 紛らわしい文字(0/O, 1/I)を除いた6文字コード。
    private static func generateCode() -> String {
        let charset = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in charset.randomElement()! })
    }
}

enum RoomError: LocalizedError {
    case notSignedIn
    case roomNotFound
    case codeUnavailable

    var errorDescription: String? {
        switch self {
        case .notSignedIn: String(localized: "Sign in to enter a harbor.")
        case .roomNotFound: String(localized: "No harbor found for this code.")
        case .codeUnavailable: String(localized: "Couldn't open a harbor just now. Please try again.")
        }
    }
}
