import SwiftUI

// アイコンは全面塗り(透過なし)・角丸なし(iOSがマスクする)。
// アプリのパレットと造形言語(フラット単色、グラデ・影なし)に従う。

/// 候補A: 不死鳥(hero symbol)。midnight地にcoralの不死鳥。
struct IconPhoenix: View {
    var body: some View {
        ZStack {
            LFColor.midnight
            PhoenixShape()
                .fill(LFColor.coral)
                .frame(width: 620, height: 620)
                .overlay(
                    Circle()
                        .fill(LFColor.midnight)
                        .frame(width: 52, height: 52)
                        .offset(x: 0, y: -150)
                )
        }
        .frame(width: 1024, height: 1024)
    }
}

/// 候補B: 帰還(landfall)。ink地に水平線(shore)と、着地するreturnOrangeの点。
struct IconReturn: View {
    var body: some View {
        ZStack {
            LFColor.ink
            // 水平線(岸)
            Capsule()
                .fill(LFColor.paper.opacity(0.9))
                .frame(width: 620, height: 20)
                .offset(y: 150)
            // 帰還の点(岸に降り立つ)
            Circle()
                .fill(LFColor.returnOrange)
                .frame(width: 210, height: 210)
                .offset(y: 20)
        }
        .frame(width: 1024, height: 1024)
    }
}

/// 候補C: スカイライン+帰還。ink地に当アプリの波形の一片とreturnOrangeの点。
struct IconSkyline: View {
    var body: some View {
        ZStack {
            LFColor.paper
            IconSkylineShape()
                .stroke(LFColor.ink, style: StrokeStyle(lineWidth: 26, lineCap: .round, lineJoin: .round))
                .frame(width: 640, height: 360)
            Circle()
                .fill(LFColor.returnOrange)
                .frame(width: 120, height: 120)
                .offset(x: 44, y: -70)
        }
        .frame(width: 1024, height: 1024)
    }
}

/// 候補D: coral地に不死鳥(明るい版)。
struct IconPhoenixCoral: View {
    var body: some View {
        ZStack {
            LFColor.coral
            PhoenixShape()
                .fill(LFColor.deepRust)
                .frame(width: 620, height: 620)
                .overlay(
                    Circle()
                        .fill(LFColor.coral)
                        .frame(width: 52, height: 52)
                        .offset(x: 0, y: -150)
                )
        }
        .frame(width: 1024, height: 1024)
    }
}

/// 候補Cの波形: 空白(平坦)→帰還(立ち上がり)→台地。
struct IconSkylineShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var p = Path()
        p.move(to: pt(0.0, 0.85))
        p.addLine(to: pt(0.30, 0.85))   // 空白(平坦)
        p.addLine(to: pt(0.30, 0.30))   // 帰還の立ち上がり
        p.addLine(to: pt(0.52, 0.30))
        p.addLine(to: pt(0.52, 0.15))   // 一段上へ
        p.addLine(to: pt(0.74, 0.15))
        p.addLine(to: pt(0.74, 0.40))
        p.addLine(to: pt(1.0, 0.40))
        return p
    }
}
