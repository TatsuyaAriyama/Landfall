import Foundation
import simd

@main
enum OceanWaveSpectrumProbe {
    static func main() {
        let fixtures: [Fixture] = [
            Fixture(
                position: SIMD2(0, 0), time: 0, amplitudeScale: 0.72,
                height: 0.1947447, slope: SIMD2(0.028405763, 0.020552676)
            ),
            Fixture(
                position: SIMD2(3.25, -1.75), time: 4.2, amplitudeScale: 0.72,
                height: -0.16971906, slope: SIMD2(-0.0062125865, -0.009174956)
            ),
            Fixture(
                position: SIMD2(-8.5, 12.25), time: 11.8, amplitudeScale: 0.91,
                height: 0.13555129, slope: SIMD2(-0.0126165245, -0.009528494)
            ),
            Fixture(
                position: SIMD2(18, -22), time: 29.4, amplitudeScale: 1,
                height: -0.37379995, slope: SIMD2(0.007997838, -0.0016768733)
            ),
        ]
        for fixture in fixtures {
            let sample = OceanWaveSpectrum.sample(
                at: fixture.position,
                time: fixture.time,
                amplitudeScale: fixture.amplitudeScale
            )
            require(abs(sample.height - fixture.height) < 0.000_002, "height fixture")
            require(simd_distance(sample.slope, fixture.slope) < 0.000_002, "slope fixture")
            require(
                simd_distance(sample.slope, numericalSlope(for: fixture)) < 0.000_15,
                "analytical slope"
            )
        }
        print("Ocean wave spectrum parity probe: PASS")
    }

    private static func numericalSlope(for fixture: Fixture) -> SIMD2<Float> {
        let epsilon: Float = 0.002
        let x = SIMD2<Float>(epsilon, 0)
        let y = SIMD2<Float>(0, epsilon)
        func height(at position: SIMD2<Float>) -> Float {
            OceanWaveSpectrum.sample(
                at: position,
                time: fixture.time,
                amplitudeScale: fixture.amplitudeScale
            ).height
        }
        return SIMD2(
            (height(at: fixture.position + x) - height(at: fixture.position - x))
                / (2 * epsilon),
            (height(at: fixture.position + y) - height(at: fixture.position - y))
                / (2 * epsilon)
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ label: String) {
        guard condition() else { fatalError("Ocean wave probe failed: \(label)") }
    }

    private struct Fixture {
        let position: SIMD2<Float>
        let time: Float
        let amplitudeScale: Float
        /// Golden values generated from the native Metal wave equation.
        let height: Float
        let slope: SIMD2<Float>
    }
}
