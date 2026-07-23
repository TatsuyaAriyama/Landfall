import Foundation
import SwiftUI

// 船のカスタマイズ。Web boat.ts の完全移植。累計時間(全期間)で部位が解放される。
// 一部(moonlight帆・kraken旗)は共同航海の戦利品(loot)で解放。選択はローカル保存。

/// カスタムできる部位。帆・前帆(ジブ)・船体・喫水ライン・旗。
enum BoatPart: String, CaseIterable, Identifiable {
    case sail, jib, hull, stripe, flag
    var id: String { rawValue }
    var storageKey: String { "boat.\(rawValue)" }

    var title: LocalizedStringKey {
        switch self {
        case .sail: "Sail"
        case .jib: "Jib"
        case .hull: "Hull"
        case .stripe: "Stripe"
        case .flag: "Flag"
        }
    }

    /// 色/形の選択肢(Web BOAT_OPTIONS と同値)。
    var options: [BoatOption] {
        switch self {
        case .sail:
            return [
                BoatOption(id: "sand", hex: 0xEADEBD, unlockMinutes: 0),
                BoatOption(id: "coral", hex: 0xF0997B, unlockMinutes: 10 * 60),
                BoatOption(id: "sunYellow", hex: 0xFFD84D, unlockMinutes: 25 * 60),
                BoatOption(id: "seaGreen", hex: 0x5DCAA5, unlockMinutes: 50 * 60),
                BoatOption(id: "lavender", hex: 0xCECBF6, unlockMinutes: 100 * 60),
                BoatOption(id: "moonlight", hex: 0xF4F1EC, unlockMinutes: 0, lootKey: .moonlightSail),
            ]
        case .jib:
            return [
                BoatOption(id: "sand", hex: 0xEADEBD, unlockMinutes: 0),
                BoatOption(id: "seaGreen", hex: 0x5DCAA5, unlockMinutes: 5 * 60),
                BoatOption(id: "coral", hex: 0xF0997B, unlockMinutes: 20 * 60),
                BoatOption(id: "sunYellow", hex: 0xFFD84D, unlockMinutes: 40 * 60),
                BoatOption(id: "lavender", hex: 0xCECBF6, unlockMinutes: 80 * 60),
            ]
        case .hull:
            return [
                BoatOption(id: "sand", hex: 0xEADEBD, unlockMinutes: 0),
                BoatOption(id: "coral", hex: 0xF0997B, unlockMinutes: 30 * 60),
                BoatOption(id: "deepRust", hex: 0x7A3B22, unlockMinutes: 60 * 60),
            ]
        case .stripe:
            return [
                BoatOption(id: "none", hex: nil, unlockMinutes: 0),
                BoatOption(id: "returnOrange", hex: 0xF5822A, unlockMinutes: 20 * 60),
                BoatOption(id: "deepRust", hex: 0x4A1B0C, unlockMinutes: 45 * 60),
            ]
        case .flag:
            return [
                BoatOption(id: "none", hex: nil, unlockMinutes: 0),
                BoatOption(id: "pennant", hex: nil, unlockMinutes: 15 * 60),
                BoatOption(id: "swallow", hex: nil, unlockMinutes: 40 * 60),
                BoatOption(id: "kraken", hex: nil, unlockMinutes: 0, lootKey: .krakenFlag),
            ]
        }
    }
}

struct BoatOption: Identifiable {
    let id: String
    /// 色を持つ部位のみ(none 系・旗は nil)。
    let hex: UInt?
    /// 解放に要する累計時間(分)。0 は最初から。
    let unlockMinutes: Int
    /// 共同航海の戦利品で解放される場合の鍵。
    var lootKey: LootKey?

    init(id: String, hex: UInt?, unlockMinutes: Int, lootKey: LootKey? = nil) {
        self.id = id
        self.hex = hex
        self.unlockMinutes = unlockMinutes
        self.lootKey = lootKey
    }

    var color: Color? { hex.map { Color(hex: $0) } }
    var uiColor: UIColor? { hex.map { UIColor(rgb: $0) } }

    /// いま選べるか(累計時間 or 戦利品)。Web isBoatOptionUnlocked 相当。
    func isUnlocked(totalMinutes: Int) -> Bool {
        if let lootKey { return LootStore.has(lootKey) }
        return totalMinutes >= unlockMinutes
    }
}

// MARK: - 戦利品(共同航海のフラグ。累計時間ではなく到着で解放。ローカル永続)

enum LootKey: String {
    case moonlightSail = "loot.moonlightSail"
    case krakenFlag = "loot.krakenFlag"
}

enum LootStore {
    /// 旧「港の試練」フラグ。持っている人は両戦利品を解放済みとして扱う。
    private static let legacyKey = "loot.harborTrial"

    static func has(_ key: LootKey) -> Bool {
        let d = UserDefaults.standard
        return d.string(forKey: key.rawValue) == "1" || d.string(forKey: legacyKey) == "1"
    }

    /// 解放する。新規に解放されたときだけ true(トースト判定用)。
    @discardableResult
    static func grant(_ key: LootKey) -> Bool {
        if has(key) { return false }
        UserDefaults.standard.set("1", forKey: key.rawValue)
        return true
    }
}

// MARK: - 3D の船に渡す見た目一式

/// 3D の船に渡す色/形一式。stripe は nil で「なし」、flag は id 文字列。
struct BoatParts {
    var sail: UIColor
    var jib: UIColor
    var hull: UIColor
    var stripe: UIColor?          // nil = none
    var flag: String              // "none" | "pennant" | "swallow" | "kraken"

    static let `default` = BoatParts(
        sail: UIColor(rgb: 0xEADEBD),
        jib: UIColor(rgb: 0xEADEBD),
        hull: UIColor(rgb: 0xEADEBD),
        stripe: nil,
        flag: "none"
    )
}

/// 選択中の船(UserDefaults)。Web の localStorage 相当。
enum BoatCustomization {
    static func selectedID(_ part: BoatPart) -> String {
        let saved = UserDefaults.standard.string(forKey: part.storageKey)
        if let saved, part.options.contains(where: { $0.id == saved }) { return saved }
        return part.options[0].id
    }

    static func select(_ part: BoatPart, _ id: String) {
        UserDefaults.standard.set(id, forKey: part.storageKey)
    }

    /// その部位の現在の色(色を持たない部位は nil)。
    static func uiColor(_ part: BoatPart) -> UIColor? {
        let id = selectedID(part)
        return part.options.first { $0.id == id }?.uiColor
    }

    /// 3D船に渡す現在の一式。
    static var currentParts: BoatParts {
        BoatParts(
            sail: uiColor(.sail) ?? BoatParts.default.sail,
            jib: uiColor(.jib) ?? BoatParts.default.jib,
            hull: uiColor(.hull) ?? BoatParts.default.hull,
            stripe: uiColor(.stripe),
            flag: selectedID(.flag)
        )
    }

    // MARK: 港へ共有する部位id一式(色ではなくidを載せる。docs/SCHEMA.md 準拠)

    static var shareData: [String: String] {
        [
            "boatSail": selectedID(.sail),
            "boatJib": selectedID(.jib),
            "boatHull": selectedID(.hull),
            "boatStripe": selectedID(.stripe),
            "boatFlag": selectedID(.flag),
        ]
    }

    /// 共有された部位idを色/形へ解決する(未知・欠損は各部位の既定へ静かに落とす)。
    static func parts(fromIDs ids: [String: String?]) -> BoatParts {
        func pick(_ part: BoatPart, _ key: String) -> BoatOption {
            let id = ids[key] ?? nil
            return part.options.first { $0.id == id } ?? part.options[0]
        }
        return BoatParts(
            sail: pick(.sail, "boatSail").uiColor ?? BoatParts.default.sail,
            jib: pick(.jib, "boatJib").uiColor ?? BoatParts.default.jib,
            hull: pick(.hull, "boatHull").uiColor ?? BoatParts.default.hull,
            stripe: pick(.stripe, "boatStripe").uiColor,
            flag: pick(.flag, "boatFlag").id
        )
    }
}

/// 累計時間(分)。船の解放判定に使う(Web totalMinutes 相当)。
func totalStudyMinutes(_ sessions: [StudySession]) -> Int {
    sessions.reduce(0) { $0 + $1.minutes }
}
