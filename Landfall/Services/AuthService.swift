import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import SwiftUI

/// Firebase Authentication のラッパー。Apple / Google サインインとサインアウト・アカウント削除を扱う。
/// アプリの状態(サインイン済みかどうか)は `user` を監視して判定する。
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var user: User?
    @Published var errorMessage: String?
    @Published var isWorking = false

    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var currentAppleNonce: String?

    var isSignedIn: Bool { user != nil }

    private init() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.user = user
        }
    }

    // MARK: - Apple

    func startSignInWithAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentAppleNonce = nonce
        request.requestedScopes = [.fullName]
        request.nonce = Self.sha256(nonce)
    }

    func handleSignInWithAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = currentAppleNonce,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Apple サインインに失敗しました。"
                return
            }
            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: idToken,
                rawNonce: nonce,
                fullName: credential.fullName
            )
            await signIn(with: firebaseCredential)
        }
    }

    // MARK: - Google

    func signInWithGoogle() async {
        guard let rootViewController = Self.topViewController() else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Google サインインに失敗しました。"
                return
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            await signIn(with: credential)
        } catch {
            if (error as NSError).code != GIDSignInError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Common

    private func signIn(with credential: AuthCredential) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await Auth.auth().signIn(with: credential)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        try? GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
    }

    /// アカウント削除。Firebase Auth のユーザーを削除する(App Store 必須要件)。
    /// Firestore 上のデータ削除は SyncService 側で先に行う。
    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { return }
        try await user.delete()
    }

    // MARK: - Helpers

    private static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        precondition(status == errSecSuccess, "Unable to generate nonce.")

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }
}
