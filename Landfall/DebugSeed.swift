#if DEBUG
import Foundation
import SwiftData

/// 動作確認専用のサンプル投入。Releaseビルドには含まれない(#if DEBUG)。
/// 環境変数 LANDFALL_SEED=1 を渡したときだけ実行する。
/// サンプルはメモリ内ストアだけに保存し、アカウントと同期しない。
enum DebugSeed {
    /// 1プロセスにつき一度だけ投入する。App の init が複数回走っても重複を作らない。
    private static var didSeed = false

    /// UI が読むのと同じ mainContext に投入するため MainActor で実行する。
    /// 別コンテキストだと mainContext が削除を認識せず、autosave で項目が復活して重複する。
    @MainActor
    static func seedIfRequested(into container: ModelContainer) {
        guard ProcessInfo.processInfo.environment["LANDFALL_SEED"] == "1" else { return }
        guard !didSeed else { return }
        didSeed = true

        let context = container.mainContext
        let calendar = Calendar.current
        let today = Date()

        // 一時ストアは空で始まる。念のため残っていれば消してから入れる。
        for session in (try? context.fetch(FetchDescriptor<StudySession>())) ?? [] { context.delete(session) }
        for day in (try? context.fetch(FetchDescriptor<StudyDay>())) ?? [] { context.delete(day) }
        for item in (try? context.fetch(FetchDescriptor<StudyItem>())) ?? [] { context.delete(item) }
        for destination in (try? context.fetch(FetchDescriptor<Destination>())) ?? [] {
            context.delete(destination)
        }
        try? context.save()

        // ストア用スクリーンショットは英語/日本語の両方で撮る。SwiftUIへ
        // LANDFALL_LANGを渡してもLocale.preferredLanguages自体は変わらないため、
        // サンプルデータも同じ明示指定を優先する。
        let forcedLanguage = ProcessInfo.processInfo.environment["LANDFALL_LANG"]
        let isJapanese = forcedLanguage == "ja" ||
            (forcedLanguage == nil && (Locale.preferredLanguages.first?.hasPrefix("ja") ?? false))

        // 学習項目(今日画面のタイル)。
        let development = StudyItem(name: isJapanese ? "開発" : "Coding", styleToken: "midnight", symbolToken: "phoenix", sortOrder: 0)
        if ProcessInfo.processInfo.environment["LANDFALL_PRIVATE_PREVIEW"] == "1" {
            development.uuid = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
        }
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
                    StudyDayStore.markDay(date, context: context, syncsToAccount: false)
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
            // 「今」から引くと、深夜に動かしたとき前日へこぼれる(記録とひとことの日がずれる)。
            // その日の始まりからの固定時刻に置き、必ず当日に収める。
            let dayStart = calendar.startOfDay(for: today)
            let hours = [9, 13, 20]
            for (index, entry) in todayPlan.enumerated() {
                let (item, minutes, note) = entry
                let date = calendar.date(byAdding: .hour, value: hours[index % hours.count], to: dayStart) ?? today
                context.insert(StudySession(date: date, minutes: minutes, note: note, item: item))
            }
            StudyDayStore.markDay(today, context: context, syncsToAccount: false)
            // setComment は既存の StudyDay を引いて書き換えるので、先に確定させる。
            try? context.save()
            // その日のカード用のひとこと(記録ごとのメモとは別物)。
            StudyDayStore.setComment(
                isJapanese ? "久しぶりに読書に没頭できた。"
                           : "Lost myself in a book for the first time in a while.",
                for: today, context: context,
                syncsToAccount: false
            )
        }

        // LANDFALL_SEED_LEVEL=6 のように渡すと、その段階へ届くだけの時間を
        // 半年前へ一括で置く。レベルで開く装備(船など)を、実際に時間を
        // 積まずに確かめるための入口。
        if let raw = ProcessInfo.processInfo.environment["LANDFALL_SEED_LEVEL"],
           let level = Int(raw), level > 1,
           let backdated = calendar.date(byAdding: .day, value: -180, to: today) {
            context.insert(StudySession(
                date: backdated,
                minutes: (level - 1) * PlayerLevelProgress.minutesPerLevel,
                note: nil,
                item: development
            ))
            StudyDayStore.markDay(backdated, context: context, syncsToAccount: false)
            try? context.save()
        }

        // 日別航海誌の確認用。昨日はまだ編集できる頁、5日前は読み返すだけの綴じた頁。
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            context.insert(StudySession(
                date: calendar.date(byAdding: .hour, value: 19, to: calendar.startOfDay(for: yesterday)) ?? yesterday,
                minutes: 35,
                note: nil,
                item: reading
            ))
            StudyDayStore.markDay(yesterday, context: context, syncsToAccount: false)
            try? context.save()
            StudyDayStore.setComment(
                isJapanese ? "急がずに進んだら、景色をよく見られた。"
                           : "Going slowly let me notice more of the view.",
                for: yesterday,
                context: context,
                syncsToAccount: false
            )
        }

        if let pastDate = calendar.date(byAdding: .day, value: -5, to: today) {
            let pastStart = calendar.startOfDay(for: pastDate)
            context.insert(StudySession(
                date: calendar.date(byAdding: .hour, value: 10, to: pastStart) ?? pastDate,
                minutes: 50,
                note: nil,
                item: development
            ))
            StudyDayStore.markDay(pastDate, context: context, syncsToAccount: false)
            try? context.save()
            var descriptor = FetchDescriptor<StudyDay>(predicate: #Predicate { $0.date == pastStart })
            descriptor.fetchLimit = 1
            if let pastDay = (try? context.fetch(descriptor))?.first {
                let sealedReflection = isJapanese
                    ? "向かい風だった。それでも帆を畳まずにいられた。"
                    : "The wind was against me, but I kept the sail raised."
                pastDay.note = sealedReflection
                pastDay.updatedAt = Date()

                // 保存層の期限も確認する。UIを迂回しても5日前の頁は変更できない。
                let accepted = StudyDayStore.setComment(
                    "This must not overwrite a sealed page.",
                    for: pastDate,
                    context: context,
                    now: today,
                    syncsToAccount: false
                )
                assert(!accepted && pastDay.note == sealedReflection)
            }
        }

        // 目的地(島)。ステップ目標を1件、途中まで達成した状態で置く(ブイの点灯/消灯と
        // 途中の船位置を確認できる)。createdAt は当月頭にして累計時間が乗るように。
        let destCreatedAt = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let dest = Destination(
            name: isJapanese ? "TOEIC" : "TOEIC",
            createdAt: destCreatedAt,
            steps: [
                DestinationStep(name: isJapanese ? "単語帳を1周" : "One pass of the vocab book", doneAt: destCreatedAt),
                DestinationStep(name: isJapanese ? "文法書を1周" : "One pass of grammar", doneAt: destCreatedAt),
                DestinationStep(name: isJapanese ? "公式問題集を1回" : "Official test set once"),
            ]
        )
        // LANDFALL_SEED_REACHED=1 で全ステップ達成にし、着岸演出の確認に使う。
        if ProcessInfo.processInfo.environment["LANDFALL_SEED_REACHED"] != nil {
            for i in dest.steps.indices { dest.steps[i].doneAt = destCreatedAt }
        }
        context.insert(dest)

        // 到達済みの島。設定画面の「到達した島」一覧と削除を確認するために置く。
        if let reachedAt = calendar.date(byAdding: .day, value: -20, to: today) {
            let reached = Destination(
                name: isJapanese ? "英検準1級" : "Reading marathon",
                createdAt: calendar.date(byAdding: .day, value: -60, to: today) ?? today,
                steps: [DestinationStep(name: isJapanese ? "過去問を3年分" : "Three years of past papers", doneAt: reachedAt)]
            )
            reached.achievedAt = reachedAt
            context.insert(reached)
        }

        // 前月: Wrapped が生成できる(前月は常に利用可能)。不死鳥型が出る配置。
        if let monthStart = calendar.dateInterval(of: .month, for: today)?.start,
           let prevStart = calendar.date(byAdding: .month, value: -1, to: monthStart) {
            for offset in [0, 1, 2, 9, 10, 13, 14, 15, 21, 22, 23, 24, 28, 29] {
                if let date = calendar.date(byAdding: .day, value: offset, to: prevStart) {
                    context.insert(StudySession(date: date, minutes: 30, note: nil, item: development))
                    StudyDayStore.markDay(date, context: context, syncsToAccount: false)
                }
            }
        }

        try? context.save()

        // LANDFALL_VOYAGE_DONE=<分> の確認は完了札まで進んだ状態が要る。
        // 航海中のタイマーを1本立て、ホームがそのまま航海画面を開くようにする。
        if ProcessInfo.processInfo.environment["LANDFALL_VOYAGE_DONE"] != nil {
            StudyTimer.defaults.set(Date().timeIntervalSince1970, forKey: StudyTimer.startKey)
            StudyTimer.defaults.set(development.uuid.uuidString, forKey: StudyTimer.itemKey)
        }

        WidgetBridge.refresh(context: context)
    }
}
#endif
