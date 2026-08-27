import Foundation

/// Samples sustained frame pacing without reacting to isolated hitches or
/// background gaps. A renderer can use the signal to lower only raster cost
/// while preserving the same ocean shader and visual composition.
struct MetalOceanFramePacingMonitor {
    private var sampleStart: TimeInterval?
    private var previousFrame: TimeInterval?
    private var frameCount = 0
    private var slowFrameCount = 0

    mutating func reset() {
        sampleStart = nil
        previousFrame = nil
        frameCount = 0
        slowFrameCount = 0
    }

    mutating func observe(at time: TimeInterval) -> Bool {
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
        if simulatesOverload || interval > (1.0 / 45.0) {
            slowFrameCount += 1
        }

        let duration = time - (sampleStart ?? time)
        guard duration >= 8, frameCount >= 60 else { return false }
        let overloaded = Double(slowFrameCount) / Double(frameCount) >= 0.35
        reset()
        return overloaded
    }
}
