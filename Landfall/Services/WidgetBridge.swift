import Foundation
import SwiftData
import WidgetKit

/// 本体アプリからウィジェットへ、今月の「学んだ/休んだ」日数を App Group 経由で受け渡す。
/// 前景復帰や記録保存のたびに呼び、ウィジェットを更新する。
enum WidgetBridge {
    static let appGroup = "group.com.tatsuyaariyama.Landfall"

    @MainActor
    static func refresh(context: ModelContext) {
        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.year, .month], from: now)
        guard let year = comps.year, let month = comps.month else { return }

        let entries = (try? context.fetch(FetchDescriptor<StudyDay>())) ?? []
        let studied = MonthStats.studiedDaySet(year: year, month: month, entries: entries, calendar: calendar)
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30

        let store = UserDefaults(suiteName: appGroup)
        store?.set(month, forKey: "w_month")
        store?.set(studied.count, forKey: "w_studied")
        store?.set(daysInMonth - studied.count, forKey: "w_rested")
        WidgetCenter.shared.reloadAllTimelines()
    }
}
