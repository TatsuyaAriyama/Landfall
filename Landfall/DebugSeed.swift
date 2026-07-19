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
            // 9日目は6日の空白明け。「また戻れた」がこのアプリの主題なので、そこに一番いい一行を置く。
            let plan: [(Int, StudyItem, Int, String?)] = isJapanese ? [
                (0, development, 45, "はじめの準備で手間取った。それでも動いた。"),
                (1, reading, 30, nil),
                (2, development, 60, "画面を1枚、形にできた。"),
                (9, reading, 20, "しばらく置いていた本に、また手が伸びた。"),
                (10, writing, 40, nil),
                (13, development, 30, nil),
                (14, security, 25, "今日は少しだけ。開いたことが大事。"),
                (15, reading, 35, nil),
            ] : [
                (0, development, 45, "Setup took longer than I thought. It runs now."),
                (1, reading, 30, nil),
                (2, development, 60, "Got one screen into shape."),
                (9, reading, 20, "Reached for the book I'd set down. Again."),
                (10, writing, 40, nil),
                (13, development, 30, nil),
                (14, security, 25, "Only a little today. Opening it was the point."),
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
            // 共有カード・ストア用スクリーンショットに写る文章。専門用語を避け、
            // 「自分も書きそう」と思える一行にする(達成・没頭・続きへ、で感情に幅を出す)。
            // 記録ごとのひとことは、いつもどおりそれぞれに残す。
            let todayPlan: [(StudyItem, Int, String?)] = isJapanese ? [
                (development, 95, "詰まっていた所が、やっと動いた。"),
                (reading, 40, "続きが気になって、寝る前にもう少し。"),
                (security, 30, "わからない所に印をつけた。次はそこから。"),
            ] : [
                (development, 95, "The part I was stuck on finally moved."),
                (reading, 40, "Couldn't put it down. A few more pages before bed."),
                (security, 30, "Marked what I didn't get. I'll start there next time."),
            ]
            for (index, entry) in todayPlan.enumerated() {
                let (item, minutes, note) = entry
                // 同じ日の中で時刻をずらし、記録された順が分かるようにする。
                let date = calendar.date(byAdding: .hour, value: -(todayPlan.count - index) * 2, to: today) ?? today
                context.insert(StudySession(date: date, minutes: minutes, note: note, item: item))
            }
            StudyDayStore.markDay(today, context: context)
            // その日のカード用のひとこと(記録ごとのメモとは別物)。
            StudyDayStore.setComment(
                isJapanese ? "久しぶりに読書に没頭できた。"
                           : "Lost myself in a book for the first time in a while.",
                for: today, context: context
            )
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
