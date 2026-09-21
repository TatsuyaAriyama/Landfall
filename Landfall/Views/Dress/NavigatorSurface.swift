import SceneKit
import UIKit

/// Small, shared surface maps add close-up detail without baking in outfit colors.
/// Material instances stay independent so existing name-based recoloring works.
enum NavigatorSurface {
    static func cloth(
        _ color: UIColor,
        roughness: CGFloat,
        doubleSided: Bool = false
    ) -> SCNMaterial {
        let value = roughness.isFinite ? min(1, max(0, roughness)) : 0.85
        let material = base(color, roughness: value, metalness: 0)
        material.isDoubleSided = doubleSided
        if let normal = weaveNormal {
            material.normal.contents = normal
            material.normal.intensity = 0.45
            configureWeave(material.normal)
        }
        if let roughnessMap = roughnessMap(value) {
            material.roughness.contents = roughnessMap
            configureWeave(material.roughness)
        }
        return material
    }

    static func leather(_ color: UIColor) -> SCNMaterial {
        // A broad, restrained highlight separates straps and boots from cloth.
        base(color, roughness: 0.60, metalness: 0)
    }

    static func brass(_ color: UIColor) -> SCNMaterial {
        // Worn brass reflects its base color, with no mirror-like pin highlights.
        base(color, roughness: 0.38, metalness: 1)
    }

    private static func base(_ color: UIColor, roughness: CGFloat, metalness: CGFloat) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.roughness.contents = roughness
        material.metalness.contents = metalness
        return material
    }

    private static func configureWeave(_ property: SCNMaterialProperty) {
        property.wrapS = .repeat
        property.wrapT = .repeat
        property.contentsTransform = SCNMatrix4MakeScale(8, 8, 1)
        property.minificationFilter = .linear
        property.magnificationFilter = .linear
        property.mipFilter = .linear
        property.maxAnisotropy = 2
    }

    private static let textureSize = 64

    // Eight smoothly sampled, seamless threads per tile. Static initialization
    // creates this map once; no per-frame work or custom fragment shader is used.
    private static let weaveNormal: CGImage? = makeMap { x, y in
        let dx = 0.12 * sin(x) + 0.025 * sin(x / 2) * cos(y / 2)
        let dy = 0.12 * sin(y) + 0.025 * cos(x / 2) * sin(y / 2)
        let length = sqrt(dx * dx + dy * dy + 1)
        return (0.5 + dx / length * 0.5, 0.5 + dy / length * 0.5, 0.5 + 0.5 / length)
    }

    private final class TextureImage {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    // NSCache is thread-safe and bounded. Only roughness values actually used by
    // outfits are generated, independently of the number of colors/materials.
    private static let roughnessMaps: NSCache<NSNumber, TextureImage> = {
        let cache = NSCache<NSNumber, TextureImage>()
        cache.countLimit = 16
        cache.totalCostLimit = 16 * textureSize * textureSize * 4
        return cache
    }()

    private static func roughnessMap(_ value: CGFloat) -> CGImage? {
        // One-percent precision bounds cache keys without a visible finish shift.
        let key = NSNumber(value: Int((value * 100).rounded()))
        if let cached = roughnessMaps.object(forKey: key) { return cached.image }
        let base = key.doubleValue / 100
        guard let image = makeMap({ x, y in
            let variation = 0.012 * cos(x) * cos(y) + 0.008 * cos(x / 2) * cos(y / 2)
            let roughness = min(1, max(0, base + variation))
            return (roughness, roughness, roughness)
        }) else { return nil }
        roughnessMaps.setObject(TextureImage(image), forKey: key, cost: textureSize * textureSize * 4)
        return image
    }

    private static func makeMap(_ sample: (Double, Double) -> (Double, Double, Double)) -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: textureSize * textureSize * 4)
        let phaseStep = 2 * Double.pi * 8 / Double(textureSize)
        for y in 0..<textureSize {
            for x in 0..<textureSize {
                let color = sample((Double(x) + 0.5) * phaseStep, (Double(y) + 0.5) * phaseStep)
                let offset = (y * textureSize + x) * 4
                pixels[offset] = UInt8((min(1, max(0, color.0)) * 255).rounded())
                pixels[offset + 1] = UInt8((min(1, max(0, color.1)) * 255).rounded())
                pixels[offset + 2] = UInt8((min(1, max(0, color.2)) * 255).rounded())
            }
        }
        // These are numeric normal/roughness values, not gamma-encoded colors.
        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB),
              let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: textureSize, height: textureSize,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: textureSize * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
