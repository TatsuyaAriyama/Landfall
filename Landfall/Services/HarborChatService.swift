import FirebaseAuth
import FirebaseFirestore
import Foundation
import SwiftUI

/// プライベートの港のチャット。
/// 言葉のやりとりに加えて、メンバーの普段の記録が「着岸」「帰還」の静かな行として自動で流れ込む。
/// 見に行かなくても、同じ時間を航海している感じ(並走感)が生まれる。
///
/// rooms/{code}/chat/{id}:
///   { uid, kind: text|landfall|return, text?, itemName?, itemStyle?, itemSymbol?,
///     minutes?, gapDays?, createdAt, reactions: {uid: token} }
/// リアクションはWeb版と共通のハート/灯台。
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

/// Web版と共通のリアクション語彙。増やすときは firestore.rules も同時に更新する。
enum ChatReaction: String, CaseIterable {
    case heart
    case lighthouse

    var title: LocalizedStringKey {
        switch self {
        case .heart: "Heart"
        case .lighthouse: "I see you."
        }
    }

    var systemImage: String {
        switch self {
        case .heart: "heart"
        case .lighthouse: "light.beacon.max"
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
        #if DEBUG
        if Self.previewEnabled {
            let now = Date()
            messages = [
                ChatMessage(
                    id: "preview-1",
                    uid: "preview-akari",
                    kind: .text,
                    text: "こちらは準備できたよ。いい風です。",
                    itemName: nil,
                    itemStyle: nil,
                    itemSymbol: nil,
                    minutes: nil,
                    gapDays: nil,
                    createdAt: now.addingTimeInterval(-420),
                    reactions: ["preview-nagi": ChatReaction.lighthouse.rawValue]
                ),
                ChatMessage(
                    id: "preview-2",
                    uid: "preview-nagi",
                    kind: .landfall,
                    text: nil,
                    itemName: "読書",
                    itemStyle: TileStyle.coral.rawValue,
                    itemSymbol: TileSymbol.book.rawValue,
                    minutes: 25,
                    gapDays: nil,
                    createdAt: now.addingTimeInterval(-240),
                    reactions: ["preview-self": ChatReaction.heart.rawValue]
                ),
            ]
            return
        }
        #endif
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

    @discardableResult
    func send(roomId: String, text: String) -> Bool {
        #if DEBUG
        let senderUID = Self.previewEnabled ? "preview-self" : uid
        #else
        let senderUID = uid
        #endif
        guard let senderUID else { return false }
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !trimmed.isEmpty, ChatSafety.isAllowed(trimmed) else { return false }
        #if DEBUG
        if Self.previewEnabled {
            messages.append(
                ChatMessage(
                    id: UUID().uuidString,
                    uid: senderUID,
                    kind: .text,
                    text: trimmed,
                    itemName: nil,
                    itemStyle: nil,
                    itemSymbol: nil,
                    minutes: nil,
                    gapDays: nil,
                    createdAt: Date(),
                    reactions: [:]
                )
            )
            return true
        }
        #endif
        chatRef(roomId).addDocument(data: [
            "uid": senderUID,
            "kind": ChatMessage.Kind.text.rawValue,
            "text": trimmed,
            "createdAt": FieldValue.serverTimestamp(),
            "reactions": [:],
        ])
        return true
    }

    /// 自分の発言を取り下げる(自分のものだけ。ルールでも本人限定)。
    func delete(roomId: String, messageId: String) {
        #if DEBUG
        if Self.previewEnabled {
            messages.removeAll { $0.id == messageId }
            return
        }
        #endif
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

/// App Review 1.2のUGC要件に沿う、送信前の最低限の有害表現フィルター。
/// 通報・ブロックと併用し、通常の学習会話を過剰に止めない範囲で脅迫・自傷誘導・
/// 代表的な差別語を弾く。正規化して空白や記号による単純な回避も抑える。
private enum ChatSafety {
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

    // MARK: - リアクション

    /// 1メッセージにつき1人1つ。同じものをもう一度選ぶと取り消し。
    func react(roomId: String, message: ChatMessage, reaction: ChatReaction) {
        #if DEBUG
        let reactingUID = Self.previewEnabled ? "preview-self" : uid
        #else
        let reactingUID = uid
        #endif
        guard let reactingUID else { return }
        #if DEBUG
        if Self.previewEnabled,
           let index = messages.firstIndex(where: { $0.id == message.id }) {
            var reactions = messages[index].reactions
            if reactions[reactingUID] == reaction.rawValue {
                reactions.removeValue(forKey: reactingUID)
            } else {
                reactions[reactingUID] = reaction.rawValue
            }
            messages[index] = Self.replacingReactions(in: messages[index], with: reactions)
            return
        }
        #endif
        let field = "reactions.\(reactingUID)"
        if message.reactions[reactingUID] == reaction.rawValue {
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
        #if DEBUG
        if Self.previewEnabled {
            blocked = []
            return
        }
        #endif
        guard let uid else { blocked = []; return }
        guard let snap = try? await db.collection("users").document(uid)
            .collection("blocks").getDocuments() else { return }
        blocked = Set(snap.documents.map(\.documentID))
    }

    func block(_ targetUid: String) async throws {
        #if DEBUG
        if Self.previewEnabled {
            guard targetUid != "preview-self", !targetUid.isEmpty else {
                throw HarborBlockError.invalidTarget
            }
            blocked.insert(targetUid)
            return
        }
        #endif
        guard let uid else { throw RoomError.notSignedIn }
        guard targetUid != uid, !targetUid.isEmpty else { throw HarborBlockError.invalidTarget }
        try await db.collection("users").document(uid).collection("blocks")
            .document(targetUid).setData(["createdAt": FieldValue.serverTimestamp()])
        guard self.uid == uid else { return }
        blocked.insert(targetUid)
    }

    func unblock(_ targetUid: String) async throws {
        #if DEBUG
        if Self.previewEnabled {
            guard !targetUid.isEmpty else { throw HarborBlockError.invalidTarget }
            blocked.remove(targetUid)
            return
        }
        #endif
        guard let uid else { throw RoomError.notSignedIn }
        guard !targetUid.isEmpty else { throw HarborBlockError.invalidTarget }
        try await db.collection("users").document(uid).collection("blocks")
            .document(targetUid).delete()
        guard self.uid == uid else { return }
        blocked.remove(targetUid)
    }

    #if DEBUG
    private static var previewEnabled: Bool {
        ProcessInfo.processInfo.environment["LANDFALL_PRIVATE_PREVIEW"] == "1"
    }

    private static func replacingReactions(
        in message: ChatMessage,
        with reactions: [String: String]
    ) -> ChatMessage {
        ChatMessage(
            id: message.id,
            uid: message.uid,
            kind: message.kind,
            text: message.text,
            itemName: message.itemName,
            itemStyle: message.itemStyle,
            itemSymbol: message.itemSymbol,
            minutes: message.minutes,
            gapDays: message.gapDays,
            createdAt: message.createdAt,
            reactions: reactions
        )
    }
    #endif
}

private enum HarborBlockError: LocalizedError {
    case invalidTarget

    var errorDescription: String? {
        LF.text("This sailor's block setting could not be changed.")
    }
}
