import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 公開誌の一頁。画像はCallableでメタデータを落とし、公開用JPEGへ整形した後のデータだけを持つ。
struct PublicJournalEntry: Identifiable, Equatable {
    let id: String
    let authorID: String
    let dayID: String
    let harborSlug: String
    let displayName: String
    let styleToken: String
    let symbolToken: String
    let body: String
    let imageData: Data
    let imageWidth: Int
    let imageHeight: Int
    let updatedAt: Date?

    var date: Date? { PublicJournalService.date(from: dayID) }
}

/// 端末からCallableへ送る前のJPEG。サーバーでも再デコード・再縮小する。
struct PreparedPublicJournalPhoto: Equatable, Sendable {
    let data: Data
    let width: Int
    let height: Int
}

enum PublicJournalError: LocalizedError {
    case notSignedIn
    case notInPublicHarbor
    case invalidPhoto
    case photoTooLarge
    case invalidResponse
    case alreadyPublished
    case dayChanged
    case tryAgainLater

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            LF.text("Sign in to publish a public page.")
        case .notInPublicHarbor:
            LF.text("Join a public harbor before publishing.")
        case .invalidPhoto:
            LF.text("This photo could not be prepared. Choose another photo.")
        case .photoTooLarge:
            LF.text("This photo is too large. Choose another photo.")
        case .invalidResponse:
            LF.text("The public page could not be updated. Please try again.")
        case .alreadyPublished:
            LF.text("A page has already been published today. Open it to make changes.")
        case .dayChanged:
            LF.text("A new day has begun in Japan. Review the page, then send it again.")
        case .tryAgainLater:
            LF.text("Please wait a moment before sending the page again.")
        }
    }
}

/// 公開誌の取得・投稿・削除・通報。
/// 書き込みはすべてApp Check付きCallableを通し、日付はサーバー側のJSTで決定する。
@MainActor
final class PublicJournalService: ObservableObject {
    static let shared = PublicJournalService()

    static let bodyLimit = 260
    static let clientUploadLimit = 1_500_000
    static let clientMaximumDimension = 2_048

    private let db = Firestore.firestore()
    private let functions = Functions.functions(region: "asia-northeast1")

    private init() {}

    // MARK: - Reading

    func latestEntries(harborSlug: String? = nil, limit: Int = 30) async throws -> [PublicJournalEntry] {
        guard Auth.auth().currentUser != nil else { throw PublicJournalError.notSignedIn }
        var query: Query = db.collection("publicJournalEntries")
        if let harborSlug {
            query = query.whereField("harborSlug", isEqualTo: harborSlug)
        }
        let snapshot = try await query
            .order(by: "dayID", descending: true)
            .limit(to: min(max(limit, 1), 30))
            .getDocuments(source: .server)
        return snapshot.documents.compactMap(Self.entry)
    }

    func entryForToday() async throws -> PublicJournalEntry? {
        guard let uid = Auth.auth().currentUser?.uid else { throw PublicJournalError.notSignedIn }
        let today = Self.dayID(Date())
        let document = try await db.collection("publicJournalEntries")
            .document(Self.documentID(uid: uid, dayID: today))
            .getDocument(source: .server)
        return Self.entry(document)
    }

    // MARK: - Publishing

    func publish(
        body: String,
        photo: PreparedPublicJournalPhoto,
        harborSlug: String,
        replaceExisting: Bool,
        intendedDayID: String? = nil
    ) async throws -> String {
        guard Auth.auth().currentUser != nil else { throw PublicJournalError.notSignedIn }
        let trimmed = String(
            body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.bodyLimit)
        )
        guard !trimmed.isEmpty else { throw PublicJournalError.invalidResponse }
        guard PublicHarbor.by(slug: harborSlug) != nil else { throw PublicJournalError.notInPublicHarbor }
        guard !photo.data.isEmpty, photo.data.count <= Self.clientUploadLimit else {
            throw PublicJournalError.photoTooLarge
        }

        do {
            let result = try await functions.httpsCallable("publishPublicJournalEntry").call([
                "requestId": UUID().uuidString.lowercased(),
                "harborSlug": harborSlug,
                "body": trimmed,
                "imageBase64": photo.data.base64EncodedString(),
                "replaceExisting": replaceExisting,
                "intendedDayID": intendedDayID ?? Self.dayID(Date()),
            ])
            guard let payload = result.data as? [String: Any],
                  let entryID = payload["entryId"] as? String,
                  !entryID.isEmpty
            else { throw PublicJournalError.invalidResponse }
            return entryID
        } catch let error as NSError where error.domain == FunctionsErrorDomain {
            let code = FunctionsErrorCode(rawValue: error.code)
            if code == .alreadyExists {
                throw PublicJournalError.alreadyPublished
            }
            if code == .failedPrecondition {
                let details = error.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
                if details?["reason"] as? String == "day-changed" {
                    throw PublicJournalError.dayChanged
                }
                throw PublicJournalError.notInPublicHarbor
            }
            if code == .resourceExhausted {
                throw PublicJournalError.tryAgainLater
            }
            throw error
        }
    }

    func delete(_ entry: PublicJournalEntry) async throws {
        guard entry.authorID == Auth.auth().currentUser?.uid else {
            throw PublicJournalError.invalidResponse
        }
        _ = try await functions.httpsCallable("deletePublicJournalEntry").call([
            "entryId": entry.id,
        ])
    }

    func report(entry: PublicJournalEntry, reason: String = "inappropriate") async throws {
        try await submitReport(
            targetUid: entry.authorID,
            harborSlug: entry.harborSlug,
            entryID: entry.id,
            reason: reason
        )
    }

    func reportMember(_ memberID: String, harborSlug: String) async throws {
        try await submitReport(
            targetUid: memberID,
            harborSlug: harborSlug,
            entryID: nil,
            reason: "profile"
        )
    }

    private func submitReport(
        targetUid: String,
        harborSlug: String,
        entryID: String?,
        reason: String
    ) async throws {
        guard Auth.auth().currentUser != nil else { throw PublicJournalError.notSignedIn }
        var payload: [String: Any] = [
            "targetUid": targetUid,
            "harborSlug": harborSlug,
            "reason": reason,
        ]
        if let entryID { payload["entryId"] = entryID }
        _ = try await functions.httpsCallable("submitPublicContentReport").call(payload)
    }

    // MARK: - Client-side image preparation

    /// ImageIOで向きを焼き込み、JPEGへ変換する。EXIF/GPSは書き戻さない。
    nonisolated static func preparePhoto(from sourceData: Data) throws -> PreparedPublicJournalPhoto {
        let maximumDimension = 2_048
        let uploadLimit = 1_500_000
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil) else {
            throw PublicJournalError.invalidPhoto
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
        else { throw PublicJournalError.invalidPhoto }

        var encoded: Data?
        for quality in [0.86, 0.78, 0.70, 0.62, 0.54] {
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                output,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else { continue }
            CGImageDestinationAddImage(
                destination,
                image,
                [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
            )
            guard CGImageDestinationFinalize(destination) else { continue }
            let candidate = output as Data
            encoded = candidate
            if candidate.count <= uploadLimit { break }
        }

        guard let encoded, encoded.count <= uploadLimit else {
            throw PublicJournalError.photoTooLarge
        }
        return PreparedPublicJournalPhoto(
            data: encoded,
            width: image.width,
            height: image.height
        )
    }

    // MARK: - Mapping

    private static func entry(_ document: DocumentSnapshot) -> PublicJournalEntry? {
        guard let data = document.data(),
              let authorID = data["authorUid"] as? String,
              let dayID = data["dayID"] as? String,
              let harborSlug = data["harborSlug"] as? String,
              let displayName = data["displayName"] as? String,
              let styleToken = data["styleToken"] as? String,
              let symbolToken = data["symbolToken"] as? String,
              let body = data["body"] as? String,
              let imageData = data["imageData"] as? Data,
              let imageWidth = integer(data["imageWidth"]),
              let imageHeight = integer(data["imageHeight"])
        else { return nil }
        return PublicJournalEntry(
            id: document.documentID,
            authorID: authorID,
            dayID: dayID,
            harborSlug: harborSlug,
            displayName: displayName,
            styleToken: styleToken,
            symbolToken: symbolToken,
            body: body,
            imageData: imageData,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue()
        )
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        return (value as? NSNumber)?.intValue
    }

    static func dayID(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    nonisolated static func date(from dayID: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dayID)
    }

    static func documentID(uid: String, dayID: String) -> String {
        "\(uid)_\(dayID)"
    }

    /// 公開誌の日付は1日枠と同じJSTで表示し、端末タイムゾーンで前日にずれないようにする。
    static func displayedDate(for dayID: String) -> String {
        guard let date = date(from: dayID) else { return dayID }
        let formatter = DateFormatter()
        formatter.calendar = japanCalendar
        formatter.locale = AppLanguage.current.locale
        formatter.timeZone = japanCalendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("yMMMMd")
        return formatter.string(from: date)
    }

    private static let japanCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = japanCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = japanCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
