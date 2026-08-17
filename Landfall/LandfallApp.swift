import Combine
import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAppCheck
import FirebaseFirestore
import GoogleSignIn

@main
struct LandfallApp: App {
    // 単一の共有コンテナ。SwiftUI が App を複数回 init しても、同じストアに対して
    // 複数のコンテナができると削除が別インスタンスの autosave で復活してしまうため、
    // static let で1つに固定する。
    private static let sharedContainer: ModelContainer = makeContainer()
    let container = LandfallApp.sharedContainer
    @StateObject private var auth = AuthService.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue
    @AppStorage(AppTheme.storageKey) private var appTheme = AppTheme.system.rawValue
    @AppStorage(PrologueState.completionKey) private var hasCompletedPrologue = false
    @AppStorage(TutorialState.completionKey) private var hasCompletedTutorial = false
    @State private var isLaunchingFirstVoyage = false
    @State private var dismissedForcedPrologue = false
    @State private var dismissedForcedTutorial = false

    init() {
        // App Check は FirebaseApp.configure() の前に工場を差し込む必要がある。
        // 本物のアプリからのアクセスであることを裏で証明し、バックエンド濫用を防ぐ。
        AppCheck.setAppCheckProviderFactory(LandfallAppCheckProviderFactory())
        FirebaseApp.configure()
        // オフライン永続を明示。ネットに繋がらない間の書き込みも端末に貯め、
        // 再起動をまたいで保持し、オンライン復帰時に自動送信する。
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = settings
        // container は sharedContainer から初期化済み(全 init で同一インスタンス)。
    }

    /// 永続コンテナを用意する。破損や移行不能で失敗しても即クラッシュさせず、
    /// 壊れたローカルストアを退避して作り直す。記録はクラウド(Firestore)に
    /// 控えがあり、次回サインイン時の同期で戻る。
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([StudyDay.self, StudyItem.self, StudySession.self, Destination.self])
        let config = ModelConfiguration(schema: schema)
        #if DEBUG
        // 動作確認用データ投入時は毎回まっさらから始める。SwiftData の削除永続化に依存せず、
        // コンテナを開く前にストアファイルを消す。本番(SEEDなし)には一切影響しない。
        if ProcessInfo.processInfo.environment["LANDFALL_SEED"] != nil {
            wipeStoreFiles(base: config.url)
        }
        #endif
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            // ストア本体と付随ファイル(-shm / -wal)を削除して再生成を試みる。
            wipeStoreFiles(base: config.url)
            do {
                return try ModelContainer(for: schema, configurations: config)
            } catch {
                // 作り直しても駄目なら最終手段としてインメモリで起動(最低限使える)。
                let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return (try? ModelContainer(for: schema, configurations: memory))
                    ?? { fatalError("ModelContainer を初期化できませんでした: \(error)") }()
            }
        }
    }

    /// SwiftData ストア本体と付随ファイル(-shm / -wal)を削除する。
    private static func wipeStoreFiles(base: URL) {
        for url in [base,
                    base.deletingPathExtension().appendingPathExtension("store-shm"),
                    base.deletingPathExtension().appendingPathExtension("store-wal")] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCompletedPrologue || (Self.forcePrologue && !dismissedForcedPrologue) {
                    if isLaunchingFirstVoyage {
                        // 序章の古船から、タイマーと同じ航海中の世界へ連続して入る。
                        PrologueVoyageLaunchSceneView {
                            withAnimation(.easeInOut(duration: 0.52)) {
                                hasCompletedPrologue = true
                                dismissedForcedPrologue = true
                                isLaunchingFirstVoyage = false
                            }
                            if !auth.canEnterApp {
                                HomeVoyageAudio.shared.stop()
                            }
                        }
                        .ignoresSafeArea()
                        .transition(.opacity)
                    } else {
                        // 初回起動では認証より先に世界観の序章を見せる。
                        ForgottenSeaPrologueView(onComplete: {
                            HomeVoyageAudio.shared.play(
                                HomeVoyageSound.initialTimerSound.rawValue
                            )
                            withAnimation(.easeInOut(duration: 0.48)) {
                                isLaunchingFirstVoyage = true
                            }
                        })
                        .transition(.opacity)
                    }
                } else if auth.canEnterApp || Self.skipAuth {
                    if !hasCompletedTutorial || (Self.forceOnboarding && !dismissedForcedTutorial) {
                        // 操作を読んだら、同じ海で最初のメモと作業記録まで残す。
                        FirstVoyageExperienceView(
                            recoverPreviouslySavedRecord: !Self.forceOnboarding
                        ) {
                            withAnimation(.easeInOut(duration: 0.52)) {
                                hasCompletedTutorial = true
                                dismissedForcedTutorial = true
                            }
                        }
                        .transition(.opacity)
                    } else {
                        ContentView()
                            .transition(.opacity)
                    }
                } else if !auth.hasResolvedInitialAuthState {
                    // Firebase has not reported yet. Hold this quiet screen for
                    // the few frames it takes rather than flashing sign-in at a
                    // player whose session is about to be restored.
                    LaunchTransitionView()
                        .transition(.opacity)
                        .task {
                            try? await Task.sleep(for: .seconds(2.5))
                            auth.resolveInitialAuthStateIfPending()
                        }
                } else {
                    SignInView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.28), value: auth.hasResolvedInitialAuthState)
            .environmentObject(auth)
            // 端末言語に関わらず、最上位画面(導入・サインイン)もアプリ言語に追従。
            .environment(\.locale, (AppLanguage(rawValue: appLanguage) ?? .system).locale)
            // 端末設定に関わらず、アプリ内の外観(ライト/ダーク)設定に追従。
            .preferredColorScheme((AppTheme(rawValue: appTheme) ?? .system).colorScheme)
            #if DEBUG
            // 動作確認用データの投入。mainContext(UIと同一)に対し、起動ごとに一度だけ。
            .task { DebugSeed.seedIfRequested(into: container) }
            #endif
            .onOpenURL { url in
                // 招待リンク(入港証)を先に見る。該当しなければサインインの折り返しとして扱う。
                if DeepLinkRouter.shared.handle(url) { return }
                GIDSignIn.sharedInstance.handle(url)
            }
            .onAppear {
                StudyTimer.migrateLegacyTimerIfNeeded()
                WidgetTimerInbox.importPending(context: container.mainContext)
                WidgetBridge.refresh(context: container.mainContext)
                if let uid = auth.user?.uid {
                    Task {
                        await LocalAccountData.prepareForSignedInUser(
                            uid: uid,
                            context: container.mainContext
                        )
                        await SyncService.shared.performInitialSync(
                            context: container.mainContext
                        )
                    }
                }
            }
            .onChange(of: auth.user?.uid) { oldUID, newUID in
                if let newUID {
                    Task {
                        await LocalAccountData.prepareForSignedInUser(
                            uid: newUID,
                            context: container.mainContext
                        )
                        await SyncService.shared.performInitialSync(
                            context: container.mainContext
                        )
                    }
                } else {
                    SyncService.shared.stopSync()
                    if oldUID != nil {
                        Task {
                            await LocalAccountData.clearAfterSignOut(
                                context: container.mainContext
                            )
                        }
                    }
                }
            }
            // 前面復帰のたびに再同期。他端末で追加された記録を取り込み、
            // 保留中の書き込みも送信される。ローカルは常に真実の源のまま。
            .onChange(of: scenePhase) { _, phase in
                if isLaunchingFirstVoyage {
                    if phase == .active {
                        HomeVoyageAudio.shared.play(
                            HomeVoyageSound.initialTimerSound.rawValue
                        )
                    } else {
                        HomeVoyageAudio.shared.stop()
                    }
                }
                if phase == .active {
                    WidgetTimerInbox.importPending(context: container.mainContext)
                    WidgetBridge.refresh(context: container.mainContext)
                    let recorded = StudyDayStore.recordedToday(context: container.mainContext)
                    Task { await NotificationService.reschedule(recordedToday: recorded) }
                    if auth.isSignedIn {
                        Task { await SyncService.shared.performInitialSync(context: container.mainContext) }
                    }
                }
            }
        }
        .modelContainer(container)
    }

    /// 動作確認用: DEBUGビルドで LANDFALL_SKIP_AUTH=1 のときだけログインを飛ばして
    /// 直接ホームに入る。Releaseビルドでは常に false(バイパス無効)。
    private static var skipAuth: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["LANDFALL_SKIP_AUTH"] == "1"
        #else
        return false
        #endif
    }

    /// 動作確認用: LANDFALL_PROLOGUE=1 で序章を強制表示する(既に見た後でも)。
    private static var forcePrologue: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["LANDFALL_PROLOGUE"] == "1"
        #else
        return false
        #endif
    }

    /// 動作確認用: LANDFALL_ONBOARD=1 でチュートリアルを強制表示する(既に見た後でも)。
    private static var forceOnboarding: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["LANDFALL_ONBOARD"] == "1"
        #else
        return false
        #endif
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue
    @AppStorage(HomeBackgroundMusic.enabledKey) private var homeMusicEnabled = false
    @AppStorage(HomeBackgroundMusic.selectedTrackKey)
    private var homeMusicTrack = HomeVoyageSound.harborMinuet.rawValue
    @AppStorage(HomeWaveAmbience.enabledKey) private var homeWavesEnabled = true
    @AppStorage(StudyTimer.startKey, store: StudyTimer.defaults) private var timerStart: Double = 0
    @AppStorage(StudyTimer.modeKey, store: StudyTimer.defaults)
    private var timerMode = HomeTimerMode.free.rawValue
    @AppStorage(StudyTimer.pomodoroStartElapsedKey, store: StudyTimer.defaults)
    private var timerPomodoroStartElapsed: Double = 0
    @AppStorage(StudyTimer.breakSecondsKey, store: StudyTimer.defaults)
    private var timerBreakSeconds: Double = 0
    @AppStorage(StudyTimer.breakStartedAtKey, store: StudyTimer.defaults)
    private var timerBreakStartedAt: Double = 0
    @AppStorage(StudyTimer.soundKey, store: StudyTimer.defaults)
    private var timerSoundMode = HomeVoyageSound.initialTimerSound.rawValue
    @State private var lastTimerResting: Bool?

    private let timerAudioClock = Timer.publish(
        every: 1,
        tolerance: 0.15,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        Group {
            #if DEBUG
            if let rawInterior = ProcessInfo.processInfo.environment["LANDFALL_INTERIOR"],
               let interior = HomeIslandInteriorKind(assetID: rawInterior) {
                HomeIslandInteriorView(kind: interior)
            } else if ProcessInfo.processInfo.environment["LANDFALL_PRIVATE_PREVIEW"] == "1" {
                PrivateIslandPreviewView()
            } else if ProcessInfo.processInfo.environment["LANDFALL_DRESS_NAV"] != nil {
                DressView()
            } else {
                VoyageHomeView()
            }
            #else
            VoyageHomeView()
            #endif
        }
        // アプリ内の言語設定を全体に反映(端末言語に関わらず切替可能)。
        .environment(\.locale, (AppLanguage(rawValue: appLanguage) ?? .system).locale)
        .onAppear {
            migrateHomeAudioSelectionIfNeeded()
            updateHomeAudio()
            #if DEBUG
            // 動作確認用: LANDFALL_LANG=en/ja/system でアプリ内言語を固定できる。
            if let raw = ProcessInfo.processInfo.environment["LANDFALL_LANG"],
               AppLanguage(rawValue: raw) != nil {
                appLanguage = raw
            }
            // 動作確認用: LANDFALL_SAIL=departure / arrival で起動直後に各アニメーションを再生する。
            if let raw = ProcessInfo.processInfo.environment["LANDFALL_SAIL"] {
                let kind: SailKind = raw == "arrival" ? .arrival : .departure
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    SailAnimator.shared.play(kind)
                }
            }
            #endif
        }
        .onChange(of: scenePhase) { _, _ in
            updateHomeAudio()
        }
        .onChange(of: timerStart) { _, _ in
            updateHomeAudio()
        }
        .onChange(of: timerMode) { _, _ in
            updateHomeAudio()
        }
        .onChange(of: timerPomodoroStartElapsed) { _, _ in
            updateHomeAudio()
        }
        .onChange(of: timerBreakSeconds) { _, _ in
            updateHomeAudio()
        }
        .onChange(of: timerBreakStartedAt) { _, _ in
            updateHomeAudio()
        }
        .onChange(of: timerSoundMode) { _, _ in
            updateHomeAudio()
        }
        .onChange(of: homeMusicEnabled) { _, _ in
            updateHomeAudio()
        }
        .onChange(of: homeMusicTrack) { _, _ in
            updateHomeAudio()
        }
        .onChange(of: homeWavesEnabled) { _, _ in
            updateHomeAudio()
        }
        .onReceive(timerAudioClock) { date in
            guard timerStart > 0 else { return }
            let resting = timerIsResting(at: date)
            guard resting != lastTimerResting else { return }
            updateHomeAudio(at: date)
        }
        .onDisappear {
            HomeBackgroundMusic.shared.stop()
            HomeWaveAmbience.shared.stop()
        }
    }

    private var timerSnapshot: HomeTimerSnapshot {
        HomeTimerSnapshot(
            startedAt: timerStart,
            mode: HomeTimerMode(rawValue: timerMode) ?? .free,
            pomodoroStartElapsed: timerPomodoroStartElapsed,
            breakSeconds: timerBreakSeconds,
            breakStartedAt: timerBreakStartedAt
        )
    }

    private func timerIsResting(at date: Date) -> Bool {
        timerSnapshot.isResting || timerSnapshot.phase(at: date)?.focusing == false
    }

    /// 航海中のBGMはタイマー画面の表示状態に依存させない。
    /// 手動休憩・ポモドーロ休憩だけ停止し、画面外やバックグラウンドでも維持する。
    private func updateHomeAudio(at date: Date = Date()) {
        if timerStart > 0 {
            HomeBackgroundMusic.shared.stop()
            HomeWaveAmbience.shared.stop()

            let resting = timerIsResting(at: date)
            lastTimerResting = resting
            if resting {
                HomeVoyageAudio.shared.stop()
            } else {
                HomeVoyageAudio.shared.ensurePlaying(timerSoundMode)
            }
            return
        }

        lastTimerResting = nil
        HomeVoyageAudio.shared.stop()
        let shouldPlayHomeAudio = scenePhase == .active
        if shouldPlayHomeAudio && homeMusicEnabled {
            HomeBackgroundMusic.shared.play()
        } else {
            HomeBackgroundMusic.shared.stop()
            HomeWaveAmbience.shared.stop()
        }
    }

    /// 従来の「波音+別BGM」設定を、4択の単一音源へ一度だけ移行する。
    private func migrateHomeAudioSelectionIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: HomeBackgroundMusic.legacyWavePreferenceMigratedKey) else {
            let resolved = HomeVoyageSound.resolve(homeMusicTrack)
            if HomeBackgroundMusic.tracks.contains(resolved), resolved.rawValue != homeMusicTrack {
                homeMusicTrack = resolved.rawValue
            }
            return
        }

        if !homeMusicEnabled, homeWavesEnabled {
            homeMusicTrack = HomeVoyageSound.waves.rawValue
            homeMusicEnabled = true
        } else {
            let resolved = HomeVoyageSound.resolve(homeMusicTrack)
            homeMusicTrack = HomeBackgroundMusic.tracks.contains(resolved)
                ? resolved.rawValue
                : HomeVoyageSound.harborMinuet.rawValue
        }
        homeWavesEnabled = false
        defaults.set(true, forKey: HomeBackgroundMusic.legacyWavePreferenceMigratedKey)
    }

}
