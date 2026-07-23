import Foundation
import SwiftUI

/// 船のカスタムできる部位。今は帆と船体(3Dの帆船が持つ主要2部位)。旗などは後で拡張。
enum BoatPart: String, CaseIterable, Identifiable {
    case sail, hull
    var id: String { rawValue }
    var storageKey: String { "boat_\(rawValue)" }

    var title: LocalizedStringKey {
        switch self {
        case .sail: "Sail color"
        case .hull: "Hull"
        }
    }

    /// 色の選択肢(id・色・解放に要する累計時間)。Web boat.ts と同値。
    var options: [BoatOption] {
        switch self {
        case .sail:
            return [
                BoatOption(id: "sand", hex: 0xEADEBD, unlockHours: 0),
                BoatOption(id: "coral", hex: 0xF0997B, unlockHours: 10),
                BoatOption(id: "sunYellow", hex: 0xFFD84D, unlockHours: 25),
                BoatOption(id: "seaGreen", hex: 0x5DCAA5, unlockHours: 50),
                BoatOption(id: "lavender", hex: 0xCECBF6, unlockHours: 100),
            ]
        case .hull:
            return [
                BoatOption(id: "sand", hex: 0xEADEBD, unlockHours: 0),
                BoatOption(id: "coral", hex: 0xF0997B, unlockHours: 30),
                BoatOption(id: "deepRust", hex: 0x7A3B22, unlockHours: 60),
            ]
        }
    }
}

struct BoatOption: Identifiable {
    let id: String
    let hex: UInt
    /// 解放に要する累計時間(時間)。0 は最初から。
    let unlockHours: Int
    var color: Color { Color(hex: hex) }
    var uiColor: UIColor { UIColor(rgb: hex) }
    func isUnlocked(totalMinutes: Int) -> Bool { totalMinutes >= unlockHours * 60 }
}

/// 3D の船に渡す色一式。
struct BoatParts {
    var sail: UIColor
    var hull: UIColor
    static let `default` = BoatParts(sail: UIColor(rgb: 0xEADEBD), hull: UIColor(rgb: 0xEADEBD))
}

/// 選択中の船の色(UserDefaults)。Web の localStorage 相当。
enum BoatCustomization {
    static func selectedID(_ part: BoatPart) -> String {
        let saved = UserDefaults.standard.string(forKey: part.storageKey)
        if let saved, part.options.contains(where: { $0.id == saved }) { return saved }
        return part.options[0].id
    }
    static func select(_ part: BoatPart, _ id: String) {
        UserDefaults.standard.set(id, forKey: part.storageKey)
    }
    static func uiColor(_ part: BoatPart) -> UIColor {
        let id = selectedID(part)
        return part.options.first { $0.id == id }?.uiColor ?? part.options[0].uiColor
    }
    /// 3D船に渡す現在の色一式。
    static var currentParts: BoatParts {
        BoatParts(sail: uiColor(.sail), hull: uiColor(.hull))
    }
}

/// 累計時間(分)。船の色の解放判定に使う(Web totalMinutes 相当)。
func totalStudyMinutes(_ sessions: [StudySession]) -> Int {
    sessions.reduce(0) { $0 + $1.minutes }
}
