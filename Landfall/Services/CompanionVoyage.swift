import FirebaseFirestore
import Foundation

/// 私設島の「同行の航海」。ホストが出す航海に、島にいる仲間が同じ船で付いていく。
///
/// 専用のドキュメントは足さない。既存の presence に scene / phase を一つずつ
/// 増やしただけで表す。島にいる全員がすでに presence を購読しているので、
/// 待ち合わせにも航海中の同乗表示にも追加の読み取りが発生しない。
enum CompanionVoyageStage: String, Equatable, Sendable {
    /// 出航前。船の支度をしながら仲間を待っている。島には立ったまま見える。
    case muster
    /// 航海中。島からは姿が消え、船の甲板に並ぶ。
    case sailing

    var presencePhase: String { rawValue }
}

/// presence の scene / phase と、同行の航海の段階との対応。
enum CompanionVoyagePresence {
    /// 島の景色から離れていることを表す presence の scene。
    static let scene = "voyage"

    static func stage(scene: String, phase: String) -> CompanionVoyageStage? {
        guard scene == Self.scene else { return nil }
        return CompanionVoyageStage(rawValue: phase)
    }

    static func stage(of presence: PrivateIslandPresence) -> CompanionVoyageStage? {
        stage(scene: presence.scene, phase: presence.phase)
    }

    /// 航海中も presence は島にいたときの座標のまま送る。船の上の並びは
    /// 受け取った側が甲板の定位置へ割り当てるので、位置を送り合う必要はない。
    static func state(
        stage: CompanionVoyageStage,
        continuing last: HomeIslandRemotePlayerState?,
        localID: String
    ) -> HomeIslandRemotePlayerState {
        HomeIslandRemotePlayerState(
            id: localID,
            x: last?.x ?? 0,
            z: last?.z ?? 0,
            yaw: last?.yaw ?? 0,
            pose: PhoenixPose.idle.rawValue,
            scene: Self.scene,
            phase: stage.presencePhase,
            isVisible: stage == .muster
        )
    }

    /// 島へ戻ったことを知らせる presence。島の景色が組み上がるまでの数秒、
    /// 仲間の画面から航海士が消えたままにならないようにする。
    static func ashoreState(
        continuing last: HomeIslandRemotePlayerState?,
        localID: String
    ) -> HomeIslandRemotePlayerState {
        HomeIslandRemotePlayerState(
            id: localID,
            x: last?.x ?? 0,
            z: last?.z ?? 0,
            yaw: last?.yaw ?? 0,
            pose: PhoenixPose.idle.rawValue,
            scene: "island",
            phase: "explore",
            isVisible: true
        )
    }
}

/// 参加一覧の一行。
struct CompanionVoyageCrewMate: Identifiable, Equatable {
    let id: String
    var name: String
    /// nil は「まだ島にいる」。
    var stage: CompanionVoyageStage?
    var isHost: Bool
    var isLocal: Bool

    var isAboard: Bool { stage != nil }
}

/// presence と名前から参加一覧を組み立てる。
enum CompanionVoyageRoster {
    static func crew(
        presences: [PrivateIslandPresence],
        names: [String: String],
        memberIDs: [String],
        hostUid: String,
        localID: String,
        localStage: CompanionVoyageStage?
    ) -> [CompanionVoyageCrewMate] {
        var stages: [String: CompanionVoyageStage?] = [:]
        for presence in presences where presence.uid != localID {
            guard presence.uid == hostUid || memberIDs.contains(presence.uid) else { continue }
            stages[presence.uid] = CompanionVoyagePresence.stage(of: presence)
        }
        if !localID.isEmpty { stages[localID] = localStage }

        let mates = stages.map { uid, stage in
            CompanionVoyageCrewMate(
                id: uid,
                name: names[uid] ?? LF.text("Sailor"),
                stage: stage,
                isHost: uid == hostUid,
                isLocal: uid == localID
            )
        }
        return mates.sorted { lhs, rhs in
            if lhs.isHost != rhs.isHost { return lhs.isHost }
            if lhs.isAboard != rhs.isAboard { return lhs.isAboard }
            if lhs.isLocal != rhs.isLocal { return lhs.isLocal }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// いま島にいて、声を掛けられる相手がいるか。
    static func hasCompanionsAshore(
        presences: [PrivateIslandPresence],
        memberIDs: [String],
        hostUid: String,
        localID: String
    ) -> Bool {
        presences.contains { presence in
            presence.uid != localID
                && (presence.uid == hostUid || memberIDs.contains(presence.uid))
        }
    }
}

/// 参加一覧に出す名前だけを、島ごとに一度だけ読む。
///
/// メンバーは最大8人なので読み取りは高々8件で頭打ちになる。人数に比例して
/// 増え続ける購読は張らない。
@MainActor
final class CompanionVoyageNameBook: ObservableObject {
    @Published private(set) var names: [String: String] = [:]

    private var loadedCode: String?
    private var loadTask: Task<Void, Never>?

    func load(code: String) {
        guard loadedCode != code, loadTask == nil else { return }
        loadTask = Task { @MainActor [weak self] in
            let fetched = await PrivateIslandService.memberDisplayNames(code: code)
            guard let self, !Task.isCancelled else { return }
            if !fetched.isEmpty {
                self.names = fetched
                self.loadedCode = code
            }
            self.loadTask = nil
        }
    }

    /// 誰かが増えていたら読み直す。参加一覧を開いた時だけ呼ぶ。
    func refresh(code: String) {
        loadedCode = nil
        load(code: code)
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
    }
}
