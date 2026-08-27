import Metal
import ObjectiveC
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
    private static let programLock = NSLock()
    private static var programs: [String: SCNProgram] = [:]
    private static var uniformStorageKey: UInt8 = 0

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

    static func make(rolloutScene: RolloutScene) -> SCNProgram? {
        guard isRolloutEnabled(for: rolloutScene),
              MetalRenderingProfile.current.supportsNativeOceanProgram,
              let device = MTLCreateSystemDefaultDevice(),
              let library = MetalOceanShaderLibrary.makeLibrary(on: device),
              MemoryLayout<Uniforms>.stride == 240 else {
            return nil
        }

        let fragmentFunctionName = MetalOceanShaderLibrary.fragmentFunctionName(
            for: MetalRenderingProfile.current.tier
        )
        programLock.lock()
        defer { programLock.unlock() }
        if let program = programs[fragmentFunctionName] {
            return program
        }

        let program = SCNProgram()
        program.library = library
        program.vertexFunctionName = MetalOceanShaderLibrary.vertexFunctionName
        program.fragmentFunctionName = fragmentFunctionName
        program.isOpaque = true
        program.delegate = diagnostics
        for bufferName in ["vertexOcean", "fragmentOcean"] {
            program.handleBinding(
                ofBufferNamed: bufferName,
                frequency: .perNode,
                handler: oceanBufferBinding
            )
        }
        programs[fragmentFunctionName] = program
        return program
    }

    static func installUniforms(
        on material: SCNMaterial,
        layout: HomeIslandOceanEffects.Layout,
        appearance: HomeIslandOceanEffects.Appearance,
        islandScale: Float
    ) {
        let uniforms = Uniforms(
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
            boatSpeed: 0,
            boatSize: .zero,
            boatPresence: 0
        )
        objc_setAssociatedObject(
            material,
            &uniformStorageKey,
            UniformStorage(uniforms),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
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

    private static func vector2(named key: String, from material: SCNMaterial) -> SIMD2<Float>? {
        guard let value = material.value(forKey: key) as? SCNVector3 else { return nil }
        return SIMD2(value.x, value.y)
    }

    private static func linearColor(_ rgb: UInt) -> SIMD3<Float> {
        let color = HomeIslandOceanEffects.linearColorVector(rgb)
        return SIMD3(color.x, color.y, color.z)
    }

    /// The vertex and fragment stages use separate buffer names because SceneKit
    /// registers each reflected stage attachment independently. Both names share
    /// this encoder and the material remains the source of scene-specific data.
    private static let oceanBufferBinding: SCNBufferBindingBlock = {
        stream, _, shadable, _ in
        guard let material = shadable as? SCNMaterial,
              let storage = objc_getAssociatedObject(
                material,
                &uniformStorageKey
              ) as? UniformStorage else { return }
        var uniforms = storage.uniforms
        uniforms.time = HomeIslandOceanEffects.currentTime
        uniforms.boatPosition = vector2(named: "uBoatPosition", from: material)
            ?? uniforms.boatPosition
        uniforms.boatHeading = vector2(named: "uBoatHeading", from: material)
            ?? uniforms.boatHeading
        uniforms.boatSpeed = number(named: "uBoatSpeed", from: material)
        uniforms.boatSize = vector2(named: "uBoatSize", from: material)
            ?? uniforms.boatSize
        uniforms.boatPresence = number(named: "uBoatPresence", from: material)
        withUnsafeBytes(of: &uniforms) { bytes in
            guard let address = bytes.baseAddress else { return }
            stream.writeBytes(address, count: bytes.count)
        }
    }

    private static func number(
        named key: String,
        from material: SCNMaterial,
        default defaultValue: Float = 0
    ) -> Float {
        (material.value(forKey: key) as? NSNumber)?.floatValue ?? defaultValue
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
        var boatSize: SIMD2<Float>
        var boatPresence: Float
    }

    private final class UniformStorage: NSObject {
        let uniforms: Uniforms

        init(_ uniforms: Uniforms) {
            self.uniforms = uniforms
        }
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
        private var fallbacks: [ObjectIdentifier: [Fallback]] = [:]

        func register(
            program: SCNProgram,
            material: SCNMaterial,
            shaderModifiers: [SCNShaderModifierEntryPoint: String]
        ) {
            lock.lock()
            fallbacks = fallbacks.compactMapValues { entries in
                let liveEntries = entries.filter { $0.material != nil }
                return liveEntries.isEmpty ? nil : liveEntries
            }
            let key = ObjectIdentifier(program)
            var entries = fallbacks[key] ?? []
            if !entries.contains(where: { $0.material === material }) {
                entries.append(Fallback(
                    material: material,
                    shaderModifiers: shaderModifiers
                ))
            }
            fallbacks[key] = entries
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
            let registeredFallbacks = fallbacks.removeValue(forKey: ObjectIdentifier(program)) ?? []
            lock.unlock()
            guard !registeredFallbacks.isEmpty else { return }
            DispatchQueue.main.async {
                for fallback in registeredFallbacks {
                    guard let material = fallback.material else { continue }
                    material.program = nil
                    material.shaderModifiers = fallback.shaderModifiers
                }
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
