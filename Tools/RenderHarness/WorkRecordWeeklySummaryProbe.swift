import Foundation

@main
struct WorkRecordWeeklySummaryProbe {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        func date(_ value: String) -> Date {
            ISO8601DateFormatter().date(from: value)!
        }
        func record(_ value: String, _ seconds: Int, id: String? = nil, name: String? = nil) -> WorkRecordWeeklySummary.Record {
            .init(date: date(value), seconds: seconds, itemID: id, itemName: name)
        }
        // Midweek cutoff excludes the rest of the previous week, future records,
        // zero / corrupt work, and counts multiple records on one day only once.
        let now = date("2026-09-16T03:00:00Z") // Wednesday noon JST
        let summary = WorkRecordWeeklySummary.summarize([
            record("2026-09-14T01:00:00Z", 61, id: "a", name: "Reading"),
            record("2026-09-14T02:00:00Z", 59, id: "a", name: "Reading"),
            record("2026-09-16T03:00:00Z", 30, id: "b", name: "Code"),
            record("2026-09-16T03:00:01Z", 9_999),
            record("2026-09-09T03:00:00Z", 120),
            record("2026-09-09T03:00:01Z", 9_999),
            record("2026-09-10T01:00:00Z", 9_999),
            record("2026-09-15T01:00:00Z", 0),
            record("2026-09-15T01:00:00Z", -7),
            .init(date: Date(timeIntervalSinceReferenceDate: .nan), seconds: 99)
        ], now: now, calendar: calendar)
        precondition(summary.totalSeconds == 150)
        precondition(summary.previousSeconds == 120)
        precondition(summary.differenceSeconds == 30)
        precondition(summary.activeDayCount == 2 && summary.recordCount == 3)
        precondition(summary.leadingItems.first?.id == "a" && summary.leadingItems.first?.seconds == 120)
        precondition(summary.days.reduce(0) { $0 + $1.seconds } == 150)
        precondition(summary.days.count == 7)
        precondition(summary.weekStart == date("2026-09-13T15:00:00Z"))
        // Legacy records have no endpoint. A duration extending past midnight is
        // retained entirely on its saved date; no invented end or pause dates.
        let overnight = WorkRecordWeeklySummary.summarize([
            record("2026-09-13T14:59:00Z", 7_200),
            record("2026-09-13T15:01:00Z", 3_600)
        ], now: now, calendar: calendar)
        precondition(overnight.totalSeconds == 3_600)
        precondition(overnight.previousSeconds == 0)
        precondition(overnight.activeDayCount == 1)
        // ISO week spans the year boundary.
        let newYear = WorkRecordWeeklySummary.summarize([
            record("2025-12-28T15:00:00Z", 1),
            record("2026-01-01T00:00:00Z", 2)
        ], now: date("2026-01-02T03:00:00Z"), calendar: calendar)
        precondition(newYear.weekStart == date("2025-12-28T15:00:00Z"))
        precondition(newYear.totalSeconds == 3 && newYear.activeDayCount == 2)
        // Respect a Sunday-first calendar rather than imposing ISO weeks.
        calendar.firstWeekday = 1
        let sunday = WorkRecordWeeklySummary.summarize([], now: now, calendar: calendar)
        precondition(sunday.weekStart == date("2026-09-12T15:00:00Z"))
        // Same wall clock cutoff through both DST transitions, not 7 x 24 hours.
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 2
        for (current, previous) in [
            ("2026-03-11T16:00:00Z", "2026-03-04T17:00:00Z"),
            ("2026-11-04T17:00:00Z", "2026-10-28T16:00:00Z")
        ] {
            let dst = WorkRecordWeeklySummary.summarize([
                record(previous, 17),
                .init(date: date(previous).addingTimeInterval(1), seconds: 900)
            ], now: date(current), calendar: calendar)
            precondition(dst.previousThrough == date(previous))
            precondition(dst.previousSeconds == 17)
            precondition(calendar.component(.hour, from: dst.previousThrough) == 12)
        }
        let empty = WorkRecordWeeklySummary.summarize([], now: now, calendar: calendar)
        precondition(empty.totalSeconds == 0 && empty.activeDayCount == 0 && empty.leadingItems.isEmpty)
        let overflow = WorkRecordWeeklySummary.summarize([
            .init(date: now, seconds: Int.max), .init(date: now, seconds: Int.max)
        ], now: now, calendar: calendar)
        precondition(overflow.totalSeconds == Int.max && overflow.leadingItems[0].seconds == Int.max)
        print("PASS WorkRecordWeeklySummary: exact seconds, partial week, saved-day legacy semantics, locale week, year boundary, DST, empty and corrupt inputs")
    }
}
