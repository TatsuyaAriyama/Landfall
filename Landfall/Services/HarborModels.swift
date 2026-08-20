import FirebaseAuth
import FirebaseFirestore
import Foundation
import SwiftData

/// 港で共有される1セッション(相手の記録を読むための非正規化データ)。
struct SharedSession: Identifiable {
    let id = UUID()
    let day: Int
    let minutes: Int
    /// 記録した時刻。古い共有データには無いため optional。
    let date: Date?
    let note: String?
    let itemName: String?
    let styleToken: String
    let symbolToken: String
}

/// 港に置くプレイヤーカード。
struct HarborMember: Identifiable, Hashable {
    let id: String          // uid
    let displayName: String
    /// プレイヤーカード(アイコン配色・シンボル・決意)。未設定は既定値で描く。
    var styleToken: String = TileStyle.midnight.rawValue
    var symbolToken: String = TileSymbol.phoenix.rawValue
    var resolve: String = ""
    /// 航海のはじまり(yyyy-MM-dd)。古いクライアントが書いたカードには無いので空。
    var sinceDay: String = ""
    /// みんなの海で使う船の部位ID。古いカードでは未設定。
    var boatSail: String? = nil
    var boatJib: String? = nil
    var boatHull: String? = nil
    var boatStripe: String? = nil
    var boatFlag: String? = nil
}

enum RoomError: LocalizedError {
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notSignedIn: LF.text("Sign in to enter a harbor.")
        }
    }
}

/// 当月の記録を港へ出すための、共有用ペイロード。
enum HarborMonthPayload {
    private enum Limit {
        static let note = 500
        static let itemName = 60
        /// ルール側の上限と足並みを揃える。
        static let monthSessions = 1000
    }

    /// 当月の「学んだ日」と各セッション(項目名・ひとこと・時間)を1枚にまとめる。
    /// 記録の全量に触れる数少ない場所なので、ここで「航海のはじまり」も取り直す。
    static func currentMonth(context: ModelContext) -> (docID: String, data: [String: Any])? {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: Date())
        guard let year = comps.year, let month = comps.month else { return nil }
        let docID = String(format: "%04d-%02d", year, month)

        let entries = (try? context.fetch(FetchDescriptor<StudyDay>())) ?? []
        let days = MonthStats.studiedDaySet(year: year, month: month, entries: entries, calendar: calendar)

        PlayerProfile.rememberVoyageStart(
            context: context,
            accountCreatedAt: Auth.auth().currentUser?.metadata.creationDate
        )

        let allSessions = (try? context.fetch(FetchDescriptor<StudySession>())) ?? []
        var monthSessions: [[String: Any]] = allSessions.compactMap { session in
            let c = calendar.dateComponents([.year, .month, .day], from: session.date)
            guard c.year == year, c.month == month, let day = c.day else { return nil }
            var dict: [String: Any] = ["day": day, "minutes": session.minutes, "date": session.date]
            if let note = session.note, !note.isEmpty { dict["note"] = String(note.prefix(Limit.note)) }
            if let item = session.item {
                dict["itemName"] = String(item.name.prefix(Limit.itemName))
                dict["styleToken"] = item.styleToken
                dict["symbolToken"] = item.symbolToken
            }
            return dict
        }
        // 一月にそこまで記録することは実際には起きないが、
        // 超えたときは一番古い記録から落として直近を守る。
        if monthSessions.count > Limit.monthSessions {
            monthSessions.sort { ($0["date"] as? Date ?? .distantPast) > ($1["date"] as? Date ?? .distantPast) }
            monthSessions = Array(monthSessions.prefix(Limit.monthSessions))
        }

        return (docID, [
            "days": days.sorted(),
            "sessions": monthSessions,
            "updatedAt": FieldValue.serverTimestamp(),
        ])
    }
}
