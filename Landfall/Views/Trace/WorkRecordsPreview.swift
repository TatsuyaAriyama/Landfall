#if DEBUG
import SwiftData
import SwiftUI

/// Development-only fixture. It never opens the user's store or invokes account synchronization.
struct WorkRecordsPreview: View {
    @StateObject private var store = Store()
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    var body: some View {
        TraceView(onClose: onClose, readOnly: true)
            .modelContainer(store.container)
    }

    @MainActor
    private final class Store: ObservableObject {
        let container: ModelContainer

        init(now: Date = Date(), calendar: Calendar = .current) {
            do {
                container = try ModelContainer(
                    for: StudyDay.self, StudyItem.self, StudySession.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                )
            } catch {
                preconditionFailure("Cannot create isolated records preview: \(error)")
            }
            let context = container.mainContext
            let writing = StudyItem(name: "開発", styleToken: "harbor", symbolToken: "compass", sortOrder: 0)
            let reading = StudyItem(name: "読書", styleToken: "sand", symbolToken: "book", sortOrder: 1)
            context.insert(writing)
            context.insert(reading)

            let today = calendar.startOfDay(for: now)
            func at(_ offset: Int, _ hour: Int, _ minute: Int) -> Date {
                let day = calendar.date(byAdding: .day, value: offset, to: today)!
                return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
            }
            var days: Set<Date> = []
            func add(
                start: Date, end: Date, breaks: [WorkSessionTiming.BreakInterval] = [],
                item: StudyItem, note: String, timed: Bool = true
            ) {
                let rest = breaks.reduce(0) { $0 + $1.duration }
                let seconds = max(0, Int(end.timeIntervalSince(start) - rest))
                let session = StudySession(
                    date: start, minutes: seconds / 60, extraSeconds: seconds % 60,
                    note: note, item: item
                )
                if timed {
                    session.timingJSON = WorkSessionTiming(
                        startedAt: start, endedAt: end, breaks: breaks,
                        totalBreakSeconds: rest, breakTimelineComplete: true, source: .timer
                    ).json
                }
                context.insert(session)
                days.insert(calendar.startOfDay(for: start))
            }

            add(
                start: at(0, 9, 0), end: at(0, 10, 15),
                breaks: [.init(startedAt: at(0, 9, 35), endedAt: at(0, 9, 45))],
                item: writing, note: "記録画面の構成を整理し、休憩を挟んで見直した。"
            )
            add(start: at(0, 11, 0), end: at(0, 11, 30), item: reading, note: "第3章まで読んだ。次は実例を試す。")
            add(start: at(0, 12, 0), end: at(0, 12, 20), item: writing, note: "以前に残した、時刻情報のない記録。", timed: false)
            add(
                start: at(-1, 23, 40), end: at(0, 0, 25),
                breaks: [.init(startedAt: at(-1, 23, 55), endedAt: at(0, 0, 5))],
                item: reading, note: "日付をまたいだ読書。前日と今日に分かれて表示される。"
            )
            add(start: at(-2, 10, 0), end: at(-2, 10, 50), item: writing, note: "実装の下準備。")
            add(start: at(-7, 9, 0), end: at(-7, 9, 45), item: writing, note: "先週の同じ曜日の作業。")
            add(start: at(-7, 11, 0), end: at(-7, 11, 20), item: reading, note: "先週の読書。")
            add(start: at(-9, 10, 0), end: at(-9, 10, 30), item: writing, note: "先週の準備。")
            for day in days {
                context.insert(StudyDay(date: day))
            }
            try? context.save()
        }
    }
}
#endif
