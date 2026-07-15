import SwiftUI

/// 選べるアプリアイコン。midnight を既定(primary)、coral を代替とする。
/// UIKit非依存にして、アイコンPNGの再生成ハーネス(macOS)からも参照できるようにする。
enum AppIconOption: String, CaseIterable, Identifiable {
    case midnight
    case coral

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .midnight: "ミッドナイト"
        case .coral: "コーラル"
        }
    }

    /// setAlternateIconName に渡す名前。primary(midnight)は nil。
    /// coral はアセットカタログの App Icon セット名と一致させる。
    var alternateIconName: String? {
        switch self {
        case .midnight: nil
        case .coral: "AppIconCoral"
        }
    }

    var background: Color {
        switch self {
        case .midnight: LFColor.midnight
        case .coral: LFColor.coral
        }
    }

    var birdColor: Color {
        switch self {
        case .midnight: LFColor.coral
        case .coral: LFColor.deepRust
        }
    }
}

/// アプリアイコンと同一構図の不死鳥。設定プレビューと実アイコンPNGの単一ソース。
/// 1024pt基準の比率で描き、任意サイズに追従する。
struct AppIconArt: View {
    let option: AppIconOption

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let k = s / 1024
            ZStack {
                option.background
                PhoenixShape()
                    .fill(option.birdColor)
                    .frame(width: 620 * k, height: 620 * k)
                    .overlay(
                        Circle()
                            .fill(option.background)
                            .frame(width: 52 * k, height: 52 * k)
                            .offset(y: -150 * k)
                    )
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
