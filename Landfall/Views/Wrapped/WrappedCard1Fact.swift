import SwiftUI

/// カード1「事実」。
/// 学んだ日数と休んだ日数を完全に同格に並べ、
/// 「休んでも、あなたはここにいる」と締める(休む=やめる ではない)。
struct WrappedCard1Fact: View {
    let month: WrappedMonth

    var body: some View {
        CardScaffold(background: LFColor.ink) {
            VStack(alignment: .leading, spacing: 0) {
                CardKicker(text: "You, \(LF.monthYear(year: month.year, month: month.month))", color: .white)

                Spacer()

                VStack(alignment: .leading, spacing: 44) {
                    FactRow(count: month.studiedCount, verb: "studied", accent: LFColor.sunYellow)
                    FactRow(count: month.restedCount, verb: "rested", accent: LFColor.seaGreen)
                }

                // 合計学習時間。判定には使わず、事実として小さく添えるだけ。
                HStack(spacing: 8) {
                    Text("Total")
                        .foregroundStyle(Color.white.opacity(0.4))
                    Text(verbatim: LF.duration(minutes: month.totalMinutes))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .monospacedDigit()
                }
                .font(LFFont.labelFixed(14))
                .padding(.top, 22)

                Spacer()

                // その月の形に合わせた締め(日数ベースで判定)。
                Text(closingLine)
                    .font(LFFont.copyFixed(20))
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
                    .frame(height: 44)

                CardBrandmark(color: .white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// その月の物語に応じた締めの一行。休む=やめる ではない、という思想は全パターンで保つ。
    private var closingLine: LocalizedStringKey {
        switch month.narrative {
        case .perfect:     "You were out at sea all month."
        case .nearPerfect: "You sailed almost every day."
        case .fewSparks:   "You set sail, even once. That's enough."
        case .longReturn:  "Away for a long stretch — and back again."
        case .manyReturns: "You drifted off many times, and returned each time."
        case .balanced:    "Days of study, days of rest — both were this month."
        case .steady:      "Even after resting, you're still here."
        }
    }
}

/// 学んだ/休んだの1行。両者で完全に同一のレイアウトを使う。
private struct FactRow: View {
    let count: Int
    let verb: LocalizedStringKey
    let accent: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(count)")
                .font(LFFont.numberFixed(64))
                .foregroundStyle(accent)
            Text("days")
                .font(LFFont.copyFixed(22))
                .foregroundStyle(accent)
            Text(verb)
                .font(LFFont.copyFixed(22))
                .foregroundStyle(Color.white)
        }
    }
}

#Preview {
    WrappedCard1Fact(month: .dummy)
}
