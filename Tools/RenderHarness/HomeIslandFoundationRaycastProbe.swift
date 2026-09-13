import Foundation
import SceneKit

@main
enum FoundationRaycastProbe {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let scene = SCNScene()
        let foundation = try SCNScene(url: directory.appendingPathComponent("home_island_foundation.usdz")).rootNode.clone()
        scene.rootNode.addChildNode(foundation)
        let resources = ["weathered_cottage", "weathered_lighthouse", "wooden_jetty", "stone_well", "weathered_crate"]
        for index in 0..<65 {
            let node = try SCNScene(url: directory.appendingPathComponent(resources[index % resources.count] + ".usdz")).rootNode.clone()
            node.position = SCNVector3(Float(index % 9) - 4, 0.62, Float(index / 9) - 3)
            scene.rootNode.addChildNode(node)
        }
        func old(_ x: Float, _ z: Float) -> SCNHitTestResult? {
            scene.rootNode.hitTestWithSegment(from: SCNVector3(x, 30, z), to: SCNVector3(x, -10, z), options: [
                SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.all.rawValue,
                SCNHitTestOption.backFaceCulling.rawValue: false,
            ]).first { hit in
                var node: SCNNode? = hit.node
                while let current = node {
                    if current === foundation { return true }
                    node = current.parent
                }
                return false
            }
        }
        let points: [(Float, Float)] = (-6...6).flatMap { x in (-4...4).map { (Float(x), Float($0)) } }
        for scale: Float in [0.8, 1, 1.6] {
            foundation.scale = SCNVector3(scale, 1, scale)
            for (x, z) in points {
                let a = old(x, z)
                let b = HomeIslandFoundationRaycast.sample(in: foundation, worldRoot: scene.rootNode, x: x, z: z)
                precondition((a == nil) == (b == nil), "hit parity")
                if let a, let b {
                    precondition(abs(a.worldCoordinates.y - b.worldCoordinates.y) < 0.0001, "height parity")
                    precondition(simd_length(a.simdWorldNormal - b.simdWorldNormal) < 0.0001, "normal parity")
                }
            }
        }
        foundation.scale = SCNVector3(1, 1, 1)
        func measure(_ body: (Float, Float) -> SCNHitTestResult?) -> Double {
            let start = CFAbsoluteTimeGetCurrent()
            for _ in 0..<12 { for (x, z) in points { _ = body(x, z) } }
            return (CFAbsoluteTimeGetCurrent() - start) * 1000
        }
        _ = measure(old)
        _ = measure { HomeIslandFoundationRaycast.sample(in: foundation, worldRoot: scene.rootNode, x: $0, z: $1) }
        let before = measure(old)
        let after = measure { HomeIslandFoundationRaycast.sample(in: foundation, worldRoot: scene.rootNode, x: $0, z: $1) }
        print(String(format: "65 props, 1404 ground queries: full scene %.2f ms → foundation %.2f ms (%.2fx). Height/normal parity at 351 points: PASS", before, after, before / after))
    }
}
