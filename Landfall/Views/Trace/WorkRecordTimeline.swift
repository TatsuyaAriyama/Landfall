import Foundation

/// Calendar-aware projection. The saved accounting date is never used to invent a clock time.
enum WorkRecordTimeline {
    struct Interval: Equatable {
        let start: Date
        let end: Date
    }

    struct Timing {
        let start: Date
        let end: Date
        let breaks: [Interval]
        let totalBreakSeconds: Double
        let breakTimelineComplete: Bool
    }

    struct Record {
        let id: UUID
        let date: Date
        let seconds: Int
        let timing: Timing?
    }

    enum SegmentKind { case work, rest, unpositionedBreaks }

    struct Segment: Identifiable {
        var id: String { "\(kind)-\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)" }
        let kind: SegmentKind
        let start: Date
        let end: Date
        var seconds: Int { max(0, Int(end.timeIntervalSince(start).rounded())) }
    }

    struct Entry: Identifiable {
        let id: UUID
        let start: Date
        let end: Date
        let continuesFromPreviousDay: Bool
        let continuesToNextDay: Bool
        let segments: [Segment]
        /// nil means breaks were recorded only as a cumulative duration.
        let workSeconds: Int?
        let recordedSeconds: Int
        let totalUnpositionedBreakSeconds: Int
    }

    struct Day {
        let timed: [Entry]
        let untimed: [Record]
        var isEmpty: Bool { timed.isEmpty && untimed.isEmpty }
    }

    static func project(_ records: [Record], on day: Date, calendar: Calendar = .current) -> Day {
        guard let bounds = calendar.dateInterval(of: .day, for: day) else {
            return Day(timed: [], untimed: [])
        }
        var timed: [Entry] = []
        var untimed: [Record] = []
        for record in records {
            guard let timing = record.timing, isValid(timing) else {
                if record.date >= bounds.start && record.date < bounds.end { untimed.append(record) }
                continue
            }
            let start = max(timing.start, bounds.start)
            let end = min(timing.end, bounds.end)
            guard end > start else { continue }
            var segments: [Segment] = []
            if timing.breakTimelineComplete {
                var cursor = timing.start
                for pause in timing.breaks.sorted(by: { $0.start < $1.start }) {
                    append(.work, from: cursor, to: pause.start, within: bounds, into: &segments)
                    append(.rest, from: pause.start, to: pause.end, within: bounds, into: &segments)
                    cursor = pause.end
                }
                append(.work, from: cursor, to: timing.end, within: bounds, into: &segments)
            } else {
                // The elapsed interval is real, but no part is presented as certain work or rest.
                segments = [Segment(kind: .unpositionedBreaks, start: start, end: end)]
            }
            timed.append(Entry(
                id: record.id, start: start, end: end,
                continuesFromPreviousDay: timing.start < bounds.start,
                continuesToNextDay: timing.end > bounds.end,
                segments: segments,
                workSeconds: timing.breakTimelineComplete
                    ? segments.filter { $0.kind == .work }.reduce(0) { $0 + $1.seconds } : nil,
                recordedSeconds: max(0, record.seconds),
                totalUnpositionedBreakSeconds: timing.breakTimelineComplete
                    ? 0 : Int(timing.totalBreakSeconds.rounded())
            ))
        }
        timed.sort { $0.start != $1.start ? $0.start < $1.start : $0.id.uuidString < $1.id.uuidString }
        untimed.sort { $0.date != $1.date ? $0.date < $1.date : $0.id.uuidString < $1.id.uuidString }
        return Day(timed: timed, untimed: untimed)
    }

    private static func isValid(_ timing: Timing) -> Bool {
        let elapsed = timing.end.timeIntervalSince(timing.start)
        guard timing.start.timeIntervalSinceReferenceDate.isFinite,
              timing.end.timeIntervalSinceReferenceDate.isFinite,
              elapsed > 0, elapsed <= 366 * 86_400,
              timing.totalBreakSeconds.isFinite,
              timing.totalBreakSeconds >= 0, timing.totalBreakSeconds <= elapsed else { return false }
        var cursor = timing.start
        var sum = 0.0
        for pause in timing.breaks.sorted(by: { $0.start < $1.start }) {
            guard pause.start.timeIntervalSinceReferenceDate.isFinite,
                  pause.end.timeIntervalSinceReferenceDate.isFinite,
                  pause.start >= cursor, pause.end > pause.start,
                  pause.end <= timing.end else { return false }
            sum += pause.end.timeIntervalSince(pause.start)
            cursor = pause.end
        }
        return !timing.breakTimelineComplete || abs(sum - timing.totalBreakSeconds) <= 1
    }

    private static func append(
        _ kind: SegmentKind, from start: Date, to end: Date,
        within bounds: DateInterval, into segments: inout [Segment]
    ) {
        let clippedStart = max(start, bounds.start)
        let clippedEnd = min(end, bounds.end)
        if clippedEnd > clippedStart {
            segments.append(Segment(kind: kind, start: clippedStart, end: clippedEnd))
        }
    }
}
