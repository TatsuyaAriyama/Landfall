import SceneKit
import simd

/// Keeps the imported lens's axis conversion intact while turning it around
/// its own centre, on the placement root's upright axis.
enum LighthouseBeaconAnimation {
    static let pivotName = "lighthouse-beacon-rotation-pivot"
    static let rotationActionKey = "lighthouse-beacon-turn"

    static func rotationPivot(in lighthouse: SCNNode) -> SCNNode? {
        if let existing = lighthouse.childNode(withName: pivotName, recursively: false) {
            return existing
        }
        guard let lens = lighthouse.childNode(
            withName: "LF_LighthouseBeaconRotor_Mesh", recursively: true
        ) ?? lighthouse.childNode(
            withName: "LF_LighthouseBeaconRotor", recursively: true
        ) else { return nil }

        let bounds = lens.boundingBox
        let centre = SCNVector3(
            (bounds.min.x + bounds.max.x) * 0.5,
            (bounds.min.y + bounds.max.y) * 0.5,
            (bounds.min.z + bounds.max.z) * 0.5
        )
        let pivot = SCNNode()
        pivot.name = pivotName
        pivot.position = lens.convertPosition(centre, to: lighthouse)
        let originalWorldTransform = lens.simdWorldTransform
        // A legacy action on the mesh would still rotate its imported axes
        // inside the new pivot, making the lamp leave the lantern room.
        lens.removeAllActions()
        lighthouse.addChildNode(pivot)
        lens.removeFromParentNode()
        pivot.addChildNode(lens)
        lens.simdWorldTransform = originalWorldTransform
        return pivot
    }
}
