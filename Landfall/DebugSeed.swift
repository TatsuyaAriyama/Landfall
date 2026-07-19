#if DEBUG
import Foundation
import SwiftData

/// 動作確認専用のサンプル投入。Releaseビルドには含まれない(#if DEBUG)。
/// 環境変数 LANDFALL_SEED を渡したときだけ実行する。本番の起動経路には一切影響しない。
enum DebugSeed {
    /// 1プロセスにつき一度だけ投入する。App の init が複数回走っても重複を作らない。
    private static var didSeed = false

    /// UI が読むのと同じ mainContext に投入するため MainActor で実行する。
    /// 別コンテキストだと mainContext が削除を認識せず、autosave で項目が復活して重複する。
    @MainActor
    static func seedIfRequested(into container: ModelContainer) {
        guard ProcessInfo.processInfo.environment["LANDFALL_SEED"] != nil else { return }
        guard !didSeed else { return }
        didSeed = true

        let context = container.mainContext
        let calendar = Calendar.current
        let today = Date()

        // ストアは投入前に makeContainer 側で消去済み。念のため残っていれば消してから入れる。
        for session in (try? context.fetch(FetchDescriptor<StudySession>())) ?? [] { context.delete(session) }
        for day in (try? context.fetch(FetchDescriptor<StudyDay>())) ?? [] { context.delete(day) }
        for item in (try? context.fetch(FetchDescriptor<StudyItem>())) ?? [] { context.delete(item) }
        try? context.save()

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

        // 今日: 複数項目+ひとことを入れて、その日の共有カードとホームの導線を確認できる形にする。
        // LANDFALL_SEED_TODAY=0 を渡すと今日は未記録のまま(帰還・空白の見え方を確認したいとき)。
        if ProcessInfo.processInfo.environment["LANDFALL_SEED_TODAY"] != "0" {
            let todayPlan: [(StudyItem, Int, String?)] = isJapanese ? [
                (development, 95, "同期まわりを直した。手強かった。"),
                (reading, 40, "積んでいた本を30ページ。"),
                (security, 30, "午前問題を15問。半分は落とした。"),
            ] : [
                (development, 95, "Fixed the sync layer. Tough one."),
                (reading, 40, "Thirty pages of the book I'd left."),
                (security, 30, "Fifteen practice questions. Missed half."),
            ]
            for (index, entry) in todayPlan.enumerated() {
                let (item, minutes, note) = entry
                // 同じ日の中で時刻をずらし、記録された順が分かるようにする。
                let date = calendar.date(byAdding: .hour, value: -(todayPlan.count - index) * 2, to: today) ?? today
                context.insert(StudySession(date: date, minutes: minutes, note: note, item: item))
            }
            StudyDayStore.markDay(today, context: context)
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
