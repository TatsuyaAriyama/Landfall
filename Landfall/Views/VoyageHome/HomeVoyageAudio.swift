@preconcurrency import AVFoundation
import Combine
import SwiftUI

enum HomeVoyageSound: String, CaseIterable, Identifiable {
    case off
    case waves
    case harborMinuet = "harbor_minuet_main_theme"
    case beaconRondo = "beacon_rondo"
    case celestialNocturne = "celestial_navigation_nocturne"

    static let selectableSounds: [HomeVoyageSound] = [
        .waves,
        .harborMinuet,
        .beaconRondo,
        .celestialNocturne,
    ]

    /// 航海タイマーの一覧だけは無音も選べる。島のBGMパネルは別に有効/無効の
    /// スイッチを持つので、そちらの一覧(`selectableSounds`)には足さない。
    static let timerSelectableSounds: [HomeVoyageSound] = [.off] + selectableSounds

    static let musicTracks: [HomeVoyageSound] = [
        .harborMinuet,
        .beaconRondo,
        .celestialNocturne,
    ]

    /// まだ一度も選曲していない航海士が、最初の航海で聴く曲。
    static let initialTimerSound: HomeVoyageSound = .harborMinuet

    var id: String { rawValue }

    static func resolve(_ storedValue: String) -> HomeVoyageSound {
        // 旧版の「piano」は、正式曲名を持つ港のメヌエットへ移行する。
        if storedValue == "piano" { return .harborMinuet }
        // 公開カタログから外れた旧曲は、既定曲へ移行する。
        if [
            "stormfront_urgence",
            "approaching_evolution",
            "harbor_andante",
            "leeward_cove",
        ].contains(storedValue) {
            return .harborMinuet
        }
        return HomeVoyageSound(rawValue: storedValue) ?? .harborMinuet
    }

    var title: LocalizedStringKey {
        switch self {
        case .off: "Sound off"
        case .waves: "Waves"
        case .harborMinuet: "Harbor Minuet"
        case .beaconRondo: "Beacon Rondo"
        case .celestialNocturne: "Celestial Navigation Nocturne"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .off: "Sail in silence"
        case .waves: "Ambient sound"
        case .harborMinuet, .beaconRondo, .celestialNocturne: "Original soundtrack"
        }
    }

    var systemImage: String {
        switch self {
        case .off: "speaker.slash.fill"
        case .waves, .harborMinuet, .beaconRondo, .celestialNocturne: "music.note"
        }
    }

    fileprivate var resourceName: String? {
        switch self {
        case .harborMinuet, .beaconRondo, .celestialNocturne: rawValue
        case .off, .waves: nil
        }
    }
}

/// BGM選択は波音も含め、同じ音符マークで表す。
struct HomeVoyageSoundIcon: View {
    let sound: HomeVoyageSound
    let selected: Bool

    private var color: Color {
        selected ? LFColor.returnOrange : LFColor.harborSand.opacity(0.62)
    }

    var body: some View {
        Image(systemName: sound.systemImage)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

/// 航海タイマー専用の波音・オリジナルサウンドトラック。
/// 選択のたびに音源を明示的に停止してから差し替え、表示と再生状態を一致させる。
@MainActor
final class HomeVoyageAudio: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = HomeVoyageAudio()

    @Published private(set) var isPlaying = false
    @Published private(set) var playbackFailed = false
    @Published private(set) var currentSound: HomeVoyageSound = .off

    private let waveEngine = AVAudioEngine()
    private let wavePlayer = AVAudioPlayerNode()
    private var waveConfigured = false
    /// 波音は選べる曲のひとつとして前に出るので、島へ薄く敷くときとは別の音量。
    /// 楽曲(実効RMS約0.046)の8割ほどに合わせ、並べて選んでも段差を感じない。
    private static let waveVolume = WaveSound.volume(forOutputPeak: 0.27)
    private var musicPlayer: AVAudioPlayer?
    private enum MusicPlaybackMode {
        case playlist
        case loopSingle
    }
    private var musicPlaybackMode: MusicPlaybackMode = .playlist
    private let musicPlaylist = HomeVoyageSound.musicTracks
    private var playbackRequested = false
    /// プレイリストが次曲へ進んでも、利用者が選んだ開始曲は別に保持する。
    /// 画面外からの再生保証が毎回1曲目へ巻き戻さないために使う。
    private var requestedSound: HomeVoyageSound = .off

    private override init() {
        super.init()
    }

    func play(_ storedValue: String) {
        play(storedValue, musicPlaybackMode: .playlist)
    }

    /// 画面遷移・前面復帰時に、航海中の音が途切れている場合だけ再開する。
    /// プレイリストが既に次曲へ進んでいるときは、その曲を維持する。
    func ensurePlaying(_ storedValue: String) {
        let sound = HomeVoyageSound.resolve(storedValue)
        if requestedSound == sound,
           playbackFailed {
            return
        }
        if requestedSound == sound,
           playbackRequested,
           currentSound != .off,
           isPlaybackActive(for: currentSound) {
            isPlaying = true
            return
        }
        play(storedValue, musicPlaybackMode: .playlist)
    }

    /// 初回チュートリアル中は、読み上げに時間がかかっても
    /// 次の曲へ進まず、港のメヌエットを同じ箇所から繰り返す。
    func playLooping(_ storedValue: String) {
        play(storedValue, musicPlaybackMode: .loopSingle)
    }

    private func play(_ storedValue: String, musicPlaybackMode: MusicPlaybackMode) {
        let sound = HomeVoyageSound.resolve(storedValue)
        requestedSound = sound
        if sound == currentSound, isPlaybackActive(for: sound) {
            self.musicPlaybackMode = musicPlaybackMode
            musicPlayer?.numberOfLoops = musicPlaybackMode == .loopSingle ? -1 : 0
            isPlaying = true
            playbackFailed = false
            return
        }

        playbackRequested = false
        stopPlayback(deactivateSession: false)
        currentSound = sound
        self.musicPlaybackMode = musicPlaybackMode
        playbackFailed = false

        guard sound != .off else {
            deactivateAudioSession()
            return
        }
        playbackRequested = true

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            switch sound {
            case .waves:
                // 波形がまだ生成中なら、出来上がった時点でこの再生要求を
                // やり直す。失敗ではないので、音が出ない印はつけない。
                guard try startWaves() else { return }
            case .harborMinuet, .beaconRondo, .celestialNocturne:
                try playMusic(sound, fadeDuration: 0.35)
            case .off:
                break
            }

            isPlaying = isPlaybackActive(for: sound)
            playbackFailed = !isPlaying
        } catch {
            playbackRequested = false
            stopPlayback(deactivateSession: true)
            playbackFailed = true
        }
    }

    func stop() {
        playbackRequested = false
        requestedSound = .off
        stopPlayback(deactivateSession: true)
        musicPlaybackMode = .playlist
        playbackFailed = false
    }

    private func playMusic(_ sound: HomeVoyageSound, fadeDuration: TimeInterval) throws {
        guard let resourceName = sound.resourceName,
              let url = Bundle.main.url(
                forResource: resourceName,
                withExtension: "m4a",
                subdirectory: "Resources"
              ) ?? Bundle.main.url(forResource: resourceName, withExtension: "m4a")
        else {
            throw CocoaError(.fileNoSuchFile)
        }

        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.numberOfLoops = musicPlaybackMode == .loopSingle ? -1 : 0
        player.volume = 0
        player.prepareToPlay()
        musicPlayer = player
        guard player.play() else {
            musicPlayer = nil
            throw CocoaError(.fileReadUnknown)
        }
        player.setVolume(0.34, fadeDuration: fadeDuration)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finishedPlayerID = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            self?.advanceAfterTrackFinished(playerID: finishedPlayerID, successfully: flag)
        }
    }

    private func advanceAfterTrackFinished(playerID: ObjectIdentifier, successfully: Bool) {
        guard playbackRequested,
              musicPlaybackMode == .playlist,
              successfully,
              let musicPlayer,
              ObjectIdentifier(musicPlayer) == playerID,
              let currentIndex = musicPlaylist.firstIndex(of: currentSound)
        else { return }

        let nextSound = musicPlaylist[(currentIndex + 1) % musicPlaylist.count]
        self.musicPlayer = nil
        currentSound = nextSound
        do {
            try playMusic(nextSound, fadeDuration: 1.35)
            isPlaying = true
            playbackFailed = false
        } catch {
            playbackRequested = false
            isPlaying = false
            playbackFailed = true
        }
    }

    /// 波形が用意できていれば鳴らして true を返す。生成待ちなら false。
    private func startWaves() throws -> Bool {
        try configureWavesIfNeeded()
        guard let buffer = WaveSound.buffer(whenReady: { [weak self] in
            guard let self, self.playbackRequested, self.requestedSound == .waves else { return }
            self.play(HomeVoyageSound.waves.rawValue, musicPlaybackMode: self.musicPlaybackMode)
        }) else { return false }

        if !waveEngine.isRunning {
            waveEngine.prepare()
            try waveEngine.start()
        }
        wavePlayer.volume = Self.waveVolume
        wavePlayer.scheduleBuffer(buffer, at: nil, options: [.loops])
        wavePlayer.play()
        return true
    }

    private func stopPlayback(deactivateSession: Bool) {
        musicPlayer?.stop()
        musicPlayer = nil
        wavePlayer.stop()
        if waveEngine.isRunning { waveEngine.stop() }
        currentSound = .off
        isPlaying = false
        if deactivateSession { deactivateAudioSession() }
    }

    private func isPlaybackActive(for sound: HomeVoyageSound) -> Bool {
        switch sound {
        case .off: false
        case .waves: wavePlayer.isPlaying && waveEngine.isRunning
        case .harborMinuet, .beaconRondo, .celestialNocturne: musicPlayer?.isPlaying == true
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
    }

    private func configureWavesIfNeeded() throws {
        guard !waveConfigured else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        waveEngine.attach(wavePlayer)
        waveEngine.connect(wavePlayer, to: waveEngine.mainMixerNode, format: format)
        waveEngine.mainMixerNode.outputVolume = 1
        waveConfigured = true
    }
}
