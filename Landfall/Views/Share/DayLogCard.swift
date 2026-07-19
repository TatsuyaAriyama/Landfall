import SwiftUI

/// 共有カードの配色。港の一日の時間帯として選ぶ。
/// すべて固定色(明暗に追従しない)なので、端末の外観設定に関わらず書き出した絵柄が変わらない。
enum DayCardTheme: String, CaseIterable, Identifiable {
    /// 昼の海。ティールの海に砂色の帆(サインイン画面と同じ情景)。
    case harbor
    /// 夜の海。ミッドナイトの海にラベンダーの空気。
    case ink
    /// 朝の海。白い靄の海にティールの帆。
    case paper

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .harbor: "Sea"
        case .ink: "Night"
        case .paper: "Morning"
        }
    }

    /// 海(カード上部)の色。
    var sea: Color {
        switch self {
        case .harbor: LFColor.harborTeal
        case .ink: LFColor.midnight
        case .paper: .white
        }
    }

    /// 海の上に置く文字の色。
    var seaText: Color {
        switch self {
        case .harbor: LFColor.harborSand
        case .ink: LFColor.lavender
        case .paper: LFColor.harborTeal
        }
    }

    /// 合計時間(主役)の色。
    var hero: Color {
        switch self {
        case .harbor, .ink: LFColor.sunYellow
        case .paper: LFColor.returnOrange
        }
    }

    /// 帆船の色。
    var boat: Color {
        switch self {
        case .harbor, .ink: LFColor.harborSand
        case .paper: LFColor.harborTeal
        }
    }

    /// 陸(カード下部)。どの時間帯でも砂浜は同じ色。
    var land: Color { LFColor.harborSand }

    /// 陸の上に置く文字の色。ティール×砂は港の基本の組み合わせ。
    var landInk: Color { LFColor.harborTeal }

    /// 白背景のSNSに貼っても輪郭が消えないよう、朝(白い海)にだけ縁を付ける。
    var border: Color {
        switch self {
        case .paper: LFColor.inkFixed.opacity(0.12)
        case .harbor, .ink: .clear
        }
    }
}

/// その日の記録を、港の情景に載せた絵はがき。
/// 構図: 海(日付と時間が浮かぶ)→ 帆船が海岸へ着く情景 → 陸(記録が荷降ろしされている)。
/// 「着岸したから、記録が陸にある」という一枚。
/// 固定寸法の絵はがきなので、文字サイズ・外観設定の影響を受けない。
struct DayLogCard: View {
    let log: DayLog
    var theme: DayCardTheme = .harbor

    /// 情景の帯の高さ。下端が汀(みぎわ)=陸との境界。
    private let sceneHeight: CGFloat = 116

    var body: some View {
        VStack(spacing: 0) {
            seaSection
            scene
            landSection
        }
        .frame(width: LFMetrics.cardSize.width)
        .background(
            // 海と陸を継ぎ目なく塗り分ける(情景の帯は海の続き)。
            VStack(spacing: 0) {
                theme.sea
                theme.land.frame(height: 8)   // 端数対策。陸側は landSection が塗る。
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
        // 絵はがきなので、端末の文字サイズ・外観に関わらず一定に描く。
        .environment(\.lfFixedType, true)
        .environment(\.colorScheme, .light)
        // 日付・単位(LF/heroTime)はアプリ内の言語設定に従うので、翻訳文もそこに揃える。
        // これが無いと、端末言語とアプリ内言語が違うときにカード内で言語が混ざる。
        .environment(\.locale, AppLanguage.current.locale)
    }

    // MARK: - 海(日付・合計時間)

    private var seaSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: LF.dayWithWeekday(log.date))
                .font(LFFont.labelFixed(14))
                .tracking(2)
                .foregroundStyle(theme.seaText.opacity(0.65))

            if log.isRestDay {
                Text("Rested.")
                    .font(LFFont.copyFixed(34))
                    .foregroundStyle(LFColor.seaGreen)
                    .padding(.top, 16)
                Text("A day at harbor is part of the voyage.")
                    .font(LFFont.copyFixed(15))
                    .foregroundStyle(theme.seaText.opacity(0.7))
                    .padding(.top, 8)
            } else {
                heroTime
                    .padding(.top, 16)
                // 空きが空いた日にだけ、戻ってきたことを言葉にする。
                // 普段の日は何も足さない(日付と時間だけの静かな面を保つ)。
                if let gap = log.daysSinceLastVoyage, gap >= 2 {
                    Text("First sail in \(gap) days.")
                        .font(LFFont.copyFixed(16))
                        .foregroundStyle(LFColor.sunYellow.opacity(0.9))
                        .padding(.top, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LFMetrics.cardPadding)
        .padding(.top, 34)
        .padding(.bottom, 6)
        .background(theme.sea)
    }

    /// 合計時間。数字を大きく・単位を小さく置く(全部同じ大きさで並べると野暮ったい)。
    /// 数字は主役色、単位は海の文字色で一歩引かせる。
    private var heroTime: some View {
        let hours = log.totalMinutes / 60
        let minutes = log.totalMinutes % 60
        let isJa = AppLanguage.current.locale.identifier.hasPrefix("ja")
        let hourUnit = isJa ? "時間" : "h"
        let minuteUnit = isJa ? "分" : "m"
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            if hours > 0 {
                Text(verbatim: "\(hours)")
                    .font(LFFont.numberFixed(60))
                    .foregroundStyle(theme.hero)
                Text(verbatim: hourUnit)
                    .font(LFFont.copyFixed(18))
                    .foregroundStyle(theme.seaText.opacity(0.85))
                    .padding(.trailing, hours > 0 && minutes > 0 ? 8 : 0)
            }
            if minutes > 0 || hours == 0 {
                Text(verbatim: "\(minutes)")
                    .font(LFFont.numberFixed(60))
                    .foregroundStyle(theme.hero)
                Text(verbatim: minuteUnit)
                    .font(LFFont.copyFixed(18))
                    .foregroundStyle(theme.seaText.opacity(0.85))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    // MARK: - 情景(帆船と海岸)

    /// 凪いだ海を渡ってきた帆船が、右手の海岸に着こうとしている。
    /// 休んだ日は、船は岸のそばに停泊している。
    private var scene: some View {
        ZStack {
            theme.sea

            // 凪の水面。サインイン画面と同じ言葉づかい。
            waterLine(width: 150, height: 6, opacity: 0.30)
                .position(x: 150, y: sceneHeight - 20)
            waterLine(width: 84, height: 5, opacity: 0.18)
                .position(x: 96, y: sceneHeight - 9)

            // 迎える海岸(右手)。裾は右端へ断ち落とす。
            CoastShape()
                .fill(theme.land)
                .frame(width: 216, height: 74)
                .position(x: 322, y: sceneHeight - 37)

            // 帆船。休んだ日は岸のそば(重ならない手前)で停泊、それ以外は海の上。
            BoatShape()
                .fill(theme.boat)
                .frame(width: 46, height: 85)
                .position(x: log.isRestDay ? 178 : 128, y: sceneHeight - 52)
        }
        .frame(width: LFMetrics.cardSize.width, height: sceneHeight)
        .clipped()
    }

    private func waterLine(width: CGFloat, height: CGFloat, opacity: Double) -> some View {
        Capsule(style: .continuous)
            .fill(theme.seaText.opacity(opacity))
            .frame(width: width, height: height)
    }

    // MARK: - 陸(荷降ろしされた記録)

    private var landSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !log.entries.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(log.entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Rectangle()
                                .fill(theme.landInk.opacity(0.12))
                                .frame(height: 1)
                        }
                        entryRow(entry)
                    }
                }
                .padding(.top, 10)
            }

            // その日について書いた一行だけを載せる(記録ごとのメモは載せない)。
            if let comment = log.comment, !comment.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(LFColor.returnOrange)
                        .frame(width: 3)
                    Text(verbatim: comment)
                        .font(LFFont.copyFixed(16))
                        .foregroundStyle(theme.landInk.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, log.entries.isEmpty ? 24 : 20)
            }

            Text(verbatim: "Landfall-StudyLog")
                .font(LFFont.labelFixed(12))
                .foregroundStyle(theme.landInk.opacity(0.5))
                .padding(.top, log.isRestDay && log.comment == nil ? 22 : 26)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, LFMetrics.cardPadding)
        .padding(.bottom, 24)
        .background(theme.land)
    }

    private func entryRow(_ entry: DayLog.Entry) -> some View {
        HStack(spacing: 13) {
            TokenTile(
                styleToken: entry.styleToken,
                symbolToken: entry.symbolToken,
                photoData: entry.photoData
            )
            .frame(width: 36, height: 36)

            Text(verbatim: entry.name)
                .font(LFFont.copyFixed(16))
                .foregroundStyle(theme.landInk)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(verbatim: LF.duration(minutes: entry.minutes))
                .font(LFFont.numberFixed(15))
                .foregroundStyle(theme.landInk.opacity(0.7))
        }
        .padding(.vertical, 12)
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
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview("学んだ日") {
    DayLogCard(
        log: DayLog(
            date: .now,
            entries: [
                .init(id: "1", name: "開発", styleToken: "midnight", symbolToken: "phoenix", photoData: nil, minutes: 95),
                .init(id: "2", name: "読書", styleToken: "coral", symbolToken: "book", photoData: nil, minutes: 40),
            ],
            notes: [],
            comment: "久しぶりに読書に没頭できた。",
            totalMinutes: 135,
            sessionCount: 2,
            daysSinceLastVoyage: 6
        ),
        theme: .harbor
    )
}

#Preview("休んだ日") {
    DayLogCard(
        log: DayLog(date: .now, entries: [], notes: [], comment: nil, totalMinutes: 0, sessionCount: 0, daysSinceLastVoyage: nil),
        theme: .harbor
    )
}
