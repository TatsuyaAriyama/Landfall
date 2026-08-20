import SwiftUI

/// 自分の島の明るさ。端末や部屋の明るさで海と砂の見え方は変わるので、
/// 歩いているときの明るさそのものを5段でずらせるようにする。
/// 写真モードのスライダは、ここで選んだ明るさからの増減として働く。
enum HomeIslandBrightness: String, CaseIterable, Identifiable {
    case dimmest, dim, standard, bright, brightest

    static let storageKey = "homeIsland.brightness"
    static let fallback = HomeIslandBrightness.standard

    var id: String { rawValue }

    /// 標準を0とした増減(EV)。写真モードのスライダと同じ単位。
    var exposureOffset: Float {
        switch self {
        case .dimmest: -0.60
        case .dim: -0.30
        case .standard: 0
        case .bright: 0.30
        case .brightest: 0.60
        }
    }

    /// 空だけはSceneKitの色調整の外にあるので、露出と同じ向きへ手で寄せる。
    var skyBrightness: Double { Double(exposureOffset) * 0.16 }

    /// 段の番号(1〜5)。目盛りの表示に使う。
    var step: Int { (Self.allCases.firstIndex(of: self) ?? 2) + 1 }

    var label: LocalizedStringKey {
        switch self {
        case .dimmest: "Dimmest"
        case .dim: "Dim"
        case .standard: "Standard"
        case .bright: "Bright"
        case .brightest: "Brightest"
        }
    }

    static func resolve(_ token: String) -> HomeIslandBrightness {
        HomeIslandBrightness(rawValue: token) ?? fallback
    }

    /// SwiftUI の外(SceneKit の Coordinator など)から今の設定を読む。
    static var current: HomeIslandBrightness {
        resolve(UserDefaults.standard.string(forKey: storageKey) ?? "")
    }
}
