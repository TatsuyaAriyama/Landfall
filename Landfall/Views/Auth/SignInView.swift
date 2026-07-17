import AuthenticationServices
import SwiftUI

/// サインインゲート。アカウントがないと以降の画面には進めない。
/// 港の情景(ティールの海・帆船・海岸)で「サインイン=入港」を描く。
/// フラット塗りのみ・グラデーション/影なし。
struct SignInView: View {
    @EnvironmentObject private var auth: AuthService
    @State private var bobbing = false

    var body: some View {
        ZStack {
            LFColor.harborTeal.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                harborScene
                    .frame(height: 300)

                Text(verbatim: "Landfall-StudyLog")
                    .font(LFFont.copy(30))
                    .foregroundStyle(LFColor.harborSand)
                    .padding(.top, 36)

                Text("Sign in to enter the harbor.")
                    .font(LFFont.copy(17))
                    .foregroundStyle(LFColor.harborSand.opacity(0.9))
                    .padding(.top, 12)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Your record syncs across your devices.")
                    .font(LFFont.label(14))
                    .foregroundStyle(LFColor.harborSand.opacity(0.55))
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                VStack(spacing: 14) {
                    SignInWithAppleButton(.signIn) { request in
                        auth.startSignInWithAppleRequest(request)
                    } onCompletion: { result in
                        Task { await auth.handleSignInWithAppleCompletion(result) }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))

                    Button {
                        Task { await auth.signInWithGoogle() }
                    } label: {
                        HStack(spacing: 10) {
                            Text(verbatim: "G")
                                .font(LFFont.copy(18))
                            Text("Continue with Google")
                                .font(LFFont.copy(16))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundStyle(LFColor.harborTeal)
                        .background(LFColor.harborSand)
                        .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .disabled(auth.isWorking)
                .opacity(auth.isWorking ? 0.5 : 1)

                if let message = auth.errorMessage {
                    Text(verbatim: message)
                        .font(LFFont.label(14))
                        .foregroundStyle(LFColor.coral)
                        .padding(.top, 16)
                }
            }
            .padding(LFMetrics.cardPadding)
        }
        .onAppear {
            guard !UIAccessibility.isReduceMotionEnabled else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                bobbing = true
            }
        }
    }

    /// 港の情景。入港間際の帆船と、迎える海岸・灯りの水面。
    /// 着岸アニメーションの終景と同じ構図(=ここが港)。
    private var harborScene: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let seaLineY = h * 0.72

            ZStack {
                // 凪の水面
                Capsule(style: .continuous)
                    .fill(LFColor.harborSand.opacity(0.30))
                    .frame(width: w * 0.72, height: 8)
                    .position(x: w * 0.42, y: seaLineY)
                Capsule(style: .continuous)
                    .fill(LFColor.harborSand.opacity(0.20))
                    .frame(width: w * 0.40, height: 7)
                    .position(x: w * 0.36, y: seaLineY + h * 0.10)
                Capsule(style: .continuous)
                    .fill(LFColor.harborSand.opacity(0.13))
                    .frame(width: w * 0.22, height: 6)
                    .position(x: w * 0.44, y: seaLineY + h * 0.19)

                // 迎える海岸(右手)
                CoastShape()
                    .fill(LFColor.harborSand)
                    .frame(width: w * 0.52, height: h * 0.34)
                    .position(x: w * 0.87, y: seaLineY - h * 0.17)

                // 入港する帆船。静かに揺れる。
                BoatShape()
                    .fill(LFColor.harborSand)
                    .frame(width: 78, height: 144)
                    .rotationEffect(.degrees(bobbing ? 1.2 : -1.2))
                    .offset(y: bobbing ? 2.5 : -2.5)
                    .position(x: w * 0.40, y: seaLineY - 144 * 0.42)
            }
        }
    }
}

#Preview {
    SignInView().environmentObject(AuthService.shared)
}
