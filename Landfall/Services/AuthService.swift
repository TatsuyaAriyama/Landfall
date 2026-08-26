import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import OSLog
import SwiftUI

/// Firebase Authentication のラッパー。Apple / Google サインインとサインアウト・アカウント削除を扱う。
/// アプリの状態(サインイン済みかどうか)は `user` を監視して判定する。
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tatsuyaariyama.Landfall",
        category: "Authentication"
    )

    @Published private(set) var user: User?
    @Published private(set) var signedInPlayerEntry: SignedInPlayerEntry?
    /// Firebase restores a saved session asynchronously. Until its first
    /// callback lands, "no user" means "not known yet" rather than "signed
    /// out" — routing on it directly is what made sign-in flash at launch.
    @Published private(set) var hasResolvedInitialAuthState = false
    @Published private(set) var isSimulatorPreviewing = false
    @Published private(set) var isUsingLocalMode: Bool
    @Published var errorMessage: String?
    @Published var isWorking = false

    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var currentAppleNonce: String?
    private var appleDeletionDelegate: AppleDeletionAuthorizationDelegate?
    private static let localModeKey = "auth.localMode"

    var isSignedIn: Bool { user != nil }
    var canEnterApp: Bool { isSignedIn || isUsingLocalMode || isSimulatorPreviewing }

    /// Stable owner scope for the player's personal island. Firebase accounts
    /// never share local placement files; local and Simulator modes keep their
    /// own device-only islands until cloud publishing is introduced.
    var homeIslandOwnerID: String {
        if let uid = user?.uid { return "firebase:\(uid)" }
        if isUsingLocalMode { return "local-device" }
        if isSimulatorPreviewing { return "simulator-preview" }
        return "signed-out"
    }

    var canPreviewWithoutSignIn: Bool {
        #if DEBUG && targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private init() {
        isUsingLocalMode = UserDefaults.standard.bool(forKey: Self.localModeKey)
        // A session already restored from the keychain is available right away;
        // taking it here means a returning player never sees a launch gap.
        user = Auth.auth().currentUser
        signedInPlayerEntry = user == nil ? nil : .returning
        hasResolvedInitialAuthState = user != nil || isUsingLocalMode
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            self.user = user
            self.hasResolvedInitialAuthState = true
            if user != nil {
                self.setLocalMode(false)
                // Interactive sign-in publishes its authoritative isNewUser value
                // immediately after this callback. A restored keychain session has
                // no pending sign-in operation and is necessarily a returning user.
                if self.signedInPlayerEntry == nil, !self.isWorking {
                    self.signedInPlayerEntry = .returning
                }
            } else {
                self.signedInPlayerEntry = nil
            }
        }
    }

    /// Safety valve for the launch screen: if Firebase never reports a state
    /// (no network on a cold, signed-out start), stop waiting and show sign-in.
    func resolveInitialAuthStateIfPending() {
        guard !hasResolvedInitialAuthState else { return }
        hasResolvedInitialAuthState = true
    }

    // MARK: - Apple

    func startSignInWithAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        errorMessage = nil
        let nonce = Self.randomNonceString()
        currentAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func handleSignInWithAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        defer { currentAppleNonce = nil }
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = Self.signInErrorMessage(for: error, provider: "Apple")
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = currentAppleNonce,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = LF.text("Apple sign-in failed. Please try again.")
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
        guard !isWorking else { return }
        errorMessage = nil
        await Task.yield()
        guard Self.authenticationStorageIsAvailable() else {
            errorMessage = LF.text(
                "Secure sign-in storage is unavailable. Install the latest signed build and try again."
            )
            return
        }
        guard configureGoogleSignIn() else {
            errorMessage = LF.text("Sign-in is not configured for this build. Check the Firebase settings.")
            return
        }
        guard let rootViewController = Self.topViewController() else {
            errorMessage = LF.text("The sign-in screen could not be opened. Please try again.")
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = LF.text("Google sign-in failed. Please try again.")
                return
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            await signIn(with: credential)
        } catch {
            if (error as NSError).code != GIDSignInError.canceled.rawValue {
                Self.logSignInError(error, stage: "google-oauth")
                errorMessage = Self.signInErrorMessage(for: error, provider: "Google")
            }
        }
    }

    // MARK: - Common

    private func signIn(with credential: AuthCredential) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await Auth.auth().signIn(with: credential)
            let entry: SignedInPlayerEntry = result.additionalUserInfo?.isNewUser == true
                ? .newlyCreated
                : .returning
            if entry == .newlyCreated {
                FirstVoyageAccountProgress.markTutorialRequired(for: result.user.uid)
            }
            signedInPlayerEntry = entry
        } catch {
            Self.logSignInError(error, stage: "firebase-credential")
            errorMessage = Self.signInErrorMessage(for: error)
        }
    }

    /// Simulator で認証プロバイダの設定に阻まれても、ローカルUIを確認できる入口。
    /// DEBUG + Simulator にしか表示されず、Firebase のユーザーや同期データは作らない。
    func continueInSimulator() {
        guard canPreviewWithoutSignIn else { return }
        errorMessage = nil
        isSimulatorPreviewing = true
    }

    /// アカウント無しでも端末内だけで使える入口。同期と港はサインイン後に有効になる。
    func continueLocally() {
        errorMessage = nil
        isSimulatorPreviewing = false
        setLocalMode(true)
    }

    /// 設定からサインイン画面へ戻す。端末内記録は呼び出し側で先に整理する。
    func stopLocalMode() {
        setLocalMode(false)
    }

    func signOut() {
        isSimulatorPreviewing = false
        setLocalMode(false)
        signedInPlayerEntry = nil
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
    }

    /// アカウント削除。最近の認証を取り直し、Apple連携ならトークンを失効してから
    /// Firebase Authを削除する。cleanupは再認証成功後・Auth削除前にだけ実行する。
    func deleteAccount(cleanup: @MainActor () async throws -> Void) async throws {
        guard let user = Auth.auth().currentUser else { return }
        var appleAuthorizationCode: String?
        let providerIDs = Set(user.providerData.map(\.providerID))

        if providerIDs.contains("apple.com") {
            let result = try await requestAppleCredentialForDeletion()
            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: result.idToken,
                rawNonce: result.rawNonce,
                fullName: result.credential.fullName
            )
            try await user.reauthenticate(with: firebaseCredential)
            appleAuthorizationCode = result.authorizationCode
        } else if providerIDs.contains("google.com") {
            guard configureGoogleSignIn() else {
                throw AccountDeletionError.missingCredential
            }
            guard let rootViewController = Self.topViewController() else {
                throw AccountDeletionError.cannotPresentSignIn
            }
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: rootViewController
            )
            guard let idToken = result.user.idToken?.tokenString else {
                throw AccountDeletionError.missingCredential
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            try await user.reauthenticate(with: credential)
        } else {
            try await user.reload()
        }

        try await cleanup()
        if let appleAuthorizationCode {
            try await Auth.auth().revokeToken(
                withAuthorizationCode: appleAuthorizationCode
            )
        }
        try await user.delete()
        setLocalMode(false)
    }

    // MARK: - Helpers

    /// GoogleSignIn can infer this from Info.plist, but configuring it explicitly
    /// keeps Simulator and signed device builds on the exact same OAuth client.
    private func configureGoogleSignIn() -> Bool {
        let firebaseClientID = FirebaseApp.app()?.options.clientID
        let plistClientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
        guard let clientID = firebaseClientID ?? plistClientID,
              !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        return true
    }

    private func setLocalMode(_ enabled: Bool) {
        isUsingLocalMode = enabled
        UserDefaults.standard.set(enabled, forKey: Self.localModeKey)
    }

    private func requestAppleCredentialForDeletion() async throws -> AppleDeletionCredential {
        let nonce = Self.randomNonceString()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = AppleDeletionAuthorizationDelegate(
                rawNonce: nonce,
                continuation: continuation
            ) { [weak self] in
                self?.appleDeletionDelegate = nil
            }
            appleDeletionDelegate = delegate
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = delegate
            controller.presentationContextProvider = delegate
            controller.performRequests()
        }
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
                ?? scenes.first,
              let window = scene.windows.first(where: \.isKeyWindow)
                ?? scene.windows.first(where: { !$0.isHidden }),
              let root = window.rootViewController else {
            return nil
        }

        func visibleViewController(from viewController: UIViewController) -> UIViewController {
            if let presented = viewController.presentedViewController {
                return visibleViewController(from: presented)
            }
            if let navigation = viewController as? UINavigationController,
               let visible = navigation.visibleViewController {
                return visibleViewController(from: visible)
            }
            if let tab = viewController as? UITabBarController,
               let selected = tab.selectedViewController {
                return visibleViewController(from: selected)
            }
            return viewController
        }

        return visibleViewController(from: root)
    }

    private static func signInErrorMessage(for error: Error, provider: String? = nil) -> String {
        let nsError = error as NSError
        let providerName = provider ?? LF.text("Account")

        if nsError.domain == NSURLErrorDomain {
            return LF.text("Check your internet connection and try again.")
        }

        if nsError.domain == AuthErrorDomain,
           let code = AuthErrorCode(rawValue: nsError.code) {
            switch code {
            case .networkError, .webNetworkRequestFailed:
                return LF.text("Check your internet connection and try again.")
            case .tooManyRequests:
                return LF.text("Too many attempts were made. Please wait and try again.")
            case .keychainError:
                return LF.text(
                    "Secure sign-in storage is unavailable. Install the latest signed build and try again."
                )
            case .operationNotAllowed, .appNotAuthorized, .invalidAPIKey:
                return LF.text("Sign-in is not configured for this build. Check the Firebase settings.")
            default:
                break
            }
        }

        return LF.format("%@ sign-in failed. Please try again.", providerName)
    }

    /// Firebase Auth persists the user in Keychain. An unsigned Simulator app
    /// can complete the Google browser flow but will then fail with -34018
    /// because the application identifier entitlement is missing. Detect that
    /// before opening the browser so the failure is actionable and repeatable.
    private static func authenticationStorageIsAvailable() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(Bundle.main.bundleIdentifier ?? "KeelMira").auth-preflight",
            kSecAttrAccount as String: "keychain-access",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: false
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Authentication storage preflight failed status=\(status, privacy: .public)")
            return false
        }
        return true
    }

    /// Authentication failures used to collapse into one generic sentence,
    /// making Simulator-only configuration regressions impossible to diagnose.
    /// Log only the stable domain/code/stage; never include credentials or the
    /// provider's userInfo payload because it can contain sensitive tokens.
    private static func logSignInError(_ error: Error, stage: String) {
        let nsError = error as NSError
        logger.error(
            "Sign-in failed stage=\(stage, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
        )
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

private struct AppleDeletionCredential {
    let credential: ASAuthorizationAppleIDCredential
    let rawNonce: String
    let idToken: String
    let authorizationCode: String
}

private enum AccountDeletionError: LocalizedError {
    case cannotPresentSignIn
    case missingCredential

    var errorDescription: String? {
        switch self {
        case .cannotPresentSignIn:
            LF.text("The sign-in screen could not be opened. Please try again.")
        case .missingCredential:
            LF.text("Account verification failed. Please try again.")
        }
    }
}

@MainActor
private final class AppleDeletionAuthorizationDelegate: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private let rawNonce: String
    private var continuation: CheckedContinuation<AppleDeletionCredential, Error>?
    private let onFinish: () -> Void

    init(
        rawNonce: String,
        continuation: CheckedContinuation<AppleDeletionCredential, Error>,
        onFinish: @escaping () -> Void
    ) {
        self.rawNonce = rawNonce
        self.continuation = continuation
        self.onFinish = onFinish
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first
        return scene?.windows.first(where: \.isKeyWindow)
            ?? scene?.windows.first
            ?? ASPresentationAnchor()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              let codeData = credential.authorizationCode,
              let authorizationCode = String(data: codeData, encoding: .utf8) else {
            finish(throwing: AccountDeletionError.missingCredential)
            return
        }
        finish(
            returning: AppleDeletionCredential(
                credential: credential,
                rawNonce: rawNonce,
                idToken: idToken,
                authorizationCode: authorizationCode
            )
        )
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        finish(throwing: error)
    }

    private func finish(returning value: AppleDeletionCredential) {
        continuation?.resume(returning: value)
        continuation = nil
        onFinish()
    }

    private func finish(throwing error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        onFinish()
    }
}
