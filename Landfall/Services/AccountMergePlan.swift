import Foundation

/// 端末の記録とアカウントの記録の「突き合わせ方」だけを、保存や通信から切り離して決める。
/// 同じ実体を二度作らないための判断はすべてここに閉じているので、
/// `Tools/RenderHarness/SyncMergeProbe.swift` から単体で検証できる。
///
/// 代表の選び方(作成が早い方、同時なら書類IDの小さい方)は入力だけで決まるため、
/// 実機とシミュレータが同時に走っても、どちらも同じ結論に達する。
enum AccountMergePlan {
    /// 突き合わせる1行。`id` は Firestore の書類ID(= UUID文字列)。
    struct Row: Equatable {
        /// 同一性の判定キー。作業項目なら正規化した名前、記録なら時刻と長さとひとこと。
        var key: String
        var id: String
        var createdAt: Date

        init(key: String, id: String, createdAt: Date) {
            self.key = key
            self.id = id
            self.createdAt = createdAt
        }
    }

    enum Decision: Equatable {
        /// 既に同じIDでアカウントにある。触らない。
        case keep
        /// 同じ実体がアカウントにある。手元のIDをそちらへ寄せる(新しい書類を作らない)。
        case adopt(String)
        /// 同じ実体を、手元のもう1行が既に持っている。その行へ畳む。
        case absorb(into: String)
        /// 本当に手元にしか無い。送る。
        case push
    }

    /// 判定キーごとの代表を選ぶ。同じ入力なら、どの端末でも必ず同じ代表になる。
    static func representatives(of remote: [Row]) -> [String: String] {
        var representative: [String: Row] = [:]
        for row in remote {
            guard let current = representative[row.key] else {
                representative[row.key] = row
                continue
            }
            if isEarlier(row, than: current) { representative[row.key] = row }
        }
        return representative.mapValues(\.id)
    }

    /// アカウント側に同じ実体が複数あるときの「取り下げる書類ID → 残す書類ID」。
    static func duplicates(in remote: [Row]) -> [String: String] {
        let keepers = representatives(of: remote)
        var result: [String: String] = [:]
        for row in remote {
            guard let keeper = keepers[row.key], keeper != row.id else { continue }
            result[row.id] = keeper
        }
        return result
    }

    /// 手元の各行をどう扱うかを決める。`local` の並び順のまま処理できる形で返す。
    /// `accountIDs` はアカウント側に実在する書類IDの集合。
    static func decisions(
        local: [Row],
        remote: [Row],
        accountIDs: Set<String>
    ) -> [String: Decision] {
        let keepers = representatives(of: remote)
        var holder: [String: String] = [:]  // 代表の書類ID → それを持つことになった手元の行
        var result: [String: Decision] = [:]

        // 先にアカウントと同じIDの行を確定させる。後から来た同名の行は、この行へ畳む。
        for row in local where accountIDs.contains(row.id) {
            result[row.id] = .keep
            holder[row.id] = row.id
        }
        for row in local where !accountIDs.contains(row.id) {
            guard let keeper = keepers[row.key] else {
                result[row.id] = .push
                continue
            }
            if holder[keeper] != nil {
                result[row.id] = .absorb(into: keeper)
            } else {
                holder[keeper] = row.id
                result[row.id] = .adopt(keeper)
            }
        }
        return result
    }

    /// 作成が早い方を優先し、同時なら書類IDの小さい方。並びに依存しない決め方。
    private static func isEarlier(_ lhs: Row, than rhs: Row) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id < rhs.id
    }

    /// 表記ゆれを吸収した突き合わせキー。大文字小文字・全角半角・前後の空白は同じ物とみなす。
    static func nameKey(_ name: String) -> String {
        name
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 同じ記録かどうかの判定。開始時刻(秒)・長さ・ひとこと・繋ぎ先まで一致したものだけを同一視する。
    static func sessionKey(
        date: Date, minutes: Int, extraSeconds: Int, note: String?, itemUUID: String?
    ) -> String {
        let second = Int(date.timeIntervalSince1970.rounded())
        return "\(itemUUID?.uppercased() ?? "-")|\(second)|\(minutes)|\(extraSeconds)|\(note ?? "")"
    }
}
