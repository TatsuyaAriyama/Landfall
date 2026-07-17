import SwiftUI

/// 出航／着岸アニメーションの種別。
enum SailKind {
    case departure   // 出航: 計測開始
    case arrival     // 着岸: 記録(=航海を終えて陸に着く)
}

/// 出航・着岸アニメーションの制御。数秒だけ帆走を見せる。
/// アプリ全体で1つ。Reduce Motion 時は再生しない。
@MainActor
final class SailAnimator: ObservableObject {
    static let shared = SailAnimator()
    @Published var kind: SailKind?

    private init() {}

    var sailing: Bool { kind != nil }

    func play(_ kind: SailKind) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        guard self.kind == nil else { return }
        self.kind = kind
    }

    func finish() {
        kind = nil
    }
}

/// アイコン(LandfallShape)と同じ造形の帆船だけを切り出したシェイプ。
/// 元の1024座標系から船の範囲(x:215-405, y:386-737)を正規化して描く。
struct BoatShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + (x - 215) / 190 * rect.width,
                    y: rect.minY + (y - 386) / 351 * rect.height)
        }
        var p = Path()
        // 帆
        p.move(to: pt(318, 386))
        p.addQuadCurve(to: pt(404, 668), control: pt(376, 524))
        p.addLine(to: pt(302, 668))
        p.addQuadCurve(to: pt(318, 386), control: pt(300, 522))
        p.closeSubpath()
        // 船体
        p.move(to: pt(215, 650))
        p.addQuadCurve(to: pt(404, 700), control: pt(320, 646))
        p.addQuadCurve(to: pt(215, 650), control: pt(300, 778))
        p.closeSubpath()
        return p
    }
}

/// アイコンの陸地(丘)だけを切り出したシェイプ。着岸アニメーションの「陸」に使う。
struct CoastShape: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + (x - 430) / 422 * rect.width,
                    y: rect.minY + (y - 340) / 408 * rect.height)
        }
        var p = Path()
        p.move(to: pt(430, 748))
        p.addQuadCurve(to: pt(556, 386), control: pt(452, 512))
        p.addQuadCurve(to: pt(624, 386), control: pt(590, 350))
        p.addQuadCurve(to: pt(705, 612), control: pt(676, 486))
        p.addQuadCurve(to: pt(788, 524), control: pt(742, 548))
        p.addQuadCurve(to: pt(852, 748), control: pt(832, 642))
        p.addLine(to: pt(430, 748))
        p.closeSubpath()
        return p
    }
}

/// 数秒の帆走アニメーション。ティールの海を砂色の帆船が横切る。
/// - 出航(departure): 船が左から右へ抜けていく。「出航。」
/// - 着岸(arrival): 右手に陸が現れ、船が左から来て陸の手前で止まる。「着岸。」
/// フラット塗りのみ(グラデーション・影なし)。約2.6秒で自動的に消える。
struct SailingOverlay: View {
    let kind: SailKind

    @ObservedObject private var animator = SailAnimator.shared
    @State private var progress: CGFloat = 0
    @State private var bobbing = false
    @State private var fadingOut = false

    private let voyageDuration: Double = 2.2

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let seaLineY = h * 0.60
            // 船の到達点: 出航は画面外へ、着岸は陸の手前で止まる。
            let boatStartX: CGFloat = -140
            let boatEndX: CGFloat = kind == .arrival ? w * 0.46 : w + 140
            let boatX = boatStartX + (boatEndX - boatStartX) * progress

            ZStack {
                LFColor.harborTeal.ignoresSafeArea()

                // 凪の水面(朝凪と同じ言語: 細いカプセル)
                waveLine(width: w * 0.66, y: seaLineY, opacity: 0.30)
                waveLine(width: w * 0.38, y: h * 0.66, opacity: 0.22)
                waveLine(width: w * 0.22, y: h * 0.71, opacity: 0.16)

                // 着岸: 右手に陸(丘)。水面線に裾を合わせる。
                if kind == .arrival {
                    CoastShape()
                        .fill(LFColor.harborSand)
                        .frame(width: w * 0.52, height: h * 0.20)
                        .position(x: w * 0.90, y: seaLineY - h * 0.10)
                }

                // 帆船: わずかに上下に揺れる。揺れと横移動は別モディファイアに分ける
                // (同じoffsetを共有すると repeatForever が横移動まで乗っ取るため)。
                BoatShape()
                    .fill(LFColor.harborSand)
                    .frame(width: 96, height: 177)
                    .rotationEffect(.degrees(bobbing ? 1.6 : -1.6))
                    .offset(y: bobbing ? 3 : -3)
                    .position(x: boatX, y: h * 0.55)

                // ひとこと。断言調、句点つき。
                Text(kind == .arrival ? "Made landfall." : "Setting sail.")
                    .font(LFFont.copy(20))
                    .foregroundStyle(LFColor.harborSand)
                    .position(x: w / 2, y: h * 0.82)
            }
        }
        .opacity(fadingOut ? 0 : 1)
        .onAppear { start() }
    }

    private func waveLine(width: CGFloat, y: CGFloat, opacity: Double) -> some View {
        GeometryReader { geo in
            Capsule(style: .continuous)
                .fill(LFColor.harborSand.opacity(opacity))
                .frame(width: width, height: 8)
                .position(x: geo.size.width / 2, y: y)
        }
    }

    private func start() {
        Task { @MainActor in
            // 挿入直後の描画とアニメーション開始が同一トランザクションに
            // ならないよう、開始をわずかに遅らせる(遅らせないと即座に最終状態になる)。
            try? await Task.sleep(for: .milliseconds(80))
            // 着岸は陸の手前で減速して止まる(easeOut)、出航は等速で抜ける。
            let curve: Animation = kind == .arrival
                ? .easeOut(duration: voyageDuration)
                : .easeInOut(duration: voyageDuration)
            withAnimation(curve) {
                progress = 1
            }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                bobbing = true
            }
            try? await Task.sleep(for: .seconds(voyageDuration))
            withAnimation(.easeOut(duration: 0.4)) { fadingOut = true }
            try? await Task.sleep(for: .seconds(0.45))
            animator.finish()
        }
    }
}

#Preview("出航") { SailingOverlay(kind: .departure) }
#Preview("着岸") { SailingOverlay(kind: .arrival) }
