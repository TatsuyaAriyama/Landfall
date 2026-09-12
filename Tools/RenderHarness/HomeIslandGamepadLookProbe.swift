import Foundation
import simd

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

@main
private enum HomeIslandGamepadLookProbe {
    static func main() {
        let map = HomeIslandGamepadMapping.look
        require(map(0, 0) == .zero, "A released stick moved the camera")
        require(map(0.06, -0.06) == .zero, "Resting stick noise moved the camera")
        require(map(0.10, 0) == .zero, "The dead-zone boundary moved the camera")
        require(
            simd_length(map(0.1001, 0)) < 0.001,
            "Camera speed jumped abruptly when the stick left the dead zone"
        )

        // The old per-axis threshold discarded (0.09, 0.09), despite having
        // more deflection than a horizontal input that already moved the view.
        let diagonal = map(0.09, 0.09)
        let sameRadius = map(sqrt(0.09 * 0.09 * 2), 0)
        require(simd_length(diagonal) > 0, "Fine diagonal camera adjustment was lost")
        require(
            abs(simd_length(diagonal) - simd_length(sameRadius)) < 0.00001,
            "Camera response depended on stick direction"
        )

        for directionIndex in 0..<16 {
            let angle = Float(directionIndex) * .pi / 8
            let direction = SIMD2<Float>(cos(angle), sin(angle))
            var previousStrength: Float = 0
            for step in 0...100 {
                let stick = direction * Float(step) / 100
                let look = map(stick.x, stick.y)
                let strength = simd_length(look)
                require(strength + 0.00001 >= previousStrength, "Camera response reversed")
                require(strength <= 1.00001, "Camera response exceeded full deflection")
                if strength > 0.00001 {
                    require(
                        simd_dot(look / strength, direction) > 0.99999,
                        "Camera input changed the intended direction"
                    )
                }
                previousStrength = strength
            }
            require(abs(previousStrength - 1) < 0.00001, "Full camera speed was reduced")
        }

        require(
            abs(simd_length(map(1, 1)) - simd_length(map(1, 0))) < 0.00001,
            "Full diagonal input moved the camera faster than full horizontal input"
        )
        require(map(.nan, 0) == .zero, "Invalid input reached the camera")
        require(map(0, .infinity) == .zero, "Non-finite input reached the camera")
        print("PASS camera stick noise, continuous onset, radial response, direction, and speed limit")
    }
}
