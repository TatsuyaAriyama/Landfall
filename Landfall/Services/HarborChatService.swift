import FirebaseAuth
import FirebaseFirestore
import Foundation

/// プライベートの港のチャット。
/// 言葉のやりとりに加えて、メンバーの普段の記録が「着岸」「帰還」の静かな行として自動で流れ込む。
/// 見に行かなくても、同じ時間を航海している感じ(並走感)が生まれる。
///
/// rooms/{code}/chat/{id}:
///   { uid, kind: text|landfall|return, text?, itemName?, itemStyle?, itemSymbol?,
///     minutes?, gapDays?, createdAt, reactions: {uid: token} }
/// リアクションは絵文字ではなく航海のシンボル3種(灯台=見てるよ / 錨=ゆっくり / 不死鳥=おかえり)。
struct ChatMessage: Identifiable, Equatable {
    enum Kind: String {
        case text
        case landfall   // 記録の自動反映
        case ret = "return"  // 空白明けの帰還(このアプリが一番祝いたい行)
    }

    let id: String
    let uid: String
    let kind: Kind
    let text: String?
    let itemName: String?
    let itemStyle: String?
    let itemSymbol: String?
    let minutes: Int?
    let gapDays: Int?
    let createdAt: Date
    /// uid → リアクショントークン(1人1つ)。
    let reactions: [String: String]
}

/// リアクションの語彙。増やすときは firestore.rules の許可リストも更新する。
enum ChatReaction: String, CaseIterable {
    case lighthouse   // 見てるよ・おつかれ
    case anchor       // ゆっくり休んで
    case phoenix      // おかえり・いい再開

    var symbol: TileSymbol {
        switch self {
        case .lighthouse: .lighthouse
        case .anchor: .anchor
        case .phoenix: .phoenix
        }
    }
}

@MainActor
final class HarborChatService: ObservableObject {
    static let shared = HarborChatService()
    private init() {}

    @Published private(set) var messages: [ChatMessage] = []
    /// 自分がブロックした相手。チャット表示から除く。
    @Published private(set) var blocked: Set<String> = []

    private var listener: ListenerRegistration?
    private var db: Firestore { Firestore.firestore() }
    private var uid: String? { Auth.auth().currentUser?.uid }

    private func chatRef(_ roomId: String) -> CollectionReference {
        db.collection("rooms").document(roomId).collection("chat")
    }

    // MARK: - 購読

    func listen(roomId: String) {
        stop()
        listener = chatRef(roomId)
            .order(by: "createdAt", descending: false)
            .limit(toLast: 120)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let snap else { return }
                Task { @MainActor in
                    self.messages = snap.documents.compactMap(Self.decode)
                }
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
        messages = []
    }

    private static func decode(_ doc: QueryDocumentSnapshot) -> ChatMessage? {
        let data = doc.data()
        guard let uid = data["uid"] as? String,
              let kindRaw = data["kind"] as? String,
              let kind = ChatMessage.Kind(rawValue: kindRaw) else { return nil }
        return ChatMessage(
            id: doc.documentID,
            uid: uid,
            kind: kind,
            text: data["text"] as? String,
            itemName: data["itemName"] as? String,
            itemStyle: data["itemStyle"] as? String,
            itemSymbol: data["itemSymbol"] as? String,
            minutes: data["minutes"] as? Int,
            gapDays: data["gapDays"] as? Int,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            reactions: data["reactions"] as? [String: String] ?? [:]
        )
    }

    // MARK: - 送る

    func send(roomId: String, text: String) {
        guard let uid else { return }
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !trimmed.isEmpty else { return }
        chatRef(roomId).addDocument(data: [
            "uid": uid,
            "kind": ChatMessage.Kind.text.rawValue,
            "text": trimmed,
            "createdAt": FieldValue.serverTimestamp(),
            "reactions": [:],
        ])
    }

    /// 自分の発言を取り下げる(自分のものだけ。ルールでも本人限定)。
    func delete(roomId: String, messageId: String) {
        chatRef(roomId).document(messageId).delete()
    }

    // MARK: - 記録の自動反映

    /// 記録の保存時に呼ぶ。参加中の全プライベート港に「着岸」または「帰還」の行を流す。
    /// 今日の記録だけ(過去日の後追いは流さない=静かに保存する)。
    func publishLog(item: StudyItem, minutes: Int, gapDays: Int?, isToday: Bool) {
        guard isToday, let uid else { return }
        let rooms = RoomService.shared.rooms
        guard !rooms.isEmpty else { return }

        let isReturn = (gapDays ?? 0) >= 2
        var data: [String: Any] = [
            "uid": uid,
            "kind": (isReturn ? ChatMessage.Kind.ret : .landfall).rawValue,
            "itemName": String(item.name.prefix(60)),
            "itemStyle": item.styleToken,
            "itemSymbol": item.symbolToken,
            "minutes": minutes,
            "createdAt": FieldValue.serverTimestamp(),
            "reactions": [:],
        ]
        if isReturn { data["gapDays"] = gapDays }

        for room in rooms {
            chatRef(room.id).addDocument(data: data)
        }
    }

    // MARK: - リアクション

    /// 1メッセージにつき1人1つ。同じものをもう一度選ぶと取り消し。
    func react(roomId: String, message: ChatMessage, reaction: ChatReaction) {
        guard let uid else { return }
        let field = "reactions.\(uid)"
        if message.reactions[uid] == reaction.rawValue {
            chatRef(roomId).document(message.id).updateData([field: FieldValue.delete()])
        } else {
            chatRef(roomId).document(message.id).updateData([field: reaction.rawValue])
        }
    }

    // MARK: - 通報・ブロック

    /// 通報。運営(開発者)だけが読める書き捨ての箱に入れる。
    func report(roomId: String, message: ChatMessage?, targetUid: String) {
        guard let uid else { return }
        var data: [String: Any] = [
            "reporterUid": uid,
            "roomId": roomId,
            "targetUid": targetUid,
            "createdAt": FieldValue.serverTimestamp(),
        ]
        if let message {
            data["messageId"] = message.id
            if let text = message.text { data["text"] = String(text.prefix(500)) }
        }
        db.collection("reports").addDocument(data: data)
    }

    /// ブロック。自分の端末とアカウントの中だけで効く(相手には伝わらない)。
    func loadBlocked() async {
        guard let uid else { blocked = []; return }
        guard let snap = try? await db.collection("users").document(uid)
            .collection("blocks").getDocuments() else { return }
        blocked = Set(snap.documents.map(\.documentID))
    }

    func block(_ targetUid: String) {
        guard let uid, targetUid != uid else { return }
        db.collection("users").document(uid).collection("blocks")
            .document(targetUid).setData(["createdAt": FieldValue.serverTimestamp()])
        blocked.insert(targetUid)
    }

    func unblock(_ targetUid: String) {
        guard let uid else { return }
        db.collection("users").document(uid).collection("blocks")
            .document(targetUid).delete()
        blocked.remove(targetUid)
    }
}
