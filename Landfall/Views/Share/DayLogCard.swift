import SwiftUI

/// 共有カードの配色。すべて固定色(明暗に追従しない)なので、
/// 端末の外観設定に関わらず書き出した絵柄が変わらない。
enum DayCardTheme: String, CaseIterable, Identifiable {
    case paper
    case ink
    case harbor

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .paper: "Paper"
        case .ink: "Ink"
        case .harbor: "Sea"
        }
    }

    var background: Color {
        switch self {
        case .paper: .white
        case .ink: LFColor.inkFixed
        case .harbor: LFColor.harborTeal
        }
    }

    /// 主文字色。
    var primary: Color {
        switch self {
        case .paper: LFColor.inkFixed
        case .ink: .white
        case .harbor: LFColor.harborSand
        }
    }

    /// 数字・強調に置く色。
    var accent: Color {
        switch self {
        case .paper: LFColor.returnOrange
        case .ink: LFColor.sunYellow
        case .harbor: LFColor.sunYellow
        }
    }

    /// 罫線の色。
    var hairline: Color { primary.opacity(0.15) }

    /// 白背景のSNSに貼っても輪郭が消えないよう、明るい配色にだけ縁を付ける。
    var border: Color {
        switch self {
        case .paper: LFColor.inkFixed.opacity(0.12)
        case .ink, .harbor: .clear
        }
    }
}

/// その日の記録を1枚に畳んだ共有カード。
/// 幅は固定・高さは中身で伸びる(その日の記録を省略せずに載せるため)。
/// 固定寸法の絵はがきと同じく、文字サイズ設定と外観設定の影響を受けない。
struct DayLogCard: View {
    let log: DayLog
    var theme: DayCardTheme = .paper

    /// ひとことが多すぎる日でも画像が肥大しないよう、ここまでを載せる。
    private let noteLimit = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 日付
            Text(verbatim: LF.dayWithWeekday(log.date))
                .font(LFFont.labelFixed(15))
                .tracking(2)
                .foregroundStyle(theme.primary.opacity(0.55))

            if log.isRestDay {
                restBody
            } else {
                workBody
            }

            // 記録の量ぶんだけ伸びる。少ない日に空洞を作らないよう最小高は低く抑える。
            Spacer(minLength: 32)

            Text(verbatim: "Landfall-StudyLog")
                .font(LFFont.labelFixed(13))
                .foregroundStyle(theme.primary.opacity(0.4))
        }
        .padding(LFMetrics.cardPadding)
        .frame(width: LFMetrics.cardSize.width, alignment: .topLeading)
        .frame(minHeight: 360, alignment: .topLeading)
        .background(theme.background)
        .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
        // 絵はがきなので、端末の文字サイズ・外観に関わらず一定に描く。
        .environment(\.lfFixedType, true)
        .environment(\.colorScheme, .light)
    }

    // MARK: - 記録のある日

    private var workBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 合計時間を主役に置く。
            Text(verbatim: LF.duration(minutes: log.totalMinutes))
                .font(LFFont.numberFixed(46))
                .foregroundStyle(theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, 18)

            Text("\(log.sessionCount) sessions · \(log.itemCount) items")
                .font(LFFont.labelFixed(14))
                .foregroundStyle(theme.primary.opacity(0.5))
                .padding(.top, 4)

            rule.padding(.top, 24)

            // 項目ごとの内訳(長い順)。
            VStack(spacing: 0) {
                ForEach(Array(log.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { rule }
                    entryRow(entry)
                }
            }

            if !log.notes.isEmpty {
                rule
                notesSection.padding(.top, 20)
            }
        }
    }

    private func entryRow(_ entry: DayLog.Entry) -> some View {
        HStack(spacing: 14) {
            TokenTile(
                styleToken: entry.styleToken,
                symbolToken: entry.symbolToken,
                photoData: entry.photoData
            )
            .frame(width: 38, height: 38)

            Text(verbatim: entry.name)
                .font(LFFont.copyFixed(17))
                .foregroundStyle(theme.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(verbatim: LF.duration(minutes: entry.minutes))
                .font(LFFont.numberFixed(16))
                .foregroundStyle(theme.primary.opacity(0.65))
        }
        .padding(.vertical, 13)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(log.notes.prefix(noteLimit).enumerated()), id: \.offset) { _, note in
                HStack(alignment: .top, spacing: 10) {
                    // 引用の目印。装飾ではなく行頭の細い罫。
                    Rectangle()
                        .fill(theme.accent)
                        .frame(width: 2)
                    Text(verbatim: note)
                        .font(LFFont.copyFixed(15))
                        .foregroundStyle(theme.primary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if log.notes.count > noteLimit {
                Text("and \(log.notes.count - noteLimit) more.")
                    .font(LFFont.labelFixed(13))
                    .foregroundStyle(theme.primary.opacity(0.45))
            }
        }
    }

    // MARK: - 休んだ日

    /// 休んだ日も同じ体裁で1枚になる。学んだ日と同格に扱う。
    private var restBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Rested.")
                .font(LFFont.copyFixed(34))
                .foregroundStyle(LFColor.seaGreen)
                .padding(.top, 20)

            Text("A day at harbor is part of the voyage.")
                .font(LFFont.copyFixed(16))
                .foregroundStyle(theme.primary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(theme.hairline)
            .frame(height: 1)
    }
}

/// 項目のトークンだけでタイルを描く(SwiftDataのオブジェクトに依存しない)。
private struct TokenTile: View {
    let styleToken: String
    let symbolToken: String
    let photoData: Data?

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                if let photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: s, height: s)
                } else {
                    let style = TileStyle.from(styleToken)
                    style.background
                    TileSymbolView(
                        symbol: TileSymbol.from(symbolToken),
                        fg: style.foreground,
                        bg: style.background
                    )
                    .frame(width: s * 0.62, height: s * 0.62)
                }
            }
            .frame(width: s, height: s)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
