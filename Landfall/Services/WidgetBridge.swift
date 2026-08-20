import Foundation
import SwiftData
import WidgetKit

/// 本体からWidget Extensionへ、統計・作業項目・航海の静止画をまとめて渡す。
enum WidgetBridge {
    static let appGroup = KeelMiraWidgetStore.appGroup

    @MainActor
    static func refresh(context: ModelContext) {
        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.year, .month], from: now)
        guard let year = comps.year, let month = comps.month else { return }

        let entries = (try? context.fetch(FetchDescriptor<StudyDay>())) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<StudySession>())) ?? []
        let items = ((try? context.fetch(FetchDescriptor<StudyItem>())) ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
        let studied = MonthStats.studiedDaySet(year: year, month: month, entries: entries, calendar: calendar)
        let elapsedDays = calendar.component(.day, from: now)
        let todayMinutes = sessions
            .filter { calendar.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.minutes }

        AppLanguage.syncToWidgets()
        let store = KeelMiraWidgetStore.defaults
        store.set(month, forKey: "w_month")
        store.set(studied.count, forKey: "w_studied")
        // 月の未来日を「休んだ日」に数えない。
        store.set(max(0, elapsedDays - studied.count), forKey: "w_rested")
        store.set(todayMinutes, forKey: KeelMiraWidgetStore.Key.todayMinutes)
        KeelMiraWidgetStore.workItems = items.prefix(4).map {
            KeelMiraWidgetItem(
                id: $0.uuid.uuidString,
                name: $0.name,
                styleToken: $0.styleToken,
                symbolToken: $0.symbolToken
            )
        }
        WidgetVoyageStillRenderer.refreshIfNeeded()
        WidgetCenter.shared.reloadTimelines(ofKind: KeelMiraWidgetStore.widgetKind)
    }
}
