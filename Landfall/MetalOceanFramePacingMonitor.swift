import Foundation

/// Samples sustained frame pacing without reacting to isolated hitches or
/// background gaps. A renderer can use the signal to lower only raster cost
/// while preserving the same ocean shader and visual composition.
struct MetalOceanFramePacingMonitor {
    private var sampleStart: TimeInterval?
    private var previousFrame: TimeInterval?
    private var frameCount = 0
    private var slowFrameCount = 0
    private var hasSignaledThermalPressure = false

    mutating func reset() {
        sampleStart = nil
        previousFrame = nil
        frameCount = 0
        slowFrameCount = 0
        hasSignaledThermalPressure = false
    }

    /// Returns true when at least 35% of a sustained sample falls below 75%
    /// of the scene's intended frame rate. Passing the target prevents an
    /// intentionally cinematic 30 fps scene from being treated as overloaded.
    mutating func observe(
        at time: TimeInterval,
        targetFramesPerSecond: Int = 60
    ) -> Bool {
        if isUnderSeriousThermalPressure {
            guard !hasSignaledThermalPressure else { return false }
            reset()
            hasSignaledThermalPressure = true
            return true
        }
        hasSignaledThermalPressure = false

        guard let previousFrame else {
            sampleStart = time
            self.previousFrame = time
            return false
        }
        let interval = time - previousFrame
        self.previousFrame = time
        guard interval > 0, interval < 0.25 else {
            reset()
            return false
        }

        frameCount += 1
#if DEBUG
        let simulatesOverload = UserDefaults.standard.bool(
            forKey: "LandfallMetalSimulateOverload"
        )
#else
        let simulatesOverload = false
#endif
        let target = Double(max(targetFramesPerSecond, 1))
        let slowFrameInterval = 1.0 / (target * 0.75)
        if simulatesOverload || interval > slowFrameInterval {
            slowFrameCount += 1
        }

        let duration = time - (sampleStart ?? time)
        guard duration >= 8, frameCount >= 60 else { return false }
        let overloaded = Double(slowFrameCount) / Double(frameCount) >= 0.35
        reset()
        return overloaded
    }

    private var isUnderSeriousThermalPressure: Bool {
#if DEBUG
        if UserDefaults.standard.bool(forKey: "LandfallMetalSimulateThermalPressure") {
            return true
        }
#endif
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            return true
        default:
            return false
        }
    }
}
