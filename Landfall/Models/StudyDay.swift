import Foundation
import SwiftData

/// 学習記録。1日1件、日付はその日の開始時刻(startOfDay)で正規化して保存する。
@Model
final class StudyDay {
    @Attribute(.unique) var date: Date
    var note: String?
    /// 端末間の競合解決(Last-Write-Wins)に使う最終更新時刻。
    var updatedAt: Date = Date.distantPast

    init(date: Date, note: String? = nil) {
        self.date = Calendar.current.startOfDay(for: date)
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = (trimmed?.isEmpty ?? true)
            ? nil
            : String(trimmed!.prefix(WorkRecordPolicy.maximumDayNoteCharacters))
        self.updatedAt = Date()
    }
}

/// Delete locally before publishing any account or derived-history changes.
@MainActor
enum StudySessionStore {
    enum DeletionError: Error {
        case recordUnavailable
        case invalidDate
    }

    struct Deletion {
        let sessionID: UUID
        let removedDay: Date?
    }

    /// The isolated context makes a failed delete reversible without rolling
    /// back other screens' pending changes in the shared UI context.
    static func persistDeletion(
        sessionID: UUID,
        context: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Deletion {
        let transaction = ModelContext(context.container)
        transaction.autosaveEnabled = false
        var descriptor = FetchDescriptor<StudySession>(
            predicate: #Predicate { $0.uuid == sessionID }
        )
        descriptor.fetchLimit = 1
        guard let session = try transaction.fetch(descriptor).first else {
            throw DeletionError.recordUnavailable
        }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: session.date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            throw DeletionError.invalidDate
        }
        var remainingDescriptor = FetchDescriptor<StudySession>(
            predicate: #Predicate {
                $0.date >= dayStart && $0.date < dayEnd && $0.uuid != sessionID
            }
        )
        remainingDescriptor.fetchLimit = 1
        let hasStoredSessions = try !transaction.fetch(remainingDescriptor).isEmpty
        let hasPendingSessions = try !context.fetch(remainingDescriptor).isEmpty
        var removedDay: Date?
        if !hasStoredSessions && !hasPendingSessions {
            let dayDescriptor = FetchDescriptor<StudyDay>(
                predicate: #Predicate { $0.date == dayStart }
            )
            let matchingDays = try transaction.fetch(dayDescriptor)
            let visibleDays = try context.fetch(dayDescriptor)
            // A journal entry remains even after its final work record is removed.
            // Include pending UI edits, which the isolated context cannot see.
            if !matchingDays.isEmpty, (matchingDays + visibleDays).allSatisfy({
                $0.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            }) {
                matchingDays.forEach { transaction.delete($0) }
                removedDay = dayStart
            }
        }
        transaction.delete(session)
        do {
            try commit(transaction)
        } catch {
            transaction.rollback()
            throw error
        }
        return Deletion(sessionID: sessionID, removedDay: removedDay)
    }

    static func delete(
        _ session: StudySession,
        context: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let dayStart = Calendar.current.startOfDay(for: session.date)
        let dayDescriptor = FetchDescriptor<StudyDay>(
            predicate: #Predicate { $0.date == dayStart }
        )
        let visibleDays = try context.fetch(dayDescriptor)
        let deletion = try persistDeletion(sessionID: session.uuid, context: context, commit: commit)
        // A save in another context updates fetch results but does not invalidate
        // cached item.sessions relationships. Mirror the durable deletion into
        // the UI context without saving or rolling back its unrelated edits.
        context.delete(session)
        if deletion.removedDay != nil { visibleDays.forEach { context.delete($0) } }
        context.processPendingChanges()
        SyncService.shared.deleteSession(id: deletion.sessionID)
        if let day = deletion.removedDay { SyncService.shared.deleteDay(day) }
        PublicHarborService.shared.publishCurrentMonth(context: context)
        WidgetBridge.refresh(context: context)
        let recordedToday = StudyDayStore.recordedToday(context: context)
        Task { await NotificationService.reschedule(recordedToday: recordedToday) }
    }
}
