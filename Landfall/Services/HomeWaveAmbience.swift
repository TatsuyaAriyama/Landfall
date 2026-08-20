import AVFoundation
import Combine

/// タイマー外の画面で、代表BGMと独立して重ねられる静かな波音。
@MainActor
final class HomeWaveAmbience: ObservableObject {
    static let shared = HomeWaveAmbience()
    static let enabledKey = "home.waveAmbienceEnabled"

    @Published private(set) var isPlaying = false
    @Published private(set) var playbackFailed = false

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var configured = false
    private var fadeTask: Task<Void, Never>?
    private var playbackRequested = false
    private var playbackGeneration: UInt = 0
    /// BGMの下へ薄く敷くだけの音量。波形の正規化前と同じ静けさ(実効ピーク約0.019)。
    private let targetVolume: Float = WaveSound.volume(forOutputPeak: 0.019)

    private init() {
        WaveSound.prewarm()
    }

    func play() {
        playbackRequested = true
        playbackGeneration &+= 1
        let generation = playbackGeneration
        fadeTask?.cancel()
        playbackFailed = false
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? session.setPreferredSampleRate(44_100)
            try session.setActive(true)
            try configureIfNeeded()

            guard let buffer = WaveSound.buffer(whenReady: { [weak self] in
                guard let self, self.playbackRequested else { return }
                self.play()
            }) else {
                isPlaying = false
                return
            }
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            if !player.isPlaying {
                player.volume = 0
                player.scheduleBuffer(buffer, at: nil, options: [.loops])
                player.play()
            }
            isPlaying = player.isPlaying && engine.isRunning
            playbackFailed = !isPlaying
            if isPlaying {
                fadeVolume(to: targetVolume, duration: 0.6, generation: generation)
            }
        } catch {
            failPlayback()
        }
    }

    /// 共有AudioSessionはBGMやタイマー音が続けて使えるよう無効化しない。
    func stop() {
        playbackRequested = false
        playbackGeneration &+= 1
        let generation = playbackGeneration
        fadeTask?.cancel()
        isPlaying = false
        playbackFailed = false

        guard player.isPlaying, engine.isRunning else {
            player.stop()
            engine.stop()
            player.volume = 0
            return
        }
        fadeOutAndStop(generation: generation)
    }

    private func fadeVolume(to target: Float, duration: TimeInterval, generation: UInt) {
        fadeTask?.cancel()
        let start = player.volume
        let steps = max(1, Int(duration * 50))
        fadeTask = Task { [weak self] in
            guard let self else { return }
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000) / UInt64(steps))
                guard !Task.isCancelled,
                      self.playbackGeneration == generation,
                      self.playbackRequested else { return }
                let linear = Float(step) / Float(steps)
                let eased = linear * linear * (3 - 2 * linear)
                self.player.volume = start + (target - start) * eased
            }
            self.fadeTask = nil
        }
    }

    private func fadeOutAndStop(generation: UInt) {
        let start = player.volume
        let duration = 0.35
        let steps = 18
        fadeTask = Task { [weak self] in
            guard let self else { return }
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000) / UInt64(steps))
                guard !Task.isCancelled,
                      self.playbackGeneration == generation,
                      !self.playbackRequested else { return }
                let linear = Float(step) / Float(steps)
                let eased = linear * linear * (3 - 2 * linear)
                self.player.volume = start * (1 - eased)
            }
            guard self.playbackGeneration == generation, !self.playbackRequested else { return }
            self.player.stop()
            self.engine.stop()
            self.player.volume = 0
            self.fadeTask = nil
        }
    }

    private func failPlayback() {
        fadeTask?.cancel()
        player.stop()
        engine.stop()
        player.volume = 0
        isPlaying = false
        playbackFailed = true
    }

    private func configureIfNeeded() throws {
        guard !configured else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        configured = true
    }
}
