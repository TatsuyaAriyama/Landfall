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
        try? context.delete(model: StudySession.self)
        try? context.delete(model: StudyItem.self)
        try? context.delete(model: StudyDay.self)

        // ストア用スクリーンショットは英語/日本語ロケール両方で撮るため、項目名・メモも実行時ロケールに合わせる。
        let isJapanese = Locale.preferredLanguages.first?.hasPrefix("ja") ?? false

        // 学習項目(今日画面のタイル)。
        let development = StudyItem(name: isJapanese ? "開発" : "Coding", styleToken: "midnight", symbolToken: "phoenix", sortOrder: 0)
        let reading = StudyItem(name: isJapanese ? "読書" : "Reading", styleToken: "coral", symbolToken: "book", sortOrder: 1)
        let writing = StudyItem(name: isJapanese ? "記事作成" : "Writing", styleToken: "ink", symbolToken: "pen", sortOrder: 2)
        let security = StudyItem(name: isJapanese ? "情報セキュリティ" : "Security exam", styleToken: "seaGreen", symbolToken: "wave", sortOrder: 3)
        for item in [development, reading, writing, security] {
            context.insert(item)
        }

        // 当月: 軌跡画面が空白・帰還を含む形に見えるパターン(今日は未記録のまま残す)。
        if let monthStart = calendar.dateInterval(of: .month, for: today)?.start {
            let plan: [(Int, StudyItem, Int, String?)] = isJapanese ? [
                (0, development, 45, "環境構築をやり切った。"),
                (1, reading, 30, nil),
                (2, development, 60, "画面を1枚組んだ。"),
                (9, reading, 20, "積んでいた本に戻れた。"),
                (10, writing, 40, nil),
                (13, development, 30, nil),
                (14, security, 25, "午前問題を10問。"),
                (15, reading, 35, nil),
            ] : [
                (0, development, 45, "Got the environment set up."),
                (1, reading, 30, nil),
                (2, development, 60, "Built one screen."),
                (9, reading, 20, "Picked the book back up."),
                (10, writing, 40, nil),
                (13, development, 30, nil),
                (14, security, 25, "Ten practice questions."),
                (15, reading, 35, nil),
            ]
            for (offset, item, minutes, note) in plan {
                if let date = calendar.date(byAdding: .day, value: offset, to: monthStart),
                   !calendar.isDate(date, inSameDayAs: today),
                   date <= today {
                    context.insert(StudySession(date: date, minutes: minutes, note: note, item: item))
                    StudyDayStore.markDay(date, context: context)
                }
            }
        }

        // 前月: Wrapped が生成できる(前月は常に利用可能)。不死鳥型が出る配置。
        if let monthStart = calendar.dateInterval(of: .month, for: today)?.start,
           let prevStart = calendar.date(byAdding: .month, value: -1, to: monthStart) {
            for offset in [0, 1, 2, 9, 10, 13, 14, 15, 21, 22, 23, 24, 28, 29] {
                if let date = calendar.date(byAdding: .day, value: offset, to: prevStart) {
                    context.insert(StudySession(date: date, minutes: 30, note: nil, item: development))
                    StudyDayStore.markDay(date, context: context)
                }
            }
        }

        try? context.save()
    }
}
#endif
