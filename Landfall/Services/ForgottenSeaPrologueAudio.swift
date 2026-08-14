@preconcurrency import AVFoundation
import Combine

/// 初回起動と設定からの再生で流す、「忘却の海」専用プロローグ。
/// 共有AudioSessionは後続画面の波音・BGMも使うため、停止時も無効化しない。
@MainActor
final class ForgottenSeaPrologueAudio: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = ForgottenSeaPrologueAudio()

    @Published private(set) var isPlaying = false
    @Published private(set) var playbackFailed = false

    private let targetVolume: Float = 0.48
    private let fadeInDuration: TimeInterval = 1.9
    private let fadeOutDuration: TimeInterval = 0.95

    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?
    private var playbackRequested = false
    private var playbackGeneration: UInt = 0

    private override init() {
        super.init()
    }

    /// 専用曲を序章が閉じるまで繰り返す。再生中の重複呼び出しでは再開始しない。
    func play() {
        playbackRequested = true
        playbackGeneration &+= 1
        stopTask?.cancel()
        stopTask = nil
        playbackFailed = false

        if let player, player.isPlaying {
            player.setVolume(targetVolume, fadeDuration: fadeInDuration)
            isPlaying = true
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            guard let url = Bundle.main.url(
                forResource: "forgotten_sea_prologue",
                withExtension: "m4a",
                subdirectory: "Resources"
            ) ?? Bundle.main.url(forResource: "forgotten_sea_prologue", withExtension: "m4a") else {
                throw CocoaError(.fileNoSuchFile)
            }

            let nextPlayer = try AVAudioPlayer(contentsOf: url)
            nextPlayer.delegate = self
            nextPlayer.numberOfLoops = -1
            nextPlayer.volume = 0
            nextPlayer.prepareToPlay()
            player = nextPlayer

            guard nextPlayer.play() else {
                player = nil
                throw CocoaError(.fileReadUnknown)
            }
            nextPlayer.setVolume(targetVolume, fadeDuration: fadeInDuration)
            isPlaying = true
        } catch {
            failSilently()
        }
    }

    /// 映像を序章の頭へ戻すとき、曲も確実に先頭へ揃える。
    func restart() {
        stopTask?.cancel()
        stopTask = nil
        playbackGeneration &+= 1
        playbackRequested = false
        player?.stop()
        player?.currentTime = 0
        player = nil
        isPlaying = false
        play()
    }

    /// 約1秒で静かに消し、同じプレイヤーを次回の先頭再生に持ち越さない。
    func stop() {
        playbackRequested = false
        playbackGeneration &+= 1
        let generation = playbackGeneration
        stopTask?.cancel()
        playbackFailed = false
        isPlaying = false

        guard let player, player.isPlaying else {
            player?.stop()
            self.player = nil
            return
        }

        player.setVolume(0, fadeDuration: fadeOutDuration)
        stopTask = Task { [weak self, weak player] in
            try? await Task.sleep(for: .milliseconds(1_020))
            guard !Task.isCancelled,
                  let self,
                  let player,
                  self.playbackGeneration == generation,
                  !self.playbackRequested else { return }
            player.stop()
            player.currentTime = 0
            if self.player === player {
                self.player = nil
            }
            self.stopTask = nil
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finishedPlayerID = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            self?.finishNaturally(playerID: finishedPlayerID, successfully: flag)
        }
    }

    private func finishNaturally(playerID: ObjectIdentifier, successfully: Bool) {
        guard let player, ObjectIdentifier(player) == playerID else { return }
        self.player = nil
        playbackRequested = false
        isPlaying = false
        playbackFailed = !successfully
    }

    /// オープニングは音が出なくても映像を続行する。呼び出し側へは例外を渡さない。
    private func failSilently() {
        stopTask?.cancel()
        stopTask = nil
        player?.stop()
        player = nil
        playbackRequested = false
        isPlaying = false
        playbackFailed = true
    }
}
