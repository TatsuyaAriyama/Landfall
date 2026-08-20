import FirebaseAuth
import FirebaseFirestore
import Foundation

enum HarborBlockError: LocalizedError {
    case invalidTarget

    var errorDescription: String? {
        switch self {
        case .invalidTarget: LF.text("This sailor's block setting could not be changed.")
        }
    }
}

/// 見えなくした相手。自分の端末とアカウントの中だけで効き、相手には伝わらない。
/// 保存先は `users/{uid}/blocks/{targetUid}` で、本人以外は読み書きできない。
@MainActor
final class BlockedSailors: ObservableObject {
    static let shared = BlockedSailors()
    private init() {}

    @Published private(set) var blocked: Set<String> = []

    /// どのアカウントの一覧を抱えているか。サインインが替わったとき、
    /// 前の人の「見えなくした相手」を持ち越さないために控える。
    private var ownerUID: String?

    private var db: Firestore { Firestore.firestore() }
    private var uid: String? { Auth.auth().currentUser?.uid }

    func load() async {
        #if DEBUG
        if Self.previewEnabled {
            blocked = []
            return
        }
        #endif
        guard let uid else {
            reset()
            return
        }
        if ownerUID != uid {
            blocked = []
            ownerUID = uid
        }
        guard let snapshot = try? await db.collection("users").document(uid)
            .collection("blocks").getDocuments() else { return }
        // 待っている間に別のアカウントへ切り替わっていたら、結果は捨てる。
        guard self.uid == uid else { return }
        blocked = Set(snapshot.documents.map(\.documentID))
        ownerUID = uid
    }

    func block(_ targetUID: String) async throws {
        #if DEBUG
        if Self.previewEnabled {
            guard targetUID != "preview-self", !targetUID.isEmpty else {
                throw HarborBlockError.invalidTarget
            }
            blocked.insert(targetUID)
            return
        }
        #endif
        guard let uid else { throw RoomError.notSignedIn }
        guard targetUID != uid, !targetUID.isEmpty else { throw HarborBlockError.invalidTarget }
        try await db.collection("users").document(uid).collection("blocks")
            .document(targetUID).setData(["createdAt": FieldValue.serverTimestamp()])
        guard self.uid == uid else { return }
        ownerUID = uid
        blocked.insert(targetUID)
    }

    func unblock(_ targetUID: String) async throws {
        #if DEBUG
        if Self.previewEnabled {
            guard !targetUID.isEmpty else { throw HarborBlockError.invalidTarget }
            blocked.remove(targetUID)
            return
        }
        #endif
        guard let uid else { throw RoomError.notSignedIn }
        guard !targetUID.isEmpty else { throw HarborBlockError.invalidTarget }
        try await db.collection("users").document(uid).collection("blocks")
            .document(targetUID).delete()
        guard self.uid == uid else { return }
        ownerUID = uid
        blocked.remove(targetUID)
    }

    func reset() {
        blocked = []
        ownerUID = nil
    }

    #if DEBUG
    private static var previewEnabled: Bool {
        ProcessInfo.processInfo.environment["LANDFALL_PRIVATE_PREVIEW"] == "1"
    }
    #endif
}
