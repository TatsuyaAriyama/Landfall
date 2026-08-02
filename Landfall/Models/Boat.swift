import Foundation
import SwiftUI
import UIKit

// 船の編集は帆色だけ。WebのSAIL_COLORSと同じ6色を、学習時間に関係なく選べる。
// メインセイルと前帆は同色にし、船体・ライン・旗はAftideの標準船へ固定する。

struct SailColorOption: Identifiable {
    let id: String
    let hex: UInt
    let title: LocalizedStringKey

    var color: Color { Color(hex: hex) }
    var uiColor: UIColor { UIColor(rgb: hex) }
}

// MARK: - 3Dの船に渡す見た目一式

struct BoatParts {
    var sail: UIColor
    var jib: UIColor
    var hull: UIColor
    var stripe: UIColor?
    var flag: String

    static let `default` = BoatParts(
        sail: UIColor(rgb: 0xEADEBD),
        jib: UIColor(rgb: 0xEADEBD),
        hull: UIColor(rgb: 0xEADEBD),
        stripe: nil,
        flag: "none"
    )
}

enum BoatCustomization {
    static let sailColors: [SailColorOption] = [
        SailColorOption(id: "sand", hex: 0xEADEBD, title: "Sand"),
        SailColorOption(id: "coral", hex: 0xF0997B, title: "Coral"),
        SailColorOption(id: "sunYellow", hex: 0xF3C065, title: "Sunlight"),
        SailColorOption(id: "seaGreen", hex: 0x5DCAA5, title: "Sea green"),
        SailColorOption(id: "lavender", hex: 0xCECBF6, title: "Twilight"),
        SailColorOption(id: "horizonBlue", hex: 0x7FA8B8, title: "Horizon"),
    ]

    private static let sailStorageKey = "boat.sail"

    static var selectedSailID: String {
        let saved = UserDefaults.standard.string(forKey: sailStorageKey)
        return sailColors.first(where: { $0.id == saved })?.id ?? sailColors[0].id
    }

    static func selectSail(_ id: String) {
        guard sailColors.contains(where: { $0.id == id }) else { return }
        UserDefaults.standard.set(id, forKey: sailStorageKey)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: sailStorageKey)
    }

    static var selectedSail: SailColorOption {
        sailColors.first(where: { $0.id == selectedSailID }) ?? sailColors[0]
    }

    /// 選択色は両方の帆へ適用し、廃止した部位は常に標準値にする。
    static var currentParts: BoatParts {
        let sail = selectedSail.uiColor
        return BoatParts(
            sail: sail,
            jib: sail,
            hull: BoatParts.default.hull,
            stripe: nil,
            flag: "none"
        )
    }

    // 旧クライアントとFirestoreルールとの互換性のため5フィールドは維持する。
    static var shareData: [String: String] {
        let sail = selectedSailID
        return [
            "boatSail": sail,
            "boatJib": sail,
            "boatHull": "sand",
            "boatStripe": "none",
            "boatFlag": "none",
        ]
    }

    /// 港の旧データに個別部位が残っていても、帆色以外は標準船として表示する。
    static func parts(fromIDs ids: [String: String?]) -> BoatParts {
        let sailID = ids["boatSail"] ?? nil
        let sail = sailColors.first(where: { $0.id == sailID })?.uiColor
            ?? BoatParts.default.sail
        return BoatParts(
            sail: sail,
            jib: sail,
            hull: BoatParts.default.hull,
            stripe: nil,
            flag: "none"
        )
    }
}
