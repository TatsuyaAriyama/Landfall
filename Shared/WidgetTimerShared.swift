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
        /// 本体の AppLanguage.storageKey の控え。Widget Extension は本体の
        /// UserDefaults を読めないので、本体側が更新のたびにここへ写す。
        static let language = "widget.appLanguage"
    }

    /// 本体で選ばれている表示言語("system" / "en" / "ja")。
    static var languageOverride: String {
        get { defaults.string(forKey: Key.language) ?? "system" }
        set { defaults.set(newValue, forKey: Key.language) }
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
        guard !itemID.isEmpty else { return }
        let current = timer
        guard !current.isActive(at: date) else { return }
        clearTimer()
        defaults.set(itemID, forKey: Key.timerItem)
        defaults.set(itemName, forKey: Key.timerItemName)
        defaults.set("free", forKey: Key.timerMode)
        defaults.set(0, forKey: Key.pomodoroStartElapsed)
        defaults.set(0, forKey: Key.breakSeconds)
        defaults.set(0, forKey: Key.breakStartedAt)
        defaults.set(itemID, forKey: Key.lastItemID)
        // Activation is committed last so readers never see a half-written timer.
        defaults.set(date.timeIntervalSince1970, forKey: Key.timerStart)
        defaults.synchronize()
    }

    static func toggleBreak(at date: Date = Date()) {
        guard timer.isActive(at: date) else { return }
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
        guard current.isActive(at: date) else { return nil }
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
        // Deactivate first; the remaining fields can then be cleared safely.
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

/// Widget Extension は本体のローカライズ資源(ja.lproj)を持たない。表示文字列は
/// ここに英日で並べ、本体の言語設定の控えに合わせて選ぶ。
/// system のときだけ端末の言語に従う。
enum KeelMiraWidgetCopy {
    static var isJapanese: Bool {
        switch KeelMiraWidgetStore.languageOverride {
        case "ja": return true
        case "en": return false
        default: return Locale.preferredLanguages.first?.hasPrefix("ja") ?? false
        }
    }

    private static func pick(_ en: String, _ ja: String) -> String { isJapanese ? ja : en }

    static var sailing: String { pick("Sailing", "航海中") }
    static var resting: String { pick("Resting", "休憩中") }
    static var working: String { pick("Working", "作業中") }
    static var quietTime: String { pick("Only the time moves, quietly.", "時間だけが、静かに進む。") }

    static var resumeVoyage: String { pick("Resume the voyage", "航海を再開") }
    static var takeABreak: String { pick("Take a break", "休憩") }
    static var resume: String { pick("Resume", "再開") }
    static var breakLabel: String { pick("Break", "休憩") }
    static var landfall: String { pick("Landfall", "着岸") }

    static var todaysVoyage: String { pick("Today's voyage", "今日の航海") }
    static var minuteUnit: String { pick("min", "分") }
    static var setSailFromWidget: String { pick("Set sail", "ウィジェットから出航") }
    static var readyToSail: String { pick("Ready to sail whenever you are", "いつでも出航できます") }
    static var addItemShort: String { pick("Add a work item in the app", "アプリで作業項目を追加") }
    static var addItemLong: String { pick("Add a work item in the app first", "アプリで作業項目を追加してください") }

    static func setSail(with name: String) -> String {
        pick("Set sail with \(name)", "\(name)で出航")
    }

    /// 「今日 42」/ "Today 42" — 単位は隣に別で置く。
    static func todayCount(_ minutes: Int) -> String {
        pick("Today \(minutes)", "今日 \(minutes)")
    }

    /// 「42分」/ "42m" — 一行に収める狭い場所用。
    static func minutes(_ minutes: Int) -> String {
        pick("\(minutes)m", "\(minutes)分")
    }

    /// 「今日 42分」/ "Today 42m"。
    static func todayMinutes(_ minutes: Int) -> String {
        pick("Today \(minutes)m", "今日 \(minutes)分")
    }

    static var configurationName: String { pick("KeelMira Voyage Timer", "KeelMira 航海タイマー") }
    static var configurationDescription: String {
        pick(
            "Set sail, take a break, and make landfall from a still voyage scene.",
            "静止した航海の景色から、出航・休憩・着岸を操作できます。"
        )
    }

    /// ウィジェットギャラリーの見本に出す作業項目名。
    static var sampleItemNames: (String, String, String) {
        isJapanese ? ("読書", "執筆", "勉強") : ("Reading", "Writing", "Study")
    }
}

struct KeelMiraWidgetItem: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let styleToken: String
    let symbolToken: String
}

struct KeelMiraWidgetTimer: Codable, Hashable, Sendable {
    private static let maximumRecoverableDuration: Double = 7 * 24 * 60 * 60

    let startedAt: Double
    let itemID: String
    let itemName: String
    let timerMode: String
    let pomodoroStartElapsed: Double
    let breakSeconds: Double
    let breakStartedAt: Double

    var isActive: Bool { isActive(at: Date()) }
    var isResting: Bool {
        let now = Date().timeIntervalSince1970
        return isActive
            && breakStartedAt.isFinite
            && breakStartedAt >= startedAt
            && breakStartedAt <= now
    }

    func isActive(at date: Date) -> Bool {
        let now = date.timeIntervalSince1970
        return now.isFinite
            && startedAt.isFinite
            && startedAt > 0
            && startedAt <= now
            && now - startedAt <= Self.maximumRecoverableDuration
            && !itemID.isEmpty
    }

    func elapsedSeconds(at date: Date = Date()) -> Int {
        guard isActive(at: date) else { return 0 }
        let now = date.timeIntervalSince1970
        let wallElapsed = max(0, now - startedAt)
        let accumulatedBreak = breakSeconds.isFinite
            ? min(wallElapsed, max(0, breakSeconds))
            : 0
        let activeBreak: Double
        if breakStartedAt.isFinite,
           breakStartedAt >= startedAt,
           breakStartedAt <= now {
            activeBreak = min(
                max(0, wallElapsed - accumulatedBreak),
                max(0, now - breakStartedAt)
            )
        } else {
            activeBreak = 0
        }
        let elapsed = max(0, wallElapsed - accumulatedBreak - activeBreak)
        guard elapsed.isFinite, elapsed < Double(Int.max) else { return 0 }
        return Int(elapsed)
    }

    func workedSeconds(at date: Date = Date()) -> Int {
        let elapsed = elapsedSeconds(at: date)
        guard timerMode == "pomodoro" else { return elapsed }
        let anchor: Int
        if pomodoroStartElapsed.isFinite {
            anchor = min(
                elapsed,
                max(0, Int(min(pomodoroStartElapsed, Double(Int.max - 1))))
            )
        } else {
            anchor = 0
        }
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
