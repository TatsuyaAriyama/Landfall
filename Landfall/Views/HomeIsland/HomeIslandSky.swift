import SwiftUI
import UIKit

struct HomeIslandSkyBackdrop: View {
    let brightness: HomeIslandBrightness

    var body: some View {
        Image(uiImage: HomeIslandSky.image(for: brightness))
            .resizable()
            .interpolation(.medium)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// A quiet daylight gradient shared by the live island and its exported photo.
/// Cache one narrow strip per brightness level, so camera movement never
/// allocates a screen-sized texture or changes the atmosphere's exposure.
enum HomeIslandSky {
    private static let strips: [HomeIslandBrightness: UIImage] = {
        Dictionary(uniqueKeysWithValues: HomeIslandBrightness.allCases.map { brightness in
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            format.preferredRange = .standard
            let size = CGSize(width: 1, height: 1_024)
            let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                let colors = [0x79B9CF, 0xAED7DE, 0xD1E5DE].map { rgb in
                    color(rgb, brightness: brightness).cgColor
                }
                guard let gradient = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                    colors: colors as CFArray,
                    locations: [0, 0.42, 1]
                ) else { return }
                renderer.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: 0, y: size.height),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
            return (brightness, image)
        })
    }()

    static func image(for brightness: HomeIslandBrightness) -> UIImage {
        // All enum cases are populated once above, including the fallback.
        strips[brightness]!
    }

    private static func color(_ rgb: Int, brightness: HomeIslandBrightness) -> UIColor {
        let offset = CGFloat(brightness.skyBrightness)
        func channel(_ value: Int) -> CGFloat {
            min(1, max(0, CGFloat(value & 0xFF) / 255 + offset))
        }
        return UIColor(
            red: channel(rgb >> 16),
            green: channel(rgb >> 8),
            blue: channel(rgb),
            alpha: 1
        )
    }
}
