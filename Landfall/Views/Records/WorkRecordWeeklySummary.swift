import Foundation

/// Weekly accounting follows the saved record date, just like progression and
/// the existing calendar. Timing metadata is deliberately not used to invent or
/// redistribute durations for historical / manually entered records.
enum WorkRecordWeeklySummary {
    struct Record {
        var date: Date
        var seconds: Int
        var itemID: String?
        var itemName: String?
    }

    struct ItemTotal: Identifiable {
        var id: String
        var name: String?
        var seconds: Int
    }

    struct Day: Identifiable {
        var date: Date
        var seconds: Int
        var recordCount: Int
        var id: Date { date }
    }

    struct Summary {
        var weekStart: Date
        var through: Date
        var previousWeekStart: Date
        var previousThrough: Date
        var totalSeconds: Int
        var previousSeconds: Int
        var activeDayCount: Int
        var recordCount: Int
        var leadingItems: [ItemTotal]
        var days: [Day]

        var differenceSeconds: Int { totalSeconds - previousSeconds }
    }

    static func summarize(
        _ records: [Record],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Summary {
        let reference = now.timeIntervalSinceReferenceDate.isFinite ? now : Date(timeIntervalSince1970: 0)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: reference)?.start
            ?? calendar.startOfDay(for: reference)
        let previousStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        // Calendar arithmetic preserves the local weekday and clock time across
        // DST. Subtracting 604800 seconds would skew a partial-week comparison.
        let previousThrough = calendar.date(byAdding: .day, value: -7, to: reference) ?? previousStart
        var days = (0..<7).compactMap { offset -> Day? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            return Day(date: date, seconds: 0, recordCount: 0)
        }
        var total = 0
        var previous = 0
        var count = 0
        var items: [String: ItemTotal] = [:]
        for record in records where record.seconds > 0 && record.date.timeIntervalSinceReferenceDate.isFinite {
            if record.date >= previousStart && record.date <= previousThrough && record.date < weekStart {
                previous = adding(previous, record.seconds)
            }
            guard record.date >= weekStart && record.date <= reference else { continue }
            total = adding(total, record.seconds)
            count = adding(count, 1)
            if let index = days.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: record.date) }) {
                days[index].seconds = adding(days[index].seconds, record.seconds)
                days[index].recordCount = adding(days[index].recordCount, 1)
            }
            let id = record.itemID ?? "unassigned"
            let name = record.itemName?.trimmingCharacters(in: .whitespacesAndNewlines)
            var item = items[id] ?? ItemTotal(id: id, name: name?.isEmpty == false ? name : nil, seconds: 0)
            item.seconds = adding(item.seconds, record.seconds)
            items[id] = item
        }
        return Summary(
            weekStart: weekStart,
            through: reference,
            previousWeekStart: previousStart,
            previousThrough: previousThrough,
            totalSeconds: total,
            previousSeconds: previous,
            activeDayCount: days.filter { $0.seconds > 0 }.count,
            recordCount: count,
            leadingItems: Array(items.values.sorted {
                if $0.seconds != $1.seconds { return $0.seconds > $1.seconds }
                return $0.id < $1.id
            }.prefix(3)),
            days: days
        )
    }

    private static func adding(_ lhs: Int, _ rhs: Int) -> Int {
        let sum = lhs.addingReportingOverflow(rhs)
        return sum.overflow ? Int.max : sum.partialValue
    }
}
