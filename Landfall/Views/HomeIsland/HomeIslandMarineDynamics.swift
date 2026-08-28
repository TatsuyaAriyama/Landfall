import SceneKit
import simd

/// Keeps the visible ocean, boat buoyancy and wake on one deterministic wave clock.
enum HomeIslandMarineDynamics {
    struct WaveSample {
        /// Height above the layout's undisturbed waterline.
        let displacement: Float
        let worldHeight: Float
        /// Derivatives of world height along world X and Z.
        let slope: SIMD2<Float>
        let normal: SIMD3<Float>
    }

    /// CPU mirror of the five geometry waves in `HomeIslandOceanEffects`.
    struct WaveField {
        let surfaceY: Float
        let width: Float
        let depth: Float
        let centerX: Float
        let includesShoreline: Bool

        static let homeIsland = WaveField(layout: .homeIsland)

        init(layout: HomeIslandOceanEffects.Layout) {
            surfaceY = layout.surfaceY
            width = Float(layout.width)
            depth = Float(layout.depth)
            centerX = layout.centerX
            includesShoreline = layout.includesShoreline
        }

        func sample(atWorldXZ worldXZ: SIMD2<Float>, time: Float) -> WaveSample {
            // A plane rotated -pi/2 maps local +Y to world -Z. Adding centerX
            // mirrors uCoordinateOffset and leaves p.x equal to world X.
            let localP = SIMD2(worldXZ.x - centerX, -worldXZ.y)
            let p = localP + SIMD2(centerX, 0)
            let distance = simd_length(SIMD2(p.x * 0.72, p.y))
            let coastalCalm = HomeIslandMarineDynamics.mix(
                0.36,
                1,
                HomeIslandMarineDynamics.smoothstep(10, 34, distance)
            )
            let calm: Float = includesShoreline ? coastalCalm : 0.72

            var phases = Self.spectrum.map { wave in
                simd_dot(p, wave.direction) * wave.waveNumber
                    - time * wave.angularSpeed
                    + wave.phaseOffset
            }
            let sinC = sin(phases[2])
            let sinD = sin(phases[3])
            let sinE = sin(phases[4])
            let cosC = cos(phases[2])
            let cosD = cos(phases[3])
            let cosE = cos(phases[4])
            let warpDirectionF = SIMD2<Float>(-0.940, 0.342)
            let warpDirectionG = SIMD2<Float>(0.515, 0.857)
            let phaseF = simd_dot(p, warpDirectionF) * 0.052
                - time * 0.14 + 0.30
            let phaseG = simd_dot(p, warpDirectionG) * 0.073
                - time * 0.19 + 1.35
            let cosF = cos(phaseF)
            let cosG = cos(phaseG)
            phases[0] += sinC * 0.34 + sinD * 0.10 + sin(phaseF) * 0.55
            phases[1] += -sinD * 0.26 + sinE * 0.08 - sin(phaseG) * 0.42

            let cosA = cos(phases[0])
            let cosB = cos(phases[1])
            let energyPhaseA = phaseF + 1.17
            let energyPhaseB = phaseG - 0.83
            let energyA = 1 + sin(energyPhaseA) * 0.18
            let energyB = 1 + sin(energyPhaseB) * 0.14
            let energyGradientA = warpDirectionF
                * (cos(energyPhaseA) * 0.052 * 0.18)
            let energyGradientB = warpDirectionG
                * (cos(energyPhaseB) * 0.073 * 0.14)
            let phaseGradients = [
                Self.spectrum[0].direction * Self.spectrum[0].waveNumber
                    + Self.spectrum[2].direction * (cosC * 0.340 * 0.34)
                    + Self.spectrum[3].direction * (cosD * 0.720 * 0.10)
                    + warpDirectionF * (cosF * 0.052 * 0.55),
                Self.spectrum[1].direction * Self.spectrum[1].waveNumber
                    - Self.spectrum[3].direction * (cosD * 0.720 * 0.26)
                    + Self.spectrum[4].direction * (cosE * 1.250 * 0.08)
                    - warpDirectionG * (cosG * 0.073 * 0.42),
                Self.spectrum[2].direction * Self.spectrum[2].waveNumber,
                Self.spectrum[3].direction * Self.spectrum[3].waveNumber,
                Self.spectrum[4].direction * Self.spectrum[4].waveNumber,
            ]
            let sinA = sin(phases[0])
            let sinB = sin(phases[1])
            var height = sinA * Self.spectrum[0].amplitude * energyA
                + sinB * Self.spectrum[1].amplitude * energyB
            var shaderSlope = phaseGradients[0]
                    * (cosA * Self.spectrum[0].amplitude * energyA)
                + energyGradientA * (sinA * Self.spectrum[0].amplitude)
                + phaseGradients[1]
                    * (cosB * Self.spectrum[1].amplitude * energyB)
                + energyGradientB * (sinB * Self.spectrum[1].amplitude)
            let sines = [sinC, sinD, sinE]
            let cosines = [cosC, cosD, cosE]
            for index in 2..<Self.spectrum.count {
                let localIndex = index - 2
                height += sines[localIndex] * Self.spectrum[index].amplitude
                shaderSlope += phaseGradients[index]
                    * (cosines[localIndex] * Self.spectrum[index].amplitude)
            }

            let edge = edgeFade(for: localP)
            let displacement = height * calm * edge
            shaderSlope *= calm * edge
            let worldSlope = SIMD2(shaderSlope.x, -shaderSlope.y)
            let normal = simd_normalize(
                SIMD3(-worldSlope.x, 1, -worldSlope.y)
            )
            return WaveSample(
                displacement: displacement,
                worldHeight: surfaceY + displacement,
                slope: worldSlope,
                normal: normal
            )
        }

        private func edgeFade(for localP: SIMD2<Float>) -> Float {
            let x = 1 - HomeIslandMarineDynamics.smoothstep(
                width * 0.43,
                width * 0.50,
                abs(localP.x)
            )
            let z = 1 - HomeIslandMarineDynamics.smoothstep(
                depth * 0.43,
                depth * 0.50,
                abs(localP.y)
            )
            return x * z
        }

        private struct Wave {
            let direction: SIMD2<Float>
            let waveNumber: Float
            let angularSpeed: Float
            let phaseOffset: Float
            let amplitude: Float
        }

        // Keep these values identical to both shader modifiers. Horizontal
        // Gerstner displacement does not change the height/slope sample point.
        private static let spectrum = [
            Wave(direction: SIMD2(0.342, 0.940), waveNumber: 0.105,
                 angularSpeed: 0.42, phaseOffset: 0, amplitude: 0.171),
            Wave(direction: SIMD2(-0.766, 0.643), waveNumber: 0.155,
                 angularSpeed: 0.36, phaseOffset: 1.70, amplitude: 0.104),
            Wave(direction: SIMD2(0.906, 0.423), waveNumber: 0.340,
                 angularSpeed: 0.78, phaseOffset: 0.45, amplitude: 0.052),
            Wave(direction: SIMD2(-0.259, 0.966), waveNumber: 0.720,
                 angularSpeed: 1.22, phaseOffset: 2.10, amplitude: 0.020),
            Wave(direction: SIMD2(0.643, -0.766), waveNumber: 1.250,
                 angularSpeed: 1.68, phaseOffset: 0.90, amplitude: 0.006),
        ]
    }

    struct BoatMotion {
        let heave: Float
        /// Rotation around the hull's bow axis.
        let roll: Float
        /// Rotation around the hull's starboard axis.
        let pitch: Float

        static let zero = BoatMotion(heave: 0, roll: 0, pitch: 0)
    }

    struct BoatTuning {
        var hullLength: Float = 2.15
        var beam: Float = 0.92
        var heaveAmount: Float = 0.86
        var angleAmount: Float = 0.78
        var maximumRoll: Float = 0.080
        var maximumPitch: Float = 0.060
        var response: Float = 5.5
        /// Boat USDZ files use local +X as the bow direction.
        var modelForward = SIMD3<Float>(1, 0, 0)

        static let homeIsland = BoatTuning()
    }

    /// Scales the home-island hull sampling footprint to a scene's boat root.
    /// The authored home boat is displayed at 0.92, while voyage compositions
    /// deliberately pull the same model farther back.
    static func boatTuning(forSceneScale sceneScale: Float) -> BoatTuning {
        var tuning = BoatTuning.homeIsland
        let scale = max(sceneScale, 0.001) / 0.92
        tuning.hullLength *= scale
        tuning.beam *= scale
        return tuning
    }

    struct WakeState {
        /// Shader coordinates: (world X, -world Z).
        let boatPosition: SIMD2<Float>
        /// Normalized travel direction in the same shader coordinate space.
        let heading: SIMD2<Float>
        let speed: Float
        /// Vertical hull offset from the undisturbed water plane.
        let heave: Float
        /// Water-contact footprint in world metres: (length, beam).
        let hullSize: SIMD2<Float>
        let isPresent: Bool

        static let inactive = WakeState(
            boatPosition: .zero,
            heading: SIMD2(1, 0),
            speed: 0,
            heave: 0,
            hullSize: .zero,
            isPresent: false
        )

        func apply(to material: SCNMaterial?) {
            material?.setValue(
                SCNVector3(boatPosition.x, boatPosition.y, 0),
                forKey: "uBoatPosition"
            )
            material?.setValue(
                SCNVector3(heading.x, heading.y, 0),
                forKey: "uBoatHeading"
            )
            material?.setValue(NSNumber(value: speed), forKey: "uBoatSpeed")
            material?.setValue(NSNumber(value: heave), forKey: "uBoatHeave")
            material?.setValue(
                SCNVector3(hullSize.x, hullSize.y, 0),
                forKey: "uBoatSize"
            )
            material?.setValue(
                NSNumber(value: isPresent ? Float(1) : Float(0)),
                forKey: "uBoatPresence"
            )
        }
    }

    struct Frame {
        let motion: BoatMotion
        let wake: WakeState
        /// The same analytical surface sample that drives the visible ocean.
        /// Consumers use it to keep the hull's wet boundary on the wave plane.
        let waterSurface: WaveSample
    }

    static func boatMotion(
        atWorldXZ center: SIMD2<Float>,
        forward rawForward: SIMD2<Float>,
        time: Float,
        field: WaveField = .homeIsland,
        tuning: BoatTuning = .homeIsland
    ) -> BoatMotion {
        let forward = normalized(rawForward, fallback: SIMD2(1, 0))
        let starboard = SIMD2(-forward.y, forward.x)
        let halfLength = tuning.hullLength * 0.5
        let halfBeam = tuning.beam * 0.5
        let bow = field.sample(atWorldXZ: center + forward * halfLength, time: time)
        let stern = field.sample(atWorldXZ: center - forward * halfLength, time: time)
        let port = field.sample(atWorldXZ: center - starboard * halfBeam, time: time)
        let right = field.sample(atWorldXZ: center + starboard * halfBeam, time: time)

        return BoatMotion(
            heave: (bow.displacement + stern.displacement + port.displacement
                    + right.displacement) * 0.25 * tuning.heaveAmount,
            roll: clamp(
                atan2(port.worldHeight - right.worldHeight, tuning.beam)
                    * tuning.angleAmount,
                -tuning.maximumRoll,
                tuning.maximumRoll
            ),
            pitch: clamp(
                atan2(bow.worldHeight - stern.worldHeight, tuning.hullLength)
                    * tuning.angleAmount,
                -tuning.maximumPitch,
                tuning.maximumPitch
            )
        )
    }

    /// Renderer-loop component that keeps hull motion and the analytical wake
    /// on the ocean shader's deterministic clock.
    final class BoatController {
        private let field: WaveField
        private let tuning: BoatTuning
        private let resetLock = NSLock()
        private weak var configuredBuoyancyNode: SCNNode?
        private weak var pendingResetNode: SCNNode?
        private var resetRequested = false
        private var basePosition = SCNVector3Zero
        private var baseOrientation = simd_quatf(
            angle: 0,
            axis: SIMD3<Float>(0, 1, 0)
        )
        private var previousPosition: SIMD3<Float>?
        private var smoothedMotion = BoatMotion.zero
        private var smoothedSpeed: Float = 0
        private var wakeHeading = SIMD2<Float>(1, 0)

        init(field: WaveField = .homeIsland, tuning: BoatTuning = .homeIsland) {
            self.field = field
            self.tuning = tuning
        }

        @discardableResult
        func update(
            boatRoot: SCNNode,
            buoyancyNode: SCNNode,
            oceanTime: Float,
            deltaTime rawDeltaTime: Float,
            reduceMotion: Bool,
            propulsionSpeed: Float? = nil
        ) -> Frame {
            configureIfNeeded(buoyancyNode)
            consumePendingReset(fallback: buoyancyNode)
            let worldPosition = boatRoot.presentation.simdWorldPosition
            let waterSurface = field.sample(
                atWorldXZ: SIMD2(worldPosition.x, worldPosition.z),
                time: oceanTime
            )
            let elapsedTime = min(max(rawDeltaTime, 0), 0.25)
            let responseDeltaTime = min(elapsedTime, 0.1)

            let transform = boatRoot.presentation.simdWorldTransform
            let localForward = simd_normalize(tuning.modelForward)
            let transformed = transform * SIMD4(localForward, 0)
            let physicalForward = HomeIslandMarineDynamics.normalized(
                SIMD2(transformed.x, transformed.z),
                fallback: SIMD2(1, 0)
            )
            let target = HomeIslandMarineDynamics.boatMotion(
                atWorldXZ: SIMD2(worldPosition.x, worldPosition.z),
                forward: physicalForward,
                time: oceanTime,
                field: field,
                tuning: tuning
            )

            if reduceMotion {
                smoothedMotion = .zero
                smoothedSpeed = 0
                apply(.zero, to: buoyancyNode)
                previousPosition = worldPosition
                return Frame(
                    motion: .zero,
                    wake: inactiveWake(at: worldPosition),
                    waterSurface: waterSurface
                )
            }

            let blend = responseDeltaTime > 0
                ? 1 - exp(-tuning.response * responseDeltaTime)
                : 1
            smoothedMotion = BoatMotion(
                heave: HomeIslandMarineDynamics.mix(
                    smoothedMotion.heave,
                    target.heave,
                    blend
                ),
                roll: HomeIslandMarineDynamics.mix(
                    smoothedMotion.roll,
                    target.roll,
                    blend
                ),
                pitch: HomeIslandMarineDynamics.mix(
                    smoothedMotion.pitch,
                    target.pitch,
                    blend
                )
            )
            apply(smoothedMotion, to: buoyancyNode)

            var speed: Float = 0
            if let propulsionSpeed {
                speed = max(propulsionSpeed, 0)
                if speed > 0.001 {
                    wakeHeading = physicalForward
                }
            } else if let previousPosition, elapsedTime > 0 {
                let travel = SIMD2(
                    worldPosition.x - previousPosition.x,
                    worldPosition.z - previousPosition.z
                )
                let distance = simd_length(travel)
                if distance < 2.5 {
                    speed = distance / elapsedTime
                    if distance > 0.001 {
                        wakeHeading = travel / distance
                    }
                }
            }
            previousPosition = worldPosition
            let speedBlend = responseDeltaTime > 0
                ? 1 - exp(-7 * responseDeltaTime)
                : 1
            smoothedSpeed = HomeIslandMarineDynamics.mix(
                smoothedSpeed,
                min(speed, 4),
                speedBlend
            )

            return Frame(
                motion: smoothedMotion,
                wake: WakeState(
                    boatPosition: SIMD2(worldPosition.x, -worldPosition.z),
                    heading: SIMD2(wakeHeading.x, -wakeHeading.y),
                    speed: smoothedSpeed,
                    heave: smoothedMotion.heave,
                    hullSize: SIMD2(tuning.hullLength, tuning.beam),
                    isPresent: true
                ),
                waterSurface: waterSurface
            )
        }

        func reset(buoyancyNode: SCNNode? = nil) {
            if let buoyancyNode { apply(.zero, to: buoyancyNode) }
            previousPosition = nil
            smoothedMotion = .zero
            smoothedSpeed = 0
        }

        /// Main-thread scene choreography can request a reset, but all mutable
        /// controller and SceneKit state is consumed on the renderer thread.
        func requestReset(buoyancyNode: SCNNode? = nil) {
            resetLock.lock()
            pendingResetNode = buoyancyNode
            resetRequested = true
            resetLock.unlock()
        }

        private func consumePendingReset(fallback: SCNNode) {
            resetLock.lock()
            let shouldReset = resetRequested
            let node = pendingResetNode
            resetRequested = false
            pendingResetNode = nil
            resetLock.unlock()
            guard shouldReset else { return }
            reset(buoyancyNode: node ?? fallback)
        }

        private func configureIfNeeded(_ node: SCNNode) {
            guard configuredBuoyancyNode !== node else { return }
            configuredBuoyancyNode = node
            basePosition = node.position
            baseOrientation = node.simdOrientation
            smoothedMotion = .zero
        }

        private func apply(_ motion: BoatMotion, to node: SCNNode) {
            let parentYScale: Float = node.parent.map {
                let axis = $0.presentation.simdWorldTransform.columns.1
                return simd_length(SIMD3(axis.x, axis.y, axis.z))
            } ?? 1
            node.position = SCNVector3(
                basePosition.x,
                basePosition.y + motion.heave / max(parentYScale, 0.001),
                basePosition.z
            )
            let forward = simd_normalize(tuning.modelForward)
            let starboard = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
            let roll = simd_quatf(angle: motion.roll, axis: forward)
            let pitch = simd_quatf(angle: motion.pitch, axis: starboard)
            node.simdOrientation = baseOrientation * roll * pitch
        }

        private func inactiveWake(at position: SIMD3<Float>) -> WakeState {
            WakeState(
                boatPosition: SIMD2(position.x, -position.z),
                heading: SIMD2(wakeHeading.x, -wakeHeading.y),
                speed: 0,
                heave: 0,
                hullSize: SIMD2(tuning.hullLength, tuning.beam),
                isPresent: true
            )
        }
    }

    private static func normalized(
        _ vector: SIMD2<Float>,
        fallback: SIMD2<Float>
    ) -> SIMD2<Float> {
        let length = simd_length(vector)
        return length > 0.0001 ? vector / length : fallback
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        let t = clamp((value - edge0) / (edge1 - edge0), 0, 1)
        return t * t * (3 - 2 * t)
    }

    private static func clamp(_ value: Float, _ lower: Float, _ upper: Float) -> Float {
        min(max(value, lower), upper)
    }

    private static func mix(_ a: Float, _ b: Float, _ amount: Float) -> Float {
        a + (b - a) * amount
    }
}
