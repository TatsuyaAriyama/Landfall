import Foundation

@main
enum WorkRecordTimelineProbe {
    static func main() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
        func record(_ timing: WorkRecordTimeline.Timing?, accounting: Date, seconds: Int = 3600) -> WorkRecordTimeline.Record {
            .init(id: UUID(), date: accounting, seconds: seconds, timing: timing)
        }
        let start = date("2026-09-12T23:30:00+09:00")
        let midnight = date("2026-09-13T00:00:00+09:00")
        let end = date("2026-09-13T01:00:00+09:00")
        let crossDay = record(.init(
            start: start, end: end,
            breaks: [.init(start: date("2026-09-12T23:50:00+09:00"), end: date("2026-09-13T00:10:00+09:00"))],
            totalBreakSeconds: 1200, breakTimelineComplete: true
        ), accounting: start, seconds: 4200)
        let first = WorkRecordTimeline.project([crossDay], on: start, calendar: tokyo).timed[0]
        let next = WorkRecordTimeline.project([crossDay], on: midnight, calendar: tokyo).timed[0]
        precondition(first.start == start && first.end == midnight)
        precondition(first.continuesToNextDay && !first.continuesFromPreviousDay)
        precondition(next.continuesFromPreviousDay && !next.continuesToNextDay)
        precondition(first.workSeconds == 1200 && next.workSeconds == 3000)
        precondition(first.segments.last?.seconds == 600 && next.segments.first?.seconds == 600)
        precondition(first.recordedSeconds == next.recordedSeconds && next.recordedSeconds == 4200)

        let exactBoundary = record(.init(start: start, end: midnight, breaks: [], totalBreakSeconds: 0, breakTimelineComplete: true), accounting: start)
        precondition(WorkRecordTimeline.project([exactBoundary], on: midnight, calendar: tokyo).isEmpty)
        let legacy = record(nil, accounting: midnight)
        let old = WorkRecordTimeline.project([legacy], on: midnight, calendar: tokyo)
        precondition(old.timed.isEmpty && old.untimed.count == 1)
        precondition(WorkRecordTimeline.project([legacy], on: start, calendar: tokyo).isEmpty)

        let unknown = record(.init(start: start, end: end, breaks: [], totalBreakSeconds: 1200, breakTimelineComplete: false), accounting: start)
        let uncertain = WorkRecordTimeline.project([unknown], on: midnight, calendar: tokyo).timed[0]
        precondition(uncertain.workSeconds == nil && uncertain.totalUnpositionedBreakSeconds == 1200)
        precondition(uncertain.segments.count == 1 && uncertain.segments[0].kind == .unpositionedBreaks)

        let invalid: [WorkRecordTimeline.Timing] = [
            .init(start: end, end: start, breaks: [], totalBreakSeconds: 0, breakTimelineComplete: true),
            .init(start: start, end: end, breaks: [], totalBreakSeconds: .nan, breakTimelineComplete: true),
            .init(start: start, end: end, breaks: [], totalBreakSeconds: 10, breakTimelineComplete: true),
            .init(start: start, end: end, breaks: [.init(start: start.addingTimeInterval(-1), end: midnight)], totalBreakSeconds: 1801, breakTimelineComplete: true),
            .init(start: start, end: end, breaks: [.init(start: start, end: midnight), .init(start: start, end: end)], totalBreakSeconds: 0, breakTimelineComplete: true)
        ]
        for timing in invalid {
            let day = WorkRecordTimeline.project([record(timing, accounting: start)], on: start, calendar: tokyo)
            precondition(day.timed.isEmpty && day.untimed.count == 1, "Malformed timing must fall back to saved accounting data")
        }

        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for (dayStart, dayEnd, seconds) in [
            ("2026-03-08T00:00:00-08:00", "2026-03-09T00:00:00-07:00", 23 * 3600),
            ("2026-11-01T00:00:00-07:00", "2026-11-02T00:00:00-08:00", 25 * 3600)
        ] {
            let from = date(dayStart), to = date(dayEnd)
            let fullDay = record(.init(start: from, end: to, breaks: [], totalBreakSeconds: 0, breakTimelineComplete: true), accounting: from)
            let value = WorkRecordTimeline.project([fullDay], on: from, calendar: la).timed[0]
            precondition(value.workSeconds == seconds && value.end == to, "Local days are not fixed 24-hour periods")
            precondition(WorkRecordTimeline.project([fullDay], on: to, calendar: la).isEmpty)
        }
        let before = record(.init(start: start.addingTimeInterval(-600), end: start, breaks: [], totalBreakSeconds: 0, breakTimelineComplete: true), accounting: start)
        let sorted = WorkRecordTimeline.project([crossDay, before], on: start, calendar: tokyo)
        precondition(sorted.timed.map(\.id) == [before.id, crossDay.id])
        print("PASS: timeline midnight clipping, half-open boundaries, chronological order, legacy, unknown breaks, malformed data and 23/25-hour DST days")
    }
}
