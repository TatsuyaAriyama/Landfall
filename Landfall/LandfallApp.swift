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
    @State private var selection = ContentView.initialTab

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label("ホーム", systemImage: "house") }
                .tag(0)
            TraceView()
                .tabItem { Label("軌跡", systemImage: "waveform") }
                .tag(1)
            WrappedView()
                .tabItem { Label("Wrapped", systemImage: "rectangle.portrait") }
                .tag(2)
        }
        .tint(LFColor.returnOrange)
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
