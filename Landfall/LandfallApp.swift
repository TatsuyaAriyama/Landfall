import SwiftUI
import SwiftData
import FirebaseCore
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
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    init() {
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
        let schema = Schema([StudyDay.self, StudyItem.self, StudySession.self])
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
                if !hasSeenOnboarding || Self.forceOnboarding {
                    // 思想を先に伝える導入。ログイン壁の前に一度だけ。
                    OnboardingView { hasSeenOnboarding = true }
                } else if auth.isSignedIn || Self.skipAuth {
                    ContentView()
                } else {
                    SignInView()
                }
            }
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
                GIDSignIn.sharedInstance.handle(url)
            }
            .onAppear {
                WidgetBridge.refresh(context: container.mainContext)
                if auth.isSignedIn {
                    Task { await SyncService.shared.performInitialSync(context: container.mainContext) }
                }
            }
            .onChange(of: auth.isSignedIn) { _, isSignedIn in
                if isSignedIn {
                    Task { await SyncService.shared.performInitialSync(context: container.mainContext) }
                } else {
                    SyncService.shared.stopSync()
                }
            }
            // 前面復帰のたびに再同期。他端末で追加された記録を取り込み、
            // 保留中の書き込みも送信される。ローカルは常に真実の源のまま。
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
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

    /// 動作確認用: LANDFALL_ONBOARD=1 で導入を強制表示する(既に見た後でも)。
    private static var forceOnboarding: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["LANDFALL_ONBOARD"] == "1"
        #else
        return false
        #endif
    }
}

struct ContentView: View {
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue
    @State private var selection = ContentView.initialTab
    @StateObject private var sailAnimator = SailAnimator.shared

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)
            TraceView()
                .tabItem { Label("Trace", systemImage: "waveform") }
                .tag(1)
            HarborView()
                .tabItem { Label("Harbor", systemImage: "sailboat") }
                .tag(2)
            WrappedView()
                .tabItem {
                    Label {
                        Text("Logbook")
                    } icon: {
                        Image(systemName: "rectangle.portrait")
                    }
                }
                .tag(3)
        }
        .tint(LFColor.returnOrange)
        // 出航中の小さなタイマーチップ。どのタブでも見え、自由に動かせる。
        .overlay {
            FloatingTimerChip()
        }
        // 出航／着岸アニメーション(数秒)。記録の瞬間に全画面で帆走を見せる。
        .overlay {
            if let kind = sailAnimator.kind {
                SailingOverlay(kind: kind)
                    .transition(.opacity)
            }
        }
        // アプリ内の言語設定を全体に反映(端末言語に関わらず切替可能)。
        .environment(\.locale, (AppLanguage(rawValue: appLanguage) ?? .system).locale)
        .onAppear {
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
    }

    /// 動作確認用: DEBUGビルドで LANDFALL_TAB を渡すと初期タブを固定できる。既定は「今日」。
    private static var initialTab: Int {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["LANDFALL_TAB"], let tab = Int(raw) {
            return tab
        }
        #endif
        return 0
    }
}
