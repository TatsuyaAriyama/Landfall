import Foundation
import SwiftData

// Link this probe with the real StudyItem, StudyDay, PlayerLevel and
// WidgetTimerShared sources. Only external publication services are replaced.
@MainActor final class SyncService {
    static let shared = SyncService()
    var deletedSessions: [UUID] = []
    var deletedDays: [Date] = []
    func deleteSession(id: UUID) { deletedSessions.append(id) }
    func deleteDay(_ date: Date) { deletedDays.append(date) }
    func push(_ day: StudyDay) {}
}
@MainActor final class PublicHarborService {
    static let shared = PublicHarborService()
    var publications = 0
    func publishCurrentMonth(context: ModelContext) { publications += 1 }
}
@MainActor enum WidgetBridge {
    static var refreshes = 0
    static func refresh(context: ModelContext) { refreshes += 1 }
}
enum NotificationService {
    static func reschedule(recordedToday: Bool) async {}
}

@main @MainActor
enum SessionDeletionReliabilityProbe {
    enum Failure: Error { case injected }
    static var checks = 0
    static func check(_ condition: Bool, _ message: String) {
        precondition(condition, message)
        checks += 1
    }
    static func main() throws {
        let container = try ModelContainer(
            for: StudyItem.self, StudySession.self, StudyDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let date = Calendar.current.startOfDay(for: Date())
        let item = StudyItem(name: "Original", styleToken: "ocean", symbolToken: "book", sortOrder: 0)
        let record = StudySession(date: date, minutes: 30, item: item)
        let second = StudySession(date: date, minutes: 15, item: item)
        let day = StudyDay(date: date)
        context.insert(item)
        context.insert(record)
        context.insert(second)
        context.insert(day)
        try context.save()
        let recordID = record.uuid
        item.name = "Unrelated pending edit"
        check(item.sessions.count == 2, "warm the shared-context relationship before deletion")

        do {
            try StudySessionStore.delete(record, context: context, commit: { _ in throw Failure.injected })
            preconditionFailure("An injected persistence failure must propagate")
        } catch Failure.injected {}
        check(try context.fetchCount(FetchDescriptor<StudySession>()) == 2, "failed delete retains both records")
        check(try context.fetchCount(FetchDescriptor<StudyDay>()) == 1, "failed delete retains day")
        check(item.name == "Unrelated pending edit" && context.hasChanges, "failure preserves unrelated pending edits")
        check(SyncService.shared.deletedSessions.isEmpty && SyncService.shared.deletedDays.isEmpty, "failure sends no remote deletions")
        check(PublicHarborService.shared.publications == 0 && WidgetBridge.refreshes == 0, "failure publishes no derived changes")

        try StudySessionStore.delete(record, context: context)
        check(try context.fetchCount(FetchDescriptor<StudySession>()) == 1, "shared context sees isolated delete")
        check(item.sessions.count == 1, "cached item relationship sees isolated delete")
        check(try context.fetchCount(FetchDescriptor<StudyDay>()) == 1, "remaining session preserves day")
        check(item.name == "Unrelated pending edit" && context.hasChanges, "success preserves unrelated pending edits")
        check(SyncService.shared.deletedSessions == [recordID], "successful delete publishes captured UUID")
        check(PublicHarborService.shared.publications == 1 && WidgetBridge.refreshes == 1, "success refreshes derived history once")

        // A pending reflection is not visible to the isolated context, but must
        // still survive deleting the day's final record.
        day.note = "Keep this journal entry"
        try StudySessionStore.delete(second, context: context)
        check(try context.fetchCount(FetchDescriptor<StudySession>()) == 0, "final session removed")
        check(try context.fetch(FetchDescriptor<StudyDay>()).first?.note == "Keep this journal entry", "journal survives final session deletion")
        check(SyncService.shared.deletedDays.isEmpty, "preserved journal is not deleted remotely")
        try context.save()
        let replacement = StudySession(date: date, minutes: 10, item: item)
        context.insert(replacement)
        try context.save()
        try StudySessionStore.delete(replacement, context: context)
        check(try context.fetch(FetchDescriptor<StudyDay>()).first?.note == "Keep this journal entry", "persisted journal also survives final deletion")

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        let last = StudySession(date: tomorrow, minutes: 5, item: item)
        context.insert(last)
        context.insert(StudyDay(date: tomorrow))
        try context.save()
        do {
            try StudySessionStore.delete(last, context: context, commit: { _ in throw Failure.injected })
            preconditionFailure("An injected final-record deletion failure must propagate")
        } catch Failure.injected {}
        check(try context.fetchCount(FetchDescriptor<StudySession>()) == 1, "failed final deletion retains session")
        check(try context.fetchCount(FetchDescriptor<StudyDay>()) == 2, "failed final deletion retains empty day")
        try StudySessionStore.delete(last, context: context)
        check(try context.fetchCount(FetchDescriptor<StudyDay>()) == 1, "empty day removed with final record")
        check(SyncService.shared.deletedDays == [tomorrow], "empty day remotely removed only after successful commit")
        print("Session deletion reliability: \(checks) checks passed")
    }
}
