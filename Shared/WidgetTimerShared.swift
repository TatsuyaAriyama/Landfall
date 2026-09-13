import AppIntents
import Foundation
import WidgetKit

/// Measured chronology is separate from the session's accounting date and rounded minutes.
/// Missing timing remains unknown; it must never be reconstructed from a legacy duration.
struct WorkSessionTiming: Codable, Hashable, Sendable {
    static let maximumJSONBytes = 131_072
    static let maximumIntervals = 512
    enum Source: String, Codable, Sendable { case timer, widget }
    struct BreakInterval: Codable, Hashable, Sendable {
        let startedAt: Date
        let endedAt: Date
        var duration: Double { endedAt.timeIntervalSince(startedAt) }
    }

    let startedAt: Date
    let endedAt: Date
    let breaks: [BreakInterval]
    let totalBreakSeconds: Double
    /// False means some rest positions were never recorded (for example an upgraded active timer).
    let breakTimelineComplete: Bool
    let source: Source

    var json: String? {
        guard isValid, let data = try? JSONEncoder().encode(self),
              data.count <= Self.maximumJSONBytes else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ json: String?) -> Self? {
        guard let json, let data = json.data(using: .utf8),
              data.count <= maximumJSONBytes,
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.isValid else { return nil }
        return value
    }

    private var isValid: Bool {
        let start = startedAt.timeIntervalSince1970
        let end = endedAt.timeIntervalSince1970
        guard start.isFinite, end.isFinite, start > 0, end >= start,
              end - start <= 7 * 24 * 60 * 60,
              totalBreakSeconds.isFinite, totalBreakSeconds >= 0,
              totalBreakSeconds <= end - start + 0.01,
              breaks.count <= Self.maximumIntervals else { return false }
        var previous = startedAt
        var measured = 0.0
        for rest in breaks {
            guard rest.startedAt.timeIntervalSince1970.isFinite,
                  rest.endedAt.timeIntervalSince1970.isFinite,
                  rest.startedAt >= previous, rest.endedAt > rest.startedAt,
                  rest.endedAt <= endedAt else { return false }
            previous = rest.endedAt
            measured += rest.duration
        }
        return measured <= totalBreakSeconds + 0.01
            && (!breakTimelineComplete || abs(measured - totalBreakSeconds) < 0.01)
    }

    /// Clips out-of-range intervals and merges overlaps, including manual pauses during a Pomodoro rest.
    static func mergedBreaks(_ intervals: [BreakInterval], startedAt: Date, endedAt: Date) -> [BreakInterval] {
        let clipped = intervals.compactMap { value -> BreakInterval? in
            guard value.startedAt.timeIntervalSince1970.isFinite,
                  value.endedAt.timeIntervalSince1970.isFinite else { return nil }
            let start = max(startedAt, value.startedAt)
            let end = min(endedAt, value.endedAt)
            return end > start ? BreakInterval(startedAt: start, endedAt: end) : nil
        }.sorted { $0.startedAt < $1.startedAt }
        var result: [BreakInterval] = []
        for interval in clipped {
            if let previous = result.last, interval.startedAt <= previous.endedAt {
                result[result.count - 1] = BreakInterval(
                    startedAt: previous.startedAt, endedAt: max(previous.endedAt, interval.endedAt)
                )
            } else {
                result.append(interval)
            }
        }
        return result
    }

    /// Maps automatic Pomodoro pauses from the timer's unpaused clock into wall time.
    /// An explicit pause freezes that clock, so an automatic rest can straddle several wall intervals.
    static func pomodoroBreaks(startedAt: Date, endedAt: Date, manualBreaks: [BreakInterval], anchor: Double) -> [BreakInterval] {
        guard anchor.isFinite, anchor >= 0,
              startedAt.timeIntervalSince1970.isFinite,
              endedAt.timeIntervalSince1970.isFinite,
              endedAt >= startedAt, endedAt.timeIntervalSince(startedAt) <= 7 * 24 * 60 * 60
        else { return [] }
        let manual = mergedBreaks(manualBreaks, startedAt: startedAt, endedAt: endedAt)
        var active: [BreakInterval] = []
        var cursor = startedAt
        for rest in manual {
            if rest.startedAt > cursor { active.append(.init(startedAt: cursor, endedAt: rest.startedAt)) }
            cursor = rest.endedAt
        }
        if cursor < endedAt { active.append(.init(startedAt: cursor, endedAt: endedAt)) }
        var elapsed = 0.0
        var result: [BreakInterval] = []
        for span in active {
            let upper = elapsed + span.duration
            var cycle = max(0, Int(max(0, elapsed - anchor) / 1_800))
            while anchor + Double(cycle) * 1_800 + 1_500 < upper {
                let restStart = max(elapsed, anchor + Double(cycle) * 1_800 + 1_500)
                let restEnd = min(upper, anchor + Double(cycle + 1) * 1_800)
                if restEnd > restStart {
                    result.append(.init(
                        startedAt: span.startedAt.addingTimeInterval(restStart - elapsed),
                        endedAt: span.startedAt.addingTimeInterval(restEnd - elapsed)
                    ))
                }
                cycle += 1
            }
            elapsed = upper
        }
        return result
    }
}

/// The start timestamp binds this ledger to one timer, preventing stale intervals leaking into a new voyage.
private struct WorkTimerBreakLedger: Codable {
    let timerStartedAt: Double
    var manualBreaks: [WorkSessionTiming.BreakInterval] = []
    var previousPomodoroBreaks: [WorkSessionTiming.BreakInterval] = []
    var unlocatedPomodoroSeconds: Double = 0
    var complete = true
}

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
        static let breakLedger = "landfall.timer.breakLedger.v1"
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
        encode(WorkTimerBreakLedger(timerStartedAt: date.timeIntervalSince1970), key: Key.breakLedger)
        // Activation is committed last so readers never see a half-written timer.
        defaults.set(date.timeIntervalSince1970, forKey: Key.timerStart)
        defaults.synchronize()
    }

    static func toggleBreak(at date: Date = Date()) {
        let current = timer
        guard current.isActive(at: date) else {
            clearTimer()
            return
        }
        let now = date.timeIntervalSince1970
        if current.isResting(at: date) {
            var ledger = ledger(for: current)
            ledger.manualBreaks.append(.init(
                startedAt: Date(timeIntervalSince1970: current.breakStartedAt), endedAt: date
            ))
            constrain(&ledger, at: date)
            encode(ledger, key: Key.breakLedger)
            defaults.set(current.breakSecondsAfterEnding(at: date), forKey: Key.breakSeconds)
            defaults.set(0, forKey: Key.breakStartedAt)
        } else {
            defaults.set(current.sanitizedBreakSeconds(at: date), forKey: Key.breakSeconds)
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
            minutes: current.creditedMinutes(at: date),
            timingJSON: timing(at: date, source: .widget)?.json
        )
        var pending = pendingLandfalls
        pending.append(record)
        guard encode(pending, key: Key.pendingLandfalls) else { return nil }
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
        defaults.removeObject(forKey: Key.breakLedger)
        defaults.set("", forKey: Key.timerItem)
        defaults.set("", forKey: Key.timerItemName)
        defaults.set("free", forKey: Key.timerMode)
        defaults.set(0, forKey: Key.pomodoroStartElapsed)
        defaults.set(0, forKey: Key.breakSeconds)
        defaults.set(0, forKey: Key.breakStartedAt)
        defaults.synchronize()
    }

    /// Call before changing Pomodoro mode, while its current anchor is still available.
    static func preservePomodoroBreaks(at date: Date = Date()) {
        let current = timer
        guard current.isActive(at: date), current.timerMode == "pomodoro" else { return }
        var value = ledger(for: current)
        let manual = manualBreaks(for: current, ledger: value, at: date)
        if abs(manual.reduce(0) { $0 + $1.duration } - current.breakSecondsAfterEnding(at: date)) >= 0.05 {
            value.complete = false
        }
        if value.complete {
            value.previousPomodoroBreaks += WorkSessionTiming.pomodoroBreaks(
                startedAt: Date(timeIntervalSince1970: current.startedAt), endedAt: date,
                manualBreaks: manual,
                anchor: current.pomodoroStartElapsed
            )
        } else {
            value.unlocatedPomodoroSeconds += Double(current.elapsedSeconds(at: date) - current.workedSeconds(at: date))
        }
        constrain(&value, at: date)
        encode(value, key: Key.breakLedger)
    }

    static func timing(at date: Date = Date(), source: WorkSessionTiming.Source = .timer) -> WorkSessionTiming? {
        let current = timer
        guard current.isActive(at: date) else { return nil }
        let start = Date(timeIntervalSince1970: current.startedAt)
        let value = ledger(for: current)
        let manual = manualBreaks(for: current, ledger: value, at: date)
        let manualTotal = current.breakSecondsAfterEnding(at: date)
        // A missing or damaged ledger may still retain an exact active pause; the whole chronology remains partial.
        let manualKnown = manual.reduce(0) { $0 + $1.duration }
        var complete = value.complete && abs(manualTotal - manualKnown) < 0.05
        var allBreaks = manual + value.previousPomodoroBreaks
        if current.timerMode == "pomodoro", complete {
            allBreaks += WorkSessionTiming.pomodoroBreaks(
                startedAt: start, endedAt: date, manualBreaks: manual,
                anchor: current.pomodoroStartElapsed
            )
        }
        var merged = WorkSessionTiming.mergedBreaks(allBreaks, startedAt: start, endedAt: date)
        let knownTotal = merged.reduce(0) { $0 + $1.duration }
        let aggregate = min(date.timeIntervalSince(start), max(
            knownTotal,
            manualTotal + max(0, value.unlocatedPomodoroSeconds)
                + value.previousPomodoroBreaks.reduce(0) { $0 + $1.duration }
                + Double(current.elapsedSeconds(at: date) - current.workedSeconds(at: date))
        ))
        if merged.count > WorkSessionTiming.maximumIntervals {
            merged = []
            complete = false
        }
        let result = WorkSessionTiming(
            startedAt: start, endedAt: date, breaks: merged,
            totalBreakSeconds: complete ? knownTotal : aggregate,
            breakTimelineComplete: complete, source: source
        )
        return result.json == nil ? nil : result
    }

    private static func ledger(for current: KeelMiraWidgetTimer) -> WorkTimerBreakLedger {
        if let value = decode(WorkTimerBreakLedger.self, key: Key.breakLedger),
           value.timerStartedAt == current.startedAt { return value }
        return WorkTimerBreakLedger(timerStartedAt: current.startedAt, complete: false)
    }

    private static func manualBreaks(for current: KeelMiraWidgetTimer, ledger: WorkTimerBreakLedger, at date: Date) -> [WorkSessionTiming.BreakInterval] {
        var intervals = ledger.manualBreaks
        if current.isResting(at: date) {
            intervals.append(.init(startedAt: Date(timeIntervalSince1970: current.breakStartedAt), endedAt: date))
        }
        return WorkSessionTiming.mergedBreaks(intervals,
            startedAt: Date(timeIntervalSince1970: current.startedAt), endedAt: date)
    }

    private static func constrain(_ ledger: inout WorkTimerBreakLedger, at date: Date) {
        let start = Date(timeIntervalSince1970: ledger.timerStartedAt)
        ledger.manualBreaks = WorkSessionTiming.mergedBreaks(ledger.manualBreaks, startedAt: start, endedAt: date)
        ledger.previousPomodoroBreaks = WorkSessionTiming.mergedBreaks(ledger.previousPomodoroBreaks, startedAt: start, endedAt: date)
        if ledger.manualBreaks.count + ledger.previousPomodoroBreaks.count > WorkSessionTiming.maximumIntervals {
            ledger.unlocatedPomodoroSeconds += ledger.previousPomodoroBreaks.reduce(0) { $0 + $1.duration }
            ledger.manualBreaks = []
            ledger.previousPomodoroBreaks = []
            ledger.complete = false
        }
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

    @discardableResult
    private static func encode<T: Encodable>(_ value: T, key: String) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        defaults.set(data, forKey: key)
        return defaults.synchronize()
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
    var isResting: Bool { isResting(at: Date()) }

    func isResting(at date: Date) -> Bool {
        let now = date.timeIntervalSince1970
        return isActive(at: date)
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
        let accumulatedBreak = sanitizedBreakSeconds(at: date)
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

    func sanitizedBreakSeconds(at date: Date = Date()) -> Double {
        guard isActive(at: date), breakSeconds.isFinite else { return 0 }
        let wallElapsed = max(0, date.timeIntervalSince1970 - startedAt)
        return min(wallElapsed, max(0, breakSeconds))
    }

    func breakSecondsAfterEnding(at date: Date = Date()) -> Double {
        let now = date.timeIntervalSince1970
        guard isResting(at: date) else { return sanitizedBreakSeconds(at: date) }
        return min(
            max(0, now - startedAt),
            sanitizedBreakSeconds(at: date) + max(0, now - breakStartedAt)
        )
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
    var timingJSON: String? = nil
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
