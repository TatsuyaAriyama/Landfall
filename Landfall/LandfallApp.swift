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
    @AppStorage(TutorialState.completionKey) private var hasCompletedTutorial = false
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
                if auth.canEnterApp || Self.skipAuth {
                    if !hasCompletedTutorial || (Self.forceOnboarding && !dismissedForcedTutorial) {
                        // サインイン後、実際の航海へ入る直前に操作を一度だけ案内する。
                        OnboardingView {
                            hasCompletedTutorial = true
                            dismissedForcedTutorial = true
                        }
                    } else {
                        ContentView()
                    }
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
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.environment["LANDFALL_PRIVATE_PREVIEW"] == "1" {
                NavigationStack {
                    HarborChatView(
                        room: HarborRoom(
                            id: "W7D3UD",
                            name: "星影の並走船団",
                            memberIds: ["preview-self", "preview-akari", "preview-nagi"],
                            ownerUid: "preview-self"
                        )
                    )
                }
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

}
