import SwiftUI

/// A compact chronological list without empty hours or an inner scrolling surface.
struct WorkRecordTimelineView: View {
    let sessions: [StudySession]
    let day: Date
    var maxEntries: Int? = nil
    var onSelect: ((StudySession) -> Void)? = nil
    var onDelete: ((StudySession) -> Void)? = nil

    static func projection(sessions: [StudySession], day: Date) -> WorkRecordTimeline.Day {
        WorkRecordTimeline.project(sessions.map { session in
            WorkRecordTimeline.Record(
                id: session.uuid, date: session.date, seconds: session.totalSeconds,
                timing: session.timing.map { timing in
                    WorkRecordTimeline.Timing(
                        start: timing.startedAt, end: timing.endedAt,
                        breaks: timing.breaks.map {
                            WorkRecordTimeline.Interval(start: $0.startedAt, end: $0.endedAt)
                        },
                        totalBreakSeconds: timing.totalBreakSeconds,
                        breakTimelineComplete: timing.breakTimelineComplete
                    )
                }
            )
        }, on: day)
    }

    var body: some View {
        let projection = Self.projection(sessions: sessions, day: day)
        let limit = max(0, maxEntries ?? Int.max)
        let timed = Array(projection.timed.prefix(limit))
        let untimed = Array(projection.untimed.prefix(max(0, limit - timed.count)))
        let hiddenCount = projection.timed.count + projection.untimed.count - timed.count - untimed.count

        VStack(alignment: .leading, spacing: 10) {
            if projection.isEmpty {
                Text("No work recorded on this day.")
                    .font(LFFont.label(12))
                    .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
            }
            ForEach(timed) { entry in
                if let session = sessions.first(where: { $0.uuid == entry.id }) {
                    timedCard(entry, session: session)
                }
            }
            if !untimed.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Time not recorded")
                        .font(LFFont.copy(13))
                    Text("These records keep their saved date and duration.")
                        .font(LFFont.label(11))
                        .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, timed.isEmpty ? 0 : 4)
                ForEach(untimed, id: \.id) { entry in
                    if let session = sessions.first(where: { $0.uuid == entry.id }) {
                        recordHeader(session, seconds: session.totalSeconds)
                            .padding(12)
                            .lfHomeFeatureCard(cornerRadius: 16)
                    }
                }
            }
            if hiddenCount > 0 {
                Text(verbatim: LF.format("%lld more", Int64(hiddenCount)))
                    .font(LFFont.label(11))
                    .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
            }
        }
        .foregroundStyle(LFHomeFeatureStyle.ink)
        .accessibilityElement(children: .contain)
    }

    private func timedCard(_ entry: WorkRecordTimeline.Entry, session: StudySession) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "clock")
                    .accessibilityHidden(true)
                Text(verbatim: timeRange(entry.start, entry.end))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(LFFont.label(12))
            .foregroundStyle(LFHomeFeatureStyle.secondaryInk)

            recordHeader(session, seconds: entry.workSeconds ?? entry.recordedSeconds)

            Text(entry.workSeconds == nil ? "Recorded work for this session" : "Measured work on this day")
                .font(LFFont.label(10))
                .foregroundStyle(LFHomeFeatureStyle.secondaryInk)

            if entry.continuesFromPreviousDay || entry.continuesToNextDay {
                VStack(alignment: .leading, spacing: 3) {
                    if entry.continuesFromPreviousDay { Text("Continued from the previous day") }
                    if entry.continuesToNextDay { Text("Continues into the next day") }
                }
                .font(LFFont.label(10))
                .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
            }

            if let _ = entry.workSeconds, entry.segments.contains(where: { $0.kind == .rest }) {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(entry.segments) { segment in
                            segmentRow(segment)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Label("Work and breaks", systemImage: "list.bullet.indent")
                        .font(LFFont.label(11))
                }
                .tint(LFHomeFeatureStyle.ink)
            } else if entry.workSeconds == nil {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: LF.format("Breaks in this session: %@", duration(entry.totalUnpositionedBreakSeconds)))
                    Text("Break times were not saved; their positions are not shown.")
                }
                .font(LFFont.label(10))
                .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .lfHomeFeatureCard(cornerRadius: 16)
    }

    private func recordHeader(_ session: StudySession, seconds: Int) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if let onSelect {
                Button { onSelect(session) } label: {
                    headerContents(session, seconds: seconds)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Edit record"))
            } else {
                headerContents(session, seconds: seconds)
            }
            if let onDelete {
                Button { onDelete(session) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(LFColor.deepRust)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Delete record"))
            }
        }
    }

    private func headerContents(_ session: StudySession, seconds: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    itemName(session)
                    Spacer(minLength: 0)
                    durationLabel(seconds)
                }
                VStack(alignment: .leading, spacing: 3) {
                    itemName(session)
                    durationLabel(seconds)
                }
            }
            if let note = session.note, !note.isEmpty {
                Text(verbatim: note)
                    .font(LFFont.label(12))
                    .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
                    .lineLimit(maxEntries == nil ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func itemName(_ session: StudySession) -> some View {
        Text(verbatim: session.item?.name ?? LF.text("No item"))
            .font(LFFont.copy(14))
            .foregroundStyle(LFHomeFeatureStyle.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func durationLabel(_ seconds: Int) -> some View {
        Text(verbatim: duration(seconds))
            .font(LFFont.label(12))
            .foregroundStyle(LFHomeFeatureStyle.ink)
            .monospacedDigit()
            .fixedSize()
    }

    private func segmentRow(_ segment: WorkRecordTimeline.Segment) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(segment.kind == .rest ? LFColor.returnOrange.opacity(0.6) : LFHomeFeatureStyle.ink.opacity(0.5))
                .frame(width: 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: timeRange(segment.start, segment.end))
                    .font(LFFont.label(10))
                    .monospacedDigit()
                Text(verbatim: "\(LF.text(segment.kind == .rest ? "Break" : "Work")) · \(duration(segment.seconds))")
                    .font(LFFont.label(11))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func timeRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.current.locale
        formatter.timeZone = .current
        let changesOffset = TimeZone.current.secondsFromGMT(for: start) != TimeZone.current.secondsFromGMT(for: end)
        formatter.setLocalizedDateFormatFromTemplate(changesOffset ? "Hm z" : "Hm")
        let endOfDay = Calendar.current.dateInterval(of: .day, for: day)?.end
        let endText = end == endOfDay ? "24:00" : formatter.string(from: end)
        return "\(formatter.string(from: start))–\(endText)"
    }

    private func duration(_ seconds: Int) -> String {
        if seconds < 60 { return LF.format("%lld sec", Int64(max(0, seconds))) }
        return LF.duration(minutes: seconds / 60)
    }
}
