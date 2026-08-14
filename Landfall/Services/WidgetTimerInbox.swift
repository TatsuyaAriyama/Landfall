import SwiftData
import WidgetKit

/// Widget Extensionで着岸した記録を、本体のSwiftDataへ一度だけ取り込む。
@MainActor
enum WidgetTimerInbox {
    static func importPending(context: ModelContext) {
        let pending = KeelMiraWidgetStore.pendingLandfalls
        guard !pending.isEmpty else { return }

        let items = (try? context.fetch(FetchDescriptor<StudyItem>())) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<StudySession>())) ?? []
        var knownIDs = Set(sessions.map(\.uuid))
        var imported: [StudySession] = []
        var remaining: [KeelMiraPendingLandfall] = []

        for record in pending {
            if knownIDs.contains(record.id) { continue }
            let itemByID = items.first(where: { $0.uuid.uuidString == record.itemID })
            let itemsByName = items.filter { $0.name == record.itemName }
            // 同期や復元でUUIDが変わった場合も、同名項目が一意なら記録を救済する。
            // 同名項目が複数あるときは誤結び付けを避け、受信箱に残す。
            let item = itemByID ?? (itemsByName.count == 1 ? itemsByName[0] : nil)
            guard let item else {
                // 同期前で項目がまだ無い場合は、次の前面復帰まで受信箱に残す。
                remaining.append(record)
                continue
            }
            let session = StudySession(
                date: record.finishedAt,
                minutes: record.minutes,
                note: nil,
                item: item
            )
            session.uuid = record.id
            context.insert(session)
            StudyDayStore.markDay(record.finishedAt, context: context)
            knownIDs.insert(record.id)
            imported.append(session)
        }

        guard !imported.isEmpty else {
            KeelMiraWidgetStore.pendingLandfalls = remaining
            return
        }

        do {
            try context.save()
        } catch {
            // 保存できなければ受信箱を残し、次回に再試行する。
            return
        }

        KeelMiraWidgetStore.pendingLandfalls = remaining
        for session in imported {
            SyncService.shared.push(session)
        }
        PublicHarborService.shared.publishCurrentMonth(context: context)
        WidgetBridge.refresh(context: context)
        let recorded = StudyDayStore.recordedToday(context: context)
        Task { await NotificationService.reschedule(recordedToday: recorded) }
    }
}
