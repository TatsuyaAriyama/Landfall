import Metal
import OSLog
import SceneKit
import simd

/// Owns the native Metal program and its packed per-frame inputs. The program
/// rolls out first on Ultra-tier timer voyages, while Debug builds can opt in
/// on every scene for visual comparison and regression testing.
enum MetalOceanProgram {
    private static let rolloutDefaultsKey = "LandfallNativeMetalOcean"
    private static let diagnostics = Diagnostics()

    private static func isRolloutEnabled(for layout: HomeIslandOceanEffects.Layout) -> Bool {
#if DEBUG
        return UserDefaults.standard.bool(forKey: rolloutDefaultsKey)
#else
        return layout.sceneRole == .timerVoyage
            && MetalRenderingProfile.current.tier == .ultra
#endif
    }

    static func make(
        layout: HomeIslandOceanEffects.Layout,
        appearance: HomeIslandOceanEffects.Appearance,
        islandScale: Float
    ) -> SCNProgram? {
        guard isRolloutEnabled(for: layout),
              MetalRenderingProfile.current.supportsNativeOceanProgram,
              let device = MTLCreateSystemDefaultDevice(),
              let library = MetalOceanShaderLibrary.makeLibrary(on: device),
              MemoryLayout<Uniforms>.stride == 224 else {
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
            microNormalScale: MetalRenderingProfile.current.oceanMicroNormalScale,
            lightColor: linearColor(appearance.light),
            fogColor: linearColor(appearance.fog),
            shoreline: layout.includesShoreline ? 1 : 0,
            islandScale: islandScale,
            boatPosition: .zero,
            boatHeading: SIMD2(0, 1),
            boatSpeed: 0
        )
        let program = SCNProgram()
        program.library = library
        program.vertexFunctionName = MetalOceanShaderLibrary.vertexFunctionName
        program.fragmentFunctionName = MetalOceanShaderLibrary.fragmentFunctionName(
            for: MetalRenderingProfile.current.tier
        )
        program.isOpaque = true
        program.delegate = diagnostics
        program.handleBinding(ofBufferNamed: "ocean", frequency: .perNode) {
            stream, _, shadable, _ in
            var uniforms = baseUniforms
            uniforms.time = HomeIslandOceanEffects.currentTime
            if let material = shadable as? SCNMaterial {
                uniforms.boatPosition = vector2(named: "uBoatPosition", from: material)
                    ?? uniforms.boatPosition
                uniforms.boatHeading = vector2(named: "uBoatHeading", from: material)
                    ?? uniforms.boatHeading
                uniforms.boatSpeed = (material.value(forKey: "uBoatSpeed") as? NSNumber)?.floatValue
                    ?? uniforms.boatSpeed
            }
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

    private static func vector2(named key: String, from material: SCNMaterial) -> SIMD2<Float>? {
        guard let value = material.value(forKey: key) as? SCNVector3 else { return nil }
        return SIMD2(value.x, value.y)
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
        var lightColor: SIMD3<Float>
        var fogColor: SIMD3<Float>
        var shoreline: Float
        var islandScale: Float
        var boatPosition: SIMD2<Float>
        var boatHeading: SIMD2<Float>
        var boatSpeed: Float
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
