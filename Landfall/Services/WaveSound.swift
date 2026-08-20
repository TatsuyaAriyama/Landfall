import AVFoundation

/// 海の音そのもの。生成した波形を、島に重ねる環境音と航海タイマーで共有する。
///
/// 波形づくりには数百ミリ秒かかり、31秒のステレオPCMは10MBを超える。どちらの
/// 画面でも同じ海が鳴るべきものなので、一度だけ作って両者で使い回す。
@MainActor
enum WaveSound {
    /// 波形のピーク。合成結果は必ずこの高さへ揃えるので、鳴らす側は
    /// 「どれくらいの大きさで出したいか」だけを考えればよい。
    nonisolated static let peakLevel: Float = 0.72

    /// 望む実効ピークから、プレイヤーへ設定する音量を求める。
    /// 波の実効RMSはピークのおよそ 1/7(うねりの谷は静かなため)。
    nonisolated static func volume(forOutputPeak peak: Float) -> Float {
        min(1, max(0, peak) / peakLevel)
    }

    private static var cached: AVAudioPCMBuffer?
    private static var generating = false
    private static var waiting: [() -> Void] = []

    /// 用意できていれば波形を返す。まだなら nil を返し、出来上がってから
    /// `whenReady` を呼ぶ。呼び出し側はそこで再生を要求し直す。
    static func buffer(whenReady: @escaping () -> Void) -> AVAudioPCMBuffer? {
        if let cached { return cached }
        waiting.append(whenReady)
        generateIfNeeded()
        return nil
    }

    /// 最初の再生で待たされないよう、先に作っておく。
    static func prewarm() {
        guard cached == nil else { return }
        generateIfNeeded()
    }

    private static func generateIfNeeded() {
        guard !generating else { return }
        generating = true
        Task {
            // 値型のPCM配列だけをActor間で渡す。AVAudioPCMBufferの生成と所有は
            // MainActor内で完結させる。
            let samples = await Task.detached(priority: .utility) {
                makeWaveSamples()
            }.value
            cached = makeWaveBuffer(from: samples)
            generating = false
            let pending = waiting
            waiting = []
            for resume in pending { resume() }
        }
    }

    /// Actor間を渡るのは値型のPCM配列だけに限定する。
    private struct WaveSamples: Sendable {
        let left: [Float]
        let right: [Float]
    }

    /// 再現可能な乱数。生成済みPCMだけを再生するため、再生中のCPU負荷は発生しない。
    private struct NoiseGenerator {
        var state: UInt64

        mutating func signed() -> Float {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(Int32(truncatingIfNeeded: state >> 32)) / Float(Int32.max)
        }

        mutating func unit() -> Float {
            (signed() + 1) * 0.5
        }
    }

    /// 左右で少し異なる寄せ波と泡。低域は中央に置き、定位が散りすぎないようにする。
    private struct ShoreTexture {
        var noise: NoiseGenerator
        var washLow: Float = 0
        var washFloor: Float = 0
        var foamLow: Float = 0
        var foamFloor: Float = 0
        var bubble: Float = 0
        var bubbleSmoothed: Float = 0

        mutating func sample(washEnvelope: Float, foamEnvelope: Float) -> Float {
            let washWhite = noise.signed()
            washLow += (washWhite - washLow) * 0.085
            washFloor += (washLow - washFloor) * 0.009
            let washBand = washLow - washFloor

            let foamWhite = noise.signed()
            foamLow += (foamWhite - foamLow) * 0.28
            foamFloor += (foamLow - foamFloor) * 0.035
            let foamBand = foamLow - foamFloor

            // 泡が立つ瞬間だけ、ごく小さな気泡の粒を混ぜる。
            if noise.unit() > 0.9998 {
                bubble = max(bubble, 0.22 + noise.unit() * 0.28)
            }
            bubble *= 0.995
            bubbleSmoothed += (bubble - bubbleSmoothed) * 0.08

            let wash = washBand * (0.055 + washEnvelope * 0.23)
            let foam = foamBand * (0.008 + foamEnvelope * 0.105)
            let fizz = bubbleSmoothed * foamEnvelope * 0.025
            return wash + foam + fizz
        }
    }

    /// 不規則な波群から、寄せ波と少し遅れて残る泡の包絡を作る。
    nonisolated private static func makeWaveEnvelopes(
        frameCount: Int,
        sampleRate: Double
    ) -> (wash: [Float], foam: [Float]) {
        var wash = [Float](repeating: 0, count: frameCount)
        var foam = [Float](repeating: 0, count: frameCount)
        var random = NoiseGenerator(state: 0x9D31_7A52_C846_0BEF)
        let duration = Double(frameCount) / sampleRate

        func addWave(
            crest: Double,
            strength: Float,
            attack: Double,
            release: Double,
            foamDelay: Double,
            foamRelease: Double
        ) {
            let washStart = max(0, Int((crest - attack) * sampleRate))
            let washEnd = min(frameCount, Int((crest + release) * sampleRate))
            if washStart < washEnd {
                for index in washStart..<washEnd {
                    let time = Double(index) / sampleRate
                    let shape: Double
                    if time < crest {
                        let x = max(0, min(1, (time - (crest - attack)) / attack))
                        shape = x * x * (3 - 2 * x)
                    } else {
                        let x = max(0, min(1, (time - crest) / release))
                        let remaining = 1 - x
                        shape = remaining * remaining * (1 + 0.18 * remaining)
                    }
                    wash[index] += strength * Float(shape)
                }
            }

            let foamCrest = crest + foamDelay
            let foamAttack = 0.28
            let foamStart = max(0, Int((foamCrest - foamAttack) * sampleRate))
            let foamEnd = min(frameCount, Int((foamCrest + foamRelease) * sampleRate))
            if foamStart < foamEnd {
                for index in foamStart..<foamEnd {
                    let time = Double(index) / sampleRate
                    let shape: Double
                    if time < foamCrest {
                        let x = max(0, min(1, (time - (foamCrest - foamAttack)) / foamAttack))
                        shape = x * x * (3 - 2 * x)
                    } else {
                        let x = max(0, min(1, (time - foamCrest) / foamRelease))
                        let remaining = 1 - x
                        shape = remaining * remaining * remaining
                    }
                    foam[index] += strength * Float(shape) * 0.92
                }
            }
        }

        // 一定間隔にせず、2〜4波の「波群」と、群の間の静かな時間を作る。
        var crest = -1.5
        while crest < duration + 3 {
            let wavesInSet = 2 + Int(random.unit() * 3)
            let setStrength = 0.66 + random.unit() * 0.30
            for waveIndex in 0..<wavesInSet {
                let strength = setStrength * (0.72 + random.unit() * 0.32)
                addWave(
                    crest: crest,
                    strength: strength,
                    attack: 1.35 + Double(random.unit()) * 1.15,
                    release: 3.0 + Double(random.unit()) * 2.1,
                    foamDelay: 0.14 + Double(random.unit()) * 0.32,
                    foamRelease: 1.8 + Double(random.unit()) * 1.5
                )
                if waveIndex < wavesInSet - 1 {
                    crest += 3.2 + Double(random.unit()) * 1.9
                }
            }
            crest += 6.0 + Double(random.unit()) * 5.5
        }
        return (wash, foam)
    }

    /// 遠い海鳴り・寄せ波・泡を別帯域で合成した、31秒のステレオ生成音。
    /// 末尾と先頭は3.5秒のオーバーラップで繋ぎ、ノイズ波形自体も連続させる。
    nonisolated private static func makeWaveSamples() -> WaveSamples {
        let rate = 44_100.0
        let loopFrames = Int(rate * 31.0)
        let overlapFrames = Int(rate * 3.5)
        let sourceFrames = loopFrames + overlapFrames
        let envelopes = makeWaveEnvelopes(frameCount: sourceFrames, sampleRate: rate)
        var sourceLeft = [Float](repeating: 0, count: sourceFrames)
        var sourceRight = [Float](repeating: 0, count: sourceFrames)

        var distantNoise = NoiseGenerator(state: 0x48A2_1F76_9C3D_5BE1)
        var distantLow: Float = 0
        var distantFloor: Float = 0
        var distantSwell: Float = 0
        var left = ShoreTexture(noise: NoiseGenerator(state: 0xA721_C49E_63B8_D205))
        var right = ShoreTexture(noise: NoiseGenerator(state: 0x3E8C_17D4_B952_A60F))

        for index in 0..<sourceFrames {
            let washEnvelope = min(1.35, envelopes.wash[index])
            let foamEnvelope = min(1.25, envelopes.foam[index])

            let distantWhite = distantNoise.signed()
            distantLow += (distantWhite - distantLow) * 0.018
            distantFloor += (distantLow - distantFloor) * 0.0012
            distantSwell += (washEnvelope - distantSwell) * 0.00018
            let seaRoar = (distantLow - distantFloor) * (0.15 + distantSwell * 0.11)

            let leftTexture = left.sample(washEnvelope: washEnvelope, foamEnvelope: foamEnvelope)
            let rightTexture = right.sample(washEnvelope: washEnvelope, foamEnvelope: foamEnvelope)
            // 弱いクロスフィードで、ヘッドフォンでも波が左右へ張り付きすぎないようにする。
            sourceLeft[index] = seaRoar + leftTexture * 0.80 + rightTexture * 0.20
            sourceRight[index] = seaRoar + rightTexture * 0.80 + leftTexture * 0.20
        }

        var outputLeft = [Float](repeating: 0, count: loopFrames)
        var outputRight = [Float](repeating: 0, count: loopFrames)
        var peak: Float = 0

        for index in 0..<loopFrames {
            var leftSample = sourceLeft[index]
            var rightSample = sourceRight[index]
            if index < overlapFrames {
                let x = Float(index) / Float(max(1, overlapFrames - 1))
                let blend = x * x * (3 - 2 * x)
                leftSample = sourceLeft[loopFrames + index] * (1 - blend) + leftSample * blend
                rightSample = sourceRight[loopFrames + index] * (1 - blend) + rightSample * blend
            }
            // 偶発的な泡のピークだけを丸め、海鳴りの小さな揺れは残す。
            leftSample /= 1 + abs(leftSample) * 0.32
            rightSample /= 1 + abs(rightSample) * 0.32
            outputLeft[index] = leftSample
            outputRight[index] = rightSample
            peak = max(peak, max(abs(leftSample), abs(rightSample)))
        }

        // 合成そのままではピークが0.12ほどしかなく、プレイヤー音量を上限まで
        // 上げても楽曲に届かない。乱数の種は固定で波形は毎回同じなので、
        // ここで既知の高さへ揃えてしまい、実際の音量は鳴らす側が決める。
        if peak > 0.000_001 {
            let gain = peakLevel / peak
            for index in 0..<loopFrames {
                outputLeft[index] *= gain
                outputRight[index] *= gain
            }
        }
        return WaveSamples(left: outputLeft, right: outputRight)
    }

    /// AVAudioPCMBufferの生成と所有はMainActor内で完結させる。
    private static func makeWaveBuffer(from samples: WaveSamples) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(samples.left.count)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        samples.left.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: source.count)
        }
        samples.right.withUnsafeBufferPointer { source in
            buffer.floatChannelData![1].update(from: source.baseAddress!, count: source.count)
        }
        return buffer
    }
}
