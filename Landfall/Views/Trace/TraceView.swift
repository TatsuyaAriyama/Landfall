import SwiftUI
import SwiftData

/// 「軌跡」画面。当月の学習をスカイライン波形で一望する。
/// 連続日数・ストリークの表示は絶対にしない。
struct TraceView: View {
    @Query private var entries: [StudyDay]
    @Environment(\.scenePhase) private var scenePhase

    var calendar: Calendar = .current
    /// 「今日」。日跨ぎ・月跨ぎに追従できるよう State に持ち、前景復帰と日付変化で更新する。
    @State private var today = Date()

    private var month: WrappedMonth {
        let comps = calendar.dateComponents([.year, .month], from: today)
        return MonthStats.wrappedMonth(
            year: comps.year ?? 2026,
            month: comps.month ?? 1,
            entries: entries,
            calendar: calendar
        )
    }

    var body: some View {
        let month = self.month

        VStack(alignment: .leading, spacing: 0) {
            CardKicker(text: "\(month.month)月の軌跡", color: LFColor.ink.opacity(0.55))

            Spacer()

            waveform(for: month)

            Spacer()

            statsRow(for: month)
        }
        .padding(LFMetrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LFColor.paper)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { today = Date() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            today = Date()
        }
    }

    // MARK: 波形

    private func waveform(for month: WrappedMonth) -> some View {
        ZStack {
            MonthWaveform(
                month: month,
                lineColor: LFColor.ink,
                gapBarColor: LFColor.coral,
                resumeMarkerColor: LFColor.returnOrange,
                gapLabelColor: LFColor.deepRust.opacity(0.85)
            )
            .frame(height: 220)

            if month.studiedCount == 0 {
                Text("今月の最初のひと刻みを待っている。")
                    .font(LFFont.copy(16))
                    .foregroundStyle(LFColor.ink.opacity(0.6))
            }
        }
    }

    // MARK: 統計(3つ同格、左・中央・右に展開)

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

    private func frameAlignment(_ alignment: HorizontalAlignment) -> Alignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }
}

// MARK: - Previews

#Preview("記録あり") {
    let container = try! ModelContainer(
        for: StudyDay.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let calendar = Calendar.current
    let comps = calendar.dateComponents([.year, .month], from: .now)
    for day in [1, 2, 3, 6, 7, 11, 12, 13] {
        var dayComps = comps
        dayComps.day = day
        if let date = calendar.date(from: dayComps) {
            container.mainContext.insert(StudyDay(date: date))
        }
    }
    return TraceView()
        .modelContainer(container)
}

#Preview("記録0日") {
    TraceView()
        .modelContainer(for: StudyDay.self, inMemory: true)
}
