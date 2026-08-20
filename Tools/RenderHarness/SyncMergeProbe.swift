import Foundation

/// AccountMergePlan の単体検証。多端末ログインで作業項目が複製されないことを、
/// 保存も通信も伴わずに確かめる。
///
///   swiftc -parse-as-library -O Landfall/Services/AccountMergePlan.swift \
///          Tools/RenderHarness/SyncMergeProbe.swift -o /tmp/syncmergeprobe && /tmp/syncmergeprobe
@main
enum SyncMergeProbe {
    static func main() {
        var failures: [String] = []

        func expect(_ condition: Bool, _ what: String) {
            print("\(condition ? "ok  " : "FAIL") \(what)")
            if !condition { failures.append(what) }
        }

        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        let day1 = day0.addingTimeInterval(86_400)

        func row(_ key: String, _ id: String, _ createdAt: Date = day0) -> AccountMergePlan.Row {
            AccountMergePlan.Row(key: key, id: id, createdAt: createdAt)
        }

        // 1. 別端末でログインした直後。アカウントには英語と数学があり、
        //    手元(ローカルモードで使っていた分)にも同じ名前の項目がある。
        let remote = [row("english", "R-ENGLISH"), row("math", "R-MATH")]
        let local = [row("english", "L-ENGLISH"), row("math", "L-MATH")]
        var plan = AccountMergePlan.decisions(
            local: local, remote: remote, accountIDs: ["R-ENGLISH", "R-MATH"]
        )
        expect(plan["L-ENGLISH"] == .adopt("R-ENGLISH"), "同名の項目はアカウント側のIDへ寄る(複製を作らない)")
        expect(plan["L-MATH"] == .adopt("R-MATH"), "2件目も同じく寄る")

        // 2. 手元にしか無い項目は必ず送る(取りこぼさない)。
        plan = AccountMergePlan.decisions(
            local: local + [row("history", "L-HISTORY")],
            remote: remote,
            accountIDs: ["R-ENGLISH", "R-MATH"]
        )
        expect(plan["L-HISTORY"] == .push, "手元にしか無い項目は送る")

        // 3. 購読が先に届いてしまい、同じ項目が手元に2行あるとき。
        //    アカウント側のIDを持つ行を残し、もう1行はそこへ畳む。
        plan = AccountMergePlan.decisions(
            local: [row("english", "L-ENGLISH"), row("english", "R-ENGLISH")],
            remote: remote,
            accountIDs: ["R-ENGLISH", "R-MATH"]
        )
        expect(plan["R-ENGLISH"] == .keep, "アカウントと同じIDの行はそのまま")
        expect(plan["L-ENGLISH"] == .absorb(into: "R-ENGLISH"), "手元の重複は残す側へ畳む")

        // 4. 表記ゆれ(全角・大文字小文字・前後の空白)は同じ物として扱う。
        expect(
            AccountMergePlan.nameKey(" Ｅｎｇｌｉｓｈ ") == AccountMergePlan.nameKey("english"),
            "全角・大文字小文字・空白の違いは同一視する"
        )

        // 5. アカウントが空(初めて作るアカウント)なら、手元は全部送る。
        plan = AccountMergePlan.decisions(local: local, remote: [], accountIDs: [])
        expect(plan["L-ENGLISH"] == .push && plan["L-MATH"] == .push, "空のアカウントには全部送る")

        // 6. 既にアカウントが複製されている場合、先に作られた方へ寄せる。
        //    並び順を変えても結論は同じ(どの端末で走っても収束する)。
        let polluted = [
            row("english", "B-ENGLISH", day1),
            row("english", "A-ENGLISH", day0),
            row("math", "A-MATH", day0),
        ]
        let duplicates = AccountMergePlan.duplicates(in: polluted)
        expect(duplicates == ["B-ENGLISH": "A-ENGLISH"], "後から増えた複製だけを取り下げる")
        expect(
            AccountMergePlan.duplicates(in: polluted.reversed()) == duplicates,
            "入力の並びが変わっても同じ結論になる"
        )
        expect(AccountMergePlan.duplicates(in: remote).isEmpty, "複製が無ければ何も取り下げない")

        // 7. 同じ時刻に作られた複製でも、書類IDで一意に決まる。
        let sameInstant = [row("english", "ZZZ", day0), row("english", "AAA", day0)]
        expect(
            AccountMergePlan.duplicates(in: sameInstant) == ["ZZZ": "AAA"],
            "作成時刻が同じなら書類IDの小さい方を残す"
        )

        // 8. 記録の同一性は、時刻(秒)・長さ・ひとこと・繋ぎ先まで一致したときだけ。
        let base = AccountMergePlan.sessionKey(
            date: day0, minutes: 25, extraSeconds: 0, note: "進んだ。", itemUUID: "R-ENGLISH"
        )
        expect(
            base == AccountMergePlan.sessionKey(
                date: day0.addingTimeInterval(0.2), minutes: 25, extraSeconds: 0,
                note: "進んだ。", itemUUID: "r-english"
            ),
            "秒未満のずれと大文字小文字は同じ記録とみなす"
        )
        expect(
            base != AccountMergePlan.sessionKey(
                date: day0, minutes: 26, extraSeconds: 0, note: "進んだ。", itemUUID: "R-ENGLISH"
            ),
            "長さが違えば別の記録"
        )
        expect(
            base != AccountMergePlan.sessionKey(
                date: day0, minutes: 25, extraSeconds: 0, note: "進んだ。", itemUUID: nil
            ),
            "繋ぎ先が違えば別の記録"
        )

        print(failures.isEmpty ? "\nすべて通過" : "\n失敗 \(failures.count) 件")
        exit(failures.isEmpty ? 0 : 1)
    }
}
