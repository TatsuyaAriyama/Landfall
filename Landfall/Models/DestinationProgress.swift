import Foundation

/// 目的地の進捗(Web版 destinations.ts の `destinationProgress` を移植)。
struct DestinationProgress {
    /// 島までの近さ 0..1。
    var ratio: Double
    /// createdAt 以降の累計(分)。着岸時に見せる「航海した時間」。
    var minutes: Int
    /// 累計時間目標の残り。
    var remainingMinutes: Int?
    /// 期日目標の残り日数。
    var remainingDays: Int?
    /// 期日目標の締切までの残り秒数。当日は時間・分で表示する。
    var remainingSeconds: TimeInterval?
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
        let minutes = sessions.reduce(0) { sum, session in
            guard session.date >= since else { return sum }
            if let itemUUID, session.item?.uuid.uuidString != itemUUID { return sum }
            return sum + session.minutes
        }

        // ステップ目標: 進捗 = 完了数 / 全数。全部完了で着岸。
        let boundedSteps = Array(steps.prefix(Self.maxSteps))
        if !boundedSteps.isEmpty {
            let done = boundedSteps.filter { $0.doneAt != nil }.count
            return DestinationProgress(
                ratio: Double(done) / Double(boundedSteps.count),
                minutes: minutes,
                remainingMinutes: nil,
                remainingDays: nil,
                remainingSeconds: nil,
                stepsDone: done,
                stepsTotal: boundedSteps.count,
                reached: done == boundedSteps.count
            )
        }

        // 完了目標: 本人がチェックしたときだけ着く。期日は表示用のメモ。
        if manual {
            let cal = Calendar.current
            let remaining = deadline(calendar: cal).map {
                max(
                    0,
                    Int(
                        (
                            cal.startOfDay(for: $0).timeIntervalSince(
                                cal.startOfDay(for: now)
                            ) / 86_400
                        ).rounded()
                    )
                )
            }
            return DestinationProgress(
                ratio: manualDone ? 1 : 0,
                minutes: minutes,
                remainingMinutes: nil,
                remainingDays: remaining,
                remainingSeconds: nil,
                stepsDone: nil,
                stepsTotal: nil,
                reached: manualDone
            )
        }

        // 累計時間目標: 作成後の対象記録で進む。
        if let targetMinutes, targetMinutes > 0 {
            let ratio = min(1, Double(minutes) / Double(targetMinutes))
            return DestinationProgress(
                ratio: ratio,
                minutes: minutes,
                remainingMinutes: max(0, targetMinutes - minutes),
                remainingDays: nil,
                remainingSeconds: nil,
                stepsDone: nil,
                stepsTotal: nil,
                reached: ratio >= 1
            )
        }

        // 期日目標: 期日が7日より先なら最遠地点に留まり、残り7日を
        // 切ってから実時刻で連続的に接近する。締切ちょうどで着岸。
        if let end = deadline() {
            let finish = end.timeIntervalSince1970
            let current = now.timeIntervalSince1970
            let remaining = max(0, finish - current)
            let approachWindow: TimeInterval = 7 * 86_400
            let ratio = min(1, max(0, 1 - remaining / approachWindow))
            return DestinationProgress(
                ratio: ratio,
                minutes: minutes,
                remainingMinutes: nil,
                remainingDays: Int(ceil(remaining / 86_400)),
                remainingSeconds: remaining,
                stepsDone: nil,
                stepsTotal: nil,
                reached: current >= finish
            )
        }

        return DestinationProgress(
            ratio: 0, minutes: minutes, remainingMinutes: nil, remainingDays: nil,
            remainingSeconds: nil,
            stepsDone: nil, stepsTotal: nil, reached: false
        )
    }

    /// カードに出す一言用: 次の未達ステップ名(ステップ目標のとき)。ラベル整形はビュー側で
    /// SwiftUI Text(環境ロケール準拠)で行い、アプリ内言語切替に追従させる。
    var nextStepName: String? {
        steps.prefix(Self.maxSteps).first(where: { $0.doneAt == nil })?.name
    }

    /// 直近に辿り着いた小島(達成日が最も新しいステップ)。ホームのカードに
    /// 「いつその小さな目標を達成したか」を小さく添えるために使う。
    var latestDoneStep: DestinationStep? {
        steps.prefix(Self.maxSteps).filter { $0.doneAt != nil }
            .max { ($0.doneAt ?? .distantPast) < ($1.doneAt ?? .distantPast) }
    }
}
