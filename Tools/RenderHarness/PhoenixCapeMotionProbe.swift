import Foundation

@main
enum PhoenixCapeMotionProbe {
    static func main() {
        var motion = PhoenixCapeMotion()
        let frame: Float = 1 / 60
        let period = Float.pi * 20
        // Wind switches after both short and hour-long sessions must have
        // the same bounded phase advance, rather than jumping with uptime.
        for index in 0..<(60 * 3_600 + 180) {
            let previous = motion.phase
            let oldWind = motion.wind
            let speed: Float = (index / 60).isMultiple(of: 2) ? 1 : 0
            motion.step(dt: frame, poseWind: speed > 0 ? 1.7 : 1, speed: speed, heading: 0)
            let advance = (motion.phase - previous + period).truncatingRemainder(dividingBy: period)
            precondition(advance > 0 && advance < 0.021, "Start/stop must never jump the cloth phase")
            precondition(motion.wind <= 1.5501 && motion.wind >= 1, "Walking breeze must stay bounded")
            precondition(abs(motion.wind - oldWind) < 0.03, "Wind must ease across speed changes")
        }

        let slow = simulate(fps: 30)
        let fast = simulate(fps: 120)
        precondition(abs(slow.phase - fast.phase) < 0.002, "Motion must not depend on display refresh rate")
        precondition(abs(slow.wind - fast.wind) < 0.0001)
        precondition(abs(slow.lateral - fast.lateral) < 0.001)

        var turning = PhoenixCapeMotion()
        for index in 0..<120 {
            turning.step(dt: frame, poseWind: 1.7, speed: 1, heading: Float(index) * frame)
        }
        precondition(turning.lateral > 0.01 && turning.lateral < 0.055, "Hem must trail a left turn")
        for index in 0..<120 {
            turning.step(dt: frame, poseWind: 1.7, speed: 1, heading: 2 - Float(index) * frame)
        }
        precondition(turning.lateral < -0.01 && turning.lateral > -0.055, "Hem must trail a right turn")
        for _ in 0..<240 { turning.step(dt: frame, poseWind: 1, speed: 0, heading: 0) }
        precondition(abs(turning.lateral) < 0.0001, "The cloth must settle after stopping")

        var wrappedHeading = PhoenixCapeMotion()
        wrappedHeading.step(dt: frame, poseWind: 1, speed: 1, heading: .pi - 0.001)
        wrappedHeading.step(dt: frame, poseWind: 1, speed: 1, heading: -.pi + 0.001)
        precondition(abs(wrappedHeading.lateral) < 0.001, "Crossing +/-pi must not whip the cape")
        wrappedHeading.step(dt: 30, poseWind: 1, speed: 1, heading: 0)
        precondition(abs(wrappedHeading.lateral) < 0.001, "Resume must not inject a turn impulse")
        wrappedHeading.step(dt: .nan, poseWind: .nan, speed: .nan, heading: .nan)
        wrappedHeading.step(dt: frame, poseWind: .nan, speed: .nan, heading: .nan)
        precondition(wrappedHeading.phase.isFinite && wrappedHeading.wind.isFinite && wrappedHeading.lateral.isFinite)

        var ship = PhoenixCapeMotion()
        for _ in 0..<600 { ship.step(dt: frame, poseWind: 1.45, speed: nil, heading: 0) }
        precondition(abs(ship.wind - 1.45) < 0.0001 && ship.lateral == 0, "Shipboard pose breeze must be preserved")
        print("PASS cape start/stop phase continuity after one hour, bounded breeze, 30/120fps parity, turn lag, settling, heading wrap, resume and shipboard motion")
    }

    private static func simulate(fps: Int) -> PhoenixCapeMotion {
        var motion = PhoenixCapeMotion()
        let dt = 1 / Float(fps)
        for index in 0..<(fps * 10) {
            motion.step(dt: dt, poseWind: 1.7, speed: 1, heading: Float(index) * dt * 0.4)
        }
        return motion
    }
}
