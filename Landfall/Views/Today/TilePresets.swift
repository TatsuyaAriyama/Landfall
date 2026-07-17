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
        case .ink: LFColor.tileInk
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

/// タイルのシンボルプリセット。航海の語彙(休む・進む・帰る・辿り着く・再生)+ 学びの本・ペン。
enum TileSymbol: String, CaseIterable, Identifiable {
    case anchor      // 停泊・休息
    case compass     // 方位・進む向き
    case wheel       // 舵を取る
    case lighthouse  // 帰る道の光
    case island      // 辿り着く陸(Landfall)
    case phoenix     // 再生・再開
    case book        // 読む
    case pen         // 書く

    var id: String { rawValue }

    static func from(_ token: String) -> TileSymbol {
        // 旧トークンの移行(波→錨・彗星→羅針盤・朝日→灯台)。既存データを壊さない。
        switch token {
        case "wave": return .anchor
        case "comet": return .compass
        case "sun": return .lighthouse
        default: return TileSymbol(rawValue: token) ?? .compass
        }
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
            case .anchor:
                AnchorSymbol(fg: fg)
            case .compass:
                CompassSymbol(fg: fg, bg: bg)
            case .wheel:
                WheelSymbol(fg: fg, bg: bg)
            case .lighthouse:
                LighthouseSymbol(fg: fg)
            case .island:
                IslandSymbol(fg: fg)
            case .phoenix:
                ZStack(alignment: .topLeading) {
                    PhoenixShape()
                        .fill(fg)
                    Circle()
                        .fill(bg)
                        .frame(width: 16 * k, height: 16 * k)
                        .offset(x: (100 - 8) * k, y: 42 * k)
                }
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
        p.addQuadCurve(to: pt(16, 38), control: pt(56, 24))
        p.addLine(to: pt(16, 148))
        p.addQuadCurve(to: pt(100, 164), control: pt(56, 136))
        p.addQuadCurve(to: pt(184, 148), control: pt(144, 136))
        p.addLine(to: pt(184, 38))
        p.addQuadCurve(to: pt(100, 52), control: pt(144, 24))
        p.closeSubpath()
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

// MARK: - 航海シンボル(錨・羅針盤・舵輪・灯台・島)

/// 舵輪。自分で舵を取る。スポーク(縁から突き出す持ち手)+リム+ハブ。
struct WheelSymbol: View {
    let fg: Color
    let bg: Color
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let k = s / 200
            ZStack {
                ForEach([0, 45, 90, 135], id: \.self) { angle in
                    Capsule().fill(fg).frame(width: 13 * k, height: 180 * k)
                        .rotationEffect(.degrees(Double(angle)))
                }
                Circle().stroke(fg, lineWidth: 13 * k).frame(width: 120 * k, height: 120 * k)
                Circle().fill(fg).frame(width: 40 * k, height: 40 * k)
                Circle().fill(bg).frame(width: 14 * k, height: 14 * k)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// 島。辿り着く陸(Landfall)。二つの丘+水面の線。
struct IslandSymbol: View {
    let fg: Color
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let k = s / 200
            ZStack {
                IslandShape().fill(fg)
                Capsule().fill(fg).frame(width: 120 * k, height: 10 * k).position(x: 100 * k, y: 170 * k)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// 島のシルエット(大小二つの丘)。200x200の設計座標をrectに射影する。
struct IslandShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 200 * rect.width, y: rect.minY + y / 200 * rect.height)
        }
        var path = Path()
        path.move(to: p(24, 150))
        path.addQuadCurve(to: p(84, 52), control: p(40, 86))
        path.addQuadCurve(to: p(120, 110), control: p(112, 66))
        path.addQuadCurve(to: p(150, 84), control: p(132, 88))
        path.addQuadCurve(to: p(176, 150), control: p(168, 120))
        path.addLine(to: p(24, 150))
        path.closeSubpath()
        return path
    }
}

/// 錨。停泊・休息の象徴。リング+竿+ストック+爪。
struct AnchorSymbol: View {
    let fg: Color
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let k = s / 200
            ZStack {
                Circle().stroke(fg, lineWidth: 11 * k)
                    .frame(width: 34 * k, height: 34 * k).position(x: 100 * k, y: 26 * k)
                Capsule().fill(fg).frame(width: 15 * k, height: 120 * k).position(x: 100 * k, y: 96 * k)
                Capsule().fill(fg).frame(width: 78 * k, height: 13 * k).position(x: 100 * k, y: 64 * k)
                AnchorArmsShape().fill(fg)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// 羅針盤。方位を探す。8方位のロゼッタ+外周リング+中心の抜き。
struct CompassSymbol: View {
    let fg: Color
    let bg: Color
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let k = s / 200
            ZStack {
                Circle().stroke(fg, lineWidth: 7 * k)
                    .frame(width: 172 * k, height: 172 * k).position(x: 100 * k, y: 100 * k)
                CompassRoseShape().fill(fg)
                Circle().fill(bg).frame(width: 20 * k, height: 20 * k).position(x: 100 * k, y: 100 * k)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// 灯台。帰る道を照らす光。塔+ギャラリー+灯室+屋根+光の一閃。
struct LighthouseSymbol: View {
    let fg: Color
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let k = s / 200
            ZStack {
                LighthouseShape().fill(fg)
                Capsule().fill(fg).frame(width: 70 * k, height: 14 * k).position(x: 100 * k, y: 178 * k)
                LighthouseRay().fill(fg).frame(width: 26 * k, height: 16 * k).position(x: 62 * k, y: 49 * k)
                LighthouseRay().fill(fg).rotationEffect(.degrees(180))
                    .frame(width: 26 * k, height: 16 * k).position(x: 138 * k, y: 49 * k)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// 錨の爪(下部の弧)。200x200の設計座標をrectに射影する。左右対称。
struct AnchorArmsShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 200 * rect.width, y: rect.minY + y / 200 * rect.height)
        }
        var path = Path()
        path.move(to: p(100, 180))
        path.addQuadCurve(to: p(30, 110), control: p(40, 178))
        path.addLine(to: p(50, 126))
        path.addQuadCurve(to: p(100, 152), control: p(74, 150))
        path.addQuadCurve(to: p(150, 126), control: p(126, 150))
        path.addLine(to: p(170, 110))
        path.addQuadCurve(to: p(100, 180), control: p(160, 178))
        path.closeSubpath()
        return path
    }
}

/// 羅針盤のロゼッタ。基本方位を長く、副方位を短く、8方向に伸ばす。
struct CompassRoseShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        func pt(_ ang: Double, _ r: CGFloat) -> CGPoint {
            CGPoint(x: c.x + CGFloat(cos(ang)) * r * s / 200,
                    y: c.y - CGFloat(sin(ang)) * r * s / 200)
        }
        var path = Path()
        for i in 0..<8 {
            let tipAng = Double(i) * .pi / 4
            let tipR: CGFloat = (i % 2 == 0) ? 70 : 40
            let valAng = tipAng + .pi / 8
            if i == 0 { path.move(to: pt(tipAng, tipR)) } else { path.addLine(to: pt(tipAng, tipR)) }
            path.addLine(to: pt(valAng, 15))
        }
        path.closeSubpath()
        return path
    }
}

/// 灯台の本体(塔+ギャラリー+灯室+屋根)。200x200の設計座標をrectに射影する。
struct LighthouseShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 200 * rect.width, y: rect.minY + y / 200 * rect.height)
        }
        var path = Path()
        path.move(to: p(74, 174)); path.addLine(to: p(87, 72)); path.addLine(to: p(113, 72)); path.addLine(to: p(126, 174)); path.closeSubpath()
        path.move(to: p(82, 72)); path.addLine(to: p(118, 72)); path.addLine(to: p(114, 58)); path.addLine(to: p(86, 58)); path.closeSubpath()
        path.move(to: p(89, 40)); path.addLine(to: p(113, 40)); path.addLine(to: p(113, 58)); path.addLine(to: p(89, 58)); path.closeSubpath()
        path.move(to: p(100, 22)); path.addLine(to: p(84, 42)); path.addLine(to: p(116, 42)); path.closeSubpath()
        return path
    }
}

/// 灯台の光(左右へ伸びる小さな三角)。
struct LighthouseRay: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
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
