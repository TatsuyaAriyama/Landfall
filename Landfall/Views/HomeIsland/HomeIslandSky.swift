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

/// A soft maritime sky shared by the live island and its exported photo.
/// Generate the cloud field once, then cache the five exposure variants. Nothing
/// animates or allocates while walking, framing a photo, or opening the HUD.
enum HomeIslandSky {
    private static let textureWidth = 384
    private static let textureHeight = 768

    private static let skies: [HomeIslandBrightness: UIImage] = {
        let width = textureWidth
        let height = textureHeight
        var daylight = [Float](repeating: 0, count: width * height * 3)
        let zenith: [Float] = [0.43, 0.68, 0.78]
        let mist: [Float] = [0.75, 0.86, 0.85]
        let horizon: [Float] = [0.82, 0.90, 0.87]
        let cloudLight: [Float] = [0.98, 0.97, 0.91]

        for y in 0..<height {
            let v = Float(y) / Float(height - 1)
            let banks = exp(-pow((v - 0.105) / 0.042, 2)) * 0.52
                + exp(-pow((v - 0.245) / 0.028, 2)) * 0.66
                + exp(-pow((v - 0.335) / 0.014, 2)) * 0.38
            let upperMix = smoothstep(0, 0.43, v)
            let lowerMix = smoothstep(0.43, 1, v)
            for x in 0..<width {
                let u = Float(x) / Float(width - 1)
                // Long wind-swept banks, broken by smaller eddies. Their soft
                // edges keep the sky quiet behind the persistent glass HUD.
                let drift = noise(u * 3.2 + 8, v * 7.5 + 4)
                let field = cloudNoise(u * 4.4 + 17, v * 24 + drift * 1.8)
                let veil = smoothstep(0.34, 0.70, field) * banks
                // A broad pearl glow suggests light through sea air without
                // attaching a sun disc to the screen as the camera turns.
                let glow = exp(-pow((u - 0.76) / 0.58, 2)
                    - pow((v - 0.30) / 0.22, 2)) * 0.09
                let index = (y * width + x) * 3
                for channel in 0..<3 {
                    let base = zenith[channel] + (mist[channel] - zenith[channel]) * upperMix
                    let sky = base + (horizon[channel] - base) * lowerMix
                    daylight[index + channel] = sky
                        + (cloudLight[channel] - sky) * min(0.8, veil + glow)
                }
            }
        }

        return Dictionary(uniqueKeysWithValues: HomeIslandBrightness.allCases.map { brightness in
            var pixels = [UInt8](repeating: 255, count: width * height * 4)
            let offset = Float(brightness.skyBrightness)
            for pixel in 0..<(width * height) {
                for channel in 0..<3 {
                    pixels[pixel * 4 + channel] = UInt8(
                        (min(1, max(0, daylight[pixel * 3 + channel] + offset)) * 255).rounded()
                    )
                }
            }
            let provider = CGDataProvider(data: Data(pixels) as CFData)!
            let cgImage = CGImage(
                width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
            )!
            return (brightness, UIImage(cgImage: cgImage))
        })
    }()

    static func image(for brightness: HomeIslandBrightness) -> UIImage {
        // All enum cases are populated once above, including the fallback.
        skies[brightness]!
    }

    private static func smoothstep(_ low: Float, _ high: Float, _ value: Float) -> Float {
        let t = min(1, max(0, (value - low) / (high - low)))
        return t * t * (3 - 2 * t)
    }

    /// Deterministic value noise makes captures repeatable and keeps every
    /// brightness setting on exactly the same cloud composition.
    private static func noise(_ x: Float, _ y: Float) -> Float {
        let ix = Int(floor(x))
        let iy = Int(floor(y))
        let tx = smoothstep(0, 1, x - Float(ix))
        let ty = smoothstep(0, 1, y - Float(iy))
        func value(_ x: Int, _ y: Int) -> Float {
            var seed = UInt32(truncatingIfNeeded: x) &* 374_761_393
                &+ UInt32(truncatingIfNeeded: y) &* 668_265_263
            seed = (seed ^ (seed >> 13)) &* 1_274_126_177
            seed ^= seed >> 16
            return Float(seed & 0xFFFF) / 65_535
        }
        let top = value(ix, iy) * (1 - tx) + value(ix + 1, iy) * tx
        let bottom = value(ix, iy + 1) * (1 - tx) + value(ix + 1, iy + 1) * tx
        return top * (1 - ty) + bottom * ty
    }

    private static func cloudNoise(_ x: Float, _ y: Float) -> Float {
        noise(x, y) * 0.57
            + noise(x * 2.03 + 5, y * 2.03 + 9) * 0.28
            + noise(x * 4.07 + 11, y * 4.07 + 3) * 0.15
    }
}
