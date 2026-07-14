import SwiftUI

/// Wrappedカード2「空白の物語」。
/// いちばん長い空白の長さと期間を大きく示し、それでも戻ってきた事実で締める。
struct WrappedCard2Silence: View {
    let month: WrappedMonth

    var body: some View {
        CardScaffold(background: LFColor.coral) {
            VStack(alignment: .leading, spacing: 0) {
                CardKicker(text: "いちばん長い空白", color: LFColor.deepRust)

                if let gap = month.longestGap {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(gap.length)")
                            .font(LFFont.number(80))
                        Text("日")
                            .font(LFFont.copy(24))
                    }
                    .foregroundStyle(LFColor.deepRust)
                    .padding(.top, 16)

                    Spacer()

                    Text("\(month.shortDate(gap.startDay))〜\(month.shortDate(gap.endDay))、あなたは沈黙した。")
                        .font(LFFont.copy(19))
                        .foregroundStyle(LFColor.deepRust)

                    Spacer()

                    ReturnBox(
                        returnLine: "それでも \(month.shortDate(gap.endDay + 1))、戻ってきた。",
                        countLine: "この月、帰還は\(month.resumeCount)回。"
                    )
                } else {
                    Text("この月、空白はなかった。")
                        .font(LFFont.copy(19))
                        .foregroundStyle(LFColor.deepRust)
                        .padding(.top, 16)

                    Spacer()
                }

                Spacer()
                    .frame(height: 44)

                CardBrandmark(color: LFColor.deepRust)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 濃色の帰還ボックス。空白の物語を反転色で締める。
private struct ReturnBox: View {
    var returnLine: String
    var countLine: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(returnLine)
                .font(LFFont.copy(19))
                .foregroundStyle(LFColor.coral)
            Text(countLine)
                .font(LFFont.label(15))
                .foregroundStyle(LFColor.coral)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(LFColor.deepRust)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    WrappedCard2Silence(month: .dummy)
}
