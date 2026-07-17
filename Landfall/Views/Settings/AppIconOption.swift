import SwiftUI

/// 選べるアプリアイコン。harbor(Landfallティール)を既定(primary)とし、
/// dusk(Landfall暖色)・midnight/coral(不死鳥)を代替とする。
/// UIKit非依存にして、アイコンPNGの再生成ハーネス(macOS)からも参照できるようにする。
enum AppIconOption: String, CaseIterable, Identifiable {
    case harbor    // Landfall図案・ティール(既定)
    case dusk      // Landfall図案・暖色(夕暮れ)
    case midnight  // 不死鳥・ミッドナイト
    case coral     // 不死鳥・コーラル

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .harbor: "Harbor"
        case .dusk: "Dusk"
        case .midnight: "Midnight"
        case .coral: "Coral"
        }
    }

    /// setAlternateIconName に渡す名前。primary(harbor)は nil。
    /// 各代替はアセットカタログの App Icon セット名と一致させる。
    var alternateIconName: String? {
        switch self {
        case .harbor: nil
        case .dusk: "AppIconDusk"
        case .midnight: "AppIconMidnight"
        case .coral: "AppIconCoral"
        }
    }

    /// アイコンの造形。Landfall(帆と陸)か Phoenix(不死鳥)か。
    enum Motif { case landfall, phoenix }

    var motif: Motif {
        switch self {
        case .harbor, .dusk: .landfall
        case .midnight, .coral: .phoenix
        }
    }

    var background: Color {
        switch self {
        case .harbor: LFColor.harborTeal
        case .dusk: LFColor.deepRust
        case .midnight: LFColor.midnight
        case .coral: LFColor.coral
        }
    }

    /// 前景(シェイプ塗り)の色。
    var foreground: Color {
        switch self {
        case .harbor: LFColor.harborSand
        case .dusk: LFColor.emberGold
        case .midnight: LFColor.coral
        case .coral: LFColor.deepRust
        }
    }
}

/// アプリアイコンと同一構図。設定プレビューと実アイコンPNGの単一ソース。
/// 1024pt基準の比率で描き、任意サイズに追従する。
struct AppIconArt: View {
    let option: AppIconOption

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let k = s / 1024
            ZStack {
                option.background
                switch option.motif {
                case .landfall:
                    LandfallShape()
                        .fill(option.foreground)
                        .frame(width: s, height: s)
                case .phoenix:
                    PhoenixShape()
                        .fill(option.foreground)
                        .frame(width: 620 * k, height: 620 * k)
                        .overlay(
                            Circle()
                                .fill(option.background)
                                .frame(width: 52 * k, height: 52 * k)
                                .offset(y: -150 * k)
                        )
                }
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Landfall の造形: 帰る帆(帆＋船体)と、望む陸地(大きな丘＋小さな丘)。
/// 1024の設計座標をrectに射影する。フラット塗りのみ。
struct LandfallShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 1024 * rect.width,
                    y: rect.minY + y / 1024 * rect.height)
        }
        var p = Path()

        // --- 陸地: 大きな丸い丘 + 小さな丘、水平の底辺 ---
        p.move(to: pt(430, 748))
        p.addQuadCurve(to: pt(556, 386), control: pt(452, 512))   // 左斜面(凸)から肩へ
        p.addQuadCurve(to: pt(624, 386), control: pt(590, 350))   // 丸い頂
        p.addQuadCurve(to: pt(705, 612), control: pt(676, 486))   // 右斜面を谷へ
        p.addQuadCurve(to: pt(788, 524), control: pt(742, 548))   // 小さな丘の頂へ
        p.addQuadCurve(to: pt(852, 748), control: pt(832, 642))   // 底辺へ下る
        p.addLine(to: pt(430, 748))
        p.closeSubpath()

        // --- 帆(細く高い山型) ---
        p.move(to: pt(318, 386))                                  // 頂点
        p.addQuadCurve(to: pt(404, 668), control: pt(376, 524))   // 右縁(凸)
        p.addLine(to: pt(302, 668))                               // 底
        p.addQuadCurve(to: pt(318, 386), control: pt(300, 522))   // 左縁(ほぼ直線)
        p.closeSubpath()

        // --- 船体(帆の下の三日月) ---
        p.move(to: pt(215, 650))                                  // 左先端
        p.addQuadCurve(to: pt(404, 700), control: pt(320, 646))   // 上縁
        p.addQuadCurve(to: pt(215, 650), control: pt(300, 778))   // 湾曲した船底
        p.closeSubpath()

        return p
    }
}
