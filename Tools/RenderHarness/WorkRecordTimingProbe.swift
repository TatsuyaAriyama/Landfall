import Foundation

@main
struct WorkRecordTimingProbe {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }
    static let start = Date(timeIntervalSince1970: 1_800_000_000)
    static func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }
    static func reset() {
        KeelMiraWidgetStore.clearTimer()
        KeelMiraWidgetStore.pendingLandfalls = []
    }
    static func begin() {
        reset()
        KeelMiraWidgetStore.start(itemID: "probe-item", itemName: "Probe", at: start)
    }
    static func main() throws {
        // The shell runner changes only the test copy's suite identifier to a UUID-backed sandbox.
        precondition(KeelMiraWidgetStore.appGroup.hasPrefix("keelmira-timing-probe."))
        defer { KeelMiraWidgetStore.defaults.removePersistentDomain(forName: KeelMiraWidgetStore.appGroup) }
        begin()
        let zeroBreak = KeelMiraWidgetStore.timing(at: at(90))!
        check(zeroBreak.startedAt == start && zeroBreak.endedAt == at(90), "actual timer boundaries")
        check(zeroBreak.breakTimelineComplete && zeroBreak.breaks.isEmpty, "fresh free timer complete")
        check(WorkSessionTiming.decode(zeroBreak.json) == zeroBreak, "canonical JSON round trip")
        check(WorkSessionTiming.decode(nil) == nil && WorkSessionTiming.decode("{}") == nil, "legacy/invalid remain unknown")

        KeelMiraWidgetStore.toggleBreak(at: at(30))
        KeelMiraWidgetStore.toggleBreak(at: at(50))
        KeelMiraWidgetStore.toggleBreak(at: at(80))
        let resting = KeelMiraWidgetStore.timing(at: at(95))!
        check(resting.breaks.count == 2 && resting.totalBreakSeconds == 35, "closed and open manual rests")
        check(resting.breaks[1].endedAt == at(95), "active rest clips to landing time")
        check(resting.breakTimelineComplete, "fresh ledger maintains complete chronology")
        let landfall = KeelMiraWidgetStore.makeLandfall(at: at(95))!
        check(WorkSessionTiming.decode(landfall.timingJSON)?.source == .widget, "widget writes trustworthy source")
        check(WorkSessionTiming.decode(landfall.timingJSON)?.totalBreakSeconds == 35, "widget inbox preserves pauses")
        check(KeelMiraWidgetStore.pendingLandfalls.first?.id == landfall.id, "landing persisted before timer cleared")
        check(KeelMiraWidgetStore.timer.startedAt == 0, "successful widget landing clears timer")
        let legacyJSON = """
        {"id":"1E1B5784-FE54-4CD4-9CA4-C2DA2C1F3C58","itemID":"probe-item","itemName":"Probe","finishedAt":700000000,"minutes":25}
        """
        let legacy = try JSONDecoder().decode(KeelMiraPendingLandfall.self, from: Data(legacyJSON.utf8))
        check(legacy.timingJSON == nil && legacy.minutes == 25, "old inbox Codable remains compatible")
        let roundTrip = try JSONDecoder().decode(KeelMiraPendingLandfall.self, from: JSONEncoder().encode(landfall))
        check(roundTrip == landfall, "new inbox Codable round trip")

        begin()
        KeelMiraWidgetStore.defaults.removeObject(forKey: KeelMiraWidgetStore.Key.breakLedger)
        KeelMiraWidgetStore.defaults.set(17, forKey: KeelMiraWidgetStore.Key.breakSeconds)
        let migrated = KeelMiraWidgetStore.timing(at: at(100))!
        check(!migrated.breakTimelineComplete && migrated.breaks.isEmpty, "unknown legacy pauses are not placed on a clock")
        check(migrated.totalBreakSeconds == 17, "legacy cumulative rest retained")
        KeelMiraWidgetStore.toggleBreak(at: at(110))
        KeelMiraWidgetStore.toggleBreak(at: at(120))
        let resumedLegacy = KeelMiraWidgetStore.timing(at: at(130))!
        check(!resumedLegacy.breakTimelineComplete && resumedLegacy.breaks.count == 1, "new exact pause does not erase legacy uncertainty")
        check(resumedLegacy.totalBreakSeconds == 27, "legacy and newly measured aggregate")

        begin()
        KeelMiraWidgetStore.defaults.set("pomodoro", forKey: KeelMiraWidgetStore.Key.timerMode)
        KeelMiraWidgetStore.toggleBreak(at: at(1550))
        KeelMiraWidgetStore.toggleBreak(at: at(1650))
        let pomodoro = KeelMiraWidgetStore.timing(at: at(1950))!
        check(pomodoro.breakTimelineComplete && pomodoro.breaks.count == 1, "manual pause during automatic break merges")
        check(pomodoro.breaks[0].startedAt == at(1500) && pomodoro.breaks[0].endedAt == at(1900), "Pomodoro clock freezes during explicit pause")
        check(pomodoro.totalBreakSeconds == 400, "rest overlap not double counted")
        KeelMiraWidgetStore.preservePomodoroBreaks(at: at(1950))
        KeelMiraWidgetStore.defaults.set("free", forKey: KeelMiraWidgetStore.Key.timerMode)
        let returnedToFree = KeelMiraWidgetStore.timing(at: at(2050))!
        check(returnedToFree.totalBreakSeconds == 400, "mode switch retains actual automatic pauses")
        KeelMiraWidgetStore.defaults.set(1950, forKey: KeelMiraWidgetStore.Key.pomodoroStartElapsed)
        KeelMiraWidgetStore.defaults.set("pomodoro", forKey: KeelMiraWidgetStore.Key.timerMode)
        let switchedAgain = KeelMiraWidgetStore.timing(at: at(3700))!
        check(switchedAgain.breaks.count == 2 && switchedAgain.totalBreakSeconds == 550, "second Pomodoro anchor retains previous mode history")

        let midnight = ISO8601DateFormatter().date(from: "2026-09-13T23:58:00+09:00")!
        reset()
        KeelMiraWidgetStore.start(itemID: "midnight", itemName: "Midnight", at: midnight)
        KeelMiraWidgetStore.toggleBreak(at: midnight.addingTimeInterval(60))
        let crossing = KeelMiraWidgetStore.timing(at: midnight.addingTimeInterval(240))!
        var japan = Calendar(identifier: .gregorian)
        japan.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        check(!japan.isDate(crossing.startedAt, inSameDayAs: crossing.endedAt), "actual chronology crosses midnight")
        check(crossing.totalBreakSeconds == 180, "midnight does not truncate a pause")

        let clipped = WorkSessionTiming.mergedBreaks([
            .init(startedAt: at(-10), endedAt: at(10)),
            .init(startedAt: at(5), endedAt: at(30)),
            .init(startedAt: at(50), endedAt: at(110)),
            .init(startedAt: at(80), endedAt: at(70))
        ], startedAt: start, endedAt: at(100))
        check(clipped.count == 2 && clipped.map(\.duration) == [30, 50], "clips bounds, merges overlaps, discards reversed spans")
        let malformed = WorkSessionTiming(startedAt: start, endedAt: at(100), breaks: clipped, totalBreakSeconds: 0, breakTimelineComplete: true, source: .timer)
        check(malformed.json == nil, "inconsistent measured totals rejected")
        let outOfBounds = WorkSessionTiming(startedAt: start, endedAt: at(100), breaks: [.init(startedAt: at(-1), endedAt: at(3))], totalBreakSeconds: 4, breakTimelineComplete: true, source: .timer)
        check(outOfBounds.json == nil, "out of session intervals rejected on serialization")
        let excessive = WorkSessionTiming(startedAt: start, endedAt: at(8 * 86400), breaks: [], totalBreakSeconds: 0, breakTimelineComplete: true, source: .timer)
        check(excessive.json == nil, "unrecoverable duration rejected")
        check(WorkSessionTiming.decode(String(repeating: " ", count: WorkSessionTiming.maximumJSONBytes + 1)) == nil, "oversized sync payload rejected")
        print("Work record timing: \(checks) checks passed")
    }
}
