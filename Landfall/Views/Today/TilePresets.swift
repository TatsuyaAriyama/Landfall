import SwiftUI

/// 配色プリセット。背景と前景の組みを固定し、デザイン言語から外れない。
/// 前半6色は項目タイルとプレイヤーカードの共用、後半6色はプレイヤーカード専用
/// (`itemCases` / `allCases` で出し分ける。Web の TILE_STYLES / PROFILE_STYLES と同じ並び)。
enum TileStyle: String, CaseIterable, Identifiable {
    case midnight
    case coral
    case ink
    case seaGreen
    case violet
    case sunYellow
    case harbor
    case sand
    case ember
    case rust
    case lavender
    case sunrise

    var id: String { rawValue }

    /// 項目タイルで選べる配色。グリッドは一覧性が命なので、ここは意図的に増やさない。
    static let itemCases: [TileStyle] = [.midnight, .coral, .ink, .seaGreen, .violet, .sunYellow]

    var background: Color {
        switch self {
        case .midnight: LFColor.midnight
        case .coral: LFColor.coral
        case .ink: LFColor.tileInk
        case .seaGreen: LFColor.seaGreen
        case .violet: LFColor.violet
        case .sunYellow: LFColor.sunYellow
        case .harbor: LFColor.harborTeal
        case .sand: LFColor.harborSand
        case .ember: LFColor.emberGold
        case .rust: LFColor.deepRust
        case .lavender: LFColor.lavender
        case .sunrise: LFColor.returnOrange
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
        case .harbor: LFColor.harborSand
        case .sand: LFColor.deepRust
        case .ember: LFColor.deepRust
        case .rust: LFColor.emberGold
        case .lavender: LFColor.violet
        case .sunrise: LFColor.midnight
        }
    }

    static func from(_ token: String) -> TileStyle {
        TileStyle(rawValue: token) ?? .midnight
    }
}

/// PCCSのトーン。24色相と組み合わせ、`pccs-{tone}-{hue}` として同期する。
enum PCCSTone: String, CaseIterable, Identifiable {
    case vivid = "v"
    case bright = "b"
    case strong = "s"
    case deep = "dp"
    case light = "lt"
    case soft = "sf"
    case dull = "d"
    case dark = "dk"
    case pale = "p"
    case lightGrayish = "ltg"
    case grayish = "g"
    case darkGrayish = "dkg"

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .vivid: "Vivid"
        case .bright: "Bright"
        case .strong: "Strong"
        case .deep: "Deep"
        case .light: "PCCS Light"
        case .soft: "Soft"
        case .dull: "Dull"
        case .dark: "PCCS Dark"
        case .pale: "Pale"
        case .lightGrayish: "Light grayish"
        case .grayish: "Grayish"
        case .darkGrayish: "Dark grayish"
        }
    }

    var saturation: Double {
        switch self {
        case .vivid: 0.88
        case .bright, .strong: 0.72
        case .deep: 0.78
        case .light, .soft: 0.42
        case .dull: 0.45
        case .dark: 0.55
        case .pale, .lightGrayish: 0.22
        case .grayish: 0.25
        case .darkGrayish: 0.28
        }
    }

    var brightness: Double {
        switch self {
        case .vivid: 0.88
        case .bright, .light: 0.96
        case .strong, .soft, .lightGrayish: 0.78
        case .deep, .dull: 0.62
        case .dark: 0.42
        case .pale: 0.97
        case .grayish: 0.60
        case .darkGrayish: 0.40
        }
    }
}

struct PCCSSelection: Equatable {
    let tone: PCCSTone
    let hue: Int

    var token: String {
        "pccs-\(tone.rawValue)-\(String(format: "%02d", min(24, max(1, hue))))"
    }

    init(tone: PCCSTone, hue: Int) {
        self.tone = tone
        self.hue = min(24, max(1, hue))
    }

    init?(token: String) {
        let parts = token.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == "pccs",
              let tone = PCCSTone(rawValue: String(parts[1])),
              let hue = Int(parts[2]),
              (1...24).contains(hue) else { return nil }
        self.init(tone: tone, hue: hue)
    }
}

struct SeaColorSelection: Equatable {
    let hue: Double
    let saturation: Double
    let brightness: Double

    var token: String {
        let h = Int(((hue.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360).rounded())
        let s = Int((min(1, max(0, saturation)) * 100).rounded())
        let b = Int((min(1, max(0.18, brightness)) * 100).rounded())
        return String(format: "sea-%03d-%03d-%03d", h, s, b)
    }

    init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = ((hue.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360)
        self.saturation = min(1, max(0, saturation))
        self.brightness = min(1, max(0.18, brightness))
    }

    init?(token: String) {
        let parts = token.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 4,
              parts[0] == "sea",
              let hue = Double(parts[1]),
              let saturation = Double(parts[2]),
              let brightness = Double(parts[3]),
              hue >= 0, hue <= 359,
              saturation >= 0, saturation <= 100,
              brightness >= 18, brightness <= 100 else { return nil }
        self.init(hue: hue, saturation: saturation / 100, brightness: brightness / 100)
    }
}

enum SeaColorPalette {
    static func background(_ selection: SeaColorSelection) -> Color {
        Color(
            hue: selection.hue / 360,
            saturation: selection.saturation,
            brightness: selection.brightness
        )
    }

    static func foreground(_ selection: SeaColorSelection) -> Color {
        let chroma = selection.brightness * selection.saturation
        let section = selection.hue / 60
        let x = chroma * (1 - abs(section.truncatingRemainder(dividingBy: 2) - 1))
        let base: [Double]
        switch section {
        case ..<1: base = [chroma, x, 0]
        case ..<2: base = [x, chroma, 0]
        case ..<3: base = [0, chroma, x]
        case ..<4: base = [0, x, chroma]
        case ..<5: base = [x, 0, chroma]
        default: base = [chroma, 0, x]
        }
        let offset = selection.brightness - chroma
        let linear = base.map { channel -> Double in
            let value = channel + offset
            return value <= 0.04045
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        return luminance > 0.38 ? Color(hex: 0x141414) : Color(hex: 0xF4F1EC)
    }
}

/// PCCSの24色相をsRGB表示向けに近似した色。Webと同じ角度を使う。
enum PCCSPalette {
    static let hueDegrees: [Double] = [
        350, 5, 20, 35, 50, 60, 72, 88, 105, 125, 145, 165,
        180, 195, 210, 225, 240, 255, 270, 285, 300, 315, 330, 340,
    ]

    static func background(_ selection: PCCSSelection) -> Color {
        let degrees = hueDegrees[selection.hue - 1]
        return Color(
            hue: degrees / 360,
            saturation: selection.tone.saturation,
            brightness: selection.tone.brightness
        )
    }

    static func foreground(_ selection: PCCSSelection) -> Color {
        let rgb = rgbValues(selection)
        let linear = rgb.map { value -> Double in
            value <= 0.04045
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        return luminance > 0.38 ? Color(hex: 0x141414) : Color(hex: 0xF4F1EC)
    }

    static func nearest(to sea: SeaColorSelection) -> PCCSSelection {
        var best = PCCSSelection(tone: .vivid, hue: 1)
        var bestDistance = Double.greatestFiniteMagnitude
        for tone in PCCSTone.allCases {
            for hue in 1...24 {
                let degrees = hueDegrees[hue - 1]
                let rawHueDistance = abs(degrees - sea.hue)
                let hueDistance = min(rawHueDistance, 360 - rawHueDistance) / 180
                let distance =
                    pow(hueDistance, 2)
                    + pow(tone.saturation - sea.saturation, 2) * 0.7
                    + pow(tone.brightness - sea.brightness, 2) * 0.7
                if distance < bestDistance {
                    bestDistance = distance
                    best = PCCSSelection(tone: tone, hue: hue)
                }
            }
        }
        return best
    }

    private static func rgbValues(_ selection: PCCSSelection) -> [Double] {
        let hue = hueDegrees[selection.hue - 1]
        let saturation = selection.tone.saturation
        let value = selection.tone.brightness
        let chroma = value * saturation
        let section = hue / 60
        let x = chroma * (1 - abs(section.truncatingRemainder(dividingBy: 2) - 1))
        let base: [Double]
        switch section {
        case ..<1: base = [chroma, x, 0]
        case ..<2: base = [x, chroma, 0]
        case ..<3: base = [0, chroma, x]
        case ..<4: base = [0, x, chroma]
        case ..<5: base = [x, 0, chroma]
        default: base = [chroma, 0, x]
        }
        let offset = value - chroma
        return base.map { $0 + offset }
    }
}

/// 作業項目用の配色解決。プロフィール用のTileStyleは従来どおり固定プリセット。
struct ItemTileStyle {
    let token: String
    let background: Color
    let foreground: Color

    static func from(_ token: String) -> ItemTileStyle {
        if let selection = SeaColorSelection(token: token) {
            return ItemTileStyle(
                token: selection.token,
                background: SeaColorPalette.background(selection),
                foreground: SeaColorPalette.foreground(selection)
            )
        }
        if let selection = PCCSSelection(token: token) {
            return ItemTileStyle(
                token: selection.token,
                background: PCCSPalette.background(selection),
                foreground: PCCSPalette.foreground(selection)
            )
        }
        let legacy = TileStyle.from(token)
        return ItemTileStyle(
            token: legacy.rawValue,
            background: legacy.background,
            foreground: legacy.foreground
        )
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
    case sailboat    // 帆船(港)
    case attire      // 旗(装い)

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
            case .sailboat:
                SailboatShape().fill(fg)
            case .attire:
                AttireShape().fill(fg)
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

/// 帆船(港)。マスト+メインセイル+ジブ+三日月の船体。Web sailboat と同座標(200x200)。
struct SailboatShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 200 * rect.width, y: rect.minY + y / 200 * rect.height)
        }
        var p = Path()
        // マスト
        p.addRect(CGRect(x: pt(98, 34).x, y: pt(98, 34).y,
                         width: 4 / 200 * rect.width, height: 116 / 200 * rect.height))
        // メインセイル(左)
        p.move(to: pt(95, 40)); p.addLine(to: pt(95, 146)); p.addLine(to: pt(48, 146)); p.closeSubpath()
        // ジブ(右)
        p.move(to: pt(105, 56)); p.addLine(to: pt(105, 146)); p.addLine(to: pt(146, 146)); p.closeSubpath()
        // 船体(三日月)
        p.move(to: pt(30, 150)); p.addLine(to: pt(170, 150))
        p.addQuadCurve(to: pt(100, 180), control: pt(148, 178))
        p.addQuadCurve(to: pt(30, 150), control: pt(52, 178))
        p.closeSubpath()
        return p
    }
}

/// 装い。旗竿+燕尾ペナント。Web attire と同座標(200x200)。
struct AttireShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 200 * rect.width, y: rect.minY + y / 200 * rect.height)
        }
        var p = Path()
        // 旗竿
        p.addRoundedRect(in: CGRect(x: pt(52, 24).x, y: pt(52, 24).y,
                                    width: 11 / 200 * rect.width, height: 152 / 200 * rect.height),
                         cornerSize: CGSize(width: 5.5 / 200 * rect.width, height: 5.5 / 200 * rect.width))
        // 燕尾ペナント(はためく旗)
        p.move(to: pt(63, 34)); p.addLine(to: pt(150, 44)); p.addLine(to: pt(118, 63))
        p.addLine(to: pt(150, 82)); p.addLine(to: pt(63, 92)); p.closeSubpath()
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
                    let style = ItemTileStyle.from(item.styleToken)
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

/// 項目が削除された後も、記録時点の控えから同じ小さなタイルを再現する。
struct SessionTileArt: View {
    let session: StudySession

    var body: some View {
        if let item = session.item {
            ItemTileArt(item: item)
        } else {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let style = ItemTileStyle.from(session.displayItemStyle)
                ZStack {
                    style.background
                    TileSymbolView(
                        symbol: TileSymbol.from(session.displayItemSymbol),
                        fg: style.foreground,
                        bg: style.background
                    )
                    .frame(width: size * 0.62, height: size * 0.62)
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .aspectRatio(1, contentMode: .fit)
        }
    }
}
