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

    var isResting: Bool {
        let now = Date().timeIntervalSince1970
        return breakStartedAt.isFinite
            && startedAt.isFinite
            && startedAt > 0
            && startedAt <= now
            && breakStartedAt >= startedAt
            && breakStartedAt <= now
    }

    func elapsedSeconds(at date: Date = Date()) -> Int {
        VoyageTimerMath.elapsedSeconds(
            startedAt: startedAt,
            breakSeconds: breakSeconds,
            breakStartedAt: breakStartedAt,
            at: date
        )
    }

    func workedSeconds(at date: Date = Date()) -> Int {
        let elapsed = elapsedSeconds(at: date)
        guard mode == .pomodoro else { return elapsed }
        // ポモドーロを途中から始めても、それ以前の通常計測を失わない。
        let anchor = VoyageTimerMath.clampedAnchor(pomodoroStartElapsed, elapsed: elapsed)
        let pomodoroElapsed = max(0, elapsed - anchor)
        let cycles = pomodoroElapsed / 1_800
        return anchor + cycles * 1_500 + min(pomodoroElapsed % 1_800, 1_500)
    }

    func creditedMinutes(at date: Date = Date(), minimum: Int = 1) -> Int {
        min(
            WorkRecordPolicy.maximumSessionMinutes,
            max(minimum, Int((Double(workedSeconds(at: date)) / 60).rounded()))
        )
    }

    /// How many 25-minute focus blocks have been completed since pomodoro was
    /// switched on. Shown so a long session reads as progress, not a number.
    func completedPomodoroCycles(at date: Date = Date()) -> Int {
        guard mode == .pomodoro else { return 0 }
        let totalElapsed = elapsedSeconds(at: date)
        let elapsed = max(
            0,
            totalElapsed - VoyageTimerMath.clampedAnchor(
                pomodoroStartElapsed,
                elapsed: totalElapsed
            )
        )
        return elapsed / 1_800
    }

    func phase(at date: Date = Date()) -> HomePomodoroPhase? {
        guard mode == .pomodoro else { return nil }
        // 通常の合計時計とは別に、オンにした瞬間から25:00を始める。
        // elapsedSecondsは手動休憩中に止まるため、こちらも同じ位置で自然に止まる。
        let totalElapsed = elapsedSeconds(at: date)
        let elapsed = max(
            0,
            totalElapsed - VoyageTimerMath.clampedAnchor(
                pomodoroStartElapsed,
                elapsed: totalElapsed
            )
        )
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
    var pomodoroCycles: Int = 0
}

/// 航海記録とは切り離した、端末内だけの作業項目別スクラッチ。
/// 明示的に残した内容だけを次の航海へ渡し、自動保存や同期は行わない。
private enum VoyageTemporaryMemoStore {
    static let maximumCharacters = 10_000
    private static let storageKey = "voyage.temporaryMemos.v1"
    private static let defaults = UserDefaults.standard

    static func load(itemID: UUID) -> String {
        let memos = defaults.dictionary(forKey: storageKey) as? [String: String]
        return memos?[itemID.uuidString] ?? ""
    }

    @discardableResult
    static func save(_ memo: String, itemID: UUID) -> String {
        let value = String(memo.prefix(maximumCharacters))
        var memos = defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        memos[itemID.uuidString] = value
        defaults.set(memos, forKey: storageKey)
        return value
    }

    static func remove(itemID: UUID) {
        var memos = defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        memos.removeValue(forKey: itemID.uuidString)
        if memos.isEmpty {
            defaults.removeObject(forKey: storageKey)
        } else {
            defaults.set(memos, forKey: storageKey)
        }
    }
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
        let savedNote = WorkRecordPolicy.normalizedNote(note)
        let date = Date()
        let session = StudySession(
            date: date,
            minutes: minutes,
            note: savedNote,
            item: item
        )

        context.insert(session)
        let dayMark = StudyDayStore.markDay(date, context: context, syncsToAccount: false)
        do {
            try context.save()
        } catch {
            context.delete(session)
            if dayMark.wasInserted { context.delete(dayMark.day) }
            throw error
        }

        SyncService.shared.publishPersistedSessionChanges(
            [session],
            insertedDays: dayMark.wasInserted ? [dayMark.day] : [],
            context: context
        )

        return HomeVoyageCompletion(minutes: minutes, note: savedNote)
    }
}

/// Web版の「航海中」をホーム専用に移植したタイマー。
/// 計測中の海を残したまま、完了時だけ航海札へ切り替える。
/// 航海HUDの色。海の上に浮かぶ計器の板と、そこに灯る明かり。
/// 白いガラス札で組むと画面の上に「アプリの用紙」が載って見えたので、
/// 板は夜の海より一段深い緑、文字と縁は帆と同じ砂、数字は船尾の灯り。
enum VoyageHUD {
    /// 計器板の地。VoyageSceneKit の夜色(#123830)より沈めて、
    /// 明るい昼の海の上でも文字が浮くようにする。
    static let plate = Color(hex: 0x07231F)
    /// 板に乗る文字と彫り線。帆・浜と同じ砂色。
    static let ink = LFColor.harborSand
    /// 灯り。経過時間と、効いている道具と、記録の押し板。
    static let lamp = LFColor.emberGold
    /// 進行中の合図とバッジ。
    static let signal = LFColor.returnOrange
}

struct HomeVoyageTimerView: View {
    let item: StudyItem
    let hasDestination: Bool
    let onManual: (Int) -> Void
    let onReturnHome: () -> Void
    let onTimerStopped: () -> Void
    let rendersScene: Bool
    let externalWorldTapToken: Int
    /// 私設島の同行者。甲板に並び、札には名前だけが出る。
    let companions: [CompanionVoyageCrewMate]
    /// 自分がこの航海を出した島の主かどうか。ホストは甲板の正面で
    /// ランタンを掲げ、船団の先を照らす。
    let hostsCompanionVoyage: Bool
    /// 同行者側では島の主の船を使う。nil の通常航海は自分の船。
    let boatParts: BoatParts?
    let boatAppearanceKey: String?
    /// 初回航海だけ、通常のメモ欄を使いながら指定の文言を必須にする。
    /// nil の通常航海では、従来どおり任意メモとして動作する。
    let firstVoyageRequiredNote: String?
    let onFirstVoyageRecorded: (() -> Void)?

    init(
        item: StudyItem,
        hasDestination: Bool,
        onManual: @escaping (Int) -> Void,
        onReturnHome: @escaping () -> Void,
        onTimerStopped: @escaping () -> Void = {},
        rendersScene: Bool = true,
        externalWorldTapToken: Int = 0,
        companions: [CompanionVoyageCrewMate] = [],
        hostsCompanionVoyage: Bool = false,
        boatParts: BoatParts? = nil,
        boatAppearanceKey: String? = nil,
        firstVoyageRequiredNote: String? = nil,
        onFirstVoyageRecorded: (() -> Void)? = nil
    ) {
        self.item = item
        self.hasDestination = hasDestination
        self.onManual = onManual
        self.onReturnHome = onReturnHome
        self.onTimerStopped = onTimerStopped
        self.rendersScene = rendersScene
        self.externalWorldTapToken = externalWorldTapToken
        self.companions = companions
        self.hostsCompanionVoyage = hostsCompanionVoyage
        self.boatParts = boatParts
        self.boatAppearanceKey = boatAppearanceKey
        self.firstVoyageRequiredNote = firstVoyageRequiredNote
        self.onFirstVoyageRecorded = onFirstVoyageRecorded
        let restoredMemo = firstVoyageRequiredNote == nil
            ? VoyageTemporaryMemoStore.load(itemID: item.uuid)
            : ""
        _note = State(initialValue: restoredMemo)
        _savedTemporaryMemo = State(initialValue: restoredMemo)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \StudyDay.date, order: .reverse) private var days: [StudyDay]
    /// 完了札の経験値バーは、記録済みの全セッションからレベルを導く。
    @Query private var sessions: [StudySession]
    @AppStorage(StudyTimer.startKey, store: StudyTimer.defaults) private var timerStart: Double = 0
    @AppStorage(StudyTimer.itemKey, store: StudyTimer.defaults) private var timerItemID = ""
    @AppStorage(StudyTimer.modeKey, store: StudyTimer.defaults) private var timerMode = HomeTimerMode.free.rawValue
    @AppStorage(StudyTimer.pomodoroStartElapsedKey, store: StudyTimer.defaults) private var pomodoroStartElapsed: Double = 0
    @AppStorage(StudyTimer.breakSecondsKey, store: StudyTimer.defaults) private var breakSeconds: Double = 0
    @AppStorage(StudyTimer.breakStartedAtKey, store: StudyTimer.defaults) private var breakStartedAt: Double = 0
    @AppStorage(StudyTimer.soundKey, store: StudyTimer.defaults)
    private var soundMode = HomeVoyageSound.initialTimerSound.rawValue
    @ObservedObject private var voyageAudio = HomeVoyageAudio.shared

    @State private var note: String
    @State private var savedTemporaryMemo: String
    @State private var reflection = ""
    @State private var completion: HomeVoyageCompletion?
    @State private var confirmingDiscard = false
    @State private var saveError = false
    @State private var saving = false
    @State private var uiHidden = false
    @State private var showingVoyageMenu = false
    @State private var showingSoundPicker = false
    @State private var showingTemporaryMemo = false
    @State private var showingReflection = false
    @State private var confirmingReturnHome = false
    @State private var confirmingTemporaryMemoClear = false
    @State private var showingTodoList = false
    @State private var showingManualEntry = false
    @StateObject private var todoStore = HomeIslandTodoStore.shared
    @State private var clockNow = Date()
    @FocusState private var noteFocused: Bool
    @FocusState private var reflectionFocused: Bool

    private let clockPulse = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var mode: HomeTimerMode {
        HomeTimerMode(rawValue: timerMode) ?? .free
    }

    private var canEnterWorkTimeManually: Bool {
        AccessPolicy.isDeveloper()
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

    /// Keep the elapsed time purely coral—without a shadow or backing plate—
    /// while preserving readable contrast as the sky changes through the day.
    private var timerCoral: Color {
        switch timeOfDay {
        case .morning, .day:
            Color(hex: 0xA33440)
        case .evening:
            Color(hex: 0x782330)
        case .night:
            LFColor.coral
        }
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

    private var normalizedReflection: String? {
        let value = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : String(value.prefix(80))
    }

    private var requiredNoteSatisfied: Bool {
        guard let firstVoyageRequiredNote else { return true }
        return normalizedReflection == firstVoyageRequiredNote
    }

    private var temporaryMemoHasUnsavedChanges: Bool {
        note != savedTemporaryMemo
    }

    private var canKeepTemporaryMemo: Bool {
        !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && temporaryMemoHasUnsavedChanges
    }

    private var temporaryMemoIsSaved: Bool {
        !savedTemporaryMemo.isEmpty && !temporaryMemoHasUnsavedChanges
    }

    private var temporaryMemoSaveLabel: LocalizedStringKey {
        temporaryMemoIsSaved ? "Saved for next time" : "Keep for next time"
    }

    /// 参加順はホストから1〜4番。全端末で同じ配列を使い、ローカルかどうかは
    /// 描画ノードを自分用・同行者用に分けるときだけ見る。
    private var localCompanionRole: VoyageSceneKit.CompanionDeckRole? {
        guard let index = companions.firstIndex(where: \.isLocal) else {
            return companions.isEmpty || !hostsCompanionVoyage ? nil : .lantern
        }
        return VoyageSceneKit.CompanionDeckRole.participant(at: index)
    }

    private var remoteCompanions: [CompanionVoyageCrewMate] {
        companions.filter { !$0.isLocal }
    }

    private var companionDeckMembers: [VoyageSceneKit.CompanionDeckMember] {
        companions.enumerated().compactMap { index, mate in
            guard !mate.isLocal,
                  let role = VoyageSceneKit.CompanionDeckRole.participant(at: index)
            else { return nil }
            return VoyageSceneKit.CompanionDeckMember(id: mate.id, role: role)
        }
    }

    private var notePlaceholder: String {
        firstVoyageRequiredNote ?? LF.text("What you worked on (optional)")
    }

    /// 航海HUDの素材。海の上に浮かぶ白いガラス札は「アプリの用紙」に
    /// 見えていたので、夜の海より一段深い板へ沈め、縁と文字だけを
    /// 船の灯りと同じ色で起こす。船室の計器を覗いている手触りにする。
    private var plateInset: CGFloat { compactHUD ? 11 : 13 }

    /// 計器板そのもの。背後の海を透かしつつ、板として厚みを持たせるため
    /// 縁は上を明るく下を暗くした一本線にする。
    private func instrumentPlate(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(VoyageHUD.plate.opacity(0.80))
        }
        .overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        VoyageHUD.ink.opacity(0.34),
                        VoyageHUD.ink.opacity(0.09),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
        )
    }

    /// 板に彫った溝。暗い線の下へ砂色の照り返しを一本添えると、
    /// ただの区切り線ではなく板の段差に見える。
    private var engravedRule: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.black.opacity(0.24)).frame(height: 1)
            Rectangle().fill(VoyageHUD.ink.opacity(0.09)).frame(height: 1)
        }
    }

    var body: some View {
        ZStack {
            if rendersScene {
                VoyagingHomeSceneView(
                    showIsland: hasDestination,
                    timeOfDay: timeOfDay,
                    date: clockNow,
                    resting: isVoyageResting,
                    elapsedSeconds: snapshot.elapsedSeconds(at: clockNow),
                    boatParts: boatParts ?? BoatCustomization.currentParts,
                    boatAppearanceKey: boatAppearanceKey ?? BoatCustomization.voyageRenderingKey,
                    companions: companionDeckMembers,
                    localSailorRole: localCompanionRole,
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
        .alert("Could not save the voyage", isPresented: $saveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your timer is still running. Please try again.")
        }
        .alert("Return to your island?", isPresented: $confirmingReturnHome) {
            Button("Return to island") {
                discardVoyageAndReturnHome()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Clear this temporary memo?", isPresented: $confirmingTemporaryMemoClear) {
            Button("Clear", role: .destructive) {
                clearTemporaryMemo()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onDisappear {
            noteFocused = false
            reflectionFocused = false
            if timerItemID.isEmpty {
                HomeVoyageAudio.shared.stop()
            }
        }
        .onAppear {
            ensureFirstVoyageTimerIsActive()
            let migratedSound = HomeVoyageSound.resolve(soundMode)
            if migratedSound.rawValue != soundMode {
                soundMode = migratedSound.rawValue
            }
            if isVoyageResting {
                HomeVoyageAudio.shared.stop()
            } else {
                playVoyageAudio(migratedSound.rawValue)
            }
            #if DEBUG
            // 動作確認用: LANDFALL_VOYAGE_DONE=<分> で、記録せずに完了札だけを開く。
            if let raw = ProcessInfo.processInfo.environment["LANDFALL_VOYAGE_DONE"],
               let minutes = Int(raw) {
                HomeVoyageAudio.shared.stop()
                completion = HomeVoyageCompletion(minutes: minutes, note: nil)
            }
            #endif
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
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 24)
            recordingPanel
        }
        .padding(.horizontal, compactHUD ? 24 : 32)
        .safeAreaPadding(.top, compactHUD ? 14 : 20)
        .safeAreaPadding(.bottom, compactHUD ? 20 : 26)
    }

    /// 景色を主役にしたまま、左上には小さな数字と道具だけを置く。
    private var timerHeader: some View {
        VStack(alignment: .leading, spacing: compactHUD ? 8 : 10) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.clock(snapshot.elapsedSeconds(at: context.date)))
                    .font(
                        .system(
                            size: compactHUD ? 22 : 25,
                            weight: .medium,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(timerCoral)
                    .contentTransition(.numericText())
            }
            .accessibilityLabel(Text("ELAPSED"))

            HStack(spacing: 7) {
                compactToolButton(
                    systemImage: snapshot.isResting ? "play.fill" : "pause.fill",
                    active: snapshot.isResting,
                    accessibilityLabel: snapshot.isResting
                        ? LF.text("Resume voyage")
                        : LF.text("Take a break")
                ) {
                    toggleBreak()
                }

                compactToolButton(
                    systemImage: "music.note",
                    active: showingSoundPicker,
                    accessibilityLabel: soundAccessibilityLabel
                ) {
                    noteFocused = false
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        showingSoundPicker.toggle()
                        showingTemporaryMemo = false
                    }
                    Haptics.tap(.light)
                }

                compactToolButton(
                    systemImage: "pencil.line",
                    active: showingTemporaryMemo,
                    accessibilityLabel: LF.text("Temporary memo")
                ) {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        showingTemporaryMemo.toggle()
                        showingSoundPicker = false
                    }
                    if showingTemporaryMemo {
                        Task { @MainActor in noteFocused = true }
                    } else {
                        noteFocused = false
                    }
                    Haptics.tap(.light)
                }

                if !isFirstVoyage {
                    compactToolButton(
                        systemImage: "chevron.backward",
                        active: false,
                        accessibilityLabel: LF.text("Return to my island")
                    ) {
                        noteFocused = false
                        reflectionFocused = false
                        showingSoundPicker = false
                        showingTemporaryMemo = false
                        confirmingReturnHome = true
                        Haptics.tap(.light)
                    }
                }
            }

            if showingSoundPicker {
                soundPicker
                    .frame(width: compactHUD ? 310 : 350)
                    .padding(.top, 2)
                    .background(transparentCardBackground(cornerRadius: 18))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if showingTemporaryMemo {
                temporaryMemoCard
                    .frame(width: compactHUD ? 310 : 370)
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func compactToolButton(
        systemImage: String,
        active: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: compactHUD ? 16 : 18, weight: .semibold))
                .foregroundStyle(active ? timerCoral : VoyageHUD.plate.opacity(0.86))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .shadow(color: Color.white.opacity(0.78), radius: 1.2)
                .shadow(color: Color.black.opacity(0.24), radius: 4, y: 2)
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
    }

    /// 航海記録へは渡さない作業項目別の走り書き。明示的に残した内容だけ、
    /// 同じ端末で次にこの項目の航海を開いたときに復元する。
    private var temporaryMemoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 13, weight: .medium))
                Text("Temporary memo")
                    .font(LFFont.label(12))
                Spacer()
                Button {
                    noteFocused = false
                    withAnimation(.easeOut(duration: 0.20)) {
                        showingTemporaryMemo = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(VoyageHUD.plate.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
            .foregroundStyle(Color.black)

            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text("Write anything here")
                        .font(LFFont.copy(14))
                        .foregroundStyle(Color.black.opacity(0.58))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $note)
                    .font(LFFont.copy(14))
                    .foregroundStyle(Color.black)
                    .tint(LFColor.coral)
                    .scrollContentBackground(.hidden)
                    .focused($noteFocused)
                    .frame(minHeight: compactHUD ? 150 : 190)
                    .accessibilityLabel(Text("Temporary memo"))
                    .onChange(of: note) { _, value in
                        guard value.count > VoyageTemporaryMemoStore.maximumCharacters else {
                            return
                        }
                        note = String(value.prefix(VoyageTemporaryMemoStore.maximumCharacters))
                    }
            }
            .padding(7)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(VoyageHUD.plate.opacity(0.10), lineWidth: 1)
            )

            if isFirstVoyage {
                Text("This is a temporary memo field.")
                    .font(LFFont.label(11))
                    .foregroundStyle(Color.black.opacity(0.72))
            } else {
                HStack(spacing: 8) {
                    if !note.isEmpty || !savedTemporaryMemo.isEmpty {
                        Button {
                            noteFocused = false
                            confirmingTemporaryMemoClear = true
                            Haptics.tap(.light)
                        } label: {
                            Label("Clear", systemImage: "trash")
                                .font(LFFont.label(10))
                                .foregroundStyle(LFColor.coral)
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                                .background(Color.white.opacity(0.34), in: Capsule())
                        }
                        .buttonStyle(LFPressableButtonStyle())
                    }

                    Spacer(minLength: 4)

                    Button {
                        keepTemporaryMemoForNextVoyage()
                    } label: {
                        Label(
                            temporaryMemoSaveLabel,
                            systemImage: canKeepTemporaryMemo ? "bookmark" : "checkmark"
                        )
                        .font(LFFont.label(10))
                        .foregroundStyle(Color.black.opacity(canKeepTemporaryMemo ? 0.88 : 0.50))
                        .padding(.horizontal, 11)
                        .frame(height: 32)
                        .background(
                            Color.white.opacity(canKeepTemporaryMemo ? 0.62 : 0.28),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .disabled(!canKeepTemporaryMemo)
                }

                VStack(alignment: .leading, spacing: 3) {
                    if temporaryMemoHasUnsavedChanges, !savedTemporaryMemo.isEmpty {
                        Text("Unsaved changes")
                            .foregroundStyle(LFColor.coral)
                    }
                    Text("This is only a temporary memo.\nUse “Keep for next time” to carry it over.")
                        .foregroundStyle(Color.black.opacity(0.72))
                        .lineLimit(2)
                }
                .font(LFFont.label(10))
            }
        }
        .padding(14)
        .background(transparentCardBackground(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.22), radius: 16, y: 8)
    }

    private func keepTemporaryMemoForNextVoyage() {
        guard canKeepTemporaryMemo else { return }
        let saved = VoyageTemporaryMemoStore.save(note, itemID: item.uuid)
        note = saved
        savedTemporaryMemo = saved
        Haptics.success()
    }

    private func clearTemporaryMemo() {
        VoyageTemporaryMemoStore.remove(itemID: item.uuid)
        note = ""
        savedTemporaryMemo = ""
        Haptics.tap(.medium)
    }

    private func transparentCardBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(Color.white.opacity(0.30))
        }
        .overlay(shape.strokeBorder(Color.black.opacity(0.16), lineWidth: 1))
    }

    /// 右下の「…」から開く航海道具。通常時は隠し、必要な時だけ
    /// 船室の計器板として現れる。
    private var voyageMenu: some View {
        VStack(spacing: 0) {
            HStack(spacing: compactHUD ? 2 : 4) {
                commandButton(
                    title: snapshot.isResting ? "Resume voyage" : "Take a break",
                    systemImage: snapshot.isResting ? "play.fill" : "pause.fill",
                    active: snapshot.isResting,
                    action: toggleBreak
                )

                commandButton(
                    title: "Pomodoro",
                    systemImage: "timer",
                    active: mode == .pomodoro,
                    action: togglePomodoro
                )

                commandButton(
                    title: "BGM",
                    systemImage: voyageAudio.playbackFailed
                        ? "exclamationmark.triangle.fill"
                        : "music.note",
                    active: showingSoundPicker || selectedSound != .off,
                    action: {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                            showingSoundPicker.toggle()
                            if showingSoundPicker { showingTodoList = false }
                        }
                        Haptics.tap(.light)
                    }
                )
                .accessibilityLabel(Text(soundAccessibilityLabel))

                commandButton(
                    title: "ToDo",
                    systemImage: "checklist",
                    active: showingTodoList,
                    badge: todoStore.openCount,
                    action: {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                            showingTodoList.toggle()
                            if showingTodoList { showingSoundPicker = false }
                        }
                        Haptics.tap(.light)
                    }
                )
                .accessibilityLabel(Text("ToDo list"))
            }
            .padding(.horizontal, compactHUD ? 7 : 9)
            .padding(.vertical, compactHUD ? 10 : 12)

            if showingSoundPicker {
                soundPicker
                    .padding(.horizontal, plateInset)
                    .padding(.bottom, plateInset)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if showingTodoList {
                // The same list the island keeps, so a task written mid-voyage
                // is already there when the navigator gets home.
                HomeIslandTodoCompactList(
                    store: todoStore,
                    ink: VoyageHUD.ink,
                    maxListHeight: compactHUD ? 176 : 196
                )
                .padding(.horizontal, plateInset)
                .padding(.bottom, plateInset)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            engravedRule

            VStack(spacing: 10) {
                noteLine

                HStack(spacing: 8) {
                    if !isFirstVoyage, canEnterWorkTimeManually {
                        Button {
                            noteFocused = false
                            showingManualEntry = true
                            Haptics.tap(.light)
                        } label: {
                            Label("Enter time", systemImage: "clock")
                                .font(LFFont.label(11))
                                .foregroundStyle(VoyageHUD.ink.opacity(0.78))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(VoyageHUD.ink.opacity(0.07), in: Capsule())
                        }
                        .buttonStyle(LFPressableButtonStyle())
                    }

                    if !isFirstVoyage {
                        Button {
                            confirmingDiscard = true
                            Haptics.tap(.rigid)
                        } label: {
                            Label("Discard voyage", systemImage: "xmark")
                                .font(LFFont.label(11))
                                .foregroundStyle(VoyageHUD.ink.opacity(0.62))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(VoyageHUD.ink.opacity(0.07), in: Capsule())
                        }
                        .buttonStyle(LFPressableButtonStyle())
                    }
                }
            }
            .padding(.horizontal, plateInset)
            .padding(.vertical, plateInset)
        }
        .frame(maxWidth: compactHUD ? 332 : 420)
        .background(instrumentPlate(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.34), radius: 18, y: 9)
    }

    private var statusLampColor: Color {
        isVoyageResting ? LFColor.sunYellow : VoyageHUD.signal
    }

    /// 航海を捨てる口。板の縁と同じ細い輪で、押し間違えない小ささに留める。
    private var discardButton: some View {
        Button {
            confirmingDiscard = true
            Haptics.tap(.rigid)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: compactHUD ? 10 : 11, weight: .medium))
                .foregroundStyle(VoyageHUD.ink.opacity(0.72))
                .frame(
                    width: compactHUD ? 26 : 28,
                    height: compactHUD ? 26 : 28
                )
                .background(VoyageHUD.ink.opacity(0.08), in: Circle())
                .overlay(Circle().strokeBorder(VoyageHUD.ink.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityLabel(Text("Discard voyage"))
    }

    /// 同じ船に乗っている仲間。甲板の航海士と同じ並び順で名前を出す。
    private var companionStrip: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(VoyageHUD.ink.opacity(0.52))
            Text(verbatim: remoteCompanions.map(\.name).joined(separator: LF.text(", ")))
                .font(LFFont.label(9.5))
                .foregroundStyle(VoyageHUD.ink.opacity(0.80))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(VoyageHUD.ink.opacity(0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(VoyageHUD.ink.opacity(0.13), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sailing together"))
        .accessibilityValue(
            Text(verbatim: remoteCompanions.map(\.name).joined(separator: LF.text(", ")))
        )
    }

    /// iPhone は画面が狭いぶん、この札だけで空の半分近くを塞いでしまう。
    /// コンパクト幅では文字も間隔も一段落として、海と船を見せたまま操作できるようにする。
    /// iPad は元の余裕のある寸法のまま。
    private var compactHUD: Bool {
        horizontalSizeClass == .compact
    }

    private var chipTrayPadding: CGFloat {
        compactHUD ? 6 : 7
    }

    /// 手元の道具。真鍮の丸ボタンを四つ並べた計器の列に見立てる。
    /// 効いている道具は灯りが点り、板の地色の字が抜ける。
    private func commandButton(
        title: LocalizedStringKey,
        systemImage: String,
        active: Bool,
        badge: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        let diameter: CGFloat = compactHUD ? 38 : 42
        return Button(action: action) {
            VStack(spacing: compactHUD ? 5 : 6) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .fill(active ? VoyageHUD.lamp : VoyageHUD.ink.opacity(0.08))
                        Circle()
                            .strokeBorder(
                                active ? VoyageHUD.lamp : VoyageHUD.ink.opacity(0.18),
                                lineWidth: 1
                            )
                        Image(systemName: systemImage)
                            .font(.system(size: compactHUD ? 13 : 14, weight: .medium))
                            .foregroundStyle(
                                active ? VoyageHUD.plate : VoyageHUD.ink.opacity(0.84)
                            )
                    }
                    .frame(width: diameter, height: diameter)
                    .shadow(
                        color: active ? VoyageHUD.lamp.opacity(0.42) : .clear,
                        radius: 9
                    )

                    if badge > 0 {
                        Text(verbatim: badge > 9 ? "9+" : "\(badge)")
                            .font(LFFont.label(8))
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 3)
                            .frame(minWidth: 14, minHeight: 14)
                            .background(VoyageHUD.signal, in: Capsule())
                            .overlay(
                                Capsule().strokeBorder(VoyageHUD.plate.opacity(0.75), lineWidth: 1)
                            )
                            .offset(x: 4, y: -3)
                    }
                }

                Text(title)
                    .font(LFFont.label(compactHUD ? 8.5 : 9.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(VoyageHUD.ink.opacity(active ? 0.92 : 0.56))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
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
                    .foregroundStyle(Color.black.opacity(0.70))
            }
            .foregroundStyle(Color.black)
            .padding(.horizontal, compactHUD ? 10 : 12)
            .frame(height: compactHUD ? 25 : 28)

            ForEach(HomeVoyageSound.timerSelectableSounds) { sound in
                Button {
                    selectSound(sound)
                } label: {
                    HStack(spacing: 12) {
                        HomeVoyageSoundIcon(
                            sound: sound,
                            selected: sound == displayedSound
                        )
                        .frame(width: compactHUD ? 21 : 24, height: compactHUD ? 21 : 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(sound.title)
                                .font(LFFont.copy(compactHUD ? 11 : 12))
                            Text(sound.subtitle)
                                .font(LFFont.label(compactHUD ? 8 : 9))
                                .foregroundStyle(Color.black.opacity(0.68))
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
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, compactHUD ? 10 : 12)
                    .frame(height: compactHUD ? 38 : 43)
                    .background(
                        sound == displayedSound
                            ? Color.black.opacity(0.08)
                            : Color.clear
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if sound != HomeVoyageSound.timerSelectableSounds.last {
                    Rectangle()
                        .fill(Color.black.opacity(0.12))
                        .frame(height: 1)
                        .padding(.leading, compactHUD ? 43 : 48)
                }
            }
        }
        .background(
            Color.white.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.black.opacity(0.16), lineWidth: 1)
        )
    }

    /// 参考画像の下部操作。記録を左の大きなカプセル、設定を右の丸い
    /// 「…」へ分け、中央の海と船の前を開けておく。
    private var recordingPanel: some View {
        Group {
            if showingReflection {
                reflectionComposer
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                recordButton
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: showingReflection)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: Color.black.opacity(0.24), radius: 10, y: 4)
    }

    private var recordButton: some View {
        HStack(alignment: .center) {
            Button {
                noteFocused = false
                showingSoundPicker = false
                showingTemporaryMemo = false
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    showingReflection = true
                }
                Task { @MainActor in reflectionFocused = true }
            } label: {
                HStack(spacing: 8) {
                    if saving {
                        ProgressView()
                            .tint(Color.black)
                    }
                    Text("Record")
                        .font(LFFont.copy(compactHUD ? 14 : 16))
                }
                .foregroundStyle(Color.black.opacity(0.88))
                .frame(width: compactHUD ? 126 : 144, height: compactHUD ? 52 : 56)
                .background(
                    Color.white,
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        Color.black.opacity(0.10),
                        lineWidth: 1
                    )
                )
            }
            .buttonStyle(LFPressableButtonStyle())
            .disabled(saving)
            .accessibilityIdentifier(isFirstVoyage ? "firstVoyage.record" : "voyage.record")

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    /// 記録直前だけ現れる短い感想欄。一時メモとは別物で、入力した場合は
    /// 航海記録と完了カードへ残す。
    private var reflectionComposer: some View {
        HStack(spacing: 9) {
            compactToolButton(
                systemImage: "chevron.backward",
                active: false,
                accessibilityLabel: LF.text("Back to timer")
            ) {
                reflectionFocused = false
                withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                    showingReflection = false
                }
                Haptics.tap(.light)
            }

            HStack(spacing: 8) {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.68))

                TextField(
                    "",
                    text: $reflection,
                    prompt: Text(verbatim: reflectionPrompt)
                )
                    .font(LFFont.copy(compactHUD ? 12 : 14))
                    .foregroundStyle(Color.black)
                    .tint(LFColor.coral)
                    .focused($reflectionFocused)
                    .submitLabel(.done)
                    .onSubmit { finishVoyage() }
                    .onChange(of: reflection) { _, value in
                        if value.count > 80 {
                            reflection = String(value.prefix(80))
                        }
                    }
                    .accessibilityLabel(Text(verbatim: reflectionPrompt))
                    .accessibilityHint(
                        Text(
                            verbatim: isFirstVoyage
                                ? LF.text("Enter \"Tutorial\".")
                                : ""
                        )
                    )
                    .accessibilityIdentifier(
                        isFirstVoyage ? "firstVoyage.note" : "voyage.reflection"
                    )

                if !reflection.isEmpty {
                    Button {
                        reflection = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.black.opacity(0.46))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear"))
                }
            }
            .padding(.horizontal, 13)
            .frame(width: compactHUD ? 150 : 230, height: compactHUD ? 44 : 48)
            .background(Color.white.opacity(0.78), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.16), lineWidth: 1))

            Button {
                finishVoyage()
            } label: {
                HStack(spacing: 6) {
                    if saving {
                        ProgressView()
                            .tint(VoyageHUD.plate)
                    }
                    Text("End voyage")
                        .font(LFFont.copy(compactHUD ? 12 : 14))
                        .lineLimit(1)
                }
                .foregroundStyle(VoyageHUD.plate)
                .padding(.horizontal, compactHUD ? 14 : 17)
                .frame(height: compactHUD ? 44 : 48)
                .background(VoyageHUD.lamp, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            }
            .buttonStyle(LFPressableButtonStyle())
            .disabled(saving || !requiredNoteSatisfied)
            .opacity(requiredNoteSatisfied ? 1 : 0.48)
            .accessibilityIdentifier(
                isFirstVoyage ? "firstVoyage.complete" : "voyage.complete"
            )
        }
    }

    private var reflectionPrompt: String {
        isFirstVoyage
            ? LF.text("Enter \"Tutorial\".")
            : LF.text("How did the work feel?")
    }

    /// 枠のないメモ欄。彫った罫線だけが書く場所を示し、書き始めると
    /// 罫線に灯りが点る。板の上で輪郭が増えないほど、海が主役のまま残る。
    private var noteLine: some View {
        VStack(spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(VoyageHUD.ink.opacity(noteFocused ? 0.80 : 0.52))

                TextField(
                    "",
                    text: $note,
                    prompt: Text(verbatim: notePlaceholder)
                        .foregroundStyle(VoyageHUD.ink.opacity(0.42))
                )
                    .font(LFFont.label(14))
                    .foregroundStyle(VoyageHUD.ink)
                    .tint(VoyageHUD.lamp)
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

                if !note.isEmpty {
                    Button {
                        note = ""
                        Haptics.tap(.light)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(VoyageHUD.ink.opacity(0.38))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear"))
                }
            }
            .frame(height: 24)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.22))
                    .frame(height: 1)
                Capsule()
                    .fill(
                        noteFocused
                            ? VoyageHUD.lamp.opacity(0.9)
                            : VoyageHUD.ink.opacity(0.16)
                    )
                    .frame(height: noteFocused ? 1.6 : 1)
                    .shadow(
                        color: noteFocused ? VoyageHUD.lamp.opacity(0.5) : .clear,
                        radius: 6
                    )
            }
            .frame(height: 2)
        }
        .animation(.easeOut(duration: 0.16), value: noteFocused)
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
              VoyageTimerMath.isActive(
                startedAt: timerStart,
                itemID: timerItemID
              ),
              timerItemID == item.uuid.uuidString,
              requiredNoteSatisfied
        else { return }
        saving = true

        if isFirstVoyage {
            do {
                try TutorialFirstVoyageRecorder.record(
                    note: normalizedReflection ?? "",
                    elapsedSeconds: snapshot.elapsedSeconds(at: clockNow),
                    context: modelContext
                )
            } catch {
                saving = false
                saveError = true
                return
            }

            stopTimer()
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
                note: normalizedReflection,
                context: modelContext
            )
        } catch {
            saving = false
            saveError = true
            return
        }

        stopTimer()
        HomeVoyageAudio.shared.stop()
        saving = false
        noteFocused = false
        reflectionFocused = false
        completion = result
        Haptics.success()
    }

    /// 保存領域だけでなく、この画面と親画面の AppStorage も同じ実行ループで
    /// 終了状態へ揃える。完了直後に作業項目を開いても旧航海を再開させない。
    private func stopTimer() {
        StudyTimer.clearAll()
        timerStart = 0
        timerItemID = ""
        timerMode = HomeTimerMode.free.rawValue
        pomodoroStartElapsed = 0
        breakSeconds = 0
        breakStartedAt = 0
        onTimerStopped()
    }

    /// 航海中の帰還は一時停止ではなく取り消しとして扱う。
    /// 永続タイマーまで消してから島へ戻さないと、次に船を開いたとき
    /// 同じ作業項目が「航海へ戻る」として復活してしまう。
    private func discardVoyageAndReturnHome() {
        guard !isFirstVoyage else {
            ensureFirstVoyageTimerIsActive()
            return
        }
        stopTimer()
        HomeVoyageAudio.shared.stop()
        onReturnHome()
        Haptics.tap(.medium)
    }

    /// The tutorial must remain recordable even if an old migration or another
    /// process left the App Group defaults half-cleared before this view appeared.
    private func ensureFirstVoyageTimerIsActive() {
        guard isFirstVoyage else { return }
        let expectedItemID = item.uuid.uuidString
        guard !VoyageTimerMath.isActive(
            startedAt: timerStart,
            itemID: timerItemID == expectedItemID ? timerItemID : ""
        ) else { return }

        StudyTimer.clearAll()
        StudyTimer.begin(itemID: expectedItemID, itemName: item.name)
        timerStart = StudyTimer.defaults.double(forKey: StudyTimer.startKey)
        timerItemID = expectedItemID
        timerMode = HomeTimerMode.free.rawValue
        pomodoroStartElapsed = 0
        breakSeconds = 0
        breakStartedAt = 0
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

                VoyageLevelBar(
                    gainedMinutes: result.minutes,
                    after: PlayerLevelProgress(sessions: sessions),
                    ink: palette.inkColor
                )
                .padding(.top, 20)

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
            .contentShape(RoundedRectangle(cornerRadius: 24))
            .onTapGesture {
                onReturnHome()
                Haptics.tap(.light)
            }
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

/// 完了札の中で、この航海のぶんだけ伸びる経験値バー。
/// 10時間で1レベル。累積なので休んでも減らず、反ストリークの原則には触れない。
/// バーは「前の位置」から描き始め、今回のぶんだけ伸びる様子をその場で見せる。
private struct VoyageLevelBar: View {
    let gainedMinutes: Int
    let after: PlayerLevelProgress
    let ink: Color

    private let before: PlayerLevelProgress

    @State private var displayedLevel: Int
    @State private var fill: Double
    @State private var leveledUp = false
    @State private var animated = false

    init(gainedMinutes: Int, after: PlayerLevelProgress, ink: Color) {
        self.gainedMinutes = gainedMinutes
        self.after = after
        self.ink = ink
        let before = PlayerLevelProgress(totalMinutes: after.totalMinutes - max(0, gainedMinutes))
        self.before = before
        _displayedLevel = State(initialValue: before.level)
        _fill = State(initialValue: before.fractionToNextLevel)
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Text(verbatim: "LV \(displayedLevel)")
                    .font(LFFont.label(10))
                    .tracking(1.5)
                    .monospacedDigit()
                    .foregroundStyle(leveledUp ? LFColor.returnOrange : ink.opacity(0.62))

                Spacer(minLength: 0)

                Text(verbatim: "+\(LF.duration(minutes: max(0, gainedMinutes)))")
                    .font(LFFont.label(10))
                    .tracking(1.5)
                    .monospacedDigit()
                    .foregroundStyle(ink.opacity(0.48))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ink.opacity(0.13))

                    Capsule()
                        .fill(LFColor.returnOrange)
                        .frame(width: max(0, geo.size.width * fill))
                }
            }
            .frame(height: 6)

            Text(caption)
                .font(LFFont.label(10))
                .tracking(leveledUp ? 2 : 0.4)
                .foregroundStyle(leveledUp ? LFColor.returnOrange : ink.opacity(0.44))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Level \(after.level)"))
        .accessibilityValue(Text(caption))
        .task { await runFill() }
    }

    private var caption: String {
        leveledUp
            ? LF.text("LEVEL UP")
            : LF.format(
                "%@ to Level %lld",
                LF.duration(minutes: after.minutesToNextLevel),
                after.level + 1
            )
    }

    /// 札が落ち着いてからバーを伸ばす。レベルが上がるぶんだけ、満たして空にするのを繰り返す。
    private func runFill() async {
        guard !animated else { return }
        animated = true

        try? await Task.sleep(for: .milliseconds(420))

        // 手入力で何段も飛ぶ場合まで律儀に見せると長いので、演出は3段までにする。
        var level = before.level
        var cycles = 0
        while level < after.level, cycles < 3 {
            withAnimation(.easeOut(duration: 0.68)) { fill = 1 }
            try? await Task.sleep(for: .milliseconds(720))

            level += 1
            cycles += 1
            Haptics.success()
            // 空にする瞬間だけはアニメーションを外し、右端から左端へ戻る動きを見せない。
            withTransaction(Transaction(animation: nil)) {
                displayedLevel = level
                fill = 0
            }
            withAnimation(.easeOut(duration: 0.3)) { leveledUp = true }
            try? await Task.sleep(for: .milliseconds(300))
        }

        // 3段を超えて飛んだときも、最終的な表示は必ず実際のレベルに合わせる。
        displayedLevel = after.level
        withAnimation(.easeOut(duration: 0.82)) { fill = after.fractionToNextLevel }
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
    /// Reports the saved length and note. The voyage screen uses it to show its
    /// own completion card instead of dropping the player back at the pier.
    var onRecorded: ((Int, String?) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyDay.date, order: .reverse) private var days: [StudyDay]

    private static let maximumSeconds = WorkRecordPolicy.maximumSessionMinutes * 60

    @State private var totalSeconds: Int
    @State private var note = ""
    @State private var recordDate = Date()
    @State private var steppingDelta: Int?
    @State private var repeatTask: Task<Void, Never>?
    /// Hours, minutes and seconds are three ordinary fields: tap the one you
    /// mean and type it. Filling one long number from the right read as a
    /// puzzle, which is not what entering "25 minutes" should be.
    @State private var hourText = "0"
    @State private var minuteText = "00"
    @State private var secondText = "00"
    @FocusState private var noteFocused: Bool
    @FocusState private var focusedClockField: ClockField?

    private enum ClockField: Hashable {
        case hour
        case minute
        case second
    }

    init(
        item: StudyItem,
        initialMinutes: Int,
        onSaved: @escaping () -> Void,
        onRecorded: ((Int, String?) -> Void)? = nil
    ) {
        self.item = item
        self.initialMinutes = initialMinutes
        self.onSaved = onSaved
        self.onRecorded = onRecorded
        _totalSeconds = State(initialValue: min(Self.maximumSeconds, max(0, initialMinutes * 60)))
    }

    private static func clamped(_ seconds: Int) -> Int {
        min(maximumSeconds, max(0, seconds))
    }

    /// Reads the three fields. Minutes and seconds above 59 simply carry, so
    /// typing "90" into minutes gives an hour and a half rather than an error.
    private func applyClockFields() {
        let hours = Int(hourText) ?? 0
        let minutes = Int(minuteText) ?? 0
        let seconds = Int(secondText) ?? 0
        totalSeconds = Self.clamped(hours * 3_600 + minutes * 60 + seconds)
    }

    private func syncClockFields() {
        hourText = String(totalSeconds / 3_600)
        minuteText = String(format: "%02d", (totalSeconds % 3_600) / 60)
        secondText = String(format: "%02d", totalSeconds % 60)
    }

    private var clockSeparator: some View {
        Text(verbatim: ":")
            .font(LFFont.number(34))
            .foregroundStyle(LFColor.ink.opacity(0.32))
            .padding(.bottom, 14)
    }

    private func clockField(
        _ field: ClockField,
        text: Binding<String>,
        unit: LocalizedStringKey,
        label: LocalizedStringKey
    ) -> some View {
        VStack(spacing: 2) {
            TextField("", text: text)
                .font(LFFont.number(42))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .foregroundStyle(
                    focusedClockField == field ? LFColor.returnOrange : LFColor.ink
                )
                .focused($focusedClockField, equals: field)
                .frame(width: 74)
                .onChange(of: text.wrappedValue) { _, value in
                    let digits = String(value.filter(\.isNumber).prefix(field == .hour ? 3 : 2))
                    if digits != value { text.wrappedValue = digits }
                    applyClockFields()
                }
                .onChange(of: focusedClockField) { previous, current in
                    // Tapping a field clears it so typing replaces rather than
                    // appends; leaving it empty falls back to zero.
                    if current == field { text.wrappedValue = "" }
                    if previous == field, text.wrappedValue.isEmpty {
                        text.wrappedValue = "0"
                        applyClockFields()
                        syncClockFields()
                    }
                }
                .accessibilityLabel(Text(label))

            Text(unit)
                .font(LFFont.label(10))
                .foregroundStyle(LFColor.ink.opacity(0.46))
        }
    }

    /// One second per tap, and a run of seconds while held — the whole control
    /// is these two buttons, so holding has to cover the distance that rows of
    /// preset amounts used to.
    private func stepButton(_ delta: Int, symbol: String, label: LocalizedStringKey) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(LFColor.ink.opacity(0.72))
            .frame(width: 38, height: 38)
            .background(Circle().fill(LFColor.ink.opacity(steppingDelta == delta ? 0.12 : 0.05)))
            .overlay(Circle().stroke(LFColor.ink.opacity(0.16), lineWidth: 1))
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in beginStepping(delta) }
                    .onEnded { _ in endStepping() }
            )
            .accessibilityLabel(Text(label))
    }

    private func beginStepping(_ delta: Int) {
        // A drag reports continuously; only the first report starts a run.
        guard steppingDelta == nil else { return }
        steppingDelta = delta
        adjust(by: delta)
        Haptics.tap(.light)
        repeatTask = Task { @MainActor in
            // A moment's grace so a tap stays a tap, then an accelerating run.
            try? await Task.sleep(for: .milliseconds(420))
            var interval = 90
            var ticks = 0
            while !Task.isCancelled {
                adjust(by: delta)
                ticks += 1
                if ticks % 10 == 0 { Haptics.tap(.light) }
                try? await Task.sleep(for: .milliseconds(interval))
                interval = max(16, interval - 4)
            }
        }
    }

    private func endStepping() {
        steppingDelta = nil
        repeatTask?.cancel()
        repeatTask = nil
    }

    private func adjust(by delta: Int) {
        totalSeconds = Self.clamped(totalSeconds + delta)
        syncClockFields()
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

                    HStack(spacing: 10) {
                        stepButton(-1, symbol: "minus", label: "One second less")

                        HStack(spacing: 4) {
                            clockField(.hour, text: $hourText, unit: "h", label: "Hours")
                            clockSeparator
                            clockField(.minute, text: $minuteText, unit: "min", label: "Minutes")
                            clockSeparator
                            clockField(.second, text: $secondText, unit: "sec", label: "Seconds")
                        }
                        .frame(maxWidth: .infinity)

                        stepButton(1, symbol: "plus", label: "One second more")
                    }

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
                                totalSeconds > 0 ? LFColor.ink : LFColor.ink.opacity(0.28),
                                in: RoundedRectangle(cornerRadius: 17)
                            )
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .disabled(totalSeconds <= 0)
                }
                .padding(20)
            }
            .background(LFColor.paper)
            .onAppear { syncClockFields() }
            .onDisappear { endStepping() }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedClockField = nil
                        noteFocused = false
                    }
                }
            }
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
        guard AccessPolicy.isDeveloper() else {
            dismiss()
            return
        }
        let seconds = totalSeconds
        guard seconds > 0 else { return }
        let date = recordDate
        let session = StudySession(
            date: date,
            minutes: seconds / 60,
            extraSeconds: seconds % 60,
            note: WorkRecordPolicy.normalizedNote(note),
            item: item
        )
        modelContext.insert(session)
        let dayMark = StudyDayStore.markDay(
            date,
            context: modelContext,
            syncsToAccount: false
        )
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(session)
            if dayMark.wasInserted { modelContext.delete(dayMark.day) }
            return
        }
        SyncService.shared.publishPersistedSessionChanges(
            [session],
            insertedDays: dayMark.wasInserted ? [dayMark.day] : [],
            context: modelContext
        )
        Haptics.success()
        if let onRecorded {
            onRecorded(session.minutes, session.note)
        } else {
            onSaved()
        }
        dismiss()
    }
}
