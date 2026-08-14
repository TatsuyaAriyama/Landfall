import FirebaseAppCheck
import FirebaseFunctions
import Foundation
import UIKit

enum FeedbackCategory: String, CaseIterable, Identifiable {
    case idea
    case issue
    case design
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idea: String(localized: "Idea")
        case .issue: String(localized: "Problem")
        case .design: String(localized: "Design")
        case .other: String(localized: "Other")
        }
    }

    var symbol: String {
        switch self {
        case .idea: "lightbulb"
        case .issue: "exclamationmark.triangle"
        case .design: "paintpalette"
        case .other: "ellipsis.bubble"
        }
    }
}

enum FeedbackSubmissionError: LocalizedError {
    case invalidResponse
    case appVerificationUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            String(localized: "Your feedback could not be sent. Please try again.")
        case .appVerificationUnavailable:
            String(localized: "The app could not be verified. Please reopen KeelMira and try again.")
        }
    }
}

/// App Check付きCallable経由で運営の非公開キューへ改善案を送る。
/// 学習記録は添付せず、不具合切り分けに必要な実行環境だけを送信する。
@MainActor
enum FeedbackService {
    static let maximumLength = 1_200
    static let minimumLength = 10

    private static let installationIDKey = "feedback.installation-id.v1"

    static func submit(category: FeedbackCategory, message: String) async throws -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumLength, trimmed.count <= maximumLength else {
            throw FeedbackSubmissionError.invalidResponse
        }

        // A callable normally obtains App Check automatically. Refreshing here prevents a
        // placeholder token cached after a temporary App Check outage from being submitted.
        let appCheckToken: AppCheckToken
        do {
            appCheckToken = try await AppCheck.appCheck().token(forcingRefresh: true)
        } catch {
            throw FeedbackSubmissionError.appVerificationUnavailable
        }
        guard appCheckToken.token.split(separator: ".").count == 3 else {
            throw FeedbackSubmissionError.appVerificationUnavailable
        }

        let callable = Functions.functions(region: "asia-northeast1")
            .httpsCallable("submitFeedback")
        let result = try await callable.call([
            "category": category.rawValue,
            "message": trimmed,
            "installationId": installationID,
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "buildNumber": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "osVersion": "iOS \(UIDevice.current.systemVersion)",
            "locale": Locale.preferredLanguages.first ?? Locale.current.identifier,
        ])

        guard let payload = result.data as? [String: Any],
              let feedbackID = payload["feedbackId"] as? String,
              !feedbackID.isEmpty
        else {
            throw FeedbackSubmissionError.invalidResponse
        }
        return feedbackID
    }

    private static var installationID: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: installationIDKey),
           UUID(uuidString: existing) != nil {
            return existing
        }
        let created = UUID().uuidString.lowercased()
        defaults.set(created, forKey: installationIDKey)
        return created
    }
}
