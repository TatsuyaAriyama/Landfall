import Metal
import OSLog
import SceneKit
import simd

/// Owns the native Metal program and its packed per-frame inputs. The program
/// rolls out by scene and GPU tier, while Debug builds can opt in on every
/// scene for visual regression testing.
enum MetalOceanProgram {
    enum RolloutScene {
        case stillImage
        case timerVoyage
        case homeIsland
        case entryExperience
        case boatStudio
    }

    private static let rolloutDefaultsKey = "LandfallNativeMetalOcean"
    private static let diagnostics = Diagnostics()

    private static func isRolloutEnabled(for scene: RolloutScene) -> Bool {
#if DEBUG
        guard UserDefaults.standard.bool(forKey: rolloutDefaultsKey) else { return false }
        if UserDefaults.standard.bool(forKey: "LandfallMetalTimerRolloutOnly") {
            return scene == .timerVoyage
        }
        return true
#else
        switch scene {
        case .stillImage:
            return false
        case .timerVoyage:
            return true
        case .homeIsland, .boatStudio:
            return MetalRenderingProfile.current.tier != .compatible
        case .entryExperience:
            return MetalRenderingProfile.current.tier != .compatible
        }
#endif
    }

    static func make(
        layout: HomeIslandOceanEffects.Layout,
        appearance: HomeIslandOceanEffects.Appearance,
        islandScale: Float,
        rolloutScene: RolloutScene
    ) -> SCNProgram? {
        guard isRolloutEnabled(for: rolloutScene),
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

    static func installRuntimeFallback(
        for program: SCNProgram,
        on material: SCNMaterial,
        shaderModifiers: [SCNShaderModifierEntryPoint: String]
    ) {
        diagnostics.register(
            program: program,
            material: material,
            shaderModifiers: shaderModifiers
        )
#if DEBUG
        if UserDefaults.standard.bool(forKey: "LandfallMetalSimulateProgramFailure") {
            diagnostics.activateFallback(for: program, simulated: true)
        }
#endif
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
        private final class Fallback {
            weak var material: SCNMaterial?
            let shaderModifiers: [SCNShaderModifierEntryPoint: String]

            init(
                material: SCNMaterial,
                shaderModifiers: [SCNShaderModifierEntryPoint: String]
            ) {
                self.material = material
                self.shaderModifiers = shaderModifiers
            }
        }

        private let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "Landfall",
            category: "MetalOcean"
        )
        private let lock = NSLock()
        private var fallbacks: [ObjectIdentifier: Fallback] = [:]

        func register(
            program: SCNProgram,
            material: SCNMaterial,
            shaderModifiers: [SCNShaderModifierEntryPoint: String]
        ) {
            lock.lock()
            fallbacks = fallbacks.filter { $0.value.material != nil }
            fallbacks[ObjectIdentifier(program)] = Fallback(
                material: material,
                shaderModifiers: shaderModifiers
            )
            lock.unlock()
        }

        func program(_ program: SCNProgram, handleError error: any Error) {
            logger.error("Native ocean program error: \(error.localizedDescription, privacy: .public)")
            activateFallback(for: program, simulated: false)
        }

        func activateFallback(for program: SCNProgram, simulated: Bool) {
            if simulated {
                logger.debug("Simulating a native ocean program failure")
            }
            lock.lock()
            let fallback = fallbacks.removeValue(forKey: ObjectIdentifier(program))
            lock.unlock()
            guard let material = fallback?.material,
                  let shaderModifiers = fallback?.shaderModifiers else { return }
            DispatchQueue.main.async { [weak material] in
                guard let material else { return }
                material.program = nil
                material.shaderModifiers = shaderModifiers
                self.logger.notice("Restored shader-modifier ocean after Metal program failure")
#if DEBUG
                if simulated {
                    print("[MetalOcean] Simulated runtime failure restored fallback ocean")
                }
#endif
            }
        }
    }
}
