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
    /// タイルのシンボルプリセット(TileSymbol.rawValue)。写真があれば写真が優先。
    var symbolToken: String
    /// 教材の表紙写真など(縮小済みJPEG)。
    @Attribute(.externalStorage) var photoData: Data?
    /// グリッド上の並び順(ドラッグで並べ替え)。
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
        self.name = name
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
    var note: String?
    var item: StudyItem?
    /// 端末間の競合解決(Last-Write-Wins)に使う最終更新時刻。
    var updatedAt: Date = Date.distantPast

    init(date: Date, minutes: Int, note: String? = nil, item: StudyItem? = nil) {
        self.uuid = UUID()
        self.date = date
        self.minutes = minutes
        self.note = note
        self.item = item
        self.updatedAt = Date()
    }
}

/// 「学んだ日」の刻印。セッション保存時に呼び、その日の StudyDay を確実に1件にする。
enum StudyDayStore {
    static func markDay(_ date: Date, context: ModelContext) {
        let dayStart = Calendar.current.startOfDay(for: date)
        var descriptor = FetchDescriptor<StudyDay>(
            predicate: #Predicate { $0.date == dayStart }
        )
        descriptor.fetchLimit = 1
        let existing = (try? context.fetch(descriptor)) ?? []
        if existing.isEmpty {
            let day = StudyDay(date: dayStart)
            context.insert(day)
            Task { @MainActor in SyncService.shared.push(day) }
        }
    }

    /// 今日すでに「学んだ日」の刻印があるか。通知のスケジュールで使う。
    static func recordedToday(context: ModelContext) -> Bool {
        let dayStart = Calendar.current.startOfDay(for: Date())
        var descriptor = FetchDescriptor<StudyDay>(
            predicate: #Predicate { $0.date == dayStart }
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
        for day in (try? context.fetch(dayDescriptor)) ?? [] {
            context.delete(day)
        }
        Task { @MainActor in SyncService.shared.deleteDay(dayStart) }
    }
}
