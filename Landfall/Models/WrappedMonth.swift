import Foundation

/// 空白区間(記録のない連続日)。
struct GapSpan: Equatable, Identifiable {
    var startDay: Int   // 空白の開始日(その月の何日か)
    var length: Int     // 空白の日数
    var endDay: Int { startDay + length - 1 }
    var id: Int { startDay }
}

/// カード1の締めに出す「その月の物語」。判定は日数の形だけで行い、時間は使わない。
enum MonthNarrative {
    case perfect       // 皆勤(1日も休まなかった)
    case nearPerfect   // ほぼ皆勤(休みが1〜2日)
    case fewSparks     // ごくわずか(学んだ日が1〜2日)
    case longReturn    // 長い空白から復帰(最長の帰還済み空白が5日以上)
    case manyReturns   // 離脱頻発(帰還が3回以上)
    case balanced      // 学びと休みが拮抗
    case steady        // 上記以外
}

/// 1か月分のWrappedデータ。派生値は保存せず、記録日の集合から都度計算する。
struct WrappedMonth {
    let year: Int
    let month: Int
    let daysInMonth: Int
    let studiedDays: Set<Int>     // 記録した日(その月の何日か)
    let archetype: StudyArchetype // 判定は診断ロジックで行い、ここに注入する
    var totalMinutes: Int = 0     // その月の合計学習時間(分)。カードに小さく添えるだけ。

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

    /// その月の物語(日数の形だけで判定。時間は見ない)。
    /// 上から順に最初に該当したものを返す。
    var narrative: MonthNarrative {
        guard studiedCount > 0 else { return .steady }        // 実際には記録のある月しか来ない
        if restedCount == 0 { return .perfect }               // 皆勤
        if restedCount <= 2 { return .nearPerfect }           // ほぼ皆勤
        if studiedCount <= 2 { return .fewSparks }            // ごくわずか
        if let longest = longestGap, longest.length >= 5 { return .longReturn } // 長い空白から復帰
        if resumeCount >= 3 { return .manyReturns }           // 離脱頻発
        if abs(studiedCount - restedCount) <= 4 { return .balanced } // 拮抗
        return .steady
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
        archetype: .phoenix,
        totalMinutes: 24 * 60 + 30
    )
}
