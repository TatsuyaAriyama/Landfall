import Foundation

/// ロケール準拠の日付・時間整形。英語/日本語で表記が自動的に切り替わる。
/// 期間や日付はここに集約し、各画面で言語別の文字列を持たない。
enum LF {
    // MARK: - 期間

    /// 期間表示。en: "9h 15m" / ja: "9時間15分"。60分未満は分のみ。
    static func duration(minutes: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = minutes >= 60 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes)m"
    }

    // MARK: - 日付

    /// 「7月14日」/ "Jul 14"。
    static func dayMonth(_ date: Date) -> String {
        templated("MMMd").string(from: date)
    }

    /// 「火曜日」/ "Tuesday"。
    static func weekdayFull(_ date: Date) -> String {
        templated("EEEE").string(from: date)
    }

    /// 「7月14日(火)」/ "Wed, Jul 14" — 見出し用。
    static func dayWithWeekday(_ date: Date) -> String {
        templated("MMMdEEE").string(from: date)
    }

    /// 「2026年7月」/ "July 2026"。
    static func monthYear(year: Int, month: Int) -> String {
        guard let date = date(year: year, month: month) else { return "\(year)/\(month)" }
        return templated("yMMMM").string(from: date)
    }

    /// 「7月」/ "July"。
    static func monthName(year: Int, month: Int) -> String {
        guard let date = date(year: year, month: month) else { return "\(month)" }
        return templated("MMMM").string(from: date)
    }

    // MARK: - 内部

    private static func date(year: Int, month: Int, day: Int = 1) -> Date? {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return Calendar.current.date(from: comps)
    }

    /// テンプレートから現在ロケールの並びで整形するフォーマッタ(テンプレート単位でキャッシュ)。
    private static var cache: [String: DateFormatter] = [:]
    private static func templated(_ template: String) -> DateFormatter {
        if let cached = cache[template] { return cached }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate(template)
        cache[template] = formatter
        return formatter
    }
}
