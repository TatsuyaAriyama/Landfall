@preconcurrency import AVFoundation
import Combine

/// タイマーの外で流す、KeelMiraオリジナルのホームテーマ。
/// タイマー用の波音・ノクターンとはプレイヤーを分け、開始時に静かに譲る。
@MainActor
final class HomeBackgroundMusic: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = HomeBackgroundMusic()
    static let enabledKey = "home.backgroundMusicEnabled"
    static let selectedTrackKey = "home.backgroundMusicTrack"
    static let tracks: [HomeVoyageSound] = [
        .harborMinuet,
        .beaconRondo,
        .celestialNocturne,
        .approachingEvolution,
        .harborAndante,
        .leewardCove,
    ]

    @Published private(set) var isPlaying = false
    @Published private(set) var playbackFailed = false
    @Published private(set) var currentTrack: HomeVoyageSound

    private let targetVolume: Float = 0.24
    private var player: AVAudioPlayer?
    private var fadeTask: Task<Void, Never>?
    private var currentTrackIndex: Int
    private var requestedTrack: HomeVoyageSound
    private var playbackRequested = false

    private override init() {
        let selected = Self.savedTrack
        currentTrack = selected
        requestedTrack = selected
        currentTrackIndex = Self.tracks.firstIndex(of: selected) ?? 0
        super.init()
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

    /// ホームのオリジナルテーマ6曲を固定順で繰り返す。
    func play() {
        playbackRequested = true
        fadeTask?.cancel()
        fadeTask = nil
        playbackFailed = false

        let selected = Self.savedTrack
        if selected != requestedTrack {
            requestedTrack = selected
            currentTrack = selected
            currentTrackIndex = Self.tracks.firstIndex(of: selected) ?? 0
            player?.stop()
            player = nil
        }

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
        let track = Self.tracks[currentTrackIndex]
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

        currentTrackIndex = (currentTrackIndex + 1) % Self.tracks.count
        self.player = nil
        do {
            try startCurrentTrack(fadeDuration: 1.35)
        } catch {
            isPlaying = false
            playbackFailed = true
        }
    }

    private static var savedTrack: HomeVoyageSound {
        guard let rawValue = UserDefaults.standard.string(forKey: selectedTrackKey),
              let track = HomeVoyageSound(rawValue: rawValue),
              tracks.contains(track)
        else { return .harborMinuet }
        return track
    }
}
