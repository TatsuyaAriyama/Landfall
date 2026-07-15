import SwiftUI

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

/// Landfall パレット。グラデーション・影は使わない。
enum LFColor {
    static let ink = Color(hex: 0x141414)          // カード1背景
    static let paper = Color.white                 // カード4背景
    static let sunYellow = Color(hex: 0xFFD84D)    // 学んだ日数
    static let seaGreen = Color(hex: 0x5DCAA5)     // 休んだ日数(学んだ日と同格)
    static let coral = Color(hex: 0xF0997B)        // カード2背景・空白バー
    static let deepRust = Color(hex: 0x4A1B0C)     // カード2の濃色
    static let midnight = Color(hex: 0x1A1130)     // カード3背景
    static let lavender = Color(hex: 0xCECBF6)     // カード3決め台詞
    static let violet = Color(hex: 0x534AB7)       // カード3ピル枠線
    static let returnOrange = Color(hex: 0xF5822A) // 帰還マーカー
}

enum LFMetrics {
    static let cardSize = CGSize(width: 390, height: 693)
    static let cardCorner: CGFloat = 20
    static let cardPadding: CGFloat = 36
}

/// 太字は使わない。weight は .medium(500)まで。
enum LFFont {
    static func number(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium).monospacedDigit()
    }
    static func copy(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium)
    }
    static func label(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular)
    }
}

/// 全カード共通の上部キッカー。4枚で仕様を揃えるため必ずこれを使う。
struct CardKicker: View {
    var text: LocalizedStringKey
    var color: Color

    var body: some View {
        Text(text)
            .font(LFFont.label(15))
            .tracking(2)
            .foregroundStyle(color)
    }
}

/// 全カード共通のブランド表記。そのカードの主前景色の40%で置く。
struct CardBrandmark: View {
    var color: Color

    var body: some View {
        Text("Landfall")
            .font(LFFont.label(13))
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
