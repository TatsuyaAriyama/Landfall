import SwiftUI
import UIKit

extension Color {
    init(hex: UInt) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

private func adaptiveColor(light: UInt, dark: UInt) -> Color {
    Color(uiColor: UIColor { trait in
        UIColor(Color(hex: trait.userInterfaceStyle == .dark ? dark : light))
    })
}

/// Landfall パレット。グラデーション・影は使わない。
/// ink / paper は明暗に追従する意味色(地＝paper、文字/線＝ink)。ボタンは ink 地 + paper 文字で自然に反転する。
/// ブランド色(harborTeal, coral, midnight, sunYellow ...)は固定。航海誌カードは固定デザインのため常にライトで描く。
enum LFColor {
    static let ink = adaptiveColor(light: 0x141414, dark: 0xF4F1EC)     // 文字・線・濃地(暗所で反転)
    static let paper = adaptiveColor(light: 0xFFFFFF, dark: 0x161412)   // 画面の地(暗所で暗く)
    static let inkFixed = Color(hex: 0x141414)     // 反転しない固定の黒
    static let tileInk = adaptiveColor(light: 0x141414, dark: 0x2C2A28)  // 黒タイル: 暗所では地から少し持ち上げて識別できるように
    static let sunYellow = Color(hex: 0xFFD84D)    // 学んだ日数
    static let seaGreen = Color(hex: 0x5DCAA5)     // 休んだ日数(学んだ日と同格)
    static let coral = Color(hex: 0xF0997B)        // カード2背景・空白バー
    static let deepRust = Color(hex: 0x4A1B0C)     // カード2の濃色
    static let midnight = Color(hex: 0x1A1130)     // カード3背景
    static let lavender = Color(hex: 0xCECBF6)     // カード3決め台詞
    static let violet = Color(hex: 0x534AB7)       // カード3ピル枠線
    static let returnOrange = Color(hex: 0xF5822A) // 帰還マーカー
    // アプリアイコン(Landfall図案)専用色
    static let harborTeal = Color(hex: 0x184A40)   // Landfall アイコン背景(既定)
    static let harborSand = Color(hex: 0xEADEBD)   // Landfall アイコン前景(帆と陸)
    static let emberGold = Color(hex: 0xF3C065)    // Landfall 暖色版の前景
}

/// 外観(ライト/ダーク)。言語設定と同じく、端末設定に関わらずアプリ内で切り替えられる。
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    static let storageKey = "appTheme"
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    var label: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum LFMetrics {
    static let cardSize = CGSize(width: 390, height: 693)
    static let cardCorner: CGFloat = 20
    static let cardPadding: CGFloat = 36
}

/// 太字は使わない。weight は .medium(500)まで。
/// 既定サイズは端末の文字サイズ設定(Dynamic Type)に追従する(UIFontMetricsで基準サイズをスケール)。
/// 航海誌カードは固定寸法の絵はがきなので、`*Fixed` を使い .large 相当に焼き付けてレイアウトを保つ
///(`\.lfFixedType` 環境が true の場所では共有部品も自動で固定側を選ぶ)。
enum LFFont {
    // 追従(端末の文字サイズに合わせて拡大)。
    static func number(_ size: CGFloat) -> Font { scaled(.monospacedDigitSystemFont(ofSize: size, weight: .medium)) }
    static func copy(_ size: CGFloat) -> Font { scaled(.systemFont(ofSize: size, weight: .medium)) }
    static func label(_ size: CGFloat) -> Font { scaled(.systemFont(ofSize: size, weight: .regular)) }

    // 固定(絵はがき用。文字サイズ設定に依存せず .large 相当で焼く)。
    static func numberFixed(_ size: CGFloat) -> Font { pinned(.monospacedDigitSystemFont(ofSize: size, weight: .medium)) }
    static func copyFixed(_ size: CGFloat) -> Font { pinned(.systemFont(ofSize: size, weight: .medium)) }
    static func labelFixed(_ size: CGFloat) -> Font { pinned(.systemFont(ofSize: size, weight: .regular)) }

    // 環境フラグでどちらかを選ぶ(共有部品用)。
    static func number(_ size: CGFloat, fixed: Bool) -> Font { fixed ? numberFixed(size) : number(size) }
    static func copy(_ size: CGFloat, fixed: Bool) -> Font { fixed ? copyFixed(size) : copy(size) }
    static func label(_ size: CGFloat, fixed: Bool) -> Font { fixed ? labelFixed(size) : label(size) }

    private static func scaled(_ base: UIFont) -> Font {
        Font(UIFontMetrics.default.scaledFont(for: base))
    }
    private static let cardTrait = UITraitCollection(preferredContentSizeCategory: .large)
    private static func pinned(_ base: UIFont) -> Font {
        Font(UIFontMetrics.default.scaledFont(for: base, compatibleWith: cardTrait))
    }
}

/// この環境が true の subtree では、文字サイズ設定に追従せず固定寸法で描く。
/// 固定寸法の航海誌カード(絵はがき/共有画像)で使い、共有部品(CardKicker等)も固定側を選ばせる。
private struct LFFixedTypeKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var lfFixedType: Bool {
        get { self[LFFixedTypeKey.self] }
        set { self[LFFixedTypeKey.self] = newValue }
    }
}

/// 押した瞬間だけ、ほんの少し沈む。タップの手応えを視覚でも返す(影は使わない)。
/// タイルや行など、頻度の高いタップ対象に添える。
struct LFPressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 全カード共通の上部キッカー。4枚で仕様を揃えるため必ずこれを使う。
struct CardKicker: View {
    var text: LocalizedStringKey
    var color: Color
    @Environment(\.lfFixedType) private var fixedType

    var body: some View {
        Text(text)
            .font(LFFont.label(15, fixed: fixedType))
            .tracking(2)
            .foregroundStyle(color)
    }
}

/// 全カード共通のブランド表記。そのカードの主前景色の40%で置く。
struct CardBrandmark: View {
    var color: Color
    @Environment(\.lfFixedType) private var fixedType

    var body: some View {
        Text(verbatim: "Landfall-StudyLog")
            .font(LFFont.label(13, fixed: fixedType))
            .foregroundStyle(color.opacity(0.4))
    }
}

/// 全カード共通の器。角丸20pt、装飾なし。
struct CardScaffold<Content: View>: View {
    var background: Color
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(LFMetrics.cardPadding)
            .frame(width: LFMetrics.cardSize.width, height: LFMetrics.cardSize.height)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
    }
}
