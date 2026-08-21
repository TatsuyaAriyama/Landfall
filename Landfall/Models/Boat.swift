import Foundation
import SwiftUI
import UIKit

// 船の編集は「船体」と「帆色」の二つ。帆色は6色を学習時間に関係なく選べる。
// 船体はレベルで開く — 積み上げた時間だけが新しい船をもたらす。
// メインセイルと前帆は同色にし、ライン・旗は各船の造形へ委ねる。

struct SailColorOption: Identifiable {
    let id: String
    let hex: UInt
    let title: LocalizedStringKey

    var color: Color { Color(hex: hex) }
    var uiColor: UIColor { UIColor(rgb: hex) }
}

// MARK: - 進水できる船

/// 航海で実際に乗る船。造形はUSDZごと差し替わるが、帆だけは
/// `LF_BoatMainSail` / `LF_BoatJib` の名前で共通なので、どの船でも
/// 同じ6色から選べる。
struct ShipDesign: Identifiable, Hashable {
    let id: String
    /// バンドル内のUSDZ名。船を足すときはここと `ShipCatalog.all` だけを触る。
    let resourceName: String
    let title: LocalizedStringKey
    let summary: LocalizedStringKey
    let symbolName: String
    /// この船が開くレベル。1は最初から乗っている船。
    let unlockLevel: Int

    static func == (lhs: ShipDesign, rhs: ShipDesign) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum ShipCatalog {
    static let all: [ShipDesign] = [
        ShipDesign(
            id: "landfall",
            resourceName: "landfall_boat",
            title: "Harbor Sloop",
            summary: "The boat you set out in.",
            symbolName: "sailboat.fill",
            unlockLevel: 1
        ),
        ShipDesign(
            id: "gardenEstate",
            resourceName: "garden_estate_ship",
            title: "Garden Estate",
            summary: "Granite decks, iron railings, two lamps burning at the stern.",
            symbolName: "leaf.fill",
            unlockLevel: 5
        ),
    ]

    static let `default` = all[0]

    static func design(id: String?) -> ShipDesign {
        all.first { $0.id == id } ?? `default`
    }
}

// MARK: - 3Dの船に渡す見た目一式

struct BoatParts {
    var sail: UIColor
    var jib: UIColor
    var hull: UIColor
    var stripe: UIColor?
    var flag: String
    /// どのUSDZを読むか。色より先に効く指定なので、船を替えたら
    /// ノードごと作り直す必要がある。
    var shipID: String = ShipCatalog.default.id

    var ship: ShipDesign { ShipCatalog.design(id: shipID) }

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
    private static let shipStorageKey = "boat.ship"

    static var selectedSailID: String {
        let saved = UserDefaults.standard.string(forKey: sailStorageKey)
        return sailColors.first(where: { $0.id == saved })?.id ?? sailColors[0].id
    }

    static func selectSail(_ id: String) {
        guard sailColors.contains(where: { $0.id == id }) else { return }
        UserDefaults.standard.set(id, forKey: sailStorageKey)
    }

    /// 一度開いた船は、あとで記録を削ってレベルが下がっても取り上げない。
    /// 開放の判定は選ぶ画面だけで行い、進水済みの船はそのまま乗り続けられる。
    static var selectedShipID: String {
        ShipCatalog.design(id: UserDefaults.standard.string(forKey: shipStorageKey)).id
    }

    static var selectedShip: ShipDesign {
        ShipCatalog.design(id: selectedShipID)
    }

    static func selectShip(_ id: String) {
        guard ShipCatalog.all.contains(where: { $0.id == id }) else { return }
        UserDefaults.standard.set(id, forKey: shipStorageKey)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: sailStorageKey)
        UserDefaults.standard.removeObject(forKey: shipStorageKey)
    }

    static var selectedSail: SailColorOption {
        sailColors.first(where: { $0.id == selectedSailID }) ?? sailColors[0]
    }

    /// 見た目が変わったかを一言で表す鍵。共有カードやウィジェットの
    /// 描き直し判定に使う。船を足しても書き換えずに済むよう、船と帆の
    /// 両方をここへ含める。
    static var appearanceKey: String {
        "\(selectedShipID)-\(selectedSailID)"
    }

    /// 選択色は両方の帆へ適用し、廃止した部位は常に標準値にする。
    static var currentParts: BoatParts {
        let sail = selectedSail.uiColor
        return BoatParts(
            sail: sail,
            jib: sail,
            hull: BoatParts.default.hull,
            stripe: nil,
            flag: "none",
            shipID: selectedShipID
        )
    }

    // 旧クライアントとFirestoreルールとの互換性のため5フィールドは維持する。
    // 船体色は廃止済みで誰も読まないので、`boatHull` を船の指定に充てる。
    // ここに新しいキーを足すとルール側の許可リスト(firestore.rules)まで
    // 触ることになり、配信の順序を狂わせる。
    static var shareData: [String: String] {
        let sail = selectedSailID
        return [
            "boatSail": sail,
            "boatJib": sail,
            "boatHull": selectedShipID,
            "boatStripe": "none",
            "boatFlag": "none",
        ]
    }

    /// 港の旧データに個別部位が残っていても、帆色と船以外は標準船として表示する。
    /// 旧クライアントの `boatHull` は色名なので、船の名前と一致しなければ
    /// 最初の船として描く。
    static func parts(fromIDs ids: [String: String?]) -> BoatParts {
        let sailID = ids["boatSail"] ?? nil
        let sail = sailColors.first(where: { $0.id == sailID })?.uiColor
            ?? BoatParts.default.sail
        return BoatParts(
            sail: sail,
            jib: sail,
            hull: BoatParts.default.hull,
            stripe: nil,
            flag: "none",
            shipID: ShipCatalog.design(id: ids["boatHull"] ?? nil).id
        )
    }
}
