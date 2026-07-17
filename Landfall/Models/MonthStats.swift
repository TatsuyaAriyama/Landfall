import Foundation

/// 年月の識別子。Wrapped一覧の選択などに使う。
struct YearMonth: Hashable, Identifiable {
    let year: Int
    let month: Int
    var id: String { "\(year)-\(month)" }
}

/// 月次統計とタイプ診断。すべて純粋関数で、記録(StudyDay)の配列から派生値を計算する。
enum MonthStats {

    // MARK: - 記録日の集合

    /// その月に記録した日(その月の何日か)の集合。
    static func studiedDaySet(
        year: Int, month: Int, entries: [StudyDay], calendar: Calendar = .current
    ) -> Set<Int> {
        var days: Set<Int> = []
        for entry in entries {
            let comps = calendar.dateComponents([.year, .month, .day], from: entry.date)
            if comps.year == year, comps.month == month, let day = comps.day {
                days.insert(day)
            }
        }
        return days
    }

    // MARK: - WrappedMonth 生成

    /// 記録からWrappedMonthを組み立てる(タイプ診断込み)。
    /// sessions を渡すと、その月の合計学習時間(分)も算出してカードに添える。
    static func wrappedMonth(
        year: Int, month: Int, entries: [StudyDay],
        sessions: [StudySession] = [], calendar: Calendar = .current
    ) -> WrappedMonth {
        let studied = studiedDaySet(year: year, month: month, entries: entries, calendar: calendar)
        let minutes = sessions.reduce(0) { sum, session in
            let comps = calendar.dateComponents([.year, .month], from: session.date)
            return (comps.year == year && comps.month == month) ? sum + session.minutes : sum
        }
        return WrappedMonth(
            year: year,
            month: month,
            daysInMonth: daysInMonth(year: year, month: month, calendar: calendar),
            studiedDays: studied,
            archetype: diagnose(year: year, month: month, studiedDays: studied, calendar: calendar),
            totalMinutes: minutes
        )
    }

    // MARK: - タイプ診断

    /// 上から順に最初に該当したタイプを返す。全タイプ肯定的。
    static func diagnose(
        year: Int, month: Int, studiedDays: Set<Int>, calendar: Calendar = .current
    ) -> StudyArchetype {
        let dayCount = daysInMonth(year: year, month: month, calendar: calendar)
        // 空白の派生値(gaps / significantGaps / openTrailingGap)を借りるための足場。
        // archetype は参照しないのでプレースホルダを入れる。
        let scaffold = WrappedMonth(
            year: year, month: month, daysInMonth: dayCount,
            studiedDays: studiedDays, archetype: .morningCalm
        )

        // 1. 不死鳥型: 帰還済みの空白(2日以上)に、長さ5日以上がある
        if scaffold.significantGaps.contains(where: { $0.length >= 5 }) {
            return .phoenix
        }

        // 2. 石橋型: 記録が1日以上あり、すべての空白
        //    (1日空白も含む gaps 全部と、月末未帰還の openTrailingGap)が2日以内
        if !studiedDays.isEmpty,
           scaffold.gaps.allSatisfy({ $0.length <= 2 }),
           (scaffold.openTrailingGap?.length ?? 0) <= 2 {
            return .stoneBridge
        }

        // 3. 波乗り型: 学習した週が3週以上、月内に完全に含まれる週はすべて学習あり、
        //    学習週ごとの学習日数の最大-最小が1以下
        if isWaveRider(year: year, month: month, studiedDays: studiedDays,
                       daysInMonth: dayCount, calendar: calendar) {
            return .waveRider
        }

        // 4. 彗星型: 学習日が3日以上で、最長連続ブロック / 学習日数 >= 0.7
        if studiedDays.count >= 3,
           Double(longestStreak(in: studiedDays)) / Double(studiedDays.count) >= 0.7 {
            return .comet
        }

        // 5. 朝凪型: 上記以外(学習0日の月もここ)
        return .morningCalm
    }

    // MARK: - 空白日数(今日画面の「おかえり」判定)

    /// 最後の記録日の翌日から昨日までの空白日数。
    /// 記録がなければ nil。今日が記録日の翌日(連日記録)なら 0。
    static func blankDays(
        since lastRecorded: Date?, to today: Date, calendar: Calendar = .current
    ) -> Int? {
        guard let lastRecorded else { return nil }
        let start = calendar.startOfDay(for: lastRecorded)
        let end = calendar.startOfDay(for: today)
        let elapsed = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(0, elapsed - 1)
    }

    // MARK: - Wrapped 利用可能月

    /// 航海誌を閲覧できる月(振り返り用の保存庫)。記録が1日以上ある月Mについて、
    /// today が「Mの最終日」以上なら閲覧可能。過去分は無期限に残る。新しい順。
    static func completedWrappedMonths(
        entries: [StudyDay], today: Date, calendar: Calendar = .current
    ) -> [YearMonth] {
        let todayDay = calendar.startOfDay(for: today)

        var recordedMonths: Set<YearMonth> = []
        for entry in entries {
            let comps = calendar.dateComponents([.year, .month], from: entry.date)
            if let y = comps.year, let m = comps.month {
                recordedMonths.insert(YearMonth(year: y, month: m))
            }
        }

        var result: [YearMonth] = []
        for ym in recordedMonths {
            guard
                let monthStart = calendar.date(from: DateComponents(year: ym.year, month: ym.month, day: 1)),
                let lastDay = lastDayOfMonth(containing: monthStart, calendar: calendar)
            else { continue }
            if todayDay >= lastDay {
                result.append(ym)
            }
        }
        return result.sorted {
            $0.year != $1.year ? $0.year > $1.year : $0.month > $1.month
        }
    }

    /// Wrappedを生成できる月。記録が1日以上ある月Mについて、
    /// today が「Mの最終日」以上かつ「M+1月の末日」以下のとき利用可能。新しい順。
    static func availableWrappedMonths(
        entries: [StudyDay], today: Date, calendar: Calendar = .current
    ) -> [YearMonth] {
        let todayDay = calendar.startOfDay(for: today)

        var recordedMonths: Set<YearMonth> = []
        for entry in entries {
            let comps = calendar.dateComponents([.year, .month], from: entry.date)
            if let y = comps.year, let m = comps.month {
                recordedMonths.insert(YearMonth(year: y, month: m))
            }
        }

        var result: [YearMonth] = []
        for ym in recordedMonths {
            guard
                let monthStart = calendar.date(from: DateComponents(year: ym.year, month: ym.month, day: 1)),
                let lastDay = lastDayOfMonth(containing: monthStart, calendar: calendar),
                let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart),
                let nextLastDay = lastDayOfMonth(containing: nextMonthStart, calendar: calendar)
            else { continue }
            if todayDay >= lastDay && todayDay <= nextLastDay {
                result.append(ym)
            }
        }
        return result.sorted {
            $0.year != $1.year ? $0.year > $1.year : $0.month > $1.month
        }
    }

    // MARK: - 内部ヘルパ

    /// その月の日数。
    private static func daysInMonth(year: Int, month: Int, calendar: Calendar) -> Int {
        guard
            let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
            let range = calendar.range(of: .day, in: .month, for: monthStart)
        else { return 30 }
        return range.count
    }

    /// 月の最終日(startOfDay)。
    private static func lastDayOfMonth(containing date: Date, calendar: Calendar) -> Date? {
        guard
            let range = calendar.range(of: .day, in: .month, for: date),
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
            let last = calendar.date(byAdding: .day, value: range.count - 1, to: monthStart)
        else { return nil }
        return calendar.startOfDay(for: last)
    }

    /// 最長連続ブロックの日数。
    private static func longestStreak(in studiedDays: Set<Int>) -> Int {
        let sorted = studiedDays.sorted()
        guard !sorted.isEmpty else { return 0 }
        var best = 1
        var current = 1
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            if b == a + 1 {
                current += 1
                best = max(best, current)
            } else {
                current = 1
            }
        }
        return best
    }

    /// 波乗り型の判定。週はその月と交差する calendar 週単位で数える
    /// (週の日数カウントは月内の日のみ対象)。
    private static func isWaveRider(
        year: Int, month: Int, studiedDays: Set<Int>, daysInMonth: Int, calendar: Calendar
    ) -> Bool {
        guard !studiedDays.isEmpty,
              let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1))
        else { return false }

        // 週の開始日 → その週に属する月内の日(1始まり)
        var weekDays: [Date: [Int]] = [:]
        for day in 1...daysInMonth {
            guard
                let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart),
                let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start
            else { return false }
            weekDays[weekStart, default: []].append(day)
        }

        // 学習した週ごとの学習日数
        let studiedCounts: [Int] = weekDays.values.compactMap { days in
            let count = days.filter { studiedDays.contains($0) }.count
            return count > 0 ? count : nil
        }

        // 学習した週が3週以上
        guard studiedCounts.count >= 3 else { return false }

        // 月内に完全に含まれる週(7日すべてが月内)はすべて学習あり
        for days in weekDays.values where days.count == 7 {
            if !days.contains(where: { studiedDays.contains($0) }) { return false }
        }

        // 学習週ごとの学習日数の最大-最小が1以下
        guard let maxCount = studiedCounts.max(), let minCount = studiedCounts.min() else {
            return false
        }
        return maxCount - minCount <= 1
    }
}
