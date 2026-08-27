import Metal
import OSLog
import SceneKit
import simd

/// Owns the native Metal program and its packed per-frame inputs. The program
/// stays behind a Debug rollout gate until it matches every shoreline and wake
/// feature provided by the current shader modifiers.
enum MetalOceanProgram {
    private static let rolloutDefaultsKey = "LandfallNativeMetalOcean"
    private static let diagnostics = Diagnostics()

    static var isRolloutEnabled: Bool {
#if DEBUG
        UserDefaults.standard.bool(forKey: rolloutDefaultsKey)
#else
        false
#endif
    }

    static func make(
        layout: HomeIslandOceanEffects.Layout,
        appearance: HomeIslandOceanEffects.Appearance
    ) -> SCNProgram? {
        guard isRolloutEnabled,
              let device = MTLCreateSystemDefaultDevice(),
              let library = MetalOceanShaderLibrary.makeLibrary(on: device),
              MemoryLayout<Uniforms>.stride == 160 else {
            return nil
        }

        let baseUniforms = Uniforms(
            time: 0,
            shallowColor: linearColor(appearance.shallow),
            seaColor: linearColor(appearance.sea),
            deepColor: linearColor(appearance.deep),
            skyColor: linearColor(appearance.sky),
            horizonColor: linearColor(appearance.horizon),
            sunColor: linearColor(appearance.sun),
            sunDirection: SIMD3(
                appearance.sunDirection.x,
                appearance.sunDirection.y,
                appearance.sunDirection.z
            ),
            sunStrength: appearance.sunStrength,
            surfaceSize: SIMD2(Float(layout.width), Float(layout.depth)),
            coordinateOffset: SIMD2(layout.centerX, 0),
            microNormalScale: MetalRenderingProfile.current.oceanMicroNormalScale
        )
        let program = SCNProgram()
        program.library = library
        program.vertexFunctionName = MetalOceanShaderLibrary.vertexFunctionName
        program.fragmentFunctionName = MetalOceanShaderLibrary.fragmentFunctionName
        program.isOpaque = true
        program.delegate = diagnostics
        program.handleBinding(ofBufferNamed: "ocean", frequency: .perNode) {
            stream, _, _, _ in
            var uniforms = baseUniforms
            uniforms.time = HomeIslandOceanEffects.currentTime
            withUnsafeBytes(of: &uniforms) { bytes in
                guard let address = bytes.baseAddress else { return }
                stream.writeBytes(address, count: bytes.count)
            }
        }
        return program
    }

    private static func linearColor(_ rgb: UInt) -> SIMD3<Float> {
        let color = HomeIslandOceanEffects.linearColorVector(rgb)
        return SIMD3(color.x, color.y, color.z)
    }

    private struct Uniforms {
        var time: Float
        var shallowColor: SIMD3<Float>
        var seaColor: SIMD3<Float>
        var deepColor: SIMD3<Float>
        var skyColor: SIMD3<Float>
        var horizonColor: SIMD3<Float>
        var sunColor: SIMD3<Float>
        var sunDirection: SIMD3<Float>
        var sunStrength: Float
        var surfaceSize: SIMD2<Float>
        var coordinateOffset: SIMD2<Float>
        var microNormalScale: Float
    }

    private final class Diagnostics: NSObject, SCNProgramDelegate {
        private let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "Landfall",
            category: "MetalOcean"
        )

        func program(_ program: SCNProgram, handleError error: any Error) {
            logger.error("Native ocean program error: \(error.localizedDescription, privacy: .public)")
        }
    }
}
