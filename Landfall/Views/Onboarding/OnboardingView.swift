import SwiftUI

/// チュートリアルを更新したときは末尾の版だけを上げる。
/// 既存ユーザーにも、新しくなった案内を一度だけ見せられる。
enum TutorialState {
    static let completionKey = "tutorial.completed.v1"
    static var requiredNote: String { LF.text("Tutorial") }
}

/// ログイン後に一度だけ表示する、KeelMira の操作チュートリアル。
/// 航海世界を切らず、1ページにつき1つの操作だけを短く伝える。
struct OnboardingView: View {
    private let secondaryActionTitle: LocalizedStringKey?
    private let showsSceneBackground: Bool
    private let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var page = 0
    @State private var isAnimating = false

    private let pages = OnboardingPage.all

    private var shouldAnimate: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["LANDFALL_ONBOARD_STATIC"] == "1" { return false }
        #endif
        return !reduceMotion
    }

    init(
        secondaryActionTitle: LocalizedStringKey? = "Skip",
        showsSceneBackground: Bool = true,
        onDone: @escaping () -> Void
    ) {
        self.secondaryActionTitle = secondaryActionTitle
        self.showsSceneBackground = showsSceneBackground
        self.onDone = onDone
    }

    var body: some View {
        ZStack {
            if showsSceneBackground {
                SignInVoyageSceneView(timeOfDay: .night, date: .now, animate: shouldAnimate)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }

            LinearGradient(
                colors: [
                    Color(hex: 0x0A2521).opacity(0.38),
                    Color(hex: 0x0A2521).opacity(0.12),
                    Color(hex: 0x071E1B).opacity(0.86)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                header

                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        tutorialPage(pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                footer
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            #if DEBUG
            if let raw = ProcessInfo.processInfo.environment["LANDFALL_ONBOARD_PAGE"],
               let requested = Int(raw) {
                page = min(max(requested, 0), pages.count - 1)
            }
            #endif
            isAnimating = shouldAnimate
        }
        .onChange(of: reduceMotion) { _, _ in
            // 設定アプリやコントロールセンターから表示中に切り替えても、
            // DEBUGのSTATIC指定を含む単一の判定に即時追従する。
            isAnimating = shouldAnimate
        }
        .onChange(of: page) { oldValue, newValue in
            if oldValue != newValue { Haptics.tap(.light) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                TileSymbolView(
                    symbol: .compass,
                    fg: LFColor.harborSand,
                    bg: Color(hex: 0x173F3B)
                )
                .frame(width: 24, height: 24)

                Text(verbatim: "KeelMira")
                    .font(LFFont.label(16))
                    .tracking(1.4)
                    .foregroundStyle(LFColor.harborSand)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 12)

            if let secondaryActionTitle {
                Button(secondaryActionTitle) {
                    Haptics.tap(.light)
                    onDone()
                }
                .font(LFFont.label(15))
                .foregroundStyle(Color.white.opacity(0.74))
                .frame(minWidth: 56, minHeight: 44, alignment: .trailing)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func tutorialPage(_ item: OnboardingPage) -> some View {
        GeometryReader { geometry in
            if usesScrollablePage(availableHeight: geometry.size.height) {
                ScrollView(.vertical) {
                    tutorialPageContents(
                        item,
                        illustrationHeight: dynamicTypeSize.isAccessibilitySize ? 112 : 160,
                        usesSpacers: false
                    )
                }
                .scrollIndicators(.visible)
            } else {
                tutorialPageContents(item, illustrationHeight: 228, usesSpacers: true)
            }
        }
    }

    private func usesScrollablePage(availableHeight: CGFloat) -> Bool {
        dynamicTypeSize > .large || availableHeight < 500
    }

    private func tutorialPageContents(
        _ item: OnboardingPage,
        illustrationHeight: CGFloat,
        usesSpacers: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if usesSpacers { Spacer(minLength: 12) }

            TutorialIllustration(kind: item.kind, animate: isAnimating)
                .frame(maxWidth: 440)
                .frame(height: illustrationHeight)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            Text(item.eyebrow)
                .font(LFFont.label(12))
                .tracking(2.2)
                .foregroundStyle(LFColor.harborSand.opacity(0.72))
                .padding(.top, usesSpacers ? 28 : 16)

            Text(item.headline)
                .font(LFFont.copy(29))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)

            Text(item.subline)
                .font(LFFont.copy(16))
                .foregroundStyle(Color.white.opacity(0.7))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            if usesSpacers { Spacer(minLength: 14) }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, usesSpacers ? 0 : 10)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(spacing: 15) {
            HStack(spacing: 14) {
                Button {
                    guard page > 0 else { return }
                    withAnimation(.easeInOut(duration: 0.28)) { page -= 1 }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                        .font(LFFont.label(14))
                        .foregroundStyle(Color.white.opacity(0.76))
                        .frame(width: 82, alignment: .leading)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(page == 0 ? 0 : 1)
                .disabled(page == 0)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.14))
                        Capsule(style: .continuous)
                            .fill(LFColor.returnOrange)
                            .frame(width: geometry.size.width * CGFloat(page + 1) / CGFloat(pages.count))
                    }
                }
                .frame(height: 4)
                .animation(.easeInOut(duration: 0.28), value: page)

                Text(verbatim: "\(page + 1) / \(pages.count)")
                    .font(LFFont.label(13))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.58))
                    .frame(width: 48, alignment: .trailing)
                    .accessibilityLabel(Text("Step \(page + 1) of \(pages.count)"))
            }

            Button {
                if page < pages.count - 1 {
                    withAnimation(.easeInOut(duration: 0.28)) { page += 1 }
                } else {
                    Haptics.success()
                    onDone()
                }
            } label: {
                HStack(spacing: 10) {
                    Text(page < pages.count - 1 ? "Next" : "Set sail")
                    Image(systemName: page < pages.count - 1 ? "arrow.right" : "wind")
                        .font(.system(size: 15, weight: .semibold))
                }
                .font(LFFont.copy(18))
                .foregroundStyle(Color(hex: 0x173F3B))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 58)
                .padding(.vertical, 4)
                .background(LFColor.harborSand)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                .shadow(color: Color.black.opacity(0.16), radius: 18, y: 9)
            }
            .buttonStyle(LFPressableButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
}

private struct OnboardingPage {
    enum Kind {
        case welcome
        case destination
        case workItems
        case voyage
        case menu
        case returnHome
    }

    let kind: Kind
    let eyebrow: LocalizedStringKey
    let headline: LocalizedStringKey
    let subline: LocalizedStringKey

    static let all: [OnboardingPage] = [
        OnboardingPage(
            kind: .welcome,
            eyebrow: "WELCOME ABOARD",
            headline: "Your work becomes a voyage.",
            subline: "Choose what to do and set sail. The time you spend becomes your route."
        ),
        OnboardingPage(
            kind: .destination,
            eyebrow: "DESTINATION",
            headline: "Tap the sea to choose an island.",
            subline: "Give it a name and a date. Your destination draws nearer day by day."
        ),
        OnboardingPage(
            kind: .workItems,
            eyebrow: "WORK ITEMS",
            headline: "Tap to begin. Hold to rearrange.",
            subline: "Add work items with +. Each one keeps its own voyage record."
        ),
        OnboardingPage(
            kind: .voyage,
            eyebrow: "UNDER SAIL",
            headline: "Your time moves with the ship.",
            subline: "Make landfall when you finish, then leave a short note about the work."
        ),
        OnboardingPage(
            kind: .menu,
            eyebrow: "LOOK BACK & EXPLORE",
            headline: "Everything is close at hand.",
            subline: "Open Logbook, Harbor, Style, and Settings from the menu. Tap the date for Trace."
        ),
        OnboardingPage(
            kind: .returnHome,
            eyebrow: "YOUR VOYAGE, YOUR PACE",
            headline: "Even if it breaks, you can move forward again.",
            subline: "Motivation comes in waves. Still, keep the voyage going."
        )
    ]
}

// MARK: - Tutorial illustrations

private struct TutorialIllustration: View {
    let kind: OnboardingPage.Kind
    let animate: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(hex: 0x0D2F2A).opacity(0.78))
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(LFColor.harborSand.opacity(0.25), lineWidth: 1)

            switch kind {
            case .welcome:
                TutorialWelcomeArt(animate: animate)
            case .destination:
                TutorialDestinationArt(animate: animate)
            case .workItems:
                TutorialWorkItemsArt(animate: animate)
            case .voyage:
                TutorialVoyageArt(animate: animate)
            case .menu:
                TutorialMenuArt(animate: animate)
            case .returnHome:
                TutorialReturnArt(animate: animate)
            }
        }
        .padding(.horizontal, 1)
    }
}

private struct TutorialWelcomeArt: View {
    let animate: Bool

    var body: some View {
        ZStack {
            TutorialRouteShape()
                .stroke(
                    LFColor.harborSand.opacity(0.38),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 9])
                )
                .frame(width: 250, height: 104)
                .offset(y: 24)

            Circle()
                .fill(LFColor.returnOrange.opacity(0.14))
                .frame(width: animate ? 124 : 104, height: animate ? 124 : 104)
                .animation(
                    animate ? .easeInOut(duration: 1.8).repeatForever(autoreverses: true) : nil,
                    value: animate
                )

            TileSymbolView(symbol: .sailboat, fg: LFColor.harborSand, bg: .clear)
                .frame(width: 116, height: 116)
                .offset(y: animate ? -4 : 4)
                .animation(
                    animate ? .easeInOut(duration: 1.7).repeatForever(autoreverses: true) : nil,
                    value: animate
                )

            HStack(spacing: 46) {
                routeDot(size: 8, opacity: 0.38)
                routeDot(size: 11, opacity: 0.64)
                routeDot(size: 14, opacity: 1)
            }
            .offset(y: 74)
        }
    }

    private func routeDot(size: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(LFColor.returnOrange.opacity(opacity))
            .frame(width: size, height: size)
    }
}

private struct TutorialDestinationArt: View {
    let animate: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    TutorialWaveShape(phase: CGFloat(index) * 0.18)
                        .stroke(Color(hex: 0x79B6A8).opacity(0.2), lineWidth: 1)
                        .frame(height: 30)
                        .offset(y: CGFloat(index * 31 + 62))
                }

                Path { path in
                    path.move(to: CGPoint(x: geometry.size.width * 0.26, y: geometry.size.height * 0.70))
                    path.addQuadCurve(
                        to: CGPoint(x: geometry.size.width * 0.72, y: geometry.size.height * 0.30),
                        control: CGPoint(x: geometry.size.width * 0.54, y: geometry.size.height * 0.66)
                    )
                }
                .stroke(
                    LFColor.harborSand.opacity(0.55),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 8])
                )

                TileSymbolView(symbol: .sailboat, fg: LFColor.harborSand, bg: .clear)
                    .frame(width: 62, height: 62)
                    .position(x: geometry.size.width * 0.24, y: geometry.size.height * 0.70)
                    .rotationEffect(.degrees(-12))

                ZStack {
                    Circle()
                        .stroke(LFColor.returnOrange.opacity(0.5), lineWidth: 2)
                        .frame(width: animate ? 94 : 66, height: animate ? 94 : 66)
                        .opacity(animate ? 0.08 : 0.7)
                        .animation(
                            animate ? .easeOut(duration: 1.7).repeatForever(autoreverses: false) : nil,
                            value: animate
                        )
                    Circle()
                        .fill(LFColor.harborSand.opacity(0.1))
                        .frame(width: 72, height: 72)
                    TileSymbolView(symbol: .island, fg: LFColor.harborSand, bg: .clear)
                        .frame(width: 78, height: 78)
                }
                .position(x: geometry.size.width * 0.74, y: geometry.size.height * 0.28)

                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 25, weight: .regular))
                    .foregroundStyle(LFColor.returnOrange)
                    .position(x: geometry.size.width * 0.82, y: geometry.size.height * 0.57)
                    .offset(y: animate ? -5 : 4)
                    .animation(
                        animate ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : nil,
                        value: animate
                    )
            }
        }
        .padding(18)
    }
}

private struct TutorialWorkItemsArt: View {
    let animate: Bool
    private let tiles: [(TileStyle, TileSymbol)] = [
        (.midnight, .book), (.coral, .pen), (.seaGreen, .compass), (.sunYellow, .lighthouse)
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(tiles.indices, id: \.self) { index in
                    let tile = tiles[index]
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(tile.0.background)
                        .frame(height: 74)
                        .overlay {
                            TileSymbolView(symbol: tile.1, fg: tile.0.foreground, bg: tile.0.background)
                                .frame(width: 50, height: 50)
                        }
                        .offset(y: index == 1 && animate ? -5 : 0)
                        .shadow(
                            color: index == 1 ? Color.black.opacity(0.25) : .clear,
                            radius: 12,
                            y: 8
                        )
                        .animation(
                            animate ? .easeInOut(duration: 1.25).repeatForever(autoreverses: true) : nil,
                            value: animate
                        )
                }
            }
            .padding(.horizontal, 48)

            ZStack {
                Circle().fill(LFColor.harborSand)
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x173F3B))
            }
            .frame(width: 50, height: 50)
            .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
            .padding(.trailing, 28)
            .offset(y: 14)
        }
        .padding(.vertical, 26)
    }
}

private struct TutorialVoyageArt: View {
    let animate: Bool

    var body: some View {
        ZStack {
            VStack(spacing: 18) {
                HStack(spacing: 14) {
                    TileSymbolView(symbol: .sailboat, fg: LFColor.harborSand, bg: .clear)
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(animate ? 2 : -2))
                        .offset(y: animate ? -3 : 3)
                        .animation(
                            animate ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true) : nil,
                            value: animate
                        )

                    VStack(alignment: .leading, spacing: 7) {
                        Text(verbatim: "25:00")
                            .font(.system(size: 31, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                        HStack(spacing: 5) {
                            Circle().fill(LFColor.returnOrange).frame(width: 7, height: 7)
                            Text("Under sail")
                                .font(LFFont.label(12))
                                .tracking(1.2)
                                .foregroundStyle(Color.white.opacity(0.62))
                        }
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "flag.checkered")
                    Text("Make landfall")
                }
                .font(LFFont.label(14))
                .foregroundStyle(Color(hex: 0x173F3B))
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(LFColor.harborSand)
                .clipShape(Capsule(style: .continuous))
            }
        }
    }
}

private struct TutorialMenuArt: View {
    let animate: Bool
    private let items: [(LocalizedStringKey, TileSymbol)] = [
        ("Logbook", .book), ("Harbor", .lighthouse), ("Style", .sailboat), ("Settings", .wheel)
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)],
                spacing: 9
            ) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        TileSymbolView(
                            symbol: items[index].1,
                            fg: LFColor.harborSand,
                            bg: Color(hex: 0x173F3B)
                        )
                        .frame(width: 28, height: 28)
                        Text(items[index].0)
                            .font(LFFont.label(12))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 58)
                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))
                }
            }
            .padding(.horizontal, 34)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: 0x173F3B))
                .frame(width: 46, height: 46)
                .background(LFColor.harborSand, in: Circle())
                .scaleEffect(animate ? 1.04 : 0.94)
                .animation(
                    animate ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : nil,
                    value: animate
                )
                .offset(x: -19, y: -21)
        }
        .padding(.vertical, 38)
    }
}

private struct TutorialReturnArt: View {
    let animate: Bool

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Capsule().fill(LFColor.harborSand.opacity(0.7)).frame(width: 64, height: 4)
                Color.clear.frame(width: 44, height: 4)
                Capsule().fill(LFColor.harborSand.opacity(0.7)).frame(width: 64, height: 4)
            }
            .offset(y: 66)

            PhoenixShape()
                .fill(LFColor.returnOrange)
                .frame(width: 128, height: 128)
                .scaleEffect(animate ? 1.04 : 0.94)
                .offset(y: animate ? -5 : 3)
                .shadow(color: LFColor.returnOrange.opacity(0.24), radius: 22)
                .animation(
                    animate ? .easeInOut(duration: 1.8).repeatForever(autoreverses: true) : nil,
                    value: animate
                )

            Circle()
                .fill(LFColor.returnOrange)
                .frame(width: 13, height: 13)
                .offset(y: 66)
        }
    }
}

private struct TutorialRouteShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY * 0.76))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY * 0.42),
            control1: CGPoint(x: rect.maxX * 0.30, y: rect.maxY * 0.12),
            control2: CGPoint(x: rect.maxX * 0.65, y: rect.maxY * 1.08)
        )
        return path
    }
}

private struct TutorialWaveShape: Shape {
    let phase: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        let wavelength = max(rect.width / 3, 1)
        for x in stride(from: rect.minX, through: rect.maxX, by: 3) {
            let y = rect.midY + sin((x / wavelength + phase) * .pi * 2) * rect.height * 0.28
            path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

#Preview {
    OnboardingView(onDone: {})
}
