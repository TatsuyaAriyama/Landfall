import Foundation
import SwiftData

/// 学習記録。1日1件、日付はその日の開始時刻(startOfDay)で正規化して保存する。
@Model
final class StudyDay {
    @Attribute(.unique) var date: Date
    var note: String?

    init(date: Date, note: String? = nil) {
        self.date = Calendar.current.startOfDay(for: date)
        self.note = note
    }
}
