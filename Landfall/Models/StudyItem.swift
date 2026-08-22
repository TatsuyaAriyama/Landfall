import Foundation
import SwiftData

/// 学習項目(教材・本・活動)。今日画面のタイルとして並ぶ。
@Model
final class StudyItem {
    /// タイマー紐付けなどで使う安定ID。
    var uuid: UUID
    var name: String
    /// タイルの配色プリセット(TileStyle.rawValue)。
    var styleToken: String
    /// タイルのシンボルプリセット(TileSymbol.rawValue)。
    var symbolToken: String
    /// 旧版で保存された表紙写真。互換性のため残すが、現在のUIでは使用しない。
    @Attribute(.externalStorage) var photoData: Data?
    /// 設定画面で指定する並び順。
    var sortOrder: Int
    var createdAt: Date
    /// 端末間の競合解決(Last-Write-Wins)に使う最終更新時刻。既定値で軽量マイグレーション可。
    var updatedAt: Date = Date.distantPast

    @Relationship(deleteRule: .cascade, inverse: \StudySession.item)
    var sessions: [StudySession] = []

    init(
        name: String,
        styleToken: String,
        symbolToken: String,
        photoData: Data? = nil,
        sortOrder: Int,
        createdAt: Date = Date()
    ) {
        self.uuid = UUID()
        self.name = String(
            name.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(WorkRecordPolicy.maximumItemNameCharacters)
        )
        self.styleToken = styleToken
        self.symbolToken = symbolToken
        self.photoData = photoData
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = Date()
    }
}

/// 1回の作業記録。時間(分)とひとことを持つ。
/// 記録された日は StudyDay として「学んだ日」に刻まれる(日ベースの土台はそのまま)。
@Model
final class StudySession {
    /// 端末をまたいだ同期(Firestore)で使う安定ID。
    /// 既定値を持たせ、uuidを持たない旧バージョンのストアからも軽量マイグレーションできるようにする。
    var uuid: UUID = UUID()
    /// 作業の開始日時。日への帰属はこの日付で決まる。
    var date: Date
    var minutes: Int
    /// 分に収まらない端数(0...59)。集計は従来どおり分で行い、実測の秒はここへ
    /// 残す。既定値付きなので、この列を持たない旧ストアからも軽量移行できる。
    var extraSeconds: Int = 0
    var note: String?
    var item: StudyItem?
    /// 同期で受け取ったのに、作業項目がまだ手元へ届いていないときの紐付け先。
    /// セッションの購読が項目の購読より先に返ると item が nil のまま固定されて
    /// しまうので、繋ぎ先を覚えておき、項目が届いた時点で結び直す。
    /// 既定値付きなので、この列を持たない旧ストアからも軽量移行できる。
    var pendingItemUUID: String? = nil
    /// 端末間の競合解決(Last-Write-Wins)に使う最終更新時刻。
    var updatedAt: Date = Date.distantPast

    init(
        date: Date,
        minutes: Int,
        extraSeconds: Int = 0,
        note: String? = nil,
        item: StudyItem? = nil
    ) {
        self.uuid = UUID()
        self.date = date
        self.minutes = min(WorkRecordPolicy.maximumSessionMinutes, max(0, minutes))
        self.extraSeconds = min(WorkRecordPolicy.maximumExtraSeconds, max(0, extraSeconds))
        self.note = WorkRecordPolicy.normalizedNote(note)
        self.item = item
        self.updatedAt = Date()
    }
}

extension StudySession {
    /// 記録された正味の長さ。手入力は秒まで、タイマー記録は分単位。
    var totalSeconds: Int {
        let safeMinutes = min(WorkRecordPolicy.maximumSessionMinutes, max(0, minutes))
        let safeSeconds = min(WorkRecordPolicy.maximumExtraSeconds, max(0, extraSeconds))
        return safeMinutes * 60 + safeSeconds
    }

    /// 記録一覧で共通して使う順序。項目の種類に関係なく、全件を開始時刻の新しい順にする。
    /// 同時刻でも同期の到着順で表示が揺れないよう、更新時刻とUUIDまで比較する。
    static func newestFirst(_ lhs: StudySession, _ rhs: StudySession) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.uuid.uuidString > rhs.uuid.uuidString
    }
}

/// 「学んだ日」の刻印。セッション保存時に呼び、その日の StudyDay を確実に1件にする。
enum StudyDayStore {
    struct MarkResult {
        let day: StudyDay
        let wasInserted: Bool
    }

    /// 航海誌は、記憶が新しいうちに残す。当日と前日だけを書き換え可能にする。
    /// UIだけでなく保存層で制限し、共有カードや軌跡から過去分を変更できないようにする。
    static func canEditComment(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let selected = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        guard selected <= today else { return false }
        let age = calendar.dateComponents([.day], from: selected, to: today).day ?? Int.max
        return age == 0 || age == 1
    }

    @discardableResult
    static func markDay(
        _ date: Date,
        context: ModelContext,
        syncsToAccount: Bool = true
    ) -> MarkResult {
        let dayStart = Calendar.current.startOfDay(for: date)
        var descriptor = FetchDescriptor<StudyDay>(
            predicate: #Predicate { $0.date == dayStart }
        )
        descriptor.fetchLimit = 1
        let existing = (try? context.fetch(descriptor)) ?? []
        if let day = existing.first {
            return MarkResult(day: day, wasInserted: false)
        }
        let day = StudyDay(date: dayStart)
        context.insert(day)
        if syncsToAccount {
            Task { @MainActor in SyncService.shared.push(day) }
        }
        return MarkResult(day: day, wasInserted: true)
    }

    /// その日のカードに添えるひとこと(記録ごとのメモとは別物)。
    static func comment(for date: Date, context: ModelContext) -> String? {
        day(for: date, context: context)?.note
    }

    /// その日の航海の感想を書き換える。当日と前日だけ保存できる。
    /// StudyDay の存在そのものが「学んだ日」を意味するので、記録の無い日には作らない
    /// (感想のために休んだ日を学んだ日に変えてしまわないため)。
    @discardableResult
    static func setComment(
        _ text: String?,
        for date: Date,
        context: ModelContext,
        now: Date = Date(),
        syncsToAccount: Bool = true
    ) -> Bool {
        guard canEditComment(for: date, now: now) else { return false }
        guard let day = day(for: date, context: context) else { return false }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true)
            ? nil
            : String(trimmed!.prefix(WorkRecordPolicy.maximumDayNoteCharacters))
        guard day.note != value else { return false }
        let previousNote = day.note
        let previousUpdatedAt = day.updatedAt
        day.note = value
        day.updatedAt = Date()
        do {
            try context.save()
        } catch {
            day.note = previousNote
            day.updatedAt = previousUpdatedAt
            return false
        }
        if syncsToAccount {
            Task { @MainActor in SyncService.shared.push(day) }
        }
        return true
    }

    private static func day(for date: Date, context: ModelContext) -> StudyDay? {
        let dayStart = Calendar.current.startOfDay(for: date)
        var descriptor = FetchDescriptor<StudyDay>(
            predicate: #Predicate { $0.date == dayStart }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// 今日すでに「学んだ日」の刻印があるか。通知のスケジュールで使う。
    static func recordedToday(context: ModelContext) -> Bool {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        var descriptor = FetchDescriptor<StudySession>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd }
        )
        descriptor.fetchLimit = 1
        return !((try? context.fetch(descriptor)) ?? []).isEmpty
    }

    /// その日のセッションが全て消えたら「学んだ日」の刻印も外す。
    /// セッション削除後に呼び、軌跡・統計の整合を保つ。
    static func unmarkDayIfEmpty(_ date: Date, context: ModelContext) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }

        var sessionDescriptor = FetchDescriptor<StudySession>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd }
        )
        sessionDescriptor.fetchLimit = 1
        let remaining = (try? context.fetch(sessionDescriptor)) ?? []
        guard remaining.isEmpty else { return }

        let dayDescriptor = FetchDescriptor<StudyDay>(
            predicate: #Predicate { $0.date == dayStart }
        )
        let matchingDays = (try? context.fetch(dayDescriptor)) ?? []
        // 航海記録を消しても、航海誌に残した言葉までは消さない。
        guard matchingDays.allSatisfy({
            $0.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        }) else { return }
        for day in matchingDays {
            context.delete(day)
        }
        Task { @MainActor in SyncService.shared.deleteDay(dayStart) }
    }
}
