#if DEBUG
import SwiftUI

/// 動作確認用: 共有物のPNGを Documents に書き出す。
/// サインインや特定の画面到達を経ずに、絵柄だけを確認するための出口。
/// - LANDFALL_PASS_DUMP=1 で入港証(LANDFALL_SITE を併せて渡すとQR入り)。
/// - LANDFALL_REST_DUMP=1 で休んだ日のカード(通常の導線からは開けないため)。
/// - LANDFALL_DAY_DUMP=1 で記録のある日のSNS共有カード3配色。
enum DebugCardDump {
    @MainActor
    static func runIfRequested() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let isJapanese = AppLanguage.current.locale.identifier.hasPrefix("ja")

        if ProcessInfo.processInfo.environment["LANDFALL_PASS_DUMP"] == "1" {
            let card = InvitePassCard(
                roomName: isJapanese ? "夜の自習室" : "Night Study Room",
                code: "K7M2QP"
            )
            if let image = WrappedShare.render(card: card, fileName: "pass.png") {
                try? image.data.write(to: dir.appendingPathComponent("pass.png"))
            }
        }

        if ProcessInfo.processInfo.environment["LANDFALL_REST_DUMP"] == "1" {
            let rest = DayLog(
                date: Date(), entries: [], notes: [], comment: nil,
                totalMinutes: 0, sessionCount: 0, daysSinceLastVoyage: nil
            )
            for theme in DayCardTheme.allCases {
                let card = DayLogCard(log: rest, theme: theme)
                if let image = WrappedShare.render(card: card, fileName: "rest.png") {
                    try? image.data.write(to: dir.appendingPathComponent("rest-\(theme.rawValue).png"))
                }
            }
        }

        if ProcessInfo.processInfo.environment["LANDFALL_DAY_DUMP"] == "1" {
            let log = DayLog(
                date: Date(),
                entries: [
                    .init(
                        id: "debug-focus", name: isJapanese ? "プロダクト設計" : "Product design",
                        styleToken: "midnight", symbolToken: "phoenix", minutes: 95
                    ),
                    .init(
                        id: "debug-book", name: isJapanese ? "読書" : "Reading",
                        styleToken: "coral", symbolToken: "book", minutes: 40
                    ),
                    .init(
                        id: "debug-review", name: isJapanese ? "振り返り" : "Review",
                        styleToken: "seaGreen", symbolToken: "spark", minutes: 25
                    ),
                ],
                notes: [],
                comment: isJapanese ? "今日も、目指す島へ少し近づいた。" : "A little closer to the island today.",
                totalMinutes: 160,
                sessionCount: 3,
                daysSinceLastVoyage: 3
            )
            for theme in DayCardTheme.allCases {
                let card = DayLogCard(log: log, theme: theme)
                if let image = WrappedShare.render(card: card, fileName: "share.png") {
                    try? image.data.write(to: dir.appendingPathComponent("share-\(theme.rawValue).png"))
                }
            }
        }
    }
}
#endif
