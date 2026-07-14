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
        case .phoenix: "不死鳥型"
        case .stoneBridge: "石橋型"
        case .waveRider: "波乗り型"
        case .comet: "彗星型"
        case .morningCalm: "朝凪型"
        }
    }

    /// 決め台詞(1行目)。
    var tagline: String {
        switch self {
        case .phoenix: "深く沈み、必ず戻る。"
        case .stoneBridge: "静かに、確実に、積む。"
        case .waveRider: "あなたには、あなたの潮がある。"
        case .comet: "燃えるときは、一気に。"
        case .morningCalm: "騒がず、焦らず、途切れず。"
        }
    }

    /// 添え書き(2行目)。決め台詞を受けて断言で締める。
    var subline: String {
        switch self {
        case .phoenix: "空白の長さは、あなたには関係がない。"
        case .stoneBridge: "派手さはいらない。積んだものが残る。"
        case .waveRider: "引く日があるから、満ちる日がある。"
        case .comet: "静けさは、次の助走にすぎない。"
        case .morningCalm: "その静けさが、いちばん強い。"
        }
    }
}
