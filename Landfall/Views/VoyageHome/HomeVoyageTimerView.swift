import Combine
import SwiftData
import SwiftUI
import WidgetKit

extension StudyTimer {
    static let modeKey = KeelMiraWidgetStore.Key.timerMode
    static let pomodoroStartElapsedKey = KeelMiraWidgetStore.Key.pomodoroStartElapsed
    static let breakSecondsKey = KeelMiraWidgetStore.Key.breakSeconds
    static let breakStartedAtKey = KeelMiraWidgetStore.Key.breakStartedAt
    static let soundKey = KeelMiraWidgetStore.Key.sound

    static func begin(itemID: String, itemName: String, at date: Date = Date()) {
        KeelMiraWidgetStore.start(itemID: itemID, itemName: itemName, at: date)
        WidgetCenter.shared.reloadTimelines(ofKind: KeelMiraWidgetStore.widgetKind)
    }

    static func clearAll() {
        KeelMiraWidgetStore.clearTimer()
        WidgetCenter.shared.reloadTimelines(ofKind: KeelMiraWidgetStore.widgetKind)
    }
}

enum HomeTimerMode: String {
    case free
    case pomodoro
}

struct HomeTimerSnapshot {
    let startedAt: Double
    let mode: HomeTimerMode
    let pomodoroStartElapsed: Double
    let breakSeconds: Double
    let breakStartedAt: Double

    var isResting: Bool { breakStartedAt > 0 }

    func elapsedSeconds(at date: Date = Date()) -> Int {
        let now = date.timeIntervalSince1970
        let activeBreak = isResting ? max(0, now - breakStartedAt) : 0
        return max(0, Int(now - startedAt - breakSeconds - activeBreak))
    }

    func workedSeconds(at date: Date = Date()) -> Int {
        let elapsed = elapsedSeconds(at: date)
        guard mode == .pomodoro else { return elapsed }
        // ポモドーロを途中から始めても、それ以前の通常計測を失わない。
        let anchor = min(elapsed, max(0, Int(pomodoroStartElapsed)))
        let pomodoroElapsed = max(0, elapsed - anchor)
        let cycles = pomodoroElapsed / 1_800
        return anchor + cycles * 1_500 + min(pomodoroElapsed % 1_800, 1_500)
    }

    func creditedMinutes(at date: Date = Date(), minimum: Int = 1) -> Int {
        min(6_000, max(minimum, Int((Double(workedSeconds(at: date)) / 60).rounded())))
    }

    func phase(at date: Date = Date()) -> HomePomodoroPhase? {
        guard mode == .pomodoro else { return nil }
        // 通常の合計時計とは別に、オンにした瞬間から25:00を始める。
        // elapsedSecondsは手動休憩中に止まるため、こちらも同じ位置で自然に止まる。
        let elapsed = max(0, elapsedSeconds(at: date) - Int(pomodoroStartElapsed))
        let remainder = elapsed % 1_800
        let focusing = remainder < 1_500
        return HomePomodoroPhase(
            focusing: focusing,
            secondsLeft: focusing ? 1_500 - remainder : 1_800 - remainder
        )
    }
}

struct HomePomodoroPhase {
    let focusing: Bool
    let secondsLeft: Int
}

struct HomeManualRequest: Identifiable {
    let id = UUID()
    let item: StudyItem
    let initialMinutes: Int
}

struct HomeQuickTimerRecord: Identifiable {
    let id = UUID()
    let minutes: Int
}

private struct HomeVoyageCompletion {
    let minutes: Int
    let note: String?
}

@MainActor
private enum HomeVoyageRecorder {
    static func record(
        item: StudyItem,
        snapshot: HomeTimerSnapshot,
        note: String?,
        context: ModelContext
    ) throws -> HomeVoyageCompletion {
        let minutes = snapshot.creditedMinutes()
        let trimmed = String(
            (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)
        )
        let savedNote = trimmed.isEmpty ? nil : trimmed
        let date = Date()
        let session = StudySession(
            date: date,
            minutes: minutes,
            note: savedNote,
            item: item
        )

        context.insert(session)
        StudyDayStore.markDay(date, context: context)
        do {
            try context.save()
        } catch {
            context.delete(session)
            throw error
        }

        SyncService.shared.push(session)
        PublicHarborService.shared.publishCurrentMonth(context: context)
        WidgetBridge.refresh(context: context)
        let recorded = StudyDayStore.recordedToday(context: context)
        Task { await NotificationService.reschedule(recordedToday: recorded) }

        return HomeVoyageCompletion(minutes: minutes, note: savedNote)
    }
}

/// Web版の「航海中」をホーム専用に移植したタイマー。
/// 計測中の海を残したまま、完了時だけ航海札へ切り替える。
struct HomeVoyageTimerView: View {
    let item: StudyItem
    let hasDestination: Bool
    let onManual: (Int) -> Void
    let onReturnHome: () -> Void
    let rendersScene: Bool
    let externalWorldTapToken: Int
    /// 初回航海だけ、通常のメモ欄を使いながら指定の文言を必須にする。
    /// nil の通常航海では、従来どおり任意メモとして動作する。
    let firstVoyageRequiredNote: String?
    let onFirstVoyageRecorded: (() -> Void)?

    init(
        item: StudyItem,
        hasDestination: Bool,
        onManual: @escaping (Int) -> Void,
        onReturnHome: @escaping () -> Void,
        rendersScene: Bool = true,
        externalWorldTapToken: Int = 0,
        firstVoyageRequiredNote: String? = nil,
        onFirstVoyageRecorded: (() -> Void)? = nil
    ) {
        self.item = item
        self.hasDestination = hasDestination
        self.onManual = onManual
        self.onReturnHome = onReturnHome
        self.rendersScene = rendersScene
        self.externalWorldTapToken = externalWorldTapToken
        self.firstVoyageRequiredNote = firstVoyageRequiredNote
        self.onFirstVoyageRecorded = onFirstVoyageRecorded
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyDay.date, order: .reverse) private var days: [StudyDay]

    @AppStorage(StudyTimer.startKey, store: StudyTimer.defaults) private var timerStart: Double = 0
    @AppStorage(StudyTimer.itemKey, store: StudyTimer.defaults) private var timerItemID = ""
    @AppStorage(StudyTimer.modeKey, store: StudyTimer.defaults) private var timerMode = HomeTimerMode.free.rawValue
    @AppStorage(StudyTimer.pomodoroStartElapsedKey, store: StudyTimer.defaults) private var pomodoroStartElapsed: Double = 0
    @AppStorage(StudyTimer.breakSecondsKey, store: StudyTimer.defaults) private var breakSeconds: Double = 0
    @AppStorage(StudyTimer.breakStartedAtKey, store: StudyTimer.defaults) private var breakStartedAt: Double = 0
    @AppStorage(StudyTimer.soundKey, store: StudyTimer.defaults)
    private var soundMode = HomeVoyageSound.initialTimerSound.rawValue
    @ObservedObject private var voyageAudio = HomeVoyageAudio.shared

    @State private var note = ""
    @State private var completion: HomeVoyageCompletion?
    @State private var confirmingDiscard = false
    @State private var saveError = false
    @State private var saving = false
    @State private var uiHidden = false
    @State private var showingSoundPicker = false
    @State private var clockNow = Date()
    @FocusState private var noteFocused: Bool

    private let clockPulse = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var mode: HomeTimerMode {
        HomeTimerMode(rawValue: timerMode) ?? .free
    }

    private var snapshot: HomeTimerSnapshot {
        HomeTimerSnapshot(
            startedAt: timerStart,
            mode: mode,
            pomodoroStartElapsed: pomodoroStartElapsed,
            breakSeconds: breakSeconds,
            breakStartedAt: breakStartedAt
        )
    }

    private var pomodoroPhase: HomePomodoroPhase? {
        snapshot.phase(at: clockNow)
    }

    private var isVoyageResting: Bool {
        snapshot.isResting || pomodoroPhase?.focusing == false
    }

    private var timeOfDay: AftideHomeTimeOfDay {
        // The timer now sails through the same continuous day cycle as Home.
        // Its camera composition remains unchanged.
        .current(at: clockNow)
    }

    private var palette: AftideHomePalette {
        .voyagingNight
    }

    private var isFirstVoyage: Bool {
        firstVoyageRequiredNote != nil
    }

    private var normalizedNote: String {
        String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    }

    private var requiredNoteSatisfied: Bool {
        guard let firstVoyageRequiredNote else { return true }
        return normalizedNote == firstVoyageRequiredNote
    }

    private var notePlaceholder: String {
        firstVoyageRequiredNote ?? LF.text("What you worked on (optional)")
    }

    private var timerGlassInk: Color { LFColor.harborTeal }
    private var timerClockInk: Color { Color(hex: 0xA74312) }

    var body: some View {
        ZStack {
            if rendersScene {
                VoyagingHomeSceneView(
                    showIsland: hasDestination,
                    timeOfDay: timeOfDay,
                    date: clockNow,
                    resting: isVoyageResting,
                    elapsedSeconds: snapshot.elapsedSeconds(at: clockNow),
                    onTapWorld: toggleWorldUI
                )
                .ignoresSafeArea()
                .accessibilityLabel(Text("360° voyage view"))
                .accessibilityHint(Text("Drag to look around. Pinch to zoom. Double-tap to reset the view."))
            }

            if let completion {
                completionCard(completion)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            } else {
                voyageControls
                    .transition(.opacity)
                    .opacity(uiHidden ? 0 : 1)
                    .allowsHitTesting(!uiHidden)
                    .accessibilityHidden(uiHidden)
            }
        }
        .background(
            (rendersScene ? Color(hex: timeOfDay.palette.sky) : Color.clear)
                .ignoresSafeArea()
        )
        // Preserve the current timer controls/material appearance even when the
        // shared world is displaying a bright morning or daytime sea.
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.62, dampingFraction: 0.82), value: completion != nil)
        .confirmationDialog(
            "Discard this voyage?",
            isPresented: $confirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard voyage", role: .destructive) {
                StudyTimer.clearAll()
                HomeVoyageAudio.shared.stop()
                onReturnHome()
                Haptics.tap(.rigid)
            }
            Button("Keep sailing", role: .cancel) {}
        } message: {
            Text("The measured time will not be recorded.")
        }
        .alert("Could not save the voyage", isPresented: $saveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your timer is still running. Please try again.")
        }
        .onDisappear {
            noteFocused = false
            if timerItemID.isEmpty {
                HomeVoyageAudio.shared.stop()
            }
        }
        .onAppear {
            let migratedSound = HomeVoyageSound.resolve(soundMode)
            if migratedSound.rawValue != soundMode {
                soundMode = migratedSound.rawValue
            }
            if isVoyageResting {
                HomeVoyageAudio.shared.stop()
            } else {
                playVoyageAudio(migratedSound.rawValue)
            }
        }
        .onChange(of: soundMode) { _, value in
            if isVoyageResting {
                HomeVoyageAudio.shared.stop()
            } else {
                playVoyageAudio(value)
            }
        }
        .onReceive(clockPulse) { date in
            clockNow = date
        }
        .onChange(of: externalWorldTapToken) { _, _ in
            guard !rendersScene else { return }
            toggleWorldUI()
        }
    }

    private func toggleWorldUI() {
        guard completion == nil else { return }
        noteFocused = false
        withAnimation(.easeInOut(duration: 0.28)) {
            uiHidden.toggle()
        }
        Haptics.tap(.light)
    }

    private var voyageControls: some View {
        VStack(spacing: 0) {
            timerHeader
            Spacer(minLength: 18)
            recordingPanel
        }
        .padding(.horizontal, 16)
        .safeAreaPadding(.top, 12)
        .safeAreaPadding(.bottom, 10)
    }

    private var timerHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(timerGlassInk.opacity(0.07))
                    ItemTileArt(item: item)
                        .padding(5)
                }
                .frame(width: 36, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(timerGlassInk.opacity(0.14), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isVoyageResting ? LFColor.sunYellow : LFColor.returnOrange)
                            .frame(width: 5, height: 5)
                        Text(statusLabel)
                            .font(LFFont.label(9))
                            .tracking(1.1)
                    }
                    .foregroundStyle(timerGlassInk.opacity(0.66))

                    Text(item.name)
                        .font(LFFont.copy(13))
                        .foregroundStyle(timerGlassInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("ELAPSED")
                            .font(LFFont.label(7))
                            .tracking(1.2)
                            .foregroundStyle(timerGlassInk.opacity(0.48))
                        Text(Self.clock(snapshot.elapsedSeconds(at: context.date)))
                            .font(LFFont.copy(24))
                            .monospacedDigit()
                            .foregroundStyle(timerClockInk)
                            .contentTransition(.numericText())
                    }
                }

                if !isFirstVoyage {
                    Button {
                        confirmingDiscard = true
                        Haptics.tap(.rigid)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(timerGlassInk)
                            .frame(width: 32, height: 32)
                            .background(timerGlassInk.opacity(0.07), in: Circle())
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .accessibilityLabel(Text("Discard voyage"))
                }
            }
            .padding(.horizontal, 11)
            .padding(.top, 10)

            Rectangle()
                .fill(timerGlassInk.opacity(0.12))
                .frame(height: 1)
                .padding(.top, 8)

            HStack(spacing: 6) {
                commandButton(
                    title: snapshot.isResting ? "Resume voyage" : "Take a break",
                    detail: Text(snapshot.isResting ? "RESUME" : "BREAK"),
                    systemImage: snapshot.isResting ? "play.fill" : "pause.fill",
                    active: snapshot.isResting,
                    action: toggleBreak
                )

                commandButton(
                    title: "Pomodoro",
                    detail: pomodoroDetail,
                    systemImage: "timer",
                    active: mode == .pomodoro,
                    action: togglePomodoro
                )

                commandButton(
                    title: "BGM",
                    detail: Text(soundLabel),
                    systemImage: voyageAudio.playbackFailed
                        ? "exclamationmark.triangle.fill"
                        : "music.note",
                    active: showingSoundPicker || selectedSound != .off,
                    action: {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                            showingSoundPicker.toggle()
                        }
                        Haptics.tap(.light)
                    }
                )
                .accessibilityLabel(Text(soundAccessibilityLabel))
            }
            .padding(9)

            if showingSoundPicker {
                soundPicker
                    .padding(.horizontal, 9)
                    .padding(.bottom, 9)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: 560)
        .background(whiteGlassBackground(cornerRadius: 17, opacity: 0.80))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(timerGlassInk.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: timerGlassInk.opacity(0.16), radius: 13, y: 6)
    }

    private func commandButton(
        title: LocalizedStringKey,
        detail: Text,
        systemImage: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 2)
                    if active {
                        Circle()
                            .fill(LFColor.returnOrange)
                            .frame(width: 5, height: 5)
                    }
                }
                Text(title)
                    .font(LFFont.label(10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                detail
                    .font(LFFont.label(7))
                    .tracking(0.8)
                    .lineLimit(1)
                    .foregroundStyle(timerGlassInk.opacity(0.52))
            }
            .foregroundStyle(active ? timerGlassInk : timerGlassInk.opacity(0.74))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 57)
            .background(
                active ? LFColor.returnOrange.opacity(0.10) : timerGlassInk.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(
                        active
                            ? LFColor.returnOrange.opacity(0.52)
                            : timerGlassInk.opacity(0.11),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(LFPressableButtonStyle())
    }

    private var soundPicker: some View {
        VStack(spacing: 0) {
            HStack {
                Text("VOYAGE PLAYLIST")
                    .font(LFFont.label(8))
                    .tracking(1.4)
                Spacer()
                Text("SELECT TRACK")
                    .font(LFFont.label(7))
                    .tracking(1.2)
                    .foregroundStyle(timerGlassInk.opacity(0.46))
            }
            .foregroundStyle(timerGlassInk.opacity(0.68))
            .padding(.horizontal, 12)
            .frame(height: 28)

            ForEach(HomeVoyageSound.selectableSounds) { sound in
                Button {
                    selectSound(sound)
                } label: {
                    HStack(spacing: 12) {
                        HomeVoyageSoundIcon(
                            sound: sound,
                            selected: sound == displayedSound
                        )
                        .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(sound.title)
                                .font(LFFont.copy(12))
                            Text(sound.subtitle)
                                .font(LFFont.label(9))
                                .foregroundStyle(timerGlassInk.opacity(0.48))
                        }

                        Spacer(minLength: 8)

                        if sound == displayedSound {
                            Image(systemName: voyageAudio.isPlaying || sound == .off
                                ? "checkmark.circle.fill"
                                : "arrow.clockwise.circle")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(
                                    voyageAudio.playbackFailed
                                        ? LFColor.coral
                                        : LFColor.returnOrange
                                )
                        }
                    }
                    .foregroundStyle(timerGlassInk)
                    .padding(.horizontal, 12)
                    .frame(height: 43)
                    .background(
                        sound == displayedSound
                            ? timerGlassInk.opacity(0.07)
                            : Color.clear
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if sound != HomeVoyageSound.selectableSounds.last {
                    Rectangle()
                        .fill(timerGlassInk.opacity(0.09))
                        .frame(height: 1)
                        .padding(.leading, 48)
                }
            }
        }
        .background(Color.white.opacity(0.54), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(timerGlassInk.opacity(0.13), lineWidth: 1)
        )
    }

    private var recordingPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(timerGlassInk.opacity(0.62))

                TextField(
                    "",
                    text: $note,
                    prompt: Text(verbatim: notePlaceholder)
                        .foregroundStyle(timerGlassInk.opacity(0.48))
                )
                    .font(LFFont.label(14))
                    .foregroundStyle(timerGlassInk)
                    .tint(LFColor.returnOrange)
                    .focused($noteFocused)
                    .submitLabel(.done)
                    .onChange(of: note) { _, value in
                        if value.count > 120 {
                            note = String(value.prefix(120))
                        }
                    }
                    .accessibilityLabel(Text("What you worked on (optional)"))
                    .accessibilityHint(
                        Text(
                            verbatim: firstVoyageRequiredNote == nil
                                ? ""
                                : LF.text("Enter \"Tutorial\".")
                        )
                    )
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Color.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 11))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(timerGlassInk.opacity(0.12), lineWidth: 1)
            )

            Button {
                finishVoyage()
            } label: {
                HStack(spacing: 9) {
                    if saving {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Log up to here")
                        .font(LFFont.copy(16))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    timerGlassInk.opacity(requiredNoteSatisfied ? 0.96 : 0.38),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
            .buttonStyle(LFPressableButtonStyle())
            .disabled(saving || !requiredNoteSatisfied)
            .padding(.top, 9)

            if !isFirstVoyage {
                HStack {
                    Button {
                        let minutes = snapshot.creditedMinutes(minimum: 0)
                        StudyTimer.clearAll()
                        HomeVoyageAudio.shared.stop()
                        onManual(minutes)
                        Haptics.tap(.light)
                    } label: {
                        Text("Enter work time")
                            .font(LFFont.label(12))
                            .foregroundStyle(timerGlassInk.opacity(0.72))
                            .frame(minHeight: 34)
                    }
                    .buttonStyle(.plain)

                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 5)
        .frame(maxWidth: 460)
        .background(whiteGlassBackground(cornerRadius: 18, opacity: 0.82))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(timerGlassInk.opacity(0.17), lineWidth: 1)
        )
        .shadow(color: timerGlassInk.opacity(0.13), radius: 12, y: 5)
    }

    private func whiteGlassBackground(
        cornerRadius: CGFloat,
        opacity: Double
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(opacity))
        }
    }

    private var statusLabel: String {
        if snapshot.isResting { return LF.text("On break") }
        if pomodoroPhase?.focusing == false { return LF.text("Pomodoro break") }
        if pomodoroPhase?.focusing == true { return LF.text("Focus") }
        return LF.text("Voyaging")
    }

    private var pomodoroDetail: Text {
        guard let phase = pomodoroPhase else { return Text("OFF") }
        let title = phase.focusing ? LF.text("Focus") : LF.text("Pomodoro break")
        return Text("\(title) · \(Self.clock(phase.secondsLeft))")
    }

    private var selectedSound: HomeVoyageSound {
        HomeVoyageSound.resolve(soundMode)
    }

    /// 選択値ではなく、プレイリストで実際に鳴っている曲を表示する。
    /// 休憩中は再生が止まるため、再開予定の選択曲へ戻す。
    private var displayedSound: HomeVoyageSound {
        guard voyageAudio.isPlaying,
              voyageAudio.currentSound != .off
        else { return selectedSound }
        return voyageAudio.currentSound
    }

    private var soundLabel: String {
        switch displayedSound {
        case .off: LF.text("Sound off")
        case .waves: LF.text("Waves")
        case .harborMinuet: LF.text("Harbor Minuet")
        case .beaconRondo: LF.text("Beacon Rondo")
        case .celestialNocturne: LF.text("Celestial Navigation Nocturne")
        }
    }

    private var soundAccessibilityLabel: String {
        let state: String
        if displayedSound == .off {
            state = LF.text("Stopped")
        } else if voyageAudio.isPlaying {
            state = LF.text("Playing")
        } else {
            state = LF.text("Sound unavailable")
        }
        return LF.text("Sound") + ": " + soundLabel + ", " + state
    }

    private func selectSound(_ sound: HomeVoyageSound) {
        soundMode = sound.rawValue
        // 永続値の通知を待たず、選択した音へ即座に切り替える。
        if isVoyageResting {
            HomeVoyageAudio.shared.stop()
        } else {
            playVoyageAudio(sound.rawValue)
        }
        withAnimation(.easeOut(duration: 0.20)) {
            showingSoundPicker = false
        }
        Haptics.tap(.light)
    }

    private func togglePomodoro() {
        if mode == .free {
            pomodoroStartElapsed = Double(snapshot.elapsedSeconds())
            timerMode = HomeTimerMode.pomodoro.rawValue
        } else {
            timerMode = HomeTimerMode.free.rawValue
            pomodoroStartElapsed = 0
        }
        Haptics.tap(.light)
    }

    private func toggleBreak() {
        let now = Date().timeIntervalSince1970
        if breakStartedAt > 0 {
            breakSeconds += max(0, now - breakStartedAt)
            breakStartedAt = 0
            if isVoyageResting {
                HomeVoyageAudio.shared.stop()
            } else {
                playVoyageAudio(soundMode)
            }
        } else {
            breakStartedAt = now
            HomeVoyageAudio.shared.stop()
        }
        WidgetCenter.shared.reloadTimelines(ofKind: KeelMiraWidgetStore.widgetKind)
        Haptics.tap(.medium)
    }

    private func finishVoyage() {
        guard !saving,
              timerStart > 0,
              timerItemID == item.uuid.uuidString,
              requiredNoteSatisfied
        else { return }
        saving = true

        if isFirstVoyage {
            do {
                try TutorialFirstVoyageRecorder.record(
                    note: normalizedNote,
                    elapsedSeconds: snapshot.elapsedSeconds(at: clockNow),
                    context: modelContext
                )
            } catch {
                saving = false
                saveError = true
                return
            }

            StudyTimer.clearAll()
            HomeVoyageAudio.shared.stop()
            saving = false
            noteFocused = false
            Haptics.success()
            onFirstVoyageRecorded?()
            return
        }

        let result: HomeVoyageCompletion
        do {
            result = try HomeVoyageRecorder.record(
                item: item,
                snapshot: snapshot,
                note: note,
                context: modelContext
            )
        } catch {
            saving = false
            saveError = true
            return
        }

        StudyTimer.clearAll()
        HomeVoyageAudio.shared.stop()
        saving = false
        noteFocused = false
        completion = result
        Haptics.success()
    }

    private func playVoyageAudio(_ storedValue: String) {
        if isFirstVoyage {
            HomeVoyageAudio.shared.playLooping(storedValue)
        } else {
            HomeVoyageAudio.shared.play(storedValue)
        }
    }

    private func completionCard(_ result: HomeVoyageCompletion) -> some View {
        VStack {
            Spacer()

            VStack(spacing: 0) {
                Capsule()
                    .fill(LFColor.returnOrange)
                    .frame(width: 76, height: 3)
                    .padding(.bottom, 22)

                Text("VOYAGE RECORDED")
                    .font(LFFont.label(11))
                    .tracking(2)
                    .foregroundStyle(palette.inkColor.opacity(0.62))

                ItemTileArt(item: item)
                    .frame(width: 72, height: 72)
                    .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
                    .padding(.top, 18)

                Text("WORK ITEM")
                    .font(LFFont.label(10))
                    .tracking(1.5)
                    .foregroundStyle(palette.inkColor.opacity(0.48))
                    .padding(.top, 16)

                Text(item.name)
                    .font(LFFont.copy(item.name.count > 18 ? 23 : 29))
                    .foregroundStyle(palette.inkColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)

                if let note = result.note {
                    Text(note)
                        .font(LFFont.label(13))
                        .foregroundStyle(palette.inkColor.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.top, 10)
                }

                Text(LF.duration(minutes: result.minutes))
                    .font(LFFont.label(12))
                    .tracking(0.5)
                    .foregroundStyle(LFColor.returnOrange)
                    .monospacedDigit()
                    .padding(.top, 12)

                Button {
                    onReturnHome()
                    Haptics.tap(.light)
                } label: {
                    Text("Return home")
                        .font(LFFont.copy(16))
                        .foregroundStyle(palette.glassColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(palette.inkColor, in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(LFPressableButtonStyle())
                .padding(.top, 22)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 25)
            .frame(maxWidth: 430)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(palette.inkColor.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 36, y: 18)
        }
        .padding(.horizontal, 16)
        .safeAreaPadding(.bottom, 16)
    }

    static func clock(_ seconds: Int) -> String {
        let value = max(0, seconds)
        let hours = value / 3_600
        let minutes = (value % 3_600) / 60
        let remainder = value % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }
}

/// 全画面を閉じている間も航海が続いていることを示す、ホーム専用チップ。
struct HomeVoyageTimerChip: View {
    let item: StudyItem
    let onOpen: () -> Void
    let onRecorded: (Int) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyDay.date, order: .reverse) private var days: [StudyDay]
    @AppStorage(StudyTimer.startKey, store: StudyTimer.defaults) private var timerStart: Double = 0
    @AppStorage(StudyTimer.itemKey, store: StudyTimer.defaults) private var timerItemID = ""
    @AppStorage(StudyTimer.modeKey, store: StudyTimer.defaults) private var timerMode = HomeTimerMode.free.rawValue
    @AppStorage(StudyTimer.pomodoroStartElapsedKey, store: StudyTimer.defaults) private var pomodoroStartElapsed: Double = 0
    @AppStorage(StudyTimer.breakSecondsKey, store: StudyTimer.defaults) private var breakSeconds: Double = 0
    @AppStorage(StudyTimer.breakStartedAtKey, store: StudyTimer.defaults) private var breakStartedAt: Double = 0
    @AppStorage(StudyTimer.soundKey, store: StudyTimer.defaults)
    private var soundMode = HomeVoyageSound.initialTimerSound.rawValue
    @State private var saving = false
    @State private var saveError = false
    @State private var clockNow = Date()

    private let clockPulse = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var snapshot: HomeTimerSnapshot {
        HomeTimerSnapshot(
            startedAt: timerStart,
            mode: HomeTimerMode(rawValue: timerMode) ?? .free,
            pomodoroStartElapsed: pomodoroStartElapsed,
            breakSeconds: breakSeconds,
            breakStartedAt: breakStartedAt
        )
    }

    private var currentPhase: HomePomodoroPhase? {
        snapshot.phase(at: clockNow)
    }

    private var isEffectivelyResting: Bool {
        snapshot.isResting || currentPhase?.focusing == false
    }

    var body: some View {
        VStack(spacing: 9) {
            Button(action: onOpen) {
                HStack(spacing: 11) {
                    ItemTileArt(item: item)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Group {
                            if isEffectivelyResting {
                                Text(chipStatusLabel)
                            } else {
                                Label(chipStatusLabel, systemImage: "record.circle")
                            }
                        }
                        .font(LFFont.label(10))
                        .foregroundStyle(LFColor.returnOrange)
                        Text(item.name)
                            .font(LFFont.label(12))
                            .lineLimit(1)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let current = snapshot
                            let phase = current.phase(at: context.date)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(HomeVoyageTimerView.clock(
                                    current.elapsedSeconds(at: context.date)
                                ))
                                .font(LFFont.copy(18))
                                .monospacedDigit()
                                .foregroundStyle(LFColor.returnOrange)
                                if let phase { phaseLabel(phase) }
                            }
                        }
                    }
                    Spacer(minLength: 6)
                    Label("Details", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                        .font(LFFont.label(11))
                        .foregroundStyle(LFColor.harborSand.opacity(0.74))
                }
                .foregroundStyle(LFColor.harborSand)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Open timer details and add a note"))

            HStack(spacing: 8) {
                Button {
                    toggleBreak()
                } label: {
                    Label(
                        snapshot.isResting ? "Resume" : "Pause",
                        systemImage: snapshot.isResting ? "play.fill" : "pause.fill"
                    )
                    .font(LFFont.label(12))
                    .foregroundStyle(LFColor.harborSand)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(LFColor.harborSand.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(LFPressableButtonStyle())

                Button {
                    finishAndRecord()
                } label: {
                    HStack(spacing: 7) {
                        if saving {
                            ProgressView()
                                .tint(LFColor.paper)
                        } else {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text("End and record")
                            .font(LFFont.copy(12))
                    }
                    .foregroundStyle(LFColor.paper)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(LFColor.returnOrange, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(LFPressableButtonStyle())
                .disabled(saving)
            }
        }
        .padding(11)
        .background(
            LFColor.harborTeal.opacity(0.97),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(LFColor.harborSand.opacity(0.24), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .accessibilityElement(children: .contain)
        .onAppear {
            if isEffectivelyResting {
                HomeVoyageAudio.shared.stop()
            } else {
                HomeVoyageAudio.shared.play(soundMode)
            }
        }
        .onReceive(clockPulse) { date in
            clockNow = date
        }
        .alert("Could not save the voyage", isPresented: $saveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your timer is still running. Please try again.")
        }
    }

    @ViewBuilder
    private func phaseLabel(_ phase: HomePomodoroPhase) -> some View {
        Text(
            "\(phase.focusing ? LF.text("Focus") : LF.text("Pomodoro break")) · \(HomeVoyageTimerView.clock(phase.secondsLeft))"
        )
        .font(LFFont.label(9))
        .foregroundStyle(LFColor.harborSand.opacity(0.72))
        .monospacedDigit()
    }

    private var chipStatusLabel: LocalizedStringKey {
        if snapshot.isResting { return "Timer paused" }
        if currentPhase?.focusing == false { return "Pomodoro break" }
        return "Timer running"
    }

    private func toggleBreak() {
        let now = Date().timeIntervalSince1970
        if breakStartedAt > 0 {
            breakSeconds += max(0, now - breakStartedAt)
            breakStartedAt = 0
            if isEffectivelyResting {
                HomeVoyageAudio.shared.stop()
            } else {
                HomeVoyageAudio.shared.play(soundMode)
            }
        } else {
            breakStartedAt = now
            HomeVoyageAudio.shared.stop()
        }
        WidgetCenter.shared.reloadTimelines(ofKind: KeelMiraWidgetStore.widgetKind)
        Haptics.tap(.medium)
    }

    private func finishAndRecord() {
        guard !saving,
              timerStart > 0,
              timerItemID == item.uuid.uuidString
        else { return }
        saving = true

        let result: HomeVoyageCompletion
        do {
            result = try HomeVoyageRecorder.record(
                item: item,
                snapshot: snapshot,
                note: nil,
                context: modelContext
            )
        } catch {
            saving = false
            saveError = true
            return
        }

        StudyTimer.clearAll()
        HomeVoyageAudio.shared.stop()
        saving = false
        Haptics.success()
        onRecorded(result.minutes)
    }
}

/// タイマーから手入力へ切り替えたときの加算式入力。
/// Web版と同じく「+30分」を2回押すと1時間になる。
struct HomeManualTimeSheet: View {
    let item: StudyItem
    let initialMinutes: Int
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyDay.date, order: .reverse) private var days: [StudyDay]

    @State private var minutes: Int
    @State private var note = ""
    @State private var recordDate = Date()
    @FocusState private var noteFocused: Bool

    init(item: StudyItem, initialMinutes: Int, onSaved: @escaping () -> Void) {
        self.item = item
        self.initialMinutes = initialMinutes
        self.onSaved = onSaved
        _minutes = State(initialValue: min(6_000, max(0, initialMinutes)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 12) {
                        ItemTileArt(item: item)
                            .frame(width: 48, height: 48)
                        Text(item.name)
                            .font(LFFont.copy(19))
                            .foregroundStyle(LFColor.ink)
                            .lineLimit(2)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(minutes)")
                            .font(LFFont.number(46))
                            .foregroundStyle(LFColor.ink)
                            .contentTransition(.numericText())
                        Text("min")
                            .font(LFFont.label(14))
                            .foregroundStyle(LFColor.ink.opacity(0.50))
                    }
                    .frame(maxWidth: .infinity)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 4),
                        spacing: 9
                    ) {
                        ForEach([5, 15, 30, 60], id: \.self) { value in
                            Button {
                                minutes = min(6_000, minutes + value)
                                Haptics.tap(.light)
                            } label: {
                                Text("+\(value)")
                                    .font(LFFont.label(15))
                                    .monospacedDigit()
                                    .foregroundStyle(LFColor.ink)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .overlay(
                                        Capsule().stroke(LFColor.ink.opacity(0.22), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(LFPressableButtonStyle())
                        }
                    }

                    Stepper(value: $minutes, in: 0...6_000, step: 5) {
                        Text("Fine tune in 5-minute steps")
                            .font(LFFont.label(13))
                            .foregroundStyle(LFColor.ink.opacity(0.58))
                    }

                    Button {
                        minutes = 0
                    } label: {
                        Text("Reset")
                            .font(LFFont.label(13))
                            .foregroundStyle(LFColor.coral)
                    }
                    .buttonStyle(.plain)

                    DatePicker(
                        "Date",
                        selection: $recordDate,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .font(LFFont.label(14))

                    TextField("What you worked on (optional)", text: $note)
                        .font(LFFont.label(15))
                        .focused($noteFocused)
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(LFColor.ink.opacity(0.18), lineWidth: 1)
                        )

                    Button {
                        save()
                    } label: {
                        Text("Log this voyage")
                            .font(LFFont.copy(17))
                            .foregroundStyle(LFColor.paper)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                minutes > 0 ? LFColor.ink : LFColor.ink.opacity(0.28),
                                in: RoundedRectangle(cornerRadius: 17)
                            )
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .disabled(minutes <= 0)
                }
                .padding(20)
            }
            .background(LFColor.paper)
            .navigationTitle("Enter work time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard minutes > 0 else { return }
        let date = recordDate
        let trimmed = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        let session = StudySession(
            date: date,
            minutes: minutes,
            note: trimmed.isEmpty ? nil : trimmed,
            item: item
        )
        modelContext.insert(session)
        StudyDayStore.markDay(date, context: modelContext)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(session)
            return
        }
        SyncService.shared.push(session)
        PublicHarborService.shared.publishCurrentMonth(context: modelContext)
        WidgetBridge.refresh(context: modelContext)
        let recorded = StudyDayStore.recordedToday(context: modelContext)
        Task { await NotificationService.reschedule(recordedToday: recorded) }
        Haptics.success()
        onSaved()
        dismiss()
    }
}
