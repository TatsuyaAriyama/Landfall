import AVFoundation

/// 短い効果音。Web audio.ts の playPlink を移植。
/// ステップ達成の反転・船タップなどで、澄んだ小さな音(G5)を鳴らす。
/// BGM とは別系統(こちらは常に鳴らしてよい単発音)。
enum SoundFX {
    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static var started = false
    private static var plinkBuffer: AVAudioPCMBuffer?
    /// 連打の間引き(Web: 180ms)。
    private static var lastPlink: TimeInterval = 0

    private static let sampleRate: Double = 44_100

    private static func setup() {
        guard !started else { return }
        started = true
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        plinkBuffer = makePlinkBuffer(format: format)
        // 単発音なので、鳴らせないとき(サイレント等)は静かに諦める。
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try engine.start()
        } catch {
            started = false
        }
    }

    /// G5(783.99Hz)のサイン波を指数減衰で。Web playPlink: 0.015s立上→0.65s減衰, gain 0.13。
    private static func makePlinkBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let duration = 0.66
        let frames = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let ch = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        let freq = 783.99
        let attack = 0.015
        let peak: Float = 0.13
        for n in 0..<Int(frames) {
            let t = Double(n) / sampleRate
            // 立ち上がり(線形)→ 指数減衰(0.65s で ~0)。
            let env: Double
            if t < attack {
                env = t / attack
            } else {
                env = exp(-(t - attack) / 0.12)
            }
            ch[n] = Float(sin(2 * .pi * freq * t)) * peak * Float(env)
        }
        return buffer
    }

    /// 澄んだ小さな音。連打は 180ms 間引き。
    static func plink() {
        setup()
        guard started, let buffer = plinkBuffer else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPlink > 0.18 else { return }
        lastPlink = now
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }
}
