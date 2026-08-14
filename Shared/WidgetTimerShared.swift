import AppIntents
import Foundation
import WidgetKit

/// 本体とWidget Extensionが共有する、軽量なタイマー状態。
/// SwiftData本体はWidget Extensionから直接触らず、着岸結果だけ安全な受信箱へ積む。
enum KeelMiraWidgetStore {
    static let appGroup = "group.com.tatsuyaariyama.Landfall"
    static let widgetKind = "LandfallWidget"
    static let defaults = UserDefaults(suiteName: appGroup) ?? .standard

    enum Key {
        static let timerStart = "landfall.timer.start"
        static let timerItem = "landfall.timer.item"
        static let timerItemName = "landfall.timer.itemName"
        static let timerMode = "landfall.timer.mode"
        static let pomodoroStartElapsed = "landfall.timer.pomodoroStartElapsed"
        static let breakSeconds = "landfall.timer.breakSeconds"
        static let breakStartedAt = "landfall.timer.breakStartedAt"
        static let sound = "landfall.timer.sound"
        static let workItems = "widget.workItems.v1"
        static let pendingLandfalls = "widget.pendingLandfalls.v1"
        static let todayMinutes = "widget.todayMinutes"
        static let lastItemID = "widget.lastItemID"
        static let voyageImageName = "widget-voyage-still.jpg"
    }

    static var workItems: [KeelMiraWidgetItem] {
        get { decode([KeelMiraWidgetItem].self, key: Key.workItems) ?? [] }
        set { encode(newValue, key: Key.workItems) }
    }

    static var pendingLandfalls: [KeelMiraPendingLandfall] {
        get { decode([KeelMiraPendingLandfall].self, key: Key.pendingLandfalls) ?? [] }
        set { encode(newValue, key: Key.pendingLandfalls) }
    }

    static var timer: KeelMiraWidgetTimer {
        KeelMiraWidgetTimer(
            startedAt: defaults.double(forKey: Key.timerStart),
            itemID: defaults.string(forKey: Key.timerItem) ?? "",
            itemName: defaults.string(forKey: Key.timerItemName) ?? "",
            timerMode: defaults.string(forKey: Key.timerMode) ?? "free",
            pomodoroStartElapsed: defaults.double(forKey: Key.pomodoroStartElapsed),
            breakSeconds: defaults.double(forKey: Key.breakSeconds),
            breakStartedAt: defaults.double(forKey: Key.breakStartedAt)
        )
    }

    static func start(itemID: String, itemName: String, at date: Date = Date()) {
        guard timer.startedAt <= 0 else { return }
        defaults.set(date.timeIntervalSince1970, forKey: Key.timerStart)
        defaults.set(itemID, forKey: Key.timerItem)
        defaults.set(itemName, forKey: Key.timerItemName)
        defaults.set("free", forKey: Key.timerMode)
        defaults.set(0, forKey: Key.pomodoroStartElapsed)
        defaults.set(0, forKey: Key.breakSeconds)
        defaults.set(0, forKey: Key.breakStartedAt)
        defaults.set(itemID, forKey: Key.lastItemID)
        defaults.synchronize()
    }

    static func toggleBreak(at date: Date = Date()) {
        guard timer.startedAt > 0 else { return }
        let now = date.timeIntervalSince1970
        let restingSince = defaults.double(forKey: Key.breakStartedAt)
        if restingSince > 0 {
            let accumulated = defaults.double(forKey: Key.breakSeconds)
            defaults.set(accumulated + max(0, now - restingSince), forKey: Key.breakSeconds)
            defaults.set(0, forKey: Key.breakStartedAt)
        } else {
            defaults.set(now, forKey: Key.breakStartedAt)
        }
        defaults.synchronize()
    }

    @discardableResult
    static func makeLandfall(at date: Date = Date()) -> KeelMiraPendingLandfall? {
        let current = timer
        guard current.startedAt > 0, !current.itemID.isEmpty else { return nil }
        // Interactive Widgetは出航ボタンのタップ中に表示が航海中へ切り替わる。
        // 同じタップの指が、切り替え後の「着岸」へ誤って落ちるのを防ぐ。
        guard current.elapsedSeconds(at: date) >= 2 else { return nil }
        let record = KeelMiraPendingLandfall(
            id: UUID(),
            itemID: current.itemID,
            itemName: current.itemName,
            finishedAt: date,
            minutes: current.creditedMinutes(at: date)
        )
        var pending = pendingLandfalls
        pending.append(record)
        pendingLandfalls = pending
        defaults.set(
            defaults.integer(forKey: Key.todayMinutes) + record.minutes,
            forKey: Key.todayMinutes
        )
        clearTimer()
        return record
    }

    static func clearTimer() {
        defaults.set(0, forKey: Key.timerStart)
        defaults.set("", forKey: Key.timerItem)
        defaults.set("", forKey: Key.timerItemName)
        defaults.set("free", forKey: Key.timerMode)
        defaults.set(0, forKey: Key.pomodoroStartElapsed)
        defaults.set(0, forKey: Key.breakSeconds)
        defaults.set(0, forKey: Key.breakStartedAt)
        defaults.synchronize()
    }

    static var voyageImageURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(Key.voyageImageName)
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
        defaults.synchronize()
    }
}

struct KeelMiraWidgetItem: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let styleToken: String
    let symbolToken: String
}

struct KeelMiraWidgetTimer: Codable, Hashable, Sendable {
    let startedAt: Double
    let itemID: String
    let itemName: String
    let timerMode: String
    let pomodoroStartElapsed: Double
    let breakSeconds: Double
    let breakStartedAt: Double

    var isActive: Bool { startedAt > 0 && !itemID.isEmpty }
    var isResting: Bool { isActive && breakStartedAt > 0 }

    func elapsedSeconds(at date: Date = Date()) -> Int {
        guard isActive else { return 0 }
        let now = date.timeIntervalSince1970
        let activeBreak = isResting ? max(0, now - breakStartedAt) : 0
        return max(0, Int(now - startedAt - breakSeconds - activeBreak))
    }

    func workedSeconds(at date: Date = Date()) -> Int {
        let elapsed = elapsedSeconds(at: date)
        guard timerMode == "pomodoro" else { return elapsed }
        let anchor = min(elapsed, max(0, Int(pomodoroStartElapsed)))
        let pomodoroElapsed = max(0, elapsed - anchor)
        let cycles = pomodoroElapsed / 1_800
        return anchor + cycles * 1_500 + min(pomodoroElapsed % 1_800, 1_500)
    }

    func creditedMinutes(at date: Date = Date()) -> Int {
        min(6_000, max(1, Int((Double(workedSeconds(at: date)) / 60).rounded())))
    }

    /// `Text(date, style: .timer)`が休憩を除いた経過時間を表示するための基準日時。
    func displayAnchor(at date: Date = Date()) -> Date {
        date.addingTimeInterval(-Double(elapsedSeconds(at: date)))
    }
}

struct KeelMiraPendingLandfall: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let itemID: String
    let itemName: String
    let finishedAt: Date
    let minutes: Int
}

struct StartKeelMiraVoyageIntent: AppIntent {
    static var title: LocalizedStringResource = "Set sail"
    static var description = IntentDescription("Start a KeelMira voyage timer.")

    @Parameter(title: "Work item") var itemID: String
    @Parameter(title: "Name") var itemName: String

    init() {
        itemID = ""
        itemName = ""
    }

    init(item: KeelMiraWidgetItem) {
        itemID = item.id
        itemName = item.name
    }

    func perform() async throws -> some IntentResult {
        KeelMiraWidgetStore.start(itemID: itemID, itemName: itemName)
        WidgetCenter.shared.reloadTimelines(ofKind: KeelMiraWidgetStore.widgetKind)
        return .result()
    }
}

struct ToggleKeelMiraBreakIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause or resume voyage"

    func perform() async throws -> some IntentResult {
        KeelMiraWidgetStore.toggleBreak()
        WidgetCenter.shared.reloadTimelines(ofKind: KeelMiraWidgetStore.widgetKind)
        return .result()
    }
}

struct MakeKeelMiraLandfallIntent: AppIntent {
    static var title: LocalizedStringResource = "Make landfall"

    func perform() async throws -> some IntentResult {
        KeelMiraWidgetStore.makeLandfall()
        WidgetCenter.shared.reloadTimelines(ofKind: KeelMiraWidgetStore.widgetKind)
        return .result()
    }
}
