import SwiftUI

/// カード4「軌跡の一枚絵」。当月の学習をスカイライン状の軌跡で一望する。背景は紙(白)。
struct WrappedCard4Trace: View {
    let month: WrappedMonth

    var body: some View {
        CardScaffold(background: LFColor.paper) {
            VStack(alignment: .leading, spacing: 0) {
                CardKicker(text: "\(month.month)月の軌跡", color: LFColor.ink.opacity(0.55))

                Spacer()

                MonthWaveform(
                    month: month,
                    lineColor: LFColor.ink,
                    gapBarColor: LFColor.coral,
                    resumeMarkerColor: LFColor.returnOrange,
                    gapLabelColor: LFColor.deepRust.opacity(0.85)
                )
                .frame(height: 216)

                Spacer()

                statsRow

                Spacer()
                    .frame(height: 44)

                CardBrandmark(color: LFColor.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 統計(3つ同格、左・中央・右に展開)

    private var statsRow: some View {
        HStack(alignment: .top, spacing: 0) {
            statBlock(label: "累積", value: month.studiedCount, unit: "日", alignment: .leading)
            statBlock(label: "再開", value: month.resumeCount, unit: "回", alignment: .center)
            statBlock(label: "やめた回数", value: month.quitCount, unit: "回", alignment: .trailing)
        }
    }

    private func statBlock(label: String, value: Int, unit: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(label)
                .font(LFFont.label(13))
                .foregroundStyle(LFColor.ink.opacity(0.5))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(verbatim: "\(value)")
                    .font(LFFont.number(30))
                    .foregroundStyle(LFColor.ink)
                Text(unit)
                    .font(LFFont.copy(14))
                    .foregroundStyle(LFColor.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment(alignment))
    }

    private func frameAlignment(_ alignment: HorizontalAlignment) -> Alignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }
}

#Preview {
    WrappedCard4Trace(month: .dummy)
}
