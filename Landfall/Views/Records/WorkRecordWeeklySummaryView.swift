import SwiftUI

/// Shared by the island record panel and the calendar. The host controls refresh
/// time so both the date selection and the summary advance together.
struct WorkRecordWeeklySummaryView: View {
    let sessions: [StudySession]
    var now: Date = Date()
    var calendar: Calendar = .current

    private var summary: WorkRecordWeeklySummary.Summary {
        WorkRecordWeeklySummary.summarize(sessions.map {
            .init(
                date: $0.date,
                seconds: $0.totalSeconds,
                itemID: $0.item?.uuid.uuidString ?? $0.pendingItemUUID,
                itemName: $0.item?.name
            )
        }, now: now, calendar: calendar)
    }

    var body: some View {
        let value = summary
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    title
                    Spacer(minLength: 12)
                    range(value)
                }
                VStack(alignment: .leading, spacing: 4) {
                    title
                    range(value)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    durationMetric(value)
                    Spacer(minLength: 0)
                    daysMetric(value)
                }
                VStack(alignment: .leading, spacing: 12) {
                    durationMetric(value)
                    daysMetric(value)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: comparison(value))
                    .font(LFFont.copy(12))
                Text("Compared with the same weekday and time last week")
                    .font(LFFont.label(10))
                    .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
            }
            .fixedSize(horizontal: false, vertical: true)

            if value.leadingItems.isEmpty {
                Text("No work recorded this week.")
                    .font(LFFont.label(12))
                    .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
            } else {
                Rectangle()
                    .fill(LFHomeFeatureStyle.outline)
                    .frame(height: 1)
                    .accessibilityHidden(true)
                Text("Main activities this week")
                    .font(LFFont.label(10))
                    .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
                ForEach(value.leadingItems) { item in
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(verbatim: item.name ?? LF.text("Unassigned activity"))
                                .lineLimit(2)
                            Spacer(minLength: 0)
                            Text(verbatim: Self.duration(item.seconds))
                                .fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: item.name ?? LF.text("Unassigned activity"))
                            Text(verbatim: Self.duration(item.seconds))
                                .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
                        }
                    }
                    .font(LFFont.copy(12))
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .foregroundStyle(LFHomeFeatureStyle.ink)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lfHomeFeatureCard(cornerRadius: 20)
        .accessibilityIdentifier("workRecordWeeklySummary")
    }

    private var title: some View {
        Text("This week's record")
            .font(LFFont.copy(14))
    }

    private func range(_ value: WorkRecordWeeklySummary.Summary) -> some View {
        Text(verbatim: "\(LF.dayMonth(value.weekStart)) – \(LF.dayMonth(value.through))")
            .font(LFFont.label(10))
            .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
    }

    private func durationMetric(_ value: WorkRecordWeeklySummary.Summary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Recorded work time")
                .font(LFFont.label(10))
                .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
            Text(verbatim: Self.duration(value.totalSeconds))
                .font(LFFont.copy(20))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func daysMetric(_ value: WorkRecordWeeklySummary.Summary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Active days")
                .font(LFFont.label(10))
                .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
            Text(verbatim: LF.format("%lld days", Int64(value.activeDayCount)))
                .font(LFFont.copy(20))
                .monospacedDigit()
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    private func comparison(_ value: WorkRecordWeeklySummary.Summary) -> String {
        guard value.previousSeconds > 0 else {
            return LF.text("No records in the same period last week")
        }
        guard value.differenceSeconds != 0 else { return LF.text("Same work time as last week") }
        return value.differenceSeconds > 0
            ? LF.format("%@ more than last week", Self.duration(value.differenceSeconds))
            : LF.format("%@ less than last week", Self.duration(-value.differenceSeconds))
    }

    /// Keep sub-minute work visible and expose all recorded seconds. Aggregating
    /// before formatting avoids losing a minute through per-session rounding.
    private static func duration(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        let remainder = safe % 60
        if safe < 60 { return LF.format("%lld sec", Int64(safe)) }
        let base = LF.duration(minutes: safe / 60)
        return remainder == 0 ? base : LF.format("%@ %lld sec", base, Int64(remainder))
    }
}
