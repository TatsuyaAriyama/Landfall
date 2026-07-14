import SwiftUI

/// カード1「事実」。
/// 学んだ日数と休んだ日数を完全に同格に並べ、
/// 「一度もやめなかった」という事実で締める。
struct WrappedCard1Fact: View {
    let month: WrappedMonth

    var body: some View {
        CardScaffold(background: LFColor.ink) {
            VStack(alignment: .leading, spacing: 0) {
                CardKicker(text: "\(String(month.year))年\(month.month)月のあなた", color: .white)

                Spacer()

                VStack(alignment: .leading, spacing: 44) {
                    FactRow(count: month.studiedCount, verb: "学んだ", accent: LFColor.sunYellow)
                    FactRow(count: month.restedCount, verb: "休んだ", accent: LFColor.seaGreen)
                }

                Spacer()

                // month.quitCount は定義上 0。その事実の宣言。
                if month.quitCount == 0 {
                    Text("そして、一度もやめなかった。")
                        .font(LFFont.copy(20))
                        .foregroundStyle(Color.white)
                }

                Spacer()
                    .frame(height: 44)

                CardBrandmark(color: .white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 学んだ/休んだの1行。両者で完全に同一のレイアウトを使う。
private struct FactRow: View {
    let count: Int
    let verb: String
    let accent: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(count)")
                .font(LFFont.number(64))
                .foregroundStyle(accent)
            Text("日")
                .font(LFFont.copy(22))
                .foregroundStyle(accent)
            Text(verb)
                .font(LFFont.copy(22))
                .foregroundStyle(Color.white)
        }
    }
}

#Preview {
    WrappedCard1Fact(month: .dummy)
}
