import Metal
import SceneKit

/// Selects a stable Metal quality level without relying on device model names.
/// SceneKit remains the scene graph while ocean rendering is migrated in small,
/// reversible stages to native Metal shaders.
struct MetalRenderingProfile {
    enum Tier {
        case compatible
        case enhanced
        case ultra
    }

    static let current = MetalRenderingProfile(device: MTLCreateSystemDefaultDevice())

    let tier: Tier
    let supportsNativeOceanProgram: Bool

    var antialiasingMode: SCNAntialiasingMode {
        .multisampling4X
    }

    var interactiveFramesPerSecond: Int {
        60
    }

    /// Adds geometric resolution only where the GPU family has comfortable
    /// headroom. The compatible tier intentionally preserves today's density.
    func oceanSegments(base: Int) -> Int {
        let scale: Double
        switch tier {
        case .compatible: scale = 1
        case .enhanced: scale = 1.17
        case .ultra: scale = 1.33
        }
        let scaled = Int((Double(base) * scale).rounded(.up))
        return ((scaled + 7) / 8) * 8
    }

    /// Fine normals are fragment-only, so modern Apple GPUs can carry a little
    /// more close-range structure without increasing SceneKit node complexity.
    var oceanMicroNormalScale: Float {
        switch tier {
        case .compatible: return 1
        case .enhanced: return 1.08
        case .ultra: return 1.16
        }
    }

    static func sceneViewOptions() -> [String: Any] {
        [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue]
    }

    private init(device: MTLDevice?) {
        guard let device else {
            tier = .compatible
            supportsNativeOceanProgram = false
            return
        }

        supportsNativeOceanProgram = MetalOceanShaderLibrary.isAvailable(on: device)

#if targetEnvironment(simulator)
        tier = .enhanced
#else
        if device.supportsFamily(.apple8) {
            tier = .ultra
        } else if device.supportsFamily(.apple6) {
            tier = .enhanced
        } else {
            tier = .compatible
        }
#endif
    }
}
