import Foundation

/// タイプ診断。判定ロジックは MonthStats 側で行い、ここでは表示語彙のみを持つ。
/// 全タイプ肯定的。
enum StudyArchetype: String, CaseIterable, Codable {
    case phoenix      // 不死鳥型
    case stoneBridge  // 石橋型
    case waveRider    // 波乗り型
    case comet        // 彗星型
    case morningCalm  // 朝凪型

    var displayName: String {
        switch self {
        case .phoenix: String(localized: "Phoenix")
        case .stoneBridge: String(localized: "Stone Bridge")
        case .waveRider: String(localized: "Wave Rider")
        case .comet: String(localized: "Comet")
        case .morningCalm: String(localized: "Morning Calm")
        }
    }

    /// 決め台詞(1行目)。
    var tagline: String {
        switch self {
        case .phoenix: String(localized: "Sink deep. Always return.")
        case .stoneBridge: String(localized: "Quietly, surely, you build.")
        case .waveRider: String(localized: "You have your own tide.")
        case .comet: String(localized: "When you burn, you burn all at once.")
        case .morningCalm: String(localized: "No noise, no rush, no break.")
        }
    }

    /// 添え書き(2行目)。決め台詞を受けて断言で締める。
    var subline: String {
        switch self {
        case .phoenix: String(localized: "The length of the gap is nothing to you.")
        case .stoneBridge: String(localized: "No flourish needed. What you stack remains.")
        case .waveRider: String(localized: "Some days ebb so others can flow.")
        case .comet: String(localized: "The stillness is only your next approach.")
        case .morningCalm: String(localized: "That calm is your greatest strength.")
        }
    }
}
