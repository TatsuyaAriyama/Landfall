import SwiftUI

/// タイルの配色プリセット。背景と前景の組みを固定し、デザイン言語から外れない。
enum TileStyle: String, CaseIterable, Identifiable {
    case midnight
    case coral
    case ink
    case seaGreen
    case violet
    case sunYellow

    var id: String { rawValue }

    var background: Color {
        switch self {
        case .midnight: LFColor.midnight
        case .coral: LFColor.coral
        case .ink: LFColor.ink
        case .seaGreen: LFColor.seaGreen
        case .violet: LFColor.violet
        case .sunYellow: LFColor.sunYellow
        }
    }

    var foreground: Color {
        switch self {
        case .midnight: LFColor.coral
        case .coral: LFColor.deepRust
        case .ink: LFColor.sunYellow
        case .seaGreen: LFColor.midnight
        case .violet: LFColor.lavender
        case .sunYellow: LFColor.deepRust
        }
    }

    static func from(_ token: String) -> TileStyle {
        TileStyle(rawValue: token) ?? .midnight
    }
}

/// タイルのシンボルプリセット。
enum TileSymbol: String, CaseIterable, Identifiable {
    case book
    case pen
    case wave
    case comet
    case sun
    case phoenix

    var id: String { rawValue }

    static func from(_ token: String) -> TileSymbol {
        TileSymbol(rawValue: token) ?? .book
    }
}

/// シンボルの描画。fg/bg を注入してどの配色でも成立させる(フラット塗りのみ)。
struct TileSymbolView: View {
    let symbol: TileSymbol
    let fg: Color
    let bg: Color

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let k = s / 200
            switch symbol {
            case .book:
                BookShape()
                    .fill(fg)
            case .pen:
                ZStack {
                    Capsule(style: .continuous)
                        .fill(fg)
                        .frame(width: 34 * k, height: 132 * k)
                        .offset(y: -16 * k)
                    PenTipShape()
                        .fill(fg)
                        .frame(width: 34 * k, height: 40 * k)
                        .offset(y: 62 * k)
                }
                .frame(width: s, height: s)
                .rotationEffect(.degrees(38))
            case .wave:
                WaveRiderShape()
                    .fill(fg)
            case .comet:
                ZStack(alignment: .topLeading) {
                    CometTailShape()
                        .fill(fg)
                    Circle()
                        .fill(fg)
                        .frame(width: 68 * k, height: 68 * k)
                        .offset(x: 30 * k, y: 102 * k)
                }
            case .sun:
                ZStack(alignment: .topLeading) {
                    MorningSunShape()
                        .fill(fg)
                    Capsule()
                        .fill(fg)
                        .frame(width: 156 * k, height: 12 * k)
                        .offset(x: 22 * k, y: 124 * k)
                }
            case .phoenix:
                ZStack(alignment: .topLeading) {
                    PhoenixShape()
                        .fill(fg)
                    Circle()
                        .fill(bg)
                        .frame(width: 16 * k, height: 16 * k)
                        .offset(x: (100 - 8) * k, y: 42 * k)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// 開いた本のシルエット。200x200の設計座標をrectに射影する。
struct BookShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 200 * rect.width,
                    y: rect.minY + y / 200 * rect.height)
        }
        var p = Path()
        p.move(to: pt(100, 52))
        p.addQuadCurve(to: pt(16, 38), control: pt(56, 24))    // 左ページ上端
        p.addLine(to: pt(16, 148))
        p.addQuadCurve(to: pt(100, 164), control: pt(56, 136)) // 左ページ下端
        p.addQuadCurve(to: pt(184, 148), control: pt(144, 136))// 右ページ下端
        p.addLine(to: pt(184, 38))
        p.addQuadCurve(to: pt(100, 52), control: pt(144, 24))  // 右ページ上端
        p.closeSubpath()
        // 中央の折り目(のど)を細く抜く
        p.move(to: pt(96, 54))
        p.addLine(to: pt(104, 54))
        p.addLine(to: pt(104, 160))
        p.addLine(to: pt(96, 160))
        p.closeSubpath()
        return p
    }
}

/// ペン先(台形+ペンポイント)。
struct PenTipShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// 項目タイルの絵柄部分。写真があれば写真、なければ配色+シンボル。
struct ItemTileArt: View {
    let item: StudyItem

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                if let data = item.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: s, height: s)
                } else {
                    let style = TileStyle.from(item.styleToken)
                    style.background
                    TileSymbolView(
                        symbol: TileSymbol.from(item.symbolToken),
                        fg: style.foreground,
                        bg: style.background
                    )
                    .frame(width: s * 0.62, height: s * 0.62)
                }
            }
            .frame(width: s, height: s)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
