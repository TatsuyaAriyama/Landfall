import Foundation
import simd

/// CPU representation of the native Metal ocean's displaced wave surface.
/// Keep its spectrum and shaping constants identical to `landfallSampleWaves`.
enum OceanWaveSpectrum {
    struct Sample {
        let height: Float
        let slope: SIMD2<Float>
    }

    static func sample(
        at position: SIMD2<Float>,
        time: Float,
        amplitudeScale: Float
    ) -> Sample {
        var phases = waves.map { wave in
            simd_dot(position, wave.direction) * wave.waveNumber
                - time * wave.angularSpeed
                + wave.phaseOffset
        }
        let sinC = sin(phases[2])
        let sinD = sin(phases[3])
        let sinE = sin(phases[4])
        let cosC = cos(phases[2])
        let cosD = cos(phases[3])
        let cosE = cos(phases[4])
        let warpDirectionF = SIMD2<Float>(-0.940, 0.342)
        let warpDirectionG = SIMD2<Float>(0.515, 0.857)
        let warpDirectionH = SIMD2<Float>(0.118, -0.993)
        let warpDirectionI = SIMD2<Float>(0.982, 0.190)
        let phaseF = simd_dot(position, warpDirectionF) * 0.052
            - time * 0.14 + 0.30
        let phaseG = simd_dot(position, warpDirectionG) * 0.073
            - time * 0.19 + 1.35
        let phaseH = simd_dot(position, warpDirectionH) * 0.310
            - time * 0.27 + 2.20
        let phaseI = simd_dot(position, warpDirectionI) * 0.470
            - time * 0.39 + 0.60
        let cosF = cos(phaseF)
        let cosG = cos(phaseG)
        let sinH = sin(phaseH)
        let sinI = sin(phaseI)
        let cosH = cos(phaseH)
        let cosI = cos(phaseI)
        phases[0] += sinC * 0.20 + sinD * 0.05
            + sin(phaseF) * 0.45 + sinH * 0.08 + sinI * 0.04
        phases[1] += -sinD * 0.12 + sinE * 0.04
            - sin(phaseG) * 0.36 - sinH * 0.05 + sinI * 0.06

        let cosA = cos(phases[0])
        let cosB = cos(phases[1])
        let harmonicPhaseA = phases[0] * 2 + 0.35
        let harmonicPhaseB = phases[1] * 2 - 0.62
        let shapedA = sin(phases[0]) + sin(harmonicPhaseA) * 0.18
        let shapedB = sin(phases[1]) + sin(harmonicPhaseB) * 0.13
        let shapedDerivativeA = cosA + cos(harmonicPhaseA) * 0.36
        let shapedDerivativeB = cosB + cos(harmonicPhaseB) * 0.26
        let energyPhaseA = phaseF + 1.17
        let energyPhaseB = phaseG - 0.83
        let energyA = 1 + sin(energyPhaseA) * 0.18
        let energyB = 1 + sin(energyPhaseB) * 0.14
        let energyGradientA = warpDirectionF
            * (cos(energyPhaseA) * 0.052 * 0.18)
        let energyGradientB = warpDirectionG
            * (cos(energyPhaseB) * 0.073 * 0.14)
        var phaseGradientA = waves[0].direction * waves[0].waveNumber
        phaseGradientA += waves[2].direction * (cosC * 0.340 * 0.20)
        phaseGradientA += waves[3].direction * (cosD * 0.720 * 0.05)
        phaseGradientA += warpDirectionF * (cosF * 0.052 * 0.45)
        phaseGradientA += warpDirectionH * (cosH * 0.310 * 0.08)
        phaseGradientA += warpDirectionI * (cosI * 0.470 * 0.04)
        var phaseGradientB = waves[1].direction * waves[1].waveNumber
        phaseGradientB -= waves[3].direction * (cosD * 0.720 * 0.12)
        phaseGradientB += waves[4].direction * (cosE * 1.250 * 0.04)
        phaseGradientB -= warpDirectionG * (cosG * 0.073 * 0.36)
        phaseGradientB -= warpDirectionH * (cosH * 0.310 * 0.05)
        phaseGradientB += warpDirectionI * (cosI * 0.470 * 0.06)
        let phaseGradients = [
            phaseGradientA,
            phaseGradientB,
            waves[2].direction * waves[2].waveNumber,
            waves[3].direction * waves[3].waveNumber,
            waves[4].direction * waves[4].waveNumber,
        ]

        var height = shapedA * waves[0].amplitude * energyA
            + shapedB * waves[1].amplitude * energyB
        let slopeA = phaseGradientA
                * (shapedDerivativeA * waves[0].amplitude * energyA)
            + energyGradientA * (shapedA * waves[0].amplitude)
        let slopeB = phaseGradientB
                * (shapedDerivativeB * waves[1].amplitude * energyB)
            + energyGradientB * (shapedB * waves[1].amplitude)
        var slope = slopeA + slopeB
        let sines = [sinC, sinD, sinE]
        let cosines = [cosC, cosD, cosE]
        for index in 2..<waves.count {
            let localIndex = index - 2
            height += sines[localIndex] * waves[index].amplitude
            slope += phaseGradients[index]
                * (cosines[localIndex] * waves[index].amplitude)
        }
        return Sample(
            height: height * amplitudeScale,
            slope: slope * amplitudeScale
        )
    }

    private struct Wave {
        let direction: SIMD2<Float>
        let waveNumber: Float
        let angularSpeed: Float
        let phaseOffset: Float
        let amplitude: Float
    }

    private static let waves = [
        Wave(direction: SIMD2(0.342, 0.940), waveNumber: 0.105,
             angularSpeed: 0.42, phaseOffset: 0, amplitude: 0.171),
        Wave(direction: SIMD2(-0.766, 0.643), waveNumber: 0.155,
             angularSpeed: 0.36, phaseOffset: 1.70, amplitude: 0.104),
        Wave(direction: SIMD2(0.906, 0.423), waveNumber: 0.340,
             angularSpeed: 0.78, phaseOffset: 0.45, amplitude: 0.052),
        Wave(direction: SIMD2(-0.259, 0.966), waveNumber: 0.720,
             angularSpeed: 1.22, phaseOffset: 2.10, amplitude: 0.020),
        Wave(direction: SIMD2(0.643, -0.766), waveNumber: 1.250,
             angularSpeed: 1.68, phaseOffset: 0.90, amplitude: 0.006),
    ]
}
