import UIKit

/// 控えめな触覚フィードバック。出航・着岸・記録などの節目に手応えを添える。
/// システムの触覚設定を尊重する(OFFなら鳴らない)。
enum Haptics {
    /// 出航など、動き出しの一打。
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// 着岸・記録の完了。
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
