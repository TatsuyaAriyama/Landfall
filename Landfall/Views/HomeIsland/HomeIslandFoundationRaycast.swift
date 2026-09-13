import SceneKit

/// Ground queries must not traverse every placed prop, visitor and effect.
/// Segment endpoints are local to the receiver; hits still report world space.
enum HomeIslandFoundationRaycast {
    static func sample(in foundation: SCNNode, worldRoot: SCNNode, x: Float, z: Float) -> SCNHitTestResult? {
        let from = foundation.convertPosition(SCNVector3(x, 30, z), from: worldRoot)
        let to = foundation.convertPosition(SCNVector3(x, -10, z), from: worldRoot)
        return foundation.hitTestWithSegment(from: from, to: to, options: [
            SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.all.rawValue,
            SCNHitTestOption.backFaceCulling.rawValue: false,
        ]).first
    }
}
