import SwiftUI
import UIKit

/// Bump only when a new opening should be offered to existing sailors once.
enum PrologueState {
    static let completionKey = "prologue.completed.v2"
}

/// The name written before authentication is deliberately staged outside the
/// synced profile. A returning account may already own a newer cloud name; the
/// pending value is adopted only after reconciliation proves the profile blank.
enum PrologueIdentity {
    private static let pendingNameKey = "prologue.pendingPlayerName.v2"

    static var pendingName: String {
        PlayerProfile.normalizedName(
            UserDefaults.standard.string(forKey: pendingNameKey) ?? ""
        )
    }

    static func stage(_ name: String) {
        let normalized = PlayerProfile.normalizedName(name)
        guard !normalized.isEmpty else { return }
        UserDefaults.standard.set(normalized, forKey: pendingNameKey)
    }

    /// Call only after local-account preparation or signed-in profile sync.
    /// Returns true when a profile was created and should be uploaded.
    @discardableResult
    static func adoptPendingNameIfProfileIsBlank() -> Bool {
        let pending = pendingName
        guard !pending.isEmpty else { return false }
        defer { UserDefaults.standard.removeObject(forKey: pendingNameKey) }
        guard PlayerProfile.name.isEmpty else { return false }
        PlayerProfile.save(
            name: pending,
            styleToken: PlayerProfile.styleToken,
            symbolToken: PlayerProfile.symbolToken,
            resolve: PlayerProfile.resolve
        )
        return true
    }
}

/// A short, interactive opening in the same SceneKit visual language as the
/// rest of KeelMira: lighthouse, shallow island, bottle, letter, then voyage.
struct ForgottenSeaPrologueView: View {
    enum Mode {
        case firstRun
        case replay
    }

    private enum Phase: Hashable {
        case lighthouse
        case bottle
        case letter

        var sceneStage: FirstLightPrologueSceneView.Stage {
            switch self {
            case .lighthouse: .lighthouse
            case .bottle: .bottle
            case .letter: .letter
            }
        }
    }

    private let mode: Mode
    private let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var nameFieldFocused: Bool
    @ScaledMetric(relativeTo: .body) private var letterTypeSize: CGFloat = 18

    @State private var phase: Phase = .lighthouse
    @State private var playerName = ""
    @State private var hasCompleted = false
    @State private var revealTask: Task<Void, Never>?
    @State private var typewriterTask: Task<Void, Never>?
    @State private var openingVisibleCharacterCount = 0
    @State private var bottleCueVisible = false

    init(mode: Mode = .firstRun, onComplete: @escaping () -> Void) {
        self.mode = mode
        self.onComplete = onComplete
    }

    private var isDebugStatic: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["LANDFALL_PROLOGUE_STATIC"] == "1"
        #else
        false
        #endif
    }

    private var shouldAnimateScene: Bool {
        !reduceMotion && !isDebugStatic && scenePhase == .active
    }

    private var normalizedName: String {
        PlayerProfile.normalizedName(playerName)
    }

    private var trimmedName: String {
        playerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameCharacterCount: Int {
        trimmedName.count
    }

    private var canSetSail: Bool {
        mode == .replay || (
            !trimmedName.isEmpty
                && nameCharacterCount <= PlayerProfile.nameCharacterLimit
        )
    }

    private var openingText: String {
        LF.text("Beyond the sea, there is nothing.\nIt ends before the horizon.")
    }

    private var visibleOpeningText: String {
        String(openingText.prefix(openingVisibleCharacterCount))
    }

    private var usesJapaneseTypography: Bool {
        locale.language.languageCode?.identifier == "ja"
    }

    /// SwiftUI's generic serif design falls back to a sans-serif face for
    /// Japanese. The prologue needs one coherent literary voice in both scripts.
    private func storyFont(_ size: CGFloat, emphasized: Bool = false) -> Font {
        if usesJapaneseTypography {
            let face = emphasized ? "HiraMinProN-W6" : "HiraMinProN-W3"
            if let font = UIFont(name: face, size: size) {
                return Font(font)
            }
        }
        return .system(
            size: size,
            weight: emphasized ? .medium : .regular,
            design: .serif
        )
    }

    var body: some View {
        ZStack {
            Color(hex: 0x071B1A)
                .ignoresSafeArea()

            FirstLightPrologueSceneView(
                stage: phase.sceneStage,
                animate: shouldAnimateScene,
                onBottleTapped: openLetter
            )
            .ignoresSafeArea()
            .accessibilityLabel(Text("A glowing bottle lies on the beach"))
            .accessibilityHidden(phase != .bottle)
            .accessibilityAction(named: Text("Open the letter")) {
                if phase == .bottle { openLetter() }
            }

            cinematicShade

            VStack(spacing: 0) {
                header

                Spacer(minLength: 24)

                if phase == .lighthouse {
                    openingCopy
                        .transition(.opacity.combined(with: .offset(y: 12)))
                } else if phase == .bottle, bottleCueVisible {
                    bottleCue
                        .transition(.opacity)
                } else if phase == .letter {
                    letter
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .move(edge: .bottom).combined(with: .opacity)
                        )
                }
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.72), value: phase)
        .onAppear(perform: resetForPresentation)
        .onDisappear(perform: stopPresentation)
        .task(id: phase) {
            guard phase == .bottle else { return }
            do {
                try await Task.sleep(for: .seconds(reduceMotion ? 0 : 3.6))
            } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.6)) {
                bottleCueVisible = true
            }
            if voiceOverEnabled {
                UIAccessibility.post(notification: .announcement,
                                     argument: LF.text("A glowing bottle lies on the beach"))
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                HomeWaveAmbience.shared.play()
                if phase == .lighthouse {
                    startOpeningTypewriterIfNeeded()
                    scheduleBottleReveal()
                }
            } else {
                revealTask?.cancel()
                revealTask = nil
                typewriterTask?.cancel()
                typewriterTask = nil
                HomeWaveAmbience.shared.stop()
            }
        }
    }

    private var cinematicShade: some View {
        LinearGradient(
            stops: [
                .init(color: Color(hex: 0x041312).opacity(0.52), location: 0),
                .init(color: .clear, location: 0.34),
                .init(color: .black.opacity(phase == .letter ? 0.46 : 0.18), location: 0.70),
                .init(color: Color(hex: 0x03100F).opacity(0.84), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(verbatim: "KEELMIRA  /  PROLOGUE")
                .font(LFFont.label(11))
                .tracking(2.4)
                .foregroundStyle(LFColor.harborSand.opacity(0.76))
                .accessibilityHidden(true)

            Spacer(minLength: 12)

            Button {
                Haptics.tap(.light)
                finish()
            } label: {
                Text("Skip")
                    .font(LFFont.label(15))
                    .foregroundStyle(Color.white.opacity(0.84))
                    .frame(minWidth: 64, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Skip the prologue"))
            .accessibilityHint(Text("Closes the prologue and continues to the next screen"))
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private var openingCopy: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle()
                .fill(Color(hex: 0xC7A968).opacity(0.72))
                .frame(width: 42, height: 1)

            Text(verbatim: openingText)
                .hidden()
                .overlay(alignment: .topLeading) {
                    Text(verbatim: visibleOpeningText)
                }
                .font(storyFont(20))
                .tracking(usesJapaneseTypography ? 0.05 : 0.45)
                .foregroundStyle(Color(hex: 0xF1E8CF))
                .lineSpacing(7)
                .multilineTextAlignment(.leading)
                .frame(minHeight: 62, alignment: .topLeading)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, alignment: .center)
        .shadow(color: .black.opacity(0.88), radius: 3, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: openingText))
        .accessibilityAddTraits(.isHeader)
    }

    private var bottleCue: some View {
        Button(action: openLetter) {
            VStack(spacing: 12) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 20, weight: .light))
                    .accessibilityHidden(true)
                Text("Open the letter")
                    .font(storyFont(16))
                    .tracking(1.2)
            }
            .foregroundStyle(Color(hex: 0xF1E8CF))
            .frame(minWidth: 160, minHeight: 80)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 42)
        .shadow(color: .black.opacity(0.8), radius: 6, y: 2)
    }

    private var letter: some View {
        VStack(spacing: 0) {
            ScrollView {
                letterPaper
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .clipped()

            departureControls
        }
    }

    private var letterPaper: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("A letter from beyond")
                .font(LFFont.label(12))
                .foregroundStyle(Color(hex: 0x69716F))
                .padding(.bottom, 30)

            VStack(alignment: .leading, spacing: 18) {
                Text("This island is not the whole world.")
                Text("Someone who knows you is waiting beyond.")
                Text("Write your name, and sail beyond the sea.")
            }
            .font(storyFont(letterTypeSize))
            .foregroundStyle(Color(hex: 0x303735))
            .lineSpacing(8)
            .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: "M.")
                .font(.system(size: letterTypeSize + 3, weight: .regular, design: .serif).italic())
                .foregroundStyle(Color(hex: 0x424A47))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 32)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 30)
        .frame(maxWidth: 460, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: 0xF2F4F1))
                .overlay {
                    ProloguePaperTexture()
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 8)
                .shadow(color: .black.opacity(0.16), radius: 2, x: 0, y: 1)
        }
    }

    /// Profile entry belongs to the app, not to the sender's stationery.
    private var departureControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            if mode == .firstRun {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Your name")
                            .font(LFFont.label(13))
                        Spacer()
                        Text(verbatim: "\(nameCharacterCount)/\(PlayerProfile.nameCharacterLimit)")
                            .font(LFFont.label(12))
                            .foregroundStyle(
                                nameCharacterCount > PlayerProfile.nameCharacterLimit
                                    ? LFColor.returnOrange : Color.white.opacity(0.6)
                            )
                            .accessibilityLabel(Text(verbatim: LF.format(
                                "%lld of %lld characters",
                                Int64(nameCharacterCount), Int64(PlayerProfile.nameCharacterLimit)
                            )))
                    }
                    .foregroundStyle(Color.white.opacity(0.82))

                    TextField("Sailor", text: $playerName)
                        .focused($nameFieldFocused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .font(LFFont.copy(18))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .tint(Color.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                        }
                        .accessibilityLabel(Text("Your name"))
                        .onSubmit {
                            if canSetSail { setSail() }
                        }
                }
            }

            Button(action: setSail) {
                HStack(spacing: 10) {
                    Text("Set sail")
                        .font(LFFont.copy(16))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .medium))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Color(hex: 0x243C35))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color(hex: 0xEFF2EE), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(LFPressableButtonStyle())
            .disabled(!canSetSail)
            .opacity(canSetSail ? 1 : 0.46)
            .accessibilityHint(Text("Closes the prologue and begins your voyage"))
        }
        .frame(maxWidth: 460)
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.48)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func resetForPresentation() {
        hasCompleted = false
        phase = .lighthouse
        bottleCueVisible = false
        openingVisibleCharacterCount = reduceMotion || voiceOverEnabled ? openingText.count : 0
        nameFieldFocused = false
        playerName = mode == .replay
            ? PlayerProfile.displayName
            : (PrologueIdentity.pendingName.isEmpty
                ? PlayerProfile.name
                : PrologueIdentity.pendingName)
        HomeWaveAmbience.shared.stop()
        HomeWaveAmbience.shared.play()
        startOpeningTypewriterIfNeeded()
        scheduleBottleReveal()
    }

    private func stopPresentation() {
        revealTask?.cancel()
        revealTask = nil
        typewriterTask?.cancel()
        typewriterTask = nil
        nameFieldFocused = false
        HomeWaveAmbience.shared.stop()
    }

    private func scheduleBottleReveal() {
        revealTask?.cancel()
        guard phase == .lighthouse, !isDebugStatic,
              openingVisibleCharacterCount == openingText.count else { return }
        revealTask = Task { @MainActor in
            do {
                // Hold the completed sentence, regardless of translation length.
                try await Task.sleep(for: .seconds(voiceOverEnabled ? 6.0 : 2.8))
            } catch {
                return
            }
            guard !Task.isCancelled, phase == .lighthouse else { return }
            withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.9)) {
                phase = .bottle
            }
            revealTask = nil
        }
    }

    private func startOpeningTypewriterIfNeeded() {
        typewriterTask?.cancel()
        typewriterTask = nil
        guard phase == .lighthouse else { return }
        guard !reduceMotion && !voiceOverEnabled else {
            openingVisibleCharacterCount = openingText.count
            scheduleBottleReveal()
            return
        }
        guard openingVisibleCharacterCount < openingText.count else { return }

        typewriterTask = Task { @MainActor in
            if openingVisibleCharacterCount == 0 {
                do {
                    try await Task.sleep(for: .milliseconds(700))
                } catch { return }
            }
            while !Task.isCancelled,
                  phase == .lighthouse,
                  openingVisibleCharacterCount < openingText.count {
                openingVisibleCharacterCount += 1
                let revealed = String(openingText.prefix(openingVisibleCharacterCount))
                let pause: Int
                switch revealed.last {
                case "。", ".": pause = 360
                case "、", ",": pause = 160
                case "\n": pause = 240
                default: pause = 52
                }
                do {
                    try await Task.sleep(for: .milliseconds(pause))
                } catch { return }
            }
            guard !Task.isCancelled else { return }
            typewriterTask = nil
            scheduleBottleReveal()
        }
    }

    private func openLetter() {
        guard phase == .bottle, !hasCompleted else { return }
        Haptics.tap(.medium)
        withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.72)) {
            phase = .letter
        }
    }

    private func setSail() {
        guard canSetSail, !hasCompleted else { return }
        if mode == .firstRun {
            PrologueIdentity.stage(normalizedName)
        }
        Haptics.success()
        finish()
    }

    private func finish() {
        guard !hasCompleted else { return }
        hasCompleted = true
        stopPresentation()
        onComplete()
    }
}

/// Neutral cotton-paper grain, kept away from the ink so glyph edges stay crisp.
private struct ProloguePaperTexture: View {
    var body: some View {
        Canvas { context, size in
            var state: UInt64 = 0x5041504552
            func sample() -> CGFloat {
                state = state &* 6_364_136_223_846_793_005 &+ 1
                return CGFloat(state >> 40) / CGFloat(1 << 24)
            }
            for _ in 0..<Int(size.width * size.height / 45) {
                let x = sample() * size.width
                let y = sample() * size.height
                let length = 0.5 + sample() * 1.5
                let grain = CGRect(x: x, y: y, width: length, height: 0.45)
                context.fill(Path(ellipseIn: grain),
                             with: .color(Color(hex: 0x52615A).opacity(0.055)))
            }

            // The paper was folded once; a shallow, irregular crease carries
            // the material without an ornamental frame or distressed edges.
            let foldY = size.height * 0.56
            var fold = Path()
            fold.move(to: CGPoint(x: 0, y: foldY + 0.5))
            fold.addQuadCurve(to: CGPoint(x: size.width, y: foldY - 0.5),
                              control: CGPoint(x: size.width * 0.45, y: foldY + 1.5))
            context.stroke(fold, with: .color(.black.opacity(0.035)), lineWidth: 0.7)
            context.translateBy(x: 0, y: 0.8)
            context.stroke(fold, with: .color(.white.opacity(0.55)), lineWidth: 0.6)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
