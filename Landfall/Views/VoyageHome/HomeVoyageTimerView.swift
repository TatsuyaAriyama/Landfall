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

private struct HomeVoyageCompletion {
    let minutes: Int
    let note: String?
}

/// Web版の「航海中」をホーム専用に移植したタイマー。
/// 計測中の海を残したまま、完了時だけ航海札へ切り替える。
struct HomeVoyageTimerView: View {
    let item: StudyItem
    let hasDestination: Bool
    let onMinimize: () -> Void
    let onManual: (Int) -> Void
    let onReturnHome: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyDay.date, order: .reverse) private var days: [StudyDay]

    @AppStorage(StudyTimer.startKey, store: StudyTimer.defaults) private var timerStart: Double = 0
    @AppStorage(StudyTimer.itemKey, store: StudyTimer.defaults) private var timerItemID = ""
    @AppStorage(StudyTimer.modeKey, store: StudyTimer.defaults) private var timerMode = HomeTimerMode.free.rawValue
    @AppStorage(StudyTimer.pomodoroStartElapsedKey, store: StudyTimer.defaults) private var pomodoroStartElapsed: Double = 0
    @AppStorage(StudyTimer.breakSecondsKey, store: StudyTimer.defaults) private var breakSeconds: Double = 0
    @AppStorage(StudyTimer.breakStartedAtKey, store: StudyTimer.defaults) private var breakStartedAt: Double = 0
    @AppStorage(StudyTimer.soundKey, store: StudyTimer.defaults) private var soundMode = "off"
    @ObservedObject private var voyageAudio = HomeVoyageAudio.shared

    @State private var note = ""
    @State private var completion: HomeVoyageCompletion?
    @State private var confirmingDiscard = false
    @State private var saveError = false
    @State private var saving = false
    @State private var uiHidden = false
    @FocusState private var noteFocused: Bool

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

    private var timeOfDay: AftideHomeTimeOfDay {
        // Web VoyagingWorld は作業への没入感を一定にするため、航海中だけ夜に固定。
        // ホームの時刻連動パレットを流用すると、同じカメラでも海と水平線が別物に見える。
        .night
    }

    private var palette: AftideHomePalette {
        .voyagingNight
    }

    var body: some View {
        ZStack {
            VoyagingHomeSceneView(
                showIsland: hasDestination,
                timeOfDay: timeOfDay,
                resting: snapshot.isResting,
                elapsedSeconds: snapshot.elapsedSeconds(),
                onTapWorld: {
                    guard completion == nil else { return }
                    noteFocused = false
                    withAnimation(.easeInOut(duration: 0.28)) {
                        uiHidden.toggle()
                    }
                    Haptics.tap(.light)
                }
            )
            .ignoresSafeArea()
            .accessibilityLabel(Text("360° voyage view"))
            .accessibilityHint(Text("Drag to look around. Pinch to zoom. Double-tap to reset the view."))

            Color.black
                .opacity(timeOfDay == .morning || timeOfDay == .day ? 0.05 : 0.13)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if let completion {
                completionCard(completion)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            } else {
                voyageControls
                    .transition(.opacity)
                    .opacity(uiHidden ? 0 : 1)
                    .allowsHitTesting(!uiHidden)
            }
        }
        .background(Color(hex: palette.sky).ignoresSafeArea())
        .preferredColorScheme(
            timeOfDay == .evening || timeOfDay == .night ? .dark : .light
        )
        .animation(.spring(response: 0.62, dampingFraction: 0.82), value: completion != nil)
        .confirmationDialog(
            "Discard this voyage?",
            isPresented: $confirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard voyage", role: .destructive) {
                StudyTimer.clearAll()
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
            HomeVoyageAudio.shared.play(soundMode)
        }
        .onChange(of: soundMode) { _, value in
            HomeVoyageAudio.shared.play(value)
        }
    }

    private var voyageControls: some View {
        VStack(spacing: 0) {
            timerHeader
            Text("Tap the sea for a full view · drag to look around")
                .font(LFFont.label(10))
                .tracking(0.35)
                .foregroundStyle(palette.inkColor.opacity(0.58))
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .background(palette.glassColor.opacity(0.58), in: Capsule())
                .overlay(
                    Capsule().stroke(palette.inkColor.opacity(0.12), lineWidth: 1)
                )
                .padding(.top, 10)
                .allowsHitTesting(false)
            Spacer(minLength: 18)
            recordingPanel
        }
        .padding(.horizontal, 16)
        .safeAreaPadding(.top, 12)
        .safeAreaPadding(.bottom, 10)
    }

    private var timerHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    ItemTileArt(item: item)
                        .frame(width: 25, height: 25)
                    Text(item.name)
                        .font(LFFont.label(13))
                        .foregroundStyle(palette.inkColor.opacity(0.72))
                        .lineLimit(1)
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let current = snapshot
                    let phase = current.phase(at: context.date)
                    VStack(alignment: .leading, spacing: 5) {
                        // ポモドーロを使っても、通常の合計時間は大きい時計のまま残す。
                        Text(Self.clock(current.elapsedSeconds(at: context.date)))
                            .font(LFFont.number(42))
                            .monospacedDigit()
                            .foregroundStyle(palette.inkColor)
                            .contentTransition(.numericText())

                        if let phase {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(phase.focusing ? LFColor.returnOrange : LFColor.seaGreen)
                                    .frame(width: 5, height: 5)
                                Text(phase.focusing ? "Focus" : "Pomodoro break")
                                    .font(LFFont.label(10))
                                    .tracking(0.5)
                                Text(Self.clock(phase.secondsLeft))
                                    .font(LFFont.number(13))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                            }
                            .foregroundStyle(palette.inkColor.opacity(0.74))
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(palette.glassColor.opacity(0.62), in: Capsule())
                            .overlay(
                                Capsule().stroke(
                                    palette.inkColor.opacity(0.14),
                                    lineWidth: 1
                                )
                            )
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                Text(statusLabel)
                    .font(LFFont.label(11))
                    .tracking(1.3)
                    .foregroundStyle(LFColor.returnOrange)

                HStack(spacing: 8) {
                    Button {
                        toggleBreak()
                    } label: {
                        Text(snapshot.isResting ? "Resume voyage" : "Take a break")
                            .font(LFFont.label(12))
                            .foregroundStyle(
                                snapshot.isResting ? LFColor.inkFixed : palette.inkColor
                            )
                            .padding(.horizontal, 13)
                            .frame(height: 34)
                            .background(
                                snapshot.isResting
                                    ? LFColor.sunYellow
                                    : palette.glassColor.opacity(0.72),
                                in: Capsule(style: .continuous)
                            )
                            .overlay {
                                if !snapshot.isResting {
                                    Capsule(style: .continuous)
                                        .stroke(palette.inkColor.opacity(0.28), lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(LFPressableButtonStyle())

                    Button {
                        if mode == .free {
                            pomodoroStartElapsed = Double(snapshot.elapsedSeconds())
                            timerMode = HomeTimerMode.pomodoro.rawValue
                        } else {
                            timerMode = HomeTimerMode.free.rawValue
                            pomodoroStartElapsed = 0
                        }
                        Haptics.tap(.light)
                    } label: {
                        Text(mode == .pomodoro ? "Pomodoro · On" : "Pomodoro")
                            .font(LFFont.label(11))
                            .foregroundStyle(
                                mode == .pomodoro ? palette.glassColor : palette.inkColor.opacity(0.70)
                            )
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(
                                mode == .pomodoro
                                    ? palette.inkColor
                                    : palette.glassColor.opacity(0.66),
                                in: Capsule(style: .continuous)
                            )
                            .overlay {
                                if mode != .pomodoro {
                                    Capsule(style: .continuous)
                                        .stroke(palette.inkColor.opacity(0.18), lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(LFPressableButtonStyle())

                    Button {
                        cycleSound()
                    } label: {
                        HStack(spacing: 5) {
                            Image(
                                systemName: soundMode == "off"
                                    ? "speaker.slash"
                                    : (voyageAudio.playbackFailed
                                        ? "exclamationmark.triangle"
                                        : "speaker.wave.2")
                            )
                                .font(.system(size: 10, weight: .regular))
                            Text(soundLabel)
                                .font(LFFont.label(10))
                            if soundMode != "off" {
                                Circle()
                                    .fill(
                                        voyageAudio.isPlaying
                                            ? LFColor.seaGreen
                                            : LFColor.returnOrange
                                    )
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .foregroundStyle(
                            voyageAudio.playbackFailed
                                ? LFColor.coral
                                : palette.inkColor.opacity(0.70)
                        )
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(
                            palette.glassColor.opacity(0.66),
                            in: Capsule(style: .continuous)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(palette.inkColor.opacity(0.18), lineWidth: 1)
                        )
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .accessibilityLabel(Text(soundAccessibilityLabel))
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 4)

            Button {
                onMinimize()
                Haptics.tap(.light)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.inkColor)
                    .frame(width: 40, height: 40)
                    .background(palette.glassColor.opacity(0.78), in: Circle())
                    .overlay(
                        Circle().stroke(palette.inkColor.opacity(0.18), lineWidth: 1)
                    )
            }
            .buttonStyle(LFPressableButtonStyle())
            .accessibilityLabel(Text("Minimize"))
        }
    }

    private var recordingPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(palette.inkColor.opacity(0.52))

                TextField("What you worked on (optional)", text: $note)
                    .font(LFFont.label(14))
                    .foregroundStyle(palette.inkColor)
                    .tint(LFColor.returnOrange)
                    .focused($noteFocused)
                    .submitLabel(.done)
                    .onChange(of: note) { _, value in
                        if value.count > 120 {
                            note = String(value.prefix(120))
                        }
                    }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(palette.glassColor.opacity(0.58), in: RoundedRectangle(cornerRadius: 13))

            Button {
                finishVoyage()
            } label: {
                HStack(spacing: 9) {
                    if saving {
                        ProgressView()
                            .tint(palette.glassColor)
                    }
                    Text("Log up to here")
                        .font(LFFont.copy(16))
                }
                .foregroundStyle(palette.glassColor)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(palette.inkColor, in: RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(LFPressableButtonStyle())
            .disabled(saving)
            .padding(.top, 14)

            HStack {
                Button {
                    let minutes = snapshot.creditedMinutes(minimum: 0)
                    StudyTimer.clearAll()
                    onManual(minutes)
                    Haptics.tap(.light)
                } label: {
                    Text("Enter work time")
                        .font(LFFont.label(12))
                        .foregroundStyle(palette.inkColor.opacity(0.68))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    confirmingDiscard = true
                } label: {
                    Text("Discard voyage")
                        .font(LFFont.label(12))
                        .foregroundStyle(LFColor.coral)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: 460)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(palette.inkColor.opacity(0.13), lineWidth: 1)
        )
    }

    private var statusLabel: String {
        if snapshot.isResting { return LF.text("At anchor") }
        return LF.text("Voyaging")
    }

    private var soundLabel: String {
        switch soundMode {
        case "waves": LF.text("Waves")
        case "piano": LF.text("Classical")
        default: LF.text("Sound off")
        }
    }

    private var soundAccessibilityLabel: String {
        let state: String
        if soundMode == "off" {
            state = LF.text("Stopped")
        } else if voyageAudio.isPlaying {
            state = LF.text("Playing")
        } else {
            state = LF.text("Sound unavailable")
        }
        return LF.text("Sound") + ": " + soundLabel + ", " + state
    }

    private func cycleSound() {
        let next = soundMode == "off" ? "waves" : (soundMode == "waves" ? "piano" : "off")
        soundMode = next
        // AppStorageの変更通知待ちにせず、ユーザーのタップで直ちに再生を開始する。
        HomeVoyageAudio.shared.play(next)
        Haptics.tap(.light)
    }

    private func toggleBreak() {
        let now = Date().timeIntervalSince1970
        if breakStartedAt > 0 {
            breakSeconds += max(0, now - breakStartedAt)
            breakStartedAt = 0
        } else {
            breakStartedAt = now
        }
        WidgetCenter.shared.reloadTimelines(ofKind: KeelMiraWidgetStore.widgetKind)
        Haptics.tap(.medium)
    }

    private func finishVoyage() {
        guard !saving, timerStart > 0, timerItemID == item.uuid.uuidString else { return }
        saving = true

        let minutes = snapshot.creditedMinutes()
        let trimmed = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        let savedNote = trimmed.isEmpty ? nil : trimmed
        let date = Date()
        let blanks = MonthStats.blankDays(since: days.first?.date, to: date)
        let session = StudySession(date: date, minutes: minutes, note: savedNote, item: item)

        modelContext.insert(session)
        StudyDayStore.markDay(date, context: modelContext)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(session)
            saving = false
            saveError = true
            return
        }

        SyncService.shared.push(session)
        RoomService.shared.publishCurrentMonth(context: modelContext)
        HarborChatService.shared.publishLog(
            item: item,
            minutes: minutes,
            gapDays: blanks,
            isToday: true
        )
        WidgetBridge.refresh(context: modelContext)
        let recorded = StudyDayStore.recordedToday(context: modelContext)
        Task { await NotificationService.reschedule(recordedToday: recorded) }

        StudyTimer.clearAll()
        HomeVoyageAudio.shared.stop()
        saving = false
        noteFocused = false
        completion = HomeVoyageCompletion(minutes: minutes, note: savedNote)
        Haptics.success()
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

    @AppStorage(StudyTimer.startKey, store: StudyTimer.defaults) private var timerStart: Double = 0
    @AppStorage(StudyTimer.modeKey, store: StudyTimer.defaults) private var timerMode = HomeTimerMode.free.rawValue
    @AppStorage(StudyTimer.pomodoroStartElapsedKey, store: StudyTimer.defaults) private var pomodoroStartElapsed: Double = 0
    @AppStorage(StudyTimer.breakSecondsKey, store: StudyTimer.defaults) private var breakSeconds: Double = 0
    @AppStorage(StudyTimer.breakStartedAtKey, store: StudyTimer.defaults) private var breakStartedAt: Double = 0
    @AppStorage(StudyTimer.soundKey, store: StudyTimer.defaults) private var soundMode = "off"
    @ObservedObject private var voyageAudio = HomeVoyageAudio.shared

    private var snapshot: HomeTimerSnapshot {
        HomeTimerSnapshot(
            startedAt: timerStart,
            mode: HomeTimerMode(rawValue: timerMode) ?? .free,
            pomodoroStartElapsed: pomodoroStartElapsed,
            breakSeconds: breakSeconds,
            breakStartedAt: breakStartedAt
        )
    }

    private var localizedSoundName: String {
        switch soundMode {
        case "waves": LF.text("Waves")
        case "piano": LF.text("Classical")
        default: LF.text("Sound off")
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    ItemTileArt(item: item)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
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
                                .font(LFFont.number(18))
                                .monospacedDigit()

                                if let phase {
                                    Text(
                                        "\(phase.focusing ? LF.text("Focus") : LF.text("Pomodoro break")) · \(HomeVoyageTimerView.clock(phase.secondsLeft))"
                                    )
                                    .font(LFFont.label(9))
                                    .foregroundStyle(LFColor.harborSand.opacity(0.72))
                                    .monospacedDigit()
                                }
                            }
                        }
                    }
                }
                .foregroundStyle(LFColor.harborSand)
            }
            .buttonStyle(.plain)

            Button {
                soundMode = soundMode == "off" ? "waves" : (soundMode == "waves" ? "piano" : "off")
                HomeVoyageAudio.shared.play(soundMode)
                Haptics.tap(.light)
            } label: {
                Image(
                    systemName: soundMode == "off"
                        ? "speaker.slash"
                        : (voyageAudio.playbackFailed
                            ? "exclamationmark.triangle"
                            : "speaker.wave.2")
                )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        voyageAudio.playbackFailed ? LFColor.coral : LFColor.harborSand
                    )
                    .frame(width: 34, height: 34)
                    .background(LFColor.harborSand.opacity(0.12), in: Circle())
            }
            .buttonStyle(LFPressableButtonStyle())
            .accessibilityLabel(
                Text(verbatim: "\(LF.text("Sound")): \(localizedSoundName)")
            )

            Button {
                let now = Date().timeIntervalSince1970
                if breakStartedAt > 0 {
                    breakSeconds += max(0, now - breakStartedAt)
                    breakStartedAt = 0
                } else {
                    breakStartedAt = now
                }
                WidgetCenter.shared.reloadTimelines(ofKind: KeelMiraWidgetStore.widgetKind)
                Haptics.tap(.medium)
            } label: {
                Image(systemName: snapshot.isResting ? "play.fill" : "cup.and.saucer")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(snapshot.isResting ? LFColor.inkFixed : LFColor.harborSand)
                    .frame(width: 36, height: 36)
                    .background(
                        snapshot.isResting ? LFColor.sunYellow : LFColor.harborSand.opacity(0.12),
                        in: Circle()
                    )
            }
            .buttonStyle(LFPressableButtonStyle())
            .accessibilityLabel(Text(snapshot.isResting ? "Resume voyage" : "Take a break"))
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(LFColor.harborTeal.opacity(0.96), in: Capsule())
        .overlay(Capsule().stroke(LFColor.harborSand.opacity(0.24), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
        .padding(.horizontal, 16)
        .safeAreaPadding(.bottom, 10)
        .accessibilityElement(children: .contain)
        .onAppear {
            HomeVoyageAudio.shared.play(soundMode)
        }
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
        let isToday = Calendar.current.isDateInToday(date)
        let blanks = isToday ? MonthStats.blankDays(since: days.first?.date, to: date) : nil
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
        RoomService.shared.publishCurrentMonth(context: modelContext)
        HarborChatService.shared.publishLog(
            item: item,
            minutes: minutes,
            gapDays: blanks,
            isToday: isToday
        )
        WidgetBridge.refresh(context: modelContext)
        let recorded = StudyDayStore.recordedToday(context: modelContext)
        Task { await NotificationService.reschedule(recordedToday: recorded) }
        Haptics.success()
        onSaved()
        dismiss()
    }
}
