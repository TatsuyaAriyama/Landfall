import Foundation

/// アプリ内の表示言語。端末設定に関わらず切り替えられる。
/// system = 端末の言語に従う / en / ja。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case ja

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    /// nil のときは端末の言語(オーバーライドしない)。
    var localeIdentifier: String? {
        switch self {
        case .system: nil
        case .en: "en"
        case .ja: "ja"
        }
    }

    /// 言語ピルに出す自称表記(自言語で表示するのが慣例)。systemは別途ローカライズ。
    var nativeName: String {
        switch self {
        case .system: ""
        case .en: "English"
        case .ja: "日本語"
        }
    }

    /// SwiftUIの \.locale に流すロケール。systemは自動更新ロケール。
    var locale: Locale {
        if let id = localeIdentifier { return Locale(identifier: id) }
        return .autoupdatingCurrent
    }

    /// 現在の保存値(UserDefaults)。LFヘルパーからも参照する。
    static var current: AppLanguage {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let value = AppLanguage(rawValue: raw) else { return .system }
        return value
    }
}
