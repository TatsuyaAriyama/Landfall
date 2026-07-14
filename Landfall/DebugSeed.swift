#if DEBUG
import Foundation
import SwiftData

/// 動作確認専用のサンプル投入。Releaseビルドには含まれない(#if DEBUG)。
/// 環境変数 LANDFALL_SEED を渡したときだけ実行する。本番の起動経路には一切影響しない。
enum DebugSeed {
    static func seedIfRequested(into container: ModelContainer) {
        guard ProcessInfo.processInfo.environment["LANDFALL_SEED"] != nil else { return }

        let context = ModelContext(container)
        let calendar = Calendar.current
        let today = Date()

        // 既存を消してから決定的に入れ直す(何度起動しても同じ状態になる)。
        try? context.delete(model: StudyDay.self)

        // 当月: 軌跡画面が空白・帰還を含む形に見えるパターン(今日は未記録のまま残す)。
        if let monthStart = calendar.dateInterval(of: .month, for: today)?.start {
            for offset in [0, 1, 2, 9, 10, 13, 14, 15] {
                if let date = calendar.date(byAdding: .day, value: offset, to: monthStart),
                   !calendar.isDate(date, inSameDayAs: today),
                   date <= today {
                    context.insert(StudyDay(date: date))
                }
            }
        }

        // 前月: Wrapped が生成できる(前月は常に利用可能)。不死鳥型が出る配置。
        if let monthStart = calendar.dateInterval(of: .month, for: today)?.start,
           let prevStart = calendar.date(byAdding: .month, value: -1, to: monthStart) {
            for offset in [0, 1, 2, 9, 10, 13, 14, 15, 21, 22, 23, 24, 28, 29] {
                if let date = calendar.date(byAdding: .day, value: offset, to: prevStart) {
                    context.insert(StudyDay(date: date))
                }
            }
        }

        try? context.save()
    }
}
#endif
