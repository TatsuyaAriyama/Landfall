import SwiftUI
import SwiftData

/// 「軌跡」画面。当月の学習をスカイライン波形で一望し、記録した日を一覧から辿れる。
/// 連続日数・ストリークの表示は絶対にしない。
struct TraceView: View {
    @Query private var entries: [StudyDay]
    @Query private var sessions: [StudySession]
    @Environment(\.scenePhase) private var scenePhase

    var calendar: Calendar = .current
    /// 「今日」。日跨ぎ・月跨ぎに追従できるよう State に持ち、前景復帰と日付変化で更新する。
    @State private var today = Date()
    /// 表示中の月のオフセット(0=当月、-1=先月...)。過去の軌跡を辿れる。
    @State private var monthOffset = 0
    @State private var path = NavigationPath()

    private var displayedDate: Date {
        calendar.date(byAdding: .month, value: monthOffset, to: today) ?? today
    }

    private var yearMonth: (year: Int, month: Int) {
        let comps = calendar.dateComponents([.year, .month], from: displayedDate)
        return (comps.year ?? 2026, comps.month ?? 1)
    }

    /// 記録がある最古の月。これより前へは戻さない。
    private var earliestRecordedYearMonth: YearMonth? {
        guard let minDate = entries.map(\.date).min() else { return nil }
        let c = calendar.dateComponents([.year, .month], from: minDate)
        guard let y = c.year, let m = c.month else { return nil }
        return YearMonth(year: y, month: m)
    }

    private var canGoBack: Bool {
        guard let earliest = earliestRecordedYearMonth else { return false }
        return yearMonth.year * 12 + yearMonth.month > earliest.year * 12 + earliest.month
    }

    /// 当月より先(未来)へは進めない。
    private var canGoForward: Bool { monthOffset < 0 }

    private var month: WrappedMonth {
        MonthStats.wrappedMonth(year: yearMonth.year, month: yearMonth.month, entries: entries, calendar: calendar)
    }

    var body: some View {
        NavigationStack(path: $path) {
            let month = self.month

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    monthHeader(for: month)
                        .padding(.top, 8)

                    waveform(for: month)
                        .padding(.top, 24)

                    statsRow(for: month)
                        .padding(.top, 28)

                    recordedDaysSection
                        .padding(.top, 40)
                }
                .padding(LFMetrics.cardPadding)
            }
            .background(LFColor.paper)
            .navigationDestination(for: DayKey.self) { key in
                DayDetailView(day: key.date)
            }
        }
        .onAppear {
            #if DEBUG
            if let raw = ProcessInfo.processInfo.environment["LANDFALL_MONTH_OFFSET"], let o = Int(raw) {
                monthOffset = o
            }
            if ProcessInfo.processInfo.environment["LANDFALL_DAY"] != nil,
               let first = recordedDays().first {
                path.append(DayKey(date: first.day))
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { today = Date() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            today = Date()
        }
    }

    // MARK: - 月ヘッダー(前後の月へ)

    private func monthHeader(for month: WrappedMonth) -> some View {
        HStack(spacing: 10) {
            navButton(system: "chevron.left", enabled: canGoBack) {
                if canGoBack { monthOffset -= 1 }
            }
            CardKicker(
                text: "Trace of \(LF.monthName(year: month.year, month: month.month))",
                color: LFColor.ink.opacity(0.55)
            )
            navButton(system: "chevron.right", enabled: canGoForward) {
                if canGoForward { monthOffset += 1 }
            }
            Spacer(minLength: 0)
        }
    }

    private func navButton(system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(LFColor.ink.opacity(enabled ? 0.7 : 0.18))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - 波形

    private func waveform(for month: WrappedMonth) -> some View {
        ZStack {
            MonthWaveform(
                month: month,
                lineColor: LFColor.ink,
                gapBarColor: LFColor.coral,
                resumeMarkerColor: LFColor.returnOrange,
                gapLabelColor: LFColor.deepRust.opacity(0.85),
                showDateAxis: true
            )
            .frame(height: 240)

            if month.studiedCount == 0 {
                Text("Waiting for this month's first mark.")
                    .font(LFFont.copy(16))
                    .foregroundStyle(LFColor.ink.opacity(0.6))
        }
        }
    }

    // MARK: - 統計(3つ同格)

    private func statsRow(for month: WrappedMonth) -> some View {
        HStack(alignment: .top, spacing: 0) {
            statBlock(label: "Total", value: month.studiedCount, unit: "days", alignment: .leading)
            statBlock(label: "Returns", value: month.resumeCount, unit: "times", alignment: .center)
            statBlock(label: "Times quit", value: month.quitCount, unit: "times", alignment: .trailing)
        }
    }

    private func statBlock(label: LocalizedStringKey, value: Int, unit: LocalizedStringKey, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(label)
                .font(LFFont.label(13))
                .foregroundStyle(LFColor.ink.opacity(0.5))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(verbatim: "\(value)")
                    .font(LFFont.number(30))
                    .foregroundStyle(LFColor.ink)
                Text(unit)
                    .font(LFFont.copy(14))
                    .foregroundStyle(LFColor.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment(alignment))
    }

    // MARK: - 記録した日の一覧

    @ViewBuilder
    private var recordedDaysSection: some View {
        let days = recordedDays()
        if !days.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Days logged")
                    .font(LFFont.label(13))
                    .tracking(1)
                    .foregroundStyle(LFColor.ink.opacity(0.5))

                VStack(spacing: 0) {
                    ForEach(days, id: \.day) { entry in
                        if entry.day != days.first?.day {
                            Rectangle()
                                .fill(LFColor.ink.opacity(0.08))
                                .frame(height: 1)
                        }
                        dayRow(entry)
                    }
                }
            }
        }
    }

    private func dayRow(_ entry: DaySummary) -> some View {
        Button {
            path.append(DayKey(date: entry.day))
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LF.dayMonth(entry.day))
                        .font(LFFont.copy(16))
                        .foregroundStyle(LFColor.ink)
                    Text(LF.weekdayFull(entry.day))
                        .font(LFFont.label(11))
                        .foregroundStyle(LFColor.ink.opacity(0.4))
                }
                .frame(width: 66, alignment: .leading)

                HStack(spacing: -6) {
                    ForEach(entry.items.prefix(4), id: \.persistentModelID) { item in
                        ItemTileArt(item: item)
                            .frame(width: 30, height: 30)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(LFColor.paper, lineWidth: 2)
                            )
                    }
                }

                Spacer(minLength: 0)

                Text(LF.duration(minutes: entry.minutes))
                    .font(LFFont.label(15))
                    .monospacedDigit()
                    .foregroundStyle(LFColor.ink.opacity(0.6))
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(LFColor.ink.opacity(0.25))
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 導出

    private struct DaySummary {
        let day: Date
        let items: [StudyItem]
        let minutes: Int
    }

    /// 当月に記録した日を新しい順にまとめる。
    private func recordedDays() -> [DaySummary] {
        let monthSessions = sessions.filter {
            let c = calendar.dateComponents([.year, .month], from: $0.date)
            return c.year == yearMonth.year && c.month == yearMonth.month
        }
        let grouped = Dictionary(grouping: monthSessions) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            let daySessions = grouped[day] ?? []
            var seen = Set<PersistentIdentifier>()
            var items: [StudyItem] = []
            for session in daySessions.sorted(by: { $0.date < $1.date }) {
                if let item = session.item, !seen.contains(item.persistentModelID) {
                    seen.insert(item.persistentModelID)
                    items.append(item)
                }
            }
            return DaySummary(day: day, items: items, minutes: daySessions.reduce(0) { $0 + $1.minutes })
        }
    }

    private func frameAlignment(_ alignment: HorizontalAlignment) -> Alignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }
}

/// ナビゲーション用の日付キー(Date直渡しの曖昧さを避ける)。
struct DayKey: Hashable {
    let date: Date
}

// MARK: - Previews

#Preview("記録あり") {
    let container = try! ModelContainer(
        for: StudyDay.self, StudyItem.self, StudySession.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let calendar = Calendar.current
    let item = StudyItem(name: "開発", styleToken: "midnight", symbolToken: "phoenix", sortOrder: 0)
    container.mainContext.insert(item)
    let comps = calendar.dateComponents([.year, .month], from: .now)
    for day in [1, 2, 3, 6, 7, 11, 12, 13] {
        var dayComps = comps
        dayComps.day = day
        if let date = calendar.date(from: dayComps) {
            container.mainContext.insert(StudySession(date: date, minutes: 30, item: item))
            StudyDayStore.markDay(date, context: container.mainContext)
        }
    }
    return TraceView().modelContainer(container)
}

#Preview("記録0日") {
    TraceView()
        .modelContainer(
            try! ModelContainer(
                for: StudyDay.self, StudyItem.self, StudySession.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        )
}
