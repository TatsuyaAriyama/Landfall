import Foundation
import simd

private enum ProbeFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case let .assertion(message): message
        }
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw ProbeFailure.assertion(message) }
}

private func flatGround(_ x: Float, _ z: Float) -> HomeIslandGroundSample {
    _ = x
    _ = z
    return HomeIslandGroundSample(height: 0)
}

private func runFlat(rate: Int, seconds: Float, input: HomeIslandWalkInput) -> HomeIslandLocomotionFrame {
    runFlat(deltas: Array(
        repeating: 1 / Float(rate),
        count: Int(Float(rate) * seconds)
    ), input: input)
}

private func runFlat(
    deltas: [Float],
    input: HomeIslandWalkInput
) -> HomeIslandLocomotionFrame {
    let tuning = HomeIslandLocomotionTuning()
    let motor = HomeIslandLocomotionMotor(tuning: tuning)
    var frame = HomeIslandLocomotionFrame.idle(position: .zero, yaw: 0)
    for delta in deltas {
        frame = motor.update(
            input: input,
            position: frame.position,
            currentYaw: frame.facingYaw,
            cameraForward: SIMD2<Float>(0, 1),
            cameraRight: SIMD2<Float>(1, 0),
            deltaTime: delta,
            sampleGround: flatGround,
            canOccupy: { _, _ in true }
        )
    }
    return frame
}

@main
private enum HomeIslandLocomotionProbe {
    static func main() throws {
        let sprintInput = HomeIslandWalkInput(
            x: 0,
            forward: 1,
            sprintRequested: true
        )
        let rates = [15, 30, 60, 120]
        let distances = rates.map {
            runFlat(rate: $0, seconds: 3, input: sprintInput).position.z
        }
        try require(
            (distances.max() ?? 0) - (distances.min() ?? 0) < 0.08,
            "15/30/60/120 Hz sprint distance diverged: \(distances)"
        )
        let hitchDeltas = Array(repeating: Float(1) / 60, count: 84)
            + [Float(0.20)]
            + Array(repeating: Float(1) / 60, count: 84)
        let hitchDistance = runFlat(deltas: hitchDeltas, input: sprintInput).position.z
        let sixtyHzDistance = distances[rates.firstIndex(of: 60)!]
        try require(
            abs(hitchDistance - sixtyHzDistance) < 0.03,
            "200 ms hitch discarded elapsed movement: \(hitchDistance) vs \(sixtyHzDistance)"
        )

        let tuning = HomeIslandLocomotionTuning()
        let accelerationMotor = HomeIslandLocomotionMotor(tuning: tuning)
        var accelerationFrame = accelerationMotor.update(
            input: sprintInput,
            position: .zero,
            currentYaw: 0,
            cameraForward: SIMD2<Float>(0, 1),
            cameraRight: SIMD2<Float>(1, 0),
            deltaTime: 1 / 60,
            sampleGround: flatGround,
            canOccupy: { _, _ in true }
        )
        try require(
            accelerationFrame.planarSpeed < tuning.sprintSpeed * 0.20,
            "sprint reached top speed on the first frame"
        )
        for _ in 0..<90 {
            accelerationFrame = accelerationMotor.update(
                input: sprintInput,
                position: accelerationFrame.position,
                currentYaw: accelerationFrame.facingYaw,
                cameraForward: SIMD2<Float>(0, 1),
                cameraRight: SIMD2<Float>(1, 0),
                deltaTime: 1 / 60,
                sampleGround: flatGround,
                canOccupy: { _, _ in true }
            )
        }
        let speedBeforeStop = accelerationFrame.planarSpeed
        for _ in 0..<30 {
            accelerationFrame = accelerationMotor.update(
                input: .zero,
                position: accelerationFrame.position,
                currentYaw: accelerationFrame.facingYaw,
                cameraForward: SIMD2<Float>(0, 1),
                cameraRight: SIMD2<Float>(1, 0),
                deltaTime: 1 / 60,
                sampleGround: flatGround,
                canOccupy: { _, _ in true }
            )
        }
        try require(speedBeforeStop > tuning.jogSpeed, "sprint never reached running speed")
        try require(accelerationFrame.planarSpeed < 0.08, "release braking remained too heavy")

        let turnMotor = HomeIslandLocomotionMotor(tuning: tuning)
        var turnFrame = HomeIslandLocomotionFrame.idle(position: .zero, yaw: 0)
        for _ in 0..<100 {
            turnFrame = turnMotor.update(
                input: sprintInput,
                position: turnFrame.position,
                currentYaw: turnFrame.facingYaw,
                cameraForward: SIMD2<Float>(0, 1),
                cameraRight: SIMD2<Float>(1, 0),
                deltaTime: 1 / 60,
                sampleGround: flatGround,
                canOccupy: { _, _ in true }
            )
        }
        var minimumTurnSpeed = turnFrame.planarSpeed
        for _ in 0..<80 {
            turnFrame = turnMotor.update(
                input: HomeIslandWalkInput(forward: -1, sprintRequested: true),
                position: turnFrame.position,
                currentYaw: turnFrame.facingYaw,
                cameraForward: SIMD2<Float>(0, 1),
                cameraRight: SIMD2<Float>(1, 0),
                deltaTime: 1 / 60,
                sampleGround: flatGround,
                canOccupy: { _, _ in true }
            )
            minimumTurnSpeed = min(minimumTurnSpeed, turnFrame.planarSpeed)
        }
        try require(
            minimumTurnSpeed < tuning.walkSpeed,
            "180-degree turn did not plant/brake: minimum \(minimumTurnSpeed)"
        )
        try require(turnFrame.velocity.z < 0, "180-degree turn never reversed travel")

        func simulateSlope(_ slope: Float) -> Float {
            let motor = HomeIslandLocomotionMotor(tuning: tuning)
            var frame = HomeIslandLocomotionFrame.idle(position: .zero, yaw: 0)
            let normal = simd_normalize(SIMD3<Float>(0, 1, -slope))
            for _ in 0..<120 {
                frame = motor.update(
                    input: HomeIslandWalkInput(forward: 0.72),
                    position: frame.position,
                    currentYaw: frame.facingYaw,
                    cameraForward: SIMD2<Float>(0, 1),
                    cameraRight: SIMD2<Float>(1, 0),
                    deltaTime: 1 / 60,
                    sampleGround: { _, z in
                        HomeIslandGroundSample(height: z * slope, normal: normal)
                    },
                    canOccupy: { _, _ in true }
                )
            }
            return frame.position.z
        }
        let flatDistance = simulateSlope(0)
        let uphillDistance = simulateSlope(0.34)
        try require(uphillDistance < flatDistance, "uphill speed was not reduced")

        let stepMotor = HomeIslandLocomotionMotor(tuning: tuning)
        var stepFrame = HomeIslandLocomotionFrame.idle(position: .zero, yaw: 0)
        for _ in 0..<120 {
            stepFrame = stepMotor.update(
                input: HomeIslandWalkInput(forward: 0.72),
                position: stepFrame.position,
                currentYaw: stepFrame.facingYaw,
                cameraForward: SIMD2<Float>(0, 1),
                cameraRight: SIMD2<Float>(1, 0),
                deltaTime: 1 / 60,
                sampleGround: { _, z in
                    HomeIslandGroundSample(height: z > 0.8 ? 0.20 : 0)
                },
                canOccupy: { _, _ in true }
            )
        }
        try require(stepFrame.position.z > 0.9, "walkable step blocked traversal")
        try require(abs(stepFrame.position.y - 0.20) < 0.001, "step lost ground contact")

        let stepGround: HomeIslandLocomotionMotor.GroundSampler = { _, z in
            HomeIslandGroundSample(height: z >= 0.80 ? 0.20 : 0)
        }
        let visualStepMotor = HomeIslandLocomotionMotor(tuning: tuning)
        var visualStepFrame = visualStepMotor.update(
            input: HomeIslandWalkInput(forward: 0.72),
            position: SIMD3<Float>(0, 0, 0.798),
            currentYaw: 0,
            cameraForward: SIMD2<Float>(0, 1),
            cameraRight: SIMD2<Float>(1, 0),
            deltaTime: 1 / 60,
            sampleGround: stepGround,
            canOccupy: { _, _ in true }
        )
        try require(
            abs(visualStepFrame.position.y - 0.20) < 0.001,
            "visual step offset changed authoritative grounding"
        )
        try require(
            visualStepFrame.stepOffset < -0.15
                && abs(visualStepFrame.position.y + visualStepFrame.stepOffset) < 0.015,
            "step did not preserve the pre-step rendered height: \(visualStepFrame.stepOffset)"
        )
        for _ in 0..<30 {
            visualStepFrame = visualStepMotor.update(
                input: .zero,
                position: visualStepFrame.position,
                currentYaw: visualStepFrame.facingYaw,
                cameraForward: SIMD2<Float>(0, 1),
                cameraRight: SIMD2<Float>(1, 0),
                deltaTime: 1 / 60,
                sampleGround: stepGround,
                canOccupy: { _, _ in true }
            )
        }
        try require(
            abs(visualStepFrame.stepOffset) < 0.01,
            "visual step offset did not decay: \(visualStepFrame.stepOffset)"
        )

        let stepJumpMotor = HomeIslandLocomotionMotor(tuning: tuning)
        let stepJumpFrame = stepJumpMotor.update(
            input: HomeIslandWalkInput(forward: 0.72, jumpRequested: true),
            position: SIMD3<Float>(0, 0, 0.798),
            currentYaw: 0,
            cameraForward: SIMD2<Float>(0, 1),
            cameraRight: SIMD2<Float>(1, 0),
            deltaTime: 1 / 60,
            sampleGround: stepGround,
            canOccupy: { _, _ in true }
        )
        try require(stepJumpFrame.didJump, "step+jump did not expose its takeoff event")
        try require(
            stepJumpFrame.position.y > 0.26,
            "step+jump launched below the new ground: \(stepJumpFrame.position.y)"
        )
        try require(
            stepJumpFrame.position.y + stepJumpFrame.stepOffset > 0.05,
            "step+jump visual offset cancelled the ballistic takeoff"
        )

        let highFloorHeight: Float = 1.20
        let highFloorStart: Float = 0.30
        let highFloor: HomeIslandLocomotionMotor.GroundSampler = { _, z in
            HomeIslandGroundSample(height: z >= highFloorStart ? highFloorHeight : 0)
        }
        let highFloorMotor = HomeIslandLocomotionMotor(tuning: tuning)
        var highFloorFrame = HomeIslandLocomotionFrame.idle(position: .zero, yaw: 0)
        var landedOnHighFloor = false
        for frameIndex in 0..<180 {
            highFloorFrame = highFloorMotor.update(
                input: HomeIslandWalkInput(
                    forward: 0.72,
                    jumpRequested: frameIndex < 4
                ),
                position: highFloorFrame.position,
                currentYaw: highFloorFrame.facingYaw,
                cameraForward: SIMD2<Float>(0, 1),
                cameraRight: SIMD2<Float>(1, 0),
                deltaTime: 1 / 60,
                sampleGround: highFloor,
                canOccupy: { _, _ in true }
            )
            landedOnHighFloor = landedOnHighFloor
                || highFloorFrame.didLand && highFloorFrame.position.y > 1
        }
        try require(
            highFloorFrame.position.z < highFloorStart + 0.02,
            "airborne movement entered a floor above the feet: \(highFloorFrame.position)"
        )
        try require(!landedOnHighFloor, "airborne movement snapped upward onto a high floor")

        let underFloorMotor = HomeIslandLocomotionMotor(tuning: tuning)
        let underFloorStart = SIMD3<Float>(0, 0.80, 0.50)
        underFloorMotor.reset(position: underFloorStart, yaw: 0, grounded: false)
        let underFloorFrame = underFloorMotor.update(
            input: .zero,
            position: underFloorStart,
            currentYaw: 0,
            cameraForward: SIMD2<Float>(0, 1),
            cameraRight: SIMD2<Float>(1, 0),
            deltaTime: 0.20,
            sampleGround: highFloor,
            canOccupy: { _, _ in true }
        )
        try require(
            !underFloorFrame.didLand && underFloorFrame.position.y < underFloorStart.y,
            "descending character below a floor was absorbed upward: \(underFloorFrame.position.y)"
        )

        let jumpMotor = HomeIslandLocomotionMotor(tuning: tuning)
        var jumpFrame = HomeIslandLocomotionFrame.idle(position: .zero, yaw: 0)
        var maximumY: Float = 0
        var sawAirborne = false
        var sawLanding = false
        var sawJump = false
        for frameIndex in 0..<180 {
            jumpFrame = jumpMotor.update(
                input: HomeIslandWalkInput(
                    forward: 0.72,
                    jumpRequested: frameIndex < 4
                ),
                position: jumpFrame.position,
                currentYaw: jumpFrame.facingYaw,
                cameraForward: SIMD2<Float>(0, 1),
                cameraRight: SIMD2<Float>(1, 0),
                deltaTime: 1 / 60,
                sampleGround: flatGround,
                canOccupy: { _, _ in true }
            )
            maximumY = max(maximumY, jumpFrame.position.y)
            sawAirborne = sawAirborne || !jumpFrame.isGrounded
            sawLanding = sawLanding || jumpFrame.didLand
            sawJump = sawJump || jumpFrame.didJump
        }
        try require(sawJump, "jump event was not surfaced by the locomotion frame")
        try require(sawAirborne && maximumY > 0.55, "jump never became airborne")
        try require(sawLanding && jumpFrame.isGrounded, "jump never landed")
        try require(abs(jumpFrame.position.y) < 0.001, "landing did not snap to ground")

        let hitchJumpMotor = HomeIslandLocomotionMotor(tuning: tuning)
        let hitchJumpFrame = hitchJumpMotor.update(
            input: HomeIslandWalkInput(jumpRequested: true),
            position: .zero,
            currentYaw: 0,
            cameraForward: SIMD2<Float>(0, 1),
            cameraRight: SIMD2<Float>(1, 0),
            deltaTime: 0.20,
            sampleGround: flatGround,
            canOccupy: { _, _ in true }
        )
        try require(
            hitchJumpFrame.didJump && !hitchJumpFrame.isGrounded,
            "substeps lost an early jump event"
        )

        let mapped = HomeIslandGamepadMapping.movement(
            stickX: 0.42,
            stickY: 0.68,
            sprint: true,
            jump: true
        )
        try require(mapped.magnitude > 0.60, "gamepad analog strength was lost")
        try require(mapped.sprintRequested && mapped.jumpRequested, "gamepad actions were lost")
        let dpadMapped = HomeIslandGamepadMapping.movement(
            stickX: 0,
            stickY: 0,
            dpadX: -1,
            dpadY: 0,
            sprint: false,
            jump: false
        )
        try require(dpadMapped.x < -0.99, "gamepad d-pad fallback failed")

        print("PASS frame-rate walking/sprint: \(distances)")
        print("PASS responsive stop and weighted 180-degree turn")
        print("PASS slope, step, jump/landing, and gamepad mapping")
    }
}
