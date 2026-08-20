import SwiftUI

/// 序章を更新したときは末尾の版だけを上げる。
/// 新しい序章を、既存ユーザーにも一度だけ見せられる。
enum PrologueState {
    static let completionKey = "prologue.completed.v1"
}

/// 初回起動で認証より先に流す、「忘却の海」の序章。
/// 背景はビートごとに進行する3Dシーンだけで構成し、静止画は使わない。
struct ForgottenSeaPrologueView: View {
    private struct Beat {
        /// 英語ソース文字列。表示のたびにアプリ内の言語設定で引き直す。
        let key: String
        let duration: TimeInterval

        var text: String { LF.text(key) }
    }

    /// 本文は英語をソース文字列(キー)にし、日本語は ja.lproj で与える。
    /// duration は日本語・英語のどちらでも読み切れる長さに合わせてある。
    private static let beats: [Beat] = [
        Beat(
            key: """
            Somewhere along the way, the sea began taking people's memories,
            and their names, their wishes, even the routes they once sailed sank into the fog.
            """,
            duration: 7.6
        ),
        Beat(
            key: """
            And so they gave this sea a name.
            They called it the Forgotten Sea.
            """,
            duration: 7.4
        ),
        Beat(
            key: """
            The stars went out, the lighthouse fires died,
            and no one looked for a new route anymore.
            """,
            duration: 8.1
        ),
        Beat(
            key: "Even so, not everything was lost.",
            duration: 7.0
        ),
        Beat(
            key: """
            You woke aboard an old ship, and in your hands was
            a logbook with nothing written in it yet,
            """,
            duration: 7.8
        ),
        Beat(
            key: "and a small flame that had not quite gone out.",
            duration: 8.0
        )
    ]

    private let onComplete: () -> Void
    private static let characterSeconds = 0.054
    /// 打ち終えてから次の場面までに残したい間。英語は文字数が多いので、
    /// 既定の速さでは間に合わない場面だけ自動で詰める(日本語は 54ms のまま)。
    private static let typingHeadroom = 0.34

    private static var launchBeat: Int {
        #if DEBUG
        if let rawValue = ProcessInfo.processInfo.environment["LANDFALL_PROLOGUE_BEAT"],
           let requestedBeat = Int(rawValue) {
            return min(max(requestedBeat, 0), beats.count - 1)
        }
        #endif
        return 0
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.scenePhase) private var scenePhase

    @State private var beat: Int
    @State private var showsFinalAction = false
    @State private var hasCompleted = false
    @State private var wasInterrupted = false
    @State private var autoAdvanceTask: Task<Void, Never>?
    @State private var typingTask: Task<Void, Never>?
    @State private var visibleCharacterCount = 0
    @AccessibilityFocusState private var storyHasAccessibilityFocus: Bool
    @AccessibilityFocusState private var finalActionHasAccessibilityFocus: Bool

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        _beat = State(initialValue: Self.launchBeat)
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

    private var shouldAutomaticallyAdvance: Bool {
        !voiceOverEnabled && !isDebugStatic && scenePhase == .active
    }

    private var currentStoryText: String {
        Self.beats[beat].text
    }

    /// 「場面 2 / 6」/ "Scene 2 of 6"。
    private var sceneProgressLabel: String {
        LF.format("Scene %lld of %lld", beat + 1, Self.beats.count)
    }

    private var visibleStoryText: String {
        String(currentStoryText.prefix(visibleCharacterCount))
    }

    private var isTyping: Bool {
        visibleCharacterCount < currentStoryText.count
    }

    var body: some View {
        ZStack {
            Color(hex: 0x03100F)
                .ignoresSafeArea()

            ForgottenSeaPrologueSceneView(beat: beat, animate: shouldAnimateScene)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            cinematicScrim

            Button(action: advance) {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            VStack(spacing: 0) {
                header

                Spacer(minLength: 32)

                VStack(spacing: 12) {
                    storyCopy
                    footer
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            resetForPresentation()
            focusStoryForVoiceOver()
            if scenePhase == .active {
                beginTyping()
                ForgottenSeaPrologueAudio.shared.restart()
                scheduleAutomaticAdvance()
            } else {
                wasInterrupted = true
            }
        }
        .onDisappear {
            cancelAutomaticAdvance()
            cancelTyping()
            ForgottenSeaPrologueAudio.shared.stop()
        }
        .onChange(of: beat) { _, _ in
            focusStoryForVoiceOver()
            beginTyping()
        }
        .onChange(of: voiceOverEnabled) { _, isEnabled in
            if isEnabled {
                cancelAutomaticAdvance()
                revealCurrentBeat()
                focusStoryForVoiceOver()
            } else {
                beginTyping()
                scheduleAutomaticAdvance()
            }
        }
        .onChange(of: reduceMotion) { _, isEnabled in
            if isEnabled {
                revealCurrentBeat()
            } else {
                beginTyping()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if wasInterrupted {
                    wasInterrupted = false
                    restartAfterInterruption()
                } else {
                    ForgottenSeaPrologueAudio.shared.play()
                }
                scheduleAutomaticAdvance()
            case .inactive, .background:
                wasInterrupted = true
                cancelAutomaticAdvance()
                cancelTyping()
                ForgottenSeaPrologueAudio.shared.stop()
            @unknown default:
                cancelAutomaticAdvance()
                cancelTyping()
                ForgottenSeaPrologueAudio.shared.stop()
            }
        }
    }

    private var cinematicScrim: some View {
        LinearGradient(
            stops: [
                .init(color: Color(hex: 0x061615).opacity(0.70), location: 0),
                .init(color: Color.black.opacity(0.08), location: 0.30),
                .init(color: Color.black.opacity(0.20), location: 0.56),
                .init(color: Color(hex: 0x061615).opacity(0.92), location: 1)
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
                .foregroundStyle(LFColor.harborSand.opacity(0.72))
                .accessibilityHidden(true)

            Spacer(minLength: 12)

            Button {
                Haptics.tap(.light)
                finish()
            } label: {
                Text("Skip")
                    .font(LFFont.label(15))
                    .foregroundStyle(Color.white.opacity(0.82))
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

    private var storyCopy: some View {
        ScrollView(.vertical) {
            ZStack(alignment: .topLeading) {
                // 全文でパネルの高さを先に確保し、タイプ中のレイアウトの揺れを防ぐ。
                Text(verbatim: currentStoryText)
                    .font(.system(.body, design: .serif, weight: .medium))
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(0)
                    .accessibilityHidden(true)

                Text(verbatim: visibleStoryText)
                    .id(beat)
                    .font(.system(.body, design: .serif, weight: .medium))
                    .foregroundStyle(Color.white)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: Color.black.opacity(0.95), radius: 3, y: 1)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 14)),
                                removal: .opacity.combined(with: .offset(y: -10))
                            )
                    )
                    .accessibilityLabel(Text(verbatim: currentStoryText))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($storyHasAccessibilityFocus)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: 0x03100F).opacity(0.91))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(LFColor.harborSand.opacity(0.42), lineWidth: 1.5)
                    }
                    .shadow(color: Color.black.opacity(0.46), radius: 14, y: 7)
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: 190)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
        .onTapGesture(perform: advance)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.95),
            value: beat
        )
    }

    private var footer: some View {
        VStack(spacing: 12) {
            progress

            if showsFinalAction {
                Button {
                    Haptics.success()
                    finish()
                } label: {
                    Text("Begin the voyage")
                        .font(LFFont.copy(18))
                        .foregroundStyle(Color(hex: 0x173F3B))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 58)
                        .padding(.vertical, 4)
                        .background(LFColor.harborSand)
                        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                }
                .buttonStyle(LFPressableButtonStyle())
                .accessibilityHint(Text("Closes the prologue and begins your voyage"))
                .accessibilityFocused($finalActionHasAccessibilityFocus)
                .transition(.opacity.combined(with: .offset(y: 10)))
            } else {
                Button(action: advance) {
                    HStack(spacing: 12) {
                        Text(beat == Self.beats.count - 1 ? "Onward" : "Tap to continue")
                            .font(LFFont.label(14))
                            .tracking(0.7)

                        Text(verbatim: "›")
                            .font(.system(size: 25, weight: .regular))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Color.white.opacity(0.78))
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(beat == Self.beats.count - 1 ? "Finish the last scene" : "Go to the next scene"))
                .accessibilityHint(Text(verbatim: sceneProgressLabel))
                .transition(.opacity)
            }
        }
        .frame(maxWidth: 430)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.55),
            value: showsFinalAction
        )
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(Self.beats.indices, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(
                        index <= beat
                            ? LFColor.harborSand.opacity(index == beat ? 0.92 : 0.48)
                            : Color.white.opacity(0.18)
                    )
                    .frame(width: index == beat ? 26 : 8, height: 3)
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.65),
            value: beat
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: sceneProgressLabel))
    }

    private func advance() {
        guard !hasCompleted, !showsFinalAction else { return }

        cancelAutomaticAdvance()
        Haptics.tap(.light)

        // 表示中のタップは文章を読み切るために使い、場面は送らない。
        if isTyping {
            revealCurrentBeat()
            scheduleAutomaticAdvance()
            return
        }

        if beat < Self.beats.count - 1 {
            if reduceMotion {
                beat += 1
            } else {
                withAnimation(.easeInOut(duration: 0.95)) {
                    beat += 1
                }
            }
            scheduleAutomaticAdvance()
        } else {
            if reduceMotion {
                showsFinalAction = true
            } else {
                withAnimation(.easeInOut(duration: 0.55)) {
                    showsFinalAction = true
                }
            }
            if voiceOverEnabled {
                Task { @MainActor in
                    await Task.yield()
                    storyHasAccessibilityFocus = false
                    finalActionHasAccessibilityFocus = true
                }
            }
        }
    }

    private func finish() {
        guard !hasCompleted else { return }
        hasCompleted = true
        cancelAutomaticAdvance()
        cancelTyping()
        ForgottenSeaPrologueAudio.shared.stop()
        onComplete()
    }

    /// fullScreenCoverが内部Viewを再利用しても、再生のたびに必ず序章の先頭へ戻す。
    private func resetForPresentation() {
        cancelAutomaticAdvance()
        cancelTyping()
        hasCompleted = false
        showsFinalAction = false
        wasInterrupted = false
        storyHasAccessibilityFocus = false
        finalActionHasAccessibilityFocus = false
        beat = Self.launchBeat
        visibleCharacterCount = 0
    }

    /// 映像・文章・音楽を同じ起点へ戻し、バックグラウンド復帰後も同期を保つ。
    private func restartAfterInterruption() {
        showsFinalAction = false
        let restartBeat = Self.launchBeat
        if reduceMotion {
            beat = restartBeat
        } else {
            withAnimation(.easeInOut(duration: 0.45)) { beat = restartBeat }
        }
        ForgottenSeaPrologueAudio.shared.restart()
        beginTyping()
        focusStoryForVoiceOver()
    }

    private func beginTyping() {
        cancelTyping()

        guard !reduceMotion,
              !voiceOverEnabled,
              !isDebugStatic,
              scenePhase == .active else {
            visibleCharacterCount = currentStoryText.count
            return
        }

        visibleCharacterCount = 0
        let typingBeat = beat
        let totalCharacters = currentStoryText.count
        guard totalCharacters > 0 else { return }
        let interval = Self.typingInterval(
            characters: totalCharacters,
            duration: Self.beats[beat].duration
        )
        typingTask = Task { @MainActor in
            for characterIndex in 1...totalCharacters {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }

                guard !Task.isCancelled, beat == typingBeat else { return }
                visibleCharacterCount = characterIndex
            }
            typingTask = nil
        }
    }

    /// 1文字あたりの間隔。場面が切り替わる前に打ち終わるところまでしか遅くしない。
    private static func typingInterval(characters: Int, duration: TimeInterval) -> Duration {
        let budget = duration * (1 - typingHeadroom)
        let perCharacter = budget / Double(characters)
        return .milliseconds(Int((min(characterSeconds, perCharacter) * 1000).rounded()))
    }

    private func revealCurrentBeat() {
        cancelTyping()
        visibleCharacterCount = currentStoryText.count
    }

    private func cancelTyping() {
        typingTask?.cancel()
        typingTask = nil
    }

    private func scheduleAutomaticAdvance() {
        cancelAutomaticAdvance()
        guard shouldAutomaticallyAdvance, !hasCompleted, !showsFinalAction else { return }

        let scheduledBeat = beat
        let delay = Self.beats[scheduledBeat].duration
        autoAdvanceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }

            guard !Task.isCancelled,
                  beat == scheduledBeat,
                  shouldAutomaticallyAdvance,
                  !hasCompleted,
                  !showsFinalAction else { return }

            autoAdvanceTask = nil
            advance()
        }
    }

    private func cancelAutomaticAdvance() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
    }

    private func focusStoryForVoiceOver() {
        guard voiceOverEnabled else { return }
        storyHasAccessibilityFocus = false
        Task { @MainActor in
            await Task.yield()
            storyHasAccessibilityFocus = true
        }
    }
}
