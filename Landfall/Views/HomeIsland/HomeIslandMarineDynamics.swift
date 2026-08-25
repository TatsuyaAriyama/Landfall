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

        static let homeIsland = WaveField(layout: .homeIsland)

        init(layout: HomeIslandOceanEffects.Layout) {
            surfaceY = layout.surfaceY
            width = Float(layout.width)
            depth = Float(layout.depth)
            centerX = layout.centerX
        }

        func sample(atWorldXZ worldXZ: SIMD2<Float>, time: Float) -> WaveSample {
            // A plane rotated -pi/2 maps local +Y to world -Z. Adding centerX
            // mirrors uCoordinateOffset and leaves p.x equal to world X.
            let localP = SIMD2(worldXZ.x - centerX, -worldXZ.y)
            let p = localP + SIMD2(centerX, 0)
            let distance = simd_length(SIMD2(p.x * 0.72, p.y))
            let calm = HomeIslandMarineDynamics.mix(
                0.36,
                1,
                HomeIslandMarineDynamics.smoothstep(10, 34, distance)
            )

            var height: Float = 0
            var shaderSlope = SIMD2<Float>.zero
            for wave in Self.spectrum {
                let phase = simd_dot(p, wave.direction) * wave.waveNumber
                    - time * wave.angularSpeed
                    + wave.phaseOffset
                height += sin(phase) * wave.amplitude
                shaderSlope += wave.direction
                    * (cos(phase) * wave.amplitude * wave.waveNumber)
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
                 angularSpeed: 0.42, phaseOffset: 0, amplitude: 0.150),
            Wave(direction: SIMD2(-0.766, 0.643), waveNumber: 0.155,
                 angularSpeed: 0.36, phaseOffset: 1.70, amplitude: 0.090),
            Wave(direction: SIMD2(0.906, 0.423), waveNumber: 0.340,
                 angularSpeed: 0.78, phaseOffset: 0.45, amplitude: 0.035),
            Wave(direction: SIMD2(-0.259, 0.966), waveNumber: 0.720,
                 angularSpeed: 1.22, phaseOffset: 2.10, amplitude: 0.014),
            Wave(direction: SIMD2(0.643, -0.766), waveNumber: 1.250,
                 angularSpeed: 1.68, phaseOffset: 0.90, amplitude: 0.005),
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

    struct WakeState {
        /// Shader coordinates: (world X, -world Z).
        let boatPosition: SIMD2<Float>
        /// Normalized travel direction in the same shader coordinate space.
        let heading: SIMD2<Float>
        let speed: Float

        static let inactive = WakeState(
            boatPosition: .zero,
            heading: SIMD2(1, 0),
            speed: 0
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
        }
    }

    struct Frame {
        let motion: BoatMotion
        let wake: WakeState
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
                return Frame(motion: .zero, wake: inactiveWake(at: worldPosition))
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
                    speed: smoothedSpeed
                )
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
                speed: 0
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
