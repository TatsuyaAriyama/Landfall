import SwiftData
import SwiftUI

/// 序章からホームへ初めて入るまでの、実地チュートリアル航海。
/// 既存オンボーディングの後は専用パネルを挟まず、通常タイマーそのものを使う。
struct FirstVoyageExperienceView: View {
    private let recoverPreviouslySavedRecord: Bool
    private let onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var tutorialItem: StudyItem
    @State private var showingOnboarding = true
    @State private var hasStarted = false
    @State private var isLeaving = false
    @State private var completionDelivered = false

    init(
        recoverPreviouslySavedRecord: Bool = true,
        onComplete: @escaping () -> Void
    ) {
        self.recoverPreviouslySavedRecord = recoverPreviouslySavedRecord
        self.onComplete = onComplete
        _tutorialItem = State(
            initialValue: StudyItem(
                name: LF.text("Tutorial"),
                styleToken: "midnight",
                symbolToken: "phoenix",
                sortOrder: 0
            )
        )
    }

    var body: some View {
        ZStack {
            if hasStarted {
                HomeVoyageTimerView(
                    item: tutorialItem,
                    hasDestination: false,
                    onManual: { _ in },
                    onReturnHome: {},
                    firstVoyageRequiredNote: TutorialState.requiredNote,
                    onFirstVoyageRecorded: finishExperience
                )
            } else {
                Color(hex: AftideHomePalette.voyagingNight.sky)
                    .ignoresSafeArea()
            }

            if showingOnboarding {
                OnboardingView(
                    secondaryActionTitle: nil,
                    showsSceneBackground: false
                ) {
                    withAnimation(.easeInOut(duration: 0.48)) {
                        showingOnboarding = false
                    }
                }
                .transition(.opacity)
            }
        }
        .opacity(isLeaving ? 0 : 1)
        .background(Color(hex: AftideHomePalette.voyagingNight.sky).ignoresSafeArea())
        .animation(.easeInOut(duration: 0.52), value: isLeaving)
        .onAppear(perform: beginExperienceIfNeeded)
        .onDisappear {
            HomeVoyageAudio.shared.stop()
        }
        .onChange(of: scenePhase) { _, _ in
            updateAudio()
        }
    }

    private func beginExperienceIfNeeded() {
        guard !hasStarted else {
            updateAudio()
            return
        }

        if recoverPreviouslySavedRecord,
           TutorialFirstVoyageRecorder.hasSavedRecord(context: modelContext) {
            finishExperience()
            return
        }

        StudyTimer.clearAll()
        StudyTimer.defaults.set(
            HomeVoyageSound.initialTimerSound.rawValue,
            forKey: StudyTimer.soundKey
        )
        StudyTimer.begin(
            itemID: tutorialItem.uuid.uuidString,
            itemName: tutorialItem.name
        )
        hasStarted = true

        HomeBackgroundMusic.shared.stop()
        HomeWaveAmbience.shared.stop()
        updateAudio()
    }

    private func updateAudio() {
        guard hasStarted, !isLeaving, scenePhase == .active else {
            HomeVoyageAudio.shared.stop()
            return
        }
        let selectedSound = StudyTimer.defaults.string(forKey: StudyTimer.soundKey)
            ?? HomeVoyageSound.initialTimerSound.rawValue
        HomeVoyageAudio.shared.playLooping(selectedSound)
    }

    private func finishExperience() {
        guard !completionDelivered else { return }
        completionDelivered = true
        isLeaving = true
        HomeVoyageAudio.shared.stop()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(540))
            onComplete()
        }
    }
}

/// 最初の航海を通常の作業記録として保存する。
/// StudyItem を勝手に作らず、作業メモだけを航海誌に残す。
@MainActor
enum TutorialFirstVoyageRecorder {
    /// 同じFirebaseアカウントの別端末でも同一記録に収束する、
    /// tutorial v1専用の決定的UUID。ユーザー間はFirestoreのuid階層で分離される。
    private static let sessionID = UUID(
        uuidString: "7AA82B17-918E-5F71-9B4D-2F7F1A10C601"
    )!

    static func hasSavedRecord(context: ModelContext) -> Bool {
        return fetchSession(id: sessionID, context: context) != nil
    }

    static func record(
        note: String,
        elapsedSeconds: Int,
        context: ModelContext
    ) throws {
        if fetchSession(id: sessionID, context: context) != nil { return }

        let savedNote = String(
            note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)
        )
        guard savedNote == TutorialState.requiredNote else {
            throw TutorialFirstVoyageRecordingError.invalidNote
        }

        let date = Date()
        let minutes = min(
            6_000,
            max(1, Int((Double(max(0, elapsedSeconds)) / 60).rounded()))
        )
        let session = StudySession(
            date: date,
            minutes: minutes,
            note: savedNote,
            item: nil
        )
        session.uuid = sessionID
        context.insert(session)
        // StudyDayStore.markDay は挿入直後に同期を予約するため、保存失敗時にも
        // 「記録のない学んだ日」だけが残り得る。この導線ではローカル保存が
        // 成功するまで同期せず、今回作った日だけをsessionと一緒に巻き戻す。
        let insertedDay = insertStudyDayIfNeeded(for: date, context: context)

        do {
            try context.save()
        } catch {
            context.delete(session)
            if let insertedDay {
                context.delete(insertedDay)
            }
            throw error
        }

        SyncService.shared.push(session)
        if let insertedDay {
            SyncService.shared.push(insertedDay)
        }
        PublicHarborService.shared.publishCurrentMonth(context: context)
        WidgetBridge.refresh(context: context)
        let recordedToday = StudyDayStore.recordedToday(context: context)
        Task {
            await NotificationService.reschedule(recordedToday: recordedToday)
        }
    }

    private static func fetchSession(id: UUID, context: ModelContext) -> StudySession? {
        var descriptor = FetchDescriptor<StudySession>(
            predicate: #Predicate { $0.uuid == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// 既存の日はそのまま使い、今回の記録のために新規挿入した場合だけ返す。
    /// 呼び出し側は保存失敗時に返却値だけを削除できるため、既存コメントや
    /// 別セッションに紐づくStudyDayを誤って巻き戻さない。
    private static func insertStudyDayIfNeeded(
        for date: Date,
        context: ModelContext
    ) -> StudyDay? {
        let dayStart = Calendar.current.startOfDay(for: date)
        var descriptor = FetchDescriptor<StudyDay>(
            predicate: #Predicate { $0.date == dayStart }
        )
        descriptor.fetchLimit = 1
        if (try? context.fetch(descriptor).first) != nil {
            return nil
        }

        let day = StudyDay(date: dayStart)
        context.insert(day)
        return day
    }
}

private enum TutorialFirstVoyageRecordingError: Error {
    case invalidNote
}
