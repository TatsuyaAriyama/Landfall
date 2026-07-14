import Foundation

/// 空白区間(記録のない連続日)。
struct GapSpan: Equatable, Identifiable {
    var startDay: Int   // 空白の開始日(その月の何日か)
    var length: Int     // 空白の日数
    var endDay: Int { startDay + length - 1 }
    var id: Int { startDay }
}

/// 1か月分のWrappedデータ。派生値は保存せず、記録日の集合から都度計算する。
struct WrappedMonth {
    let year: Int
    let month: Int
    let daysInMonth: Int
    let studiedDays: Set<Int>     // 記録した日(その月の何日か)
    let archetype: StudyArchetype // 判定は診断ロジックで行い、ここに注入する

    // MARK: 派生値

    var studiedCount: Int { studiedDays.count }
    var restedCount: Int { daysInMonth - studiedDays.count }

    /// やめた回数。定義上、常に0。
    var quitCount: Int { 0 }

    /// 記録日に挟まれた空白区間(長さ1日以上すべて)。
    var gaps: [GapSpan] {
        let sorted = studiedDays.sorted()
        guard sorted.count >= 2 else { return [] }
        var result: [GapSpan] = []
        for (a, b) in zip(sorted, sorted.dropFirst()) where b - a > 1 {
            result.append(GapSpan(startDay: a + 1, length: b - a - 1))
        }
        return result
    }

    /// 軌跡やカードで「空白」として語る区間(2日以上)。定義上すべて帰還済み。
    var significantGaps: [GapSpan] {
        gaps.filter { $0.length >= 2 }
    }

    /// 月末まで続いている未帰還の空白(2日以上のみ)。まだ物語の途中なので責めない。
    var openTrailingGap: GapSpan? {
        guard let last = studiedDays.max(), daysInMonth - last >= 2 else { return nil }
        return GapSpan(startDay: last + 1, length: daysInMonth - last)
    }

    var longestGap: GapSpan? {
        significantGaps.max { $0.length < $1.length }
    }

    /// 帰還した日 = 2日以上の空白の直後に記録した日。
    var resumeDays: [Int] {
        significantGaps.map { $0.endDay + 1 }
    }

    var resumeCount: Int { resumeDays.count }

    /// 再開力スコア(0〜100)。帰還した空白の割合。
    /// 空白の「長さ」は問わない — 戻ったかどうかだけを見る。
    /// 空白が一度もない月は nil(スコア自体が不要)。
    var resumePower: Int? {
        let returned = significantGaps.count
        let open = openTrailingGap == nil ? 0 : 1
        guard returned + open > 0 else { return nil }
        return Int((Double(returned) / Double(returned + open) * 100).rounded())
    }

    /// 「5/10」形式。
    func shortDate(_ day: Int) -> String { "\(month)/\(day)" }
}

extension WrappedMonth {
    /// ダミーデータ: 2026年5月。学14日/休17日、最長空白6日、帰還4回、不死鳥型。
    static let dummy = WrappedMonth(
        year: 2026,
        month: 5,
        daysInMonth: 31,
        studiedDays: [1, 2, 3, 10, 11, 14, 15, 16, 22, 23, 24, 25, 29, 30],
        archetype: .phoenix
    )
}
