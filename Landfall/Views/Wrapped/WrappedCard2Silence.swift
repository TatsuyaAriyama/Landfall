import SwiftUI

/// Wrappedカード2「空白の物語」。
/// いちばん長い空白の長さと期間を大きく示し、港で休み、また海へ出た事実で締める。
struct WrappedCard2Silence: View {
    let month: WrappedMonth

    var body: some View {
        CardScaffold(background: LFColor.coral) {
            VStack(alignment: .leading, spacing: 0) {
                CardKicker(text: "Your longest gap", color: LFColor.deepRust)

                if let gap = month.longestGap {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(gap.length)")
                            .font(LFFont.numberFixed(80))
                        Text("days")
                            .font(LFFont.copyFixed(24))
                    }
                    .foregroundStyle(LFColor.deepRust)
                    .padding(.top, 16)

                    Spacer()

                    Text("\(month.shortDate(gap.startDay))–\(month.shortDate(gap.endDay)), you rested at harbor.")
                        .font(LFFont.copyFixed(19))
                        .foregroundStyle(LFColor.deepRust)

                    Spacer()

                    ReturnBox(
                        returnLine: "And on \(month.shortDate(gap.endDay + 1)), you set sail again.",
                        countLine: "\(month.resumeCount) returns this month."
                    )
                } else {
                    Text("No gap this month.")
                        .font(LFFont.copyFixed(19))
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
    var returnLine: LocalizedStringKey
    var countLine: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(returnLine)
                .font(LFFont.copyFixed(19))
                .foregroundStyle(LFColor.coral)
            Text(countLine)
                .font(LFFont.labelFixed(15))
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
