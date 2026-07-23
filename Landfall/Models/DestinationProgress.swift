import Foundation

/// 目的地の進捗(Web版 destinations.ts の `destinationProgress` を移植)。
struct DestinationProgress {
    /// 島までの近さ 0..1。
    var ratio: Double
    /// createdAt 以降の累計(分)。着岸時に見せる「航海した時間」。
    var minutes: Int
    /// 期日目標の残り日数。
    var remainingDays: Int?
    /// ステップ目標の完了数 / 全数。
    var stepsDone: Int?
    var stepsTotal: Int?
    /// 到達(着岸)したか。
    var reached: Bool
}

extension Destination {
    /// 島までの進捗。ステップ目標=完了数/全数、期日目標=経過時間で近づく。
    /// `minutes` は createdAt 以降の全セッション合計。
    func progress(sessions: [StudySession], now: Date = Date()) -> DestinationProgress {
        let since = createdAt
        let minutes = sessions.reduce(0) { $1.date >= since ? $0 + $1.minutes : $0 }

        // ステップ目標: 進捗 = 完了数 / 全数。全部完了で着岸。
        if !steps.isEmpty {
            let done = steps.filter { $0.doneAt != nil }.count
            return DestinationProgress(
                ratio: Double(done) / Double(steps.count),
                minutes: minutes,
                remainingDays: nil,
                stepsDone: done,
                stepsTotal: steps.count,
                reached: done == steps.count
            )
        }

        // 期日目標: 経過時間で船が近づく。期日到来で着岸。
        if let target = targetDate {
            let cal = Calendar.current
            let start = cal.startOfDay(for: since)
            let end = cal.startOfDay(for: target)
            let today = cal.startOfDay(for: now)
            let total = max(1, end.timeIntervalSince(start))
            let ratio = min(1, max(0, today.timeIntervalSince(start) / total))
            let remaining = max(0, Int((end.timeIntervalSince(today) / 86_400).rounded()))
            return DestinationProgress(
                ratio: ratio,
                minutes: minutes,
                remainingDays: remaining,
                stepsDone: nil,
                stepsTotal: nil,
                reached: today >= end
            )
        }

        return DestinationProgress(
            ratio: 0, minutes: minutes, remainingDays: nil,
            stepsDone: nil, stepsTotal: nil, reached: false
        )
    }

    /// カードに出す一言用: 次の未達ステップ名(ステップ目標のとき)。ラベル整形はビュー側で
    /// SwiftUI Text(環境ロケール準拠)で行い、アプリ内言語切替に追従させる。
    var nextStepName: String? {
        steps.first(where: { $0.doneAt == nil })?.name
    }
}
