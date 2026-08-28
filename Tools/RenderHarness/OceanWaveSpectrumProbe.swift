import Foundation
import simd

@main
enum OceanWaveSpectrumProbe {
    static func main() {
        let fixtures: [Fixture] = [
            Fixture(
                position: SIMD2(0, 0), time: 0, amplitudeScale: 0.72,
                height: 0.24883008, slope: SIMD2(0.026959412, 0.016132101)
            ),
            Fixture(
                position: SIMD2(3.25, -1.75), time: 4.2, amplitudeScale: 0.72,
                height: -0.22312282, slope: SIMD2(-0.008904569, -0.009035387)
            ),
            Fixture(
                position: SIMD2(-8.5, 12.25), time: 11.8, amplitudeScale: 0.91,
                height: 0.0657505, slope: SIMD2(-0.0055370783, -0.0038195795)
            ),
            Fixture(
                position: SIMD2(18, -22), time: 29.4, amplitudeScale: 1,
                height: -0.2848109, slope: SIMD2(0.013507379, 0.015734665)
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
        verifyHullFootprintCurvature()
        print("Ocean wave spectrum parity probe: PASS")
    }

    /// The wet hull boundary retains the even (curved) part of the wave after
    /// its center tangent plane has removed height and first-order slope.
    private static func verifyHullFootprintCurvature() {
        let center = SIMD2<Float>(4.7, -3.1)
        let forward = simd_normalize(SIMD2<Float>(0.81, 0.59))
        let across = SIMD2<Float>(-forward.y, forward.x)
        let halfLength: Float = 2.15 * 0.5
        let halfBeam: Float = 0.92 * 0.5
        let time: Float = 8.4
        let amplitudeScale: Float = 0.72
        let centerSample = OceanWaveSpectrum.sample(
            at: center,
            time: time,
            amplitudeScale: amplitudeScale
        )
        let normal = simd_normalize(
            SIMD3<Float>(-centerSample.slope.x, 1, -centerSample.slope.y)
        )
        func planeResidual(at position: SIMD2<Float>) -> Float {
            let height = OceanWaveSpectrum.sample(
                at: position,
                time: time,
                amplitudeScale: amplitudeScale
            ).height
            return simd_dot(
                SIMD3(
                    position.x - center.x,
                    height - centerSample.height,
                    position.y - center.y
                ),
                normal
            )
        }
        let bowResidual = planeResidual(at: center + forward * halfLength)
        let sternResidual = planeResidual(at: center - forward * halfLength)
        let portResidual = planeResidual(at: center - across * halfBeam)
        let starboardResidual = planeResidual(at: center + across * halfBeam)
        let forwardCurvature = (bowResidual + sternResidual) * 0.5
        let acrossCurvature = (portResidual + starboardResidual) * 0.5

        require(
            abs(forwardCurvature - -0.003_363_087_8) < 0.000_002,
            "forward hull curvature fixture"
        )
        require(
            abs(acrossCurvature - -0.000_788_922_77) < 0.000_002,
            "across hull curvature fixture"
        )
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
