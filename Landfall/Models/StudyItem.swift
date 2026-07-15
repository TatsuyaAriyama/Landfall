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
    }
}

/// 1回の作業記録。時間(分)とひとことを持つ。
/// 記録された日は StudyDay として「学んだ日」に刻まれる(日ベースの土台はそのまま)。
@Model
final class StudySession {
    /// 作業の開始日時。日への帰属はこの日付で決まる。
    var date: Date
    var minutes: Int
    var note: String?
    var item: StudyItem?

    init(date: Date, minutes: Int, note: String? = nil, item: StudyItem? = nil) {
        self.date = date
        self.minutes = minutes
        self.note = note
        self.item = item
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
            context.insert(StudyDay(date: dayStart))
        }
    }
}
