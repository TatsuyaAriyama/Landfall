import SwiftUI

/// タイプ診断。判定ロジックは MonthStats 側で行い、ここでは表示語彙のみを持つ。
/// 全タイプ肯定的。表示文字列は LocalizedStringKey にして Text 経由で言語に追従させる。
enum StudyArchetype: String, CaseIterable, Codable {
    case phoenix      // 不死鳥型
    case stoneBridge  // 石橋型
    case waveRider    // 波乗り型
    case comet        // 彗星型
    case morningCalm  // 朝凪型

    var displayName: LocalizedStringKey {
        switch self {
        case .phoenix: "Phoenix"
        case .stoneBridge: "Stone Bridge"
        case .waveRider: "Wave Rider"
        case .comet: "Comet"
        case .morningCalm: "Morning Calm"
        }
    }

    /// 決め台詞(1行目)。
    var tagline: LocalizedStringKey {
        switch self {
        case .phoenix: "Sink for long, then rise again."
        case .stoneBridge: "Quietly, surely, you build."
        case .waveRider: "You have your own tide."
        case .comet: "When you burn, you burn all at once."
        case .morningCalm: "No noise, no rush, no break."
        }
    }

    /// 添え書き(2行目)。決め台詞を受けて断言で締める。
    var subline: LocalizedStringKey {
        switch self {
        case .phoenix: "However long the gap, you begin again."
        case .stoneBridge: "No flourish needed. What you stack remains."
        case .waveRider: "Some days ebb so others can flow."
        case .comet: "The stillness is only your next approach."
        case .morningCalm: "That calm is your greatest strength."
        }
    }
}
