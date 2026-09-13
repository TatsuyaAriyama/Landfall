import SwiftUI

/// Shared by the island record panel and the calendar. The host controls refresh
/// time so both the date selection and the summary advance together.
struct WorkRecordWeeklySummaryView: View {
    let sessions: [StudySession]
    var now: Date = Date()
    var calendar: Calendar = .current
    var selectedDay: Date? = nil
    var onSelectDay: ((Date) -> Void)? = nil

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
            weeklyChart(value)
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
                DisclosureGroup {
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
                } label: {
                    Text("Main activities this week")
                        .font(LFFont.label(12))
                }
                .tint(LFHomeFeatureStyle.ink)
            }
        }
        .foregroundStyle(LFHomeFeatureStyle.ink)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lfHomeFeatureCard(cornerRadius: 20)
        .accessibilityIdentifier("workRecordWeeklySummary")
    }

    /// The original island week chart, using the same seconds and cutoff as
    /// the metrics above so short sessions and week boundaries stay consistent.
    private func weeklyChart(_ value: WorkRecordWeeklySummary.Summary) -> some View {
        let maximum = max(1, value.days.map(\.seconds).max() ?? 0)
        return VStack(alignment: .trailing, spacing: 7) {
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(value.days) { day in
                    let isToday = calendar.isDate(day.date, inSameDayAs: now)
                    let isSelected = calendar.isDate(day.date, inSameDayAs: selectedDay ?? now)
                    let isFuture = day.date > calendar.startOfDay(for: now)
                    Button {
                        onSelectDay?(day.date)
                    } label: {
                        VStack(spacing: 6) {
                            Text(verbatim: day.seconds > 0 ? shortDuration(day.seconds) : "")
                                .font(LFFont.label(8))
                                .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(height: 11)
                            GeometryReader { proxy in
                                VStack {
                                    Spacer(minLength: 0)
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(isToday ? Color(uiColor: VoyageSceneKit.returnOrange)
                                              : LFHomeFeatureStyle.ink.opacity(day.seconds > 0 ? 0.72 : 0.10))
                                        .frame(height: max(5, proxy.size.height * CGFloat(day.seconds) / CGFloat(maximum)))
                                }
                            }
                            .frame(height: 78)
                            Text(verbatim: day.date.formatted(.dateTime.weekday(.abbreviated)))
                                .font(LFFont.label(9))
                                .foregroundStyle(LFHomeFeatureStyle.ink.opacity(isSelected || isToday ? 1 : 0.48))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(LFHomeFeatureStyle.ink.opacity(isSelected ? 0.11 : 0)))
                        }
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .disabled(isFuture || onSelectDay == nil)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "\(LF.dayWithWeekday(day.date)), \(Self.duration(day.seconds))"))
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityHint(Text("Shows this day's work below the card"))
                }
            }
            Text(verbatim: LF.format("%lld records", Int64(value.recordCount)))
                .font(LFFont.label(10))
                .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
        }
        .accessibilityIdentifier("workRecordWeekChart")
    }

    private func shortDuration(_ seconds: Int) -> String {
        if seconds >= 3600 { return String(format: "%.1fh", Double(seconds) / 3600) }
        if seconds >= 60 { return "\(seconds / 60)m" }
        return "\(seconds)s"
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
