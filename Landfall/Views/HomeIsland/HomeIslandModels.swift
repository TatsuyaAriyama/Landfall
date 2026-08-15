import Combine
import CryptoKit
import Foundation
import SceneKit

extension Notification.Name {
    /// The signed-in player's personal island changed on this device.
    static let homeIslandDidChange = Notification.Name("HomeIslandDidChange")
}

enum HomeIslandMetrics {
    static let foundationResourceName = "home_island_foundation"
    static let surfaceY: Float = 0.62
    // Placement remains slightly inset; walking uses the authored irregular
    // shoreline below and can approach every safe section of the sand lip.
    static let buildableRadiusX: Float = 12.42
    static let buildableRadiusZ: Float = 8.55
    static let maximumPlacements = 120
    static let arrivalJettyScale: Float = 0.72
    static let arrivalJettyYaw: Float = .pi
    // Authored wooden_jetty model-space dimensions. Keeping these beside the
    // fixed placement prevents rendering, walking and arrival choreography
    // from drifting apart when the source asset changes.
    static let jettyDeckSeawardEndLocalZ: Float = -13.85
    static let jettyDeckLandwardEndLocalZ: Float = 2.30
    static let jettyRailSeawardEndLocalZ: Float = -13.55
    static let jettyRailLandwardEndLocalZ: Float = 1.55
    static let jettyRailCenterLocalX: Float = 0.69
    static let arrivalJettyTransferLocalZ: Float = -13.48
    static let arrivalJettyIslandLocalZ: Float = 1.50
    // The reserved corridor includes both the permanent jetty and the
    // player's moored boat, so newly placed props cannot overlap the berth.
    static let arrivalJettyReservedHalfWidth: Float = 2.15
    static let arrivalJettyReservedNearZ: Float = 7.10
    static let arrivalJettyReservedFarZ: Float = 21.80
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

    private static let foundationRadiusX: Float = 13.10
    private static let foundationRadiusZ: Float = 9.10
    private static let sandApronScale: Float = 0.955

    /// Matches `outline(..., layer: 1)` from the deterministic Blender source.
    /// Keeping rendering and collision on this one boundary prevents a visible
    /// strip that looks walkable but rejects the player.
    static func sandEdgePoint(angle: Float) -> (x: Float, z: Float) {
        let ripple = sin(angle * 3 + 0.45) * 0.045
            + sin(angle * 7 - 0.82) * 0.026
            + sin(angle * 11 + 1.3) * 0.012
        let layerShift = sin(angle * 5 + 0.91) * 0.018
        let scale = sandApronScale * (1 + ripple + layerShift)
        return (
            cos(angle) * foundationRadiusX * scale,
            // USDZ imports Blender's horizontal Y axis as negative SceneKit Z.
            -sin(angle) * foundationRadiusZ * scale
        )
    }

    static var arrivalJettyPosition: (x: Float, z: Float) {
        sandEdgePoint(angle: -.pi / 2)
    }

    static func containsWalkableSand(x: Float, z: Float, margin: Float) -> Bool {
        let angle = atan2(-z / foundationRadiusZ, x / foundationRadiusX)
        let edge = sandEdgePoint(angle: angle)
        let edgeDistance = sqrt(edge.x * edge.x + edge.z * edge.z)
        let distance = sqrt(x * x + z * z)
        return distance <= max(0, edgeDistance - margin)
    }

    static func clampedPosition(
        x: Float,
        z: Float,
        footprintMargin: Float = 0
    ) -> (x: Float, z: Float) {
        let radiusX = max(0.5, buildableRadiusX - footprintMargin)
        let radiusZ = max(0.5, buildableRadiusZ - footprintMargin)
        let normalized = (x * x) / (radiusX * radiusX)
            + (z * z) / (radiusZ * radiusZ)
        guard normalized > 1 else { return (x, z) }
        let scale = 1 / sqrt(normalized)
        return (x * scale, z * scale)
    }

    static func contains(x: Float, z: Float) -> Bool {
        (x * x) / (buildableRadiusX * buildableRadiusX)
            + (z * z) / (buildableRadiusZ * buildableRadiusZ) <= 1
    }

    /// A jetty is authored along local Z: positive Z is the low shore ramp and
    /// negative Z reaches into the water.  The returned yaw therefore points
    /// local -Z along the shoreline's outward normal.
    static func jettyCoastPlacement(
        nearX x: Float,
        z: Float,
        requireCoastalInput: Bool
    ) -> (x: Float, z: Float, yaw: Float)? {
        let inputDistance = sqrt(x * x + z * z)
        guard inputDistance > 0.5 else { return nil }

        let angle = atan2(-z / foundationRadiusZ, x / foundationRadiusX)
        let edge = sandEdgePoint(angle: angle)
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
    let title: String
    let symbolName: String
    let defaultScale: Float
    let footprintMargin: Float
    let unlockLevel: Int
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
}

/// Network-safe identity for one seat on one placed asset.
struct HomeIslandSeatAddress: Codable, Hashable, Sendable {
    let placementID: UUID
    let slotID: String
}

enum HomeIslandAssetCatalog {
    private static let driftwoodBenchSeatSlots = [
        HomeIslandContactSlotDefinition(
            id: "left",
            motion: .sit,
            seatNodeName: "SeatSocket_Left",
            approachNodeName: "SeatApproach_Left"
        ),
        HomeIslandContactSlotDefinition(
            id: "right",
            motion: .sit,
            seatNodeName: "SeatSocket_Right",
            approachNodeName: "SeatApproach_Right"
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

    static func contactSlots(for assetID: String) -> [HomeIslandContactSlotDefinition] {
        switch assetID {
        case "driftwood_bench":
            driftwoodBenchSeatSlots
        case "navigator_hammock":
            navigatorHammockContactSlots
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
        "small_tree",
        "small_stump",
        "small_rock"
    ]

    /// Only these operator-approved assets can enter player-authored islands.
    /// Keeping this allowlist independent from 3D Studio prevents developer or
    /// terrain tools from leaking into the consumer placement experience.
    static let approved: [HomeIslandAsset] = [
        HomeIslandAsset(
            id: "small_tree",
            title: String(localized: "Small Tree"),
            symbolName: "tree.fill",
            defaultScale: 1.32,
            footprintMargin: 0.38,
            unlockLevel: 1
        ),
        HomeIslandAsset(
            id: "small_stump",
            title: String(localized: "Small Stump"),
            symbolName: "tree.fill",
            defaultScale: 0.76,
            footprintMargin: 0.60,
            unlockLevel: 1
        ),
        HomeIslandAsset(
            id: "small_lighthouse",
            title: String(localized: "Small Lighthouse"),
            symbolName: "light.beacon.max.fill",
            defaultScale: 0.72,
            footprintMargin: 0.68,
            unlockLevel: 2
        ),
        HomeIslandAsset(
            id: "small_rock",
            title: String(localized: "Small Rock"),
            symbolName: "mountain.2.fill",
            defaultScale: 0.70,
            footprintMargin: 0.55,
            unlockLevel: 1
        ),
        HomeIslandAsset(
            id: "weathered_cottage",
            title: String(localized: "Weathered Cottage"),
            symbolName: "house.fill",
            defaultScale: 0.78,
            footprintMargin: 0.92,
            unlockLevel: 3
        ),
        HomeIslandAsset(
            id: "weathered_crate",
            title: String(localized: "Weathered Crate"),
            symbolName: "shippingbox.fill",
            defaultScale: 0.88,
            footprintMargin: 0.46,
            unlockLevel: 4
        ),
        HomeIslandAsset(
            id: "small_lake",
            title: String(localized: "Small Lake"),
            symbolName: "water.waves",
            defaultScale: 0.82,
            footprintMargin: 0.88,
            unlockLevel: 5
        ),
        HomeIslandAsset(
            id: "weathered_lighthouse",
            title: String(localized: "Stone Lighthouse"),
            symbolName: "light.beacon.max.fill",
            defaultScale: 0.68,
            footprintMargin: 0.82,
            unlockLevel: 6
        ),
        HomeIslandAsset(
            id: "campfire_circle",
            title: String(localized: "Campfire Circle"),
            symbolName: "flame.fill",
            defaultScale: 0.72,
            footprintMargin: 1.62,
            unlockLevel: 1
        ),
        HomeIslandAsset(
            id: "stone_well",
            title: String(localized: "Stone Well"),
            symbolName: "drop.fill",
            defaultScale: 0.76,
            footprintMargin: 1.14,
            unlockLevel: 9
        ),
        HomeIslandAsset(
            id: "voyage_flagpole",
            title: String(localized: "Voyage Flagpole"),
            symbolName: "flag.fill",
            defaultScale: 0.72,
            footprintMargin: 1.10,
            unlockLevel: 10
        ),
        HomeIslandAsset(
            id: "cliff_lookout",
            title: String(localized: "Cliff Lookout"),
            symbolName: "binoculars.fill",
            defaultScale: 0.72,
            footprintMargin: 1.90,
            unlockLevel: 11
        ),
        HomeIslandAsset(
            id: "mossy_ruins",
            title: String(localized: "Mossy Ruins"),
            symbolName: "building.columns.fill",
            defaultScale: 0.70,
            footprintMargin: 1.62,
            unlockLevel: 12
        ),
        HomeIslandAsset(
            id: "stone_path_straight",
            title: String(localized: "Stone Path — Straight"),
            symbolName: "square.grid.3x3.fill",
            defaultScale: 0.78,
            footprintMargin: 1.50,
            unlockLevel: 13
        ),
        HomeIslandAsset(
            id: "stone_path_curve",
            title: String(localized: "Stone Path — Curve"),
            symbolName: "square.grid.3x3.fill",
            defaultScale: 0.78,
            footprintMargin: 1.62,
            unlockLevel: 13
        ),
        HomeIslandAsset(
            id: "stone_path_fork",
            title: String(localized: "Stone Path — Fork"),
            symbolName: "square.grid.3x3.fill",
            defaultScale: 0.78,
            footprintMargin: 1.60,
            unlockLevel: 13
        ),
        HomeIslandAsset(
            id: "coastal_rocks",
            title: String(localized: "Coastal Rocks"),
            symbolName: "mountain.2.fill",
            defaultScale: 0.72,
            footprintMargin: 1.90,
            unlockLevel: 14
        ),
        HomeIslandAsset(
            id: "navigator_tent",
            title: String(localized: "Navigator's Tent"),
            symbolName: "tent.fill",
            defaultScale: 0.62,
            footprintMargin: 1.98,
            unlockLevel: 2
        ),
        HomeIslandAsset(
            id: "wooden_desk",
            title: String(localized: "Wooden Desk"),
            symbolName: "table.furniture.fill",
            defaultScale: 0.82,
            footprintMargin: 1.08,
            unlockLevel: 4
        ),
        HomeIslandAsset(
            id: "wooden_chair",
            title: String(localized: "Wooden Chair"),
            symbolName: "chair.fill",
            defaultScale: 0.82,
            footprintMargin: 0.70,
            unlockLevel: 3
        ),
        HomeIslandAsset(
            id: "harbor_lantern_post",
            title: String(localized: "Harbor Lantern Post"),
            symbolName: "lightbulb.fill",
            defaultScale: 0.76,
            footprintMargin: 0.68,
            unlockLevel: 6
        ),
        HomeIslandAsset(
            id: "driftwood_bench",
            title: String(localized: "Driftwood Bench"),
            symbolName: "chair.fill",
            defaultScale: 0.62,
            footprintMargin: 1.08,
            unlockLevel: 5
        ),
        HomeIslandAsset(
            id: "weathered_anchor",
            title: String(localized: "Weathered Anchor"),
            symbolName: "anchor",
            defaultScale: 0.76,
            footprintMargin: 0.86,
            unlockLevel: 7
        ),
        HomeIslandAsset(
            id: "net_drying_rack",
            title: String(localized: "Net Drying Rack"),
            symbolName: "grid",
            defaultScale: 0.74,
            footprintMargin: 1.18,
            unlockLevel: 8
        ),
        HomeIslandAsset(
            id: "navigator_hammock",
            title: String(localized: "Navigator's Hammock"),
            symbolName: "bed.double.fill",
            defaultScale: 0.52,
            footprintMargin: 1.45,
            unlockLevel: 9
        ),
        HomeIslandAsset(
            id: "voyage_signal_bell",
            title: String(localized: "Voyage Signal Bell"),
            symbolName: "bell.fill",
            defaultScale: 0.76,
            footprintMargin: 0.72,
            unlockLevel: 10
        ),
        HomeIslandAsset(
            id: "supply_barrels",
            title: String(localized: "Supply Barrels"),
            symbolName: "cylinder.split.1x2",
            defaultScale: 0.80,
            footprintMargin: 0.92,
            unlockLevel: 8
        ),
        HomeIslandAsset(
            id: "compass_rose_inlay",
            title: String(localized: "Compass Rose Inlay"),
            symbolName: "location.north.circle.fill",
            defaultScale: 0.78,
            footprintMargin: 1.18,
            unlockLevel: 12
        ),
        HomeIslandAsset(
            id: "dune_grass_patch",
            title: String(localized: "Dune Grass Patch"),
            symbolName: "leaf.fill",
            defaultScale: 0.82,
            footprintMargin: 0.78,
            unlockLevel: 2
        ),
    ]

    static var approvedIDs: Set<String> { Set(approved.map(\.id)) }

    static func available(in bundle: Bundle = .main) -> [HomeIslandAsset] {
        approved.filter { asset in
            asset.id == "small_lake"
                || bundle.url(forResource: asset.id, withExtension: "usdz") != nil
        }
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

    /// Most props are intentionally scarce. Natural ground details can be
    /// repeated more freely so players can shape a convincing island edge.
    static func placementLimit(for assetID: String) -> Int {
        switch assetID {
        case "small_stump", "small_rock", "small_tree":
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
        requireValidCoastPoint: Bool
    ) -> HomeIslandTransform? {
        if assetID == "wooden_jetty" {
            guard let coast = HomeIslandMetrics.jettyCoastPlacement(
                nearX: x,
                z: z,
                requireCoastalInput: requireValidCoastPoint
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
            footprintMargin: margin
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
             "stone_path_straight",
             "stone_path_curve",
             "stone_path_fork",
             "compass_rose_inlay",
             "dune_grass_patch":
            false
        default:
            true
        }
    }

    /// A compact gameplay collision profile. Paths remain deliberately
    /// traversable and may sit beneath furniture or scenery; jetties only need
    /// separation from other jetties because their landward end touches sand.
    static func placementCollisionRadius(assetID: String, scale: Float) -> Float {
        max(0.24, footprintMargin(assetID: assetID, scale: scale) * 0.68)
    }

    static func participatesInPlacementCollision(assetID: String) -> Bool {
        switch assetID {
        case "stone_path_straight", "stone_path_curve", "stone_path_fork",
             "compass_rose_inlay", "dune_grass_patch":
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
            guard count < HomeIslandAssetCatalog.placementLimit(for: placement.assetID) else {
                continue
            }

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
        let document = Document(
            ownerKey: ownerKey,
            updatedAt: date,
            placements: sanitized(placements)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        let directory = directoryURL(ownerKey: ownerKey)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeAndVerify(
            data,
            to: recoveryFileURL(ownerKey: ownerKey),
            ownerKey: ownerKey
        )
        try writeAndVerify(data, to: fileURL(ownerKey: ownerKey), ownerKey: ownerKey)
        return date
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
        readOnly: Bool = false
    ) {
        let localOwnerKey = HomeIslandPersistence.ownerKey(for: ownerID)
        isReadOnly = readOnly
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
            readOnly: readOnly
        )
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
            && placementCount(assetID: assetID) < HomeIslandAssetCatalog.placementLimit(for: assetID)
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
        guard let transform = validTransform(
            assetID: assetID,
            x: x,
            z: z,
            yaw: Float(placements.count % 8) * (.pi / 4),
            scale: asset.defaultScale,
            excluding: nil,
            requireValidCoastPoint: true
        ) else { return nil }
        let placement = HomeIslandPlacement(
            id: UUID(),
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
        guard let transform = validTransform(
            assetID: placements[index].assetID,
            x: x,
            z: z,
            yaw: placements[index].transform.yaw,
            scale: placements[index].transform.scale,
            excluding: selectedID,
            requireValidCoastPoint: true
        ) else { return false }
        placements[index].transform = transform
        finishEdit(from: previous)
        return true
    }

    func rotateSelected(by radians: Float = .pi / 4) {
        guard !isReadOnly,
              let selectedID,
              let index = placements.firstIndex(where: { $0.id == selectedID })
        else { return }
        guard placements[index].assetID != "wooden_jetty" else { return }
        let previous = editState
        placements[index].transform.yaw += radians
        finishEdit(from: previous)
    }

    @discardableResult
    func resizeSelected(by delta: Float) -> Bool {
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
        let baseSpacing = max(
            0.9,
            HomeIslandAssetCatalog.placementCollisionRadius(
                assetID: selected.assetID,
                scale: selected.transform.scale
            ) * 1.75
        )
        var transform: HomeIslandTransform?
        for ring in 1...3 where transform == nil {
            let spacing = baseSpacing * Float(ring)
            for direction in directions {
                transform = validTransform(
                    assetID: selected.assetID,
                    x: selected.transform.x + direction.0 * spacing,
                    z: selected.transform.z + direction.1 * spacing,
                    yaw: selected.transform.yaw + .pi / 8,
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
                requireValidCoastPoint: requireValidCoastPoint
              ),
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

        // Preserve a clear path from the permanent arrival jetty into the island.
        // Ground paths remain allowed because they are deliberately traversable.
        if HomeIslandAssetCatalog.blocksWalking(assetID: assetID),
           transform.z >= 2.85 - candidateRadius,
           transform.z <= 8.10 + candidateRadius,
           abs(transform.x) <= 0.78 + candidateRadius {
            return false
        }

        guard HomeIslandAssetCatalog.participatesInPlacementCollision(assetID: assetID)
        else { return true }

        // The fixed arrival jetty is a system node rather than a saved placement,
        // so reserve its complete visible footprint explicitly. This prevents new
        // props and player jetties from covering the berth or its walkable ramp.
        if abs(transform.x) <= HomeIslandMetrics.arrivalJettyReservedHalfWidth + candidateRadius,
           transform.z >= HomeIslandMetrics.arrivalJettyReservedNearZ - candidateRadius,
           transform.z <= HomeIslandMetrics.arrivalJettyReservedFarZ + candidateRadius {
            return false
        }

        // The notice board is a permanent public fixture beside the fixed jetty.
        // Keep player-built assets from covering it even though it is not saved.
        let noticeDX = transform.x - HomeIslandMetrics.fixedNoticeBoardPosition.x
        let noticeDZ = transform.z - HomeIslandMetrics.fixedNoticeBoardPosition.z
        let noticeMinimumDistance = candidateRadius
            + HomeIslandMetrics.fixedNoticeBoardPlacementRadius
        if noticeDX * noticeDX + noticeDZ * noticeDZ
            < noticeMinimumDistance * noticeMinimumDistance {
            return false
        }

        return placements.allSatisfy { existing in
            guard existing.id != excludedID,
                  HomeIslandAssetCatalog.participatesInPlacementCollision(
                    assetID: existing.assetID
                  )
            else { return true }

            if assetID == "wooden_jetty" || existing.assetID == "wooden_jetty" {
                guard assetID == "wooden_jetty", existing.assetID == "wooden_jetty"
                else { return true }
            }

            let existingRadius = HomeIslandAssetCatalog.placementCollisionRadius(
                assetID: existing.assetID,
                scale: existing.transform.scale
            )
            let dx = transform.x - existing.transform.x
            let dz = transform.z - existing.transform.z
            let minimumDistance = (candidateRadius + existingRadius) * 0.92
            return dx * dx + dz * dz >= minimumDistance * minimumDistance
        }
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
        } catch {
            lastSaveSucceeded = false
            lastSaveError = error.localizedDescription
        }
    }
}
