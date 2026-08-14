import SwiftUI
import UIKit

/// 公開誌の日付は、一日一頁の判定と同じ日本時間で表示する。
enum PublicJournalDayDisplay {
    static func fullDate(for dayID: String) -> String {
        guard let date = PublicJournalService.date(from: dayID) else { return dayID }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = AppLanguage.current.locale
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.setLocalizedDateFormatFromTemplate("yMMMMd")
        return formatter.string(from: date)
    }
}

/// 公開誌の基本紙面。写真に文字を重ねず、景色と文章がそれぞれ呼吸できる二段構成にする。
struct PublicJournalPageCard: View {
    let entry: PublicJournalEntry

    private var ink: Color { LFColor.inkFixed }

    var body: some View {
        VStack(spacing: 0) {
            authorRow
                .padding(.horizontal, 20)
                .padding(.vertical, 17)

            PublicJournalPhoto(data: entry.imageData)
                .aspectRatio(4 / 3, contentMode: .fit)

            VStack(alignment: .leading, spacing: 18) {
                PublicJournalTideRule()

                Text(verbatim: entry.body)
                    .font(LFFont.copy(17))
                    .foregroundStyle(ink)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .lastTextBaseline) {
                    CardBrandmark(color: ink)
                    Spacer()
                    Text("One page per tide")
                        .font(LFFont.label(11))
                        .tracking(1.1)
                        .foregroundStyle(ink.opacity(0.68))
                }
            }
            .padding(20)
        }
        .background(Color(hex: 0xFCFAF5))
        .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous)
                .stroke(ink.opacity(0.12), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    private var authorRow: some View {
        HStack(spacing: 12) {
            PlayerAvatarArt(styleToken: entry.styleToken, symbolToken: entry.symbolToken)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: entry.displayName)
                    .font(LFFont.copy(16))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(verbatim: displayedDate)
                    Text(verbatim: "·")
                    if let harbor = PublicHarbor.by(slug: entry.harborSlug) {
                        Text(harbor.title)
                    }
                }
                .font(LFFont.label(12))
                .foregroundStyle(ink.opacity(0.68))
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("PUBLIC")
                Text("LOGBOOK")
            }
            .font(LFFont.label(9))
            .tracking(1.4)
            .foregroundStyle(LFColor.deepRust)
            .accessibilityHidden(true)
        }
    }

    private var displayedDate: String {
        PublicJournalDayDisplay.fullDate(for: entry.dayID)
    }

    private var accessibilitySummary: String {
        LF.format(
            "%@, %@, photo attached. %@",
            entry.displayName,
            displayedDate,
            entry.body
        )
    }
}

struct PublicJournalPhoto: View {
    let data: Data

    var body: some View {
        Group {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(hex: 0xE8E2D7)
                    Image(systemName: "photo")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(LFColor.inkFixed.opacity(0.28))
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

struct PublicJournalTideRule: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(LFColor.returnOrange)
                .frame(width: 42, height: 2)
            Rectangle()
                .fill(LFColor.inkFixed.opacity(0.12))
                .frame(height: 1)
            Image(systemName: "anchor")
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(LFColor.inkFixed.opacity(0.35))
        }
        .accessibilityHidden(true)
    }
}

/// SNSへ書き出す固定寸法の一頁。フィード用Dynamic Typeとは分離して崩れを防ぐ。
struct PublicJournalShareCard: View {
    let entry: PublicJournalEntry

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                PublicJournalPhoto(data: entry.imageData)
                    .frame(width: LFMetrics.cardSize.width, height: 310)

                Text(verbatim: shareDate)
                    .font(LFFont.numberFixed(14))
                    .foregroundStyle(LFColor.inkFixed)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(Color(hex: 0xFCFAF5))
                    .padding(22)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    PlayerAvatarArt(styleToken: entry.styleToken, symbolToken: entry.symbolToken)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: entry.displayName)
                            .font(LFFont.copyFixed(14))
                            .foregroundStyle(LFColor.inkFixed)
                            .lineLimit(1)
                        Text("PUBLIC LOGBOOK")
                            .font(LFFont.labelFixed(9))
                            .tracking(1.3)
                            .foregroundStyle(LFColor.deepRust)
                    }
                    Spacer()
                    if let harbor = PublicHarbor.by(slug: entry.harborSlug) {
                        Text(harbor.title)
                            .font(LFFont.labelFixed(10))
                            .foregroundStyle(LFColor.inkFixed.opacity(0.68))
                    }
                }

                PublicJournalTideRule()

                Text(verbatim: entry.body)
                    .font(LFFont.copyFixed(entry.body.count > 180 ? 13 : 16))
                    .foregroundStyle(LFColor.inkFixed)
                    .lineSpacing(entry.body.count > 180 ? 2 : 5)
                    .lineLimit(entry.body.count > 180 ? 13 : 11)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)

                HStack(alignment: .lastTextBaseline) {
                    CardBrandmark(color: LFColor.inkFixed)
                    Spacer()
                    Text("ONE PAGE PER TIDE")
                        .font(LFFont.labelFixed(9))
                        .tracking(1.2)
                        .foregroundStyle(LFColor.inkFixed.opacity(0.68))
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
        .frame(width: LFMetrics.cardSize.width, height: LFMetrics.cardSize.height)
        .background(Color(hex: 0xFCFAF5))
        .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
        .environment(\.lfFixedType, true)
        .environment(\.colorScheme, .light)
        .environment(\.locale, AppLanguage.current.locale)
    }

    private var shareDate: String {
        PublicJournalDayDisplay.fullDate(for: entry.dayID)
    }
}

@MainActor
enum PublicJournalShareRenderer {
    static func render(_ entry: PublicJournalEntry) -> WrappedCardImage? {
        WrappedShare.render(
            card: PublicJournalShareCard(entry: entry),
            fileName: "KeelMira-public-logbook-\(entry.dayID).png"
        )
    }
}
