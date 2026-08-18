@preconcurrency import AVFoundation
import Combine

/// タイマーの外で流す、KeelMiraオリジナルのホームテーマ。
/// タイマー用の波音・ノクターンとはプレイヤーを分け、開始時に静かに譲る。
@MainActor
final class HomeBackgroundMusic: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = HomeBackgroundMusic()
    static let enabledKey = "home.backgroundMusicEnabled"
    static let selectedTrackKey = "home.backgroundMusicTrack"
    static let legacyWavePreferenceMigratedKey = "home.audioSelectionV2Migrated"
    static let tracks = HomeVoyageSound.selectableSounds

    @Published private(set) var isPlaying = false
    @Published private(set) var playbackFailed = false
    @Published private(set) var currentTrack: HomeVoyageSound

    private let targetVolume: Float = 0.24
    private var player: AVAudioPlayer?
    private var fadeTask: Task<Void, Never>?
    private var currentTrackIndex: Int
    private var requestedTrack: HomeVoyageSound
    private var playbackRequested = false
    private var waveSubscriptions: Set<AnyCancellable> = []

    private override init() {
        let selected = Self.savedTrack
        currentTrack = selected
        requestedTrack = selected
        currentTrackIndex = HomeVoyageSound.musicTracks.firstIndex(of: selected) ?? 0
        super.init()
        observeWavePlayback()
    }

    var playbackProgress: Double {
        guard let player, player.duration > 0 else { return 0 }
        return min(1, max(0, player.currentTime / player.duration))
    }

    var elapsedTime: TimeInterval {
        player?.currentTime ?? 0
    }

    var duration: TimeInterval {
        player?.duration ?? 0
    }

    /// 選択した波音、またはオリジナルテーマ3曲を再生する。
    func play() {
        playbackRequested = true
        fadeTask?.cancel()
        fadeTask = nil
        playbackFailed = false

        let selected = Self.savedTrack
        if selected != requestedTrack {
            requestedTrack = selected
            currentTrack = selected
            currentTrackIndex = HomeVoyageSound.musicTracks.firstIndex(of: selected) ?? 0
            player?.stop()
            player = nil
        }

        if selected == .waves {
            player?.stop()
            player = nil
            currentTrack = .waves
            HomeWaveAmbience.shared.play()
            isPlaying = HomeWaveAmbience.shared.isPlaying
            playbackFailed = HomeWaveAmbience.shared.playbackFailed
            return
        }

        HomeWaveAmbience.shared.stop()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            if let player {
                if !player.isPlaying {
                    player.volume = 0
                    player.play()
                }
                player.setVolume(targetVolume, fadeDuration: 1.6)
                isPlaying = player.isPlaying
                playbackFailed = !isPlaying
            } else {
                try startCurrentTrack(fadeDuration: 1.6)
            }
        } catch {
            player?.stop()
            player = nil
            isPlaying = false
            playbackFailed = true
        }
    }

    /// 別の画面音へ自然につなぐ。共有AudioSessionはタイマー側が続けて使えるよう残す。
    func stop() {
        playbackRequested = false
        fadeTask?.cancel()
        if requestedTrack == .waves {
            HomeWaveAmbience.shared.stop()
            isPlaying = false
            playbackFailed = false
            return
        }
        guard let player, player.isPlaying else {
            isPlaying = false
            return
        }
        player.setVolume(0, fadeDuration: 0.55)
        isPlaying = false
        fadeTask = Task { [weak self, weak player] in
            try? await Task.sleep(for: .milliseconds(620))
            guard !Task.isCancelled, let self, let player else { return }
            player.pause()
            player.currentTime = 0
            self.fadeTask = nil
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finishedPlayerID = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            self?.advanceAfterTrackFinished(playerID: finishedPlayerID, successfully: flag)
        }
    }

    private func startCurrentTrack(fadeDuration: TimeInterval) throws {
        let track = HomeVoyageSound.musicTracks[currentTrackIndex]
        let resourceName = track.rawValue
        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: "m4a",
            subdirectory: "Resources"
        ) ?? Bundle.main.url(forResource: resourceName, withExtension: "m4a") else {
            throw CocoaError(.fileNoSuchFile)
        }

        let nextPlayer = try AVAudioPlayer(contentsOf: url)
        nextPlayer.delegate = self
        nextPlayer.numberOfLoops = 0
        nextPlayer.volume = 0
        nextPlayer.prepareToPlay()
        #if DEBUG
        // 動作確認用: LANDFALL_MUSIC_TAIL=5 で各曲を終わり5秒から始め、
        // 次曲への自動送りと表示の切り替わりを数秒で確かめられる。
        if let raw = ProcessInfo.processInfo.environment["LANDFALL_MUSIC_TAIL"],
           let tail = TimeInterval(raw), tail > 0 {
            nextPlayer.currentTime = max(0, nextPlayer.duration - tail)
        }
        #endif
        player = nextPlayer
        currentTrack = track

        guard nextPlayer.play() else {
            player = nil
            throw CocoaError(.fileReadUnknown)
        }
        nextPlayer.setVolume(targetVolume, fadeDuration: fadeDuration)
        isPlaying = true
        playbackFailed = false
    }

    private func advanceAfterTrackFinished(playerID: ObjectIdentifier, successfully: Bool) {
        guard playbackRequested,
              successfully,
              let player,
              ObjectIdentifier(player) == playerID else { return }

        currentTrackIndex = (currentTrackIndex + 1) % HomeVoyageSound.musicTracks.count
        self.player = nil
        do {
            try startCurrentTrack(fadeDuration: 1.35)
        } catch {
            isPlaying = false
            playbackFailed = true
        }
    }

    private static var savedTrack: HomeVoyageSound {
        let rawValue = UserDefaults.standard.string(forKey: selectedTrackKey)
            ?? HomeVoyageSound.harborMinuet.rawValue
        let track = HomeVoyageSound.resolve(rawValue)
        return tracks.contains(track) ? track : .harborMinuet
    }

    private func observeWavePlayback() {
        HomeWaveAmbience.shared.$isPlaying
            .combineLatest(HomeWaveAmbience.shared.$playbackFailed)
            .sink { [weak self] isPlaying, playbackFailed in
                guard let self,
                      self.playbackRequested,
                      self.requestedTrack == .waves else { return }
                self.currentTrack = .waves
                self.isPlaying = isPlaying
                self.playbackFailed = playbackFailed
            }
            .store(in: &waveSubscriptions)
    }
}
