import CryptoKit
import FirebaseAuth
import Foundation

/// 有料機能と開発者権限の共通判定。
/// 画面ごとにメールアドレスを直書きせず、必ずここを通す。
enum AccessPolicy {
    static let developerEmail = "ari.initx@gmail.com"

    static func isDeveloper(_ user: User? = Auth.auth().currentUser) -> Bool {
        guard let user,
              user.isEmailVerified,
              let email = user.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        else { return false }
        return email == developerEmail
    }

    /// StoreKitの appAccountToken とFirebase UIDを紐付ける安定UUID。
    /// サーバーも同じ手順で再計算し、他アカウントの購入JWSの使い回しを防ぐ。
    static func appAccountToken(for uid: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(uid.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50 // UUID version 5と同じ安定表現
        bytes[8] = (bytes[8] & 0x3f) | 0x80 // RFC 4122 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
