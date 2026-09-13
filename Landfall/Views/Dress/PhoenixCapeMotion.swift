import Foundation

/// Continuous cloth motion shared by the island and the navigator on board.
/// Wind changes the rate of an integrated phase, never the phase's position.
struct PhoenixCapeMotion {
    private var accumulatedPhase: Double = 0
    private var previousHeading: Float?
    private(set) var wind: Float = 1
    private(set) var lateral: Float = 0
    var phase: Float { Float(accumulatedPhase) }

    mutating func step(
        dt: Float,
        poseWind: Float,
        speed: Float?,
        heading: Float?
    ) {
        guard dt.isFinite, dt > 0 else { return }
        let delta = min(dt, 0.1)
        let base = poseWind.isFinite ? min(1.7, max(0, poseWind)) : 1
        let travel = speed.map { $0.isFinite ? min(1, max(0, $0)) : 0 }
        // Walking used to add 2.1 on top of the pose's 1.7: more than twice
        // the shipboard breeze. Keep a light airflow, with a modest travel lift.
        let targetWind = travel.map { min(base, 1) + $0 * 0.55 } ?? base
        let oldWind = wind
        wind += (targetWind - wind) * (1 - exp(-2.8 * delta))
        accumulatedPhase += Double(delta) * (0.7 + 0.3 * Double((oldWind + wind) * 0.5))
        // Every wave frequency is a multiple of 0.1; this is their common
        // period, so wrapping stays seamless even through an all-day session.
        accumulatedPhase.formTruncatingRemainder(dividingBy: 20 * .pi)

        var targetLateral: Float = 0
        if let heading, heading.isFinite {
            if let previousHeading, travel != nil, dt < 0.1 {
                let angle = atan2(sin(heading - previousHeading), cos(heading - previousHeading))
                let angularSpeed = min(3, max(-3, angle / delta))
                targetLateral = angularSpeed * 0.018 * (travel ?? 0)
            }
            previousHeading = heading
        } else {
            previousHeading = nil
        }
        // The free hem trails a turn and settles after it; the shoulders stay
        // attached. A pause/resume never injects an accumulated turn impulse.
        lateral += (targetLateral - lateral) * (1 - exp(-3.2 * delta))
    }
}
