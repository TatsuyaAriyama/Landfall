import AVFoundation
import Foundation

/// A scene-scoped audio controller for locomotion. Footsteps use a small voice
/// pool so consecutive plants never cut each other off; wind owns a separate
/// looping voice and mixes with the existing music and wave ambience.
final class HomeIslandLocomotionAudio {
    private let queue = DispatchQueue(label: "com.landfall.home-island-locomotion-audio")
    private let engine = AVAudioEngine()
    private let windPlayer = AVAudioPlayerNode()
    private let stepPlayers = (0..<4).map { _ in AVAudioPlayerNode() }
    private var stepBuffers: [HomeIslandGroundSurface: [AVAudioPCMBuffer]] = [:]
    private var windBuffer: AVAudioPCMBuffer?
    private var nextVoice = 0
    private var nextVariant: [HomeIslandGroundSurface: Int] = [:]
    private var started = false
    private var windScheduled = false
    private let sampleRate: Double = 44_100

    init() {
        queue.async { [weak self] in self?.prepare() }
    }

    func playFootstep(surface: HomeIslandGroundSurface, intensity: Float) {
        queue.async { [weak self] in
            guard let self else { return }
            self.prepare()
            guard self.started, let variants = self.stepBuffers[surface], !variants.isEmpty else {
                return
            }
            let variant = self.nextVariant[surface, default: 0] % variants.count
            self.nextVariant[surface] = variant + 1
            let player = self.stepPlayers[self.nextVoice % self.stepPlayers.count]
            self.nextVoice += 1
            player.volume = min(max(0.16 + intensity * 0.32, 0.12), 0.48)
            if !player.isPlaying { player.play() }
            player.scheduleBuffer(variants[variant], at: nil, options: [], completionHandler: nil)
        }
    }

    func setWindIntensity(_ intensity: Float) {
        queue.async { [weak self] in
            guard let self else { return }
            self.prepare()
            guard self.started else { return }
            if !self.windScheduled, let windBuffer = self.windBuffer {
                self.windScheduled = true
                self.windPlayer.scheduleBuffer(
                    windBuffer,
                    at: nil,
                    options: .loops,
                    completionHandler: nil
                )
                self.windPlayer.play()
            }
            // Kept deliberately below the wave ambience; it should be felt
            // only near full sprint rather than becoming a constant hiss.
            self.windPlayer.volume = min(max(intensity, 0), 1) * 0.085
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.windPlayer.volume = 0
            self.stepPlayers.forEach { $0.stop() }
        }
    }

    private func prepare() {
        guard !started else { return }
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        ) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            engine.attach(windPlayer)
            engine.connect(windPlayer, to: engine.mainMixerNode, format: format)
            for player in stepPlayers {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
            }
            stepBuffers = Dictionary(
                uniqueKeysWithValues: HomeIslandGroundSurface.allCases.map { surface in
                    (surface, (0..<3).compactMap {
                        makeStepBuffer(surface: surface, variant: $0, format: format)
                    })
                }
            )
            windBuffer = makeWindBuffer(format: format)
            try engine.start()
            started = true
        } catch {
            engine.stop()
            started = false
        }
    }

    private func makeStepBuffer(
        surface: HomeIslandGroundSurface,
        variant: Int,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let duration: Double = surface == .sand || surface == .grass ? 0.16 : 0.12
        let frames = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frames
        var seed = UInt32(0xA341_316C &+ UInt32(variant * 977))
            &+ UInt32(surfaceIndex(surface) * 7_919)
        var smoothedNoise: Float = 0
        for frame in 0..<Int(frames) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Float(Int32(bitPattern: seed)) / Float(Int32.max)
            let time = Double(frame) / sampleRate
            let attack = min(time / 0.008, 1)
            let envelope = Float(attack * exp(-time / (duration * 0.28)))
            let value: Float
            switch surface {
            case .sand:
                smoothedNoise += (noise - smoothedNoise) * 0.20
                value = smoothedNoise * 0.58 + noise * 0.08
            case .grass:
                smoothedNoise += (noise - smoothedNoise) * 0.11
                value = smoothedNoise * 0.48
            case .wood, .boat:
                let frequency = 155.0 + Double(variant) * 17
                value = Float(sin(2 * .pi * frequency * time)) * 0.70 + noise * 0.12
            case .stone:
                let frequency = 720.0 + Double(variant) * 95
                value = Float(sin(2 * .pi * frequency * time)) * 0.48 + noise * 0.20
            }
            channel[frame] = value * envelope * 0.62
        }
        return buffer
    }

    private func makeWindBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let duration: Double = 3.2
        let frames = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frames
        var seed: UInt32 = 0xC801_3EA4
        var low: Float = 0
        var band: Float = 0
        for frame in 0..<Int(frames) {
            seed = seed &* 1_103_515_245 &+ 12_345
            let noise = Float(Int32(bitPattern: seed)) / Float(Int32.max)
            low += (noise - low) * 0.018
            band += ((noise - low) - band) * 0.035
            let phase = Float(frame) / Float(max(Int(frames) - 1, 1))
            let loopCrossfade = min(min(phase / 0.08, (1 - phase) / 0.08), 1)
            channel[frame] = band * 0.72 * max(loopCrossfade, 0)
        }
        return buffer
    }

    private func surfaceIndex(_ surface: HomeIslandGroundSurface) -> Int {
        switch surface {
        case .sand: 0
        case .grass: 1
        case .stone: 2
        case .wood: 3
        case .boat: 4
        }
    }

    deinit {
        engine.stop()
    }
}
