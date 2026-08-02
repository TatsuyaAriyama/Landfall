import AuthenticationServices
import SwiftData
import SwiftUI

/// 最新Web版と同じ3D航海を背景に使うサインインゲート。
struct SignInView: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isAnimating = false
    @State private var now = Date()

    /// Web SignInView の STARS と同じ位置・大きさ。
    private let stars: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
        (0.10, 0.16, 4), (0.24, 0.08, 3), (0.36, 0.20, 3),
        (0.52, 0.06, 4), (0.68, 0.14, 3), (0.83, 0.09, 4),
        (0.91, 0.24, 3), (0.17, 0.30, 2), (0.44, 0.12, 2),
        (0.60, 0.28, 2), (0.76, 0.18, 2)
    ]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let safeTop = max(geo.safeAreaInsets.top, windowSafeAreaTop)
            let compact = size.width <= 720
            let timeOfDay = webTimeOfDay(at: now)

            ZStack(alignment: .topLeading) {
                SignInVoyageSceneView(
                    timeOfDay: timeOfDay,
                    animate: !reduceMotion && scenePhase == .active
                )

                signInShade(compact: compact)

                Text(verbatim: "KeelMira")
                    .font(LFFont.copy(14))
                    .tracking(1)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .shadow(color: Color(hex: 0x041210).opacity(0.4), radius: 12, y: 1)
                    .padding(.leading, compact ? 22 : 32)
                    .padding(.top, max(compact ? 22 : 28, safeTop + 8))

                if compact {
                    VStack {
                        Spacer(minLength: 120)
                        signInPanel(for: size, compact: true)
                            .frame(width: min(390, size.width - 20))
                            .padding(.bottom, max(16, geo.safeAreaInsets.bottom))
                    }
                    .frame(width: size.width, height: size.height)
                } else {
                    HStack {
                        Spacer(minLength: 24)
                        signInPanel(for: size, compact: false)
                            .frame(
                                width: min(520, size.width - 48),
                                height: size.height - max(144, size.height * 0.18)
                            )
                            .padding(.trailing, min(132, max(28, size.width * 0.08)))
                    }
                    .frame(width: size.width, height: size.height)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .onReceive(
            Timer.publish(every: 60, on: .main, in: .common).autoconnect()
        ) { date in
            now = date
        }
    }

    private var windowSafeAreaTop: CGFloat {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first else {
            return 0
        }
        return window.safeAreaInsets.top
    }

    private func webTimeOfDay(at date: Date) -> AftideHomeTimeOfDay {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<10: .morning
        case 10..<17: .day
        case 17..<20: .evening
        default: .night
        }
    }

    private func signInShade(compact: Bool) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x071715).opacity(compact ? 0.02 : 0.04),
                    Color.clear,
                    Color(hex: 0x061211).opacity(compact ? 0.42 : 0.26)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [
                    Color(hex: 0x061211).opacity(compact ? 0.08 : 0.04),
                    Color.clear,
                    Color(hex: 0x061211).opacity(compact ? 0.08 : 0.34)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .allowsHitTesting(false)
    }

    private func signInPanel(for size: CGSize, compact: Bool) -> some View {
        VStack(spacing: 0) {
            if !compact {
                Spacer(minLength: 16)
            }

            AppIconArt(option: .harbor)
                .frame(width: compact ? 76 : 92, height: compact ? 76 : 92)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: compact ? 18 : 22,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: compact ? 18 : 22,
                        style: .continuous
                    )
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: Color(hex: 0x02110F).opacity(0.24), radius: 17, y: 8)
                .padding(.bottom, compact ? 22 : 28)

            Text("Sign in to enter the harbor.")
                .font(
                    LFFont.copy(
                        compact
                            ? min(20, max(15.5, size.width * 0.048))
                            : min(28, max(24, size.width * 0.022))
                    )
                )
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(hex: 0xF4F1EC))
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: compact ? 10 : 12) {
                SignInWithAppleButton(.continue) { request in
                    auth.startSignInWithAppleRequest(request)
                } onCompletion: { result in
                    Task { await auth.handleSignInWithAppleCompletion(result) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: compact ? 50 : 54)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Button {
                    Task { await auth.signInWithGoogle() }
                } label: {
                    HStack(spacing: 10) {
                        GoogleGlyph()
                            .frame(width: 18, height: 18)
                        Text("Continue with Google")
                            .font(LFFont.copy(16))
                            .fontWeight(.medium)
                            .foregroundStyle(Color(hex: 0x1F1F1F))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 50 : 54)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(SignInPressStyle())

                Button {
                    Task {
                        await LocalAccountData.prepareForLocalMode(
                            context: modelContext
                        )
                        auth.continueLocally()
                    }
                } label: {
                    Text("Continue without signing in")
                        .font(LFFont.label(13))
                        .foregroundStyle(Color(hex: 0xF4F1EC).opacity(0.72))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 40)
                }
                .buttonStyle(SignInPressStyle())
                .accessibilityHint(
                    Text("Records stay only on this device. Sync and harbors are unavailable.")
                )

                #if DEBUG
                if auth.canPreviewWithoutSignIn {
                    Button("Open simulator preview") {
                        auth.continueInSimulator()
                    }
                    .font(LFFont.label(11))
                    .foregroundStyle(Color(hex: 0xF4F1EC).opacity(0.4))
                    .buttonStyle(SignInPressStyle())
                }
                #endif

                Text("Your record syncs across your devices.")
                    .font(LFFont.label(11.5))
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(hex: 0xF4F1EC).opacity(0.42))
                    .padding(.top, 7)

                if auth.isWorking {
                    ProgressView("Signing in…")
                        .font(LFFont.label(13))
                        .tint(Color(hex: 0xF4F1EC))
                        .foregroundStyle(Color(hex: 0xF4F1EC).opacity(0.72))
                        .padding(.top, 8)
                }

                if let message = auth.errorMessage {
                    Text(verbatim: message)
                        .font(LFFont.label(14))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(LFColor.coral)
                        .padding(.top, 8)
                }
            }
            .padding(.top, compact ? 24 : 40)
            .disabled(auth.isWorking)
            .opacity(auth.isWorking ? 0.45 : 1)

            if !compact {
                Spacer(minLength: 16)
            }
        }
        .padding(.horizontal, compact ? 16 : 32)
        .padding(.top, compact ? 34 : 20)
        .padding(.bottom, compact ? 28 : 20)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color(hex: 0x0A2420).opacity(0.56))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(LFColor.harborSand.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Color(hex: 0x030F0E).opacity(0.22), radius: 40, y: 20)
    }

    private func starField(in size: CGSize) -> some View {
        ZStack {
            ForEach(Array(stars.enumerated()), id: \.offset) { index, star in
                Circle()
                    .fill(LFColor.harborSand)
                    .frame(width: star.size, height: star.size)
                    .opacity(isAnimating ? 0.42 : 0.14)
                    .position(x: size.width * star.x, y: size.height * star.y)
                    .animation(
                        reduceMotion ? nil :
                            .easeInOut(duration: 3.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index % 3) * 0.36),
                        value: isAnimating
                    )
            }
        }
    }

    private func moon(in size: CGSize) -> some View {
        let moonSize = min(56, max(40, size.width * 0.05))
        return ZStack {
            Circle()
                .fill(LFColor.harborSand.opacity(0.04))
                .frame(width: moonSize + 44, height: moonSize + 44)
            Circle()
                .fill(LFColor.harborSand.opacity(0.08))
                .frame(width: moonSize + 20, height: moonSize + 20)
            Circle()
                .fill(LFColor.harborSand)
                .opacity(isAnimating ? 0.92 : 0.78)
                .frame(width: moonSize, height: moonSize)
                .shadow(color: LFColor.harborSand.opacity(0.12), radius: 30)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 7).repeatForever(autoreverses: true),
                    value: isAnimating
                )
        }
        .position(
            x: size.width - size.width * 0.14 - moonSize / 2,
            y: size.height * 0.09 + moonSize / 2
        )
    }

    private func sea(in size: CGSize, height: CGFloat) -> some View {
        let top = size.height - height
        let horizonY = top + height * 0.40
        let boatWidth = min(88, max(60, size.width * 0.08))
        let boatHeight = boatWidth * 320 / 260
        let coastWidth = min(420, max(180, size.width * 0.34))
        let coastHeight = height * 0.34
        let moonPathWidth = min(86, max(52, size.width * 0.07))

        return ZStack {
            Rectangle()
                .fill(LFColor.harborSand.opacity(0.25))
                .frame(width: size.width, height: 2)
                .position(x: size.width / 2, y: horizonY)

            CoastShape()
                .fill(LFColor.harborSand)
                .frame(width: coastWidth, height: coastHeight)
                .position(
                    x: size.width - coastWidth / 2,
                    y: horizonY + 2 - coastHeight / 2
                )

            MoonPathShape()
                .fill(LFColor.harborSand.opacity(0.16))
                .frame(width: moonPathWidth, height: height * 0.58)
                .mask(
                    LinearGradient(
                        colors: [.black.opacity(0.9), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .position(
                    x: size.width * 0.86,
                    y: horizonY + height * 0.29
                )

            Capsule(style: .continuous)
                .fill(LFColor.harborSand.opacity(0.16))
                .frame(width: size.width * 0.22, height: 7)
                .position(x: size.width * 0.23, y: horizonY + 37.5)

            Capsule(style: .continuous)
                .fill(LFColor.harborSand.opacity(0.10))
                .frame(width: size.width * 0.10, height: 7)
                .position(x: size.width * 0.37, y: horizonY + 73.5)

            Capsule(style: .continuous)
                .fill(LFColor.harborSand.opacity(0.12))
                .frame(width: size.width * 0.15, height: 7)
                .position(x: size.width * 0.745, y: horizonY + 55.5)

            HarborSignInBoat()
                .frame(width: boatWidth, height: boatHeight)
                .rotationEffect(.degrees(isAnimating ? 1.2 : -1.2))
                .offset(y: isAnimating ? 2.5 : -2.5)
                .position(x: size.width * 0.24, y: horizonY + 2 - boatHeight / 2)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                    value: isAnimating
                )
        }
        .allowsHitTesting(false)
    }
}

private struct MoonPathShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.46, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.54, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.82, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SignInPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Web BoatSvg(260×320)の既定船。マスト・メインセイル・ジブ・船体を同じパスで描く。
private struct HarborSignInBoat: View {
    var body: some View {
        Canvas { context, size in
            let transform = CGAffineTransform(
                scaleX: size.width / 260,
                y: size.height / 320
            )
            let sand = GraphicsContext.Shading.color(LFColor.harborSand)

            let mast = Path(
                roundedRect: CGRect(x: 126, y: 26, width: 8, height: 200),
                cornerRadius: 4
            )
            context.fill(mast.applying(transform), with: sand)

            var mainSail = Path()
            mainSail.move(to: CGPoint(x: 140, y: 42))
            mainSail.addQuadCurve(
                to: CGPoint(x: 208, y: 220),
                control: CGPoint(x: 216, y: 124)
            )
            mainSail.addLine(to: CGPoint(x: 140, y: 220))
            mainSail.addQuadCurve(
                to: CGPoint(x: 140, y: 42),
                control: CGPoint(x: 149, y: 132)
            )
            mainSail.closeSubpath()
            context.fill(mainSail.applying(transform), with: sand)

            var jib = Path()
            jib.move(to: CGPoint(x: 118, y: 74))
            jib.addQuadCurve(
                to: CGPoint(x: 60, y: 222),
                control: CGPoint(x: 54, y: 152)
            )
            jib.addLine(to: CGPoint(x: 118, y: 222))
            jib.addQuadCurve(
                to: CGPoint(x: 118, y: 74),
                control: CGPoint(x: 111, y: 152)
            )
            jib.closeSubpath()
            context.fill(jib.applying(transform), with: sand)

            var hull = Path()
            hull.move(to: CGPoint(x: 26, y: 240))
            hull.addQuadCurve(
                to: CGPoint(x: 234, y: 240),
                control: CGPoint(x: 130, y: 230)
            )
            hull.addQuadCurve(
                to: CGPoint(x: 130, y: 300),
                control: CGPoint(x: 220, y: 294)
            )
            hull.addQuadCurve(
                to: CGPoint(x: 26, y: 240),
                control: CGPoint(x: 40, y: 294)
            )
            hull.closeSubpath()
            context.fill(hull.applying(transform), with: sand)
        }
        .accessibilityHidden(true)
    }
}

/// Google公式の4色G。Web版のSVGパス(48×48)をそのままSwiftUI Pathへ移植。
private struct GoogleGlyph: View {
    var body: some View {
        Canvas { context, size in
            let transform = CGAffineTransform(
                scaleX: size.width / 48,
                y: size.height / 48
            )

            context.fill(
                bluePath.applying(transform),
                with: .color(Color(hex: 0x4285F4))
            )
            context.fill(
                greenPath.applying(transform),
                with: .color(Color(hex: 0x34A853))
            )
            context.fill(
                yellowPath.applying(transform),
                with: .color(Color(hex: 0xFBBC05))
            )
            context.fill(
                redPath.applying(transform),
                with: .color(Color(hex: 0xEA4335))
            )
        }
        .accessibilityHidden(true)
    }

    private var bluePath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 45.12, y: 24.5))
        p.addCurve(
            to: CGPoint(x: 44.72, y: 20),
            control1: CGPoint(x: 45.12, y: 22.94),
            control2: CGPoint(x: 44.98, y: 21.44)
        )
        p.addLine(to: CGPoint(x: 24, y: 20))
        p.addLine(to: CGPoint(x: 24, y: 28.51))
        p.addLine(to: CGPoint(x: 35.84, y: 28.51))
        p.addCurve(
            to: CGPoint(x: 31.45, y: 35.15),
            control1: CGPoint(x: 35.33, y: 31.26),
            control2: CGPoint(x: 33.78, y: 33.59)
        )
        p.addLine(to: CGPoint(x: 31.45, y: 40.67))
        p.addLine(to: CGPoint(x: 38.56, y: 40.67))
        p.addCurve(
            to: CGPoint(x: 45.12, y: 24.5),
            control1: CGPoint(x: 42.72, y: 36.84),
            control2: CGPoint(x: 45.12, y: 31.2)
        )
        p.closeSubpath()
        return p
    }

    private var greenPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 24, y: 46))
        p.addCurve(
            to: CGPoint(x: 38.56, y: 40.67),
            control1: CGPoint(x: 29.94, y: 46),
            control2: CGPoint(x: 34.92, y: 44.03)
        )
        p.addLine(to: CGPoint(x: 31.45, y: 35.15))
        p.addCurve(
            to: CGPoint(x: 24, y: 37.25),
            control1: CGPoint(x: 29.48, y: 36.47),
            control2: CGPoint(x: 26.96, y: 37.25)
        )
        p.addCurve(
            to: CGPoint(x: 11.69, y: 28.18),
            control1: CGPoint(x: 18.27, y: 37.25),
            control2: CGPoint(x: 13.42, y: 33.38)
        )
        p.addLine(to: CGPoint(x: 4.34, y: 33.88))
        p.addCurve(
            to: CGPoint(x: 24, y: 46),
            control1: CGPoint(x: 7.96, y: 41.07),
            control2: CGPoint(x: 15.4, y: 46)
        )
        p.closeSubpath()
        return p
    }

    private var yellowPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 11.69, y: 28.18))
        p.addCurve(
            to: CGPoint(x: 11, y: 24),
            control1: CGPoint(x: 11.25, y: 26.86),
            control2: CGPoint(x: 11, y: 25.45)
        )
        p.addCurve(
            to: CGPoint(x: 11.69, y: 19.82),
            control1: CGPoint(x: 11, y: 22.55),
            control2: CGPoint(x: 11.25, y: 21.14)
        )
        p.addLine(to: CGPoint(x: 11.69, y: 14.12))
        p.addLine(to: CGPoint(x: 4.34, y: 14.12))
        p.addCurve(
            to: CGPoint(x: 2, y: 24),
            control1: CGPoint(x: 2.85, y: 17.09),
            control2: CGPoint(x: 2, y: 20.45)
        )
        p.addCurve(
            to: CGPoint(x: 4.34, y: 33.88),
            control1: CGPoint(x: 2, y: 27.55),
            control2: CGPoint(x: 2.85, y: 30.91)
        )
        p.addLine(to: CGPoint(x: 11.69, y: 28.18))
        p.closeSubpath()
        return p
    }

    private var redPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 24, y: 10.75))
        p.addCurve(
            to: CGPoint(x: 32.41, y: 14.04),
            control1: CGPoint(x: 27.23, y: 10.75),
            control2: CGPoint(x: 30.13, y: 11.86)
        )
        p.addLine(to: CGPoint(x: 38.72, y: 7.73))
        p.addCurve(
            to: CGPoint(x: 24, y: 2),
            control1: CGPoint(x: 34.91, y: 4.18),
            control2: CGPoint(x: 29.93, y: 2)
        )
        p.addCurve(
            to: CGPoint(x: 4.34, y: 14.12),
            control1: CGPoint(x: 15.4, y: 2),
            control2: CGPoint(x: 7.96, y: 6.93)
        )
        p.addLine(to: CGPoint(x: 11.69, y: 19.82))
        p.addCurve(
            to: CGPoint(x: 24, y: 10.75),
            control1: CGPoint(x: 13.42, y: 14.62),
            control2: CGPoint(x: 18.27, y: 10.75)
        )
        p.closeSubpath()
        return p
    }
}

#Preview {
    SignInView().environmentObject(AuthService.shared)
}
