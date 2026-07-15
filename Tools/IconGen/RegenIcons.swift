import SwiftUI

// アプリの AppIconArt(単一ソース)から各アイコンPNGを再生成する確認用CLI。
// アプリ本体には含まれない(Tools配下)。
@main
@MainActor
struct RegenIcons {
    static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
        for option in AppIconOption.allCases {
            renderCard(
                AppIconArt(option: option).frame(width: 1024, height: 1024),
                name: "appicon-\(option.rawValue)",
                outDir: out,
                scale: 1
            )
        }
    }
}
