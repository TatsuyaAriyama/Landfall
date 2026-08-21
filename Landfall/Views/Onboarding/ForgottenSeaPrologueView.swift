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

    private enum Phase {
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

    @State private var phase: Phase = .lighthouse
    @State private var playerName = ""
    @State private var hasCompleted = false
    @State private var revealTask: Task<Void, Never>?
    @State private var typewriterTask: Task<Void, Never>?
    @State private var openingVisibleCharacterCount = 0

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

            Text(verbatim: visibleOpeningText)
                .font(storyFont(18))
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

    private var letter: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: 0x23483F))
                    Circle()
                        .stroke(Color(hex: 0xB69A5D), lineWidth: 1)
                        .padding(3)
                    Text(verbatim: "M")
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .foregroundStyle(Color(hex: 0xD6C28C))
                }
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

                Text("A letter from beyond")
                    .font(storyFont(11))
                    .tracking(2.1)
                    .textCase(.uppercase)
                Spacer()
            }
            .foregroundStyle(Color(hex: 0x31504A).opacity(0.76))

            HStack(spacing: 8) {
                Rectangle().frame(height: 1)
                Circle().frame(width: 4, height: 4)
                Rectangle().frame(height: 1)
            }
            .foregroundStyle(Color(hex: 0xA58C56).opacity(0.48))
            .padding(.top, 14)

            Text("This island is not the whole world.")
                .padding(.top, 20)
            Text("Someone who knows you is waiting beyond.")
                .padding(.top, 10)
            Text("Write your name, and sail beyond the sea.")
                .padding(.top, 10)

            Rectangle()
                .fill(Color(hex: 0xA58C56).opacity(0.34))
                .frame(height: 1)
                .padding(.vertical, 18)

            if mode == .firstRun {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your name")
                        .font(storyFont(10))
                        .tracking(1.8)
                        .textCase(.uppercase)
                        .foregroundStyle(Color(hex: 0x31504A).opacity(0.68))

                    TextField("Sailor", text: $playerName)
                        .focused($nameFieldFocused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .font(storyFont(20))
                        .foregroundStyle(Color(hex: 0x173F3B))
                        .padding(.horizontal, 2)
                        .frame(height: 42)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color(hex: 0x7D704B).opacity(0.54))
                                .frame(height: 1)
                        }
                        .onSubmit {
                            if canSetSail { setSail() }
                        }

                    Text(verbatim: "\(nameCharacterCount)/\(PlayerProfile.nameCharacterLimit)")
                        .font(storyFont(10))
                        .foregroundStyle(
                            nameCharacterCount > PlayerProfile.nameCharacterLimit
                                ? LFColor.returnOrange
                                : Color(hex: 0x31504A).opacity(0.54)
                        )
                        .accessibilityLabel(
                            Text(
                                verbatim: LF.format(
                                    "%lld of %lld characters",
                                    Int64(nameCharacterCount),
                                    Int64(PlayerProfile.nameCharacterLimit)
                                )
                            )
                        )
                }
            } else {
                Text(verbatim: PlayerProfile.displayName)
                    .font(storyFont(22))
                    .foregroundStyle(Color(hex: 0x173F3B))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: setSail) {
                Text("Set sail")
                    .font(storyFont(14, emphasized: true))
                    .tracking(1.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Color(hex: 0xEFE4C7))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .background(Color(hex: 0x23483F))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(hex: 0xB69A5D).opacity(0.72), lineWidth: 1)
                            .padding(3)
                    }
            }
            .buttonStyle(LFPressableButtonStyle())
            .disabled(!canSetSail)
            .opacity(canSetSail ? 1 : 0.46)
            .padding(.top, 18)
            .accessibilityHint(Text("Closes the prologue and begins your voyage"))
        }
        .font(storyFont(17))
        .foregroundStyle(Color(hex: 0x173F3B))
        .lineSpacing(5)
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .background {
            EstateLetterPaperShape(cut: 12)
                .fill(Color(hex: 0xE8DDBB).opacity(0.985))
                .overlay {
                    EstatePaperTexture()
                        .clipShape(EstateLetterPaperShape(cut: 12))
                }
                .overlay {
                    EstateLetterPaperShape(cut: 12)
                        .stroke(Color(hex: 0x8E7A4B).opacity(0.52), lineWidth: 1)
                        .padding(4)
                }
                .shadow(color: .black.opacity(0.46), radius: 18, y: 10)
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
    }

    private func resetForPresentation() {
        hasCompleted = false
        phase = .lighthouse
        openingVisibleCharacterCount = reduceMotion ? openingText.count : 0
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
        guard phase == .lighthouse, !isDebugStatic else { return }
        revealTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(reduceMotion ? 3.0 : 5.4))
            } catch {
                return
            }
            guard !Task.isCancelled, phase == .lighthouse else { return }
            withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.9)) {
                phase = .bottle
            }
            if voiceOverEnabled {
                UIAccessibility.post(
                    notification: .announcement,
                    argument: LF.text("A glowing bottle lies on the beach")
                )
            }
            revealTask = nil
        }
    }

    private func startOpeningTypewriterIfNeeded() {
        typewriterTask?.cancel()
        typewriterTask = nil
        guard phase == .lighthouse else { return }
        guard !reduceMotion else {
            openingVisibleCharacterCount = openingText.count
            return
        }
        guard openingVisibleCharacterCount < openingText.count else { return }

        typewriterTask = Task { @MainActor in
            if openingVisibleCharacterCount == 0 {
                try? await Task.sleep(for: .milliseconds(420))
            }
            while !Task.isCancelled,
                  phase == .lighthouse,
                  openingVisibleCharacterCount < openingText.count {
                openingVisibleCharacterCount += 1
                let revealed = String(openingText.prefix(openingVisibleCharacterCount))
                let pause: Int = revealed.last == "。" || revealed.last == "." ? 300 : 52
                try? await Task.sleep(for: .milliseconds(pause))
            }
            typewriterTask = nil
        }
    }

    private func openLetter() {
        guard phase == .bottle, !hasCompleted else { return }
        Haptics.tap(.medium)
        withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.72)) {
            phase = .letter
        }
        if mode == .firstRun {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 80 : 520))
                guard phase == .letter else { return }
                nameFieldFocused = true
            }
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

private struct EstateLetterPaperShape: InsettableShape {
    var cut: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let c = min(cut, min(r.width, r.height) * 0.12)
        var path = Path()
        path.move(to: CGPoint(x: r.minX + c, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        path.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY - c))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> EstateLetterPaperShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct EstatePaperTexture: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<34 {
                let x = size.width * CGFloat((index * 47 + 13) % 97) / 97
                let y = size.height * CGFloat((index * 31 + 7) % 89) / 89
                var fiber = Path()
                fiber.move(to: CGPoint(x: x, y: y))
                fiber.addLine(
                    to: CGPoint(
                        x: min(size.width, x + CGFloat(5 + index % 9)),
                        y: y + CGFloat((index % 3) - 1)
                    )
                )
                context.stroke(
                    fiber,
                    with: .color(Color(hex: 0x806E43).opacity(0.055)),
                    lineWidth: 0.65
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
