import Foundation

/// A small magnetic zone around nearby centre lines; no island-wide grid.
/// Validation belongs to the caller so coast and reserved-area rules stay shared.
enum HomeIslandPlacementSnap {
    struct Pose: Equatable {
        var x: Float
        var z: Float
        var yaw: Float
    }

    struct Neighbor {
        var id: UUID
        var assetID: String
        var pose: Pose
    }

    struct Guide: Equatable {
        var from: SIMD2<Float>
        var to: SIMD2<Float>
    }

    struct Result {
        var pose: Pose
        var guides: [Guide]
    }

    static let distanceThreshold: Float = 0.18
    static let neighborRange: Float = 4

    static func resolve(
        _ proposed: Pose,
        assetID: String,
        excluding id: UUID? = nil,
        neighbors: [Neighbor],
        enabled: Bool,
        isValid: (Pose) -> Bool
    ) -> Result {
        let unchanged = Result(pose: proposed, guides: [])
        guard enabled, assetID != "wooden_jetty",
              proposed.x.isFinite, proposed.z.isFinite, proposed.yaw.isFinite
        else { return unchanged }
        let nearby = neighbors.filter {
            let distance = hypot($0.pose.x - proposed.x, $0.pose.z - proposed.z)
            // Avoid pulling two anchors onto one another. Intentional overlap
            // remains available through the normal unsnapped move.
            return $0.id != id && distance >= 0.55 && distance <= neighborRange
                && $0.pose.yaw.isFinite && $0.assetID != "wooden_jetty"
        }.sorted {
            let a = hypot($0.pose.x - proposed.x, $0.pose.z - proposed.z)
            let b = hypot($1.pose.x - proposed.x, $1.pose.z - proposed.z)
            return a == b ? $0.id.uuidString < $1.id.uuidString : a < b
        }
        var pose = proposed
        var anchors: [(Neighbor, Bool)] = []
        for xAxis in [true, false] {
            let candidate = nearby.filter {
                abs(xAxis ? $0.pose.x - proposed.x : $0.pose.z - proposed.z) <= distanceThreshold
            }.min {
                abs(xAxis ? $0.pose.x - proposed.x : $0.pose.z - proposed.z)
                    < abs(xAxis ? $1.pose.x - proposed.x : $1.pose.z - proposed.z)
            }
            if let candidate {
                var aligned = pose
                if xAxis { aligned.x = candidate.pose.x } else { aligned.z = candidate.pose.z }
                if isValid(aligned) {
                    pose = aligned
                    anchors.append((candidate, xAxis))
                }
            }
        }
        if let family = alignmentFamily(assetID),
           let neighbor = nearby.first(where: { alignmentFamily($0.assetID) == family }) {
            let difference = atan2(sin(neighbor.pose.yaw - pose.yaw), cos(neighbor.pose.yaw - pose.yaw))
            if abs(difference) <= .pi / 12 {
                var aligned = pose
                aligned.yaw = neighbor.pose.yaw
                if isValid(aligned) { pose = aligned }
            }
        }
        return Result(pose: pose, guides: anchors.map { neighbor, xAxis in
            Guide(
                from: SIMD2(pose.x, pose.z),
                to: xAxis ? SIMD2(pose.x, neighbor.pose.z) : SIMD2(neighbor.pose.x, pose.z)
            )
        })
    }

    private static func alignmentFamily(_ assetID: String) -> String? {
        if assetID.hasPrefix("stone_path_") { return "stone-path" }
        if assetID.hasPrefix("wooden_fence") { return "wooden-fence" }
        if assetID == "garden_iron_fence" || assetID == "garden_iron_gate" { return "garden-iron" }
        return nil
    }
}
