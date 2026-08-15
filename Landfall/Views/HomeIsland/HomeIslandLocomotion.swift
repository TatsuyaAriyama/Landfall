import Foundation
import simd

/// Designer-facing tuning for Home Island locomotion. The shipped defaults are
/// mirrored by `navigator_locomotion.json`, so movement can be balanced without
/// touching the SceneKit integration.
struct HomeIslandLocomotionTuning: Codable, Equatable, Sendable {
    var inputDeadZone: Float = 0.045
    var walkInputEnd: Float = 0.34
    var jogInputEnd: Float = 0.74
    var walkSpeed: Float = 1.05
    var jogSpeed: Float = 2.30
    var sprintSpeed: Float = 4.05
    var groundAcceleration: Float = 10.8
    var sprintAcceleration: Float = 8.2
    var braking: Float = 15.5
    var reverseBraking: Float = 19.0
    var lowSpeedTurnRate: Float = 11.5
    var sprintTurnRate: Float = 4.2
    var bodyTurnRate: Float = 9.5
    var highSpeedTurnSlowdown: Float = 0.62
    var airAcceleration: Float = 2.4
    var gravity: Float = 14.8
    var jumpSpeed: Float = 4.85
    var coyoteTime: Float = 0.10
    var jumpBufferTime: Float = 0.12
    var maximumStepUp: Float = 0.34
    var groundSnapDistance: Float = 0.46
    var maximumSubstepDistance: Float = 0.085
    var slopeProbeDistance: Float = 0.24
    var maximumSlopeDegrees: Float = 44
    var uphillSpeedLoss: Float = 0.38
    var downhillSpeedGain: Float = 0.10
    var walkCycleDistance: Float = 0.72
    var jogCycleDistance: Float = 1.02
    var sprintCycleDistance: Float = 1.34
    var landingReactionSpeed: Float = 3.2
    var fullLandingReactionSpeed: Float = 8.0
    var longRunBreathOnset: Float = 8
    var longRunBreathFull: Float = 24
    var cameraFollowSharpness: Float = 13
    var cameraMaximumLookAhead: Float = 0.48
    var cameraMaximumPullback: Float = 1.15
    var cameraMaximumFOVBoost: Float = 5.5
    var cameraBobAmount: Float = 0.026

    static let standard: Self = {
        guard let url = Bundle.main.url(
            forResource: "navigator_locomotion",
            withExtension: "json"
        ), let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Self.self, from: data),
           decoded.isValid
        else { return Self() }
        return decoded
    }()

    private var isValid: Bool {
        inputDeadZone >= 0 && inputDeadZone < 0.5
            && walkInputEnd > inputDeadZone
            && jogInputEnd > walkInputEnd && jogInputEnd < 1
            && walkSpeed > 0 && jogSpeed > walkSpeed && sprintSpeed > jogSpeed
            && groundAcceleration > 0 && braking > 0 && reverseBraking >= braking
            && gravity > 0 && jumpSpeed > 0 && maximumStepUp >= 0
            && maximumSubstepDistance > 0.02
    }
}

struct HomeIslandWalkInput: Equatable, Sendable {
    var x: Float = 0
    var forward: Float = 0
    var sprintRequested = false
    var jumpRequested = false

    static let zero = HomeIslandWalkInput()

    var magnitude: Float {
        min(sqrt(x * x + forward * forward), 1)
    }
}

enum HomeIslandGroundSurface: String, Codable, CaseIterable, Sendable {
    case sand
    case grass
    case stone
    case wood
    case boat
}

struct HomeIslandGroundSample: Equatable, Sendable {
    var height: Float
    var normal: SIMD3<Float>
    var surface: HomeIslandGroundSurface

    init(
        height: Float,
        normal: SIMD3<Float> = SIMD3<Float>(0, 1, 0),
        surface: HomeIslandGroundSurface = .sand
    ) {
        self.height = height
        let length = simd_length(normal)
        self.normal = length > 0.001 ? normal / length : SIMD3<Float>(0, 1, 0)
        self.surface = surface
    }
}

enum HomeIslandGait: String, Codable, Sendable {
    case idle
    case walk
    case jog
    case sprint
    case airborne
}

enum HomeIslandStepFoot: Sendable {
    case left
    case right
}

struct HomeIslandLocomotionBlend: Equatable, Sendable {
    var idle: Float
    var walk: Float
    var jog: Float
    var sprint: Float
}

struct HomeIslandLocomotionFrame: Sendable {
    var position: SIMD3<Float>
    var velocity: SIMD3<Float>
    var facingYaw: Float
    var planarSpeed: Float
    var normalizedSpeed: Float
    var turnIntensity: Float
    var gait: HomeIslandGait
    var blend: HomeIslandLocomotionBlend
    var gaitPhase: Float
    var isGrounded: Bool
    var didLand: Bool
    var didJump: Bool
    var landingImpact: Float
    /// Add this to the rendered character Y while the authoritative root stays
    /// snapped to its logical ground. It briefly preserves the pre-step visual
    /// height, then decays to zero inside the motor.
    var stepOffset: Float
    var didStep: Bool
    var stepFoot: HomeIslandStepFoot
    var ground: HomeIslandGroundSample
    var slopeAngle: Float
    var fatigue: Float

    static func idle(position: SIMD3<Float>, yaw: Float) -> Self {
        Self(
            position: position,
            velocity: .zero,
            facingYaw: yaw,
            planarSpeed: 0,
            normalizedSpeed: 0,
            turnIntensity: 0,
            gait: .idle,
            blend: .init(idle: 1, walk: 0, jog: 0, sprint: 0),
            gaitPhase: 0,
            isGrounded: true,
            didLand: false,
            didJump: false,
            landingImpact: 0,
            stepOffset: 0,
            didStep: false,
            stepFoot: .left,
            ground: .init(height: position.y),
            slopeAngle: 0,
            fatigue: 0
        )
    }
}

private enum HomeIslandLocomotionSimulation {
    /// Long stalls are bounded so returning from the background cannot run an
    /// unbounded simulation burst, while ordinary 15 Hz frames and 200 ms
    /// hitches still consume all elapsed gameplay time.
    static let maximumFrameDelta: Float = 0.25
    static let maximumSubstepDelta: Float = 1 / 60
    static let landingSurfaceTolerance: Float = 0.015
    static let visualStepThreshold: Float = 0.055
    static let visualStepDecayRate: Float = 12
    static let levelStepNormalY: Float = 0.978 // approximately cos(12 degrees)
}

/// Pure mapping shared by a physical gamepad and deterministic probes.
enum HomeIslandGamepadMapping {
    static func movement(
        stickX: Float,
        stickY: Float,
        dpadX: Float = 0,
        dpadY: Float = 0,
        sprint: Bool,
        jump: Bool,
        deadZone: Float = 0.10
    ) -> HomeIslandWalkInput {
        var x = stickX
        var y = stickY
        if sqrt(x * x + y * y) < deadZone {
            x = dpadX
            y = dpadY
        }
        let length = sqrt(x * x + y * y)
        guard length >= deadZone else {
            return HomeIslandWalkInput(jumpRequested: jump)
        }
        let response = min(max((length - deadZone) / max(1 - deadZone, 0.001), 0), 1)
        let scale = response / max(length, 0.001)
        return HomeIslandWalkInput(
            x: x * scale,
            forward: y * scale,
            sprintRequested: sprint,
            jumpRequested: jump
        )
    }
}

/// Vertical motion is kept separate from planar steering so arrival, seating,
/// and future traversal modes can reset it without disturbing input routing.
final class HomeIslandGroundingController {
    private let tuning: HomeIslandLocomotionTuning
    private(set) var verticalVelocity: Float = 0
    private(set) var isGrounded = true
    private(set) var landingImpact: Float = 0
    private var timeSinceGrounded: Float = 0
    private var jumpBufferRemaining: Float = 0
    private var jumpWasHeld = false

    init(tuning: HomeIslandLocomotionTuning) {
        self.tuning = tuning
    }

    func reset(grounded: Bool = true) {
        verticalVelocity = 0
        isGrounded = grounded
        landingImpact = 0
        timeSinceGrounded = grounded ? 0 : tuning.coyoteTime + 1
        jumpBufferRemaining = 0
        jumpWasHeld = false
    }

    struct Result {
        var y: Float
        var didLand: Bool
        var didJump: Bool
    }

    func update(
        currentY: Float,
        groundHeight: Float,
        jumpHeld: Bool,
        canSnapToGround: Bool,
        canLandOnGround: Bool,
        deltaTime: Float
    ) -> Result {
        let dt = min(
            max(deltaTime, 0),
            HomeIslandLocomotionSimulation.maximumSubstepDelta
        )
        landingImpact = max(landingImpact - dt * 3.6, 0)
        let jumpPressed = jumpHeld && !jumpWasHeld
        jumpWasHeld = jumpHeld
        if jumpPressed { jumpBufferRemaining = tuning.jumpBufferTime }
        else { jumpBufferRemaining = max(jumpBufferRemaining - dt, 0) }

        if isGrounded { timeSinceGrounded = 0 }
        else { timeSinceGrounded += dt }

        if jumpBufferRemaining > 0,
           isGrounded || timeSinceGrounded <= tuning.coyoteTime {
            let takeoffY = isGrounded && canSnapToGround
                ? max(currentY, groundHeight)
                : currentY
            jumpBufferRemaining = 0
            isGrounded = false
            verticalVelocity = tuning.jumpSpeed
            return Result(
                y: takeoffY + verticalVelocity * dt,
                didLand: false,
                didJump: true
            )
        }

        if isGrounded {
            guard canSnapToGround else {
                isGrounded = false
                verticalVelocity = 0
                return Result(y: currentY, didLand: false, didJump: false)
            }
            verticalVelocity = 0
            return Result(y: groundHeight, didLand: false, didJump: false)
        }

        verticalVelocity -= tuning.gravity * dt
        let nextY = currentY + verticalVelocity * dt
        let crossesGroundFromAbove = currentY
            >= groundHeight - HomeIslandLocomotionSimulation.landingSurfaceTolerance
            && nextY <= groundHeight
        if canLandOnGround,
           verticalVelocity <= 0,
           crossesGroundFromAbove {
            let impactSpeed = abs(verticalVelocity)
            verticalVelocity = 0
            isGrounded = true
            timeSinceGrounded = 0
            landingImpact = min(max(
                (impactSpeed - tuning.landingReactionSpeed)
                    / max(tuning.fullLandingReactionSpeed - tuning.landingReactionSpeed, 0.001),
                0
            ), 1)
            return Result(y: groundHeight, didLand: true, didJump: false)
        }
        return Result(y: nextY, didLand: false, didJump: false)
    }
}

/// Frame-rate-independent kinematic motor. SceneKit supplies ground queries and
/// collision predicates; this type owns velocity, inertia, gait, and grounding.
final class HomeIslandLocomotionMotor {
    typealias GroundSampler = (_ x: Float, _ z: Float) -> HomeIslandGroundSample
    typealias OccupancyTest = (_ x: Float, _ z: Float) -> Bool

    let tuning: HomeIslandLocomotionTuning
    private let grounding: HomeIslandGroundingController
    private var horizontalVelocity = SIMD2<Float>.zero
    private var facingYaw: Float = 0
    private var gaitPhase: Float = 0
    private var halfStepIndex = 0
    private var sprintDuration: Float = 0
    private var visualStepOffset: Float = 0
    private var isReversing = false
    private var initialized = false

    init(tuning: HomeIslandLocomotionTuning = .standard) {
        self.tuning = tuning
        grounding = HomeIslandGroundingController(tuning: tuning)
    }

    func reset(position: SIMD3<Float>, yaw: Float, grounded: Bool = true) {
        horizontalVelocity = .zero
        facingYaw = yaw
        gaitPhase = 0
        halfStepIndex = 0
        sprintDuration = 0
        visualStepOffset = 0
        isReversing = false
        initialized = true
        grounding.reset(grounded: grounded)
    }

    func update(
        input: HomeIslandWalkInput,
        position initialPosition: SIMD3<Float>,
        currentYaw: Float,
        cameraForward: SIMD2<Float>,
        cameraRight: SIMD2<Float>,
        deltaTime: Float,
        sampleGround: GroundSampler,
        canOccupy: OccupancyTest
    ) -> HomeIslandLocomotionFrame {
        let totalDelta = min(
            max(deltaTime, 0),
            HomeIslandLocomotionSimulation.maximumFrameDelta
        )
        guard totalDelta > 0 else {
            var frame = HomeIslandLocomotionFrame.idle(
                position: initialPosition,
                yaw: currentYaw
            )
            frame.gaitPhase = gaitPhase
            frame.isGrounded = grounding.isGrounded
            frame.landingImpact = grounding.landingImpact
            frame.stepOffset = visualStepOffset
            return frame
        }
        if !initialized { reset(position: initialPosition, yaw: currentYaw) }

        let substepCount = max(
            1,
            Int(ceil(
                totalDelta / HomeIslandLocomotionSimulation.maximumSubstepDelta
            ))
        )
        let substepDelta = totalDelta / Float(substepCount)
        var position = initialPosition
        var yaw = currentYaw
        var frame = HomeIslandLocomotionFrame.idle(
            position: initialPosition,
            yaw: currentYaw
        )
        var didLand = false
        var didJump = false
        var didStep = false
        var stepFoot = frame.stepFoot
        var eventLandingImpact: Float = 0

        for _ in 0..<substepCount {
            frame = updateSubstep(
                input: input,
                position: position,
                currentYaw: yaw,
                cameraForward: cameraForward,
                cameraRight: cameraRight,
                deltaTime: substepDelta,
                sampleGround: sampleGround,
                canOccupy: canOccupy
            )
            position = frame.position
            yaw = frame.facingYaw
            didLand = didLand || frame.didLand
            didJump = didJump || frame.didJump
            if frame.didLand {
                eventLandingImpact = max(eventLandingImpact, frame.landingImpact)
            }
            if frame.didStep {
                didStep = true
                stepFoot = frame.stepFoot
            }
        }

        frame.didLand = didLand
        frame.didJump = didJump
        frame.didStep = didStep
        if didStep { frame.stepFoot = stepFoot }
        if didLand {
            frame.landingImpact = max(frame.landingImpact, eventLandingImpact)
        }
        return frame
    }

    private func updateSubstep(
        input: HomeIslandWalkInput,
        position initialPosition: SIMD3<Float>,
        currentYaw _: Float,
        cameraForward: SIMD2<Float>,
        cameraRight: SIMD2<Float>,
        deltaTime dt: Float,
        sampleGround: GroundSampler,
        canOccupy: OccupancyTest
    ) -> HomeIslandLocomotionFrame {
        visualStepOffset *= exp(
            -HomeIslandLocomotionSimulation.visualStepDecayRate * dt
        )
        if abs(visualStepOffset) < 0.0005 { visualStepOffset = 0 }

        var position = initialPosition
        let currentGround = sampleGround(position.x, position.z)
        let rawMagnitude = min(sqrt(input.x * input.x + input.forward * input.forward), 1)
        let strength = remappedInput(rawMagnitude)
        let desiredDirection = worldDirection(
            lateral: input.x,
            forward: input.forward,
            cameraForward: cameraForward,
            cameraRight: cameraRight
        )

        var targetSpeed = speed(forInput: strength)
        if input.sprintRequested, strength > 0 {
            targetSpeed = tuning.sprintSpeed
        }
        targetSpeed *= slopeMultiplier(direction: desiredDirection, ground: currentGround)

        let currentSpeed = simd_length(horizontalVelocity)
        var turnIntensity: Float = 0
        if let desiredDirection {
            let desiredYaw = atan2(desiredDirection.x, desiredDirection.y)
            if currentSpeed > 0.04 {
                let velocityYaw = atan2(horizontalVelocity.x, horizontalVelocity.y)
                let delta = shortestAngle(desiredYaw - velocityYaw)
                turnIntensity = min(abs(delta) / .pi, 1)
                let speedRatio = min(currentSpeed / tuning.sprintSpeed, 1)
                let turnRate = mix(
                    tuning.lowSpeedTurnRate,
                    tuning.sprintTurnRate,
                    speedRatio
                )
                let nextVelocityYaw = velocityYaw
                    + clamp(delta, -turnRate * dt, turnRate * dt)
                let slowedTarget = targetSpeed * (
                    1 - tuning.highSpeedTurnSlowdown * speedRatio * turnIntensity
                )
                if !isReversing,
                   cos(delta) < -0.35,
                   currentSpeed > tuning.jogSpeed {
                    isReversing = true
                } else if isReversing, currentSpeed <= tuning.walkSpeed * 0.52 {
                    isReversing = false
                }
                let reversesAtSpeed = isReversing
                let acceleration = reversesAtSpeed
                    ? tuning.reverseBraking
                    : (slowedTarget > currentSpeed
                        ? mix(tuning.groundAcceleration, tuning.sprintAcceleration, speedRatio)
                        : tuning.braking)
                let nextSpeed = moveToward(
                    currentSpeed,
                    reversesAtSpeed ? min(slowedTarget, tuning.walkSpeed * 0.48) : slowedTarget,
                    acceleration * dt
                )
                horizontalVelocity = SIMD2<Float>(
                    sin(nextVelocityYaw) * nextSpeed,
                    cos(nextVelocityYaw) * nextSpeed
                )
            } else {
                let nextSpeed = moveToward(
                    currentSpeed,
                    targetSpeed,
                    tuning.groundAcceleration * dt
                )
                horizontalVelocity = desiredDirection * nextSpeed
            }
        } else {
            let nextSpeed = moveToward(currentSpeed, 0, tuning.braking * dt)
            if currentSpeed > 0.001 {
                horizontalVelocity *= nextSpeed / currentSpeed
            } else {
                horizontalVelocity = .zero
            }
        }

        if !grounding.isGrounded, let desiredDirection {
            let desiredAirVelocity = desiredDirection * min(targetSpeed, tuning.jogSpeed)
            horizontalVelocity = moveToward(
                horizontalVelocity,
                desiredAirVelocity,
                tuning.airAcceleration * dt
            )
        }

        let desiredDelta = horizontalVelocity * dt
        let horizontalStart = SIMD2<Float>(position.x, position.z)
        let resolved = resolveHorizontal(
            start: horizontalStart,
            displacement: desiredDelta,
            currentGroundHeight: currentGround.height,
            currentFootHeight: position.y,
            grounded: grounding.isGrounded,
            sampleGround: sampleGround,
            canOccupy: canOccupy
        )
        position.x = resolved.x
        position.z = resolved.y
        let actualDelta = resolved - horizontalStart
        horizontalVelocity = actualDelta / max(dt, 0.001)

        let ground = sampleGround(position.x, position.z)
        let drop = position.y - ground.height
        let groundIsWalkable = ground.normal.y
            >= cos(tuning.maximumSlopeDegrees * .pi / 180)
        let canSnap = drop <= tuning.groundSnapDistance && groundIsWalkable
        let wasGrounded = grounding.isGrounded
        let previousY = position.y
        let vertical = grounding.update(
            currentY: position.y,
            groundHeight: ground.height,
            jumpHeld: input.jumpRequested,
            canSnapToGround: canSnap,
            canLandOnGround: groundIsWalkable,
            deltaTime: dt
        )
        position.y = vertical.y

        if wasGrounded,
           ground.normal.y >= HomeIslandLocomotionSimulation.levelStepNormalY {
            let logicalStep: Float
            if vertical.didJump {
                // A simultaneous jump only needs to hide the upward ground snap;
                // the ballistic takeoff itself must remain visible.
                logicalStep = max(ground.height - previousY, 0)
            } else if grounding.isGrounded {
                logicalStep = ground.height - previousY
            } else {
                logicalStep = 0
            }
            if abs(logicalStep) >= HomeIslandLocomotionSimulation.visualStepThreshold {
                let limit = max(tuning.maximumStepUp, tuning.groundSnapDistance)
                visualStepOffset = clamp(
                    visualStepOffset - logicalStep,
                    -limit,
                    limit
                )
            }
        }

        let planarSpeed = simd_length(horizontalVelocity)
        if planarSpeed > 0.02 {
            let motionYaw = atan2(horizontalVelocity.x, horizontalVelocity.y)
            let speedRatio = min(planarSpeed / tuning.sprintSpeed, 1)
            let bodyRate = mix(tuning.bodyTurnRate * 1.25, tuning.bodyTurnRate * 0.70, speedRatio)
            facingYaw += clamp(
                shortestAngle(motionYaw - facingYaw),
                -bodyRate * dt,
                bodyRate * dt
            )
        }

        let normalizedSpeed = min(planarSpeed / tuning.sprintSpeed, 1)
        let gait = gait(for: planarSpeed, grounded: grounding.isGrounded)
        let cycleDistance = gaitCycleDistance(for: planarSpeed)
        let previousHalfStep = halfStepIndex
        if grounding.isGrounded, planarSpeed > 0.04 {
            gaitPhase += simd_length(actualDelta) / max(cycleDistance, 0.01) * 2 * .pi
            halfStepIndex = Int(floor(gaitPhase / .pi))
        }
        let didStep = grounding.isGrounded
            && simd_length(actualDelta) > 0.001
            && halfStepIndex != previousHalfStep
        let stepFoot: HomeIslandStepFoot = halfStepIndex.isMultiple(of: 2) ? .left : .right

        if gait == .sprint { sprintDuration += dt }
        else { sprintDuration = max(sprintDuration - dt * 1.7, 0) }
        let fatigue = min(max(
            (sprintDuration - tuning.longRunBreathOnset)
                / max(tuning.longRunBreathFull - tuning.longRunBreathOnset, 0.001),
            0
        ), 1)
        let slopeAngle = acos(min(max(ground.normal.y, -1), 1))

        return HomeIslandLocomotionFrame(
            position: position,
            velocity: SIMD3<Float>(
                horizontalVelocity.x,
                grounding.verticalVelocity,
                horizontalVelocity.y
            ),
            facingYaw: facingYaw,
            planarSpeed: planarSpeed,
            normalizedSpeed: normalizedSpeed,
            turnIntensity: turnIntensity,
            gait: gait,
            blend: blend(for: planarSpeed),
            gaitPhase: gaitPhase,
            isGrounded: grounding.isGrounded,
            didLand: vertical.didLand,
            didJump: vertical.didJump,
            landingImpact: grounding.landingImpact,
            stepOffset: visualStepOffset,
            didStep: didStep,
            stepFoot: stepFoot,
            ground: ground,
            slopeAngle: slopeAngle,
            fatigue: fatigue
        )
    }

    private func remappedInput(_ magnitude: Float) -> Float {
        guard magnitude > tuning.inputDeadZone else { return 0 }
        return min(max(
            (magnitude - tuning.inputDeadZone) / max(1 - tuning.inputDeadZone, 0.001),
            0
        ), 1)
    }

    private func speed(forInput strength: Float) -> Float {
        guard strength > 0 else { return 0 }
        if strength <= tuning.walkInputEnd {
            return tuning.walkSpeed * smoothstep(0, tuning.walkInputEnd, strength)
        }
        if strength <= tuning.jogInputEnd {
            let p = smoothstep(tuning.walkInputEnd, tuning.jogInputEnd, strength)
            return mix(tuning.walkSpeed, tuning.jogSpeed, p)
        }
        let p = smoothstep(tuning.jogInputEnd, 1, strength)
        return mix(tuning.jogSpeed, tuning.sprintSpeed, p)
    }

    private func worldDirection(
        lateral: Float,
        forward: Float,
        cameraForward: SIMD2<Float>,
        cameraRight: SIMD2<Float>
    ) -> SIMD2<Float>? {
        let combined = cameraForward * forward + cameraRight * lateral
        let length = simd_length(combined)
        return length > 0.001 ? combined / length : nil
    }

    private func slopeMultiplier(
        direction: SIMD2<Float>?,
        ground: HomeIslandGroundSample
    ) -> Float {
        guard let direction, ground.normal.y > 0.001 else { return 1 }
        let gradient = SIMD2<Float>(
            -ground.normal.x / ground.normal.y,
            -ground.normal.z / ground.normal.y
        )
        let gradientLength = simd_length(gradient)
        guard gradientLength > 0.001 else { return 1 }
        let slope = min(gradientLength, 1)
        let alignment = simd_dot(direction, gradient / gradientLength)
        if alignment >= 0 {
            return max(1 - tuning.uphillSpeedLoss * alignment * slope, 0.55)
        }
        return min(1 - tuning.downhillSpeedGain * alignment * slope, 1.12)
    }

    private func resolveHorizontal(
        start: SIMD2<Float>,
        displacement: SIMD2<Float>,
        currentGroundHeight: Float,
        currentFootHeight: Float,
        grounded: Bool,
        sampleGround: GroundSampler,
        canOccupy: OccupancyTest
    ) -> SIMD2<Float> {
        let distance = simd_length(displacement)
        let count = max(1, Int(ceil(distance / tuning.maximumSubstepDistance)))
        let increment = displacement / Float(count)
        var point = start
        var referenceGround = currentGroundHeight

        func valid(_ candidate: SIMD2<Float>, fromHeight: Float) -> Bool {
            guard canOccupy(candidate.x, candidate.y) else { return false }
            let sample = sampleGround(candidate.x, candidate.y)
            guard sample.normal.y >= cos(tuning.maximumSlopeDegrees * .pi / 180) else {
                return false
            }
            if grounded {
                return sample.height - fromHeight <= tuning.maximumStepUp
            }
            // Airborne movement may pass over a surface, but it must not enter
            // laterally below that surface and later snap upward onto it.
            return sample.height
                <= currentFootHeight
                    + HomeIslandLocomotionSimulation.landingSurfaceTolerance
        }

        for _ in 0..<count {
            let full = point + increment
            if valid(full, fromHeight: referenceGround) {
                point = full
                referenceGround = sampleGround(point.x, point.y).height
                continue
            }
            let xOnly = SIMD2<Float>(point.x + increment.x, point.y)
            let zOnly = SIMD2<Float>(point.x, point.y + increment.y)
            let xValid = valid(xOnly, fromHeight: referenceGround)
            let zValid = valid(zOnly, fromHeight: referenceGround)
            if xValid && zValid {
                point = abs(increment.x) >= abs(increment.y) ? xOnly : zOnly
            } else if xValid {
                point = xOnly
            } else if zValid {
                point = zOnly
            }
            referenceGround = sampleGround(point.x, point.y).height
        }
        return point
    }

    private func gait(for speed: Float, grounded: Bool) -> HomeIslandGait {
        guard grounded else { return .airborne }
        if speed < 0.06 { return .idle }
        if speed <= tuning.walkSpeed * 1.08 { return .walk }
        if speed <= tuning.jogSpeed * 1.08 { return .jog }
        return .sprint
    }

    private func gaitCycleDistance(for speed: Float) -> Float {
        if speed <= tuning.walkSpeed { return tuning.walkCycleDistance }
        if speed <= tuning.jogSpeed {
            let p = (speed - tuning.walkSpeed) / max(tuning.jogSpeed - tuning.walkSpeed, 0.001)
            return mix(tuning.walkCycleDistance, tuning.jogCycleDistance, p)
        }
        let p = min(
            (speed - tuning.jogSpeed) / max(tuning.sprintSpeed - tuning.jogSpeed, 0.001),
            1
        )
        return mix(tuning.jogCycleDistance, tuning.sprintCycleDistance, p)
    }

    private func blend(for speed: Float) -> HomeIslandLocomotionBlend {
        if speed <= tuning.walkSpeed {
            let p = min(speed / max(tuning.walkSpeed, 0.001), 1)
            return .init(idle: 1 - p, walk: p, jog: 0, sprint: 0)
        }
        if speed <= tuning.jogSpeed {
            let p = (speed - tuning.walkSpeed) / max(tuning.jogSpeed - tuning.walkSpeed, 0.001)
            return .init(idle: 0, walk: 1 - p, jog: p, sprint: 0)
        }
        let p = min(
            (speed - tuning.jogSpeed) / max(tuning.sprintSpeed - tuning.jogSpeed, 0.001),
            1
        )
        return .init(idle: 0, walk: 0, jog: 1 - p, sprint: p)
    }
}

struct HomeIslandCameraMotion: Equatable, Sendable {
    var pullback: Float = 0
    var fovBoost: Float = 0
    var lookAhead: SIMD2<Float> = .zero
    var bob: SIMD2<Float> = .zero
}

/// Camera response is intentionally independent from the kinematic motor. It
/// consumes one locomotion frame and can be disabled wholesale for Reduce Motion.
final class HomeIslandLocomotionCameraController {
    private let tuning: HomeIslandLocomotionTuning
    private(set) var motion = HomeIslandCameraMotion()

    init(tuning: HomeIslandLocomotionTuning) {
        self.tuning = tuning
    }

    func reset() {
        motion = HomeIslandCameraMotion()
    }

    func update(
        frame: HomeIslandLocomotionFrame,
        deltaTime: Float,
        reduceMotion: Bool
    ) -> HomeIslandCameraMotion {
        guard !reduceMotion else {
            reset()
            return motion
        }
        let dt = min(max(deltaTime, 0), 0.05)
        let response = 1 - exp(-tuning.cameraFollowSharpness * dt)
        let sprint = smoothstep(0.56, 1, frame.normalizedSpeed)
        let direction: SIMD2<Float>
        if frame.planarSpeed > 0.02 {
            direction = SIMD2<Float>(frame.velocity.x, frame.velocity.z) / frame.planarSpeed
        } else {
            direction = .zero
        }
        let targetLookAhead = direction * tuning.cameraMaximumLookAhead * sprint
        motion.lookAhead += (targetLookAhead - motion.lookAhead) * response
        motion.pullback += (tuning.cameraMaximumPullback * sprint - motion.pullback) * response
        motion.fovBoost += (tuning.cameraMaximumFOVBoost * sprint - motion.fovBoost) * response
        let planted: Float = frame.isGrounded ? 1 : 0
        let bobWeight = tuning.cameraBobAmount * frame.normalizedSpeed * planted
        let targetBob = SIMD2<Float>(
            sin(frame.gaitPhase) * bobWeight * 0.34,
            abs(cos(frame.gaitPhase)) * bobWeight
        )
        motion.bob += (targetBob - motion.bob) * min(response * 1.35, 1)
        return motion
    }
}

private func clamp(_ value: Float, _ lower: Float, _ upper: Float) -> Float {
    min(max(value, lower), upper)
}

private func mix(_ lhs: Float, _ rhs: Float, _ amount: Float) -> Float {
    lhs + (rhs - lhs) * min(max(amount, 0), 1)
}

private func moveToward(_ value: Float, _ target: Float, _ maximumDelta: Float) -> Float {
    if abs(target - value) <= maximumDelta { return target }
    return value + (target > value ? maximumDelta : -maximumDelta)
}

private func moveToward(
    _ value: SIMD2<Float>,
    _ target: SIMD2<Float>,
    _ maximumDelta: Float
) -> SIMD2<Float> {
    let delta = target - value
    let length = simd_length(delta)
    guard length > maximumDelta, length > 0.001 else { return target }
    return value + delta / length * maximumDelta
}

private func shortestAngle(_ angle: Float) -> Float {
    atan2(sin(angle), cos(angle))
}

private func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
    guard edge1 > edge0 else { return value < edge0 ? 0 : 1 }
    let x = min(max((value - edge0) / (edge1 - edge0), 0), 1)
    return x * x * (3 - 2 * x)
}
