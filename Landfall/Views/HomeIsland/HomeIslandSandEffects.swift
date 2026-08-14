import SceneKit
import UIKit

/// Gives the home island one continuous, physically based sand surface instead
/// of a collection of flat beige materials. The texture is generated locally
/// and deterministically, so it remains sharp without adding a large asset to
/// the app bundle or depending on the network.
enum HomeIslandSandSurface {
    private struct TextureSet {
        let color: UIImage
        let normal: UIImage
        let roughness: UIImage
        let occlusion: UIImage
    }

    private static let textures: TextureSet? = {
        guard let color = UIImage(named: "home_island_sand_albedo"),
              let normal = UIImage(named: "home_island_sand_normal"),
              let roughness = UIImage(named: "home_island_sand_roughness"),
              let occlusion = UIImage(named: "home_island_sand_occlusion")
        else { return nil }
        return TextureSet(
            color: color,
            normal: normal,
            roughness: roughness,
            occlusion: occlusion
        )
    }()

    static func apply(to foundation: SCNNode) {
        guard let textures else { return }
        unifyCliffMaterials(in: foundation)
        let material = SCNMaterial()
        material.name = "home-island-pristine-sand"
        material.lightingModel = .physicallyBased
        material.diffuse.contents = textures.color
        configure(material.diffuse)
        material.normal.contents = textures.normal
        material.normal.intensity = 0.42
        configure(material.normal)
        material.roughness.contents = textures.roughness
        material.roughness.intensity = 1
        configure(material.roughness)
        material.ambientOcclusion.contents = textures.occlusion
        material.ambientOcclusion.intensity = 0.22
        configure(material.ambientOcclusion)
        material.metalness.contents = UIColor.black
        material.emission.contents = textures.color
        material.emission.intensity = 0.38
        material.isDoubleSided = true
        material.locksAmbientWithDiffuse = false

        let surface = makeSurfaceNode()
        surface.geometry?.firstMaterial = material
        foundation.addChildNode(surface)
    }

    private static func unifyCliffMaterials(in foundation: SCNNode) {
        foundation.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }
            geometry.materials = geometry.materials.map { source in
                let name = source.name ?? ""
                guard name.hasPrefix("LF_HomeSand") else { return source }
                let material = SCNMaterial()
                material.name = "home-island-clean-sand-edge"
                material.lightingModel = .constant
                material.diffuse.contents = UIColor(
                    red: 0.88,
                    green: 0.85,
                    blue: 0.78,
                    alpha: 1
                )
                material.isDoubleSided = true
                return material
            }
        }
    }

    private static func configure(_ property: SCNMaterialProperty) {
        property.wrapS = .clamp
        property.wrapT = .clamp
        property.minificationFilter = .linear
        property.magnificationFilter = .linear
        property.mipFilter = .linear
        property.maxAnisotropy = 8
    }

    /// A single uninterrupted top layer hides the old patchwork while keeping
    /// the authored sandstone cliff visible around the side of the island.
    private static func makeSurfaceNode() -> SCNNode {
        let segments = 128
        let textureExtentX: Float = 14
        let textureExtentZ: Float = 10
        let y = HomeIslandMetrics.surfaceY + 0.018
        var vertices = [SCNVector3(0, y, 0)]
        var normals = [SCNVector3(0, 1, 0)]
        var coordinates = [CGPoint(x: 0.5, y: 0.5)]

        for index in 0..<segments {
            let angle = Float.pi * 2 * Float(index) / Float(segments)
            let edge = HomeIslandMetrics.sandEdgePoint(angle: angle)
            let x = edge.x
            let z = edge.z
            vertices.append(SCNVector3(x, y, z))
            normals.append(SCNVector3(0, 1, 0))
            coordinates.append(CGPoint(
                x: CGFloat(x / (textureExtentX * 2) + 0.5),
                y: CGFloat(z / (textureExtentZ * 2) + 0.5)
            ))
        }

        var indices: [Int32] = []
        indices.reserveCapacity(segments * 3)
        for index in 0..<segments {
            indices.append(0)
            indices.append(Int32(index + 1))
            indices.append(Int32((index + 1) % segments + 1))
        }
        let tangentValues = [Float](
            repeating: 0,
            count: vertices.count * 4
        ).enumerated().map { offset, value -> Float in
            switch offset % 4 {
            case 0, 3: 1
            default: value
            }
        }
        let tangentData = tangentValues.withUnsafeBytes { Data($0) }
        let tangentSource = SCNGeometrySource(
            data: tangentData,
            semantic: .tangent,
            vectorCount: vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 4
        )
        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: vertices),
                SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: coordinates),
                tangentSource,
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        geometry.name = "home-island-pristine-sand-surface"
        let node = SCNNode(geometry: geometry)
        node.name = "home-island-pristine-sand-surface"
        node.castsShadow = false
        return node
    }

}

/// A compact boot-print pressed into the surface as real SceneKit geometry.
/// Using a shallow bevel instead of a flat sprite keeps the mark readable under
/// the island's moving camera and directional lighting.
enum HomeIslandFootprintVisual {
    static func prewarm() {}

    static func makeNode(leftFoot: Bool) -> SCNNode {
        let container = SCNNode()
        container.name = leftFoot ? "sand-footprint-left" : "sand-footprint-right"

        let rim = footprintShape(scale: 1.13)
        rim.geometry?.firstMaterial = material(
            color: UIColor(red: 0.86, green: 0.73, blue: 0.50, alpha: 0.25),
            constant: true
        )
        rim.position.y = 0.001
        container.addChildNode(rim)

        let impression = footprintShape(scale: 1)
        impression.geometry?.firstMaterial = material(
            color: UIColor(red: 0.36, green: 0.27, blue: 0.16, alpha: 0.58),
            constant: false
        )
        impression.position.y = 0.003
        container.addChildNode(impression)

        let treadMaterial = material(
            color: UIColor(red: 0.23, green: 0.15, blue: 0.08, alpha: 0.50),
            constant: true
        )
        for z in [-0.105, -0.035, 0.045, 0.112] as [Float] {
            let tread = SCNBox(width: 0.125, height: 0.002, length: 0.022, chamferRadius: 0.006)
            tread.firstMaterial = treadMaterial
            let treadNode = SCNNode(geometry: tread)
            treadNode.position = SCNVector3(
                z == -0.035 || z == 0.112 ? 0.012 : -0.012,
                0.006,
                z
            )
            treadNode.renderingOrder = 92
            container.addChildNode(treadNode)
        }
        if leftFoot { container.scale.x = -1 }
        return container
    }

    private static func footprintShape(scale: CGFloat) -> SCNNode {
        let sole = UIBezierPath()
        sole.append(UIBezierPath(
            roundedRect: CGRect(x: -0.082, y: -0.155, width: 0.164, height: 0.132),
            cornerRadius: 0.055
        ))
        sole.append(UIBezierPath(
            roundedRect: CGRect(x: -0.067, y: -0.050, width: 0.134, height: 0.125),
            cornerRadius: 0.045
        ))
        sole.append(UIBezierPath(
            ovalIn: CGRect(x: -0.098, y: 0.035, width: 0.196, height: 0.165)
        ))
        sole.apply(CGAffineTransform(scaleX: scale, y: scale))
        let shape = SCNShape(path: sole, extrusionDepth: 0.003)
        shape.chamferRadius = 0.004
        shape.chamferMode = .both
        let node = SCNNode(geometry: shape)
        node.eulerAngles.x = -.pi / 2
        node.renderingOrder = 91
        return node
    }

    private static func material(color: UIColor, constant: Bool) -> SCNMaterial {
        let material = SCNMaterial()
        material.name = "home-island-footprint-material"
        material.lightingModel = constant ? .constant : .physicallyBased
        material.diffuse.contents = color
        material.roughness.contents = 1
        material.metalness.contents = 0
        material.blendMode = .alpha
        material.transparencyMode = .aOne
        material.isDoubleSided = true
        material.readsFromDepthBuffer = true
        material.writesToDepthBuffer = false
        return material
    }
}
