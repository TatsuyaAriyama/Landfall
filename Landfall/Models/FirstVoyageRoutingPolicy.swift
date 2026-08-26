import Foundation

enum SignedInPlayerEntry: Equatable {
    case newlyCreated
    case returning
}

enum FirstVoyageRoute: Equatable {
    case waitingForAccountClassification
    case tutorial
    case home
}

/// Firebaseの新規作成判定と、端末内チュートリアルの進行状態を分けて扱う。
///
/// 復元済みFirebaseセッションは、再インストール後でも既存プレイヤーとして
/// 島へ戻す。一方、この端末で作成した新規アカウントは、アプリが途中終了
/// しても完了するまで初回航海を続ける。
enum FirstVoyageAccountProgress {
    private static let requiredPrefix = "tutorial.required.account.v1."
    private static let completedPrefix = "tutorial.completed.account.v1."

    static func markTutorialRequired(
        for uid: String,
        defaults: UserDefaults = .standard
    ) {
        guard !uid.isEmpty else { return }
        defaults.set(true, forKey: requiredPrefix + uid)
        defaults.removeObject(forKey: completedPrefix + uid)
    }

    static func markTutorialCompleted(
        for uid: String,
        defaults: UserDefaults = .standard
    ) {
        guard !uid.isEmpty else { return }
        defaults.removeObject(forKey: requiredPrefix + uid)
        defaults.set(true, forKey: completedPrefix + uid)
    }

    static func tutorialIsRequired(
        for uid: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard !uid.isEmpty else { return false }
        return defaults.bool(forKey: requiredPrefix + uid)
    }

    static func tutorialIsCompleted(
        for uid: String,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard !uid.isEmpty else { return false }
        return defaults.bool(forKey: completedPrefix + uid)
    }
}

enum FirstVoyageRoutingPolicy {
    static func route(
        forceTutorial: Bool,
        deviceTutorialCompleted: Bool,
        firebaseUID: String?,
        signedInEntry: SignedInPlayerEntry?,
        canUseDeviceOnlyMode: Bool,
        defaults: UserDefaults = .standard
    ) -> FirstVoyageRoute {
        if forceTutorial { return .tutorial }

        if let firebaseUID {
            if FirstVoyageAccountProgress.tutorialIsCompleted(
                for: firebaseUID,
                defaults: defaults
            ) {
                return .home
            }
            if FirstVoyageAccountProgress.tutorialIsRequired(
                for: firebaseUID,
                defaults: defaults
            ) {
                return .tutorial
            }
            guard let signedInEntry else {
                return .waitingForAccountClassification
            }
            return signedInEntry == .newlyCreated ? .tutorial : .home
        }

        guard canUseDeviceOnlyMode else {
            return .waitingForAccountClassification
        }
        return deviceTutorialCompleted ? .home : .tutorial
    }
}

enum FirstVoyageNotePolicy {
    static let maximumLength = 80

    static func normalized(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : String(value.prefix(maximumLength))
    }

    static func matches(_ input: String, requiredNote: String) -> Bool {
        normalized(input) == requiredNote
    }
}
