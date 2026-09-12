import Foundation
import SceneKit
import simd

// Run with the shared helper and optionally the production lighthouse USDZ:
// swiftc Landfall/Views/AssetStudio/LighthouseBeaconAnimation.swift \
//   Tools/RenderHarness/LighthouseBeaconPivotProbe.swift -o /tmp/lighthouse-pivot-probe
// /tmp/lighthouse-pivot-probe Landfall/Resources/weathered_lighthouse.usdz
@main
private enum LighthouseBeaconPivotProbe {
    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    private static func requireNear(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ message: String) {
        require(simd_distance(a, b) < 0.0005, message)
    }

    private static func verify(_ lighthouse: SCNNode, label: String) {
        let scene = SCNScene()
        let parent = SCNNode()
        parent.simdPosition = SIMD3(7, -2, 3)
        parent.simdEulerAngles = SIMD3(0.13, 0.71, -0.09)
        parent.simdScale = SIMD3(1.2, 0.9, 1.3)
        scene.rootNode.addChildNode(parent)
        lighthouse.simdPosition = SIMD3(-4, 1, 2)
        lighthouse.simdEulerAngles.y = -0.42
        lighthouse.simdScale = SIMD3(repeating: 1.35)
        parent.addChildNode(lighthouse)

        guard let lens = lighthouse.childNode(withName: "LF_LighthouseBeaconRotor_Mesh", recursively: true)
            ?? lighthouse.childNode(withName: "LF_LighthouseBeaconRotor", recursively: true)
        else { preconditionFailure("Missing lighthouse lens: \(label)") }
        let bounds = lens.boundingBox
        let minimum = SIMD3<Float>(Float(bounds.min.x), Float(bounds.min.y), Float(bounds.min.z))
        let maximum = SIMD3<Float>(Float(bounds.max.x), Float(bounds.max.y), Float(bounds.max.z))
        let centre = (minimum + maximum) * 0.5
        let worldBefore = lens.simdWorldTransform
        let centreBefore = lens.simdConvertPosition(centre, to: nil)
        let edgeBefore = lens.simdConvertPosition(maximum, to: nil)
        // Simulate a clone that still carries the former mesh-local action.
        lens.runAction(.repeatForever(.rotateBy(x: 0, y: 6.28, z: 0, duration: 8)))

        guard let pivot = LighthouseBeaconAnimation.rotationPivot(in: lighthouse)
        else { preconditionFailure("Missing pivot: \(label)") }
        require(pivot.parent === lighthouse, "Pivot escaped the placement root")
        require(lens.parent === pivot, "Lens did not move under its pivot")
        require(!lens.hasActions, "Legacy mesh rotation survived")
        for column in 0..<4 {
            require(simd_length(worldBefore[column] - lens.simdWorldTransform[column]) < 0.0005,
                    "Reparenting changed the imported world transform")
        }
        requireNear(lens.simdConvertPosition(centre, to: nil), centreBefore, "Lens centre moved")
        requireNear(lens.simdConvertPosition(maximum, to: nil), edgeBefore, "Imported axes or scale changed")
        requireNear(pivot.simdWorldPosition, centreBefore, "Pivot missed the lens centre")
        require(LighthouseBeaconAnimation.rotationPivot(in: lighthouse) === pivot,
                "A second caller nested another pivot")

        let pivotCentre = pivot.simdPosition
        let lensEdge = lens.simdConvertPosition(maximum, to: lighthouse) - pivotCentre
        for step in 0...32 {
            pivot.simdEulerAngles.y = Float(step) * .pi / 16
            requireNear(lens.simdConvertPosition(centre, to: nil), centreBefore,
                        "Lens orbited outside its lantern room")
            let rotatedEdge = lens.simdConvertPosition(maximum, to: lighthouse) - pivotCentre
            require(abs(rotatedEdge.y - lensEdge.y) < 0.0005, "Lens turned on an imported sideways axis")
            require(abs(simd_length(rotatedEdge) - simd_length(lensEdge)) < 0.0005,
                    "Lens deformed while turning")
        }

        pivot.runAction(.repeatForever(.rotateBy(x: 0, y: 6.28, z: 0, duration: 8)),
                        forKey: LighthouseBeaconAnimation.rotationActionKey)
        pivot.removeAction(forKey: LighthouseBeaconAnimation.rotationActionKey)
        require(!pivot.hasActions, "Prologue could not stop the runtime clock")
        lighthouse.simdPosition += SIMD3(3, 0, -2)
        requireNear(lens.simdConvertPosition(centre, to: nil), pivot.simdWorldPosition,
                    "Moving the placement detached its lens")
        print("PASS \(label): world transform, centre, upright rotation, reuse, action handoff, placement movement")
    }

    static func main() throws {
        let lighthouse = SCNNode()
        let importedParent = SCNNode()
        importedParent.simdEulerAngles.x = -.pi / 2
        importedParent.simdPosition = SIMD3(0.2, 0.3, -0.1)
        importedParent.simdScale = SIMD3(0.9, 1.1, 1.2)
        lighthouse.addChildNode(importedParent)
        let lens = SCNNode(geometry: SCNBox(width: 0.8, height: 0.2, length: 0.5, chamferRadius: 0))
        lens.name = "LF_LighthouseBeaconRotor_Mesh"
        lens.simdPosition = SIMD3(0, 0, 5.3)
        lens.simdEulerAngles.z = 0.23
        importedParent.addChildNode(lens)
        verify(lighthouse, label: "transformed synthetic asset")

        if let path = CommandLine.arguments.dropFirst().first {
            let asset = try SCNScene(url: URL(fileURLWithPath: path), options: nil)
            let root = SCNNode()
            for child in asset.rootNode.childNodes { root.addChildNode(child) }
            verify(root, label: "production USDZ")
        }
    }
}
