import FirebaseFirestore
import Foundation

extension BoatCustomization {
    /// 船デザイン対応前後の共有データで同じように使える再描画キー。
    static var voyageRenderingKey: String {
        shareData.keys.sorted().map { "\($0)=\(shareData[$0] ?? "")" }.joined(separator: "|")
    }
}

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
        localID: String,
        identity: CompanionVoyageIdentity
    ) -> HomeIslandRemotePlayerState {
        HomeIslandRemotePlayerState(
            id: localID,
            x: last?.x ?? 0,
            z: last?.z ?? 0,
            yaw: last?.yaw ?? 0,
            pose: PhoenixPose.idle.rawValue,
            scene: Self.scene,
            phase: stage.presencePhase,
            arrivalNonce: identity.presenceToken,
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

/// 同行の航海中だけ presence に載せる小さなプレイヤーカード。
///
/// 専用の Firestore 読み取りやスキーマを増やさず、すでに各端末へ届く
/// `arrivalNonce` の短い文字列として運ぶ。島へ戻ると破棄される一時情報なので、
/// レベルや選択中の船が古いまま残らない。
struct CompanionVoyageIdentity: Equatable, Sendable {
    private static let tokenPrefix = "c1"

    let level: Int
    let styleToken: String
    let symbolToken: String
    /// 旧クライアントでは船体色、新クライアントでは船デザインID。
    /// `BoatCustomization.parts(fromIDs:)` が両方を互換的に解釈する。
    let hullID: String
    let sailID: String

    static let fallback = CompanionVoyageIdentity(
        level: 1,
        styleToken: TileStyle.midnight.rawValue,
        symbolToken: TileSymbol.phoenix.rawValue,
        hullID: "sand",
        sailID: BoatCustomization.sailColors[0].id
    )

    static func local(level: Int) -> CompanionVoyageIdentity {
        let boat = BoatCustomization.shareData
        return CompanionVoyageIdentity(
            level: max(1, level),
            styleToken: TileStyle.from(PlayerProfile.styleToken).rawValue,
            symbolToken: TileSymbol.from(PlayerProfile.symbolToken).rawValue,
            hullID: boat["boatHull"] ?? "sand",
            sailID: BoatCustomization.selectedSailID
        )
    }

    var presenceToken: String {
        let style = TileStyle.from(styleToken)
        let symbol = TileSymbol.from(symbolToken)
        let styleIndex = TileStyle.allCases.firstIndex(of: style) ?? 0
        let symbolIndex = TileSymbol.allCases.firstIndex(of: symbol) ?? 0
        let sailIndex = BoatCustomization.sailColors.firstIndex { $0.id == sailID } ?? 0
        let safeHull = String(
            hullID.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
                .prefix(24)
        )
        return [
            Self.tokenPrefix,
            String(max(1, min(level, 9999))),
            String(styleIndex),
            String(symbolIndex),
            String(sailIndex),
            safeHull.isEmpty ? "sand" : safeHull,
        ].joined(separator: "|")
    }

    var boatParts: BoatParts {
        BoatCustomization.parts(fromIDs: [
            "boatSail": sailID,
            "boatHull": hullID,
        ])
    }

    var boatAppearanceKey: String { "\(hullID)-\(sailID)" }

    static func decode(_ token: String?) -> CompanionVoyageIdentity? {
        guard let token else { return nil }
        let fields = token.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 6,
              fields[0] == Substring(tokenPrefix),
              let level = Int(fields[1]),
              (1...9999).contains(level)
        else { return nil }

        guard let styleIndex = Int(fields[2]),
              TileStyle.allCases.indices.contains(styleIndex),
              let symbolIndex = Int(fields[3]),
              TileSymbol.allCases.indices.contains(symbolIndex),
              let sailIndex = Int(fields[4]),
              BoatCustomization.sailColors.indices.contains(sailIndex)
        else { return nil }
        let hullID = String(fields[5])
        guard !hullID.isEmpty,
              hullID.utf8.count <= 24,
              hullID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
        else {
            return nil
        }
        let style = TileStyle.allCases[styleIndex]
        let symbol = TileSymbol.allCases[symbolIndex]
        let sailID = BoatCustomization.sailColors[sailIndex].id
        return CompanionVoyageIdentity(
            level: level,
            styleToken: style.rawValue,
            symbolToken: symbol.rawValue,
            hullID: hullID,
            sailID: sailID
        )
    }
}

/// 参加一覧の一行。
struct CompanionVoyageCrewMate: Identifiable, Equatable {
    let id: String
    var name: String
    var identity: CompanionVoyageIdentity = .fallback
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
        localStage: CompanionVoyageStage?,
        localIdentity: CompanionVoyageIdentity
    ) -> [CompanionVoyageCrewMate] {
        var stages: [String: CompanionVoyageStage?] = [:]
        var identities: [String: CompanionVoyageIdentity] = [:]
        for presence in presences where presence.uid != localID {
            guard presence.uid == hostUid || memberIDs.contains(presence.uid) else { continue }
            stages[presence.uid] = CompanionVoyagePresence.stage(of: presence)
            if let identity = CompanionVoyageIdentity.decode(presence.arrivalNonce) {
                identities[presence.uid] = identity
            }
        }
        if !localID.isEmpty {
            stages[localID] = localStage
            identities[localID] = localIdentity
        }

        let mates = stages.map { uid, stage in
            CompanionVoyageCrewMate(
                id: uid,
                name: uid == localID
                    ? PlayerProfile.displayName
                    : (names[uid] ?? LF.text("Sailor")),
                identity: identities[uid] ?? .fallback,
                stage: stage,
                isHost: uid == hostUid,
                isLocal: uid == localID
            )
        }
        // memberIds は Cloud Function が参加時に末尾へ追加する永続的な参加順。
        // local / remote や presence の到着順で並べ替えないため、全端末で同じ
        // 1〜4番が得られ、甲板の役割を追加通信なしで固定できる。
        var memberOrder: [String: Int] = [:]
        for (index, uid) in memberIDs.enumerated() where memberOrder[uid] == nil {
            memberOrder[uid] = index
        }
        return mates.sorted { lhs, rhs in
            if lhs.isHost != rhs.isHost { return lhs.isHost }
            let lhsOrder = memberOrder[lhs.id] ?? Int.max
            let rhsOrder = memberOrder[rhs.id] ?? Int.max
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return lhs.id < rhs.id
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
