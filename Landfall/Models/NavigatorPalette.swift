import SwiftUI
import UIKit

// 航海士の装いの色。帆色と同じく、学習量に関係なくいつでも選べる。
// 既定の熾火(コーラル)はそのままに、原色へ寄らない明るいくすみ色を三つ足す。
// 海は緑(#1E5348)・波紋は淡緑、帆と浜は砂色なので、その二つの色域は避けている。

/// ローブに乗る三色。素体の砂色・夜色・ランタンの灯は装いで変えない。
struct NavigatorPalette {
    /// 袍・肩マント・フードの主色。
    var robe: UIColor
    /// 裾・袖口・靴底・ランタンの金具にまわる縁取り。
    var trim: UIColor
    /// 帯・手・踵を締める最も濃い色。
    var deep: UIColor

    static let `default` = NavigatorPalette(
        robe: UIColor(rgb: 0xF0997B),
        trim: UIColor(rgb: 0x7A3B22),
        deep: UIColor(rgb: 0x4A1B0C)
    )
}

struct NavigatorColorOption: Identifiable {
    let id: String
    let robeHex: UInt
    let trimHex: UInt
    let deepHex: UInt
    let title: LocalizedStringKey
    /// 既定のコーラル以外は航海証(サブスク)で開く。鍵は掛かっていても一覧には並べる。
    var requiresPass = false

    /// 選択チップに出す代表色は主色。
    var swatch: Color { Color(hex: robeHex) }

    var palette: NavigatorPalette {
        NavigatorPalette(
            robe: UIColor(rgb: robeHex),
            trim: UIColor(rgb: trimHex),
            deep: UIColor(rgb: deepHex)
        )
    }
}

enum NavigatorCustomization {
    static let colors: [NavigatorColorOption] = [
        NavigatorColorOption(
            id: "coral", robeHex: 0xF0997B, trimHex: 0x7A3B22, deepHex: 0x4A1B0C,
            title: "Coral"
        ),
        NavigatorColorOption(
            id: "mist", robeHex: 0x8FB8DE, trimHex: 0x2E5570, deepHex: 0x16303F,
            title: "Mist", requiresPass: true
        ),
        NavigatorColorOption(
            id: "iris", robeHex: 0xB3ACE8, trimHex: 0x534AB7, deepHex: 0x1A1130,
            title: "Iris", requiresPass: true
        ),
        NavigatorColorOption(
            id: "honey", robeHex: 0xE5C07A, trimHex: 0x8A6220, deepHex: 0x4A3413,
            title: "Honey", requiresPass: true
        ),
        NavigatorColorOption(
            id: "smoke", robeHex: 0xB5AFA6, trimHex: 0x5E574E, deepHex: 0x322D27,
            title: "Smoke", requiresPass: true
        ),
    ]

    /// 仕草と同じく、この端末に憶えておく(港の相手へは配らない)。
    private static let storageKey = "navigator.color"

    static var selectedID: String {
        let saved = UserDefaults.standard.string(forKey: storageKey)
        return colors.first(where: { $0.id == saved })?.id ?? colors[0].id
    }

    static func select(_ id: String) {
        guard colors.contains(where: { $0.id == id }) else { return }
        UserDefaults.standard.set(id, forKey: storageKey)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    static var selected: NavigatorColorOption {
        colors.first(where: { $0.id == selectedID }) ?? colors[0]
    }

    /// 最後に確かめた航海証の状態。3Dの組み立ては描画スレッドからも走るので、
    /// StoreKit(@MainActor)を直に見ずに、この控えを読む。
    /// 選んだ色は消さない。証が切れているあいだ既定色で描き、戻れば元の色に戻る。
    private static let passKey = "navigator.passActive"

    static var isPassActive: Bool { UserDefaults.standard.bool(forKey: passKey) }

    static func updatePassState(_ active: Bool) {
        UserDefaults.standard.set(active, forKey: passKey)
    }

    static var currentPalette: NavigatorPalette {
        let option = selected
        guard !option.requiresPass || isPassActive else { return .default }
        return option.palette
    }
}
