import AVFoundation
import Combine

/// Web版と同じく、音源ファイルに頼らず端末内で作る航海用の環境音。
/// 波音は低域へ丸めたノイズ、クラシックはAftide用の約2分のオリジナル曲。
@MainActor
final class HomeVoyageAudio: ObservableObject {
    static let shared = HomeVoyageAudio()

    @Published private(set) var isPlaying = false
    @Published private(set) var playbackFailed = false

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var configured = false
    private var currentMode = "off"
    private var waveBuffer: AVAudioPCMBuffer?
    private var pianoBuffer: AVAudioPCMBuffer?

    private init() {}

    func play(_ mode: String) {
        let normalized = ["waves", "piano"].contains(mode) ? mode : "off"
        if normalized == currentMode, player.isPlaying, engine.isRunning {
            isPlaying = true
            playbackFailed = false
            return
        }
        stop(deactivateSession: false)
        currentMode = normalized
        playbackFailed = false
        guard normalized != "off" else {
            deactivateAudioSession()
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            // ユーザーが明示的に選ぶBGMなので、消音スイッチで無音にならない
            // playbackを使用する。他アプリの音は止めず、Aftide側を重ねる。
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? session.setPreferredSampleRate(44_100)
            try session.setActive(true)
            try configureIfNeeded()

            let buffer: AVAudioPCMBuffer
            if normalized == "waves" {
                if waveBuffer == nil { waveBuffer = Self.makeWaveBuffer() }
                guard let waveBuffer else { return }
                buffer = waveBuffer
                player.volume = 0.34
            } else {
                if pianoBuffer == nil { pianoBuffer = Self.makePianoBuffer() }
                guard let pianoBuffer else { return }
                buffer = pianoBuffer
                player.volume = 0.38
            }
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            player.scheduleBuffer(buffer, at: nil, options: [.loops])
            player.play()
            isPlaying = player.isPlaying && engine.isRunning
            playbackFailed = !isPlaying
        } catch {
            currentMode = "off"
            player.stop()
            engine.stop()
            isPlaying = false
            playbackFailed = true
            deactivateAudioSession()
        }
    }

    func stop() {
        stop(deactivateSession: true)
    }

    private func stop(deactivateSession: Bool) {
        if player.isPlaying { player.stop() }
        if engine.isRunning { engine.stop() }
        currentMode = "off"
        isPlaying = false
        if deactivateSession {
            playbackFailed = false
            deactivateAudioSession()
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
    }

    private func configureIfNeeded() throws {
        guard !configured else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        configured = true
    }

    private static func makeWaveBuffer() -> AVAudioPCMBuffer {
        let rate = 44_100.0
        let frameCount = AVAudioFrameCount(rate * 6)
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]

        var seed: UInt64 = 0xA17D_E5EA_9234_61C7
        var low: Float = 0
        var lower: Float = 0
        for index in 0..<Int(frameCount) {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let white = Float(Int32(truncatingIfNeeded: seed >> 32)) / Float(Int32.max)
            low += (white - low) * 0.035
            lower += (low - lower) * 0.006
            let time = Float(index) / Float(rate)
            let swell = 0.56 + sin(time * 0.42) * 0.18 + sin(time * 0.71 + 1.1) * 0.12
            samples[index] = lower * swell * 2.5
        }
        normalize(samples: samples, count: Int(frameCount), peak: 0.68)
        return buffer
    }

    private static func makePianoBuffer() -> AVAudioPCMBuffer {
        let rate = 44_100.0
        let step = 0.42
        let beatsPerBar = 6
        let barDuration = step * Double(beatsPerBar)
        let bars = classicalBars()
        let duration = barDuration * Double(bars.count)
        let frameCount = AVAudioFrameCount(rate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(frameCount) { samples[index] = 0 }

        // D major / B minor、6/8。従来の冒頭4小節をそのまま主題にし、
        // 主題提示 → 展開 → 再現 → コーダの48小節(約2分)へ広げる。
        for (barIndex, bar) in bars.enumerated() {
            let barStart = Double(barIndex) * barDuration
            for (noteIndex, midi) in bar.arpeggio.enumerated() {
                let start = barStart + Double(noteIndex) * step
                addPianoTone(
                    samples: samples,
                    frameCount: Int(frameCount),
                    sampleRate: rate,
                    midi: midi,
                    start: start,
                    duration: noteIndex % 6 == 0 ? 2.25 : 1.55,
                    level: (noteIndex % 6 == 0 ? 0.12 : 0.075) * bar.dynamic
                )
            }
            // 2拍ごとの長い旋律。主題の分散和音を壊さず、後半ほど歌う。
            for (melodyIndex, midi) in bar.melody.enumerated() {
                guard let midi else { continue }
                addPianoTone(
                    samples: samples,
                    frameCount: Int(frameCount),
                    sampleRate: rate,
                    midi: midi,
                    start: barStart + Double(melodyIndex * 2) * step + 0.018,
                    duration: melodyIndex == 2 ? 2.05 : 1.72,
                    level: 0.068 * bar.dynamic
                )
            }
        }

        // 曲の奥に、ごく遠い海だけを残す。
        var seed: UInt64 = 0x5EA5_0A7D_1138_4A91
        var sea: Float = 0
        for index in 0..<Int(frameCount) {
            seed = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493
            let white = Float(Int32(truncatingIfNeeded: seed >> 32)) / Float(Int32.max)
            sea += (white - sea) * 0.018
            samples[index] = max(-0.9, min(0.9, samples[index] + sea * 0.018))
        }
        normalize(samples: samples, count: Int(frameCount), peak: 0.74)
        return buffer
    }

    private typealias ClassicalBar = (
        arpeggio: [Int],
        melody: [Int?],
        dynamic: Double
    )

    /// 48小節 = 120.96秒。最後の小節は余韻を残し、冒頭へ唐突につながらない。
    private static func classicalBars() -> [ClassicalBar] {
        let theme: [ClassicalBar] = [
            // 既存曲の冒頭。ここは音程・強弱とも変更しない。
            ([38, 50, 57, 54, 57, 50], [nil, nil, nil], 1.00),
            ([37, 49, 57, 52, 57, 49], [nil, nil, nil], 1.00),
            ([35, 47, 54, 50, 54, 47], [nil, nil, nil], 1.00),
            ([42, 54, 61, 57, 61, 54], [nil, nil, nil], 1.00),
            // 同じ主題に、遠い上声が入り始める。
            ([38, 50, 57, 62, 57, 54], [66, 69, 74], 0.94),
            ([37, 49, 56, 61, 56, 52], [64, 68, 73], 0.92),
            ([35, 47, 54, 59, 54, 50], [62, 66, 71], 0.96),
            ([42, 54, 57, 61, 66, 61], [69, 73, 78], 1.00)
        ]

        let secondTheme: [ClassicalBar] = [
            ([43, 55, 59, 62, 67, 62], [71, 74, 79], 0.92),
            ([42, 54, 57, 62, 66, 57], [69, 74, 78], 0.94),
            ([40, 52, 59, 55, 59, 52], [67, 71, 76], 0.98),
            ([35, 47, 54, 59, 62, 54], [66, 71, 74], 1.02),
            ([43, 55, 62, 59, 62, 55], [74, 71, 67], 1.04),
            ([45, 52, 61, 57, 61, 52], [73, 69, 76], 1.06),
            ([38, 50, 57, 62, 66, 57], [74, 78, 81], 1.08),
            ([45, 52, 61, 57, 64, 61], [76, 73, 69], 0.98)
        ]

        let development: [ClassicalBar] = [
            ([35, 47, 54, 59, 66, 59], [71, 74, 78], 1.02),
            ([33, 45, 52, 57, 61, 52], [69, 73, 76], 1.04),
            ([31, 43, 50, 55, 59, 50], [67, 71, 74], 1.06),
            ([38, 50, 57, 62, 69, 62], [74, 78, 81], 1.10),
            ([40, 52, 59, 64, 71, 64], [76, 79, 83], 1.12),
            ([35, 47, 54, 59, 66, 62], [74, 71, 78], 1.14),
            ([43, 55, 62, 67, 71, 62], [79, 78, 74], 1.10),
            ([45, 52, 61, 64, 69, 61], [76, 73, 69], 1.02)
        ]

        let quietPassage: [ClassicalBar] = [
            ([38, 50, 57, 54, 57, 50], [66, nil, 69], 0.78),
            ([37, 49, 56, 52, 56, 49], [64, nil, 68], 0.76),
            ([35, 47, 54, 50, 54, 47], [62, nil, 66], 0.74),
            ([42, 54, 61, 57, 61, 54], [69, nil, 73], 0.78),
            ([43, 55, 59, 62, 59, 55], [71, 74, 71], 0.82),
            ([40, 52, 59, 55, 59, 52], [67, 71, 76], 0.84),
            ([45, 52, 61, 57, 61, 52], [69, 73, 76], 0.88),
            ([45, 52, 61, 64, 69, 61], [76, 73, 69], 0.92)
        ]

        let recapitulation: [ClassicalBar] = [
            ([38, 50, 57, 54, 57, 50], [74, 69, 66], 1.02),
            ([37, 49, 57, 52, 57, 49], [73, 68, 64], 1.00),
            ([35, 47, 54, 50, 54, 47], [71, 66, 62], 1.02),
            ([42, 54, 61, 57, 61, 54], [73, 78, 76], 1.06),
            ([38, 50, 57, 62, 66, 57], [74, 78, 81], 1.10),
            ([43, 55, 62, 59, 67, 62], [79, 74, 71], 1.08),
            ([45, 52, 61, 57, 64, 61], [76, 73, 69], 1.04),
            ([45, 52, 61, 64, 69, 61], [76, 73, 78], 1.00)
        ]

        let coda: [ClassicalBar] = [
            ([43, 55, 62, 59, 67, 62], [74, 71, 67], 0.94),
            ([42, 54, 57, 62, 66, 57], [69, 74, 78], 0.92),
            ([40, 52, 59, 55, 64, 59], [76, 71, 67], 0.88),
            ([45, 52, 61, 57, 64, 61], [73, 69, 76], 0.86),
            ([38, 50, 57, 54, 62, 57], [74, 69, 66], 0.82),
            ([35, 47, 54, 50, 59, 54], [71, 66, 62], 0.76),
            ([38, 50, 57, 62, 66, 69], [74, 78, 74], 0.70),
            // 最後の和音を一度だけ置き、残りを海と減衰の余韻にする。
            ([38], [66, nil, nil], 0.62)
        ]

        return theme + secondTheme + development + quietPassage + recapitulation + coda
    }

    /// フィルタ後の波音は振幅が極端に小さくなるため、生成結果を一度だけ正規化する。
    /// プレイヤー側の音量を別に残し、集中用BGMとして過大にならない余白も確保する。
    private static func normalize(
        samples: UnsafeMutablePointer<Float>,
        count: Int,
        peak targetPeak: Float
    ) {
        guard count > 0 else { return }
        var sourcePeak: Float = 0
        for index in 0..<count {
            sourcePeak = max(sourcePeak, abs(samples[index]))
        }
        guard sourcePeak > 0.000_001 else { return }
        let gain = min(12, targetPeak / sourcePeak)
        for index in 0..<count {
            samples[index] = max(-0.95, min(0.95, samples[index] * gain))
        }
    }

    private static func addPianoTone(
        samples: UnsafeMutablePointer<Float>,
        frameCount: Int,
        sampleRate: Double,
        midi: Int,
        start: Double,
        duration: Double,
        level: Double
    ) {
        let first = max(0, Int(start * sampleRate))
        let count = min(frameCount - first, Int(duration * sampleRate))
        guard count > 0 else { return }
        let frequency = 440 * pow(2, Double(midi - 69) / 12)
        for offset in 0..<count {
            let time = Double(offset) / sampleRate
            let attack = min(1, time / 0.014)
            let decay = exp(-time * 1.75)
            let body = sin(2 * .pi * frequency * time)
            let second = sin(2 * .pi * frequency * 2.003 * time) * exp(-time * 2.8) * 0.22
            let third = sin(2 * .pi * frequency * 3.01 * time) * exp(-time * 4.2) * 0.07
            samples[first + offset] += Float((body + second + third) * attack * decay * level)
        }
    }
}
