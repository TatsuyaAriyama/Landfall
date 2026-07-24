import SwiftUI
import UIKit

/// タブバー用アイコン。Web と同じ航海シンボル(TileSymbol)を、単色のテンプレート画像に
/// 焼いて使う。テンプレートなので選択色(returnOrange)/非選択色はタブバーが着色する。
/// SF シンボルではなく Web と同一の図案にするための橋渡し。
enum TabSymbolIcon {
    @MainActor private static var cache: [TileSymbol: Image] = [:]

    @MainActor static func image(_ symbol: TileSymbol) -> Image {
        if let cached = cache[symbol] { return cached }
        let renderer = ImageRenderer(content:
            TileSymbolView(symbol: symbol, fg: .black, bg: .clear)
                .frame(width: 60, height: 60)
                .padding(4)
        )
        renderer.scale = 3
        let image: Image
        if let ui = renderer.uiImage?.withRenderingMode(.alwaysTemplate) {
            image = Image(uiImage: ui)
        } else {
            image = Image(systemName: "circle")
        }
        cache[symbol] = image
        return image
    }
}
