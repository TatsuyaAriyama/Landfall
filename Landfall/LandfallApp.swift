import SwiftUI
import SwiftData

@main
struct LandfallApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: StudyDay.self, StudyItem.self, StudySession.self)
        } catch {
            fatalError("ModelContainer の初期化に失敗しました: \(error)")
        }
        #if DEBUG
        DebugSeed.seedIfRequested(into: container)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}

struct ContentView: View {
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue
    @State private var selection = ContentView.initialTab

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)
            TraceView()
                .tabItem { Label("Trace", systemImage: "waveform") }
                .tag(1)
            WrappedView()
                .tabItem {
                    Label {
                        Text(verbatim: "Wrapped")
                    } icon: {
                        Image(systemName: "rectangle.portrait")
                    }
                }
                .tag(2)
        }
        .tint(LFColor.returnOrange)
        // アプリ内の言語設定を全体に反映(端末言語に関わらず切替可能)。
        .environment(\.locale, (AppLanguage(rawValue: appLanguage) ?? .system).locale)
        .onAppear {
            #if DEBUG
            // 動作確認用: LANDFALL_LANG=en/ja/system でアプリ内言語を固定できる。
            if let raw = ProcessInfo.processInfo.environment["LANDFALL_LANG"],
               AppLanguage(rawValue: raw) != nil {
                appLanguage = raw
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
