import SceneKit
import UIKit

/// A restrained base shadow supplements the broad directional shadow map.
/// One cached texture/geometry, no extra shadow pass or per-frame work.
enum HomeIslandContactShadow {
    private static let name = "home-island-contact-shadow"
    private static let baseFactors: [String: Float] = [
        "conifer_tree": 0.20, "palm_tree": 0.13, "small_stump": 0.52,
        "navigator_tent": 0.46, "weathered_cottage": 0.48,
        "small_lighthouse": 0.47, "weathered_lighthouse": 0.47,
        "stone_well": 0.48, "weathered_crate": 0.50, "supply_barrels": 0.46,
        "garden_fountain": 0.47, "garden_bird_bath": 0.24,
        "garden_sundial": 0.30, "garden_urn_planter": 0.35,
        "garden_topiary_cone": 0.28, "garden_boulder": 0.47,
        "garden_outcrop": 0.45, "log_stool": 0.48, "wooden_bookshelf": 0.47,
    ]
    private static let geometry: SCNPlane = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let texture = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128), format: format).image { renderer in
            let colors = [UIColor(white: 0, alpha: 0.20).cgColor,
                          UIColor(white: 0, alpha: 0.12).cgColor,
                          UIColor.clear.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1])!
            renderer.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                                                  endCenter: CGPoint(x: 64, y: 64), endRadius: 62, options: [])
        }
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = texture
        material.diffuse.mipFilter = .linear
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.isDoubleSided = false
        let plane = SCNPlane(width: 2, height: 2)
        plane.materials = [material]
        return plane
    }()

    static func install(on prop: SCNNode, assetID: String) {
        guard let factor = baseFactors[assetID],
              prop.childNode(withName: name, recursively: false) == nil else { return }
        let (minimum, maximum) = prop.boundingBox
        let width = Float(maximum.x - minimum.x)
        let depth = Float(maximum.z - minimum.z)
        guard width > 0, depth > 0 else { return }
        let shadow = SCNNode(geometry: geometry)
        shadow.name = name
        shadow.categoryBitMask = 0
        shadow.castsShadow = false
        shadow.eulerAngles.x = -.pi / 2
        shadow.position.x = (minimum.x + maximum.x) / 2
        shadow.position.z = (minimum.z + maximum.z) / 2
        shadow.scale = SCNVector3(width * factor, depth * factor, 1)
        prop.addChildNode(shadow)
    }

    static func update(on prop: SCNNode, groundY: Float) {
        guard let shadow = prop.childNode(withName: name, recursively: false) else { return }
        // The sand overlay sits 18 mm above the authored foundation. Keep the
        // decal above it at every prop scale and hide it on raised furniture.
        shadow.isHidden = abs(prop.position.y - groundY) > 0.01
        shadow.position.y = 0.023 / max(prop.scale.y, 0.001)
    }
}
