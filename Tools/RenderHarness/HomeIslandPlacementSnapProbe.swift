import Foundation

@main
private enum HomeIslandPlacementSnapProbe {
    typealias Snap = HomeIslandPlacementSnap

    static func main() {
        let id = UUID()
        let neighbor = Snap.Neighbor(id: id, assetID: "stone_path_straight",
                                     pose: .init(x: 0, z: 2, yaw: 0.12))
        let source = Snap.Pose(x: 0.14, z: 0, yaw: 0)
        func resolve(_ pose: Snap.Pose = source, asset: String = "stone_path_curve",
                     neighbors: [Snap.Neighbor] = [neighbor], enabled: Bool = true,
                     excluding: UUID? = nil, valid: (Snap.Pose) -> Bool = { _ in true }) -> Snap.Result {
            Snap.resolve(pose, assetID: asset, excluding: excluding, neighbors: neighbors,
                         enabled: enabled, isValid: valid)
        }

        let disabled = resolve(enabled: false, valid: { _ in fatalError("Disabled snap consulted validation") })
        precondition(disabled.pose == source && disabled.guides.isEmpty)
        let aligned = resolve()
        precondition(aligned.pose.x == 0 && aligned.pose.z == 0 && aligned.pose.yaw == 0.12)
        precondition(aligned.guides.count == 1 && aligned.guides[0].to == SIMD2(0, 2))
        precondition(resolve(.init(x: 0.181, z: 0, yaw: 0)).pose.x == 0.181,
                     "A distant pointer stayed stuck to an alignment")
        precondition(resolve(.init(x: 0.18, z: 0, yaw: 0)).pose.x == 0,
                     "The advertised distance boundary stopped aligning")
        precondition(resolve(excluding: id).pose == source, "Selection aligned against itself")
        precondition(resolve(valid: { _ in false }).pose == source,
                     "A rejected coast/reserved-area pose reached the preview")
        precondition(resolve(asset: "wooden_jetty").pose == source,
                     "Assistance overrode the jetty's coastline placement rule")

        let zNeighbor = Snap.Neighbor(id: UUID(), assetID: "palm_tree",
                                      pose: .init(x: 2, z: 0.10, yaw: 0.9))
        let twoAxes = resolve(neighbors: [neighbor, zNeighbor])
        precondition(twoAxes.pose.x == 0 && twoAxes.pose.z == 0.1 && twoAxes.guides.count == 2)
        let partiallyBlocked = resolve(neighbors: [neighbor, zNeighbor], valid: { $0.z == 0 })
        precondition(partiallyBlocked.pose.x == 0 && partiallyBlocked.pose.z == 0,
                     "A blocked second axis discarded an independently valid alignment")
        precondition(partiallyBlocked.guides.count == 1)

        precondition(resolve(asset: "palm_tree").pose.yaw == source.yaw,
                     "A natural prop lost its authored random facing")
        precondition(resolve(.init(x: 0.14, z: 0, yaw: .pi / 2)).pose.yaw == .pi / 2,
                     "Facing alignment overwrote a deliberate quarter-turn")
        let far = Snap.Neighbor(id: UUID(), assetID: neighbor.assetID, pose: .init(x: 0, z: 5, yaw: 0))
        precondition(resolve(neighbors: [far]).pose == source, "Far scenery attracted the prop")
        let overlapping = Snap.Neighbor(id: UUID(), assetID: neighbor.assetID,
                                        pose: .init(x: 0.1, z: 0.1, yaw: 0))
        precondition(resolve(neighbors: [overlapping]).pose == source,
                     "Alignment stacked nearby anchors on each other")
        let jetty = Snap.Neighbor(id: UUID(), assetID: "wooden_jetty", pose: neighbor.pose)
        precondition(resolve(neighbors: [jetty]).pose == source, "A jetty attracted another prop")
        print("PASS placement assistance: opt-in, thresholds, axis guides, release, self exclusion, validation, families, jetty protection")
    }
}
