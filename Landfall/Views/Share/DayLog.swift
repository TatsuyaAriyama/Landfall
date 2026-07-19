import Foundation
import SwiftData

/// その日の記録を、共有カード用に畳んだ値。
/// カードは ImageRenderer で描くので、SwiftData のオブジェクトを直接持たず
/// 描画に必要な素の値だけを写し取る(描画中にモデルが変わっても崩れない)。
struct DayLog {
    /// 項目ひとつぶんの合計。
    struct Entry: Identifiable {
        let id: String
        let name: String
        let styleToken: String
        let symbolToken: String
        let photoData: Data?
        let minutes: Int
    }

    let date: Date
    /// 項目ごとに合算し、長い順。
    let entries: [Entry]
    /// その日に書いたひとこと(空は除く)。書いた順。
    let notes: [String]
    let totalMinutes: Int
    let sessionCount: Int

    var isRestDay: Bool { sessionCount == 0 }
    var itemCount: Int { entries.count }

    /// その日のセッションから組み立てる。項目ごとに合算し、ひとことは順に拾う。
    static func make(date: Date, sessions: [StudySession], calendar: Calendar = .current) -> DayLog {
        let ofDay = sessions
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date < $1.date }

        // 項目ごとに合算(項目が消えた記録は「項目なし」に寄せる)。
        var order: [String] = []
        var byKey: [String: Entry] = [:]
        for session in ofDay {
            let item = session.item
            let key = item?.uuid.uuidString ?? "__none__"
            if let existing = byKey[key] {
                byKey[key] = Entry(
                    id: existing.id, name: existing.name,
                    styleToken: existing.styleToken, symbolToken: existing.symbolToken,
                    photoData: existing.photoData,
                    minutes: existing.minutes + session.minutes
                )
            } else {
                order.append(key)
                byKey[key] = Entry(
                    id: key,
                    name: item?.name ?? String(localized: "No item"),
                    styleToken: item?.styleToken ?? TileStyle.ink.rawValue,
                    symbolToken: item?.symbolToken ?? TileSymbol.compass.rawValue,
                    photoData: item?.photoData,
                    minutes: session.minutes
                )
            }
        }

        let entries = order.compactMap { byKey[$0] }.sorted { $0.minutes > $1.minutes }
        let notes = ofDay.compactMap { session -> String? in
            guard let note = session.note?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !note.isEmpty else { return nil }
            return note
        }

        return DayLog(
            date: date,
            entries: entries,
            notes: notes,
            totalMinutes: ofDay.reduce(0) { $0 + $1.minutes },
            sessionCount: ofDay.count
        )
    }
}
