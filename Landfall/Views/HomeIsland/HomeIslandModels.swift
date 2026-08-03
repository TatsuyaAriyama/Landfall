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
    static let buildableRadiusX: Float = 11.10
    static let buildableRadiusZ: Float = 7.44
    static let maximumPlacements = 120

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
}

struct HomeIslandAsset: Identifiable, Hashable {
    let id: String
    let title: String
    let symbolName: String
    let defaultScale: Float
    let footprintMargin: Float
    let unlockLevel: Int
}

enum HomeIslandAssetCatalog {
    /// Only these operator-approved assets can enter player-authored islands.
    /// Keeping this allowlist independent from 3D Studio prevents developer or
    /// terrain tools from leaking into the consumer placement experience.
    static let approved: [HomeIslandAsset] = [
        HomeIslandAsset(
            id: "small_tree",
            title: String(localized: "Small Tree"),
            symbolName: "tree.fill",
            defaultScale: 0.92,
            footprintMargin: 0.38,
            unlockLevel: 2
        ),
        HomeIslandAsset(
            id: "windswept_tree",
            title: String(localized: "Windswept Tree"),
            symbolName: "tree.fill",
            defaultScale: 0.86,
            footprintMargin: 0.56,
            unlockLevel: 2
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

    static func footprintMargin(assetID: String, scale: Float) -> Float {
        guard let asset = asset(id: assetID) else { return 0 }
        return asset.footprintMargin
            * max(scale, 0.05)
            / max(asset.defaultScale, 0.05)
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

    private static func sanitized(_ placements: [HomeIslandPlacement]) -> [HomeIslandPlacement] {
        placements
            .filter { HomeIslandAssetCatalog.approvedIDs.contains($0.assetID) }
            .prefix(HomeIslandMetrics.maximumPlacements)
            .map { placement in
                var copy = placement
                copy.transform.scale = min(2, max(0.25, copy.transform.scale))
                let margin = HomeIslandAssetCatalog.footprintMargin(
                    assetID: copy.assetID,
                    scale: copy.transform.scale
                )
                let position = HomeIslandMetrics.clampedPosition(
                    x: copy.transform.x,
                    z: copy.transform.z,
                    footprintMargin: margin
                )
                copy.transform.x = position.x
                copy.transform.z = position.z
                return copy
            }
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
    private let maximumUndoDepth = 60

    let ownerKey: String

    init(ownerID: String) {
        ownerKey = HomeIslandPersistence.ownerKey(for: ownerID)
        let snapshot = HomeIslandPersistence.load(ownerKey: ownerKey)
        placements = snapshot.placements
        lastSavedAt = snapshot.updatedAt == .distantPast ? nil : snapshot.updatedAt
    }

    var selectedPlacement: HomeIslandPlacement? {
        guard let selectedID else { return nil }
        return placements.first { $0.id == selectedID }
    }

    var canAdd: Bool { placements.count < HomeIslandMetrics.maximumPlacements }
    var canUndo: Bool { !undoStack.isEmpty }

    func select(_ id: UUID?) {
        selectedID = id.flatMap { candidate in
            placements.contains(where: { $0.id == candidate }) ? candidate : nil
        }
    }

    @discardableResult
    func add(assetID: String, x: Float, z: Float, playerLevel: Int) -> UUID? {
        guard canAdd,
              let asset = HomeIslandAssetCatalog.asset(id: assetID),
              playerLevel >= asset.unlockLevel
        else { return nil }
        let previous = editState
        let position = HomeIslandMetrics.clampedPosition(
            x: x,
            z: z,
            footprintMargin: asset.footprintMargin
        )
        let placement = HomeIslandPlacement(
            id: UUID(),
            assetID: assetID,
            transform: HomeIslandTransform(
                x: position.x,
                z: position.z,
                yaw: Float(placements.count % 8) * (.pi / 4),
                scale: asset.defaultScale
            )
        )
        placements.append(placement)
        selectedID = placement.id
        finishEdit(from: previous)
        return placement.id
    }

    func moveSelected(x: Float, z: Float) {
        guard let selectedID,
              let index = placements.firstIndex(where: { $0.id == selectedID })
        else { return }
        let previous = editState
        let margin = HomeIslandAssetCatalog.footprintMargin(
            assetID: placements[index].assetID,
            scale: placements[index].transform.scale
        )
        let position = HomeIslandMetrics.clampedPosition(
            x: x,
            z: z,
            footprintMargin: margin
        )
        placements[index].transform.x = position.x
        placements[index].transform.z = position.z
        finishEdit(from: previous)
    }

    func rotateSelected(by radians: Float = .pi / 4) {
        guard let selectedID,
              let index = placements.firstIndex(where: { $0.id == selectedID })
        else { return }
        let previous = editState
        placements[index].transform.yaw += radians
        finishEdit(from: previous)
    }

    func resizeSelected(by delta: Float) {
        guard let selectedID,
              let index = placements.firstIndex(where: { $0.id == selectedID })
        else { return }
        let previous = editState
        let scale = min(2, max(0.25, placements[index].transform.scale + delta))
        placements[index].transform.scale = scale
        let margin = HomeIslandAssetCatalog.footprintMargin(
            assetID: placements[index].assetID,
            scale: scale
        )
        let position = HomeIslandMetrics.clampedPosition(
            x: placements[index].transform.x,
            z: placements[index].transform.z,
            footprintMargin: margin
        )
        placements[index].transform.x = position.x
        placements[index].transform.z = position.z
        finishEdit(from: previous)
    }

    @discardableResult
    func duplicateSelected(playerLevel: Int) -> UUID? {
        guard canAdd,
              let selected = selectedPlacement,
              let asset = HomeIslandAssetCatalog.asset(id: selected.assetID),
              playerLevel >= asset.unlockLevel
        else { return nil }
        let previous = editState
        var copy = selected
        copy.id = UUID()
        let margin = HomeIslandAssetCatalog.footprintMargin(
            assetID: selected.assetID,
            scale: selected.transform.scale
        )
        let position = HomeIslandMetrics.clampedPosition(
            x: selected.transform.x + 0.62,
            z: selected.transform.z + 0.42,
            footprintMargin: margin
        )
        copy.transform.x = position.x
        copy.transform.z = position.z
        copy.transform.yaw += .pi / 8
        placements.append(copy)
        selectedID = copy.id
        finishEdit(from: previous)
        return copy.id
    }

    func deleteSelected() {
        guard let selectedID else { return }
        let previous = editState
        placements.removeAll { $0.id == selectedID }
        self.selectedID = nil
        finishEdit(from: previous)
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        placements = previous.placements
        selectedID = previous.selectedID.flatMap { restoredID in
            placements.contains(where: { $0.id == restoredID }) ? restoredID : nil
        }
        save()
    }

    private var editState: EditState {
        EditState(placements: placements, selectedID: selectedID)
    }

    private func finishEdit(from previous: EditState) {
        guard placements != previous.placements || selectedID != previous.selectedID else { return }
        undoStack.append(previous)
        if undoStack.count > maximumUndoDepth {
            undoStack.removeFirst(undoStack.count - maximumUndoDepth)
        }
        save()
    }

    func save() {
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
