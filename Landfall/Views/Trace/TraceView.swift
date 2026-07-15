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
    @State private var path = NavigationPath()

    private var yearMonth: (year: Int, month: Int) {
        let comps = calendar.dateComponents([.year, .month], from: today)
        return (comps.year ?? 2026, comps.month ?? 1)
    }

    private var month: WrappedMonth {
        MonthStats.wrappedMonth(year: yearMonth.year, month: yearMonth.month, entries: entries, calendar: calendar)
    }

    var body: some View {
        NavigationStack(path: $path) {
            let month = self.month

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CardKicker(text: "\(month.month)月の軌跡", color: LFColor.ink.opacity(0.55))
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
                Text("今月の最初のひと刻みを待っている。")
                    .font(LFFont.copy(16))
                    .foregroundStyle(LFColor.ink.opacity(0.6))
        }
        }
    }

    // MARK: - 統計(3つ同格)

    private func statsRow(for month: WrappedMonth) -> some View {
        HStack(alignment: .top, spacing: 0) {
            statBlock(label: "累積", value: month.studiedCount, unit: "日", alignment: .leading)
            statBlock(label: "再開", value: month.resumeCount, unit: "回", alignment: .center)
            statBlock(label: "やめた回数", value: month.quitCount, unit: "回", alignment: .trailing)
        }
    }

    private func statBlock(label: String, value: Int, unit: String, alignment: HorizontalAlignment) -> some View {
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
                Text("記録した日")
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
                    Text(Self.dayFormatter.string(from: entry.day))
                        .font(LFFont.copy(16))
                        .foregroundStyle(LFColor.ink)
                    Text(Self.weekdayFormatter.string(from: entry.day))
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

                Text(durationText(entry.minutes))
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

    private func durationText(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 { return m > 0 ? "\(h)時間\(m)分" : "\(h)時間" }
        return "\(m)分"
    }

    private func frameAlignment(_ alignment: HorizontalAlignment) -> Alignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "EEEE"
        return f
    }()
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
