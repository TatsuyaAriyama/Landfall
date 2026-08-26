import Combine
import CryptoKit
import Foundation
import SceneKit

extension Notification.Name {
    /// The signed-in player's personal island changed on this device.
    static let homeIslandDidChange = Notification.Name("HomeIslandDidChange")
}

/// Where the invisible walking thumbstick sits on screen.
///
/// The scene reads it to decide whether a touch steers the navigator. The
/// floating glance panels — ToDo, music, the player card — read it too, so the
/// transparent tap-catcher they lay over the island can leave that one corner
/// alone. A glance is not a destination: opening it must never take the walk
/// away from the player.
enum HomeIslandTouchLayout {
    static func movementRegion(
        in bounds: CGRect,
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat
    ) -> CGRect {
        let usableTop = max(bounds.minY + safeAreaTop, bounds.minY)
        let usableBottom = min(bounds.maxY - safeAreaBottom, bounds.maxY)
        let usableHeight = max(usableBottom - usableTop, 1)
        let top = usableTop + usableHeight * 0.54
        // A phone is steered with one thumb near the corner; on an iPad the
        // hand rests further in, so the strip is narrower in proportion.
        let widthRatio: CGFloat = bounds.width < 600 ? 0.58 : 0.48
        return CGRect(
            x: bounds.minX,
            y: top,
            width: bounds.width * widthRatio,
            height: max(usableBottom - top, 0)
        )
    }
}

enum HomeIslandMetrics {
    /// The props every island builds regardless of what the player placed.
    static let fixedSceneryResourceNames = [
        foundationResourceName,
        "wooden_jetty",
        "voyage_notice_board",
        "harbor_welcome_beacon",
    ]

    static let foundationResourceName = "home_island_foundation"
    static let surfaceY: Float = 0.62
    // Placement follows the same authored shoreline that walking uses, so a
    // prop can sit on the last hand's width of sand. Only this lip is kept
    // clear, and only so an anchor never lands in the water.
    static let placementEdgeLip: Float = 0.10
    /// The most a prop's own size may pull it back from the shoreline. Large
    /// scenery still needs a little breathing room, but nothing is pushed as
    /// far inland as its full placement footprint once did.
    static let placementEdgeSizeInsetLimit: Float = 0.30
    static let maximumPlacements = 120
    static let maximumIslandScale = HomeIslandExpansionPolicy.expandedScale
    static let arrivalJettyScale: Float = 0.72
    static let arrivalJettyYaw: Float = .pi
    /// The authored pier previously sat almost 1.5 m above the water. Lowering
    /// the fixed harbor by 24 cm keeps its deck close to the beach while the
    /// landward ramp still meets the sand without a step or buried boards.
    static let arrivalJettyVerticalOffset: Float = -0.24
    // Authored wooden_jetty model-space dimensions. Keeping these beside the
    // fixed placement prevents rendering, walking and arrival choreography
    // from drifting apart when the source asset changes.
    static let jettyDeckSeawardEndLocalZ: Float = -7.42
    static let jettyDeckLandwardEndLocalZ: Float = 2.30
    static let jettyRailSeawardEndLocalZ: Float = -7.25
    static let jettyRailLandwardEndLocalZ: Float = 1.55
    static let jettyRailCenterLocalX: Float = 0.69
    static let jettyBoardingGateSeawardLocalZ: Float = -4.75
    static let jettyBoardingGateLandwardLocalZ: Float = -3.50
    static let boardingFloatCenterLocalX: Float = 2.15
    static let boardingFloatCenterLocalZ: Float = -4.17
    static let boardingFloatHalfWidth: Float = 0.67
    static let boardingFloatHalfLength: Float = 1.50
    static let boardingFloatBoatGateHalfLength: Float = 0.62
    static let boardingConnectorNearLocalX: Float = 0.35
    static let boardingConnectorFarLocalX: Float = 1.72
    static let boardingConnectorHalfLength: Float = 0.60
    // Keep the boarding point comfortably inside the low float's walkable
    // footprint. 2.70 sat just beyond the capsule-safe edge and could spawn
    // the navigator in an invalid position beside the rope posts.
    static let arrivalJettyTransferLocalX: Float = 2.58
    static let arrivalJettyTransferLocalZ: Float = -4.17
    // Arrival ends at the pier-side top tread, visibly clear of the vessel.
    // The transfer point remains on the low float for the departure walk.
    static let arrivalJettyLandingLocalX: Float = 0.35
    static let arrivalJettyIslandLocalZ: Float = 1.50
    static let welcomeBeaconPositions = [
        (x: Float(-0.98), z: Float(8.05)),
        (x: Float(0.98), z: Float(8.05)),
    ]
    static let welcomeBeaconScale: Float = 0.72
    // Permanently place the notice board on the positive-X side of the jetty,
    // just inside the authored shoreline. This keeps the moored boat's
    // negative-X berth clear while making both fixtures read as one entrance.
    static let fixedNoticeBoardPosition = (x: Float(1.82), z: Float(8.45))
    // The imported board faces SceneKit local -Z; rotate it toward the
    // sea/arrival camera so the notices, rather than the rear legs, are shown.
    static let fixedNoticeBoardYaw: Float = .pi
    static let fixedNoticeBoardScale: Float = 0.78
    static let fixedNoticeBoardObstacleRadius: Float = 0.63
    static let fixedNoticeBoardPlacementRadius: Float = 0.68

    static func welcomeBeaconPositions(islandScale: Float) -> [(x: Float, z: Float)] {
        welcomeBeaconPositions.map { position in
            (x: position.x * islandScale, z: position.z * islandScale)
        }
    }

    static func fixedNoticeBoardPosition(islandScale: Float) -> (x: Float, z: Float) {
        (
            x: fixedNoticeBoardPosition.x * islandScale,
            z: fixedNoticeBoardPosition.z * islandScale
        )
    }

    // MARK: - 目的地の島
    // 桟橋の正面(+Z)のはるか沖に、いま向かっている島を置く。孤立した飾りではなく
    // 「この島から見える目的地」。数値は Web / Android へそのまま写せるよう、
    // 描画側ではなくここへ集約する。
    /// 桟橋は x = 0 の海岸にあり、その真正面が +Z。島も同じ線上に置く。
    static let destinationIslandBearingX: Float = 0
    /// 進捗0のときの距離。海(HomeIslandOceanEffects の 180×180)の縁は z=90 で、
    /// そこから先は水が無い。島の向こうに海が残る位置まで手前に置かないと、
    /// 水平線の上へ乗り上げて「空に浮かぶ島」に見えてしまう。
    static let destinationIslandFarDistance: Float = 62
    /// 進捗1(着岸できる)のときの距離。霧を抜け、形がはっきり読める。
    static let destinationIslandNearDistance: Float = 34
    /// 遠景でも「島」として読める大きさ。VoyageSceneKit.makeIsland の半径3.4基準。
    static let destinationIslandScale: Float = 2.75
    /// My Island の海面(HomeIslandOceanEffects.Layout.homeIsland.surfaceY)。
    static let seaSurfaceY: Float = -0.55
    /// 島の吃水線。海面より 1.45 沈め、台座の底面と浜の裏側を水面下へ隠す。
    /// 浅いと岩盤の縁が海の上に残って浮遊物に見え、深すぎると浜ごと沈んで
    /// 峰だけの岩礁になる。浜が波打ち際に接する、この深さが島に見える。
    static let destinationIslandWaterlineY: Float = seaSurfaceY - 1.45
    /// 目的地の島は -X 側を「正面」として作られている(航海中の世界では船が -X にいる)。
    /// こちらは島の -Z 側から見るので、その分だけ回して同じ面を見せる。
    static let destinationIslandYaw: Float = -.pi / 2

    /// 進捗で近づく距離。Web `homeDestinationDistance` と同じ曲線(pow 2.15)で、
    /// 序盤はほとんど動かず、終盤にはっきり近づく。
    static func destinationIslandDistance(progressRatio: Double) -> Float {
        let progress = Float(min(1, max(0, progressRatio)))
        let far = destinationIslandFarDistance
        let near = destinationIslandNearDistance
        if progress <= 0 { return far }
        if progress >= 1 { return near }
        return far + (near - far) * pow(progress, 2.15)
    }

    /// How far from the island's centre a ground-plane raycast is still
    /// meaningful. Near the horizon a camera ray runs almost parallel to the
    /// ground and "hits" it tens of units out at sea; treating that as a real
    /// point let a single drag frame throw a prop clear across the island.
    static let groundRaycastLimit: Float = 20.0

    private static let foundationRadiusX: Float = 13.10
    private static let foundationRadiusZ: Float = 9.10
    private static let sandApronScale: Float = 0.955

    /// Matches `outline(..., layer: 1)` from the deterministic Blender source.
    /// Keeping rendering and collision on this one boundary prevents a visible
    /// strip that looks walkable but rejects the player.
    static func sandEdgePoint(
        angle: Float,
        islandScale: Float = HomeIslandExpansionPolicy.baseScale
    ) -> (x: Float, z: Float) {
        let ripple = sin(angle * 3 + 0.45) * 0.045
            + sin(angle * 7 - 0.82) * 0.026
            + sin(angle * 11 + 1.3) * 0.012
        let layerShift = sin(angle * 5 + 0.91) * 0.018
        let scale = sandApronScale * (1 + ripple + layerShift)
        return (
            cos(angle) * foundationRadiusX * scale * islandScale,
            // USDZ imports Blender's horizontal Y axis as negative SceneKit Z.
            -sin(angle) * foundationRadiusZ * scale * islandScale
        )
    }

    static func arrivalJettyPosition(islandScale: Float) -> (x: Float, z: Float) {
        sandEdgePoint(angle: -.pi / 2, islandScale: islandScale)
    }

    static func containsWalkableSand(
        x: Float,
        z: Float,
        margin: Float,
        islandScale: Float = HomeIslandExpansionPolicy.baseScale
    ) -> Bool {
        let angle = atan2(-z / foundationRadiusZ, x / foundationRadiusX)
        let edge = sandEdgePoint(angle: angle, islandScale: islandScale)
        let edgeDistance = sqrt(edge.x * edge.x + edge.z * edge.z)
        let distance = sqrt(x * x + z * z)
        return distance <= max(0, edgeDistance - margin)
    }

    /// How far inside the authored shoreline a prop's anchor may sit.
    private static func placementEdgeInset(footprintMargin: Float) -> Float {
        placementEdgeLip + min(footprintMargin * 0.22, placementEdgeSizeInsetLimit)
    }

    static func clampedPosition(
        x: Float,
        z: Float,
        footprintMargin: Float = 0,
        islandScale: Float = HomeIslandExpansionPolicy.baseScale
    ) -> (x: Float, z: Float) {
        let distance = sqrt(x * x + z * z)
        guard distance > 0.0001 else { return (x, z) }
        let angle = atan2(-z / foundationRadiusZ, x / foundationRadiusX)
        let edge = sandEdgePoint(angle: angle, islandScale: islandScale)
        let edgeDistance = sqrt(edge.x * edge.x + edge.z * edge.z)
        let limit = max(0.5, edgeDistance - placementEdgeInset(footprintMargin: footprintMargin))
        guard distance > limit else { return (x, z) }
        let scale = limit / distance
        return (x * scale, z * scale)
    }

    static func contains(
        x: Float,
        z: Float,
        islandScale: Float = HomeIslandExpansionPolicy.baseScale
    ) -> Bool {
        containsWalkableSand(
            x: x,
            z: z,
            margin: placementEdgeLip,
            islandScale: islandScale
        )
    }

    /// A jetty is authored along local Z: positive Z is the low shore ramp and
    /// negative Z reaches into the water.  The returned yaw therefore points
    /// local -Z along the shoreline's outward normal.
    static func jettyCoastPlacement(
        nearX x: Float,
        z: Float,
        requireCoastalInput: Bool,
        islandScale: Float = HomeIslandExpansionPolicy.baseScale
    ) -> (x: Float, z: Float, yaw: Float)? {
        let inputDistance = sqrt(x * x + z * z)
        guard inputDistance > 0.5 else { return nil }

        let angle = atan2(-z / foundationRadiusZ, x / foundationRadiusX)
        let edge = sandEdgePoint(angle: angle, islandScale: islandScale)
        let edgeDistance = sqrt(edge.x * edge.x + edge.z * edge.z)
        guard edgeDistance > 0.001 else { return nil }

        if requireCoastalInput {
            // Let players tap the visible lip or just beyond it in the water,
            // while rejecting ordinary inland sand.
            let insetFromEdge = edgeDistance - inputDistance
            guard insetFromEdge >= -0.72, insetFromEdge <= 1.55 else { return nil }
        }

        let outwardX = edge.x / edgeDistance
        let outwardZ = edge.z / edgeDistance
        return (
            edge.x,
            edge.z,
            atan2(-outwardX, -outwardZ)
        )
    }
}

struct HomeIslandAsset: Identifiable, Hashable {
    let id: String
    /// Keep the localization key, not the text resolved when this static
    /// catalog happened to be initialized. The player can change the app
    /// language while Home Island remains alive underneath Settings.
    let titleKey: String
    let symbolName: String
    let defaultScale: Float
    let footprintMargin: Float
    let unlockLevel: Int
    /// 航海証で開く飾り。鍵が掛かっていても一覧には並べる。
    var requiresPass = false

    var title: String { LF.text(titleKey) }
}

/// One member of a prop that ships in several. `swatch` is the dot the drawer
/// paints, and it is the prop's own colour rather than a UI accent — the row
/// of dots under a tile has to look like the thing it will place.
///
/// Leave `swatch` out when the members differ in shape rather than colour: no
/// dot can tell a conifer from a palm, so the drawer shows those variants as
/// the models themselves.
struct HomeIslandAssetVariant: Identifiable, Hashable, Sendable {
    let assetID: String
    let nameKey: String
    var swatch: UInt?

    var id: String { assetID }
    var name: String { LF.text(nameKey) }
}

/// A prop the player thinks of as one thing that comes in several. Without
/// this the drawer showed three hibiscus tiles, three rose tiles and two
/// benches, and the shelf read as a spreadsheet instead of a catalogue.
struct HomeIslandAssetFamily: Identifiable, Hashable, Sendable {
    let id: String
    let titleKey: String
    /// The icon the chooser row wears. Colours get a palette; a family that
    /// differs in shape gets its own silhouette instead.
    var symbolName = "paintpalette.fill"
    let variants: [HomeIslandAssetVariant]

    var title: String { LF.text(titleKey) }
    var assetIDs: [String] { variants.map(\.assetID) }

    /// Whether a row of dots can stand in for the models. It can only when
    /// every member carries its own colour.
    var showsSwatches: Bool { variants.allSatisfy { $0.swatch != nil } }
}

/// The shelves of the build drawer, in the order the chips show them.
/// Membership lives in `HomeIslandAssetCatalog.group(of:)`.
enum HomeIslandAssetGroup: String, CaseIterable, Sendable {
    case nature
    case structures
    case decor
    case paths
    case furniture
}

/// アセット側が要求するキャラモーション。寝具を追加するときも接触ソケットと
/// モーションをカタログへ登録するだけで判別できる。
enum HomeIslandContactMotion: String, Codable, Hashable, Sendable {
    case sit
    case lie
}

/// A stable, reservable contact point inside one placed Home Island asset.
/// Multiplayer can address a slot with `(placementID, id)` and synchronize
/// occupants without allowing two players to claim the same transform.
struct HomeIslandContactSlotDefinition: Identifiable, Hashable, Sendable {
    let id: String
    let motion: HomeIslandContactMotion
    let seatNodeName: String
    let approachNodeName: String
    let facesAwayFromApproach: Bool
    let seatPlanarOffset: Float?
    let approachClearance: Float?
    /// Whether the player may walk into this seat from any side.
    ///
    /// A slot normally has one standing spot — its approach socket — and the
    /// player has to be on it to sit. That is right for a bench built into a
    /// row, and wrong for a chair standing in the open: a desk chair that can
    /// only be entered from behind sends the player walking a circle around
    /// it. When this is set the approach socket still says which way the
    /// navigator ends up facing, but no longer says where they must stand.
    let allowsEntryFromAnySide: Bool

    init(
        id: String,
        motion: HomeIslandContactMotion,
        seatNodeName: String,
        approachNodeName: String,
        facesAwayFromApproach: Bool = false,
        seatPlanarOffset: Float? = nil,
        approachClearance: Float? = nil,
        allowsEntryFromAnySide: Bool = false
    ) {
        self.id = id
        self.motion = motion
        self.seatNodeName = seatNodeName
        self.approachNodeName = approachNodeName
        self.facesAwayFromApproach = facesAwayFromApproach
        self.seatPlanarOffset = seatPlanarOffset
        self.approachClearance = approachClearance
        self.allowsEntryFromAnySide = allowsEntryFromAnySide
    }
}

/// Network-safe identity for one seat on one placed asset.
struct HomeIslandSeatAddress: Codable, Hashable, Sendable {
    let placementID: UUID
    let slotID: String
}

enum HomeIslandAssetCatalog {
    /// Harbor equipment authored into every island at deterministic positions.
    /// The moored boat is also fixed, but is rendered from BoatCustomization
    /// rather than participating in the placeable-asset catalog.
    static let allUsersFixedAssetIDs: Set<String> = [
        "voyage_notice_board",
        "wooden_jetty",
        "harbor_boarding_float",
        "harbor_welcome_beacon",
    ]

    /// Saved instances remain in snapshots while these props are withheld.
    private static let temporarilyHiddenAssetIDs: Set<String> = [
        "navigator_hammock",
    ]

    private static let smallStumpSeatSlots = [
        HomeIslandContactSlotDefinition(
            id: "stump",
            motion: .sit,
            seatNodeName: "SeatSocket_Stump",
            approachNodeName: "SeatApproach_Stump",
            seatPlanarOffset: 0,
            approachClearance: 0.05
        ),
    ]

    /// Shared by every bench: the stone bench is authored from the driftwood
    /// bench's own envelope, so both carry these sockets at identical heights.
    ///
    /// The bench sockets already sit in the middle of a 0.36 deep seat, so the
    /// default backrest clearance — which pushes the body 0.145 toward the
    /// approach — parked the navigator on the front lip, looking like they were
    /// standing in front of the bench rather than sitting on it. Nought keeps
    /// them on the socket.
    private static let benchSeatSlots = [
        HomeIslandContactSlotDefinition(
            id: "left",
            motion: .sit,
            seatNodeName: "SeatSocket_Left",
            approachNodeName: "SeatApproach_Left",
            seatPlanarOffset: 0
        ),
        HomeIslandContactSlotDefinition(
            id: "right",
            motion: .sit,
            seatNodeName: "SeatSocket_Right",
            approachNodeName: "SeatApproach_Right",
            seatPlanarOffset: 0
        ),
    ]

    private static let navigatorHammockContactSlots = [
        HomeIslandContactSlotDefinition(
            id: "center",
            motion: .lie,
            seatNodeName: "SleepSocket_Center",
            approachNodeName: "SleepApproach_Center"
        ),
    ]

    /// The council chair is a single seat the player positions themselves, so
    /// the navigator walks in from the front and sits with the backrest behind.
    private static let councilChairSeatSlots = [
        HomeIslandContactSlotDefinition(
            id: "seat",
            motion: .sit,
            seatNodeName: "SeatSocket_Seat",
            approachNodeName: "SeatApproach_Seat"
        ),
    ]

    /// The desk chair is entered from wherever the player happens to be. Its
    /// approach socket sits behind the backrest and `facesAwayFromApproach`
    /// turns that around into a facing, so the navigator always ends up
    /// looking over the front of the chair — at the desk, if there is one —
    /// no matter which side they walked in from.
    private static let officeChairSeatSlots = [
        HomeIslandContactSlotDefinition(
            id: "seat",
            motion: .sit,
            seatNodeName: "SeatSocket_Seat",
            approachNodeName: "SeatApproach_Seat",
            facesAwayFromApproach: true,
            // The default inset for a seat faced away from its approach is
            // 0.10, which is a council stool's depth. On a 0.38 deep desk
            // chair it perched the navigator on the front lip; 0.02 sets them
            // in the middle of the pad with the backrest at their back.
            seatPlanarOffset: -0.02,
            approachClearance: 0.05,
            allowsEntryFromAnySide: true
        ),
    ]

    /// The log that used to sit in the campfire's ring. No backrest, so it is
    /// entered from the front and sat on facing back out, exactly like the
    /// benches — and like them the body belongs on the socket rather than
    /// pushed forward off a backrest that is not there.
    private static let logStoolSeatSlots = [
        HomeIslandContactSlotDefinition(
            id: "seat",
            motion: .sit,
            seatNodeName: "SeatSocket_Seat",
            approachNodeName: "SeatApproach_Seat",
            seatPlanarOffset: 0,
            approachClearance: 0.05
        ),
    ]

    static func contactSlots(for assetID: String) -> [HomeIslandContactSlotDefinition] {
        switch assetID {
        case "small_stump":
            smallStumpSeatSlots
        case "driftwood_bench", "stone_bench":
            benchSeatSlots
        case "navigator_hammock":
            navigatorHammockContactSlots
        case "council_chair":
            councilChairSeatSlots
        case "office_chair", "office_chair_pink":
            officeChairSeatSlots
        case "log_stool":
            logStoolSeatSlots
        default:
            []
        }
    }

    static func seatSlots(for assetID: String) -> [HomeIslandContactSlotDefinition] {
        contactSlots(for: assetID).filter { $0.motion == .sit }
    }

    static func seatingCapacity(for assetID: String) -> Int {
        seatSlots(for: assetID).count
    }

    /// Assets whose operator-approved calibration replaces every previously
    /// saved instance as well as becoming the default for new placements.
    /// Add an asset ID here when its final simulator percentage is approved.
    private static let calibratedScaleAssetIDs: Set<String> = [
        "small_stump",
        "small_rock",
        // Sizes the operator set by eye in the simulator. Listing them here
        // applies the calibration to islands that already have one placed.
        "sandcastle"
    ]

    /// Only these operator-approved assets can enter player-authored islands.
    /// Keeping this allowlist independent from 3D Studio prevents developer or
    /// terrain tools from leaking into the consumer placement experience.
    ///
    /// The order here is the order the build drawer shows: category by
    /// category in the same sequence as the category chips, and inside each
    /// one grouped into sets rather than sorted by unlock level. Level and
    /// the Voyage Pass are applied on top of this by the drawer itself, which
    /// sends anything the player cannot place today to the back — so this list
    /// is free to read as a furniture catalogue instead of a progression table.
    static let approved: [HomeIslandAsset] = [
        // Nature: trees first, then what grows low, then flowers, stone, water.
        HomeIslandAsset(
            id: "conifer_tree",
            titleKey: "Conifer",
            symbolName: "tree.fill",
            defaultScale: 1.20,
            footprintMargin: 0.40,
            unlockLevel: 1
        ),
        HomeIslandAsset(
            id: "palm_tree",
            titleKey: "Palm Tree",
            symbolName: "tree.fill",
            defaultScale: 1.00,
            footprintMargin: 0.85,
            unlockLevel: 4
        ),
        HomeIslandAsset(
            id: "small_stump",
            titleKey: "Small Stump",
            symbolName: "tree.fill",
            defaultScale: 0.66,
            footprintMargin: 0.60,
            unlockLevel: 4
        ),
        HomeIslandAsset(
            id: "dune_grass_patch",
            titleKey: "Dune Grass Patch",
            symbolName: "leaf.fill",
            defaultScale: 0.82,
            footprintMargin: 0.78,
            unlockLevel: 4
        ),
        HomeIslandAsset(
            id: "hibiscus_bush_red",
            titleKey: "Red Hibiscus",
            symbolName: "camera.macro",
            defaultScale: 1.00,
            footprintMargin: 0.42,
            unlockLevel: 2
        ),
        HomeIslandAsset(
            id: "hibiscus_bush_pink",
            titleKey: "Pink Hibiscus",
            symbolName: "camera.macro",
            defaultScale: 1.00,
            footprintMargin: 0.42,
            unlockLevel: 2
        ),
        HomeIslandAsset(
            id: "hibiscus_bush_orange",
            titleKey: "Orange Hibiscus",
            symbolName: "camera.macro",
            defaultScale: 1.00,
            footprintMargin: 0.42,
            unlockLevel: 2
        ),
        HomeIslandAsset(
            id: "rose_bush_white",
            titleKey: "White Roses",
            symbolName: "camera.macro",
            defaultScale: 1.00,
            footprintMargin: 0.42,
            unlockLevel: 4,
            requiresPass: true
        ),
        HomeIslandAsset(
            id: "rose_bush_red",
            titleKey: "Red Roses",
            symbolName: "camera.macro",
            defaultScale: 1.00,
            footprintMargin: 0.42,
            unlockLevel: 4,
            requiresPass: true
        ),
        HomeIslandAsset(
            id: "rose_bush_yellow",
            titleKey: "Yellow Roses",
            symbolName: "camera.macro",
            defaultScale: 1.00,
            footprintMargin: 0.42,
            unlockLevel: 4,
            requiresPass: true
        ),
        HomeIslandAsset(
            id: "small_rock",
            titleKey: "Small Rock",
            symbolName: "mountain.2.fill",
            defaultScale: 0.70,
            footprintMargin: 0.55,
            unlockLevel: 1
        ),
        HomeIslandAsset(
            id: "coastal_rocks",
            titleKey: "Coastal Rocks",
            symbolName: "mountain.2.fill",
            defaultScale: 0.72,
            footprintMargin: 1.90,
            unlockLevel: 13
        ),
        HomeIslandAsset(
            id: "small_lake",
            titleKey: "Small Lake",
            symbolName: "water.waves",
            defaultScale: 0.82,
            footprintMargin: 0.88,
            unlockLevel: 5
        ),
        // Structures: somewhere to sleep, then to see by, then the landmarks.
        HomeIslandAsset(
            id: "navigator_tent",
            titleKey: "Navigator's Tent",
            symbolName: "tent.fill",
            defaultScale: 0.62,
            footprintMargin: 1.98,
            unlockLevel: 2
        ),
        HomeIslandAsset(
            id: "weathered_cottage",
            titleKey: "Weathered Cottage",
            symbolName: "house.fill",
            defaultScale: 0.78,
            footprintMargin: 0.92,
            unlockLevel: 4,
            requiresPass: true
        ),
        HomeIslandAsset(
            id: "small_lighthouse",
            titleKey: "Small Lighthouse",
            symbolName: "light.beacon.max.fill",
            defaultScale: 0.72,
            footprintMargin: 0.68,
            unlockLevel: 4
        ),
        HomeIslandAsset(
            id: "weathered_lighthouse",
            titleKey: "Stone Lighthouse",
            symbolName: "light.beacon.max.fill",
            defaultScale: 0.68,
            footprintMargin: 0.82,
            unlockLevel: 6
        ),
        HomeIslandAsset(
            id: "stone_well",
            titleKey: "Stone Well",
            symbolName: "drop.fill",
            defaultScale: 0.76,
            footprintMargin: 1.14,
            unlockLevel: 7
        ),
        HomeIslandAsset(
            id: "cliff_lookout",
            titleKey: "Cliff Lookout",
            symbolName: "binoculars.fill",
            defaultScale: 0.72,
            footprintMargin: 1.90,
            unlockLevel: 9
        ),
        HomeIslandAsset(
            id: "mossy_ruins",
            titleKey: "Mossy Ruins",
            symbolName: "building.columns.fill",
            defaultScale: 0.70,
            footprintMargin: 1.62,
            unlockLevel: 10
        ),
        // Decor: firelight, then working harbour gear, then the voyage's own
        // marks, and finally the things a beach day leaves behind.
        HomeIslandAsset(
            id: "campfire_circle",
            titleKey: "Campfire",
            symbolName: "flame.fill",
            defaultScale: 0.72,
            // The seating used to be part of this prop, and the margin had to
            // clear the whole ring of benches. What is left is the fire and
            // the moss around it. The saved ID stays `campfire_circle` so
            // every island that already has one keeps it.
            footprintMargin: 0.86,
            unlockLevel: 1
        ),
        HomeIslandAsset(
            id: "harbor_lantern_post",
            titleKey: "Harbor Lantern Post",
            symbolName: "lightbulb.fill",
            defaultScale: 0.76,
            footprintMargin: 0.68,
            unlockLevel: 6
        ),
        HomeIslandAsset(
            id: "weathered_crate",
            titleKey: "Weathered Crate",
            symbolName: "shippingbox.fill",
            defaultScale: 0.88,
            footprintMargin: 0.46,
            unlockLevel: 4
        ),
        HomeIslandAsset(
            id: "supply_barrels",
            titleKey: "Supply Barrels",
            symbolName: "cylinder.split.1x2",
            defaultScale: 0.80,
            footprintMargin: 0.92,
            unlockLevel: 8
        ),
        HomeIslandAsset(
            id: "weathered_anchor",
            titleKey: "Weathered Anchor",
            symbolName: "anchor",
            defaultScale: 0.76,
            footprintMargin: 0.86,
            unlockLevel: 7
        ),
        HomeIslandAsset(
            id: "net_drying_rack",
            titleKey: "Net Drying Rack",
            symbolName: "grid",
            defaultScale: 0.74,
            footprintMargin: 1.18,
            unlockLevel: 8
        ),
        HomeIslandAsset(
            id: "voyage_flagpole",
            titleKey: "Voyage Flagpole",
            symbolName: "flag.fill",
            defaultScale: 0.72,
            footprintMargin: 1.10,
            unlockLevel: 8
        ),
        HomeIslandAsset(
            id: "voyage_signal_bell",
            titleKey: "Voyage Signal Bell",
            symbolName: "bell.fill",
            defaultScale: 0.76,
            footprintMargin: 0.72,
            unlockLevel: 10
        ),
        HomeIslandAsset(
            id: "beach_parasol",
            titleKey: "Beach Parasol",
            symbolName: "umbrella.fill",
            defaultScale: 1.00,
            footprintMargin: 0.56,
            unlockLevel: 5
        ),
        HomeIslandAsset(
            id: "swim_ring",
            titleKey: "Swim Ring",
            symbolName: "lifepreserver.fill",
            defaultScale: 1.00,
            footprintMargin: 0.24,
            unlockLevel: 5
        ),
        HomeIslandAsset(
            id: "sandcastle",
            titleKey: "Sandcastle",
            symbolName: "building.2.fill",
            defaultScale: 1.60,
            footprintMargin: 0.48,
            unlockLevel: 6
        ),
        HomeIslandAsset(
            id: "watermelon",
            titleKey: "Watermelon",
            symbolName: "leaf.fill",
            defaultScale: 1.00,
            footprintMargin: 0.26,
            unlockLevel: 6
        ),
        HomeIslandAsset(
            id: "seaside_mailbox",
            titleKey: "Seaside Mailbox",
            symbolName: "envelope.fill",
            defaultScale: 1.00,
            footprintMargin: 0.40,
            unlockLevel: 5
        ),
        HomeIslandAsset(
            id: "seaside_gramophone",
            titleKey: "Seaside Gramophone",
            symbolName: "music.note",
            defaultScale: 1.00,
            footprintMargin: 0.38,
            unlockLevel: 6
        ),
        // Paths: the three pieces that join up, then the inlay they lead to.
        HomeIslandAsset(
            id: "stone_path_straight",
            titleKey: "Stone Path — Straight",
            symbolName: "square.grid.3x3.fill",
            defaultScale: 0.78,
            footprintMargin: 1.50,
            unlockLevel: 12
        ),
        HomeIslandAsset(
            id: "stone_path_curve",
            titleKey: "Stone Path — Curve",
            symbolName: "square.grid.3x3.fill",
            defaultScale: 0.78,
            footprintMargin: 1.62,
            unlockLevel: 12
        ),
        HomeIslandAsset(
            id: "stone_path_fork",
            titleKey: "Stone Path — Fork",
            symbolName: "square.grid.3x3.fill",
            defaultScale: 0.78,
            footprintMargin: 1.60,
            unlockLevel: 12
        ),
        HomeIslandAsset(
            id: "compass_rose_inlay",
            titleKey: "Compass Rose Inlay",
            symbolName: "location.north.circle.fill",
            defaultScale: 0.78,
            footprintMargin: 1.18,
            unlockLevel: 11
        ),
        // Furniture, in sets: the desk and what stands on it, the council pair,
        // benches, then reading.
        HomeIslandAsset(
            id: "office_desk",
            titleKey: "Desk",
            symbolName: "table.furniture.fill",
            defaultScale: 1.00,
            footprintMargin: 0.46,
            unlockLevel: 2
        ),
        HomeIslandAsset(
            id: "office_desk_pink",
            titleKey: "Desk (Pink)",
            symbolName: "table.furniture.fill",
            defaultScale: 1.00,
            footprintMargin: 0.46,
            unlockLevel: 2
        ),
        HomeIslandAsset(
            id: "office_chair",
            titleKey: "Chair",
            symbolName: "chair.fill",
            defaultScale: 1.00,
            footprintMargin: 0.44,
            unlockLevel: 2
        ),
        HomeIslandAsset(
            id: "office_chair_pink",
            titleKey: "Chair (Pink)",
            symbolName: "chair.fill",
            defaultScale: 1.00,
            footprintMargin: 0.44,
            unlockLevel: 2
        ),
        HomeIslandAsset(
            id: "silver_laptop",
            titleKey: "PC",
            symbolName: "laptopcomputer",
            defaultScale: 1.00,
            footprintMargin: 0.30,
            unlockLevel: 2
        ),
        // Something to put down beside the laptop. The three share one tile in
        // the drawer, and each is authored at the size the real thing is: the
        // water bottle stands 0.190 against the desk's 0.420, which is how a
        // bottle on a desk reads.
        HomeIslandAsset(
            id: "spring_water_bottle",
            titleKey: "Water Bottle",
            symbolName: "waterbottle.fill",
            defaultScale: 1.00,
            footprintMargin: 0.18,
            unlockLevel: 2
        ),
        HomeIslandAsset(
            id: "sparkling_water_bottle",
            titleKey: "Sparkling Water",
            symbolName: "waterbottle.fill",
            defaultScale: 1.00,
            footprintMargin: 0.18,
            unlockLevel: 2
        ),
        HomeIslandAsset(
            id: "canned_coffee",
            titleKey: "Canned Coffee",
            symbolName: "cup.and.saucer.fill",
            defaultScale: 1.00,
            footprintMargin: 0.16,
            unlockLevel: 2
        ),
        HomeIslandAsset(
            id: "council_table",
            titleKey: "Council Table",
            symbolName: "table.furniture.fill",
            defaultScale: 0.72,
            footprintMargin: 0.92,
            unlockLevel: 3
        ),
        HomeIslandAsset(
            id: "council_chair",
            titleKey: "Council Chair",
            symbolName: "chair.fill",
            defaultScale: 0.72,
            footprintMargin: 0.62,
            unlockLevel: 3
        ),
        HomeIslandAsset(
            id: "driftwood_bench",
            titleKey: "Driftwood Bench",
            symbolName: "chair.fill",
            defaultScale: 0.62,
            footprintMargin: 1.08,
            unlockLevel: 3
        ),
        HomeIslandAsset(
            id: "stone_bench",
            titleKey: "Stone Bench",
            symbolName: "chair.fill",
            defaultScale: 0.62,
            footprintMargin: 1.08,
            unlockLevel: 5
        ),
        HomeIslandAsset(
            id: "log_stool",
            titleKey: "Log Stool",
            symbolName: "chair.fill",
            defaultScale: 1.00,
            footprintMargin: 0.62,
            unlockLevel: 1
        ),
        HomeIslandAsset(
            id: "wooden_bookshelf",
            titleKey: "Bookshelf",
            symbolName: "books.vertical.fill",
            defaultScale: 1.00,
            footprintMargin: 0.42,
            unlockLevel: 4,
            requiresPass: true
        ),
        HomeIslandAsset(
            id: "stacked_books",
            titleKey: "Stacked Books",
            symbolName: "book.closed.fill",
            defaultScale: 1.00,
            footprintMargin: 0.24,
            unlockLevel: 3,
            requiresPass: true
        ),
        HomeIslandAsset(
            id: "navigator_hammock",
            titleKey: "Navigator's Hammock",
            symbolName: "bed.double.fill",
            defaultScale: 0.52,
            footprintMargin: 1.45,
            unlockLevel: 9
        ),
    ]

    static var approvedIDs: Set<String> { Set(approved.map(\.id)) }

    /// A flat top the navigator can stand on, once they are high enough to be
    /// on it. Rocks are what this is for: their sides are far taller than a
    /// step, so the only way up is a jump — which is the point of a rock being
    /// there at all.
    ///
    /// The shape is an ellipse in the asset's own frame, because a rock is
    /// round and a rectangle would offer corners the model does not have.
    /// Heights and half-axes are authored units; the placement's scale
    /// multiplies them, so a bigger rock really is a harder climb.
    struct StandableLedge {
        let assetID: String
        var x: Float = 0
        var z: Float = 0
        let halfWidth: Float
        let halfDepth: Float
        let topHeight: Float
    }

    /// Measured off the models themselves, at the height where each mesh has
    /// already flattened out, so standing on a ledge is standing on rock
    /// rather than hovering over it.
    static let standableLedges: [StandableLedge] = [
        // One dome, one perch, right at the top.
        StandableLedge(
            assetID: "small_rock",
            halfWidth: 0.45,
            halfDepth: 0.40,
            topHeight: 0.70
        ),
        // The cluster is climbed in two hops. Its summit is out of reach from
        // the sand on purpose: the shoulder that rings it is the first step,
        // and the top is the second.
        StandableLedge(
            assetID: "coastal_rocks",
            z: -0.30,
            halfWidth: 1.35,
            halfDepth: 0.82,
            topHeight: 0.80
        ),
        StandableLedge(
            assetID: "coastal_rocks",
            z: -0.25,
            halfWidth: 0.70,
            halfDepth: 0.55,
            topHeight: 1.36
        ),
    ]

    private static let standableLedgesByAssetID: [String: [StandableLedge]] = {
        var index: [String: [StandableLedge]] = [:]
        for ledge in standableLedges {
            index[ledge.assetID, default: []].append(ledge)
        }
        return index
    }()

    static func standableLedges(for assetID: String) -> [StandableLedge] {
        standableLedgesByAssetID[assetID] ?? []
    }

    /// A prop with a working surface: how high its top stands at scale 1, how
    /// far the usable rectangle reaches from the prop's centre along its own
    /// axes, and what is allowed to stand on it.
    struct Surface {
        let assetID: String
        let topHeight: Float
        let halfWidth: Float
        let halfDepth: Float
        let accepts: Set<String>
    }

    /// Numbers copied from `Tools/Blender/build_office_desk.py`: the top is
    /// 0.420 high and 1.060 by 0.520 across, so the usable rectangle is that
    /// whole top — 0.530 by 0.260 from the centre.
    ///
    /// It used to be the top pulled in by the laptop's own half-size, which
    /// kept a laptop from ever hanging over the lip but left only the middle
    /// two thirds of the desk usable: dragging one toward either end, or
    /// toward the front rail, dropped it off the desk onto the sand well
    /// before it looked like it had left the desk. The whole top now counts,
    /// and a laptop set right at the edge overhangs it, exactly as one set
    /// down at the edge of a real desk does.
    static let surfaces: [Surface] = [
        Surface(
            assetID: "office_desk",
            topHeight: 0.420,
            halfWidth: 0.530,
            halfDepth: 0.260,
            accepts: [
                "silver_laptop",
                "spring_water_bottle", "sparkling_water_bottle", "canned_coffee",
            ]
        ),
        // The pink desk is the same desk in another palette, so it carries the
        // same top. Painting one does not stop a laptop standing on it.
        Surface(
            assetID: "office_desk_pink",
            topHeight: 0.420,
            halfWidth: 0.530,
            halfDepth: 0.260,
            accepts: [
                "silver_laptop",
                "spring_water_bottle", "sparkling_water_bottle", "canned_coffee",
            ]
        ),
    ]

    /// Props that stand on something else rather than on the ground.
    static let surfaceGuestIDs: Set<String> = Set(surfaces.flatMap(\.accepts))

    /// Whether this prop offers a top that other props stand on.
    static func isSurfaceHost(assetID: String) -> Bool {
        surfaces.contains { $0.assetID == assetID }
    }

    /// How high a prop rests, given where everything else on the island stands.
    ///
    /// Derived every frame rather than saved with the placement: sliding the
    /// desk out from under the laptop sets the laptop back down on the sand,
    /// deleting the desk does the same, and no snapshot — local, synced, or
    /// from a visitor's island — has to learn a new field.
    static func restingHeight(
        assetID: String,
        x: Float,
        z: Float,
        among placements: [HomeIslandPlacement],
        excluding excludedID: UUID?
    ) -> Float {
        var height: Float = 0
        for surface in surfaces where surface.accepts.contains(assetID) {
            for host in placements
            where host.assetID == surface.assetID && host.id != excludedID {
                let scale = max(0.05, host.transform.scale)
                // Into the desk's own frame, so a rotated desk still keeps a
                // rectangular top instead of a diamond.
                let dx = x - host.transform.x
                let dz = z - host.transform.z
                let cosYaw = cos(host.transform.yaw)
                let sinYaw = sin(host.transform.yaw)
                let localX = dx * cosYaw - dz * sinYaw
                let localZ = dx * sinYaw + dz * cosYaw
                guard abs(localX) <= surface.halfWidth * scale,
                      abs(localZ) <= surface.halfDepth * scale
                else { continue }
                height = max(height, surface.topHeight * scale)
            }
        }
        return height
    }

    /// Temporarily keeps unfinished assets out of customer builds without
    /// deleting their saved placements. Debug tuning can opt them back in.
    static func isVisibleInCurrentBuild(assetID: String) -> Bool {
        guard temporarilyHiddenAssetIDs.contains(assetID) else { return true }
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["LANDFALL_SHOW_HIDDEN_HOME_ASSETS"] == "1" {
            return true
        }
        return assetID == "small_stump"
            && (environment["LANDFALL_SHOW_STUMP"] == "1"
                || environment["LANDFALL_SEAT_DEMO"] == "stump")
        #else
        return false
        #endif
    }

    static func available(in bundle: Bundle = .main) -> [HomeIslandAsset] {
        approved.filter { asset in
            isUserPlaceable(assetID: asset.id)
                && (asset.id == "small_lake"
                    || bundle.url(forResource: asset.id, withExtension: "usdz") != nil)
        }
    }

    static func isUserPlaceable(assetID: String) -> Bool {
        approvedIDs.contains(assetID)
            && !allUsersFixedAssetIDs.contains(assetID)
            && isVisibleInCurrentBuild(assetID: assetID)
    }

    static func asset(id: String) -> HomeIslandAsset? {
        approved.first { $0.id == id }
    }

    static func persistedScale(assetID: String, storedScale: Float) -> Float {
        guard calibratedScaleAssetIDs.contains(assetID),
              let asset = asset(id: assetID)
        else { return storedScale }
        return asset.defaultScale
    }

    /// Trees, rocks and flowers are turned by a stable angle taken from their
    /// own identifier. Everything built by hand keeps the facing it was
    /// authored with, so jetties, paths and furniture stay square.
    static func naturalFacing(assetID: String, id: UUID) -> Float {
        switch assetID {
        case "conifer_tree", "palm_tree", "small_rock",
             "small_stump", "coastal_rocks", "dune_grass_patch",
             "rose_bush_white", "rose_bush_red", "rose_bush_yellow",
             "hibiscus_bush_red", "hibiscus_bush_pink", "hibiscus_bush_orange":
            let hashed = UInt32(truncatingIfNeeded: id.hashValue)
            return Float(hashed % 3600) / 3600 * 2 * .pi
        default:
            return 0
        }
    }

    /// Most props are intentionally scarce. Natural ground details can be
    /// repeated more freely so players can shape a convincing island edge.
    /// How many of one prop a player may place, stated per group because that
    /// is how the rule reads: ten of anything that grows or paves, three of
    /// everything else.
    ///
    /// Nature and paths are the two things an island is *made* of — a grove,
    /// a border, a path that actually reaches somewhere — so they get the
    /// room. Everything else is furniture and landmarks, where three is
    /// already a set and more only makes an island look like a warehouse.
    /// Props that come in more than one. A family's tile sits where its first
    /// variant would have, and the rest never get a tile of their own.
    ///
    /// Each member stays its own asset with its own saved placements and its
    /// own limit — this only changes how they are offered. Nothing already
    /// placed moves or changes.
    static let families: [HomeIslandAssetFamily] = [
        // A player looking for somewhere to plant is looking for "a tree",
        // not for a conifer: the kind is the second question, asked after
        // the tile is tapped.
        HomeIslandAssetFamily(
            id: "tree",
            titleKey: "Tree",
            symbolName: "tree.fill",
            variants: [
                HomeIslandAssetVariant(
                    assetID: "conifer_tree",
                    nameKey: "Conifer"
                ),
                HomeIslandAssetVariant(
                    assetID: "palm_tree",
                    nameKey: "Palm Tree"
                ),
            ]
        ),
        // Same question as the tree: a player clearing a shore is looking for
        // "a rock". Whether it is one boulder or a whole reef is what the
        // chooser is for.
        HomeIslandAssetFamily(
            id: "rock",
            titleKey: "Rock",
            symbolName: "mountain.2.fill",
            variants: [
                HomeIslandAssetVariant(
                    assetID: "small_rock",
                    nameKey: "Small Rock"
                ),
                HomeIslandAssetVariant(
                    assetID: "coastal_rocks",
                    nameKey: "Coastal Rocks"
                ),
            ]
        ),
        HomeIslandAssetFamily(
            id: "hibiscus",
            titleKey: "Hibiscus",
            variants: [
                HomeIslandAssetVariant(
                    assetID: "hibiscus_bush_red",
                    nameKey: "Red",
                    swatch: 0xD5495A
                ),
                HomeIslandAssetVariant(
                    assetID: "hibiscus_bush_pink",
                    nameKey: "Pink",
                    swatch: 0xE9779E
                ),
                HomeIslandAssetVariant(
                    assetID: "hibiscus_bush_orange",
                    nameKey: "Orange",
                    swatch: 0xE8853C
                ),
            ]
        ),
        HomeIslandAssetFamily(
            id: "rose",
            titleKey: "Roses",
            variants: [
                HomeIslandAssetVariant(
                    assetID: "rose_bush_white",
                    nameKey: "White",
                    swatch: 0xF2EDE2
                ),
                HomeIslandAssetVariant(
                    assetID: "rose_bush_red",
                    nameKey: "Red",
                    swatch: 0xC33A45
                ),
                HomeIslandAssetVariant(
                    assetID: "rose_bush_yellow",
                    nameKey: "Yellow",
                    swatch: 0xE8C44E
                ),
            ]
        ),
        HomeIslandAssetFamily(
            id: "lighthouse",
            titleKey: "Lighthouse",
            symbolName: "light.beacon.max.fill",
            variants: [
                HomeIslandAssetVariant(
                    assetID: "small_lighthouse",
                    nameKey: "White"
                ),
                HomeIslandAssetVariant(
                    assetID: "weathered_lighthouse",
                    nameKey: "Stone"
                ),
            ]
        ),
        HomeIslandAssetFamily(
            id: "bench",
            titleKey: "Bench",
            variants: [
                HomeIslandAssetVariant(
                    assetID: "driftwood_bench",
                    nameKey: "Wood",
                    swatch: 0x6A513D
                ),
                HomeIslandAssetVariant(
                    assetID: "stone_bench",
                    nameKey: "Stone",
                    swatch: 0x9AA09C
                ),
            ]
        ),
        HomeIslandAssetFamily(
            id: "office_chair",
            titleKey: "Chair",
            variants: [
                HomeIslandAssetVariant(
                    assetID: "office_chair",
                    nameKey: "Black",
                    swatch: 0x23272B
                ),
                HomeIslandAssetVariant(
                    assetID: "office_chair_pink",
                    nameKey: "Pink",
                    swatch: 0xEE9DB4
                ),
            ]
        ),
        // Three different drinks rather than three colours of one, so the
        // chooser shows the models: which drink it is, is the whole question.
        HomeIslandAssetFamily(
            id: "drink",
            titleKey: "Drinks",
            symbolName: "waterbottle.fill",
            variants: [
                HomeIslandAssetVariant(
                    assetID: "spring_water_bottle",
                    nameKey: "Water"
                ),
                HomeIslandAssetVariant(
                    assetID: "sparkling_water_bottle",
                    nameKey: "Sparkling"
                ),
                HomeIslandAssetVariant(
                    assetID: "canned_coffee",
                    nameKey: "Coffee"
                ),
            ]
        ),
        HomeIslandAssetFamily(
            id: "office_desk",
            titleKey: "Desk",
            variants: [
                HomeIslandAssetVariant(
                    assetID: "office_desk",
                    nameKey: "Black",
                    swatch: 0x23272B
                ),
                HomeIslandAssetVariant(
                    assetID: "office_desk_pink",
                    nameKey: "Pink",
                    swatch: 0xEE9DB4
                ),
            ]
        ),
    ]

    private static let familyByAssetID: [String: HomeIslandAssetFamily] = {
        var index: [String: HomeIslandAssetFamily] = [:]
        for family in families {
            for variant in family.variants {
                index[variant.assetID] = family
            }
        }
        return index
    }()

    static func family(containing assetID: String) -> HomeIslandAssetFamily? {
        familyByAssetID[assetID]
    }

    /// Which shelf of the build drawer a prop belongs on. The drawer's chips
    /// read this, and so does `placementLimit`, so the two can never drift
    /// into disagreeing about what counts as "nature".
    static func group(of assetID: String) -> HomeIslandAssetGroup? {
        switch assetID {
        case "conifer_tree", "palm_tree", "small_stump",
             "dune_grass_patch",
             "hibiscus_bush_red", "hibiscus_bush_pink", "hibiscus_bush_orange",
             "rose_bush_white", "rose_bush_red", "rose_bush_yellow",
             "small_rock", "coastal_rocks", "small_lake":
            .nature
        case "navigator_tent", "weathered_cottage",
             "small_lighthouse", "weathered_lighthouse",
             "stone_well", "cliff_lookout", "mossy_ruins":
            .structures
        case "campfire_circle", "harbor_lantern_post",
             "weathered_crate", "supply_barrels", "weathered_anchor",
             "net_drying_rack",
             "voyage_flagpole", "voyage_signal_bell",
             "beach_parasol", "swim_ring", "sandcastle", "watermelon",
             "seaside_mailbox", "seaside_gramophone":
            .decor
        case "stone_path_straight", "stone_path_curve", "stone_path_fork",
             "compass_rose_inlay":
            .paths
        case "office_desk", "office_desk_pink",
             "office_chair", "office_chair_pink", "silver_laptop",
             "spring_water_bottle", "sparkling_water_bottle", "canned_coffee",
             "council_table", "council_chair",
             "driftwood_bench", "stone_bench", "log_stool",
             "wooden_bookshelf", "stacked_books",
             "navigator_hammock":
            .furniture
        default:
            nil
        }
    }

    static func placementLimit(for assetID: String) -> Int {
        switch group(of: assetID) {
        case .nature, .paths:
            10
        default:
            3
        }
    }

    /// Simulator builds expose the complete catalog so island interactions and
    /// placement can be tested without seeding many hours of study history.
    static func isUnlocked(_ asset: HomeIslandAsset, playerLevel: Int) -> Bool {
        #if targetEnvironment(simulator)
        true
        #else
        playerLevel >= asset.unlockLevel
        #endif
    }

    /// A second lock, independent of level. It is asked only when something new
    /// is placed: a pass that lapses never takes back what the island already
    /// has, and no simulator escape hatch applies — an entitlement fails closed.
    static func isPassLocked(_ asset: HomeIslandAsset, hasVoyagePass: Bool) -> Bool {
        asset.requiresPass && !hasVoyagePass
    }

    static func footprintMargin(assetID: String, scale: Float) -> Float {
        guard let asset = asset(id: assetID) else { return 0 }
        return asset.footprintMargin
            * max(scale, 0.05)
            / max(asset.defaultScale, 0.05)
    }

    static func placementTransform(
        assetID: String,
        x: Float,
        z: Float,
        yaw: Float,
        scale: Float,
        requireValidCoastPoint: Bool,
        islandScale: Float = HomeIslandMetrics.maximumIslandScale
    ) -> HomeIslandTransform? {
        if assetID == "wooden_jetty" {
            guard let coast = HomeIslandMetrics.jettyCoastPlacement(
                nearX: x,
                z: z,
                requireCoastalInput: requireValidCoastPoint,
                islandScale: islandScale
            ) else { return nil }
            return HomeIslandTransform(
                x: coast.x,
                z: coast.z,
                yaw: coast.yaw,
                scale: scale
            )
        }

        let margin = footprintMargin(assetID: assetID, scale: scale)
        let position = HomeIslandMetrics.clampedPosition(
            x: x,
            z: z,
            footprintMargin: margin,
            islandScale: islandScale
        )
        return HomeIslandTransform(
            x: position.x,
            z: position.z,
            yaw: yaw,
            scale: scale
        )
    }

    /// Ground decorations are traversable; solid scenery becomes a walking
    /// obstacle.  Keeping this next to the placement allowlist means newly
    /// approved assets default to the safe (blocking) behaviour.
    static func blocksWalking(assetID: String) -> Bool {
        switch assetID {
        case "wooden_jetty",
             // The lookout is climbed rather than walked around: its deck and
             // stairs are a walk surface, and its own rail line does the
             // blocking. A body-sized obstacle here would seal the stairs.
             "cliff_lookout",
             // Rocks are climbed too. Their ledges are solid up to their own
             // tops and open above them, so a flat body-sized cylinder here
             // would be a lid: nothing could ever land on one.
             "small_rock",
             "coastal_rocks",
             "stone_path_straight",
             "stone_path_curve",
             "stone_path_fork",
             "compass_rose_inlay",
             "dune_grass_patch",
             // Flowers are planting, not scenery: the navigator walks through a
             // bed of roses exactly as if it were open ground.
             "rose_bush_white",
             "rose_bush_red",
             "rose_bush_yellow",
             "hibiscus_bush_red",
             "hibiscus_bush_pink",
             "hibiscus_bush_orange",
             // Ankle height: the navigator steps over these rather than
             // walking around them.
             "swim_ring",
             "watermelon",
             "stacked_books",
             // A laptop belongs on a desk. Standing on the sand it is small
             // enough to step over, and standing on a desk it is not on the
             // ground at all — a collider would fence off the very spot the
             // navigator has to reach to sit at the desk.
             "silver_laptop",
             // Same for what stands next to it: a bottle is ankle height on
             // the sand and is not on the ground at all once it is on the
             // desk, so neither is worth a collider.
             "spring_water_bottle", "sparkling_water_bottle", "canned_coffee":
            false
        default:
            true
        }
    }

    /// Walking collision is intentionally independent from the placement
    /// footprint. Wide interactive furniture needs generous placement space,
    /// but a much tighter body collider so the navigator can reach its
    /// authored interaction point.
    static func walkingCollisionRadius(assetID: String, scale: Float) -> Float {
        // A parasol and a palm are mostly canopy: blocking their full footprint
        // would fence off the shade, which is the point of standing there.
        // A bench is shallow and its seat is only 0.42 from its centre. The
        // footprint-derived collider was 0.78, which put the seat — and the
        // ground in front of it — inside the navigator's own no-go circle: the
        // player could not reach the bench, and standing up landed on an
        // invalid spot. The collider is now the frame itself.
        if assetID == "small_stump" {
            guard let asset = asset(id: assetID) else { return 0.30 }
            let scaleRatio = max(scale, 0.05) / max(asset.defaultScale, 0.05)
            return max(0.18, 0.30 * scaleRatio)
        }
        if assetID == "driftwood_bench" || assetID == "stone_bench"
            || assetID == "log_stool" {
            guard let asset = asset(id: assetID) else { return 0.30 }
            let scaleRatio = max(scale, 0.05) / max(asset.defaultScale, 0.05)
            return max(0.18, 0.30 * scaleRatio)
        }
        // Masts, posts and bells are thin: their footprint buys them visual
        // breathing room, but the body collider is the pole itself.
        switch assetID {
        case "voyage_flagpole", "harbor_lantern_post", "voyage_signal_bell",
             "weathered_anchor", "small_lighthouse", "seaside_mailbox":
            guard let asset = asset(id: assetID) else { return 0.24 }
            let scaleRatio = max(scale, 0.05) / max(asset.defaultScale, 0.05)
            return max(0.16, 0.26 * scaleRatio)
        default:
            break
        }
        if assetID == "beach_parasol" || assetID == "palm_tree" {
            guard let asset = asset(id: assetID) else { return 0.22 }
            let scaleRatio = max(scale, 0.05) / max(asset.defaultScale, 0.05)
            return max(0.14, (assetID == "palm_tree" ? 0.26 : 0.18) * scaleRatio)
        }
        if assetID == "navigator_hammock" {
            guard let asset = asset(id: assetID) else { return 0.54 }
            let scaleRatio = max(scale, 0.05) / max(asset.defaultScale, 0.05)
            return max(0.30, 0.54 * scaleRatio)
        }
        return max(0.25, footprintMargin(assetID: assetID, scale: scale) * 0.72)
    }

    /// A compact gameplay collision profile. Paths remain deliberately
    /// traversable and may sit beneath furniture or scenery; jetties only need
    /// separation from other jetties because their landward end touches sand.
    ///
    /// Deliberately much tighter than the authored footprint. The footprint
    /// describes the space a prop wants to look good in; this is only the space
    /// two props may not share, so islands can be arranged densely.
    static func placementCollisionRadius(assetID: String, scale: Float) -> Float {
        max(0.16, footprintMargin(assetID: assetID, scale: scale) * 0.38)
    }

    /// Planting is free-form: trees, flowers and grass may overlap each other
    /// and any other prop, which is how a believable grove, bed or border gets
    /// made. Their trunks still block walking — only placement is unrestricted.
    static func participatesInPlacementCollision(assetID: String) -> Bool {
        switch assetID {
        case "stone_path_straight", "stone_path_curve", "stone_path_fork",
             "compass_rose_inlay", "dune_grass_patch",
             "rose_bush_white", "rose_bush_red", "rose_bush_yellow",
             "hibiscus_bush_red", "hibiscus_bush_pink", "hibiscus_bush_orange",
             "conifer_tree", "palm_tree":
            false
        default:
            true
        }
    }

    static func interactionRadius(assetID: String, scale: Float) -> Float? {
        switch assetID {
        case "weathered_cottage", "navigator_tent":
            max(2.15, footprintMargin(assetID: assetID, scale: scale) + 1.25)
        case "campfire_circle":
            max(2.0, footprintMargin(assetID: assetID, scale: scale) + 0.85)
        default:
            nil
        }
    }
}

struct HomeIslandTransform: Codable, Equatable {
    var x: Float
    var z: Float
    var yaw: Float
    var scale: Float

    func apply(to node: SCNNode) {
        node.position = SCNVector3(x, HomeIslandMetrics.surfaceY, z)
        node.eulerAngles = SCNVector3(0, yaw, 0)
        let safeScale = max(0.05, scale)
        node.scale = SCNVector3(safeScale, safeScale, safeScale)
    }
}

struct HomeIslandPlacement: Identifiable, Codable, Equatable {
    var id: UUID
    var assetID: String
    var transform: HomeIslandTransform
}

/// This is deliberately suitable for a future read-only visitor payload.  The
/// current milestone persists it locally per owner; cloud transport can later
/// publish the same snapshot without exposing editor-only studio documents.
struct HomeIslandSnapshot: Codable, Equatable {
    var schemaVersion = 1
    var ownerKey: String
    var updatedAt: Date
    var placements: [HomeIslandPlacement]
}

enum HomeIslandPersistence {
    private struct Document: Codable {
        var version = 1
        var ownerKey: String
        var updatedAt: Date
        var placements: [HomeIslandPlacement]
    }

    private enum PersistenceError: Error {
        case verificationFailed(URL)
    }

    static func ownerKey(for ownerID: String) -> String {
        SHA256.hash(data: Data(ownerID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func directoryURL(ownerKey: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Landfall", isDirectory: true)
            .appendingPathComponent("HomeIslands", isDirectory: true)
            .appendingPathComponent(ownerKey, isDirectory: true)
    }

    static func fileURL(ownerKey: String) -> URL {
        directoryURL(ownerKey: ownerKey)
            .appendingPathComponent("HomeIsland.json", isDirectory: false)
    }

    static func recoveryFileURL(ownerKey: String) -> URL {
        directoryURL(ownerKey: ownerKey)
            .appendingPathComponent("HomeIsland.recovery.json", isDirectory: false)
    }

    private static func decodedDocument(at url: URL, ownerKey: String) -> (Document, Data)? {
        guard let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(Document.self, from: data),
              document.ownerKey == ownerKey
        else { return nil }
        return (document, data)
    }

    private static func loadDocument(ownerKey: String) -> Document? {
        let primary = decodedDocument(at: fileURL(ownerKey: ownerKey), ownerKey: ownerKey)
        let recovery = decodedDocument(at: recoveryFileURL(ownerKey: ownerKey), ownerKey: ownerKey)
        switch (primary, recovery) {
        case let (.some(primary), .some(recovery)):
            guard recovery.0.updatedAt > primary.0.updatedAt else { return primary.0 }
            try? recovery.1.write(to: fileURL(ownerKey: ownerKey), options: .atomic)
            return recovery.0
        case let (.some(primary), .none):
            return primary.0
        case let (.none, .some(recovery)):
            try? recovery.1.write(to: fileURL(ownerKey: ownerKey), options: .atomic)
            return recovery.0
        case (.none, .none):
            return nil
        }
    }

    /// The same defensive boundary is used for local documents and untrusted
    /// multiplayer snapshots. Keeping it file-private lets the in-memory
    /// visitor store reuse the exact persistence validation without exposing a
    /// general-purpose editor API to the rest of the app.
    ///
    /// It validates shape, never entitlement: neither unlock level nor the
    /// Voyage Pass is consulted, so an island keeps everything it was built
    /// with. Only placing something new asks whether the pass is active.
    fileprivate static func sanitized(_ placements: [HomeIslandPlacement]) -> [HomeIslandPlacement] {
        var counts: [String: Int] = [:]
        var seenIDs: Set<UUID> = []
        var result: [HomeIslandPlacement] = []
        result.reserveCapacity(min(placements.count, HomeIslandMetrics.maximumPlacements))

        for placement in placements {
            guard result.count < HomeIslandMetrics.maximumPlacements,
                  HomeIslandAssetCatalog.approvedIDs.contains(placement.assetID),
                  seenIDs.insert(placement.id).inserted,
                  placement.transform.x.isFinite,
                  placement.transform.z.isFinite,
                  placement.transform.yaw.isFinite,
                  placement.transform.scale.isFinite,
                  abs(placement.transform.x) <= 10_000,
                  abs(placement.transform.z) <= 10_000
            else { continue }

            let count = counts[placement.assetID, default: 0]
            // The limit is the limit, including for islands built under the
            // older, larger numbers: anything past it is dropped on load and
            // not written back. Placing and keeping answer to one rule.
            guard count < HomeIslandAssetCatalog.placementLimit(for: placement.assetID)
            else { continue }

            var copy = placement
            copy.transform.scale = HomeIslandAssetCatalog.persistedScale(
                assetID: copy.assetID,
                storedScale: min(2, max(0.25, copy.transform.scale))
            )
            copy.transform.yaw = atan2(sin(copy.transform.yaw), cos(copy.transform.yaw))
            guard let transform = HomeIslandAssetCatalog.placementTransform(
                assetID: copy.assetID,
                x: copy.transform.x,
                z: copy.transform.z,
                yaw: copy.transform.yaw,
                scale: copy.transform.scale,
                requireValidCoastPoint: false
            ) else { continue }
            guard transform.x.isFinite,
                  transform.z.isFinite,
                  transform.yaw.isFinite,
                  transform.scale.isFinite
            else { continue }
            copy.transform = transform
            result.append(copy)
            counts[copy.assetID] = count + 1
        }
        return result
    }

    /// The account backup uses the same allow-list, transform bounds and
    /// per-asset limits as local persistence and multiplayer snapshots.
    static func sanitizedForAccountSync(
        _ placements: [HomeIslandPlacement]
    ) -> [HomeIslandPlacement] {
        sanitized(placements)
    }

    /// A slot's headline figures, read without building placements.
    static func summary(ownerKey: String) -> (updatedAt: Date, placementCount: Int)? {
        guard let document = loadDocument(ownerKey: ownerKey) else { return nil }
        return (document.updatedAt, sanitized(document.placements).count)
    }

    static func load(ownerKey: String) -> HomeIslandSnapshot {
        guard let document = loadDocument(ownerKey: ownerKey) else {
            return HomeIslandSnapshot(ownerKey: ownerKey, updatedAt: .distantPast, placements: [])
        }
        return HomeIslandSnapshot(
            ownerKey: ownerKey,
            updatedAt: document.updatedAt,
            placements: sanitized(document.placements)
        )
    }

    private static func writeAndVerify(_ data: Data, to url: URL, ownerKey: String) throws {
        try data.write(to: url, options: .atomic)
        guard let persisted = try? Data(contentsOf: url),
              persisted == data,
              let decoded = try? JSONDecoder().decode(Document.self, from: persisted),
              decoded.ownerKey == ownerKey
        else { throw PersistenceError.verificationFailed(url) }
    }

    @discardableResult
    static func save(ownerKey: String, placements: [HomeIslandPlacement]) throws -> Date {
        let date = Date()
        try save(
            snapshot: HomeIslandSnapshot(
                ownerKey: ownerKey,
                updatedAt: date,
                placements: placements
            )
        )
        return date
    }

    /// Writes an already timestamped cloud snapshot without inventing a newer
    /// local edit. This prevents a download -> upload loop between devices.
    static func save(snapshot: HomeIslandSnapshot) throws {
        let document = Document(
            version: snapshot.schemaVersion,
            ownerKey: snapshot.ownerKey,
            updatedAt: snapshot.updatedAt,
            placements: sanitized(snapshot.placements)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        let directory = directoryURL(ownerKey: snapshot.ownerKey)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeAndVerify(
            data,
            to: recoveryFileURL(ownerKey: snapshot.ownerKey),
            ownerKey: snapshot.ownerKey
        )
        try writeAndVerify(
            data,
            to: fileURL(ownerKey: snapshot.ownerKey),
            ownerKey: snapshot.ownerKey
        )
    }
}

@MainActor
final class HomeIslandStore: ObservableObject {
    private struct EditState {
        var placements: [HomeIslandPlacement]
        var selectedID: UUID?
    }

    @Published private(set) var placements: [HomeIslandPlacement]
    @Published private(set) var selectedID: UUID?
    @Published private(set) var lastSavedAt: Date?
    @Published private(set) var lastSaveSucceeded = true
    @Published private(set) var lastSaveError: String?

    private var undoStack: [EditState] = []
    private var redoStack: [EditState] = []
    private let maximumUndoDepth = 60
    private var snapshotSchemaVersion = 1
    private var playerLevel: Int

    private var islandScale: Float {
        HomeIslandExpansionPolicy.scale(for: playerLevel)
    }

    let ownerKey: String
    /// Read-only stores are used for islands owned by another player. This is
    /// intentionally enforced in the model as well as in the UI so a future
    /// visitor screen cannot mutate or persist the host's layout accidentally.
    let isReadOnly: Bool

    /// Creates either the existing locally persisted editor store or an
    /// in-memory store backed by a supplied multiplayer snapshot.
    ///
    /// A read-only store with no supplied snapshot starts empty and never loads
    /// another player's local persistence path. Existing `init(ownerID:)` call
    /// sites retain their original loading and saving behavior through the
    /// default arguments.
    init(
        ownerID: String,
        snapshot suppliedSnapshot: HomeIslandSnapshot? = nil,
        readOnly: Bool = false,
        playerLevel: Int = 1
    ) {
        let localOwnerKey = HomeIslandPersistence.ownerKey(for: ownerID)
        isReadOnly = readOnly
        self.playerLevel = max(1, playerLevel)
        ownerKey = readOnly ? (suppliedSnapshot?.ownerKey ?? localOwnerKey) : localOwnerKey

        let snapshot: HomeIslandSnapshot
        if let suppliedSnapshot {
            snapshot = HomeIslandSnapshot(
                schemaVersion: suppliedSnapshot.schemaVersion,
                ownerKey: suppliedSnapshot.ownerKey,
                updatedAt: suppliedSnapshot.updatedAt,
                placements: HomeIslandPersistence.sanitized(suppliedSnapshot.placements)
            )
        } else if readOnly {
            snapshot = HomeIslandSnapshot(
                ownerKey: ownerKey,
                updatedAt: .distantPast,
                placements: []
            )
        } else {
            snapshot = HomeIslandPersistence.load(ownerKey: ownerKey)
        }
        snapshotSchemaVersion = snapshot.schemaVersion
        placements = snapshot.placements
        lastSavedAt = snapshot.updatedAt == .distantPast ? nil : snapshot.updatedAt

        // Warm the 3D cache off the main thread. The scene view is built a
        // moment later and every model it needs is known right here, so the
        // parsing overlaps with view setup instead of stalling the first frame.
        AssetPlacementRuntime.preload(
            resourceNames: HomeIslandMetrics.fixedSceneryResourceNames
                + snapshot.placements.map(\.assetID)
        )
    }

    /// Convenience for callers that already decoded only the placement array.
    convenience init(
        ownerID: String,
        placements: [HomeIslandPlacement],
        readOnly: Bool
    ) {
        let ownerKey = HomeIslandPersistence.ownerKey(for: ownerID)
        self.init(
            ownerID: ownerID,
            snapshot: HomeIslandSnapshot(
                ownerKey: ownerKey,
                updatedAt: .distantPast,
                placements: placements
            ),
            readOnly: readOnly,
            playerLevel: 1
        )
    }

    func updatePlayerLevel(_ level: Int) {
        playerLevel = max(1, level)
    }

    var snapshot: HomeIslandSnapshot {
        HomeIslandSnapshot(
            schemaVersion: snapshotSchemaVersion,
            ownerKey: ownerKey,
            updatedAt: lastSavedAt ?? .distantPast,
            placements: placements
        )
    }

    var selectedPlacement: HomeIslandPlacement? {
        guard let selectedID else { return nil }
        return placements.first { $0.id == selectedID }
    }

    var canAdd: Bool {
        !isReadOnly && placements.count < HomeIslandMetrics.maximumPlacements
    }
    var canUndo: Bool { !isReadOnly && !undoStack.isEmpty }
    var canRedo: Bool { !isReadOnly && !redoStack.isEmpty }

    func placementCount(assetID: String) -> Int {
        placements.lazy.filter { $0.assetID == assetID }.count
    }

    func canAdd(assetID: String) -> Bool {
        canAdd
            && HomeIslandAssetCatalog.isUserPlaceable(assetID: assetID)
            && !isPassLocked(assetID: assetID)
            && placementCount(assetID: assetID) < HomeIslandAssetCatalog.placementLimit(for: assetID)
    }

    /// Adding and duplicating both come through `canAdd(assetID:)`, so the
    /// subscription is enforced here rather than only by the build palette.
    /// Loading, moving and saving deliberately never ask: props placed while
    /// the pass was active stay on the island, and stay editable, without it.
    private func isPassLocked(assetID: String) -> Bool {
        guard let asset = HomeIslandAssetCatalog.asset(id: assetID) else { return false }
        return HomeIslandAssetCatalog.isPassLocked(
            asset,
            hasVoyagePass: VoyagePassStore.shared.isActive
        )
    }

    func select(_ id: UUID?) {
        guard !isReadOnly else { return }
        selectedID = id.flatMap { candidate in
            placements.contains(where: { $0.id == candidate }) ? candidate : nil
        }
    }

    @discardableResult
    func add(assetID: String, x: Float, z: Float, playerLevel: Int) -> UUID? {
        guard !isReadOnly,
              canAdd(assetID: assetID),
              let asset = HomeIslandAssetCatalog.asset(id: assetID),
              HomeIslandAssetCatalog.isUnlocked(asset, playerLevel: playerLevel)
        else { return nil }
        let previous = editState
        let placementID = UUID()
        guard let transform = validTransform(
            assetID: assetID,
            x: x,
            z: z,
            // Built props keep their authored facing. Natural ones are turned
            // by an angle derived from their own id: a grove of identical
            // trees stops looking stamped, and because the angle comes from
            // the placement itself it never changes afterwards. (Deriving it
            // from the island's object count used to do exactly that.)
            yaw: HomeIslandAssetCatalog.naturalFacing(assetID: assetID, id: placementID),
            scale: asset.defaultScale,
            excluding: nil,
            requireValidCoastPoint: true
        ) else { return nil }
        let placement = HomeIslandPlacement(
            id: placementID,
            assetID: assetID,
            transform: transform
        )
        placements.append(placement)
        selectedID = placement.id
        finishEdit(from: previous)
        return placement.id
    }

    @discardableResult
    func moveSelected(x: Float, z: Float) -> Bool {
        guard !isReadOnly,
              let selectedID,
              let index = placements.firstIndex(where: { $0.id == selectedID })
        else { return false }
        let previous = editState
        if let transform = validTransform(
            assetID: placements[index].assetID,
            x: x,
            z: z,
            yaw: placements[index].transform.yaw,
            scale: placements[index].transform.scale,
            excluding: selectedID,
            requireValidCoastPoint: true
        ) {
            placements[index].transform = transform
            finishEdit(from: previous)
            return true
        }

        // A prop already standing somewhere the rules refuse — an older island
        // laid out under different rules, say — could otherwise never be
        // dragged out of it, because every destination on the way is refused
        // too. Let it move anywhere the shoreline allows.
        guard !isValidPlacement(
            assetID: placements[index].assetID,
            transform: placements[index].transform,
            excluding: selectedID
        ), let rescued = HomeIslandAssetCatalog.placementTransform(
            assetID: placements[index].assetID,
            x: x,
            z: z,
            yaw: placements[index].transform.yaw,
            scale: placements[index].transform.scale,
            requireValidCoastPoint: false,
            islandScale: islandScale
        ) else { return false }
        placements[index].transform = rescued
        finishEdit(from: previous)
        return true
    }

    /// Rotates in 15-degree steps so small props and furniture can be aligned
    /// precisely without turning the build dock into a continuous slider.
    func rotateSelected(by radians: Float = .pi / 12) {
        guard !isReadOnly,
              let selectedID,
              let index = placements.firstIndex(where: { $0.id == selectedID })
        else { return }
        guard placements[index].assetID != "wooden_jetty" else { return }
        let previous = editState
        let yaw = placements[index].transform.yaw + radians
        placements[index].transform.yaw = atan2(sin(yaw), cos(yaw))
        finishEdit(from: previous)
    }

    @discardableResult
    func resizeSelected(by delta: Float) -> Bool {
        #if !targetEnvironment(simulator)
        // Asset scale is developer calibration data, not a consumer edit.
        // Keep the model guarded as well as the UI so future call sites cannot
        // re-enable device resizing accidentally.
        return false
        #else
        guard !isReadOnly,
              let selectedID,
              let index = placements.firstIndex(where: { $0.id == selectedID })
        else { return false }
        let previous = editState
        let scale = min(2, max(0.25, placements[index].transform.scale + delta))
        guard let transform = validTransform(
            assetID: placements[index].assetID,
            x: placements[index].transform.x,
            z: placements[index].transform.z,
            yaw: placements[index].transform.yaw,
            scale: scale,
            excluding: selectedID,
            requireValidCoastPoint: false
        ) else { return false }
        placements[index].transform = transform
        finishEdit(from: previous)
        return true
        #endif
    }

    @discardableResult
    func duplicateSelected(playerLevel: Int) -> UUID? {
        guard !isReadOnly,
              let selected = selectedPlacement,
              canAdd(assetID: selected.assetID),
              let asset = HomeIslandAssetCatalog.asset(id: selected.assetID),
              HomeIslandAssetCatalog.isUnlocked(asset, playerLevel: playerLevel)
        else { return nil }
        let previous = editState
        var copy = selected
        copy.id = UUID()
        let directions: [(Float, Float)] = [
            (1, 0), (0.7, 0.7), (0, 1), (-0.7, 0.7),
            (-1, 0), (-0.7, -0.7), (0, -1), (0.7, -0.7),
        ]
        // Just far enough that the copy is visibly a second prop. Props may
        // overlap, so there is no reason to fling a duplicate a metre away.
        let baseSpacing = max(
            0.30,
            HomeIslandAssetCatalog.placementCollisionRadius(
                assetID: selected.assetID,
                scale: selected.transform.scale
            ) * 0.65
        )
        var transform: HomeIslandTransform?
        for ring in 1...3 where transform == nil {
            let spacing = baseSpacing * Float(ring)
            for direction in directions {
                transform = validTransform(
                    assetID: selected.assetID,
                    x: selected.transform.x + direction.0 * spacing,
                    z: selected.transform.z + direction.1 * spacing,
                    yaw: selected.transform.yaw,
                    scale: selected.transform.scale,
                    excluding: nil,
                    requireValidCoastPoint: false
                )
                if transform != nil { break }
            }
        }
        guard let transform else { return nil }
        copy.transform = transform
        placements.append(copy)
        selectedID = copy.id
        finishEdit(from: previous)
        return copy.id
    }

    func deleteSelected() {
        guard !isReadOnly, let selectedID else { return }
        let previous = editState
        placements.removeAll { $0.id == selectedID }
        self.selectedID = nil
        finishEdit(from: previous)
    }

    /// Takes every placed prop back and leaves the island bare. The props
    /// are not consumed by placing them, so there is no inventory to return
    /// them to; clearing the layout is all "putting them back" means. This
    /// goes through `finishEdit`, so one undo brings the whole island back.
    func removeAllPlacements() {
        guard !isReadOnly, !placements.isEmpty else { return }
        let previous = editState
        placements.removeAll()
        selectedID = nil
        finishEdit(from: previous)
    }

    func undo() {
        guard !isReadOnly, let previous = undoStack.popLast() else { return }
        append(&redoStack, state: editState)
        placements = previous.placements
        selectedID = previous.selectedID.flatMap { restoredID in
            placements.contains(where: { $0.id == restoredID }) ? restoredID : nil
        }
        save()
    }

    func redo() {
        guard !isReadOnly, let next = redoStack.popLast() else { return }
        append(&undoStack, state: editState)
        placements = next.placements
        selectedID = next.selectedID.flatMap { restoredID in
            placements.contains(where: { $0.id == restoredID }) ? restoredID : nil
        }
        save()
    }

    func validTransform(
        assetID: String,
        x: Float,
        z: Float,
        yaw: Float,
        scale: Float,
        excluding excludedID: UUID?,
        requireValidCoastPoint: Bool
    ) -> HomeIslandTransform? {
        guard x.isFinite, z.isFinite, yaw.isFinite, scale.isFinite,
              let transform = HomeIslandAssetCatalog.placementTransform(
                assetID: assetID,
                x: x,
                z: z,
                yaw: yaw,
                scale: scale,
                requireValidCoastPoint: requireValidCoastPoint,
                islandScale: islandScale
              ),
              // User gestures must never be silently clamped to a distant
              // edge position. Persistence still sanitizes legacy snapshots
              // through `placementTransform` directly, while live edits fail
              // closed and keep the last valid transform under the finger.
              (assetID == "wooden_jetty"
                || hypot(transform.x - x, transform.z - z) <= 0.025),
              isValidPlacement(assetID: assetID, transform: transform, excluding: excludedID)
        else { return nil }
        return transform
    }

    private var editState: EditState {
        EditState(placements: placements, selectedID: selectedID)
    }

    private func finishEdit(from previous: EditState) {
        guard !isReadOnly else {
            // Defense in depth for future editor operations: even if a new
            // mutator forgets its early read-only guard, its in-memory change
            // is rolled back before it can leak into visitor state.
            placements = previous.placements
            selectedID = previous.selectedID
            return
        }
        guard placements != previous.placements || selectedID != previous.selectedID else { return }
        append(&undoStack, state: previous)
        redoStack.removeAll(keepingCapacity: true)
        save()
    }

    private func append(_ stack: inout [EditState], state: EditState) {
        stack.append(state)
        if stack.count > maximumUndoDepth {
            stack.removeFirst(stack.count - maximumUndoDepth)
        }
    }

    private func isValidPlacement(
        assetID: String,
        transform: HomeIslandTransform,
        excluding excludedID: UUID?
    ) -> Bool {
        let candidateRadius = HomeIslandAssetCatalog.placementCollisionRadius(
            assetID: assetID,
            scale: transform.scale
        )

        // Keep the step off the jetty clear. This used to reserve a 5.25 m lane
        // running deep into the island, which refused props over a large part
        // of the front shore; only the landing itself actually has to stay
        // walkable. Ground paths remain allowed — they are traversable.
        if HomeIslandAssetCatalog.blocksWalking(assetID: assetID),
           transform.z >= 6.60 * islandScale - candidateRadius,
           transform.z <= 8.90 * islandScale + candidateRadius,
           abs(transform.x) <= 0.72 + candidateRadius {
            return false
        }

        guard HomeIslandAssetCatalog.participatesInPlacementCollision(assetID: assetID)
        else { return true }

        // The berth itself needs no reservation: props are clamped to the
        // shoreline and cannot reach the water where the boat moors. Reserving
        // the whole 9.8 x 11.8 rectangle in front of the jetty made a third of
        // the island refuse anything, which is what made dragging props around
        // the entrance feel broken.

        // The notice board is a permanent public fixture beside the fixed jetty.
        // Keep player-built assets from covering it even though it is not saved.
        let noticePosition = HomeIslandMetrics.fixedNoticeBoardPosition(
            islandScale: islandScale
        )
        let noticeDX = transform.x - noticePosition.x
        let noticeDZ = transform.z - noticePosition.z
        let noticeMinimumDistance = candidateRadius
            + HomeIslandMetrics.fixedNoticeBoardPlacementRadius
        if noticeDX * noticeDX + noticeDZ * noticeDZ
            < noticeMinimumDistance * noticeMinimumDistance {
            return false
        }

        // Props do not collide with each other at all. Overlap is how a grove,
        // a flower bed or a cluster of furniture gets composed, and the player
        // can see exactly what they are building. What stays reserved above is
        // only what gameplay needs: the walk in from the jetty, the berth the
        // boat arrives at, and the notice board.
        return true
    }

    /// Applies a live host snapshot to an in-memory visitor store. Writable
    /// stores reject this operation so network updates can never overwrite a
    /// player's locally authored island.
    @discardableResult
    func replaceRemoteSnapshot(_ snapshot: HomeIslandSnapshot) -> Bool {
        guard isReadOnly else { return false }
        placements = HomeIslandPersistence.sanitized(snapshot.placements)
        selectedID = selectedID.flatMap { selectedID in
            placements.contains(where: { $0.id == selectedID }) ? selectedID : nil
        }
        undoStack.removeAll(keepingCapacity: true)
        redoStack.removeAll(keepingCapacity: true)
        snapshotSchemaVersion = snapshot.schemaVersion
        lastSavedAt = snapshot.updatedAt == .distantPast ? nil : snapshot.updatedAt
        lastSaveSucceeded = true
        lastSaveError = nil
        return true
    }

    /// Pulls a newer cloud-restored snapshot from the account-scoped local
    /// file into the live editor without recreating the whole island screen.
    @discardableResult
    func reloadLocalSnapshotIfNewer() -> Bool {
        guard !isReadOnly else { return false }
        let snapshot = HomeIslandPersistence.load(ownerKey: ownerKey)
        let currentDate = lastSavedAt ?? .distantPast
        guard snapshot.updatedAt > currentDate else { return false }
        guard snapshot.placements != placements else {
            // Same layout, newer stamp: the account echo of our own save. Take
            // the timestamp so last-write-wins stays honest, but leave the
            // editor — selection, undo history, an in-flight drag — alone.
            lastSavedAt = snapshot.updatedAt
            return false
        }
        placements = snapshot.placements
        selectedID = nil
        undoStack.removeAll(keepingCapacity: true)
        redoStack.removeAll(keepingCapacity: true)
        snapshotSchemaVersion = snapshot.schemaVersion
        lastSavedAt = snapshot.updatedAt
        lastSaveSucceeded = true
        lastSaveError = nil
        return true
    }

    func save() {
        guard !isReadOnly else { return }
        do {
            lastSavedAt = try HomeIslandPersistence.save(
                ownerKey: ownerKey,
                placements: placements
            )
            lastSaveSucceeded = true
            lastSaveError = nil
            NotificationCenter.default.post(name: .homeIslandDidChange, object: ownerKey)
            let snapshot = self.snapshot
            Task { await SyncService.shared.pushHomeIslandSnapshot(snapshot) }
        } catch {
            lastSaveSucceeded = false
            lastSaveError = error.localizedDescription
        }
    }
}
