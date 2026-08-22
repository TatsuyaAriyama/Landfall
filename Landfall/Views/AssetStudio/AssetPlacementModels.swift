import Combine
import Foundation
import SceneKit
import UIKit

extension Notification.Name {
    /// 3Dスタジオの保存内容を参照する全SceneKit画面への更新通知。
    static let assetStudioWorldDidChange = Notification.Name("AssetStudioWorldDidChange")
}

/// アプリへ同梱された USDZ 一つ分。ファイル名を永続IDとして扱う。
struct Asset3DDescriptor: Identifiable, Hashable {
    let id: String
    let displayName: String

    var resourceName: String { id }
    var providesPlacementSurface: Bool { Asset3DCatalog.providesPlacementSurface(for: id) }

    var symbolName: String {
        let lowercased = id.lowercased()
        if SavedAssetStudio.id(fromAssetID: id) != nil { return "square.3.layers.3d.top.filled" }
        if lowercased.contains("lake") || lowercased.contains("water") { return "water.waves" }
        if lowercased.contains("island") { return "mountain.2.fill" }
        if lowercased.contains("tree") { return "tree.fill" }
        if lowercased.contains("lighthouse") { return "light.beacon.max.fill" }
        if lowercased.contains("jetty") || lowercased.contains("pier") { return "water.waves" }
        if lowercased.contains("campfire") { return "flame.fill" }
        if lowercased.contains("well") { return "drop.fill" }
        if lowercased.contains("flagpole") { return "flag.fill" }
        if lowercased.contains("lookout") { return "binoculars.fill" }
        if lowercased.contains("ruins") { return "building.columns.fill" }
        if lowercased.contains("stone_path") { return "square.grid.3x3.fill" }
        if lowercased.contains("coastal_rocks") { return "mountain.2.fill" }
        if lowercased.contains("tent") { return "tent.fill" }
        if lowercased.contains("bottle") { return "waterbottle.fill" }
        if lowercased.contains("coffee") { return "cup.and.saucer.fill" }
        if lowercased.contains("desk") || lowercased.contains("table") { return "table.furniture.fill" }
        if lowercased.contains("chair") { return "chair.fill" }
        if lowercased.contains("bench") { return "chair.fill" }
        if lowercased.contains("hammock") { return "bed.double.fill" }
        if lowercased.contains("lantern") { return "lightbulb.fill" }
        if lowercased.contains("anchor") { return "anchor" }
        if lowercased.contains("drying_rack") { return "grid" }
        if lowercased.contains("bell") { return "bell.fill" }
        if lowercased.contains("notice_board") { return "map.fill" }
        if lowercased.contains("barrel") { return "cylinder.split.1x2" }
        if lowercased.contains("compass_rose") { return "location.north.circle.fill" }
        if lowercased.contains("grass") { return "leaf.fill" }
        if lowercased.contains("cottage") || lowercased.contains("house") { return "house.fill" }
        if lowercased.contains("crate") { return "shippingbox.fill" }
        if lowercased.contains("boat") { return "sailboat.fill" }
        if lowercased.contains("navigator") { return "figure.wave" }
        return "cube.transparent.fill"
    }
}

enum Asset3DCatalog {
    private static let preferredOrder = [
        "island_base",
        "home_island_foundation",
        "conifer_tree",
        "small_lake",
        "weathered_cottage",
        "weathered_lighthouse",
        "wooden_jetty",
        "campfire_circle",
        "log_stool",
        "stone_well",
        "voyage_flagpole",
        "cliff_lookout",
        "mossy_ruins",
        "stone_path_straight",
        "stone_path_curve",
        "stone_path_fork",
        "coastal_rocks",
        "navigator_tent",
        "weathered_crate",
        "harbor_lantern_post",
        "driftwood_bench",
        "stone_bench",
        "wooden_bookshelf",
        "stacked_books",
        "weathered_anchor",
        "net_drying_rack",
        "navigator_hammock",
        "voyage_signal_bell",
        "voyage_notice_board",
        "supply_barrels",
        "compass_rose_inlay",
        "dune_grass_patch",
        "rose_bush_white",
        "rose_bush_red",
        "rose_bush_yellow",
        "hibiscus_bush_red",
        "hibiscus_bush_pink",
        "hibiscus_bush_orange",
        "council_table",
        "council_chair",
        "palm_tree",
        "beach_parasol",
        "swim_ring",
        "sandcastle",
        "watermelon",
        "seaside_mailbox",
        "seaside_gramophone",
        "office_desk",
        "office_desk_pink",
        "office_chair",
        "office_chair_pink",
        "silver_laptop",
        "spring_water_bottle",
        "sparkling_water_bottle",
        "canned_coffee",
        "landfall_boat",
        "garden_estate_ship",
        "pirate_ship",
        "navigator_main",
    ]

    static func available(in bundle: Bundle = .main) -> [Asset3DDescriptor] {
        var names = Set(
            (bundle.urls(forResourcesWithExtension: "usdz", subdirectory: nil) ?? [])
                .map { $0.deletingPathExtension().lastPathComponent }
        )
        // コード生成アセットもUSDZと同じIDで保存・複製できる。
        names.insert("small_lake")

        // Xcode のリソース同期方式や Preview によって列挙できない場合も、既知素材は個別に拾う。
        for name in preferredOrder where bundle.url(forResource: name, withExtension: "usdz") != nil {
            names.insert(name)
        }

        return names
            .map { Asset3DDescriptor(id: $0, displayName: displayName(for: $0)) }
            .sorted { lhs, rhs in
                let lhsIndex = preferredOrder.firstIndex(of: lhs.id) ?? Int.max
                let rhsIndex = preferredOrder.firstIndex(of: rhs.id) ?? Int.max
                if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    static func displayName(for resourceName: String) -> String {
        switch resourceName {
        case "island_base": return LF.text("Island Foundation")
        case "home_island_foundation": return LF.text("Home Island Foundation")
        case "conifer_tree": return LF.text("Conifer")
        case "small_lake": return LF.text("Small Lake")
        case "weathered_cottage": return LF.text("Weathered Cottage")
        case "weathered_lighthouse": return LF.text("Stone Lighthouse")
        case "wooden_jetty": return LF.text("Wooden Jetty")
        case "campfire_circle": return LF.text("Campfire")
        case "log_stool": return LF.text("Log Stool")
        case "stone_well": return LF.text("Stone Well")
        case "voyage_flagpole": return LF.text("Voyage Flagpole")
        case "cliff_lookout": return LF.text("Cliff Lookout")
        case "mossy_ruins": return LF.text("Mossy Ruins")
        case "stone_path_straight": return LF.text("Stone Path — Straight")
        case "stone_path_curve": return LF.text("Stone Path — Curve")
        case "stone_path_fork": return LF.text("Stone Path — Fork")
        case "coastal_rocks": return LF.text("Coastal Rocks")
        case "navigator_tent": return LF.text("Navigator's Tent")
        case "weathered_crate": return LF.text("Weathered Crate")
        case "harbor_lantern_post": return LF.text("Harbor Lantern Post")
        case "driftwood_bench": return LF.text("Driftwood Bench")
        case "stone_bench": return LF.text("Stone Bench")
        case "wooden_bookshelf": return LF.text("Bookshelf")
        case "stacked_books": return LF.text("Stacked Books")
        case "weathered_anchor": return LF.text("Weathered Anchor")
        case "net_drying_rack": return LF.text("Net Drying Rack")
        case "navigator_hammock": return LF.text("Navigator's Hammock")
        case "voyage_signal_bell": return LF.text("Voyage Signal Bell")
        case "voyage_notice_board": return LF.text("Voyage Notice Board")
        case "supply_barrels": return LF.text("Supply Barrels")
        case "compass_rose_inlay": return LF.text("Compass Rose Inlay")
        case "dune_grass_patch": return LF.text("Dune Grass Patch")
        case "rose_bush_white": return LF.text("White Roses")
        case "rose_bush_red": return LF.text("Red Roses")
        case "rose_bush_yellow": return LF.text("Yellow Roses")
        case "hibiscus_bush_red": return LF.text("Red Hibiscus")
        case "hibiscus_bush_pink": return LF.text("Pink Hibiscus")
        case "hibiscus_bush_orange": return LF.text("Orange Hibiscus")
        case "council_table": return LF.text("Council Table")
        case "council_chair": return LF.text("Council Chair")
        case "palm_tree": return LF.text("Palm Tree")
        case "beach_parasol": return LF.text("Beach Parasol")
        case "swim_ring": return LF.text("Swim Ring")
        case "sandcastle": return LF.text("Sandcastle")
        case "watermelon": return LF.text("Watermelon")
        case "seaside_mailbox": return LF.text("Seaside Mailbox")
        case "seaside_gramophone": return LF.text("Seaside Gramophone")
        case "office_desk": return LF.text("Desk")
        case "office_desk_pink": return LF.text("Desk (Pink)")
        case "office_chair": return LF.text("Chair")
        case "office_chair_pink": return LF.text("Chair (Pink)")
        case "silver_laptop": return LF.text("PC")
        case "spring_water_bottle": return LF.text("Water Bottle")
        case "sparkling_water_bottle": return LF.text("Sparkling Water")
        case "canned_coffee": return LF.text("Canned Coffee")
        case "landfall_boat": return "Landfall Boat"
        case "garden_estate_ship": return "Garden Estate Ship"
        case "pirate_ship": return "Pirate Ship"
        case "navigator_main": return "Navigator"
        default:
            return resourceName
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }
    }

    static func providesPlacementSurface(for resourceName: String) -> Bool {
        if let studioID = SavedAssetStudio.id(fromAssetID: resourceName),
           let contents = AssetPlacementPersistence.contents(forStudioID: studioID) {
            return !contents.terrainStrokes.isEmpty || contents.placements.contains { placement in
                isBundledPlacementSurface(placement.assetID)
            }
        }
        return isBundledPlacementSurface(resourceName)
    }

    private static func isBundledPlacementSurface(_ resourceName: String) -> Bool {
        let normalized = resourceName.lowercased()
        return normalized == "island_base"
            || normalized.contains("foundation")
            || normalized.contains("platform")
            || normalized.contains("ground")
    }
}

/// 配置をどのゲーム空間へ反映するか。
enum AssetPlacementContext: String, CaseIterable, Codable, Identifiable {
    case destinationIsland
    case studio

    var id: String { rawValue }
}

/// 空の編集空間を名前付きで保存したもの。中身は各配置・筆跡のstudioIDで関連付ける。
struct SavedAssetStudio: Identifiable, Codable, Equatable, Hashable {
    static let assetIDPrefix = "saved-studio:"

    var id: UUID
    var name: String

    var assetID: String { Self.assetIDPrefix + id.uuidString }

    static func id(fromAssetID assetID: String) -> UUID? {
        guard assetID.hasPrefix(assetIDPrefix) else { return nil }
        return UUID(uuidString: String(assetID.dropFirst(assetIDPrefix.count)))
    }
}

enum AssetManipulationMode: String, CaseIterable, Identifiable {
    case select
    case paint
    case terrain
    case place
    case move
    case height
    case rotate
    case scale
    case camera

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .select: return "rectangle.dashed"
        case .paint: return "paintbrush.pointed.fill"
        case .terrain: return "mountain.2.fill"
        case .place: return "plus.circle.fill"
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .height: return "arrow.up.and.down"
        case .rotate: return "rotate.3d"
        case .scale: return "arrow.up.left.and.arrow.down.right"
        case .camera: return "camera.viewfinder"
        }
    }
}

/// SwiftUIの操作パネルからSceneKitのカメラへ送る一回限りの指示。
enum AssetStudioCameraAction: Equatable {
    case reset
    case overview
    case homeShipMarker
    case homeShipView
    case focusSelection
    case moveForward
    case moveBackward
    case moveLeft
    case moveRight
    case zoomIn
    case zoomOut
    case top
    case front
    case side
}

struct AssetStudioCameraRequest: Equatable {
    let id = UUID()
    let action: AssetStudioCameraAction
}

struct AssetTransform: Codable, Equatable {
    var x: Float = 0
    var y: Float = 0
    var z: Float = 0
    var pitch: Float = 0
    var yaw: Float = 0
    var roll: Float = 0
    var scale: Float = 1

    func apply(to node: SCNNode) {
        node.position = SCNVector3(x, y, z)
        node.eulerAngles = SCNVector3(pitch, yaw, roll)
        let uniformScale = max(scale, 0.001)
        node.scale = SCNVector3(uniformScale, uniformScale, uniformScale)
    }
}

struct AssetPlacement: Identifiable, Codable, Equatable {
    var id: UUID
    var assetID: String
    var name: String
    var context: AssetPlacementContext
    var studioID: UUID? = nil
    var transform: AssetTransform
}

enum AssetPaintMaterial: String, CaseIterable, Codable, Identifiable {
    case sand
    case grass
    case path
    case rock
    case snow

    var id: String { rawValue }

    var color: UIColor {
        switch self {
        // 島の地形で実際に使っている浜・苔・中腹の岩色へ合わせる。
        // ペンだけ別の高彩度パレットにすると、同じ光を当ててもシール状に浮いて見える。
        case .sand: return VoyageSceneKit.beach
        case .grass: return UIColor(rgb: 0x58705A)
        case .path: return UIColor(rgb: 0x929276)
        case .rock: return AssetTerrainMaterial.rock.color
        case .snow: return AssetTerrainMaterial.snow.color
        }
    }
}

enum AssetPaintTool: String, CaseIterable, Identifiable {
    case sand
    case grass
    case path
    case rock
    case snow
    case eraser

    var id: String { rawValue }

    var material: AssetPaintMaterial? {
        AssetPaintMaterial(rawValue: rawValue)
    }

    var symbolName: String {
        switch self {
        case .sand: return "circle.hexagongrid.fill"
        case .grass: return "leaf.fill"
        case .path: return "road.lanes"
        case .rock: return "mountain.2.fill"
        case .snow: return "snowflake"
        case .eraser: return "eraser.fill"
        }
    }
}

struct AssetPaintPoint: Codable, Equatable {
    var x: Float
    var y: Float
    var z: Float

    var vector: SCNVector3 { SCNVector3(x, y, z) }
}

struct AssetPaintStroke: Identifiable, Codable, Equatable {
    var id: UUID
    var context: AssetPlacementContext
    var studioID: UUID? = nil
    var material: AssetPaintMaterial
    var width: Float
    var points: [AssetPaintPoint]
}

/// 地形ブラシ。ストロークを時系列で再生し、一枚の連続した高さフィールドを作る。
enum AssetTerrainTool: String, CaseIterable, Codable, Identifiable {
    case raise
    case lower
    case smooth

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .raise: return "mountain.2.fill"
        case .lower: return "arrow.down.to.line"
        case .smooth: return "wind"
        }
    }
}

/// 山の断面を一操作で作るためのブラシ形状。
/// パラメータを個別に追い込まなくても、選んでタップするだけで基本形が出来る。
enum AssetTerrainShape: String, CaseIterable, Codable, Identifiable {
    case hill
    case mountain
    case plateau
    case ridge

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .hill: return "mountain.2"
        case .mountain: return "mountain.2.fill"
        case .plateau: return "rectangle.3.group.fill"
        case .ridge: return "waveform.path"
        }
    }

    var radius: Float {
        switch self {
        case .hill: return 1.45
        case .mountain: return 1.30
        case .plateau: return 1.70
        case .ridge: return 0.78
        }
    }

    var strength: Float {
        switch self {
        case .hill: return 0.95
        case .mountain: return 1.85
        case .plateau: return 1.15
        case .ridge: return 1.25
        }
    }
}

/// 地形自体に焼き込む表面素材。後から塗り直す必要を減らす。
enum AssetTerrainMaterial: String, CaseIterable, Codable, Identifiable {
    case grass
    case earth
    case sand
    case rock
    case snow

    var id: String { rawValue }

    var color: UIColor {
        switch self {
        case .grass: return UIColor(rgb: 0x62A164)
        case .earth: return UIColor(rgb: 0x9A6847)
        case .sand: return UIColor(rgb: 0xE5C980)
        case .rock: return UIColor(rgb: 0x7D8074)
        case .snow: return UIColor(rgb: 0xE2E9DF)
        }
    }

    var symbolName: String {
        switch self {
        case .grass: return "leaf.fill"
        case .earth: return "circle.hexagongrid.fill"
        case .sand: return "sun.max.fill"
        case .rock: return "mountain.2.fill"
        case .snow: return "snowflake"
        }
    }
}

struct AssetTerrainStroke: Identifiable, Codable, Equatable {
    var id: UUID
    var context: AssetPlacementContext
    var studioID: UUID? = nil
    var tool: AssetTerrainTool
    var radius: Float
    var strength: Float
    /// nilは旧データ。緑地形として安全に移行する。
    var shape: AssetTerrainShape? = nil
    var material: AssetTerrainMaterial? = nil
    var points: [AssetPaintPoint]
}

private struct AssetPlacementDocument: Codable {
    var version = 7
    /// 最後に完全なJSONとして検証できた保存時刻。primary/recoveryの新しい方を選ぶためにも使う。
    var savedAt: Date? = nil
    var placements: [AssetPlacement]
    var paintStrokes: [AssetPaintStroke]?
    var terrainStrokes: [AssetTerrainStroke]?
    var studios: [SavedAssetStudio]?
    var activeStudioID: UUID?
}

enum AssetPlacementPersistence {
    /// 配布アプリに焼き込む目的地の既定デザイン。
    /// 3DスタジオのApplication Supportだけを参照すると、開発端末で作った島が
    /// App Store / TestFlightの新規インストールへ届かないため、同じdocument形式を
    /// Bundleにも持たせる。端末で編集済みのdocumentがある場合は常にそちらを優先する。
    private static let bundledDefaultResourceName = "DefaultAssetPlacements"

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Landfall", isDirectory: true)
            .appendingPathComponent("AssetPlacements.json", isDirectory: false)
    }

    /// primaryへの置換中にアプリが終了しても、同じ内容をここから復旧できる。
    static var recoveryFileURL: URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent("AssetPlacements.recovery.json", isDirectory: false)
    }

    private enum PersistenceError: Error {
        case verificationFailed(URL)
    }

    private static func decodedDocument(at url: URL) -> (AssetPlacementDocument, Data)? {
        guard let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(AssetPlacementDocument.self, from: data)
        else { return nil }
        return (document, data)
    }

    private static func bundledDefaultDocument(bundle: Bundle = .main) -> AssetPlacementDocument? {
        guard let url = bundle.url(
            forResource: bundledDefaultResourceName,
            withExtension: "json"
        ) else { return nil }
        return decodedDocument(at: url)?.0
    }

    /// 通常ファイルが欠損・破損していてもrecoveryから最新の完全保存を読み戻す。
    private static func loadDocument() -> AssetPlacementDocument? {
        let primary = decodedDocument(at: fileURL)
        let recovery = decodedDocument(at: recoveryFileURL)

        switch (primary, recovery) {
        case let (.some(primary), .some(recovery)):
            let primaryDate = primary.0.savedAt ?? .distantPast
            let recoveryDate = recovery.0.savedAt ?? .distantPast
            guard recoveryDate > primaryDate else { return primary.0 }
            try? recovery.1.write(to: fileURL, options: .atomic)
            return recovery.0
        case let (.some(primary), .none):
            return primary.0
        case let (.none, .some(recovery)):
            try? recovery.1.write(to: fileURL, options: .atomic)
            return recovery.0
        case (.none, .none):
            // Clean installでも、ホーム・航海中・目的地が開発時と同じ最新の島を使う。
            return bundledDefaultDocument()
        }
    }

    private static func writeAndVerify(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        guard let persistedData = try? Data(contentsOf: url),
              persistedData == data,
              (try? JSONDecoder().decode(AssetPlacementDocument.self, from: persistedData)) != nil
        else {
            throw PersistenceError.verificationFailed(url)
        }
    }

    static func load() -> [AssetPlacement] {
        guard let document = loadDocument() else { return [] }
        return document.placements
    }

    static func loadPaintStrokes() -> [AssetPaintStroke] {
        guard let document = loadDocument() else { return [] }
        return document.paintStrokes ?? []
    }

    static func loadTerrainStrokes() -> [AssetTerrainStroke] {
        guard let document = loadDocument() else { return [] }
        return document.terrainStrokes ?? []
    }

    static func loadStudios() -> [SavedAssetStudio] {
        guard let document = loadDocument() else { return [] }
        return document.studios ?? []
    }

    static func loadActiveStudioID() -> UUID? {
        loadDocument()?.activeStudioID
    }

    static func loadSavedAt() -> Date? {
        if let savedAt = loadDocument()?.savedAt { return savedAt }
        return try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    static func activeStudioContents(
    ) -> (
        studio: SavedAssetStudio,
        placements: [AssetPlacement],
        paintStrokes: [AssetPaintStroke],
        terrainStrokes: [AssetTerrainStroke]
    )? {
        guard let document = loadDocument() else { return nil }
        let studios = document.studios ?? []
        let studioIDs = Set(studios.map(\.id))
        let formerlyPlacedStudioID = document.placements.reversed().compactMap { placement in
            placement.context == .destinationIsland
                ? SavedAssetStudio.id(fromAssetID: placement.assetID)
                : nil
        }.first(where: studioIDs.contains)
        let firstStudioWithContent = studios.first { studio in
            document.placements.contains {
                $0.context == .studio && $0.studioID == studio.id
            } || (document.paintStrokes ?? []).contains {
                $0.context == .studio && $0.studioID == studio.id
            } || (document.terrainStrokes ?? []).contains {
                $0.context == .studio && $0.studioID == studio.id
            }
        }?.id
        guard let studioID = [document.activeStudioID, formerlyPlacedStudioID, firstStudioWithContent]
            .compactMap({ $0 })
            .first(where: studioIDs.contains),
              let studio = studios.first(where: { $0.id == studioID })
        else { return nil }
        return (
            studio,
            document.placements.filter { $0.context == .studio && $0.studioID == studioID },
            (document.paintStrokes ?? []).filter { $0.context == .studio && $0.studioID == studioID },
            (document.terrainStrokes ?? []).filter { $0.context == .studio && $0.studioID == studioID }
        )
    }

    static func contents(
        forStudioID studioID: UUID
    ) -> (
        studio: SavedAssetStudio,
        placements: [AssetPlacement],
        paintStrokes: [AssetPaintStroke],
        terrainStrokes: [AssetTerrainStroke]
    )? {
        guard let document = loadDocument(),
              let studio = document.studios?.first(where: { $0.id == studioID })
        else { return nil }
        return (
            studio,
            document.placements.filter { $0.context == .studio && $0.studioID == studioID },
            (document.paintStrokes ?? []).filter { $0.context == .studio && $0.studioID == studioID },
            (document.terrainStrokes ?? []).filter { $0.context == .studio && $0.studioID == studioID }
        )
    }

    static func save(
        _ placements: [AssetPlacement],
        paintStrokes: [AssetPaintStroke],
        terrainStrokes: [AssetTerrainStroke],
        studios: [SavedAssetStudio],
        activeStudioID: UUID?
    ) throws -> Date {
        let savedAt = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(
            AssetPlacementDocument(
                savedAt: savedAt,
                placements: placements,
                paintStrokes: paintStrokes,
                terrainStrokes: terrainStrokes,
                studios: studios,
                activeStudioID: activeStudioID
            )
        )
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // 先にrecovery、次にprimaryへ同一データを原子的に保存し、双方を読み戻して検証する。
        // どちらか一方への置換中に終了しても、次回はsavedAtが新しい完全な方を採用する。
        try writeAndVerify(data, to: recoveryFileURL)
        try writeAndVerify(data, to: fileURL)
        return savedAt
    }

    static func encodedString(
        _ placements: [AssetPlacement],
        paintStrokes: [AssetPaintStroke],
        terrainStrokes: [AssetTerrainStroke],
        studios: [SavedAssetStudio],
        activeStudioID: UUID?
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(
            AssetPlacementDocument(
                savedAt: Date(),
                placements: placements,
                paintStrokes: paintStrokes,
                terrainStrokes: terrainStrokes,
                studios: studios,
                activeStudioID: activeStudioID
            )
        ) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}

private struct AssetStudioSnapshot: Equatable {
    var placements: [AssetPlacement]
    var paintStrokes: [AssetPaintStroke]
    var terrainStrokes: [AssetTerrainStroke]
}

/// 編集UIとSceneKit表示の単一の状態源。配置変更は自動保存される。
@MainActor
final class AssetPlacementStore: ObservableObject {
    @Published private(set) var placements: [AssetPlacement]
    @Published private(set) var paintStrokes: [AssetPaintStroke]
    @Published private(set) var terrainStrokes: [AssetTerrainStroke]
    @Published private(set) var studios: [SavedAssetStudio]
    @Published private(set) var selectedStudioID: UUID?
    @Published private(set) var activeStudioID: UUID?
    @Published private(set) var selectedID: UUID?
    @Published private(set) var selectedIDs: Set<UUID>
    @Published var context: AssetPlacementContext
    @Published var manipulationMode: AssetManipulationMode = .move
    @Published var paintTool: AssetPaintTool = .sand
    @Published var paintWidth: Float = 0.48
    @Published var terrainTool: AssetTerrainTool = .raise
    @Published var terrainShape: AssetTerrainShape = .mountain
    @Published var terrainMaterial: AssetTerrainMaterial = .grass
    @Published var terrainRadius: Float = AssetTerrainShape.mountain.radius
    @Published var terrainStrength: Float = AssetTerrainShape.mountain.strength
    @Published var placementBrushAssetID: String?
    @Published var followsPlacementSurface = true
    @Published private(set) var lastSaveSucceeded = true
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var lastSavedAt: Date?
    @Published private(set) var lastSaveError: String?
    @Published private(set) var cameraRequest: AssetStudioCameraRequest?
    @Published private(set) var surfaceSnapRequestID: UUID?
    @Published private(set) var surfaceSnapClampsOnly = false

    let catalog: [Asset3DDescriptor]

    private var history: [AssetStudioSnapshot]
    private var historyIndex = 0
    private var interactionStart: AssetStudioSnapshot?
    private var autosaveTask: Task<Void, Never>?

    init(
        placements: [AssetPlacement]? = nil,
        paintStrokes: [AssetPaintStroke]? = nil,
        terrainStrokes: [AssetTerrainStroke]? = nil,
        studios: [SavedAssetStudio]? = nil,
        activeStudioID: UUID? = nil,
        catalog: [Asset3DDescriptor] = Asset3DCatalog.available()
    ) {
        let loadedEntireDocumentFromPersistence = placements == nil
            && paintStrokes == nil
            && terrainStrokes == nil
            && studios == nil
        var didMigrateLegacyStudio = false
        var didRemoveUnavailableAssets = false
        var resolvedPlacements = placements ?? AssetPlacementPersistence.load()
        var resolvedPaintStrokes = paintStrokes ?? AssetPlacementPersistence.loadPaintStrokes()
        var resolvedTerrainStrokes = terrainStrokes ?? AssetPlacementPersistence.loadTerrainStrokes()
        var resolvedStudios = studios ?? AssetPlacementPersistence.loadStudios()
        var resolvedActiveStudioID = activeStudioID
            ?? (loadedEntireDocumentFromPersistence ? AssetPlacementPersistence.loadActiveStudioID() : nil)

        // version 2までの「空のスタジオ」内データを、最初の保存済みスタジオへ無損失移行する。
        if resolvedStudios.isEmpty {
            resolvedStudios = [SavedAssetStudio(id: UUID(), name: LF.text("My Studio"))]
            didMigrateLegacyStudio = true
        }
        if let legacyStudioID = resolvedStudios.first?.id {
            for index in resolvedPlacements.indices
            where resolvedPlacements[index].context == .studio
                && resolvedPlacements[index].studioID == nil {
                resolvedPlacements[index].studioID = legacyStudioID
                didMigrateLegacyStudio = true
            }
            for index in resolvedPaintStrokes.indices
            where resolvedPaintStrokes[index].context == .studio
                && resolvedPaintStrokes[index].studioID == nil {
                resolvedPaintStrokes[index].studioID = legacyStudioID
                didMigrateLegacyStudio = true
            }
            for index in resolvedTerrainStrokes.indices
            where resolvedTerrainStrokes[index].context == .studio
                && resolvedTerrainStrokes[index].studioID == nil {
                resolvedTerrainStrokes[index].studioID = legacyStudioID
                didMigrateLegacyStudio = true
            }
        }

        // 削除済みのバンドルアセットを古い保存データから復活させない。
        // 保存済みスタジオを参照する複合アセットだけは、有効なstudioIDなら維持する。
        let availableAssetIDs = Set(catalog.map(\.id))
        let existingSavedStudioIDs = Set(resolvedStudios.map(\.id))
        let placementCountBeforeSanitizing = resolvedPlacements.count
        resolvedPlacements.removeAll { placement in
            if availableAssetIDs.contains(placement.assetID) { return false }
            if let studioID = SavedAssetStudio.id(fromAssetID: placement.assetID) {
                return !existingSavedStudioIDs.contains(studioID)
            }
            return true
        }
        didRemoveUnavailableAssets = resolvedPlacements.count != placementCountBeforeSanitizing

        // v3まではスタジオ全体を島に「配置」していた。旧参照があればそれを、
        // なければ内容を持つ最初のスタジオをゲーム世界として無損失で引き継ぐ。
        let existingStudioIDs = Set(resolvedStudios.map(\.id))
        if let activeCandidate = resolvedActiveStudioID,
           !existingStudioIDs.contains(activeCandidate) {
            resolvedActiveStudioID = nil
            didMigrateLegacyStudio = true
        }
        if resolvedActiveStudioID == nil {
            let formerlyPlacedStudioID = resolvedPlacements.reversed().compactMap { placement in
                placement.context == .destinationIsland
                    ? SavedAssetStudio.id(fromAssetID: placement.assetID)
                    : nil
            }.first(where: existingStudioIDs.contains)
            let firstStudioWithContent = resolvedStudios.first { studio in
                resolvedPlacements.contains {
                    $0.context == .studio && $0.studioID == studio.id
                } || resolvedPaintStrokes.contains {
                    $0.context == .studio && $0.studioID == studio.id
                }
            }?.id
            let firstStudioWithTerrain = resolvedStudios.first { studio in
                resolvedTerrainStrokes.contains {
                    $0.context == .studio && $0.studioID == studio.id
                }
            }?.id
            resolvedActiveStudioID = formerlyPlacedStudioID
                ?? firstStudioWithContent
                ?? firstStudioWithTerrain
            didMigrateLegacyStudio = resolvedActiveStudioID != nil || didMigrateLegacyStudio
        }

        self.placements = resolvedPlacements
        self.paintStrokes = resolvedPaintStrokes
        self.terrainStrokes = resolvedTerrainStrokes
        self.studios = resolvedStudios
        selectedStudioID = resolvedStudios.first?.id
        self.activeStudioID = resolvedActiveStudioID
        self.catalog = catalog
        context = .destinationIsland
        history = [AssetStudioSnapshot(
            placements: resolvedPlacements,
            paintStrokes: resolvedPaintStrokes,
            terrainStrokes: resolvedTerrainStrokes
        )]
        lastSavedAt = loadedEntireDocumentFromPersistence
            ? AssetPlacementPersistence.loadSavedAt()
            : nil
        let initialSelection = resolvedPlacements.first {
            $0.context == .destinationIsland
                && SavedAssetStudio.id(fromAssetID: $0.assetID) == nil
        }?.id
        selectedID = initialSelection
        selectedIDs = initialSelection.map { [$0] } ?? []

        // 移行で発行したstudioIDを固定し、次回起動時にも複合アセット参照を維持する。
        if loadedEntireDocumentFromPersistence
            && (didMigrateLegacyStudio || didRemoveUnavailableAssets) {
            lastSavedAt = try? AssetPlacementPersistence.save(
                resolvedPlacements,
                paintStrokes: resolvedPaintStrokes,
                terrainStrokes: resolvedTerrainStrokes,
                studios: resolvedStudios,
                activeStudioID: resolvedActiveStudioID
            )
        }
    }

    var visiblePlacements: [AssetPlacement] {
        placements.filter { placement in
            guard placement.context == context else { return false }
            // v3までの複合アセット参照はアクティブ世界へ移行済み。
            if context == .destinationIsland,
               SavedAssetStudio.id(fromAssetID: placement.assetID) != nil {
                return false
            }
            return context != .studio || placement.studioID == selectedStudioID
        }
    }

    var visiblePaintStrokes: [AssetPaintStroke] {
        paintStrokes.filter { stroke in
            guard stroke.context == context else { return false }
            return context != .studio || stroke.studioID == selectedStudioID
        }
    }

    var visibleTerrainStrokes: [AssetTerrainStroke] {
        terrainStrokes.filter { stroke in
            guard stroke.context == context else { return false }
            return context != .studio || stroke.studioID == selectedStudioID
        }
    }

    var currentStudio: SavedAssetStudio? {
        guard let selectedStudioID else { return nil }
        return studios.first { $0.id == selectedStudioID }
    }

    var currentStudioHasContent: Bool {
        !visiblePlacements.isEmpty || !visiblePaintStrokes.isEmpty || !visibleTerrainStrokes.isEmpty
    }

    var studioAssetDescriptors: [Asset3DDescriptor] {
        studios.compactMap { studio in
            let hasContent = placements.contains {
                $0.context == .studio && $0.studioID == studio.id
            } || paintStrokes.contains {
                $0.context == .studio && $0.studioID == studio.id
            } || terrainStrokes.contains {
                $0.context == .studio && $0.studioID == studio.id
            }
            return hasContent
                ? Asset3DDescriptor(id: studio.assetID, displayName: studio.name)
                : nil
        }
    }

    var availableAssetCount: Int {
        catalog.count + (context == .destinationIsland ? studioAssetDescriptors.count : 0)
    }

    var selectedPlacement: AssetPlacement? {
        guard let selectedID else { return nil }
        return placements.first { $0.id == selectedID }
    }

    var selectedPlacements: [AssetPlacement] {
        visiblePlacements.filter { selectedIDs.contains($0.id) }
    }

    var selectedPaintStrokes: [AssetPaintStroke] {
        visiblePaintStrokes.filter { selectedIDs.contains($0.id) }
    }

    var selectedTerrainStrokes: [AssetTerrainStroke] {
        visibleTerrainStrokes.filter { selectedIDs.contains($0.id) }
    }

    var visibleSelectableIDs: Set<UUID> {
        Set(visiblePlacements.map(\.id))
            .union(visiblePaintStrokes.map(\.id))
            .union(visibleTerrainStrokes.map(\.id))
    }

    var selectionCount: Int { selectedIDs.count }

    var canUndo: Bool { historyIndex > 0 }
    var canRedo: Bool { historyIndex + 1 < history.count }

    func setContext(_ newContext: AssetPlacementContext) {
        guard context != newContext else { return }
        endInteractiveEdit()
        context = newContext
        followsPlacementSurface = true
        let initialSelection = visiblePlacements.first?.id
        selectedID = initialSelection
        selectedIDs = initialSelection.map { [$0] } ?? []
    }

    func selectStudio(_ studioID: UUID) {
        guard studios.contains(where: { $0.id == studioID }) else { return }
        endInteractiveEdit()
        context = .studio
        selectedStudioID = studioID
        followsPlacementSurface = true
        let initialSelection = placements.first {
            $0.context == .studio && $0.studioID == studioID
        }?.id
        selectedID = initialSelection
        selectedIDs = initialSelection.map { [$0] } ?? []
        requestCamera(.reset)
    }

    @discardableResult
    func createStudio(named proposedName: String) -> UUID {
        endInteractiveEdit()
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = String(
            format: LF.text("Studio %lld"),
            Int64(studios.count + 1)
        )
        let studio = SavedAssetStudio(
            id: UUID(),
            name: trimmedName.isEmpty ? fallbackName : trimmedName
        )
        studios.append(studio)
        selectedStudioID = studio.id
        context = .studio
        selectedID = nil
        selectedIDs.removeAll()
        save()
        requestCamera(.reset)
        return studio.id
    }

    @discardableResult
    func renameCurrentStudio(to proposedName: String) -> Bool {
        guard let selectedStudioID,
              let index = studios.firstIndex(where: { $0.id == selectedStudioID })
        else { return false }
        let trimmedName = String(
            proposedName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(40)
        )
        guard !trimmedName.isEmpty else { return false }
        guard studios[index].name != trimmedName else { return true }
        studios[index].name = trimmedName
        markDocumentChanged()
        save()
        return lastSaveSucceeded
    }

    func saveCurrentStudio() {
        guard let selectedStudioID else { return }
        endInteractiveEdit()
        activeStudioID = selectedStudioID
        save()
    }

    @discardableResult
    func useCurrentStudioInGame() -> Bool {
        guard currentStudio != nil, currentStudioHasContent else { return false }
        saveCurrentStudio()
        setContext(.destinationIsland)
        return lastSaveSucceeded
    }

    @discardableResult
    func useStudioInGame(_ studioID: UUID) -> Bool {
        let hasContent = placements.contains {
            $0.context == .studio && $0.studioID == studioID
        } || paintStrokes.contains {
            $0.context == .studio && $0.studioID == studioID
        } || terrainStrokes.contains {
            $0.context == .studio && $0.studioID == studioID
        }
        guard studios.contains(where: { $0.id == studioID }), hasContent else { return false }
        endInteractiveEdit()
        activeStudioID = studioID
        save()
        return lastSaveSucceeded
    }

    func select(_ id: UUID?) {
        guard let id, visibleSelectableIDs.contains(id) else {
            selectedID = nil
            selectedIDs.removeAll()
            return
        }
        selectedIDs = [id]
        selectedID = visiblePlacements.contains(where: { $0.id == id }) ? id : nil
    }

    func select(_ ids: Set<UUID>, primary: UUID? = nil) {
        let visibleIDs = visibleSelectableIDs
        let validIDs = ids.intersection(visibleIDs)
        selectedIDs = validIDs
        if let primary,
           validIDs.contains(primary),
           visiblePlacements.contains(where: { $0.id == primary }) {
            selectedID = primary
        } else {
            selectedID = visiblePlacements.first(where: { validIDs.contains($0.id) })?.id
        }
    }

    func requestCamera(_ action: AssetStudioCameraAction) {
        cameraRequest = AssetStudioCameraRequest(action: action)
    }

    func requestSurfaceSnap(clampOnly: Bool = false) {
        surfaceSnapClampsOnly = clampOnly
        surfaceSnapRequestID = UUID()
    }

    @discardableResult
    func add(
        assetID: String,
        at surfacePoint: AssetPaintPoint? = nil,
        interactively: Bool = false
    ) -> UUID {
        let awaitsSurfaceSnap = surfacePoint != nil
        if interactively || awaitsSurfaceSnap {
            beginInteractiveEdit()
        } else {
            endInteractiveEdit()
        }
        let duplicateCount = placements.filter { $0.assetID == assetID }.count
        let baseName = studios.first(where: { $0.assetID == assetID })?.name
            ?? Asset3DCatalog.displayName(for: assetID)
        var initialTransform = AssetTransform()
        if let surfacePoint {
            initialTransform.x = surfacePoint.x
            initialTransform.y = surfacePoint.y
            initialTransform.z = surfacePoint.z
            // 連続配置でも完全に同じ向きに並ばず、自然な密度に見える。
            initialTransform.yaw = Float(duplicateCount % 12) * (.pi / 6)
        } else if context == .destinationIsland {
            // 山体の内側へ出現させず、追加直後から見つけやすい海岸沿いへ順番に置く。
            let slot = visiblePlacements.count
            let angle = -2.45 + Float(slot % 8) * 0.76
            initialTransform.x = cos(angle) * 2.48
            initialTransform.z = sin(angle) * 1.68
            initialTransform.y = VoyageSceneKit.islandSurfaceHeight(
                x: initialTransform.x,
                z: initialTransform.z
            )
            initialTransform.yaw = -angle + .pi * 0.5
        }
        let placement = AssetPlacement(
            id: UUID(),
            assetID: assetID,
            name: duplicateCount == 0 ? baseName : "\(baseName) \(duplicateCount + 1)",
            context: context,
            studioID: context == .studio ? selectedStudioID : nil,
            transform: initialTransform
        )
        placements.append(placement)
        markDocumentChanged()
        selectedID = placement.id
        selectedIDs = [placement.id]
        followsPlacementSurface = true
        if !interactively && !awaitsSurfaceSnap { commitCurrentState() }
        requestSurfaceSnap()
        return placement.id
    }

    func choosePlacementBrush(assetID: String) {
        guard catalog.contains(where: { $0.id == assetID }) else { return }
        placementBrushAssetID = assetID
        manipulationMode = .place
        select(nil)
    }

    func finishPlacementBrush() {
        endInteractiveEdit()
        placementBrushAssetID = nil
        manipulationMode = .move
    }

    func duplicateSelected() {
        guard selectionCount == 1, var copy = selectedPlacement else { return }
        endInteractiveEdit()
        copy.id = UUID()
        copy.name += " \(LF.text("Copy"))"
        copy.transform.x += 0.35
        copy.transform.z += 0.35
        placements.append(copy)
        selectedID = copy.id
        selectedIDs = [copy.id]
        commitCurrentState()
        requestSurfaceSnap(clampOnly: !followsPlacementSurface)
    }

    func deleteSelected() {
        let deletionIDs = selectedIDs.isEmpty ? Set([selectedID].compactMap { $0 }) : selectedIDs
        guard !deletionIDs.isEmpty else { return }
        endInteractiveEdit()
        let previousCount = placements.count + paintStrokes.count + terrainStrokes.count
        placements.removeAll { deletionIDs.contains($0.id) }
        paintStrokes.removeAll { deletionIDs.contains($0.id) }
        terrainStrokes.removeAll { deletionIDs.contains($0.id) }
        guard placements.count + paintStrokes.count + terrainStrokes.count != previousCount else { return }
        selectedID = nil
        selectedIDs.removeAll()
        commitCurrentState()
    }

    func updatePlacement(
        id: UUID,
        interactively: Bool = false,
        _ mutation: (inout AssetPlacement) -> Void
    ) {
        guard let index = placements.firstIndex(where: { $0.id == id }) else { return }
        if interactively { beginInteractiveEdit() } else { endInteractiveEdit() }
        mutation(&placements[index])
        placements[index].transform.scale = min(max(placements[index].transform.scale, 0.01), 20)
        markDocumentChanged()
        if !interactively { commitCurrentState() }
    }

    func updateSelectedTransform(
        interactively: Bool = false,
        _ mutation: (inout AssetTransform) -> Void
    ) {
        guard let selectedID else { return }
        updatePlacement(id: selectedID, interactively: interactively) { placement in
            mutation(&placement.transform)
        }
    }

    @discardableResult
    func beginPaintStroke(at point: AssetPaintPoint) -> UUID? {
        beginInteractiveEdit()
        guard let material = paintTool.material else {
            erasePaint(at: point, radius: paintWidth * 0.72)
            return nil
        }
        let stroke = AssetPaintStroke(
            id: UUID(),
            context: context,
            studioID: context == .studio ? selectedStudioID : nil,
            material: material,
            width: paintWidth,
            points: [point]
        )
        paintStrokes.append(stroke)
        markDocumentChanged()
        return stroke.id
    }

    func appendPaintPoint(_ point: AssetPaintPoint, to strokeID: UUID) {
        guard let index = paintStrokes.firstIndex(where: { $0.id == strokeID }) else { return }
        paintStrokes[index].points.append(point)
        markDocumentChanged()
    }

    func erasePaint(at point: AssetPaintPoint, radius: Float? = nil) {
        let eraserRadius = radius ?? paintWidth * 0.72
        var result: [AssetPaintStroke] = []

        for stroke in paintStrokes {
            let belongsToCurrentWorld = stroke.context == context
                && (context != .studio || stroke.studioID == selectedStudioID)
            guard belongsToCurrentWorld else {
                result.append(stroke)
                continue
            }

            var runs: [[AssetPaintPoint]] = [[]]
            for candidate in stroke.points {
                let dx = candidate.x - point.x
                let dz = candidate.z - point.z
                let outsideEraser = sqrt(dx * dx + dz * dz) > eraserRadius + stroke.width * 0.32
                if outsideEraser {
                    runs[runs.count - 1].append(candidate)
                } else if !runs[runs.count - 1].isEmpty {
                    runs.append([])
                }
            }

            let remainingRuns = runs.filter { !$0.isEmpty }
            for (index, points) in remainingRuns.enumerated() {
                result.append(
                    AssetPaintStroke(
                        id: index == 0 ? stroke.id : UUID(),
                        context: stroke.context,
                        studioID: stroke.studioID,
                        material: stroke.material,
                        width: stroke.width,
                        points: points
                    )
                )
            }
        }
        guard result != paintStrokes else { return }
        paintStrokes = result
        markDocumentChanged()
    }

    @discardableResult
    func beginTerrainStroke(at point: AssetPaintPoint) -> UUID {
        beginInteractiveEdit()
        let stroke = AssetTerrainStroke(
            id: UUID(),
            context: context,
            studioID: context == .studio ? selectedStudioID : nil,
            tool: terrainTool,
            radius: terrainRadius,
            strength: terrainStrength,
            shape: terrainShape,
            material: terrainMaterial,
            points: [point]
        )
        terrainStrokes.append(stroke)
        markDocumentChanged()
        return stroke.id
    }

    /// 形を選ぶだけで実用的な半径・高さへ切り替える。
    func selectTerrainShape(_ shape: AssetTerrainShape) {
        terrainShape = shape
        terrainTool = .raise
        terrainRadius = shape.radius
        terrainStrength = shape.strength
    }

    /// ツール切替時に用途に合う安全な初期値へ移す。特に「削る」は一筆で
    /// 大きく失わず、同じ場所を重ねて深さを決められる精密ステップにする。
    func selectTerrainTool(_ tool: AssetTerrainTool) {
        guard terrainTool != tool else { return }
        terrainTool = tool
        switch tool {
        case .raise:
            terrainRadius = max(terrainRadius, terrainShape.radius)
            terrainStrength = terrainShape.strength
        case .lower:
            terrainRadius = min(terrainRadius, 0.72)
            terrainStrength = 0.10
        case .smooth:
            terrainRadius = min(max(terrainRadius, 0.55), 1.4)
            terrainStrength = 0.32
        }
    }

    func appendTerrainPoint(_ point: AssetPaintPoint, to strokeID: UUID) {
        guard let index = terrainStrokes.firstIndex(where: { $0.id == strokeID }) else { return }
        terrainStrokes[index].points.append(point)
        markDocumentChanged()
    }

    func clearVisibleTerrain() {
        endInteractiveEdit()
        let before = terrainStrokes.count
        terrainStrokes.removeAll { stroke in
            stroke.context == context
                && (context != .studio || stroke.studioID == selectedStudioID)
        }
        guard terrainStrokes.count != before else { return }
        commitCurrentState()
    }

    /// すでに作った山を描き直さず、表面素材だけを一括変更する。
    func recolorVisibleTerrain(to material: AssetTerrainMaterial) {
        endInteractiveEdit()
        var changed = false
        for index in terrainStrokes.indices {
            let stroke = terrainStrokes[index]
            guard stroke.context == context,
                  context != .studio || stroke.studioID == selectedStudioID,
                  stroke.tool == .raise,
                  stroke.material != material
            else { continue }
            terrainStrokes[index].material = material
            changed = true
        }
        guard changed else { return }
        terrainMaterial = material
        commitCurrentState()
    }

    func beginInteractiveEdit() {
        if interactionStart == nil { interactionStart = currentSnapshot }
    }

    func endInteractiveEdit() {
        guard let interactionStart else { return }
        // SceneViewはドラッグ中の穴を防ぐため高密度に点を送る。表示結果を
        // ほぼ変えない許容誤差で操作終了時に簡略化し、長い山脈や谷でも
        // JSON、Undoスナップショット、メッシュ再生成を小さく保つ。
        simplifyChangedStrokes(comparedTo: interactionStart)
        self.interactionStart = nil
        guard interactionStart != currentSnapshot else { return }
        commitCurrentState()
    }

    func undo() {
        endInteractiveEdit()
        guard canUndo else { return }
        historyIndex -= 1
        restore(history[historyIndex])
        repairSelection()
        markDocumentChanged()
        save()
    }

    func redo() {
        endInteractiveEdit()
        guard canRedo else { return }
        historyIndex += 1
        restore(history[historyIndex])
        repairSelection()
        markDocumentChanged()
        save()
    }

    func save() {
        autosaveTask?.cancel()
        autosaveTask = nil
        persistNow(scheduleRetryOnFailure: true)
    }

    private func persistNow(scheduleRetryOnFailure: Bool) {
        do {
            let savedAt = try AssetPlacementPersistence.save(
                placements,
                paintStrokes: paintStrokes,
                terrainStrokes: terrainStrokes,
                studios: studios,
                activeStudioID: activeStudioID
            )
            lastSaveSucceeded = true
            hasUnsavedChanges = false
            lastSavedAt = savedAt
            lastSaveError = nil
            NotificationCenter.default.post(name: .assetStudioWorldDidChange, object: nil)
        } catch {
            lastSaveSucceeded = false
            hasUnsavedChanges = true
            lastSaveError = error.localizedDescription
            if scheduleRetryOnFailure {
                scheduleAutosave(afterNanoseconds: 1_500_000_000)
            }
        }
    }

    /// 操作中でも最大約0.4秒分までしか未保存にしない、先頭エッジ型の自動保存。
    /// ドラッグ終了を待たないため、長い地形ストロークの途中で中断されても復元できる。
    private func markDocumentChanged() {
        hasUnsavedChanges = true
        scheduleAutosave()
    }

    private func scheduleAutosave(afterNanoseconds delay: UInt64 = 400_000_000) {
        guard autosaveTask == nil else { return }
        autosaveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard let self else { return }
            self.autosaveTask = nil
            guard self.hasUnsavedChanges else { return }
            self.persistNow(scheduleRetryOnFailure: true)
        }
    }

    func exportJSONString() -> String {
        AssetPlacementPersistence.encodedString(
            placements,
            paintStrokes: paintStrokes,
            terrainStrokes: terrainStrokes,
            studios: studios,
            activeStudioID: activeStudioID
        )
    }

    private var currentSnapshot: AssetStudioSnapshot {
        AssetStudioSnapshot(
            placements: placements,
            paintStrokes: paintStrokes,
            terrainStrokes: terrainStrokes
        )
    }

    private func restore(_ snapshot: AssetStudioSnapshot) {
        placements = snapshot.placements
        paintStrokes = snapshot.paintStrokes
        terrainStrokes = snapshot.terrainStrokes
    }

    private func simplifyChangedStrokes(comparedTo start: AssetStudioSnapshot) {
        let originalTerrainPoints = Dictionary(
            uniqueKeysWithValues: start.terrainStrokes.map { ($0.id, $0.points) }
        )
        for index in terrainStrokes.indices {
            let stroke = terrainStrokes[index]
            guard originalTerrainPoints[stroke.id] != stroke.points else { continue }
            terrainStrokes[index].points = Self.simplifiedPoints(
                stroke.points,
                tolerance: max(stroke.radius * 0.045, 0.012)
            )
        }
    }

    /// Ramer–Douglas–Peucker。XZだけでなくYも評価し、斜面上のストロークを浮かせない。
    private static func simplifiedPoints(
        _ points: [AssetPaintPoint],
        tolerance: Float
    ) -> [AssetPaintPoint] {
        guard points.count > 2 else { return points }
        let squaredTolerance = tolerance * tolerance
        var retained = Array(repeating: false, count: points.count)
        retained[0] = true
        retained[points.count - 1] = true
        var ranges: [(Int, Int)] = [(0, points.count - 1)]

        while let (start, end) = ranges.popLast() {
            guard end > start + 1 else { continue }
            var furthestIndex: Int?
            var furthestDistance: Float = 0
            for index in (start + 1)..<end {
                let distance = squaredDistance(
                    from: points[index],
                    toSegmentFrom: points[start],
                    to: points[end]
                )
                if distance > furthestDistance {
                    furthestDistance = distance
                    furthestIndex = index
                }
            }
            guard let furthestIndex, furthestDistance > squaredTolerance else { continue }
            retained[furthestIndex] = true
            ranges.append((start, furthestIndex))
            ranges.append((furthestIndex, end))
        }

        return zip(points, retained).compactMap { point, keep in keep ? point : nil }
    }

    private static func squaredDistance(
        from point: AssetPaintPoint,
        toSegmentFrom start: AssetPaintPoint,
        to end: AssetPaintPoint
    ) -> Float {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let dz = end.z - start.z
        let lengthSquared = dx * dx + dy * dy + dz * dz
        guard lengthSquared > 0.000_001 else {
            let px = point.x - start.x
            let py = point.y - start.y
            let pz = point.z - start.z
            return px * px + py * py + pz * pz
        }
        let projection = min(max(
            ((point.x - start.x) * dx
                + (point.y - start.y) * dy
                + (point.z - start.z) * dz) / lengthSquared,
            0
        ), 1)
        let px = point.x - (start.x + dx * projection)
        let py = point.y - (start.y + dy * projection)
        let pz = point.z - (start.z + dz * projection)
        return px * px + py * py + pz * pz
    }

    private func commitCurrentState() {
        if historyIndex + 1 < history.count {
            history.removeSubrange((historyIndex + 1)..<history.count)
        }
        let snapshot = currentSnapshot
        if history.last != snapshot {
            history.append(snapshot)
            if history.count > 80 { history.removeFirst(history.count - 80) }
            historyIndex = history.count - 1
        }
        markDocumentChanged()
        save()
    }

    private func repairSelection() {
        let visibleIDs = visibleSelectableIDs
        selectedIDs.formIntersection(visibleIDs)
        let visiblePlacementIDs = Set(visiblePlacements.map(\.id))
        if let selectedID, visiblePlacementIDs.contains(selectedID) {
            selectedIDs.insert(selectedID)
        } else {
            selectedID = visiblePlacements.first(where: { selectedIDs.contains($0.id) })?.id
        }
        if selectedIDs.isEmpty, let fallback = visiblePlacements.first?.id
            ?? visiblePaintStrokes.first?.id
            ?? visibleTerrainStrokes.first?.id {
            selectedID = fallback
            selectedIDs = [fallback]
            if !visiblePlacementIDs.contains(fallback) { selectedID = nil }
        }
    }
}

/// 保存済み配置をゲーム本編のSceneKitノードへ取り込む。
enum AssetPlacementRuntime {
    static let placementSurfaceCategory = 1 << 12

    /// Parsed USDZ roots, kept one per resource.
    ///
    /// Every prop used to re-parse its file: an island with ten trees paid the
    /// tree's load ten times, all of it on the main thread while the first
    /// frame waited. A prototype is parsed once and each placement gets a
    /// clone, which shares the geometry instead of rebuilding it.
    private static let prototypeLock = NSLock()
    private static var prototypeCache: [String: SCNNode] = [:]

    /// Parses the given resources on a background queue so the scene can be
    /// built from warm cache entries. Safe to call repeatedly; already-cached
    /// resources cost nothing.
    static func preload(resourceNames: [String], bundle: Bundle = .main) {
        let pending = Set(resourceNames).filter { name in
            prototypeLock.lock()
            defer { prototypeLock.unlock() }
            return prototypeCache[name] == nil
        }
        guard !pending.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            for name in pending {
                _ = prototype(resourceName: name, bundle: bundle)
            }
        }
    }

    /// The parsed, un-instanced root for a resource. Geometry only: physics
    /// bodies and looping actions belong to each instance, so they are applied
    /// after cloning rather than baked into the shared prototype.
    private static func prototype(resourceName: String, bundle: Bundle) -> SCNNode? {
        prototypeLock.lock()
        let cached = prototypeCache[resourceName]
        prototypeLock.unlock()
        if let cached { return cached }

        guard let url = bundle.url(forResource: resourceName, withExtension: "usdz") else {
            return nil
        }
        let container = SCNNode()
        if let reference = SCNReferenceNode(url: url) {
            reference.load()
            for child in reference.childNodes {
                container.addChildNode(child)
            }
        } else if let scene = try? SCNScene(url: url, options: nil) {
            for child in scene.rootNode.childNodes {
                container.addChildNode(child)
            }
        } else {
            return nil
        }

        prototypeLock.lock()
        prototypeCache[resourceName] = container
        prototypeLock.unlock()
        return container
    }

    /// ゲーム全体が表示する、現在の3Dスタジオ世界。
    /// 空のスタジオは旧来の島へフォールバックできるようnilを返す。
    static func makeActiveStudioWorldNode(bundle: Bundle = .main) -> SCNNode? {
        guard let contents = AssetPlacementPersistence.activeStudioContents(),
              !contents.placements.isEmpty
                || !contents.paintStrokes.isEmpty
                || !contents.terrainStrokes.isEmpty
        else { return nil }
        return makeAssetNode(resourceName: contents.studio.assetID, bundle: bundle)
    }

    static func makeAssetNode(resourceName: String, bundle: Bundle = .main) -> SCNNode? {
        makeAssetNode(resourceName: resourceName, bundle: bundle, resolvingStudioIDs: [])
    }

    private static func makeAssetNode(
        resourceName: String,
        bundle: Bundle,
        resolvingStudioIDs: Set<UUID>
    ) -> SCNNode? {
        if let studioID = SavedAssetStudio.id(fromAssetID: resourceName) {
            guard !resolvingStudioIDs.contains(studioID),
                  let contents = AssetPlacementPersistence.contents(forStudioID: studioID)
            else { return nil }

            var nextResolvingIDs = resolvingStudioIDs
            nextResolvingIDs.insert(studioID)
            let container = SCNNode()
            container.name = "saved-studio:\(studioID.uuidString)"

            // 各子モデルの相対座標・回転・高さ・縮尺を一切変えず、一つの親へ束ねる。
            for placement in contents.placements {
                guard let child = makeAssetNode(
                    resourceName: placement.assetID,
                    bundle: bundle,
                    resolvingStudioIDs: nextResolvingIDs
                ) else { continue }
                child.name = "saved-studio-component:\(placement.id.uuidString)"
                placement.transform.apply(to: child)
                container.addChildNode(child)
            }
            let terrain = makeTerrainNode(for: contents.terrainStrokes)
            if let terrain {
                container.addChildNode(terrain)
            }
            for stroke in contents.paintStrokes {
                container.addChildNode(makePaintNode(for: stroke, terrainNode: terrain))
            }
            return container
        }

        if resourceName == "small_lake" {
            return makeSmallLakeNode()
        }

        guard let prototype = prototype(resourceName: resourceName, bundle: bundle) else {
            return nil
        }
        let node = prototype.clone()

        if Asset3DCatalog.providesPlacementSurface(for: resourceName) {
            let shape = SCNPhysicsShape(
                node: node,
                options: [
                    // USDZは上面・側面が別の開いたメッシュなので、凹型形状では下面を拾う場合がある。
                    // 全体を閉じた凸包へ変換し、上からの接地レイが必ず支持面へ当たるようにする。
                    .type: SCNPhysicsShape.ShapeType.convexHull,
                    .keepAsCompound: false,
                ]
            )
            let body = SCNPhysicsBody(type: .static, shape: shape)
            body.categoryBitMask = placementSurfaceCategory
            body.collisionBitMask = 0
            body.contactTestBitMask = 0
            node.physicsBody = body
        }
        if resourceName == "spring_water_bottle" {
            clearThePlastic(on: node)
        }
        if resourceName == "weathered_lighthouse", !UIAccessibility.isReduceMotionEnabled {
            let beacon = node.childNode(withName: "LF_LighthouseBeaconRotor_Mesh", recursively: true)
                ?? node.childNode(withName: "LF_LighthouseBeaconRotor", recursively: true)
            beacon?.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 8)))
        }
        if resourceName == "campfire_circle", !UIAccessibility.isReduceMotionEnabled {
            let flameLayers = [
                ("LF_CampfireFlameOuter", 0.72, 0.34, 2.8),
                ("LF_CampfireFlameMid", 0.80, 0.27, -2.2),
                ("LF_CampfireFlameCore", 0.86, 0.21, 1.7),
            ]
            for (name, dimOpacity, pulseDuration, turnDuration) in flameLayers {
                let flame = node.childNode(withName: "\(name)_Mesh", recursively: true)
                    ?? node.childNode(withName: name, recursively: true)
                let flicker = SCNAction.sequence([
                    .fadeOpacity(to: dimOpacity, duration: pulseDuration),
                    .fadeOpacity(to: 1, duration: pulseDuration * 0.72),
                ])
                flame?.runAction(.repeatForever(flicker), forKey: "campfire-flicker")
                let turnAngle = turnDuration < 0 ? -CGFloat.pi * 2 : CGFloat.pi * 2
                flame?.runAction(
                    .repeatForever(.rotateBy(x: 0, y: turnAngle, z: 0, duration: abs(turnDuration))),
                    forKey: "campfire-turn"
                )
            }
        }
        if resourceName == "voyage_flagpole", !UIAccessibility.isReduceMotionEnabled {
            let sway = SCNAction.sequence([
                .rotateBy(x: 0, y: 0, z: 0.035, duration: 0.72),
                .rotateBy(x: 0, y: 0, z: -0.07, duration: 1.18),
                .rotateBy(x: 0, y: 0, z: 0.035, duration: 0.72),
            ])
            for name in ["LF_VoyageFlagCloth", "LF_VoyageFlagMark"] {
                let flagPart = node.childNode(withName: "\(name)_Mesh", recursively: true)
                    ?? node.childNode(withName: name, recursively: true)
                flagPart?.runAction(.repeatForever(sway), forKey: "voyage-flag-sway")
            }
        }
        return node
    }

    /// Turn the water bottle's shell to clear plastic.
    ///
    /// The bottle is authored as ordinary opaque plastic and made transparent
    /// here rather than in Blender: USD's own opacity arrives in SceneKit as a
    /// material that still writes depth, which hides the water standing inside
    /// the very shell it is meant to be seen through. Set in code, the shell
    /// stops writing depth and is drawn after everything else, so the water,
    /// the label and the ribs on the far wall all read through it.
    ///
    /// The material names come from `Tools/Blender/build_drink_set.py`, which
    /// merges each prop's meshes by material — so one name is one surface.
    private static func clearThePlastic(on node: SCNNode) {
        for name in ["LF_DrinkPetShell", "LF_DrinkPetShellShade"] {
            let part = node.childNode(withName: "\(name)_Mesh", recursively: true)
                ?? node.childNode(withName: name, recursively: true)
            guard let part else { continue }
            part.renderingOrder = 40
            for material in part.geometry?.materials ?? [] {
                material.transparency = 0.34
                material.blendMode = .alpha
                material.transparencyMode = .dualLayer
                material.writesToDepthBuffer = false
                material.isDoubleSided = true
            }
        }
    }

    /// 保存・複製・ゲーム反映ができるコード生成の小さな湖。
    /// 岸、浅瀬、水面、波紋、岩、葦を別レイヤーにし、どの視点でも厚みが読める。
    private static func makeSmallLakeNode() -> SCNNode {
        let root = SCNNode()
        root.name = "small-lake"

        let basinGeometry = SCNCylinder(radius: 1, height: 0.10)
        basinGeometry.radialSegmentCount = 64
        basinGeometry.firstMaterial = VoyageSceneKit.litMaterial(
            UIColor(rgb: 0x74715E),
            roughness: 0.98,
            doubleSided: true,
            fogged: false
        )
        let basin = SCNNode(geometry: basinGeometry)
        basin.name = "small-lake-basin"
        basin.position.y = 0.05
        basin.scale = SCNVector3(1.34, 1, 0.91)
        basin.castsShadow = true
        root.addChildNode(basin)

        let shore = makeLakeShoreNode()
        shore.position.y = 0.105
        root.addChildNode(shore)

        let water = makeLakeWaterNode()
        water.position.y = 0.122
        root.addChildNode(water)

        let rockMaterial = VoyageSceneKit.litMaterial(
            UIColor(rgb: 0x777A6D),
            roughness: 0.92,
            doubleSided: true,
            fogged: false
        )
        for index in 0..<14 {
            let angle = Float(index) / 14 * 2 * .pi + sin(Float(index) * 2.19) * 0.08
            let boundary = lakeBoundaryScale(at: angle)
            let radius = 1.13 + sin(Float(index) * 1.71) * 0.08
            let sphere = SCNSphere(radius: CGFloat(0.085 + Float(index % 3) * 0.014))
            sphere.segmentCount = 7
            sphere.firstMaterial = rockMaterial
            let rock = SCNNode(geometry: sphere)
            rock.name = "small-lake-shore-rock"
            rock.position = SCNVector3(
                cos(angle) * radius * boundary * 1.10,
                0.14 + Float(index % 2) * 0.012,
                sin(angle) * radius * boundary * 0.76
            )
            rock.scale = SCNVector3(
                1.0 + sin(Float(index) * 0.9) * 0.20,
                0.58 + Float(index % 4) * 0.06,
                0.82 + cos(Float(index) * 1.3) * 0.14
            )
            rock.eulerAngles.y = angle * 1.7
            rock.castsShadow = true
            root.addChildNode(rock)
        }

        for cluster in 0..<4 {
            let angle = Float(cluster) * 1.47 + 0.46
            let clusterNode = makeLakeReedCluster(index: cluster)
            clusterNode.position = SCNVector3(
                cos(angle) * 1.02 * lakeBoundaryScale(at: angle),
                0.10,
                sin(angle) * 0.70 * lakeBoundaryScale(at: angle)
            )
            clusterNode.eulerAngles.y = -angle
            root.addChildNode(clusterNode)
        }

        // 半透明の波紋を時間差で広げ、静止画的な水面にならないようにする。
        for index in 0..<3 {
            let torus = SCNTorus(ringRadius: 0.68, pipeRadius: 0.008)
            torus.ringSegmentCount = 64
            torus.pipeSegmentCount = 5
            let rippleColor = UIColor(rgb: 0xBCE8DC).withAlphaComponent(0.42)
            let rippleMaterial = VoyageSceneKit.unlitMaterial(rippleColor)
            rippleMaterial.blendMode = .add
            rippleMaterial.writesToDepthBuffer = false
            torus.firstMaterial = rippleMaterial
            let ripple = SCNNode(geometry: torus)
            ripple.name = "small-lake-ripple"
            ripple.position = SCNVector3(
                -0.32 + Float(index) * 0.28,
                0.143 + Float(index) * 0.001,
                -0.12 + Float(index % 2) * 0.22
            )
            ripple.opacity = 0
            ripple.renderingOrder = 82 + index
            let delay = SCNAction.wait(duration: Double(index) * 0.92)
            let travel = SCNAction.customAction(duration: 3.0) { node, elapsed in
                let progress = min(max(Float(elapsed / 3.0), 0), 1)
                let scale = 0.36 + progress * 0.92
                node.scale = SCNVector3(scale, 1, scale * 0.70)
                node.opacity = CGFloat(sin(progress * .pi) * 0.34)
            }
            ripple.runAction(.repeatForever(.sequence([delay, travel])))
            root.addChildNode(ripple)
        }

        return root
    }

    private static func makeLakeShoreNode() -> SCNNode {
        let segments = 72
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var colors: [UIColor] = []
        var indices: [Int32] = []
        vertices.reserveCapacity((segments + 1) * 2)
        normals.reserveCapacity((segments + 1) * 2)
        colors.reserveCapacity((segments + 1) * 2)

        for segment in 0...segments {
            let angle = Float(segment) / Float(segments) * 2 * .pi
            let boundary = lakeBoundaryScale(at: angle)
            let inner = boundary * (0.91 + sin(angle * 5.2) * 0.012)
            let outer = boundary * (1.16 + cos(angle * 4.1) * 0.024)
            vertices.append(SCNVector3(cos(angle) * inner, 0.005, sin(angle) * inner * 0.69))
            vertices.append(SCNVector3(cos(angle) * outer, sin(angle * 6.3) * 0.010, sin(angle) * outer * 0.72))
            normals.append(contentsOf: [SCNVector3(0, 1, 0), SCNVector3(0, 1, 0)])
            colors.append(UIColor(rgb: 0xB2A67C))
            colors.append(UIColor(rgb: 0x7C8265).scaled(CGFloat(0.96 + sin(angle * 3.7) * 0.05)))
            if segment < segments {
                let base = Int32(segment * 2)
                indices.append(contentsOf: [base, base + 2, base + 1, base + 1, base + 2, base + 3])
            }
        }

        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: vertices),
                SCNGeometrySource(normals: normals),
                paintColorSource(colors),
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        geometry.firstMaterial = VoyageSceneKit.litMaterial(
            .white,
            roughness: 0.97,
            doubleSided: true,
            fogged: false
        )
        let node = SCNNode(geometry: geometry)
        node.name = "small-lake-shore"
        node.castsShadow = true
        return node
    }

    private static func makeLakeWaterNode() -> SCNNode {
        let segments = 72
        let rings = 7
        var vertices = [SCNVector3(0, 0, 0)]
        var normals = [SCNVector3(0, 1, 0)]
        var colors = [UIColor(rgb: 0x70C9BE).withAlphaComponent(0.90)]
        var indices: [Int32] = []

        for ring in 1...rings {
            let radial = Float(ring) / Float(rings)
            for segment in 0..<segments {
                let angle = Float(segment) / Float(segments) * 2 * .pi
                let boundary = lakeBoundaryScale(at: angle) * 0.90
                let staticRipple = sin(angle * 5 + radial * 8.3) * 0.004 * radial
                vertices.append(SCNVector3(
                    cos(angle) * radial * boundary,
                    staticRipple,
                    sin(angle) * radial * boundary * 0.69
                ))
                normals.append(SCNVector3(0, 1, 0))
                let edgeBlend = CGFloat(radial)
                colors.append(
                    blend(
                        UIColor(rgb: 0x73CFC2).withAlphaComponent(0.90),
                        UIColor(rgb: 0x296F6C).withAlphaComponent(0.84),
                        amount: Float(edgeBlend * 0.52)
                    )
                )
            }
        }

        for segment in 0..<segments {
            let current = Int32(1 + segment)
            let next = Int32(1 + (segment + 1) % segments)
            indices.append(contentsOf: [0, next, current])
        }
        if rings > 1 {
            for ring in 1..<rings {
                let innerStart = 1 + (ring - 1) * segments
                let outerStart = 1 + ring * segments
                for segment in 0..<segments {
                    let nextSegment = (segment + 1) % segments
                    let inner = Int32(innerStart + segment)
                    let innerNext = Int32(innerStart + nextSegment)
                    let outer = Int32(outerStart + segment)
                    let outerNext = Int32(outerStart + nextSegment)
                    indices.append(contentsOf: [inner, outerNext, outer, inner, innerNext, outerNext])
                }
            }
        }

        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: vertices),
                SCNGeometrySource(normals: normals),
                paintColorSource(colors),
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        let material = SCNMaterial()
        material.name = "small-lake-water-material"
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(rgb: 0x4A9F98).withAlphaComponent(0.92)
        material.roughness.contents = 0.20
        material.metalness.contents = 0.03
        material.emission.contents = UIColor(rgb: 0x1E5C59).withAlphaComponent(0.06)
        material.isDoubleSided = true
        material.blendMode = .alpha
        material.transparencyMode = .dualLayer
        material.fresnelExponent = 1.35
        material.shaderModifiers = [
            .geometry: """
            #pragma body
            float waveA = sin((_geometry.position.x * 7.0) + scn_frame.time * 1.35);
            float waveB = cos((_geometry.position.z * 9.0) - scn_frame.time * 1.05);
            _geometry.position.y += (waveA + waveB) * 0.0065;
            """
        ]
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.name = "small-lake-water"
        node.renderingOrder = 80
        return node
    }

    private static func makeLakeReedCluster(index: Int) -> SCNNode {
        let cluster = SCNNode()
        cluster.name = "small-lake-reeds"
        let stemMaterial = VoyageSceneKit.litMaterial(
            UIColor(rgb: 0x456A4D),
            roughness: 0.90,
            doubleSided: true,
            fogged: false
        )
        let headMaterial = VoyageSceneKit.litMaterial(
            UIColor(rgb: 0x5B4634),
            roughness: 0.96,
            doubleSided: true,
            fogged: false
        )
        for reedIndex in 0..<5 {
            let height = 0.25 + Float((reedIndex + index) % 3) * 0.055
            let stemGeometry = SCNCylinder(radius: 0.010, height: CGFloat(height))
            stemGeometry.radialSegmentCount = 6
            stemGeometry.firstMaterial = stemMaterial
            let stem = SCNNode(geometry: stemGeometry)
            stem.position = SCNVector3(
                Float(reedIndex - 2) * 0.045,
                height * 0.5,
                sin(Float(reedIndex) * 2.3) * 0.035
            )
            stem.eulerAngles.z = Float(reedIndex - 2) * 0.018
            stem.castsShadow = true
            cluster.addChildNode(stem)

            if reedIndex % 2 == 0 {
                let headGeometry = SCNSphere(radius: 0.024)
                headGeometry.segmentCount = 7
                headGeometry.firstMaterial = headMaterial
                let head = SCNNode(geometry: headGeometry)
                head.position = SCNVector3(stem.position.x, height + 0.018, stem.position.z)
                head.scale.y = 1.8
                cluster.addChildNode(head)
            }
        }
        return cluster
    }

    private static func lakeBoundaryScale(at angle: Float) -> Float {
        1 + sin(angle * 3.1 + 0.4) * 0.055 + cos(angle * 5.3 - 0.7) * 0.034
    }

    private final class TerrainHeightField: NSObject {
        let minimumX: Float
        let minimumZ: Float
        let stepX: Float
        let stepZ: Float
        let columns: Int
        let rows: Int
        let heights: [Float]
        let coverage: [Float]

        init(
            minimumX: Float,
            minimumZ: Float,
            stepX: Float,
            stepZ: Float,
            columns: Int,
            rows: Int,
            heights: [Float],
            coverage: [Float]
        ) {
            self.minimumX = minimumX
            self.minimumZ = minimumZ
            self.stepX = stepX
            self.stepZ = stepZ
            self.columns = columns
            self.rows = rows
            self.heights = heights
            self.coverage = coverage
        }

        func height(atX x: Float, z: Float) -> Float? {
            let gridX = (x - minimumX) / max(stepX, 0.0001)
            let gridZ = (z - minimumZ) / max(stepZ, 0.0001)
            guard gridX >= 0, gridZ >= 0,
                  gridX <= Float(columns - 1), gridZ <= Float(rows - 1)
            else { return nil }

            let left = min(max(Int(floor(gridX)), 0), columns - 1)
            let top = min(max(Int(floor(gridZ)), 0), rows - 1)
            let right = min(left + 1, columns - 1)
            let bottom = min(top + 1, rows - 1)
            let fractionX = gridX - Float(left)
            let fractionZ = gridZ - Float(top)
            let topHeight = heights[top * columns + left]
                + (heights[top * columns + right] - heights[top * columns + left]) * fractionX
            let bottomHeight = heights[bottom * columns + left]
                + (heights[bottom * columns + right] - heights[bottom * columns + left]) * fractionX
            let topCoverage = coverage[top * columns + left]
                + (coverage[top * columns + right] - coverage[top * columns + left]) * fractionX
            let bottomCoverage = coverage[bottom * columns + left]
                + (coverage[bottom * columns + right] - coverage[bottom * columns + left]) * fractionX
            let sampledCoverage = topCoverage + (bottomCoverage - topCoverage) * fractionZ
            guard sampledCoverage > 0.025 else { return nil }
            return topHeight + (bottomHeight - topHeight) * fractionZ
        }

        func normal(atX x: Float, z: Float) -> SCNVector3? {
            guard let center = height(atX: x, z: z) else { return nil }
            let sampleX = max(stepX, 0.025)
            let sampleZ = max(stepZ, 0.025)
            let left = height(atX: x - sampleX, z: z) ?? center
            let right = height(atX: x + sampleX, z: z) ?? center
            let near = height(atX: x, z: z - sampleZ) ?? center
            let far = height(atX: x, z: z + sampleZ) ?? center
            let raw = SCNVector3(
                -(right - left) / max(sampleX * 2, 0.0001),
                1,
                -(far - near) / max(sampleZ * 2, 0.0001)
            )
            let length = max(sqrt(raw.x * raw.x + raw.y * raw.y + raw.z * raw.z), 0.0001)
            return SCNVector3(raw.x / length, raw.y / length, raw.z / length)
        }
    }

    private final class TerrainSceneNode: SCNNode {
        var heightField: TerrainHeightField?

        override init() {
            super.init()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }
    }

    /// 複数のブラシ履歴を一枚の連続メッシュへ変換する。
    /// 同じ場所を重ねると峰が高くなり、長く引くと尾根になる。
    static func makeTerrainNode(for strokes: [AssetTerrainStroke]) -> SCNNode? {
        let validStrokes = strokes.filter { !$0.points.isEmpty && $0.radius > 0.02 }
        // 保存時はポイントを簡略化し、メッシュ化時だけ等間隔に復元する。
        // 見た目の連続性と大規模マップの保存コストを両立する。
        let renderPoints = Dictionary(
            uniqueKeysWithValues: validStrokes.map { stroke in
                (stroke.id, resampledTerrainPoints(for: stroke))
            }
        )
        let allPoints = validStrokes.flatMap { renderPoints[$0.id] ?? $0.points }
        guard !allPoints.isEmpty else { return nil }

        let largestRadius = validStrokes.map(\.radius).max() ?? 0.8
        let padding = largestRadius * 1.06
        let minimumX = (allPoints.map(\.x).min() ?? 0) - padding
        let maximumX = (allPoints.map(\.x).max() ?? 0) + padding
        let minimumZ = (allPoints.map(\.z).min() ?? 0) - padding
        let maximumZ = (allPoints.map(\.z).max() ?? 0) + padding
        let width = max(maximumX - minimumX, 0.2)
        let depth = max(maximumZ - minimumZ, 0.2)

        // 小さなブラシは細かく、広域地形は端末で扱える頂点数に自動調整。
        // 従来の137固定上限で起きていた、広いマップの山頂や尾根の角張りを抑える。
        let smallestRadius = validStrokes.map(\.radius).min() ?? 0.8
        let preferredStep = min(max(smallestRadius / 13, 0.045), 0.14)
        let columns = min(max(Int(ceil(width / preferredStep)) + 1, 7), 193)
        let rows = min(max(Int(ceil(depth / preferredStep)) + 1, 7), 193)
        let stepX = width / Float(columns - 1)
        let stepZ = depth / Float(rows - 1)
        let vertexCount = columns * rows
        let averageBaseY = allPoints.map(\.y).reduce(0, +) / Float(allPoints.count)
        var baseHeights = Array(repeating: averageBaseY, count: vertexCount)
        var nearestBaseDistances = Array(repeating: Float.greatestFiniteMagnitude, count: vertexCount)

        func affectedRange(
            coordinate: Float,
            minimum: Float,
            step: Float,
            radius: Float,
            count: Int
        ) -> ClosedRange<Int> {
            let lower = max(0, Int(floor((coordinate - radius - minimum) / step)))
            let upper = min(count - 1, Int(ceil((coordinate + radius - minimum) / step)))
            return lower...max(lower, upper)
        }

        // 曲面の土台上でも接地するよう、各頂点の基準高を最寄りの入力点から求める。
        for stroke in validStrokes {
            let reach = stroke.radius * 1.5
            for point in renderPoints[stroke.id] ?? stroke.points {
                let columnRange = affectedRange(
                    coordinate: point.x,
                    minimum: minimumX,
                    step: stepX,
                    radius: reach,
                    count: columns
                )
                let rowRange = affectedRange(
                    coordinate: point.z,
                    minimum: minimumZ,
                    step: stepZ,
                    radius: reach,
                    count: rows
                )
                for row in rowRange {
                    let z = minimumZ + Float(row) * stepZ
                    for column in columnRange {
                        let x = minimumX + Float(column) * stepX
                        let distanceSquared = pow(x - point.x, 2) + pow(z - point.z, 2)
                        let index = row * columns + column
                        if distanceSquared < nearestBaseDistances[index] {
                            nearestBaseDistances[index] = distanceSquared
                            baseHeights[index] = point.y
                        }
                    }
                }
            }
        }

        var heights = baseHeights
        // 「盛る」で作った高さだけを記録し、川岸の視覚補助と削れる山体を区別する。
        // これにより平地で削る操作を重ねても、前の一筆が次の一筆で打ち消されない。
        var raisedRelief = Array(repeating: Float.zero, count: vertexCount)
        // 各頂点が最後に受けた「盛る」ブラシの素材を保持。
        // v5までの地形はグレー固定にせず、芝生へ移行する。
        var surfaceMaterials = Array(repeating: AssetTerrainMaterial.grass, count: vertexCount)
        var weatheringMask = Array(repeating: Float.zero, count: vertexCount)
        for stroke in validStrokes {
            var influence = Array(repeating: Float.zero, count: vertexCount)
            let radius = max(stroke.radius, 0.03)
            for point in renderPoints[stroke.id] ?? stroke.points {
                let columnRange = affectedRange(
                    coordinate: point.x,
                    minimum: minimumX,
                    step: stepX,
                    radius: radius,
                    count: columns
                )
                let rowRange = affectedRange(
                    coordinate: point.z,
                    minimum: minimumZ,
                    step: stepZ,
                    radius: radius,
                    count: rows
                )
                for row in rowRange {
                    let z = minimumZ + Float(row) * stepZ
                    for column in columnRange {
                        let x = minimumX + Float(column) * stepX
                        let normalizedDistance = sqrt(pow(x - point.x, 2) + pow(z - point.z, 2)) / radius
                        guard normalizedDistance < 1 else { continue }
                        let remaining = 1 - normalizedDistance
                        let smoothFalloff = remaining * remaining * (3 - 2 * remaining)
                        let value: Float
                        switch stroke.shape ?? .hill {
                        case .hill:
                            value = smoothFalloff
                        case .mountain:
                            // すそ野は滑らかで、山頂だけをしっかり立てる。
                            value = pow(remaining, 1.32)
                        case .plateau:
                            // 中心45%を平らに、外周を段丘の斜面にする。
                            if normalizedDistance <= 0.45 {
                                value = 1
                            } else {
                                let edge = max(0, (1 - normalizedDistance) / 0.55)
                                value = edge * edge * (3 - 2 * edge)
                            }
                        case .ridge:
                            // 細い横断面でドラッグ軌跡を繋ぐと、一筆で尾根になる。
                            value = pow(smoothFalloff, 0.72)
                        }
                        let index = row * columns + column
                        influence[index] = max(influence[index], value)
                    }
                }
            }

            let terrainShape = stroke.shape ?? .hill
            let detailSeed = paintSeed(for: stroke.id)
            switch stroke.tool {
            case .raise:
                for index in heights.indices where influence[index] > 0 {
                    let row = index / columns
                    let column = index % columns
                    let x = minimumX + Float(column) * stepX
                    let z = minimumZ + Float(row) * stepZ
                    let detail = terrainDetail(atX: x, z: z, seed: detailSeed)
                    var delta = stroke.strength * influence[index]
                    switch terrainShape {
                    case .hill:
                        // 丘のシルエットは保ち、同じ形のコピー感だけを消す。
                        delta *= 1 + detail * 0.035 * min(influence[index] * 2, 1)
                    case .mountain:
                        // 大小二段の決定的ノイズで岩稜と枝尾根を一筆で作る。
                        delta *= 1 + detail * 0.19 * pow(influence[index], 0.42)
                        weatheringMask[index] = max(weatheringMask[index], influence[index])
                    case .plateau:
                        // 中心の平面と外周の段丘を同時に作る。
                        let terraceStep = max(stroke.strength / 4.5, 0.08)
                        let terraced = floor(delta / terraceStep + 0.20) * terraceStep
                        delta = delta * 0.18 + terraced * 0.82
                    case .ridge:
                        delta *= 1 + detail * 0.12 * min(influence[index] * 1.6, 1)
                        weatheringMask[index] = max(weatheringMask[index], influence[index] * 0.78)
                    }
                    let previousHeight = heights[index]
                    heights[index] = min(
                        baseHeights[index] + 24,
                        heights[index] + max(delta, 0)
                    )
                    raisedRelief[index] += max(heights[index] - previousHeight, 0)
                    if influence[index] > 0.025 {
                        surfaceMaterials[index] = stroke.material ?? .grass
                    }
                }
            case .lower:
                for index in heights.indices where influence[index] > 0 {
                    let row = index / columns
                    let column = index % columns
                    let x = minimumX + Float(column) * stepX
                    let z = minimumZ + Float(row) * stepZ
                    let detail = terrainDetail(atX: x, z: z, seed: detailSeed)
                    if raisedRelief[index] > 0.002 {
                        // 完全な円形ではなく、自然に枝分かれた谷・火口になる。
                        let delta = stroke.strength * influence[index] * (1 + detail * 0.08)
                        let removed = min(max(delta, 0), raisedRelief[index])
                        heights[index] = max(baseHeights[index], heights[index] - removed)
                        raisedRelief[index] = max(raisedRelief[index] - removed, 0)
                    } else {
                        // SceneKitの島土台自体に穴を開けられない場合も、平地への一筆で
                        // 両岸を生成し、元の地表を川床・谷底として見せる。
                        let shoulder = max(
                            0,
                            1 - abs(influence[index] - 0.34) / 0.24
                        )
                        let bankHeight = stroke.strength * 0.30 * shoulder * (1 + detail * 0.07)
                        heights[index] = min(
                            baseHeights[index] + 24,
                            heights[index] + max(bankHeight, 0)
                        )
                        if shoulder > 0.04 {
                            surfaceMaterials[index] = stroke.material ?? .earth
                        }
                    }
                }
            case .smooth:
                for _ in 0..<2 {
                    let source = heights
                    for row in 1..<(rows - 1) {
                        for column in 1..<(columns - 1) {
                            let index = row * columns + column
                            guard influence[index] > 0 else { continue }
                            var total: Float = 0
                            for neighborRow in (row - 1)...(row + 1) {
                                for neighborColumn in (column - 1)...(column + 1) {
                                    total += source[neighborRow * columns + neighborColumn]
                                }
                            }
                            let average = total / 9
                            let amount = min(0.92, stroke.strength * 1.8) * influence[index]
                            heights[index] = max(
                                baseHeights[index],
                                source[index] + (average - source[index]) * amount
                            )
                        }
                    }
                }
            }
        }

        // 急峻な山と尾根だけに小さな熱侵食風の緩和をかける。
        // 大きな輪郭や台地の段差は残しつつ、ノイズの孤立した針を防ぐ。
        for _ in 0..<2 {
            let source = heights
            for row in 1..<(rows - 1) {
                for column in 1..<(columns - 1) {
                    let index = row * columns + column
                    let mask = weatheringMask[index]
                    guard mask > 0.02 else { continue }
                    let neighborAverage = (
                        source[index - 1]
                            + source[index + 1]
                            + source[index - columns]
                            + source[index + columns]
                    ) / 4
                    let difference = neighborAverage - source[index]
                    let excessSlope = max(abs(difference) - 0.11, 0)
                    let amount = min(excessSlope * 0.16 * mask, 0.075)
                    heights[index] = max(
                        baseHeights[index],
                        source[index] + (difference < 0 ? -amount : amount)
                    )
                }
            }
        }

        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var colors: [UIColor] = []
        vertices.reserveCapacity(vertexCount)
        normals.reserveCapacity(vertexCount)
        colors.reserveCapacity(vertexCount)

        for row in 0..<rows {
            for column in 0..<columns {
                let index = row * columns + column
                let left = heights[row * columns + max(column - 1, 0)]
                let right = heights[row * columns + min(column + 1, columns - 1)]
                let near = heights[max(row - 1, 0) * columns + column]
                let far = heights[min(row + 1, rows - 1) * columns + column]
                let rawNormal = SCNVector3(
                    -(right - left) / max(stepX * 2, 0.0001),
                    1,
                    -(far - near) / max(stepZ * 2, 0.0001)
                )
                let normalLength = max(
                    sqrt(
                        rawNormal.x * rawNormal.x
                            + rawNormal.y * rawNormal.y
                            + rawNormal.z * rawNormal.z
                    ),
                    0.0001
                )
                let normal = SCNVector3(
                    rawNormal.x / normalLength,
                    rawNormal.y / normalLength,
                    rawNormal.z / normalLength
                )
                let elevation = heights[index] - baseHeights[index]
                let steepness = 1 - normal.y
                let selectedMaterial = surfaceMaterials[index]
                let x = minimumX + Float(column) * stepX
                let z = minimumZ + Float(row) * stepZ
                let detail = terrainDetail(atX: x, z: z, seed: 7.31)
                let baseColor = terrainSurfaceColor(
                    material: selectedMaterial,
                    elevation: elevation,
                    steepness: steepness,
                    detail: detail
                )
                let tone = 0.965 + detail * 0.045
                vertices.append(SCNVector3(x, heights[index] + 0.004, z))
                normals.append(normal)
                colors.append(baseColor.scaled(CGFloat(tone)))
            }
        }

        var indices: [Int32] = []
        indices.reserveCapacity((rows - 1) * (columns - 1) * 6)
        for row in 0..<(rows - 1) {
            for column in 0..<(columns - 1) {
                let nearLeftIndex = row * columns + column
                let nearRightIndex = nearLeftIndex + 1
                let farLeftIndex = (row + 1) * columns + column
                let farRightIndex = farLeftIndex + 1
                // ブラシの影響がない高さ0の四角形は作らない。
                // これで山の外周だけが土台へ溶け込み、長方形の板が見えない。
                let hasRelief = [nearLeftIndex, nearRightIndex, farLeftIndex, farRightIndex]
                    .contains { heights[$0] - baseHeights[$0] > 0.001 }
                guard hasRelief else { continue }
                let nearLeft = Int32(nearLeftIndex)
                let nearRight = Int32(nearRightIndex)
                let farLeft = Int32(farLeftIndex)
                let farRight = Int32(farRightIndex)
                indices.append(contentsOf: [nearLeft, farLeft, nearRight, nearRight, farLeft, farRight])
            }
        }

        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: vertices),
                SCNGeometrySource(normals: normals),
                paintColorSource(colors),
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        geometry.firstMaterial = VoyageSceneKit.litMaterial(
            .white,
            roughness: 0.94,
            doubleSided: true,
            fogged: false
        )

        let node = TerrainSceneNode()
        node.geometry = geometry
        node.name = "asset-studio-terrain"
        node.castsShadow = true
        node.renderingOrder = 12
        node.heightField = TerrainHeightField(
            minimumX: minimumX,
            minimumZ: minimumZ,
            stepX: stepX,
            stepZ: stepZ,
            columns: columns,
            rows: rows,
            heights: heights,
            coverage: zip(heights, baseHeights).map { height, baseHeight in
                min(max(abs(height - baseHeight) / 0.018, 0), 1)
            }
        )
        let shape = SCNPhysicsShape(
            geometry: geometry,
            options: [.type: SCNPhysicsShape.ShapeType.concavePolyhedron]
        )
        let body = SCNPhysicsBody(type: .static, shape: shape)
        body.categoryBitMask = placementSurfaceCategory
        body.collisionBitMask = 0
        body.contactTestBitMask = 0
        node.physicsBody = body
        return node
    }

    static func terrainSurfaceHeight(on node: SCNNode, atLocalX x: Float, z: Float) -> Float? {
        (node as? TerrainSceneNode)?.heightField?.height(atX: x, z: z)
    }

    private static func terrainSurfaceNormal(
        on node: SCNNode,
        atLocalX x: Float,
        z: Float
    ) -> SCNVector3? {
        (node as? TerrainSceneNode)?.heightField?.normal(atX: x, z: z)
    }

    private static func resampledTerrainPoints(
        for stroke: AssetTerrainStroke
    ) -> [AssetPaintPoint] {
        guard let first = stroke.points.first, stroke.points.count > 1 else {
            return stroke.points
        }
        let spacing = max(stroke.radius * 0.18, 0.055)
        var result = [first]
        result.reserveCapacity(stroke.points.count)
        for index in 1..<stroke.points.count {
            let start = stroke.points[index - 1]
            let end = stroke.points[index]
            let dx = end.x - start.x
            let dy = end.y - start.y
            let dz = end.z - start.z
            let distance = sqrt(dx * dx + dz * dz)
            let steps = max(Int(ceil(distance / spacing)), 1)
            for step in 1...steps {
                let progress = Float(step) / Float(steps)
                result.append(
                    AssetPaintPoint(
                        x: start.x + dx * progress,
                        y: start.y + dy * progress,
                        z: start.z + dz * progress
                    )
                )
            }
        }
        return result
    }

    /// 完全に決定的な二オクターブの地形ディテール。保存の度に形が変わらない。
    private static func terrainDetail(atX x: Float, z: Float, seed: Float) -> Float {
        let broad = sin(x * 1.37 + seed * 0.73) * cos(z * 1.11 - seed * 0.41)
        let fine = sin((x + z) * 3.17 + seed * 1.91)
            * cos((x - z) * 2.43 - seed * 0.83)
        return broad * 0.68 + fine * 0.32
    }

    /// 選択素材を主役に保ちながら、高度と斜度で岩肌・雪線を自動生成。
    private static func terrainSurfaceColor(
        material: AssetTerrainMaterial,
        elevation: Float,
        steepness: Float,
        detail: Float
    ) -> UIColor {
        let rock = UIColor(rgb: 0x74796F)
        let snow = UIColor(rgb: 0xDFE7DF)
        var color: UIColor
        switch material {
        case .grass:
            color = blend(
                material.color,
                UIColor(rgb: 0x426F4A),
                amount: min(max((steepness - 0.12) / 0.30, 0), 0.72)
            )
        case .earth:
            color = blend(
                material.color,
                UIColor(rgb: 0x6E4937),
                amount: min(max((steepness - 0.14) / 0.34, 0), 0.66)
            )
        case .sand:
            color = blend(
                material.color,
                UIColor(rgb: 0xBFAE83),
                amount: min(max((steepness - 0.16) / 0.34, 0), 0.58)
            )
        case .rock:
            color = blend(
                material.color,
                UIColor(rgb: 0xA4A696),
                amount: min(max(elevation / 7, 0), 0.48)
            )
        case .snow:
            color = blend(
                material.color,
                rock,
                amount: min(max((steepness - 0.18) / 0.34, 0), 0.72)
            )
        }

        // 芝・土の高山は岩壁から雪線へ自然に遷移する。
        if material == .grass || material == .earth {
            let exposedRock = min(max((steepness - 0.27) / 0.25, 0), 0.70)
            color = blend(color, rock, amount: exposedRock)
            let snowLine = 5.4 + detail * 0.55
            let snowAmount = min(max((elevation - snowLine) / 2.4, 0), 0.82)
                * min(max((0.56 - steepness) / 0.34, 0), 1)
            color = blend(color, snow, amount: snowAmount)
        }
        return color
    }

    private static func blend(_ lhs: UIColor, _ rhs: UIColor, amount: Float) -> UIColor {
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
        lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)
        let t = CGFloat(min(max(amount, 0), 1))
        return UIColor(
            red: lr + (rr - lr) * t,
            green: lg + (rg - lg) * t,
            blue: lb + (rb - lb) * t,
            alpha: la + (ra - la) * t
        )
    }

    static func makePaintNode(
        for stroke: AssetPaintStroke,
        terrainNode: SCNNode? = nil
    ) -> SCNNode {
        let container = SCNNode()
        container.name = "asset-studio-paint:\(stroke.id.uuidString)"
        let projectedPoints = stroke.points.map { point in
            AssetPaintPoint(
                x: point.x,
                y: paintSurfaceHeight(
                    atX: point.x,
                    z: point.z,
                    fallback: point.y,
                    terrainNode: terrainNode
                ),
                z: point.z
            )
        }
        guard let firstPoint = projectedPoints.first else { return container }

        let material = paintMaterial(for: stroke.material)
        let halfWidth = max(stroke.width * 0.5, 0.025)
        // 島に元からある苔パッチと同程度だけ持ち上げ、ちらつきを防ぎつつ地面へ密着させる。
        let surfaceOffset: Float = 0.016
        let seed = paintSeed(for: stroke.id)

        if projectedPoints.count > 1 {
            var vertices: [SCNVector3] = []
            var normals: [SCNVector3] = []
            var colors: [UIColor] = []
            var textureCoordinates: [CGPoint] = []
            var indices: [Int32] = []

            for index in projectedPoints.indices {
                let previous = projectedPoints[max(index - 1, 0)]
                let next = projectedPoints[min(index + 1, projectedPoints.count - 1)]
                let tangentX = next.x - previous.x
                let tangentZ = next.z - previous.z
                let tangentLength = max(sqrt(tangentX * tangentX + tangentZ * tangentZ), 0.0001)
                // 完全に平行な帯ではなく、島の海岸線と同じ程度のごく小さな揺らぎを輪郭へ入れる。
                let phase = Float(index) * 1.73 + seed
                let leftWidth = halfWidth * (1 + sin(phase) * 0.052)
                let rightWidth = halfWidth * (1 + cos(phase * 0.83 + 1.7) * 0.046)
                let sideUnitX = -tangentZ / tangentLength
                let sideUnitZ = tangentX / tangentLength
                let point = projectedPoints[index]
                let surfaceNormal = paintSurfaceNormal(
                    at: index,
                    points: projectedPoints,
                    terrainNode: terrainNode
                )
                let leftX = point.x + sideUnitX * leftWidth
                let leftZ = point.z + sideUnitZ * leftWidth
                let rightX = point.x - sideUnitX * rightWidth
                let rightZ = point.z - sideUnitZ * rightWidth
                let safeNormalY = max(abs(surfaceNormal.y), 0.18)
                let leftFallback = point.y
                    - (surfaceNormal.x * sideUnitX * leftWidth
                        + surfaceNormal.z * sideUnitZ * leftWidth) / safeNormalY
                let rightFallback = point.y
                    - (surfaceNormal.x * -sideUnitX * rightWidth
                        + surfaceNormal.z * -sideUnitZ * rightWidth) / safeNormalY

                vertices.append(SCNVector3(
                    leftX,
                    paintSurfaceHeight(
                        atX: leftX,
                        z: leftZ,
                        fallback: leftFallback,
                        terrainNode: terrainNode
                    ) + surfaceOffset,
                    leftZ
                ))
                vertices.append(SCNVector3(
                    rightX,
                    paintSurfaceHeight(
                        atX: rightX,
                        z: rightZ,
                        fallback: rightFallback,
                        terrainNode: terrainNode
                    ) + surfaceOffset,
                    rightZ
                ))
                normals.append(contentsOf: [surfaceNormal, surfaceNormal])

                // 島本体と同じ頂点色方式。緩やかな明暗差で面の密度を出し、単色の板に見せない。
                let tone = 0.97 + sin(Float(index) * 1.19 + seed * 0.61) * 0.045
                colors.append(UIColor.white.scaled(CGFloat(tone * 0.985)))
                colors.append(UIColor.white.scaled(CGFloat(tone * 1.015)))
                let progress = CGFloat(index) / CGFloat(max(projectedPoints.count - 1, 1))
                textureCoordinates.append(CGPoint(x: 0, y: progress))
                textureCoordinates.append(CGPoint(x: 1, y: progress))

                if index < projectedPoints.count - 1 {
                    let base = Int32(index * 2)
                    indices.append(contentsOf: [base, base + 2, base + 1, base + 1, base + 2, base + 3])
                }
            }

            let geometry = SCNGeometry(
                sources: [
                    SCNGeometrySource(vertices: vertices),
                    SCNGeometrySource(normals: normals),
                    paintColorSource(colors),
                    SCNGeometrySource(textureCoordinates: textureCoordinates),
                ],
                elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
            )
            geometry.firstMaterial = material
            let ribbon = SCNNode(geometry: geometry)
            ribbon.renderingOrder = 60
            container.addChildNode(ribbon)
        }

        let capPoints = projectedPoints.count == 1
            ? [(firstPoint, 0)]
            : [(firstPoint, 0), (projectedPoints.last ?? firstPoint, projectedPoints.count - 1)]
        for (point, index) in capPoints {
            let capNode = makePaintCap(
                point: point,
                pointIndex: index,
                points: projectedPoints,
                radius: halfWidth,
                surfaceOffset: surfaceOffset + 0.0005,
                seed: seed,
                paint: stroke.material,
                material: material,
                terrainNode: terrainNode
            )
            capNode.renderingOrder = 61
            container.addChildNode(capNode)
        }
        return container
    }

    private static func paintMaterial(for paint: AssetPaintMaterial) -> SCNMaterial {
        // 頂点色は微細な明暗だけを担当させ、基調色はマテリアル側に置く。
        // 急斜面でも黒潰れしない程度の弱い環境色を加え、素材色を判別しやすくする。
        let material = VoyageSceneKit.litMaterial(
            paint.color,
            roughness: 0.96,
            doubleSided: true,
            fogged: false
        )
        material.emission.contents = paint.color.scaled(0.26)
        return material
    }

    private static func makePaintCap(
        point: AssetPaintPoint,
        pointIndex: Int,
        points: [AssetPaintPoint],
        radius: Float,
        surfaceOffset: Float,
        seed: Float,
        paint: AssetPaintMaterial,
        material: SCNMaterial,
        terrainNode: SCNNode?
    ) -> SCNNode {
        let segments = 12
        let normal = paintSurfaceNormal(
            at: pointIndex,
            points: points,
            terrainNode: terrainNode
        )
        let centerY = paintSurfaceHeight(
            atX: point.x,
            z: point.z,
            fallback: point.y,
            terrainNode: terrainNode
        )
        var vertices = [SCNVector3(point.x, centerY + surfaceOffset, point.z)]
        var normals = [normal]
        var colors = [UIColor.white.scaled(1.025)]
        var indices: [Int32] = []

        for segment in 0..<segments {
            let angle = Float(segment) / Float(segments) * 2 * .pi
            let wobble = 1 + sin(Float(segment) * 2.31 + seed) * 0.048
            let dx = cos(angle) * radius * wobble
            let dz = sin(angle) * radius * wobble
            let safeNormalY = max(abs(normal.y), 0.18)
            let dy = -(normal.x * dx + normal.z * dz) / safeNormalY
            let x = point.x + dx
            let z = point.z + dz
            let y = paintSurfaceHeight(
                atX: x,
                z: z,
                fallback: point.y + dy,
                terrainNode: terrainNode
            )
            vertices.append(SCNVector3(x, y + surfaceOffset, z))
            normals.append(normal)
            let tone = 0.94 + sin(Float(segment) * 1.41 + seed * 0.7) * 0.035
            colors.append(UIColor.white.scaled(CGFloat(tone)))
        }

        for segment in 0..<segments {
            // XZ平面で上向きになる頂点順。
            let current = Int32(segment + 1)
            let next = Int32((segment + 1) % segments + 1)
            indices.append(contentsOf: [0, next, current])
        }

        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: vertices),
                SCNGeometrySource(normals: normals),
                paintColorSource(colors),
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        geometry.firstMaterial = material
        return SCNNode(geometry: geometry)
    }

    private static func paintSurfaceHeight(
        atX x: Float,
        z: Float,
        fallback: Float,
        terrainNode: SCNNode?
    ) -> Float {
        guard let terrainNode,
              let terrainHeight = terrainSurfaceHeight(on: terrainNode, atLocalX: x, z: z)
        else { return fallback }
        return terrainHeight
    }

    private static func paintSurfaceNormal(
        at index: Int,
        points: [AssetPaintPoint],
        terrainNode: SCNNode?
    ) -> SCNVector3 {
        let point = points[index]
        if let terrainNode,
           let sampledNormal = terrainSurfaceNormal(
               on: terrainNode,
               atLocalX: point.x,
               z: point.z
           ) {
            return sampledNormal
        }
        guard points.count > 1 else { return SCNVector3(0, 1, 0) }
        let previous = points[max(index - 1, 0)]
        let next = points[min(index + 1, points.count - 1)]
        let tangent = SCNVector3(next.x - previous.x, next.y - previous.y, next.z - previous.z)
        let horizontalLength = max(sqrt(tangent.x * tangent.x + tangent.z * tangent.z), 0.0001)
        let side = SCNVector3(-tangent.z / horizontalLength, 0, tangent.x / horizontalLength)
        let cross = SCNVector3(
            side.y * tangent.z - side.z * tangent.y,
            side.z * tangent.x - side.x * tangent.z,
            side.x * tangent.y - side.y * tangent.x
        )
        let length = max(sqrt(cross.x * cross.x + cross.y * cross.y + cross.z * cross.z), 0.0001)
        let direction: Float = cross.y < 0 ? -1 : 1
        return SCNVector3(
            cross.x / length * direction,
            cross.y / length * direction,
            cross.z / length * direction
        )
    }

    private static func paintColorSource(_ colors: [UIColor]) -> SCNGeometrySource {
        let values: [SIMD4<Float>] = colors.map { color in
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return SIMD4(Float(red), Float(green), Float(blue), Float(alpha))
        }
        let data = values.withUnsafeBytes { Data($0) }
        return SCNGeometrySource(
            data: data,
            semantic: .color,
            vectorCount: values.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD4<Float>>.stride
        )
    }

    private static func paintSeed(for id: UUID) -> Float {
        let stableValue = id.uuidString.utf8.reduce(UInt32(2_166_136_261)) { value, byte in
            (value ^ UInt32(byte)) &* 16_777_619
        }
        return Float(stableValue % 10_000) * 0.001
    }

    static func attachSavedPlacements(
        context: AssetPlacementContext,
        to parent: SCNNode,
        bundle: Bundle = .main
    ) {
        for placement in AssetPlacementPersistence.load() where placement.context == context {
            // v3の手動「スタジオ配置」はアクティブ世界へ移行済み。
            // 直接配置した木や小物だけを追加レイヤーとして復元する。
            if context == .destinationIsland,
               SavedAssetStudio.id(fromAssetID: placement.assetID) != nil {
                continue
            }
            guard let node = makeAssetNode(resourceName: placement.assetID, bundle: bundle) else { continue }
            node.name = "custom-asset-\(placement.id.uuidString)"
            placement.transform.apply(to: node)
            parent.addChildNode(node)
        }
        let terrainStrokes = AssetPlacementPersistence.loadTerrainStrokes().filter {
            $0.context == context
        }
        let terrain = makeTerrainNode(for: terrainStrokes)
        if let terrain {
            parent.addChildNode(terrain)
        }
        for stroke in AssetPlacementPersistence.loadPaintStrokes() where stroke.context == context {
            parent.addChildNode(makePaintNode(for: stroke, terrainNode: terrain))
        }
    }
}
