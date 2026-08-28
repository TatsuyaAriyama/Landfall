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
        let phaseF = simd_dot(position, warpDirectionF) * 0.052
            - time * 0.14 + 0.30
        let phaseG = simd_dot(position, warpDirectionG) * 0.073
            - time * 0.19 + 1.35
        let cosF = cos(phaseF)
        let cosG = cos(phaseG)
        phases[0] += sinC * 0.34 + sinD * 0.10 + sin(phaseF) * 0.55
        phases[1] += -sinD * 0.26 + sinE * 0.08 - sin(phaseG) * 0.42

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
        let phaseGradients = [
            waves[0].direction * waves[0].waveNumber
                + waves[2].direction * (cosC * 0.340 * 0.34)
                + waves[3].direction * (cosD * 0.720 * 0.10)
                + warpDirectionF * (cosF * 0.052 * 0.55),
            waves[1].direction * waves[1].waveNumber
                - waves[3].direction * (cosD * 0.720 * 0.26)
                + waves[4].direction * (cosE * 1.250 * 0.08)
                - warpDirectionG * (cosG * 0.073 * 0.42),
            waves[2].direction * waves[2].waveNumber,
            waves[3].direction * waves[3].waveNumber,
            waves[4].direction * waves[4].waveNumber,
        ]

        var height = shapedA * waves[0].amplitude * energyA
            + shapedB * waves[1].amplitude * energyB
        var slope = phaseGradients[0]
                * (shapedDerivativeA * waves[0].amplitude * energyA)
            + energyGradientA * (shapedA * waves[0].amplitude)
            + phaseGradients[1]
                * (shapedDerivativeB * waves[1].amplitude * energyB)
            + energyGradientB * (shapedB * waves[1].amplitude)
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
