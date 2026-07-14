import SwiftUI

/// タイプごとの抽象シンボル。フラット塗りのみ、グラデーション・影は使わない。
struct ArchetypeSymbol: View {
    let archetype: StudyArchetype
    var size: CGFloat = 150

    var body: some View {
        Group {
            switch archetype {
            case .phoenix:
                PhoenixSymbol()
            case .stoneBridge:
                StoneBridgeSymbol()
            case .waveRider:
                WaveRiderSymbol()
            case .comet:
                CometSymbol()
            case .morningCalm:
                MorningCalmSymbol()
            }
        }
        .frame(width: size, height: size)
    }
}

/// 不死鳥: 頭・両翼・二又の尾を持つ炎のシルエット。中央上部に目。
struct PhoenixSymbol: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 200
            ZStack(alignment: .topLeading) {
                PhoenixShape()
                    .fill(LFColor.coral)
                Circle()
                    .fill(LFColor.midnight)
                    .frame(width: 16 * s, height: 16 * s)
                    .offset(x: (100 - 8) * s, y: 42 * s)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// 不死鳥のシルエット。200x200の設計座標をrectに射影する。左右対称。
struct PhoenixShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 200 * rect.width,
                    y: rect.minY + y / 200 * rect.height)
        }
        var p = Path()
        // 頭の頂点から時計回り。谷は曲線上の点、先端は鋭角。
        p.move(to: pt(100, 12))
        p.addQuadCurve(to: pt(124, 54), control: pt(112, 28))   // 頭の右斜面
        p.addQuadCurve(to: pt(193, 98), control: pt(172, 58))   // 丸い肩から右翼の先端へ(凸)
        p.addQuadCurve(to: pt(127, 116), control: pt(150, 100)) // 翼の下側は深い凹
        p.addQuadCurve(to: pt(143, 192), control: pt(135, 150)) // 右尾の先端へ(外へ流す)
        p.addQuadCurve(to: pt(100, 148), control: pt(112, 162)) // 尾の間の谷
        p.addQuadCurve(to: pt(57, 192), control: pt(88, 162))   // 左尾の先端へ(外へ流す)
        p.addQuadCurve(to: pt(73, 116), control: pt(65, 150))   // 左尾から翼の下側へ
        p.addQuadCurve(to: pt(7, 98), control: pt(50, 100))     // 左翼の先端へ(深い凹)
        p.addQuadCurve(to: pt(76, 54), control: pt(28, 58))     // 左翼の上側、丸い肩
        p.addQuadCurve(to: pt(100, 12), control: pt(88, 28))    // 頭の左斜面
        p.closeSubpath()
        return p
    }
}

/// 石橋: 湾曲した橋桁と2本の橋脚。中央のアーチは背景色で抜く。
struct StoneBridgeSymbol: View {
    var body: some View {
        StoneBridgeShape()
            .fill(LFColor.seaGreen)
            .aspectRatio(1, contentMode: .fit)
    }
}

/// 石橋のシルエット。200x200の設計座標をrectに射影する。左右対称。
struct StoneBridgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 200 * rect.width,
                    y: rect.minY + y / 200 * rect.height)
        }
        var p = Path()
        // 桁の左端から時計回り。反った桁に3本の脚、2つのアーチを抜く(眼鏡橋)。左右対称。
        p.move(to: pt(6, 72))
        p.addQuadCurve(to: pt(194, 72), control: pt(100, 44))   // 桁の上面(太鼓橋の反り)
        p.addQuadCurve(to: pt(198, 160), control: pt(192, 116)) // 右端の脚の外側(裾を開く)
        p.addLine(to: pt(160, 160))                             // 右脚の底
        p.addLine(to: pt(160, 114))                             // 右脚の内側を上へ
        p.addQuadCurve(to: pt(136, 92), control: pt(158, 94))   // 右アーチ右半分(起拱は垂直に)
        p.addQuadCurve(to: pt(112, 114), control: pt(114, 94))  // 右アーチ左半分
        p.addLine(to: pt(112, 160))                             // 中央脚の右側面
        p.addLine(to: pt(88, 160))                              // 中央脚の底
        p.addLine(to: pt(88, 114))                              // 中央脚の左側面
        p.addQuadCurve(to: pt(64, 92), control: pt(86, 94))     // 左アーチ右半分
        p.addQuadCurve(to: pt(40, 114), control: pt(42, 94))    // 左アーチ左半分
        p.addLine(to: pt(40, 160))                              // 左脚の内側を下へ
        p.addLine(to: pt(2, 160))                               // 左脚の底
        p.addQuadCurve(to: pt(6, 72), control: pt(8, 116))      // 左端の脚の外側
        p.closeSubpath()
        return p
    }
}

/// 波乗り: 巻き込む一枚波。バレルの空洞が負の空間になる。
struct WaveRiderSymbol: View {
    var body: some View {
        WaveRiderShape()
            .fill(LFColor.lavender)
            .aspectRatio(1, contentMode: .fit)
    }
}

/// 巻き波のシルエット。200x200の設計座標をrectに射影する。
struct WaveRiderShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 200 * rect.width,
                    y: rect.minY + y / 200 * rect.height)
        }
        var p = Path()
        // 左下から時計回り。クレストは右へ大きく巻き込み、先端は鋭く垂れる。
        p.move(to: pt(12, 172))
        p.addQuadCurve(to: pt(70, 44), control: pt(46, 150))    // 波の背(登るほど急に)
        p.addQuadCurve(to: pt(150, 60), control: pt(120, 18))   // クレストの巻き上がり
        p.addQuadCurve(to: pt(132, 118), control: pt(164, 94))  // 巻きの先端へ(鋭く)
        p.addQuadCurve(to: pt(92, 72), control: pt(132, 80))    // バレルの天井へ戻る
        p.addQuadCurve(to: pt(190, 172), control: pt(104, 162)) // 波の面を滑り降りる
        p.closeSubpath()                                        // 底辺で閉じる
        return p
    }
}

/// 彗星: 丸い頭と、右上へ細く伸びる尾。
struct CometSymbol: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 200
            ZStack(alignment: .topLeading) {
                CometTailShape()
                    .fill(LFColor.returnOrange)
                Circle()
                    .fill(LFColor.sunYellow)
                    .frame(width: 68 * s, height: 68 * s)
                    .offset(x: 30 * s, y: 102 * s)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// 彗星の尾。頭の円(中心64,136 半径34)に接し、右上の先端へ細る。
struct CometTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 200 * rect.width,
                    y: rect.minY + y / 200 * rect.height)
        }
        var p = Path()
        p.move(to: pt(40, 112))                                 // 頭の左上の接点
        p.addQuadCurve(to: pt(186, 16), control: pt(92, 34))    // 尾の上縁(外へ弧を描く)
        p.addQuadCurve(to: pt(88, 160), control: pt(142, 92))   // 尾の下縁(内へ絞る)
        p.closeSubpath()                                        // 頭の円が重なって隠す
        return p
    }
}

/// 朝凪: 水平線に昇る半円の太陽と、静かな水面の線。
struct MorningCalmSymbol: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 200
            ZStack(alignment: .topLeading) {
                MorningSunShape()
                    .fill(LFColor.sunYellow)
                Capsule()
                    .fill(LFColor.lavender)
                    .frame(width: 184 * s, height: 12 * s)
                    .offset(x: 8 * s, y: 112 * s)               // 水平線
                Capsule()
                    .fill(LFColor.lavender)
                    .frame(width: 92 * s, height: 9 * s)
                    .offset(x: 54 * s, y: 140 * s)              // 凪の水面(中)
                Capsule()
                    .fill(LFColor.lavender)
                    .frame(width: 40 * s, height: 7 * s)
                    .offset(x: 80 * s, y: 164 * s)              // 凪の水面(小)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// 昇る太陽の半円(中心100,114 半径52 の上半分)。200x200の設計座標をrectに射影する。
struct MorningSunShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 200
        var p = Path()
        p.addArc(center: CGPoint(x: rect.minX + 100 * s, y: rect.minY + 114 * s),
                 radius: 52 * s,
                 startAngle: .degrees(180),
                 endAngle: .degrees(360),
                 clockwise: false)
        p.closeSubpath()
        return p
    }
}

#Preview {
    ZStack {
        LFColor.midnight
        VStack(spacing: 0) {
            ForEach(StudyArchetype.allCases, id: \.self) { archetype in
                ArchetypeSymbol(archetype: archetype, size: 130)
            }
        }
    }
    .frame(width: 390, height: 700)
}
