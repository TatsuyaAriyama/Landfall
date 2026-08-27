import OSLog
import SceneKit
import SwiftUI
import UIKit

// 目的地の夜の海(実3D / SceneKit)。Web版 VoyageScene / BoatModel / SeaParts の忠実移植。
// ジオメトリ・配置・配色・アニメの定数は web/src/three/*.tsx と同値に保つ。
// 低ポリ+flatShading・グラデ無し・影無しの世界観。

extension UIColor {
    /// 0xRRGGBB から UIColor(SceneKit用。トレイトに依存しない固定色)。
    convenience init(rgb: UInt) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    /// 明度をk倍した色(Webの deck = hull*0.72 相当)。
    func scaled(_ k: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * k, green: g * k, blue: b * k, alpha: a)
    }
}

/// 3D の航路に置くステップ1つ分。達成の有無と、いつ辿り着いたか。
/// SwiftData のモデルに依存させず、シーン生成に必要な最小限だけを持つ。
struct VoyageStep: Equatable {
    var doneAt: Date?
    var done: Bool { doneAt != nil }
}

enum VoyageSceneKit {
    // 配色(web/src/three と同値)
    static let nightBG = UIColor(rgb: 0x123830)   // NIGHT_BG
    static let seaBase = UIColor(rgb: 0x1E5348)   // SEA_COLOR
    static let seaDeep = nightBG
    static let sand = UIColor(rgb: 0xEADEBD)      // SAND(帆・島・月光)
    static let coral = UIColor(rgb: 0xF0997B)     // CORAL(船上アクセント)
    static let beach = UIColor(rgb: 0xDCCFA9)     // BEACH(浜)
    static let wood = UIColor(rgb: 0x5A2A15)      // WOOD(マスト・ブーム)
    static let ember = UIColor(rgb: 0xF3C065)     // 点灯ブイ
    static let buoyDim = UIColor(rgb: 0x4A3A2A)   // 未達ブイ
    static let returnOrange = UIColor(rgb: 0xF5822A) // 帰帆色(制覇の旗・達成日)

    // 航路(Web VoyageScene と同値)。ステップの島は「そう簡単には届かない目標」なので、
    // 航路を長くとって一つ一つを遠くに置く(島の間に開けた海を残す)。
    static let xStart: Float = -56.0
    static let xEnd: Float = -2.0

    static let routeApproachPower: Float = 2.15

    // MARK: - 素材
    //
    // Web は three.js の meshStandardMaterial(PBR + flatShading + roughness)。
    // three.js は既定で HDR + ACES トーンマッピング + リニア色管理で描くため、
    // SceneKit でも (1) lightingModel=.physicallyBased (2) カメラ wantsHDR+bloom
    // (3) 被フォグ素材にカメラ距離フォグ を揃えないと同じ絵にならない。

    /// 面法線をフラグメントで再計算して低ポリのファセットを出す(flatShading 相当)。
    private static let flatNormalBody =
        "_surface.normal = normalize(cross(dfdx(_surface.position.xyz), dfdy(_surface.position.xyz)));"

    /// Web <fog NIGHT_BG 12 30> 相当。被フォグ素材にだけ差す、カメラ距離の線形フォグ。
    /// リニア空間で出力色を夜色へ寄せる(月/海/水平線/点灯ブイ/波紋/航跡には差さない)。
    private static let fogFragment = """
    float _fogD = length(_surface.position.xyz);
    float _fogF = clamp((_fogD - 12.0) / (30.0 - 12.0), 0.0, 1.0);
    float3 _fogC = pow(float3(0.0706, 0.2196, 0.1882), 2.2); // #123830 → linear
    _output.color.rgb = mix(_output.color.rgb, _fogC, _fogF);
    """

    /// 船体の幅絞り(舳先/船尾へ向けて奥行きを絞る)。Web の頂点後処理を GPU で。
    private static let hullTaperGeometry = """
    float _hx = _geometry.position.x;
    float _hn = clamp(abs(_hx - 0.1) - 0.35, 0.0, 1.0);
    _geometry.position.z *= (1.0 - 0.55 * _hn * _hn);
    """

    /// PBR のフラット素材(meshStandardMaterial color+flatShading+roughness 相当)。
    static func litMaterial(
        _ color: UIColor,
        roughness: CGFloat = 0.9,
        doubleSided: Bool = false,
        fogged: Bool = true,
        hullTaper: Bool = false
    ) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = 0.0
        m.isDoubleSided = doubleSided
        var mods: [SCNShaderModifierEntryPoint: String] = [.surface: flatNormalBody]
        if hullTaper { mods[.geometry] = hullTaperGeometry }
        if fogged { mods[.fragment] = fogFragment }
        m.shaderModifiers = mods
        return m
    }

    /// 旧名の別名(既存呼び出しの互換)。
    static func flatMaterial(_ color: UIColor, doubleSided: Bool = false) -> SCNMaterial {
        litMaterial(color, doubleSided: doubleSided)
    }

    /// 発光・自照の素材(月・水平線・旗の目など)。フォグは差さない。
    static func unlitMaterial(_ color: UIColor, fogged: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.isDoubleSided = true
        if fogged { m.shaderModifiers = [.fragment: fogFragment] }
        return m
    }

    // MARK: - 空(月・星・水平線)

    static func makeMoon(
        position: SCNVector3,
        date: Date = .now
    ) -> SCNNode {
        let node = LandfallMoonEffects.makeNode(phase: .current(at: date))
        node.position = position
        return node
    }

    /// 星空。drei Stars(radius 42, depth 18)相当の点群を決定的な乱数で撒く。
    static func makeStars(count: Int = 380) -> SCNNode {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rand() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float((seed >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
        }
        var verts: [SCNVector3] = []
        verts.reserveCapacity(count)
        var i = 0
        while verts.count < count && i < count * 20 {
            i += 1
            // 球殻(42..60)上の一様方向。海面下と真後ろは捨てる。
            let u = rand() * 2 - 1
            let phi = rand() * 2 * Float.pi
            let s = sqrt(max(0, 1 - u * u))
            let dir = SCNVector3(s * cos(phi), u, s * sin(phi))
            if dir.y < 0.02 { continue }       // 水平線より下は見えない
            if dir.z > 0.3 { continue }        // カメラ背後は不要
            let r = 42 + rand() * 18
            verts.append(SCNVector3(dir.x * r, dir.y * r, dir.z * r))
        }
        let src = SCNGeometrySource(vertices: verts)
        var idx = (0..<UInt32(verts.count)).map { $0 }
        let data = Data(bytes: &idx, count: idx.count * 4)
        let elem = SCNGeometryElement(
            data: data, primitiveType: .point,
            primitiveCount: verts.count, bytesPerIndex: 4
        )
        elem.pointSize = 0.1
        elem.minimumPointScreenSpaceRadius = 0.6
        elem.maximumPointScreenSpaceRadius = 1.9
        let geo = SCNGeometry(sources: [src], elements: [elem])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = sand.withAlphaComponent(0.85)
        geo.firstMaterial = m
        return SCNNode(geometry: geo)
    }

    // MARK: - 壮大な目的地の島

    /// 航海のすべての画面で共有する目的地の島。遠景では段状の長い稜線、
    /// 近景では浜から山頂へ続く道・灯り・岩・植生まで読める密度にする。
    static func makeIsland(
        position: SCNVector3 = SCNVector3(3.5, 0, -0.9),
        scale: SCNVector3 = SCNVector3(1.34, 1.38, 1.34),
        includesCustomAssets: Bool = true,
        oceanAppearance: HomeIslandOceanEffects.Appearance = .daylight
    ) -> SCNNode {
        let group = SCNNode()
        group.name = "island"
        group.position = position
        group.scale = scale
        group.eulerAngles.y = AftideHomeWorldReference.islandYaw

        // 3Dスタジオで選んだ世界が、このゲームの「島そのもの」。
        // 共通ファクトリの入り口で旧島と置き換えることで、ホーム・航海中・
        // 目的地・共有画面のどこから見ても必ず同じデザインになる。
        if let studioWorld = AssetPlacementRuntime.makeActiveStudioWorldNode() {
            studioWorld.name = "active-studio-world"
            group.addChildNode(studioWorld)
            if includesCustomAssets {
                AssetPlacementRuntime.attachSavedPlacements(context: .destinationIsland, to: group)
            }
            return group
        }

        let shadowGeo = SCNCone(topRadius: 3.38, bottomRadius: 3.66, height: 0.035)
        shadowGeo.radialSegmentCount = 24
        let shadowMaterial = unlitMaterial(UIColor(rgb: 0x0B2927).withAlphaComponent(0.28))
        shadowMaterial.writesToDepthBuffer = false
        shadowGeo.firstMaterial = shadowMaterial
        let shadow = SCNNode(geometry: shadowGeo)
        shadow.position = SCNVector3(0.08, 0.018, 0.08)
        shadow.scale.z = 0.74
        group.addChildNode(shadow)

        group.addChildNode(makeShoreBreakers(appearance: oceanAppearance))

        let beachGeo = SCNCone(topRadius: 3.18, bottomRadius: 3.48, height: 0.15)
        beachGeo.radialSegmentCount = 28
        beachGeo.firstMaterial = litMaterial(beach, roughness: 0.97)
        let beachNode = SCNNode(geometry: beachGeo)
        beachNode.position = SCNVector3(0, 0.085, 0.08)
        beachNode.scale.z = 0.74
        group.addChildNode(beachNode)

        let terrain = SCNNode(geometry: makeGrandIslandTerrain())
        terrain.name = "islandTerrain"
        terrain.position.y = 0.11
        group.addChildNode(terrain)

        // 岩峰は真円錐ではなく、各段の中心と半径を揺らしたファセット形状。
        // 海側から見たときに峰が重ならないよう、左右と奥行きへ散らす。
        let crags: [(x: Float, y: Float, z: Float, radius: Float, height: Float, color: UInt, seed: Int)] = [
            (-0.92, 0.72, -0.82, 0.88, 2.25, 0x7E8771, 11),
            (-0.34, 0.90, 0.62, 1.03, 2.92, 0x96967A, 23),
            (0.36, 1.04, -0.34, 1.12, 3.62, 0xAAA486, 37),
            (1.12, 1.14, 0.58, 0.92, 4.28, 0x737C6C, 53),
            (1.62, 0.74, -0.78, 0.68, 2.42, 0x687467, 71),
        ]
        for crag in crags {
            let node = makeIslandCrag(
                radius: crag.radius,
                height: crag.height,
                color: UIColor(rgb: crag.color),
                seed: crag.seed
            )
            node.position = SCNVector3(crag.x, crag.y, crag.z)
            group.addChildNode(node)
        }

        // 浜から尾根を折り返しながら登る道。背景画像の「先へ進める島」を
        // 実際の3Dでも同じ意味で見せる。
        let pathPoints = [
            SCNVector3(-3.02, 0.20, 0.64),
            SCNVector3(-2.34, 0.34, 0.52),
            SCNVector3(-1.78, 0.56, 0.12),
            SCNVector3(-1.22, 0.86, 0.52),
            SCNVector3(-0.56, 1.15, 0.24),
            SCNVector3(0.02, 1.48, -0.18),
            SCNVector3(0.54, 1.94, 0.10),
            SCNVector3(0.92, 2.48, 0.42),
            SCNVector3(1.16, 3.08, 0.54),
        ]
        group.addChildNode(makeIslandPath(points: pathPoints))

        for (index, point) in pathPoints.enumerated() where index > 0 && index < pathPoints.count - 1 {
            if index.isMultiple(of: 2) {
                let lamp = makeIslandLamp(strong: index == 6)
                lamp.position = SCNVector3(point.x, point.y + 0.04, point.z + 0.28)
                group.addChildNode(lamp)
            }
        }

        // 海岸の岩。シルエットを崩すだけでなく、浜を「円盤」ではなく入り江に見せる。
        for index in 0..<18 {
            let angle = Float(index) / 18 * 2 * .pi + sin(Float(index) * 1.7) * 0.11
            let radius = 2.68 + sin(Float(index) * 2.3) * 0.28
            let x = cos(angle) * radius
            let z = sin(angle) * radius * 0.70
            let size = 0.18 + Float(index % 5) * 0.035
            let rock = SCNSphere(radius: CGFloat(size))
            rock.segmentCount = 6
            rock.firstMaterial = litMaterial(
                UIColor(rgb: index.isMultiple(of: 3) ? 0x6E6B5D : 0x827A65),
                roughness: 0.98
            )
            let node = SCNNode(geometry: rock)
            node.position = SCNVector3(x, 0.18 + size * 0.42, z)
            node.scale = SCNVector3(1.18, 0.78 + Float(index % 3) * 0.10, 0.92)
            node.eulerAngles = SCNVector3(0.12, Float(index) * 0.73, 0.08)
            group.addChildNode(node)
        }

        // 植生は乱数で全面へ散らさず、海風の弱い谷筋と岩陰へ群落を作る。
        // 地表を這う苔 → 低木 → 草の順に重ね、地形から自然に生えた密度へする。
        let coverPatches: [(x: Float, z: Float, radius: Float, seed: Int)] = [
            (-2.18, -0.62, 0.64, 3), (-1.92, 1.06, 0.52, 7),
            (-1.24, -1.28, 0.58, 11), (-0.58, 1.58, 0.48, 17),
            (0.12, -1.72, 0.56, 23), (0.78, 1.58, 0.44, 29),
            (1.58, 1.30, 0.48, 31), (2.08, -0.74, 0.55, 37),
        ]
        for patch in coverPatches {
            group.addChildNode(makeIslandGroundCover(
                center: SCNVector3(patch.x, 0, patch.z),
                radius: patch.radius,
                seed: patch.seed
            ))
        }

        let shrubs: [(x: Float, z: Float, scale: Float, seed: Int)] = [
            (-2.38, -0.50, 0.86, 5), (-2.04, -0.92, 1.02, 9),
            (-1.82, 1.20, 0.88, 13), (-1.38, -1.48, 0.96, 19),
            (-0.92, 1.72, 0.78, 27), (-0.20, -1.84, 0.92, 33),
            (0.44, 1.82, 0.82, 39), (1.12, 1.66, 0.90, 43),
            (1.84, 1.10, 0.80, 51), (2.18, -0.58, 0.94, 57),
            (2.38, 0.28, 0.76, 63),
        ]
        for shrub in shrubs {
            let normalizedRadius = islandNormalizedRadius(x: shrub.x, z: shrub.z)
            let ground = grandIslandHeight(x: shrub.x, z: shrub.z, radius: normalizedRadius)
            let plant = makeIslandShrub(seed: shrub.seed, scale: shrub.scale)
            plant.position = SCNVector3(shrub.x, 0.11 + ground, shrub.z)
            plant.eulerAngles.y = Float(shrub.seed) * 0.41
            group.addChildNode(plant)
        }

        let grasses: [(x: Float, z: Float, seed: Int)] = [
            (-2.62, 0.18, 2), (-2.34, 0.86, 4), (-2.08, -1.22, 6),
            (-1.72, -1.58, 8), (-1.48, 1.62, 10), (-1.06, -1.86, 12),
            (-0.70, 1.92, 14), (-0.28, -1.98, 16), (0.18, 2.00, 18),
            (0.72, -1.88, 20), (1.10, 1.86, 22), (1.56, -1.58, 24),
            (1.94, 1.28, 26), (2.28, -1.02, 28), (2.56, 0.22, 30),
        ]
        for grass in grasses {
            let normalizedRadius = islandNormalizedRadius(x: grass.x, z: grass.z)
            let ground = grandIslandHeight(x: grass.x, z: grass.z, radius: normalizedRadius)
            let plant = makeIslandGrass(seed: grass.seed)
            plant.position = SCNVector3(grass.x, 0.11 + ground, grass.z)
            plant.eulerAngles.y = Float(grass.seed) * 0.29
            group.addChildNode(plant)
        }

        let summitBeacon = makeIslandSummitBeacon()
        summitBeacon.position = SCNVector3(1.16, 5.37, 0.54)
        group.addChildNode(summitBeacon)

        // 3D Asset Studioで保存した配置を島のローカル座標として復元する。
        // Studio自身は false を渡し、編集対象が二重表示されないようにする。
        if includesCustomAssets {
            AssetPlacementRuntime.attachSavedPlacements(context: .destinationIsland, to: group)
        }

        return group
    }

    /// 海岸線を均一なチューブで囲まず、海面上で途切れながら進む二筋の砕波にする。
    /// 外周形状は島の地形と同じ複数周期で揺らし、細い外波を少し遅らせることで
    /// 静止画でも輪郭が自然に崩れ、動画では寄せては消える奥行きが生まれる。
    private static func makeShoreBreakers(
        appearance: HomeIslandOceanEffects.Appearance
    ) -> SCNNode {
        let geometry = makeShoreBreakerRibbon()
        let material = shoreBreakerMaterial(appearance: appearance)
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.name = "island-shore-breakers"
        node.position = SCNVector3(0, 0.056, 0.08)
        node.castsShadow = false
        node.renderingOrder = 24
        material.setValue(NSNumber(value: HomeIslandOceanEffects.currentTime), forKey: "uTime")
        node.runAction(.repeatForever(.customAction(duration: 86_400) { node, _ in
            node.geometry?.firstMaterial?.setValue(
                NSNumber(value: HomeIslandOceanEffects.currentTime),
                forKey: "uTime"
            )
        }))
        return node
    }

    private static func makeShoreBreakerRibbon() -> SCNGeometry {
        let segments = 144
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var texcoords: [CGPoint] = []
        var indices: [UInt32] = []
        vertices.reserveCapacity((segments + 1) * 2)
        normals.reserveCapacity((segments + 1) * 2)
        texcoords.reserveCapacity((segments + 1) * 2)
        indices.reserveCapacity(segments * 6)

        for segment in 0...segments {
            let progress = Float(segment) / Float(segments)
            let angle = progress * Float.pi * 2
            let coast = sin(angle * 3 + 0.45) * 0.045
                + sin(angle * 7 - 0.82) * 0.026
                + sin(angle * 11 + 1.30) * 0.012
            let fineDrift = sin(angle * 17 + 0.25) * 0.018
            let centerRadius = 3.46 * (1 + coast) + fineDrift
            let localWidth = 0.72 * (0.90 + 0.10 * (0.5 + 0.5 * sin(angle * 9 - 0.25)))
            let radii = [centerRadius - localWidth * 0.5, centerRadius + localWidth * 0.5]
            for (edge, radius) in radii.enumerated() {
                vertices.append(
                    SCNVector3(
                        cos(angle) * radius * 1.02,
                        sin(angle * 5 + 0.25) * 0.006,
                        sin(angle) * radius * 0.74
                    )
                )
                normals.append(SCNVector3(0, 1, 0))
                texcoords.append(CGPoint(x: CGFloat(progress), y: CGFloat(edge)))
            }
        }

        for segment in 0..<segments {
            let start = UInt32(segment * 2)
            indices += [start, start + 2, start + 1, start + 1, start + 2, start + 3]
        }
        let element = indices.withUnsafeBufferPointer {
            SCNGeometryElement(
                data: Data(buffer: $0),
                primitiveType: .triangles,
                primitiveCount: indices.count / 3,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )
        }
        return SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: vertices),
                SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: texcoords),
            ],
            elements: [element]
        )
    }

    private static func shoreBreakerMaterial(
        appearance: HomeIslandOceanEffects.Appearance
    ) -> SCNMaterial {
        let tint = mixedColor(appearance.light, appearance.shallow, weight: 0.14)
        let opacity = CGFloat(0.42 + appearance.sunStrength * 0.24)
        let material = unlitMaterial(tint.withAlphaComponent(opacity))
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.shaderModifiers = [.fragment: """
        #pragma arguments
        float uTime;
        #pragma body
        float u = _surface.diffuseTexcoord.x;
        float v = _surface.diffuseTexcoord.y;
        float primaryCenter = 0.34 + sin(u * 31.42 - uTime * 0.58) * 0.035;
        float outerCenter = 0.78 + sin(u * 81.68 + uTime * 0.37) * 0.025;
        float primary = 1.0 - smoothstep(0.055, 0.145, abs(v - primaryCenter));
        float outer = 1.0 - smoothstep(0.035, 0.100, abs(v - outerCenter));
        float primaryBreak = 0.5 + 0.5 * sin(
            u * 144.51 + sin(u * 56.55 + 0.25) * 1.45 - uTime * 0.82
        );
        float outerBreak = 0.5 + 0.5 * sin(
            u * 257.61 - sin(u * 106.81) * 1.10 + uTime * 0.57 + 2.10
        );
        float primaryFragments = max(
            smoothstep(0.40, 0.76, primaryBreak),
            smoothstep(0.72, 0.94, outerBreak) * 0.42
        );
        float outerFragments = smoothstep(0.48, 0.84, outerBreak);
        float foam = min(
            primary * primaryFragments + outer * outerFragments * 0.44,
            1.0
        );
        float surge = 0.82 + 0.18 * sin(uTime * 0.66 + u * 31.42 + 0.25);
        _output.color.rgb *= 0.94 + foam * 0.10;
        _output.color.a *= foam * surge;
        """]
        return material
    }

    private static func mixedColor(_ primary: UInt, _ secondary: UInt, weight: Float) -> UIColor {
        func component(_ rgb: UInt, shift: UInt) -> Float {
            Float((rgb >> shift) & 0xFF) / 255
        }
        let amount = min(max(weight, 0), 1)
        return UIColor(
            red: CGFloat(component(primary, shift: 16) * (1 - amount)
                + component(secondary, shift: 16) * amount),
            green: CGFloat(component(primary, shift: 8) * (1 - amount)
                + component(secondary, shift: 8) * amount),
            blue: CGFloat(component(primary, shift: 0) * (1 - amount)
                + component(secondary, shift: 0) * amount),
            alpha: 1
        )
    }

    /// 海岸から複数の丘が連続して立ち上がる、低ポリの一枚地形。
    private static func makeGrandIslandTerrain(segments: Int = 48, rings: Int = 10) -> SCNGeometry {
        var vertices = [SCNVector3(0, grandIslandHeight(x: 0, z: 0, radius: 0), 0)]
        var colors = [grandIslandColor(height: vertices[0].y, x: 0, z: 0)]
        var indices: [UInt32] = []

        for ring in 1...rings {
            let radius = Float(ring) / Float(rings)
            for segment in 0..<segments {
                let angle = Float(segment) / Float(segments) * 2 * .pi
                let coast = 1
                    + sin(angle * 3 + 0.4) * 0.055
                    + cos(angle * 5 - 0.7) * 0.035
                    + sin(angle * 9 + 1.3) * 0.018
                let x = cos(angle) * 3.12 * radius * coast
                let z = sin(angle) * 2.22 * radius * (1 + sin(angle * 4 + 0.2) * 0.05)
                let y = grandIslandHeight(x: x, z: z, radius: radius)
                vertices.append(SCNVector3(x, y, z))
                colors.append(grandIslandColor(height: y, x: x, z: z))
            }
        }

        for segment in 0..<segments {
            let next = (segment + 1) % segments
            indices += [0, UInt32(1 + next), UInt32(1 + segment)]
        }
        for ring in 2...rings {
            let previous = 1 + (ring - 2) * segments
            let current = 1 + (ring - 1) * segments
            for segment in 0..<segments {
                let next = (segment + 1) % segments
                let a = UInt32(previous + segment)
                let b = UInt32(previous + next)
                let c = UInt32(current + segment)
                let d = UInt32(current + next)
                indices += [a, b, c, b, d, c]
            }
        }

        let normals = islandNormals(vertices: vertices, indices: indices)
        let element = indices.withUnsafeBufferPointer {
            SCNGeometryElement(
                data: Data(buffer: $0),
                primitiveType: .triangles,
                primitiveCount: indices.count / 3,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )
        }
        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: vertices),
                SCNGeometrySource(normals: normals),
                islandColorSource(colors),
            ],
            elements: [element]
        )
        geometry.firstMaterial = litMaterial(.white, roughness: 0.96, fogged: false)
        return geometry
    }

    private static func grandIslandHeight(x: Float, z: Float, radius: Float) -> Float {
        if radius >= 0.995 { return 0.08 }
        let front = 0.72 * exp(-(((x + 1.55) * (x + 1.55)) / 1.65 + ((z - 0.18) * (z - 0.18)) / 0.72))
        let center = 1.24 * exp(-(((x + 0.25) * (x + 0.25)) / 1.85 + ((z + 0.10) * (z + 0.10)) / 1.10))
        let rear = 1.46 * exp(-(((x - 1.02) * (x - 1.02)) / 1.28 + ((z - 0.12) * (z - 0.12)) / 0.86))
        let ridge = 0.54 * exp(-(((x - 0.08) * (x - 0.08)) / 3.4 + (z * z) / 0.48))
        let coastFade = pow(max(0, 1 - radius), 0.42)
        let foothill = 0.30 * pow(max(0, 1 - radius), 0.66)
        let facets = (sin(x * 3.8 + z * 1.6) + sin(x * 1.7 - z * 4.8))
            * 0.045 * pow(max(0, 1 - radius), 1.2)
        let raw = 0.08 + foothill + (front + center + rear + ridge) * coastFade + facets
        // わずかな段差を混ぜ、生成背景の登れる岩棚のリズムを作る。
        let terraced = floor(raw * 5) / 5
        return max(0.08, raw * 0.72 + terraced * 0.28)
    }

    /// Asset Studioの「地面に合わせる」で使う、島ローカル座標の地表高。
    static func islandSurfaceHeight(x: Float, z: Float) -> Float {
        let radius = islandNormalizedRadius(x: x, z: z)
        return 0.11 + grandIslandHeight(x: x, z: z, radius: radius)
    }

    private static func grandIslandColor(height: Float, x: Float, z: Float) -> UIColor {
        let rock: UIColor
        switch height {
        case ..<0.34: rock = UIColor(rgb: 0xB6B187)
        case ..<0.78: rock = UIColor(rgb: 0x7F9070)
        case ..<1.24: rock = UIColor(rgb: 0x929276)
        default: rock = UIColor(rgb: 0xAAA481)
        }
        // 低地と谷筋だけに連続した植生帯を作る。頂点単位で地形へ焼き込むため、
        // 緑の板や球が岩から浮かず、斜面の形に沿って見える。
        let moisture = sin(x * 2.15 + z * 3.70) + cos(x * 3.05 - z * 1.85)
        let altitude = max(0, min(1, (1.42 - height) / 1.18))
        let moss = max(0, min(0.52, (moisture + 0.18) * 0.24 * altitude))
        return islandBlend(rock, UIColor(rgb: 0x58705A), moss)
    }

    /// 半径と中心を段ごとにずらした、左右非対称の岩峰。
    private static func makeIslandCrag(
        radius: Float,
        height: Float,
        color: UIColor,
        seed: Int
    ) -> SCNNode {
        let segments = 9
        let levels: [(y: Float, radius: Float)] = [
            (0, 1), (0.20, 0.93), (0.27, 0.78),
            (0.47, 0.74), (0.55, 0.55), (0.72, 0.50),
            (0.80, 0.32), (0.92, 0.26),
        ]
        var vertices: [SCNVector3] = []
        var colors: [UIColor] = []
        for (levelIndex, level) in levels.enumerated() {
            let driftX = sin(Float(seed + levelIndex * 17)) * radius * 0.11
            let driftZ = cos(Float(seed * 3 + levelIndex * 13)) * radius * 0.09
            for segment in 0..<segments {
                let angle = Float(segment) / Float(segments) * 2 * .pi
                let jitter = 1 + sin(Float(seed * 19 + levelIndex * 11 + segment * 7)) * 0.10
                vertices.append(SCNVector3(
                    driftX + cos(angle) * radius * level.radius * jitter,
                    height * level.y,
                    driftZ + sin(angle) * radius * level.radius * jitter
                ))
                let faceVariation = sin(Float(seed + segment * 5 + levelIndex * 11)) * 0.035
                let rockColor = islandBlend(color, sand, level.y * 0.18 + faceVariation)
                let moisture = sin(angle * 2.3 + Float(seed) * 0.17 + level.y * 4.8)
                    + cos(angle * 4.1 - Float(seed) * 0.11)
                let altitudeBand = max(0, sin(level.y * .pi))
                let moss = max(0, min(0.46, (moisture - 0.12) * 0.25 * altitudeBand))
                colors.append(islandBlend(rockColor, UIColor(rgb: 0x4C6852), moss))
            }
        }
        let topIndex = UInt32(vertices.count)
        vertices.append(SCNVector3(
            sin(Float(seed)) * radius * 0.16,
            height,
            cos(Float(seed * 2)) * radius * 0.12
        ))
        colors.append(islandBlend(color, sand, 0.24))

        var indices: [UInt32] = []
        for level in 0..<(levels.count - 1) {
            let current = level * segments
            let nextLevel = (level + 1) * segments
            for segment in 0..<segments {
                let next = (segment + 1) % segments
                indices += [
                    UInt32(current + segment), UInt32(current + next), UInt32(nextLevel + segment),
                    UInt32(current + next), UInt32(nextLevel + next), UInt32(nextLevel + segment),
                ]
            }
        }
        let lastRing = (levels.count - 1) * segments
        for segment in 0..<segments {
            let next = (segment + 1) % segments
            indices += [UInt32(lastRing + segment), UInt32(lastRing + next), topIndex]
        }

        let normals = islandNormals(vertices: vertices, indices: indices)
        let element = indices.withUnsafeBufferPointer {
            SCNGeometryElement(
                data: Data(buffer: $0),
                primitiveType: .triangles,
                primitiveCount: indices.count / 3,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )
        }
        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: vertices),
                SCNGeometrySource(normals: normals),
                islandColorSource(colors),
            ],
            elements: [element]
        )
        geometry.firstMaterial = litMaterial(.white, roughness: 0.97, fogged: false)
        return SCNNode(geometry: geometry)
    }

    private static func makeIslandPath(points: [SCNVector3]) -> SCNNode {
        let root = SCNNode()
        root.name = "islandPath"
        guard points.count > 1 else { return root }
        for index in 0..<(points.count - 1) {
            let from = points[index]
            let to = points[index + 1]
            let dx = to.x - from.x
            let dy = to.y - from.y
            let dz = to.z - from.z
            let horizontal = sqrt(dx * dx + dz * dz)
            let length = sqrt(horizontal * horizontal + dy * dy)
            let geometry = SCNBox(
                width: CGFloat(length + 0.08),
                height: 0.055,
                length: index < 2 ? 0.38 : 0.30,
                chamferRadius: 0.06
            )
            geometry.chamferSegmentCount = 1
            geometry.firstMaterial = litMaterial(UIColor(rgb: 0xD7CBA5), roughness: 0.98, fogged: false)
            let segment = SCNNode(geometry: geometry)
            segment.position = SCNVector3(
                (from.x + to.x) * 0.5,
                (from.y + to.y) * 0.5 + 0.025,
                (from.z + to.z) * 0.5
            )
            segment.eulerAngles.y = -atan2(dz, dx)
            segment.eulerAngles.z = atan2(dy, max(horizontal, 0.001))
            root.addChildNode(segment)
        }
        return root
    }

    private static func makeIslandLamp(strong: Bool) -> SCNNode {
        let root = SCNNode()
        let poleHeight: Float = 0.42
        let poleGeo = SCNCylinder(radius: 0.018, height: CGFloat(poleHeight))
        poleGeo.radialSegmentCount = 6
        poleGeo.firstMaterial = litMaterial(wood, roughness: 0.9, fogged: false)
        let pole = SCNNode(geometry: poleGeo)
        pole.position.y = poleHeight * 0.5
        root.addChildNode(pole)

        let lightGeo = SCNSphere(radius: strong ? 0.075 : 0.058)
        lightGeo.segmentCount = 8
        let material = litMaterial(ember, roughness: 0.4, fogged: false)
        material.emission.contents = returnOrange
        material.emission.intensity = strong ? 2.2 : 1.6
        lightGeo.firstMaterial = material
        let glow = SCNNode(geometry: lightGeo)
        glow.position.y = poleHeight + 0.03
        root.addChildNode(glow)
        return root
    }

    private static func makeIslandGrass(seed: Int) -> SCNNode {
        let root = SCNNode()
        let colors = [UIColor(rgb: 0x526F59), UIColor(rgb: 0x637A5E), UIColor(rgb: 0x455F50)]
        for blade in 0..<3 {
            let height = 0.22 + Float((seed + blade) % 3) * 0.035
            let geometry = SCNCone(topRadius: 0, bottomRadius: 0.035, height: CGFloat(height))
            geometry.radialSegmentCount = 4
            geometry.firstMaterial = litMaterial(colors[(seed + blade) % colors.count], roughness: 0.98, fogged: false)
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(Float(blade - 1) * 0.055, height * 0.5, Float(blade % 2) * 0.028)
            node.eulerAngles.z = Float(blade - 1) * 0.20
            root.addChildNode(node)
        }
        return root
    }

    /// 地形の各頂点高を再計算して密着させる、不定形の苔・下草パッチ。
    private static func makeIslandGroundCover(
        center: SCNVector3,
        radius: Float,
        seed: Int
    ) -> SCNNode {
        let segments = 12
        var vertices: [SCNVector3] = []
        let centerRadius = islandNormalizedRadius(x: center.x, z: center.z)
        vertices.append(SCNVector3(
            center.x,
            0.126 + grandIslandHeight(x: center.x, z: center.z, radius: centerRadius),
            center.z
        ))
        for index in 0..<segments {
            let angle = Float(index) / Float(segments) * 2 * .pi
            let wobble = 0.78 + 0.22 * sin(Float(seed * 13 + index * 7))
            let x = center.x + cos(angle) * radius * wobble
            let z = center.z + sin(angle) * radius * 0.72 * wobble
            let normalizedRadius = islandNormalizedRadius(x: x, z: z)
            vertices.append(SCNVector3(
                x,
                0.126 + grandIslandHeight(x: x, z: z, radius: normalizedRadius),
                z
            ))
        }

        var indices: [UInt32] = []
        for index in 0..<segments {
            indices += [0, UInt32(index + 1), UInt32((index + 1) % segments + 1)]
        }
        let normals = islandNormals(vertices: vertices, indices: indices)
        let element = indices.withUnsafeBufferPointer {
            SCNGeometryElement(
                data: Data(buffer: $0),
                primitiveType: .triangles,
                primitiveCount: indices.count / 3,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )
        }
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
            elements: [element]
        )
        let colors = [0x486655, 0x526E59, 0x5B755E]
        geometry.firstMaterial = litMaterial(
            UIColor(rgb: UInt(colors[abs(seed) % colors.count])),
            roughness: 1,
            doubleSided: true,
            fogged: false
        )
        return SCNNode(geometry: geometry)
    }

    /// 球形のトピアリーに見えないよう、中心をずらした二つの不定形な葉房で作る低木。
    private static func makeIslandShrub(seed: Int, scale: Float) -> SCNNode {
        let root = SCNNode()
        let trunkHeight = 0.28 * scale
        let trunkGeometry = SCNCylinder(radius: CGFloat(0.025 * scale), height: CGFloat(trunkHeight))
        trunkGeometry.radialSegmentCount = 5
        trunkGeometry.firstMaterial = litMaterial(UIColor(rgb: 0x5B4934), roughness: 1, fogged: false)
        let trunk = SCNNode(geometry: trunkGeometry)
        trunk.position.y = trunkHeight * 0.5
        trunk.eulerAngles.z = sin(Float(seed)) * 0.08
        root.addChildNode(trunk)

        let leafColors = [0x355747, 0x42644F, 0x4E6E55, 0x5B775B]
        let crownCount = seed.isMultiple(of: 2) ? 2 : 1
        for index in 0..<crownCount {
            let radius = (index == 0 ? 0.23 : 0.16) * scale
            let height = (index == 0 ? 0.34 : 0.26) * scale
            let geometry = makeIslandFoliageCrown(
                radius: radius,
                height: height,
                color: UIColor(rgb: UInt(leafColors[(seed + index) % leafColors.count])),
                seed: seed + index * 11
            )
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(
                (index == 0 ? -0.025 : 0.13) * scale,
                (index == 0 ? 0.23 : 0.26) * scale,
                (index == 0 ? 0.01 : -0.07) * scale
            )
            root.addChildNode(node)
        }
        return root
    }

    private static func makeIslandFoliageCrown(
        radius: Float,
        height: Float,
        color: UIColor,
        seed: Int
    ) -> SCNGeometry {
        let segments = 7
        let levels: [(y: Float, radius: Float)] = [
            (0, 0.62), (0.28, 0.96), (0.66, 0.78), (0.88, 0.42),
        ]
        var vertices: [SCNVector3] = []
        for (levelIndex, level) in levels.enumerated() {
            let driftX = sin(Float(seed + levelIndex * 7)) * radius * 0.14
            let driftZ = cos(Float(seed * 2 + levelIndex * 5)) * radius * 0.12
            for segment in 0..<segments {
                let angle = Float(segment) / Float(segments) * 2 * .pi
                let jitter = 0.84 + 0.18 * (0.5 + 0.5 * sin(Float(seed * 3 + levelIndex * 13 + segment * 5)))
                vertices.append(SCNVector3(
                    driftX + cos(angle) * radius * level.radius * jitter,
                    height * level.y,
                    driftZ + sin(angle) * radius * level.radius * jitter
                ))
            }
        }
        let topIndex = UInt32(vertices.count)
        vertices.append(SCNVector3(
            sin(Float(seed)) * radius * 0.12,
            height,
            cos(Float(seed)) * radius * 0.10
        ))

        var indices: [UInt32] = []
        for level in 0..<(levels.count - 1) {
            let current = level * segments
            let nextLevel = (level + 1) * segments
            for segment in 0..<segments {
                let next = (segment + 1) % segments
                indices += [
                    UInt32(current + segment), UInt32(current + next), UInt32(nextLevel + segment),
                    UInt32(current + next), UInt32(nextLevel + next), UInt32(nextLevel + segment),
                ]
            }
        }
        let lastRing = (levels.count - 1) * segments
        for segment in 0..<segments {
            let next = (segment + 1) % segments
            indices += [UInt32(lastRing + segment), UInt32(lastRing + next), topIndex]
        }
        let normals = islandNormals(vertices: vertices, indices: indices)
        let element = indices.withUnsafeBufferPointer {
            SCNGeometryElement(
                data: Data(buffer: $0),
                primitiveType: .triangles,
                primitiveCount: indices.count / 3,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )
        }
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
            elements: [element]
        )
        geometry.firstMaterial = litMaterial(color, roughness: 1, fogged: false)
        return geometry
    }

    private static func islandNormalizedRadius(x: Float, z: Float) -> Float {
        min(1, sqrt((x / 3.1) * (x / 3.1) + (z / 2.25) * (z / 2.25)))
    }

    private static func makeIslandSummitBeacon() -> SCNNode {
        let root = SCNNode()
        let poleGeo = SCNCylinder(radius: 0.024, height: 0.72)
        poleGeo.radialSegmentCount = 7
        poleGeo.firstMaterial = litMaterial(wood, roughness: 0.9, fogged: false)
        let pole = SCNNode(geometry: poleGeo)
        pole.position.y = 0.36
        root.addChildNode(pole)

        let flagPath = UIBezierPath()
        flagPath.move(to: CGPoint(x: 0, y: 0))
        flagPath.addLine(to: CGPoint(x: 0, y: 0.24))
        flagPath.addLine(to: CGPoint(x: 0.46, y: 0.17))
        flagPath.addLine(to: CGPoint(x: 0.34, y: 0.09))
        flagPath.addLine(to: CGPoint(x: 0.46, y: 0.02))
        flagPath.close()
        let flagGeo = SCNShape(path: flagPath, extrusionDepth: 0.006)
        flagGeo.firstMaterial = litMaterial(returnOrange, roughness: 0.92, doubleSided: true, fogged: false)
        let flag = SCNNode(geometry: flagGeo)
        flag.position = SCNVector3(0.02, 0.45, 0)
        root.addChildNode(flag)

        let glowGeo = SCNSphere(radius: 0.065)
        glowGeo.segmentCount = 8
        let glowMaterial = litMaterial(ember, roughness: 0.35, fogged: false)
        glowMaterial.emission.contents = returnOrange
        glowMaterial.emission.intensity = 2.4
        glowGeo.firstMaterial = glowMaterial
        let glow = SCNNode(geometry: glowGeo)
        glow.position.y = 0.76
        root.addChildNode(glow)
        return root
    }

    private static func islandColorSource(_ colors: [UIColor]) -> SCNGeometrySource {
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

    private static func islandBlend(_ a: UIColor, _ b: UIColor, _ t: Float) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: nil)
        b.getRed(&br, green: &bg, blue: &bb, alpha: nil)
        let amount = CGFloat(min(1, max(0, t)))
        return UIColor(
            red: ar + (br - ar) * amount,
            green: ag + (bg - ag) * amount,
            blue: ab + (bb - ab) * amount,
            alpha: 1
        )
    }

    private static func islandNormals(vertices: [SCNVector3], indices: [UInt32]) -> [SCNVector3] {
        var normals = [SCNVector3](repeating: SCNVector3Zero, count: vertices.count)
        for index in stride(from: 0, to: indices.count, by: 3) {
            let ia = Int(indices[index])
            let ib = Int(indices[index + 1])
            let ic = Int(indices[index + 2])
            let ab = SCNVector3(
                vertices[ib].x - vertices[ia].x,
                vertices[ib].y - vertices[ia].y,
                vertices[ib].z - vertices[ia].z
            )
            let ac = SCNVector3(
                vertices[ic].x - vertices[ia].x,
                vertices[ic].y - vertices[ia].y,
                vertices[ic].z - vertices[ia].z
            )
            let normal = SCNVector3(
                ab.y * ac.z - ab.z * ac.y,
                ab.z * ac.x - ab.x * ac.z,
                ab.x * ac.y - ab.y * ac.x
            )
            for vertexIndex in [ia, ib, ic] {
                normals[vertexIndex].x += normal.x
                normals[vertexIndex].y += normal.y
                normals[vertexIndex].z += normal.z
            }
        }
        return normals.map { value in
            let length = sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
            guard length > 0.0001 else { return SCNVector3(0, 1, 0) }
            return SCNVector3(value.x / length, value.y / length, value.z / length)
        }
    }

    // MARK: - 船(Web BoatModel の忠実移植)

    /// 舳先の上がった三日月型の船体。Webと同じ側面プロフィールを押し出し(面取り=ベベル)、
    /// 端へ向けた幅絞りは素材の .geometry シェーダで行う(hullTaper)。
    private static func makeHullGeometry(color: UIColor) -> SCNGeometry {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -1.02, y: 0.42))
        path.addQuadCurve(to: CGPoint(x: -0.88, y: -0.14), controlPoint: CGPoint(x: -1.2, y: 0.1))
        path.addQuadCurve(to: CGPoint(x: 0.86, y: -0.14), controlPoint: CGPoint(x: -0.02, y: -0.46))
        path.addQuadCurve(to: CGPoint(x: 1.32, y: 0.58), controlPoint: CGPoint(x: 1.18, y: 0.02))
        path.addLine(to: CGPoint(x: 1.14, y: 0.58))
        path.addQuadCurve(to: CGPoint(x: -1.02, y: 0.42), controlPoint: CGPoint(x: 0.18, y: 0.2))
        path.close()
        path.flatness = 0.12   // Web curveSegments: 9 相当の粗さ(低ポリの丸み)

        let shape = SCNShape(path: path, extrusionDepth: 0.5)
        shape.chamferRadius = 0.13
        shape.chamferMode = .both
        shape.firstMaterial = litMaterial(color, roughness: 0.85, hullTaper: true)
        return shape
    }

    /// 旗(pennant/swallow/kraken)の平面形。Web makeFlagGeometry(ShapeGeometry)相当。
    private static func makeFlagGeometry(kind: String, color: UIColor) -> SCNGeometry {
        let s = UIBezierPath()
        switch kind {
        case "pennant":
            s.move(to: CGPoint(x: 0, y: 0))
            s.addLine(to: CGPoint(x: 0, y: 0.22))
            s.addLine(to: CGPoint(x: -0.5, y: 0.11))
        case "swallow":
            s.move(to: CGPoint(x: 0, y: 0))
            s.addLine(to: CGPoint(x: 0, y: 0.22))
            s.addLine(to: CGPoint(x: -0.52, y: 0.22))
            s.addLine(to: CGPoint(x: -0.33, y: 0.11))
            s.addLine(to: CGPoint(x: -0.52, y: 0))
        default: // kraken: 触腕を思わせる、曲線の二叉
            s.move(to: CGPoint(x: 0, y: 0))
            s.addLine(to: CGPoint(x: 0, y: 0.22))
            s.addQuadCurve(to: CGPoint(x: -0.56, y: 0.21), controlPoint: CGPoint(x: -0.36, y: 0.28))
            s.addQuadCurve(to: CGPoint(x: -0.27, y: 0.11), controlPoint: CGPoint(x: -0.36, y: 0.16))
            s.addQuadCurve(to: CGPoint(x: -0.56, y: 0.01), controlPoint: CGPoint(x: -0.36, y: 0.06))
            s.addQuadCurve(to: CGPoint(x: 0, y: 0), controlPoint: CGPoint(x: -0.36, y: -0.06))
        }
        s.close()
        s.flatness = 0.01
        let shape = SCNShape(path: s, extrusionDepth: 0)
        shape.firstMaterial = litMaterial(color, roughness: 0.9, doubleSided: true)
        return shape
    }

    /// 三角帆。まっすぐなラフ+湾曲したリーチ+中央の膨らみ(Web makeSailGeometry と同式)。
    private static func makeSailGeometry(
        width: Float, height: Float, bulge: Float, shear: Float, color: UIColor
    ) -> SCNGeometry {
        let cols = 7, rows = 9
        var verts: [SCNVector3] = []
        for r in 0...rows {
            let v = Float(r) / Float(rows)
            let w = width * (1 - v * 0.97)
            let leech = 1 + 0.18 * sin(.pi * v)
            for c in 0...cols {
                let u = Float(c) / Float(cols)
                verts.append(SCNVector3(
                    -shear * v - u * w * leech,
                    v * height,
                    bulge * sin(.pi * u) * sin(.pi * min(v * 0.9 + 0.08, 1))
                ))
            }
        }
        var idx: [UInt32] = []
        for r in 0..<rows {
            for c in 0..<cols {
                let a = UInt32(r * (cols + 1) + c)
                let b = a + 1
                let d = a + UInt32(cols + 1)
                idx += [a, d, b, b, d, d + 1]
            }
        }
        let src = SCNGeometrySource(vertices: verts)
        let normals = SCNGeometrySource(normals: [SCNVector3](repeating: SCNVector3(0, 0, 1), count: verts.count))
        let data = Data(bytes: &idx, count: idx.count * 4)
        let elem = SCNGeometryElement(data: data, primitiveType: .triangles, primitiveCount: idx.count / 3, bytesPerIndex: 4)
        let geo = SCNGeometry(sources: [src, normals], elements: [elem])
        geo.firstMaterial = litMaterial(color, roughness: 0.95, doubleSided: true)
        return geo
    }

    /// 完成船モデルの実甲板上に置く航海士の足元。Webの定数と同値。
    static let navigatorDeckPosition = SCNVector3(0.74, 0.68, 0.18)
    static let navigatorDeckScale: Float = 0.62

    /// 航海士は船と同じBlenderモデル内の甲板アンカーへ取り付ける。
    /// GLB/USDZの軸変換後にワールド座標を足すと、視点を回した際に船から離れるため。
    private static func attachNavigator(to boat: SCNNode) {
        let sailor = PhoenixNavigator.makeNavigatorNode()
        sailor.position = SCNVector3Zero
        sailor.scale = SCNVector3(navigatorDeckScale, navigatorDeckScale, navigatorDeckScale)
        if let anchor = boat.childNode(withName: "Navigator_Anchor", recursively: true) {
            anchor.addChildNode(sailor)
        } else {
            sailor.position = navigatorDeckPosition
            boat.addChildNode(sailor)
        }
    }

    /// 甲板の4人は「役割 = 仕草 + 色」を固定する。ホスト側で見ても同行者側で
    /// 見ても、ランタン・見張り・座る・海図読みの4つが一度ずつだけ現れる。
    enum CompanionDeckRole: String, Hashable {
        case lantern, lookout, seated, chart

        /// 島の参加順と役割は全端末で同じ。見た目のための追加通信は行わない。
        static func participant(at index: Int) -> CompanionDeckRole? {
            switch index {
            case 0: .lantern
            case 1: .lookout
            case 2: .seated
            case 3: .chart
            default: nil
            }
        }

        var pose: PhoenixPose {
            switch self {
            case .lantern: .raise
            case .lookout: .lookout
            case .seated: .sit
            case .chart: .chart
            }
        }

        var colorID: String {
            switch self {
            case .lantern: "coral"
            case .lookout: "mist"
            case .seated: "iris"
            case .chart: "honey"
            }
        }

        var palette: NavigatorPalette {
            NavigatorCustomization.colors.first(where: { $0.id == colorID })?.palette ?? .default
        }
    }

    /// 私設島の同行者が並ぶ甲板の定位置。ホストを含む4役を前後左右へ固定し、
    /// 本人か同行者かに関係なく同じ席を使う。座標を送り合う必要はない。
    /// 席は「写真に撮ったときの並び」として決めている。
    ///
    /// 船首側はランタンと見張り、船尾側は座る役と海図役を左右に一人ずつ。
    /// 上から見ると2×2の菱形になり、どちらか一方の舷へ人が固まらない。
    static let companionDeckSlots: [CompanionDeckSeat] = [
        // 船首寄りの右舷。柵と帆から一歩内側で、右舷の水平線を見渡す。
        CompanionDeckSeat(position: SCNVector3(0.42, 0.68, 0.25), role: .lookout, facing: .starboard),
        // 船尾寄りの右舷。舷側へ腰を下ろして海を見る。
        CompanionDeckSeat(position: SCNVector3(-0.28, 0.68, 0.42), role: .seated, facing: .starboard),
        // 船尾寄りの左舷。柵から離れた甲板上で海図を読み、後列も2人で揃える。
        CompanionDeckSeat(position: SCNVector3(-0.36, 0.62, -0.38), role: .chart, facing: .bowStarboard),
    ]

    /// 島の主の席。船首寄りの左舷内側で、正面を向いてランタンを掲げる。
    static let companionHostDeckSeat = CompanionDeckSeat(
        position: SCNVector3(0.42, 0.68, -0.25),
        role: .lantern,
        facing: .bow
    )

    static func companionDeckSeat(for role: CompanionDeckRole) -> CompanionDeckSeat {
        switch role {
        case .lantern: companionHostDeckSeat
        case .lookout: companionDeckSlots[0]
        case .seated: companionDeckSlots[1]
        case .chart: companionDeckSlots[2]
        }
    }

    /// 甲板の一席。同じ船に四人が乗っても、みな別のことをしている。
    struct CompanionDeckSeat {
        /// 航海士が向く方角。素体は正面 +Z で組んであり、+π/2 で船首を向く。
        enum Facing: Float {
            case bow = 1.570_796_4
            case bowStarboard = 0.785_398_2
            case port = 3.141_592_7
            case starboard = 0
        }

        let position: SCNVector3
        let role: CompanionDeckRole
        let facing: Facing
    }

    /// 甲板に並べる一人ぶん。参加順から確定した役割だけを渡す。
    struct CompanionDeckMember: Equatable {
        let id: String
        let role: CompanionDeckRole

        init(id: String, role: CompanionDeckRole) {
            self.id = id
            self.role = role
        }
    }

    /// 役割ごとの席は固定。同じ役割が重複して届いても一人だけを描く。
    static func companionDeckSeating(
        for members: [CompanionDeckMember]
    ) -> [(id: String, seat: CompanionDeckSeat)] {
        var seating: [(id: String, seat: CompanionDeckSeat)] = []
        var occupiedRoles: Set<CompanionDeckRole> = []
        for member in members {
            guard occupiedRoles.insert(member.role).inserted else { continue }
            seating.append((member.id, companionDeckSeat(for: member.role)))
        }
        return seating
    }

    // MARK: - 船の質感

    /// USDZ が静水面に浮くときの、船体ローカル座標での喫水線。
    private static let authoredBoatWaterline: Float = 0.07

    private struct BoatSurfaceProfile {
        let roughness: CGFloat?
        let metalness: CGFloat?
        let clearCoat: (amount: CGFloat, roughness: CGFloat)
        let ambientOcclusion: CGFloat
        let detail: (scale: Float, strength: Float, roughness: Float, color: Float)
        let isWettable: Bool

        init(
            roughness: CGFloat?,
            metalness: CGFloat? = 0,
            clearCoat: (amount: CGFloat, roughness: CGFloat) = (0, 0.8),
            ambientOcclusion: CGFloat = 0.96,
            detail: (scale: Float, strength: Float, roughness: Float, color: Float)
                = (1, 0, 0, 0),
            isWettable: Bool = false
        ) {
            self.roughness = roughness
            self.metalness = metalness
            self.clearCoat = clearCoat
            self.ambientOcclusion = ambientOcclusion
            self.detail = detail
            self.isWettable = isWettable
        }
    }

    /// USDZ 側の材質名を「何でできているか」へまとめる。
    /// 船を追加しても、名前に意味が入っていれば同じ光の中に揃う。
    private enum BoatSurfaceKind: Float {
        case generic = 0
        case paint = 1
        case varnishedWood = 2
        case weatheredWood = 3
        case sailcloth = 4
        case rope = 5
        case iron = 6
        case polishedMetal = 7
        case stone = 8
        case organic = 9
        case glass = 10
        case glow = 11
        case bone = 12

        static func resolve(_ identity: String) -> Self {
            if identity.contains("glow") { return .glow }
            if identity.contains("glass") { return .glass }
            if identity.contains("mainsail")
                || identity.contains("boatjib")
                || identity.contains("sailpatch")
                || identity.contains("flag") {
                return .sailcloth
            }
            if identity.contains("rope") { return .rope }
            if identity.contains("brass") || identity.contains("gold") {
                return .polishedMetal
            }
            if identity.contains("iron") || identity.contains("metal") {
                return .iron
            }
            if identity.contains("stone") { return .stone }
            if identity.contains("leaf") || identity.contains("bloom") {
                return .organic
            }
            if identity.contains("bone") { return .bone }
            if identity.contains("pirate")
                && (identity.contains("hull")
                    || identity.contains("deck")
                    || identity.contains("strake")
                    || identity.contains("bulwark")
                    || identity.contains("tar")) {
                return .weatheredWood
            }
            if identity.contains("wood") || identity.contains("boatdeck") {
                return .varnishedWood
            }
            if identity.contains("boathull")
                || identity.contains("cockpit")
                || identity.contains("stripe") {
                return .paint
            }
            return .generic
        }

        var profile: BoatSurfaceProfile {
            switch self {
            case .generic:
                BoatSurfaceProfile(roughness: nil, metalness: nil)
            case .paint:
                BoatSurfaceProfile(
                    roughness: 0.42,
                    clearCoat: (0.52, 0.20),
                    detail: (19, 0.010, 0.035, 0.018),
                    isWettable: true
                )
            case .varnishedWood:
                BoatSurfaceProfile(
                    roughness: 0.68,
                    clearCoat: (0.22, 0.32),
                    detail: (7.5, 0.032, 0.085, 0.060),
                    isWettable: true
                )
            case .weatheredWood:
                BoatSurfaceProfile(
                    roughness: 0.88,
                    ambientOcclusion: 0.82,
                    detail: (6.2, 0.052, 0.080, 0.090),
                    isWettable: true
                )
            case .sailcloth:
                BoatSurfaceProfile(
                    roughness: 0.94,
                    ambientOcclusion: 0.90,
                    detail: (58, 0.004, 0.010, 0.002)
                )
            case .rope:
                BoatSurfaceProfile(
                    roughness: 0.98,
                    ambientOcclusion: 0.82,
                    detail: (22, 0.038, 0.025, 0.065)
                )
            case .iron:
                BoatSurfaceProfile(
                    roughness: 0.62,
                    metalness: 0.38,
                    detail: (17, 0.022, 0.090, 0.030),
                    isWettable: true
                )
            case .polishedMetal:
                BoatSurfaceProfile(
                    roughness: 0.36,
                    metalness: 0.70,
                    clearCoat: (0.18, 0.18),
                    detail: (25, 0.010, 0.055, 0.018),
                    isWettable: true
                )
            case .stone:
                BoatSurfaceProfile(
                    roughness: 0.94,
                    ambientOcclusion: 0.82,
                    detail: (9, 0.050, 0.060, 0.075),
                    isWettable: true
                )
            case .organic:
                BoatSurfaceProfile(
                    roughness: 0.86,
                    ambientOcclusion: 0.90,
                    detail: (13, 0.016, 0.055, 0.040)
                )
            case .glass:
                BoatSurfaceProfile(
                    roughness: 0.16,
                    clearCoat: (0.88, 0.08)
                )
            case .glow:
                BoatSurfaceProfile(roughness: 0.24)
            case .bone:
                BoatSurfaceProfile(
                    roughness: 0.82,
                    detail: (12, 0.020, 0.040, 0.040),
                    isWettable: true
                )
            }
        }
    }

    /// 同行者の航海士。港と同じく、遠くの相手は既定の熾火で描く。
    /// ノード名は自分の航海士(`navigator`)と必ず変える。同じ名前だと、
    /// 甲板の自分を動かすアニメータが仲間の体を掴んでしまう。
    static func makeCompanionNavigator(id: String, role: CompanionDeckRole) -> SCNNode {
        let sailor = PhoenixNavigator.makeNavigatorNode(palette: role.palette)
        sailor.name = "companion-navigator:\(id)"
        sailor.scale = SCNVector3(
            navigatorDeckScale,
            navigatorDeckScale,
            navigatorDeckScale
        )
        return sailor
    }

    /// UV や画像を増やさず、各メッシュの座標に微細凹凸を固定する。
    /// 分岐は材質ごとに一定なので、小さな船では画像テクスチャより転送量が少ない。
    private static let boatSurfaceShader = """
    #pragma arguments
    float uBoatSurfaceKind;
    float uBoatDetailScale;
    float uBoatDetailStrength;
    float uBoatRoughnessVariation;
    float uBoatColorVariation;
    float uBoatWettable;
    float uBoatWaterline;
    float3 uBoatWaterlineNormal;
    float4x4 uBoatLocalToModel;
    float3 uBoatGrainAxis;
    float3 uBoatSeaBounce;
    float3 uBoatSunDirection;
    float3 uBoatSunColor;
    #pragma body
    float3 localP = (scn_node.inverseModelViewTransform
        * float4(_surface.position, 1.0)).xyz;
    // USDZ submeshes do not share an origin (the cockpit and fittings are
    // translated children). Bring every fragment into one hull coordinate
    // space before evaluating the common water plane.
    float3 boatP = (uBoatLocalToModel * float4(localP, 1.0)).xyz;
    float3 p = localP * uBoatDetailScale;
    float height = 0.0;

    if (uBoatSurfaceKind > 1.5 && uBoatSurfaceKind < 3.5) {
        // 長辺に沿う年輪と細い導管。マストでも船体でも流れが揃う。
        float along = dot(p, uBoatGrainAxis);
        float3 acrossP = p - uBoatGrainAxis * along;
        float across = length(acrossP);
        height = sin(along * 1.18 + sin(across * 0.71) * 1.55) * 0.62
            + sin(along * 4.7 + across * 0.38) * 0.21;
    } else if (uBoatSurfaceKind > 3.5 && uBoatSurfaceKind < 4.5) {
        // 帆布の縦糸と横糸。大きなシワは別の頂点シェーダが担う。
        // 縦横の正弦波をそのまま表示すると縞や市松に見える。
        // 周期が合わない三方向を重ね、布の粗さだけを残す。
        height = sin(dot(p, float3(0.73, 1.19, 0.41))) * 0.36
            + sin(dot(p, float3(1.37, -0.52, 0.91))) * 0.23
            + sin(dot(p, float3(-0.61, 0.83, 1.43))) * 0.17;
    } else if (uBoatSurfaceKind > 4.5 && uBoatSurfaceKind < 5.5) {
        float twist = dot(p, uBoatGrainAxis);
        height = sin(twist * 1.45 + length(p - uBoatGrainAxis * twist) * 2.6) * 0.72;
    } else if (uBoatSurfaceKind > 5.5 && uBoatSurfaceKind < 7.5) {
        // 鍛造金属のごく小さな槌目。
        height = sin(p.x * 1.13 + p.z * 0.77)
            * sin(p.y * 1.37 - p.z * 0.83) * 0.42;
    } else if (uBoatSurfaceKind > 7.5 && uBoatSurfaceKind < 8.5) {
        height = sin(p.x * 0.73 + sin(p.z * 0.61) * 1.4) * 0.46
            + sin(p.y * 1.51 - p.x * 0.37) * 0.25;
    } else if (uBoatSurfaceKind > 0.5 && uBoatSurfaceKind < 1.5) {
        // 塗膜のオレンジピールは強く出さず、ハイライトだけを割る。
        height = sin(p.x * 1.71 + p.y * 1.23) * sin(p.z * 1.57 - p.y) * 0.28;
    } else if (uBoatSurfaceKind > 8.5 && uBoatSurfaceKind < 9.5) {
        height = sin(p.x * 0.91 + p.z * 1.19) * sin(p.y * 0.83 - p.x) * 0.34;
    } else if (uBoatSurfaceKind > 11.5 && uBoatSurfaceKind < 12.5) {
        height = sin(p.x * 0.82 + p.y * 0.37) * sin(p.z * 0.91 - p.y * 0.28) * 0.29;
    }

    // 小さく映るときは糸や導管がピクセルより細くなる。そのまま残すと
    // 帆が等間隔の縞模様に見えるため、画面上の微分でミップ相当の減衰をかける。
    float detailFootprint = max(length(dfdx(p)), length(dfdy(p)));
    float detailVisibility = 1.0 - smoothstep(0.12, 0.58, detailFootprint);
    height *= detailVisibility;

    float3 normal = normalize(_surface.normal);
    if (uBoatDetailStrength > 0.0) {
        // 高さの画面微分から接線空間を復元。UV がない USDZ でも泳がない。
        float3 dpdx = dfdx(_surface.position);
        float3 dpdy = dfdy(_surface.position);
        float3 dpdyPerp = cross(dpdy, normal);
        float3 dpdxPerp = cross(normal, dpdx);
        float determinant = dot(dpdx, dpdyPerp);
        float3 gradient = dpdyPerp * dfdx(height) + dpdxPerp * dfdy(height);
        normal = normalize(
            max(abs(determinant), 0.00001) * normal
                - copysign(uBoatDetailStrength, determinant) * gradient
        );
        _surface.normal = normal;
        _surface.roughness = clamp(
            _surface.roughness + height * uBoatRoughnessVariation,
            0.06,
            1.0
        );
        _surface.diffuse.rgb *= 1.0 + height * uBoatColorVariation;
    }

    float3 viewDirection = normalize(_surface.view);
    float3 sunDirection = normalize(
        (scn_frame.viewTransform * float4(uBoatSunDirection, 0.0)).xyz
    );
    if (uBoatSurfaceKind > 3.5 && uBoatSurfaceKind < 4.5) {
        // 表からの反射だけでなく、太陽と視点が帆の反対側にあるときは
        // 布の糸の間から暖色が薄く抜ける。発光板にならないよう透過は逆光時だけに絞る。
        float viewSide = dot(normal, viewDirection);
        float lightSide = dot(normal, sunDirection);
        float backlit = smoothstep(0.05, 0.62, -viewSide * lightSide);
        float threadOpenings = 0.72 + height * 0.32;
        _surface.emission.rgb += uBoatSunColor
            * (backlit * threadOpenings * 0.075);
        _surface.roughness = mix(_surface.roughness, 0.82, backlit * 0.16);
    }

    // 水没部、水面の細い鏡面リム、上に残る飛沫跡を分ける。
    // 広いグラデーションにすると船体全体が灰色に見えるため、境界は海面付近へ絞る。
    float lineBreakup = sin(boatP.x * 7.1 + sin(boatP.z * 10.9) * 0.82) * 0.014
        + sin(boatP.z * 18.7 - boatP.x * 3.4) * 0.006;
    float brokenLine = uBoatWaterline + lineBreakup;
    float waterlineDistance = dot(
        boatP,
        normalize(uBoatWaterlineNormal)
    ) - brokenLine;
    float belowSurface = uBoatWettable
        * (1.0 - smoothstep(-0.025, 0.055, waterlineDistance));
    float waterlineRim = uBoatWettable
        * (1.0 - smoothstep(0.012, 0.060, abs(waterlineDistance)));

    // 飛沫跡は水面直上にまばらに残し、横一文字の塗装に見せない。
    float splashNoise = sin(boatP.x * 15.1 + boatP.z * 8.7)
        * sin(boatP.z * 13.3 - boatP.x * 5.9);
    float splashTop = 0.055 + (splashNoise * 0.5 + 0.5) * 0.075;
    float splashDamp = uBoatWettable
        * smoothstep(-0.010, 0.018, waterlineDistance)
        * (1.0 - smoothstep(splashTop - 0.020, splashTop + 0.025, waterlineDistance))
        * smoothstep(-0.30, 0.28, splashNoise);
    float wetColorWeight = clamp(belowSurface * 0.42 + splashDamp * 0.13, 0.0, 0.46);
    float3 wetColor = _surface.diffuse.rgb * float3(0.52, 0.68, 0.66)
        + uBoatSeaBounce * 0.035;
    _surface.diffuse.rgb = mix(_surface.diffuse.rgb, wetColor, wetColorWeight);

    float wetSheen = clamp(belowSurface * 0.88 + waterlineRim + splashDamp * 0.42, 0.0, 1.0);
    _surface.roughness = mix(_surface.roughness, 0.11, wetSheen * 0.88);
    _surface.clearCoat = max(_surface.clearCoat, wetSheen * 0.92);
    _surface.clearCoatRoughness = mix(_surface.clearCoatRoughness, 0.045, wetSheen);
    _surface.clearCoatNormal = normal;

    // SceneKit の単色環境光だけでは船体と海が別々に見えるため、同じ時間帯の
    // 空・太陽・海を半球反射として戻す。材質の粗さと濡れは既存 PBR 値をそのまま使う。
    float3 worldUp = normalize(
        (scn_frame.viewTransform * float4(0.0, 1.0, 0.0, 0.0)).xyz
    );
    float upFacing = dot(normal, worldUp);
    float fresnel = pow(
        1.0 - clamp(dot(normal, viewDirection), 0.0, 1.0),
        4.0
    );
    float gloss = clamp(1.0 - _surface.roughness, 0.0, 1.0);
    float reflectionResponse = 0.16;
    if (uBoatSurfaceKind > 0.5 && uBoatSurfaceKind < 1.5) {
        reflectionResponse = 0.70;
    } else if (uBoatSurfaceKind > 1.5 && uBoatSurfaceKind < 2.5) {
        reflectionResponse = 0.48;
    } else if (uBoatSurfaceKind > 5.5 && uBoatSurfaceKind < 7.5) {
        reflectionResponse = 0.92;
    } else if (uBoatSurfaceKind > 9.5 && uBoatSurfaceKind < 10.5) {
        reflectionResponse = 1.0;
    } else if (uBoatSurfaceKind > 3.5 && uBoatSurfaceKind < 5.5) {
        reflectionResponse = 0.09;
    }

    float skyLobe = smoothstep(-0.28, 0.72, upFacing);
    float seaLobe = smoothstep(-0.18, 0.78, -upFacing);
    float environmentStrength = reflectionResponse
        * (0.010 + gloss * 0.030 + fresnel * 0.032);
    _surface.emission.rgb += uBoatSunColor
        * (skyLobe * environmentStrength);
    _surface.emission.rgb += uBoatSeaBounce
        * (seaLobe * environmentStrength * 0.82
            + belowSurface * 0.018
            + waterlineRim * 0.012);

    // 直接光の鏡面に、遠景の太陽と同じ色の小さな芯だけを足す。
    // 粗い木や布では広がって消え、金属・塗膜・濡れ面だけに残る。
    float reflectedSun = clamp(
        dot(reflect(-sunDirection, normal), viewDirection),
        0.0,
        1.0
    );
    float sunGlint = pow(reflectedSun, mix(18.0, 104.0, gloss))
        * smoothstep(-0.04, 0.22, dot(normal, sunDirection));
    _surface.emission.rgb += uBoatSunColor
        * (sunGlint * gloss * reflectionResponse * 0.075);
    """

    private static func styleBoatMaterial(
        _ material: SCNMaterial,
        on node: SCNNode,
        identity: String,
        localToModel: simd_float4x4,
        seaBounce: UInt,
        sunDirection: SCNVector3,
        sunColor: UInt
    ) {
        let surface = BoatSurfaceKind.resolve(identity.lowercased())
        let profile = surface.profile
        material.lightingModel = .physicallyBased
        if let roughness = profile.roughness {
            material.roughness.contents = roughness
        }
        if let metalness = profile.metalness {
            material.metalness.contents = metalness
        }
        material.ambientOcclusion.contents = profile.ambientOcclusion
        material.clearCoat.contents = profile.clearCoat.amount
        material.clearCoatRoughness.contents = profile.clearCoat.roughness

        if surface == .sailcloth {
            material.isDoubleSided = true
        } else if surface == .glow {
            if material.emission.contents == nil {
                material.emission.contents = material.diffuse.contents
                material.emission.intensity = 1.7
            }
        }

        let detail = profile.detail
        let detailMultiplier = MetalRenderingProfile.current.boatSurfaceDetailMultiplier
        var modifiers = material.shaderModifiers ?? [:]
        modifiers[.surface] = boatSurfaceShader
        material.shaderModifiers = modifiers
        material.setValue(NSNumber(value: surface.rawValue), forKey: "uBoatSurfaceKind")
        material.setValue(NSNumber(value: detail.scale), forKey: "uBoatDetailScale")
        material.setValue(
            NSNumber(value: detail.strength * detailMultiplier),
            forKey: "uBoatDetailStrength"
        )
        material.setValue(
            NSNumber(value: detail.roughness * detailMultiplier),
            forKey: "uBoatRoughnessVariation"
        )
        material.setValue(
            NSNumber(value: detail.color * min(detailMultiplier, 1.05)),
            forKey: "uBoatColorVariation"
        )
        material.setValue(
            NSNumber(value: profile.isWettable ? Float(1) : Float(0)),
            forKey: "uBoatWettable"
        )
        material.setValue(NSNumber(value: authoredBoatWaterline), forKey: "uBoatWaterline")
        material.setValue(SCNVector3(0, 1, 0), forKey: "uBoatWaterlineNormal")
        material.setValue(
            NSValue(scnMatrix4: SCNMatrix4(localToModel)),
            forKey: "uBoatLocalToModel"
        )
        material.setValue(longestLocalAxis(of: node), forKey: "uBoatGrainAxis")
        material.setValue(
            HomeIslandOceanEffects.linearColorVector(seaBounce),
            forKey: "uBoatSeaBounce"
        )
        material.setValue(sunDirection, forKey: "uBoatSunDirection")
        material.setValue(
            HomeIslandOceanEffects.linearColorVector(sunColor),
            forKey: "uBoatSunColor"
        )
    }

    /// 船のマテリアルを毎フレーム再探索せず、波と同期する喫水線の書き込み先を集める。
    static func styledBoatMaterials(in root: SCNNode) -> [SCNMaterial] {
        var materials: [SCNMaterial] = []
        root.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? [] {
                guard material.shaderModifiers?[.surface]?.contains("uBoatWaterline") == true,
                      !materials.contains(where: { $0 === material })
                else { continue }
                materials.append(material)
            }
        }
        return materials
    }

    /// CPU側の波面を船モデル座標へ変換し、船体の濡れ境界へ渡す。
    /// 波の高さだけでなく法線も共有するため、ロール・ピッチ中も接触線が傾く。
    static func updateBoatWaterline(
        surface: HomeIslandMarineDynamics.WaveSample,
        buoyancyNode: SCNNode,
        materials: [SCNMaterial]
    ) {
        let worldOrigin = buoyancyNode.simdWorldPosition
        let worldContact = SIMD3<Float>(
            worldOrigin.x,
            surface.worldHeight,
            worldOrigin.z
        )
        let localContact = buoyancyNode.simdConvertPosition(
            worldContact,
            from: nil
        )
        let localNormal = simd_normalize(
            buoyancyNode.simdConvertVector(surface.normal, from: nil)
        )
        let waterline = simd_dot(localContact, localNormal)
            + authoredBoatWaterline
        for material in materials {
            material.setValue(NSNumber(value: waterline), forKey: "uBoatWaterline")
            material.setValue(
                SCNVector3(localNormal.x, localNormal.y, localNormal.z),
                forKey: "uBoatWaterlineNormal"
            )
        }
    }

    private static func longestLocalAxis(of node: SCNNode) -> SCNVector3 {
        let bounds = node.boundingBox
        let spans = [
            bounds.max.x - bounds.min.x,
            bounds.max.y - bounds.min.y,
            bounds.max.z - bounds.min.z,
        ]
        switch spans.indices.max(by: { spans[$0] < spans[$1] }) ?? 0 {
        case 1: return SCNVector3(0, 1, 0)
        case 2: return SCNVector3(0, 0, 1)
        default: return SCNVector3(1, 0, 0)
        }
    }

    /// Blenderソースから出力した完成船。簡易プリミティブを組み直さず、
    /// 船体・甲板・舷縁・索具の形と座標系をそのまま持ち込む。
    ///
    /// どの船を読むかは `parts.shipID` が決める。どのUSDZも帆の材質名と
    /// `Navigator_Anchor` の位置を共有しているので、色替えも甲板の航海士も
    /// 船ごとの分岐なしに動く。
    static func makeBoatModel(
        _ parts: BoatParts,
        seaBounce: UInt = 0x2E7063,
        sunDirection: SCNVector3 = SCNVector3(-0.34, 0.72, 0.60),
        sunColor: UInt = 0xFFF1C7
    ) -> SCNNode {
        let ship = parts.ship
        guard let url = Bundle.main.url(forResource: ship.resourceName, withExtension: "usdz"),
              let importedScene = try? SCNScene(url: url, options: nil) else {
            assertionFailure("\(ship.resourceName).usdz could not be loaded")
            return makeProceduralBoatModel(parts)
        }

        let model = SCNNode()
        model.name = "boatModel"
        for child in importedScene.rootNode.childNodes {
            model.addChildNode(child.clone())
        }

        model.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }
            geometry.materials = geometry.materials.map { source in
                guard let material = source.copy() as? SCNMaterial else {
                    return source
                }
                let materialName = material.name ?? ""
                switch materialName {
                case "LF_BoatHull":
                    material.diffuse.contents = parts.hull
                case "LF_BoatDeck":
                    material.diffuse.contents = parts.hull.scaled(0.72)
                case "LF_BoatMainSail":
                    material.diffuse.contents = parts.sail
                    // 風を受けたときだけ効く。凪の画面では素通り。
                    VoyageSailFlutter.install(on: node, material: material)
                case "LF_BoatJib":
                    material.diffuse.contents = parts.jib
                    VoyageSailFlutter.install(on: node, material: material)
                case "LF_BoatCockpit":
                    // 帆色の選択とは切り離し、船上のアクセントはブランドの
                    // コーラルへ固定する。元モデルのミッドナイト色もここで上書きする。
                    material.diffuse.contents = coral
                case "LF_BoatStripe":
                    node.isHidden = parts.stripe == nil
                    if let stripe = parts.stripe { material.diffuse.contents = stripe }
                case "LF_BoatFlag":
                    node.isHidden = parts.flag == "none"
                    material.diffuse.contents = flagColorFor(parts.flag)
                default:
                    break
                }
                styleBoatMaterial(
                    material,
                    on: node,
                    identity: "\(materialName) \(node.name ?? "")",
                    localToModel: node.simdConvertTransform(
                        matrix_identity_float4x4,
                        to: model
                    ),
                    seaBounce: seaBounce,
                    sunDirection: sunDirection,
                    sunColor: sunColor
                )
                return material
            }
        }
        return model
    }

    /// 読み込み失敗時だけ使う旧簡易船。通常の航海画面では使用しない。
    private static func makeProceduralBoatModel(_ parts: BoatParts) -> SCNNode {
        let model = SCNNode()
        model.name = "boatModel"

        // 船体
        let hullNode = SCNNode(geometry: makeHullGeometry(color: parts.hull))
        hullNode.name = "boatHull"
        // SCNShapeは押し出しが z=0...depth。Webは生成後に-depth/2だけ戻して
        // 船体をマスト中心(z=0)へ揃えるため、同じ補正を入れる。
        hullNode.position.z = -0.25
        model.addChildNode(hullNode)

        // デッキ(少し暗い同系色の薄い蓋 = hull*0.72)
        let deckGeo = SCNCylinder(radius: 1, height: 0.06)
        deckGeo.radialSegmentCount = 14
        deckGeo.firstMaterial = litMaterial(parts.hull.scaled(0.72), roughness: 0.9)
        let deckNode = SCNNode(geometry: deckGeo)
        deckNode.name = "boatDeck"
        deckNode.position = SCNVector3(0.05, 0.47, 0)
        deckNode.scale = SCNVector3(0.82, 1, 0.3)
        model.addChildNode(deckNode)

        // マスト
        let mastGeo = SCNCone(topRadius: 0.035, bottomRadius: 0.028, height: 2.3)
        mastGeo.radialSegmentCount = 8
        mastGeo.firstMaterial = litMaterial(wood, roughness: 0.8)
        let mastNode = SCNNode(geometry: mastGeo)
        mastNode.position = SCNVector3(0.1, 1.42, 0)
        model.addChildNode(mastNode)

        // ブーム+メインセイル(わずかに開いたトリム)
        let rig = SCNNode()
        rig.position = SCNVector3(0.1, 0, 0)
        rig.eulerAngles.y = 0.16
        let boomGeo = SCNCylinder(radius: 0.024, height: 1.15)
        boomGeo.radialSegmentCount = 8
        boomGeo.firstMaterial = litMaterial(wood, roughness: 0.8)
        let boomNode = SCNNode(geometry: boomGeo)
        boomNode.position = SCNVector3(-0.55, 0.68, 0)
        boomNode.eulerAngles.z = .pi / 2
        rig.addChildNode(boomNode)
        let mainNode = SCNNode(geometry: makeSailGeometry(width: 1.0, height: 1.8, bulge: 0.16, shear: 0, color: parts.sail))
        mainNode.name = "boatSailMain"
        mainNode.position = SCNVector3(0, 0.72, 0)
        rig.addChildNode(mainNode)
        model.addChildNode(rig)

        // ジブ(前帆): 舳先からマスト頂へ斜めのラフ。独立色。
        let jibNode = SCNNode(geometry: makeSailGeometry(width: 0.72, height: 1.5, bulge: 0.1, shear: 0.92, color: parts.jib))
        jibNode.name = "boatSailJib"
        jibNode.position = SCNVector3(1.1, 0.62, 0)
        jibNode.eulerAngles.y = 0.12
        model.addChildNode(jibNode)

        // 船体のライン(喫水近くの細い帯 = Torus)。none なら省略。
        if let stripe = parts.stripe {
            let torus = SCNTorus(ringRadius: 1, pipeRadius: 0.05)
            torus.ringSegmentCount = 40
            torus.pipeSegmentCount = 8
            torus.firstMaterial = litMaterial(stripe, roughness: 0.85)
            let stripeNode = SCNNode(geometry: torus)
            stripeNode.name = "boatStripe"
            stripeNode.position = SCNVector3(0.06, 0.2, 0)
            stripeNode.eulerAngles.x = .pi / 2
            stripeNode.scale = SCNVector3(0.93, 0.47, 0.5)
            model.addChildNode(stripeNode)
        }

        // 旗(マスト頂ではためく)。none 以外のとき。
        if ["pennant", "swallow", "kraken"].contains(parts.flag) {
            let flagColor = flagColorFor(parts.flag)
            let flagGroup = SCNNode()
            flagGroup.name = "boatFlag"
            flagGroup.position = SCNVector3(0.1, 2.34, 0)
            let flagNode = SCNNode(geometry: makeFlagGeometry(kind: parts.flag, color: flagColor))
            flagGroup.addChildNode(flagNode)
            // 海獣の旗には returnOrange の小さな目を添える(2Dの図案と同じ)。
            if parts.flag == "kraken" {
                let eye = SCNShape(path: UIBezierPath(ovalIn: CGRect(x: -0.028, y: -0.028, width: 0.056, height: 0.056)), extrusionDepth: 0)
                eye.firstMaterial = unlitMaterial(UIColor(rgb: 0xF5822A))
                let eyeNode = SCNNode(geometry: eye)
                eyeNode.position = SCNVector3(-0.12, 0.11, 0.002)
                flagGroup.addChildNode(eyeNode)
            }
            model.addChildNode(flagGroup)
        }

        return model
    }

    /// 旗の配色(Web FLAG_COLORS)。
    static func flagColorFor(_ flag: String) -> UIColor {
        switch flag {
        case "pennant": return UIColor(rgb: 0xF5822A)  // returnOrange
        case "swallow": return UIColor(rgb: 0xF0997B)  // coral
        default: return UIColor(rgb: 0x1A1130)          // kraken = midnight
        }
    }

    // MARK: - ステップの小島(航路に浮かぶ低ポリの島。巡っていく)

    static let verdant = UIColor(rgb: 0x5DCAA5)   // 達成した島の緑
    static let isletRock = UIColor(rgb: 0x7A6B57) // 小岩

    /// Blenderで制作した中継島の原型。読み込みは一度だけにし、各ステップで
    /// USDZの解析を繰り返さない。各島ではジオメトリと素材を独立させる。
    private static let stepIsletTemplate: SCNNode? = {
        guard let url = Bundle.main.url(forResource: "voyage_step_islet", withExtension: "usdz"),
              let scene = try? SCNScene(url: url, options: nil)
        else { return nil }
        let template = SCNNode()
        template.name = "voyage_step_islet_template"
        for child in scene.rootNode.childNodes {
            template.addChildNode(child.clone())
        }
        return template
    }()

    /// USDZを島ごとの独立インスタンスにする。旧素材も読めるよう状態色は互換で残す。
    private static func makeStepIsletAsset(index: Int, done: Bool) -> SCNNode? {
        guard let asset = stepIsletTemplate?.clone() else { return nil }
        asset.name = "step_islet_asset"
        asset.scale = SCNVector3(0.86, 0.86, 0.86)
        asset.eulerAngles.y = Float(index % 7) * 0.19 - 0.34

        asset.enumerateChildNodes { node, _ in
            guard let sourceGeometry = node.geometry,
                  let geometry = sourceGeometry.copy() as? SCNGeometry
            else { return }
            node.geometry = geometry
            geometry.materials = sourceGeometry.materials.map { sourceMaterial in
                guard let material = sourceMaterial.copy() as? SCNMaterial else {
                    return sourceMaterial
                }
                let identity = "\(material.name ?? "") \(node.name ?? "")"
                let color: UIColor
                switch identity {
                case let name where name.contains("LF_StepGrass"):
                    color = done ? verdant : UIColor(rgb: 0x607272)
                case let name where name.contains("LF_StepMoss"):
                    color = done ? UIColor(rgb: 0x83B986) : UIColor(rgb: 0x667D77)
                case let name where name.contains("LF_StepSoil"):
                    color = done ? UIColor(rgb: 0x405C48) : UIColor(rgb: 0x2D4547)
                case let name where name.contains("LF_StepBeach"):
                    color = beach
                case let name where name.contains("LF_StepPath"):
                    color = done ? sand : UIColor(rgb: 0xA79C80)
                case let name where name.contains("LF_StepMarker"):
                    color = done ? returnOrange : UIColor(rgb: 0x756E61)
                default:
                    return material
                }
                material.diffuse.contents = color
                material.lightingModel = .physicallyBased
                material.roughness.contents = 0.96
                return material
            }
        }
        return asset
    }

    /// ステップ1つ=航路に浮かぶ「島」。目標地点なので存在感を持たせる(船と釣り合う大きさ)。
    /// 島本体はどの状態でも静かな砂州。達成時だけ小さな旗と灯を添える。
    /// `doneAt` を渡すと、達成した日付を島の上に小さなオレンジ文字で掲げる。
    static func makeStepIslet(index: Int, total: Int, done: Bool, doneAt: Date? = nil) -> SCNNode {
        let group = SCNNode()
        group.name = "step_\(index)"
        let hillH: Float
        if let islet = makeStepIsletAsset(index: index, done: done) {
            group.addChildNode(islet)
            hillH = 0.36
        } else {
            // リソース欠損時にも航路を失わない、最小限の低ポリ島。
            let beachGeo = SCNCone(topRadius: 0.56, bottomRadius: 0.74, height: 0.09)
            beachGeo.radialSegmentCount = 9
            beachGeo.firstMaterial = litMaterial(beach, roughness: 0.95)
            let beachNode = SCNNode(geometry: beachGeo)
            beachNode.position = SCNVector3(0, 0.045, 0)
            group.addChildNode(beachNode)

            hillH = done ? 0.72 : 0.52
            let hillGeo = SCNCone(topRadius: 0, bottomRadius: 0.46, height: CGFloat(hillH))
            hillGeo.radialSegmentCount = 6
            hillGeo.firstMaterial = litMaterial(done ? verdant : sand, roughness: 0.9)
            let hillNode = SCNNode(geometry: hillGeo)
            hillNode.position = SCNVector3(-0.05, 0.09 + hillH / 2, 0)
            group.addChildNode(hillNode)
        }

        if done {
            // 制覇の証として、丘の頂に小さなペナントを立てる。
            group.addChildNode(makeStepFlag(hillHeight: hillH))

            // 達成した島には、浜に温かい灯(たき火/ランタン)。HDRでやわらかくにじむ。
            let glowGeo = SCNSphere(radius: 0.085)
            glowGeo.segmentCount = 10
            let gm = SCNMaterial()
            gm.lightingModel = .physicallyBased
            gm.diffuse.contents = ember
            gm.emission.contents = ember
            gm.emission.intensity = 1.5
            gm.roughness.contents = 0.5
            gm.metalness.contents = 0.0
            glowGeo.firstMaterial = gm
            let glowNode = SCNNode(geometry: glowGeo)
            glowNode.name = "step_glow"
            glowNode.position = SCNVector3(0.16, 0.17, 0.5)
            group.addChildNode(glowNode)

            // いつ辿り着いたかを、島の上に小さなオレンジ文字で残す。
            if let doneAt {
                group.addChildNode(makeDateLabel(text: LF.dayMonth(doneAt), y: hillH + 0.43))
            }
        }

        // 一つのステップにつき必ず一島。前後へ緩やかに散らして群島感を出す。
        let progress = Float(index + 1) / Float(total + 1)
        let x = xStart + pow(progress, routeApproachPower) * (xEnd - xStart)
        let lane = Float(index % 3) - 1
        // 編集パネルに隠れにくいようカメラ側へ寄せず、目的地と同じ水平線側へ置く。
        let z: Float = -0.62 + lane * 0.58
        group.position = SCNVector3(x, 0, z)
        return group
    }

    /// 制覇の旗。丘の頂で主張しすぎない、小さな船旗(帰帆色)。
    private static func makeStepFlag(hillHeight: Float) -> SCNNode {
        let flag = SCNNode()
        flag.name = "step_flag"
        flag.position = SCNVector3(-0.05, 0.09 + hillHeight, 0)

        let poleH: Float = 0.31
        let poleGeo = SCNCylinder(radius: 0.012, height: CGFloat(poleH))
        poleGeo.radialSegmentCount = 8
        poleGeo.firstMaterial = litMaterial(wood, roughness: 0.9, fogged: false)
        let pole = SCNNode(geometry: poleGeo)
        pole.position = SCNVector3(0, poleH / 2, 0)
        flag.addChildNode(pole)

        // 小さな船旗。燕尾の切り込みで、印象を軽くする。
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 0.1))
        path.addLine(to: CGPoint(x: 0.18, y: 0.1))
        path.addLine(to: CGPoint(x: 0.14, y: 0.05))
        path.addLine(to: CGPoint(x: 0.18, y: 0))
        path.close()
        let clothGeo = SCNShape(path: path, extrusionDepth: 0.003)
        clothGeo.firstMaterial = unlitMaterial(returnOrange)
        let cloth = SCNNode(geometry: clothGeo)
        cloth.name = "step_flag_cloth"
        cloth.position = SCNVector3(0.01, poleH - 0.11, 0)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .Y
        cloth.constraints = [billboard]
        flag.addChildNode(cloth)
        return flag
    }

    /// 3D空間に浮かぶ小さな文字板(常にカメラを向く)。達成日の記録に使う。
    static func makeDateLabel(text: String, y: Float) -> SCNNode {
        let font = UIFont.systemFont(ofSize: 44, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: returnOrange]
        let size = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 18
        let w = size.width + pad * 2
        let h = size.height + pad
        let image = UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { _ in
            (text as NSString).draw(at: CGPoint(x: pad, y: pad / 2), withAttributes: attrs)
        }
        let worldH: CGFloat = 0.28
        let plane = SCNPlane(width: worldH * (w / h), height: worldH)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        plane.firstMaterial = m
        let node = SCNNode(geometry: plane)
        node.name = "step_date"
        node.position = SCNVector3(0, y, 0)
        node.constraints = [SCNBillboardConstraint()]
        return node
    }

    // MARK: - 光・カメラ

    static func makeLights() -> [SCNNode] {
        // 月光: sand の directional+暖色の弱い ambient+海色の弱い fill(Web と同構成)。
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(rgb: 0xFFE9C8)
        ambient.intensity = 520
        let ambientNode = SCNNode()
        ambientNode.light = ambient

        let key = SCNLight()
        key.type = .directional
        key.color = sand
        key.intensity = 1050
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(-6, 8, -5)
        keyNode.look(at: SCNVector3(0, 0, 0))

        let fill = SCNLight()
        fill.type = .directional
        fill.color = UIColor(rgb: 0x5DCAA5)
        fill.intensity = 220
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.position = SCNVector3(5, 3, 6)
        fillNode.look(at: SCNVector3(0, 0, 0))

        return [ambientNode, keyNode, fillNode]
    }

    private static func makeCamera(position: SCNVector3, target: SCNVector3, fov: CGFloat) -> SCNNode {
        let cam = SCNCamera()
        cam.fieldOfView = fov
        cam.zNear = 0.1
        cam.zFar = 200
        // three.js 既定の HDR + フィルミックトーンマッピングに相当(リニア色管理+ハイライト圧縮)。
        // Web は EffectComposer/Bloom を使っていないので、ブルームは差さない(切る)。
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = 0
        cam.bloomIntensity = 0
        let node = SCNNode()
        node.name = "camera"
        node.camera = cam
        node.position = position
        node.look(at: target)
        return node
    }

    // MARK: - シーン(上陸)

    /// 航海中と同じ海・船・航海士・島を、浜へ到着した瞬間の構図へ組み直す。
    /// 静止画へ切り替えず、航海の世界がそのまま上陸記録へ続く。
    static func makeLandfallScene(
        nativeMetalRollout: MetalOceanProgram.RolloutScene
    ) -> SCNScene {
        let oceanAppearance = makeVoyagingOceanAppearance(
            timeOfDay: .night,
            palette: .voyagingNight
        )
        let scene = SCNScene()
        scene.background.contents = nightBG
        scene.rootNode.addChildNode(
            HomeIslandOceanEffects.makeScene(
                layout: .timerVoyage,
                appearance: oceanAppearance,
                nativeMetalRollout: nativeMetalRollout
            ).root
        )
        scene.rootNode.addChildNode(makeStars(count: 560))
        scene.rootNode.addChildNode(makeMoon(position: SCNVector3(-5.2, 3.6, -17)))
        let islandPosition = SCNVector3(1.65, 0, -0.72)
        let island = makeIsland(
            position: islandPosition,
            scale: SCNVector3(1.16, 1.16, 1.16),
            oceanAppearance: oceanAppearance
        )
        island.name = "landfallIsland"

        // 到着後の航海士。アニメーション中は船上の航海士を表示し、
        // 浜へ着いた瞬間にこちらへ自然にクロスフェードする。
        let shoreX: Float = -2.10
        let shoreZ: Float = 0.76
        let shoreRadius = islandNormalizedRadius(x: shoreX, z: shoreZ)
        let shoreNavigator = PhoenixNavigator.makeNavigatorNode()
        shoreNavigator.name = "landfallShoreNavigator"
        shoreNavigator.position = SCNVector3(
            shoreX,
            0.13 + grandIslandHeight(x: shoreX, z: shoreZ, radius: shoreRadius),
            shoreZ
        )
        shoreNavigator.scale = SCNVector3(0.46, 0.46, 0.46)
        shoreNavigator.eulerAngles.y = -.pi * 0.43
        island.addChildNode(shoreNavigator)
        scene.rootNode.addChildNode(island)

        let travel = SCNNode()
        travel.name = "landfallTravel"
        travel.position = SCNVector3(-2.15, 0.025, 0.66)
        travel.eulerAngles.y = 0.10
        travel.scale = SCNVector3(0.54, 0.54, 0.54)
        let bob = SCNNode()
        bob.name = "landfallBoatBob"
        let boat = makeBoatModel(
            BoatCustomization.currentParts,
            seaBounce: oceanAppearance.sea
        )
        attachNavigator(to: boat)
        if let boatNavigator = boat.childNode(withName: "navigator", recursively: true) {
            boatNavigator.name = "landfallBoatNavigator"
            boatNavigator.opacity = 0
        }
        bob.addChildNode(boat)
        travel.addChildNode(bob)
        scene.rootNode.addChildNode(travel)

        makeLights().forEach { scene.rootNode.addChildNode($0) }

        let target = SCNNode()
        target.name = "landfallCameraTarget"
        target.position = SCNVector3(0.15, 1.65, -0.18)
        scene.rootNode.addChildNode(target)

        let camera = makeCamera(
            position: SCNVector3(-7.35, 4.75, 13.1),
            target: target.position,
            fov: 43
        )
        camera.camera?.contrast = 0.08
        camera.camera?.saturation = 1.04
        camera.camera?.screenSpaceAmbientOcclusionIntensity = 0.58
        camera.camera?.screenSpaceAmbientOcclusionRadius = 1.35
        camera.camera?.screenSpaceAmbientOcclusionBias = 0.025
        let look = SCNLookAtConstraint(target: target)
        look.isGimbalLockEnabled = true
        camera.constraints = [look]
        scene.rootNode.addChildNode(camera)
        return scene
    }

    // MARK: - シーン(航海ホーム / Web VoyagingWorld)

    /// 10羽の海鳥の群れ。各ノードの軌道値はKVCでアニメータへ渡す。
    static func makeVoyagingGulls() -> SCNNode {
        let root = SCNNode()
        root.name = "gulls"
        let flock: [(r: Float, y: Float, omega: Float, scale: Float, flap: Float, phase: Float)] = [
            (4.2, 2.3, 0.085, 0.15, 2.1, 0.0), (5.0, 2.8, -0.065, 0.14, 1.7, 0.8),
            (4.6, 2.0, 0.11, 0.16, 2.5, 1.6), (5.6, 3.2, 0.055, 0.13, 1.6, 2.4),
            (3.9, 2.6, -0.1, 0.17, 2.3, 3.2), (6.0, 2.2, 0.07, 0.12, 1.9, 4.0),
            (5.2, 3.5, -0.05, 0.14, 1.5, 4.8), (4.4, 3.0, 0.095, 0.16, 2.2, 5.6),
            (6.6, 2.5, -0.045, 0.12, 1.8, 6.1), (3.6, 3.3, 0.125, 0.18, 2.6, 2.0)
        ]
        for (index, gull) in flock.enumerated() {
            let bird = makeVoyagingGullModel()
            bird.name = "gull_\(index)"
            bird.scale = SCNVector3(gull.scale, gull.scale, gull.scale)
            root.addChildNode(bird)
        }
        return root
    }

    /// 遠景でも「三角の紙片」に見えない最小構成。翼は直接の子にし、
    /// 航海・プロローグ・サインインの各アニメータが同じ名前で羽ばたかせる。
    private static func makeVoyagingGullModel() -> SCNNode {
        let bird = SCNNode()
        let feather = UIColor(rgb: 0xE8E4D4)
        let underside = UIColor(rgb: 0xF8F5E9)
        let wingTip = UIColor(rgb: 0x52636A)

        let bodyGeometry = SCNCapsule(capRadius: 0.13, height: 0.62)
        bodyGeometry.radialSegmentCount = 8
        bodyGeometry.capSegmentCount = 3
        bodyGeometry.firstMaterial = litMaterial(feather, roughness: 0.92)
        let body = SCNNode(geometry: bodyGeometry)
        body.name = "body"
        body.eulerAngles.x = .pi / 2
        body.scale = SCNVector3(0.90, 1, 0.82)
        bird.addChildNode(body)

        let headGeometry = SCNSphere(radius: 0.155)
        headGeometry.segmentCount = 8
        headGeometry.firstMaterial = litMaterial(underside, roughness: 0.90)
        let head = SCNNode(geometry: headGeometry)
        head.name = "head"
        head.position = SCNVector3(0, 0.035, -0.35)
        head.scale.y = 0.82
        bird.addChildNode(head)

        let beakGeometry = SCNCone(topRadius: 0, bottomRadius: 0.065, height: 0.20)
        beakGeometry.radialSegmentCount = 6
        beakGeometry.firstMaterial = litMaterial(UIColor(rgb: 0xD8A24B), roughness: 0.82)
        let beak = SCNNode(geometry: beakGeometry)
        beak.name = "beak"
        beak.position = SCNVector3(0, 0.02, -0.51)
        beak.eulerAngles.x = -.pi / 2
        bird.addChildNode(beak)

        for wingIndex in 0..<2 {
            let wing = SCNNode(geometry: makeVoyagingGullWing(
                feather: feather,
                tip: wingTip
            ))
            wing.name = wingIndex == 0 ? "leftWing" : "rightWing"
            wing.position.y = 0.055
            wing.scale.x = wingIndex == 0 ? -1 : 1
            wing.eulerAngles.z = wingIndex == 0 ? -0.22 : 0.22
            bird.addChildNode(wing)
        }

        let tailVertices = [
            SCNVector3(-0.10, 0, 0.24), SCNVector3(-0.22, 0.01, 0.55),
            SCNVector3(0, 0, 0.43), SCNVector3(0.22, 0.01, 0.55),
            SCNVector3(0.10, 0, 0.24),
        ]
        var tailIndices: [UInt32] = [0, 1, 2, 0, 2, 4, 4, 2, 3]
        let tailData = Data(
            bytes: &tailIndices,
            count: tailIndices.count * MemoryLayout<UInt32>.size
        )
        let tailElement = SCNGeometryElement(
            data: tailData,
            primitiveType: .triangles,
            primitiveCount: tailIndices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        let tailGeometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: tailVertices)],
            elements: [tailElement]
        )
        tailGeometry.firstMaterial = litMaterial(underside, roughness: 0.94, doubleSided: true)
        let tail = SCNNode(geometry: tailGeometry)
        tail.name = "tail"
        tail.position.y = 0.015
        bird.addChildNode(tail)
        return bird
    }

    private static func makeVoyagingGullWing(
        feather: UIColor,
        tip: UIColor
    ) -> SCNGeometry {
        let vertices = [
            SCNVector3(0, 0, 0.02), SCNVector3(0.28, 0.035, -0.17),
            SCNVector3(0.72, 0.075, -0.09), SCNVector3(1.14, 0.02, 0.16),
            SCNVector3(0.73, -0.01, 0.32), SCNVector3(0.26, 0, 0.23),
        ]
        let source = SCNGeometrySource(vertices: vertices)
        func element(_ rawIndices: [UInt32]) -> SCNGeometryElement {
            var indices = rawIndices
            let data = Data(
                bytes: &indices,
                count: indices.count * MemoryLayout<UInt32>.size
            )
            return SCNGeometryElement(
                data: data,
                primitiveType: .triangles,
                primitiveCount: indices.count / 3,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )
        }
        let geometry = SCNGeometry(
            sources: [source],
            elements: [
                element([0, 1, 2, 0, 2, 4, 0, 4, 5]),
                element([2, 3, 4]),
            ]
        )
        geometry.materials = [
            litMaterial(feather, roughness: 0.94, doubleSided: true),
            litMaterial(tip, roughness: 0.90, doubleSided: true),
        ]
        return geometry
    }

    /// Web VoyagingWorld の定数をそのまま使うログイン後の航海ホーム。
    /// Webと同様、航海を始めた時刻ではなく現在の朝・昼・夕・夜を海へ反映する。
    static func makeVoyagingScene(
        showIsland: Bool,
        timeOfDay: AftideHomeTimeOfDay = .night,
        date: Date = .now,
        oceanAppearance customOceanAppearance: HomeIslandOceanEffects.Appearance? = nil,
        boatParts: BoatParts = BoatCustomization.currentParts,
        nativeMetalRollout: MetalOceanProgram.RolloutScene
    ) -> SCNScene {
        let palette = timeOfDay == .night ? AftideHomePalette.voyagingNight : timeOfDay.palette
        let oceanAppearance = customOceanAppearance
            ?? makeVoyagingOceanAppearance(timeOfDay: timeOfDay, palette: palette)
        let scene = SCNScene()
        scene.background.contents = makeVoyagingSkyBackground(
            timeOfDay: timeOfDay,
            palette: palette
        )
        scene.fogColor = UIColor(rgb: palette.fog)
        scene.fogStartDistance = 12
        scene.fogEndDistance = 34
        if palette.stars > 0 {
            scene.rootNode.addChildNode(makeStars(count: palette.stars))
        }

        scene.rootNode.addChildNode(makeVoyagingCelestial(timeOfDay: timeOfDay, date: date))
        let ocean = HomeIslandOceanEffects.makeScene(
            layout: .timerVoyage,
            appearance: oceanAppearance,
            nativeMetalRollout: nativeMetalRollout
        )
        ocean.animatedMaterial.setValue(
            linearRGB(boatParts.hull),
            forKey: "uBoatReflectionColor"
        )
        scene.rootNode.addChildNode(ocean.root)
        scene.rootNode.addChildNode(makeVoyagingGulls())

        if showIsland {
            // Web ApproachingIsland と同じ二重group構造。開始時の距離はアニメータが
            // 経過時間から決め、25分ほどかけて最終位置へ近づける。
            let approach = SCNNode()
            approach.name = "approachingIsland"
            approach.scale = SCNVector3(0.7, 0.7, 0.7)
            approach.addChildNode(makeIsland(oceanAppearance: oceanAppearance))
            scene.rootNode.addChildNode(approach)
        }

        let travel = SCNNode()
        travel.name = "travel"
        travel.eulerAngles.y = 0.1
        travel.scale = SCNVector3(0.55, 0.55, 0.55)
        let bob = SCNNode()
        bob.name = "boatBob"
        let boat = makeBoatModel(
            boatParts,
            seaBounce: oceanAppearance.sea,
            sunDirection: oceanAppearance.sunDirection,
            sunColor: oceanAppearance.sun
        )
        attachNavigator(to: boat)
        bob.addChildNode(boat)
        // しぶきは船体と一緒に上下し、その時間帯の海色と反射色を受け継ぐ。
        bob.addChildNode(
            VoyageBowSpray.makeNode(
                palette: .init(
                    sea: UIColor(rgb: palette.sea),
                    highlight: UIColor(rgb: palette.reflection)
                )
            )
        )
        travel.addChildNode(bob)
        scene.rootNode.addChildNode(travel)

        makeVoyagingLights(timeOfDay: timeOfDay).forEach {
            scene.rootNode.addChildNode($0)
        }
        let camera = makeCamera(
            position: SCNVector3(-5.6, 2.4, 8.6),
            target: SCNVector3(0.8, 1.15, 0),
            fov: 38
        )
        // 海面の発光感は残しつつ、帆・木・金属のハイライトを白飛びさせない。
        camera.camera?.exposureOffset = 0.14
        // タイマーの近景だけ、甲板・航海士・島の接地感を補う。
        // ブルームや被写界深度は輪郭をぼかすため使わず、控えめなAOと色調整に留める。
        camera.camera?.contrast = 0.10
        camera.camera?.saturation = 1.05
        camera.camera?.screenSpaceAmbientOcclusionIntensity = 0.42
        camera.camera?.screenSpaceAmbientOcclusionRadius = 1.25
        camera.camera?.screenSpaceAmbientOcclusionBias = 0.025
        camera.camera?.screenSpaceAmbientOcclusionDepthThreshold = 2.0
        scene.rootNode.addChildNode(camera)
        return scene
    }

    /// 単色の背景では海面が平面に見えるため、天頂から水平線までの
    /// 大気の厚みを小さな手続きテクスチャにする。海の反射と同じ時間帯パレットを使う。
    private static func makeVoyagingSkyBackground(
        timeOfDay: AftideHomeTimeOfDay,
        palette: AftideHomePalette
    ) -> UIImage {
        let sky = UIColor(rgb: palette.sky)
        let fog = UIColor(rgb: palette.fog)
        let reflection = UIColor(rgb: palette.reflection)
        let zenithScale: CGFloat
        let sunX: CGFloat
        switch timeOfDay {
        case .morning:
            zenithScale = 0.82
            sunX = 0.24
        case .day:
            zenithScale = 0.88
            sunX = 0.50
        case .evening:
            zenithScale = 0.72
            sunX = 0.76
        case .night:
            zenithScale = 0.54
            sunX = 0.72
        }
        let upperHaze = mixColor(sky, fog, amount: 0.55)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        return UIGraphicsImageRenderer(
            size: CGSize(width: 192, height: 512),
            format: format
        ).image { renderer in
            let context = renderer.cgContext
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [
                sky.scaled(zenithScale).cgColor,
                sky.cgColor,
                upperHaze.cgColor,
                fog.cgColor,
                fog.cgColor,
                fog.cgColor,
            ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: colors,
                // The default voyage camera places the geometric horizon at
                // roughly 30% of the portrait viewport. Center the dense haze
                // there so the sky and the far rows of water share one color.
                locations: [0, 0.18, 0.245, 0.285, 0.36, 1]
            ) {
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 96, y: 0),
                    end: CGPoint(x: 96, y: 512),
                    options: []
                )
            }

            guard timeOfDay != .night else { return }
            let haloColors = [
                reflection.withAlphaComponent(0.18).cgColor,
                reflection.withAlphaComponent(0.055).cgColor,
                reflection.withAlphaComponent(0).cgColor,
            ] as CFArray
            guard let halo = CGGradient(
                colorsSpace: colorSpace,
                colors: haloColors,
                locations: [0, 0.34, 1]
            ) else { return }
            context.setBlendMode(.screen)
            // Keep the solar bloom in the upper atmosphere. Letting this
            // background-only light cross the geometric horizon brightens the
            // sky without brightening the water and reveals a ruler-straight
            // seam, even when the ocean itself has converged to the fog color.
            context.drawRadialGradient(
                halo,
                startCenter: CGPoint(x: 192 * sunX, y: 92),
                startRadius: 0,
                endCenter: CGPoint(x: 192 * sunX, y: 92),
                endRadius: 78,
                options: []
            )
        }
    }

    private static func mixColor(
        _ lhs: UIColor,
        _ rhs: UIColor,
        amount: CGFloat
    ) -> UIColor {
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
        lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)
        let t = min(max(amount, 0), 1)
        return UIColor(
            red: lr + (rr - lr) * t,
            green: lg + (rg - lg) * t,
            blue: lb + (rb - lb) * t,
            alpha: la + (ra - la) * t
        )
    }

    private static func linearRGB(_ color: UIColor) -> SCNVector3 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linear(_ component: CGFloat) -> Float {
            let value = Float(component)
            return value > 0.04045
                ? powf((value + 0.055) / 1.055, 2.4)
                : value / 12.92
        }
        return SCNVector3(linear(red), linear(green), linear(blue))
    }

    private static func makeVoyagingCelestial(
        timeOfDay: AftideHomeTimeOfDay,
        date: Date
    ) -> SCNNode {
        let palette = timeOfDay == .night ? AftideHomePalette.voyagingNight : timeOfDay.palette
        if timeOfDay == .night {
            let moon = LandfallMoonEffects.makeNode(phase: .current(at: date))
            moon.position = SCNVector3(5.1, 3.3, -5.5)
            moon.scale = SCNVector3(0.4, 0.4, 0.4)
            return moon
        }
        let sphere = SCNSphere(radius: 1.25)
        sphere.segmentCount = 40
        let material = unlitMaterial(UIColor(rgb: palette.reflection))
        material.emission.contents = UIColor(rgb: palette.reflection)
        material.emission.intensity = 0.62
        material.writesToDepthBuffer = false
        sphere.firstMaterial = material
        let node = SCNNode(geometry: sphere)
        node.name = "voyagingSun"
        node.position = voyagingCelestialPosition(for: timeOfDay)
        node.scale = SCNVector3(0.27, 0.27, 0.27)
        node.renderingOrder = -20
        return node
    }

    private static let voyagingLightTarget = SCNVector3(0.8, 1.15, 0)

    private static func voyagingCelestialPosition(
        for timeOfDay: AftideHomeTimeOfDay
    ) -> SCNVector3 {
        SCNVector3(
            timeOfDay == .morning ? -5.2 : (timeOfDay == .day ? 0.8 : 5.1),
            timeOfDay == .day ? 5.1 : (timeOfDay == .evening ? 1.25 : 3.3),
            -5.5
        )
    }

    private static func makeVoyagingOceanAppearance(
        timeOfDay: AftideHomeTimeOfDay,
        palette: AftideHomePalette
    ) -> HomeIslandOceanEffects.Appearance {
        let source = voyagingCelestialPosition(for: timeOfDay)
        let target = voyagingLightTarget
        let strength: Float
        switch timeOfDay {
        case .morning: strength = 0.65
        case .day: strength = 1
        case .evening: strength = 0.55
        case .night: strength = 0.10
        }
        return HomeIslandOceanEffects.Appearance(
            shallow: timeOfDay == .night ? palette.sea : palette.fill,
            sea: palette.sea,
            deep: palette.seaDeep,
            light: palette.reflection,
            sky: palette.sky,
            horizon: palette.fog,
            sun: palette.reflection,
            fog: palette.fog,
            sunDirection: SCNVector3(
                source.x - target.x,
                source.y - target.y,
                source.z - target.z
            ),
            sunStrength: strength
        )
    }

    private static func makeVoyagingLights(
        timeOfDay: AftideHomeTimeOfDay
    ) -> [SCNNode] {
        let palette = timeOfDay == .night ? AftideHomePalette.voyagingNight : timeOfDay.palette
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(rgb: palette.ambient)
        ambient.light?.intensity = timeOfDay == .day ? 620 : 440

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.color = UIColor(rgb: palette.key)
        key.light?.intensity = timeOfDay == .day ? 1_100 : 900
        key.position = voyagingCelestialPosition(for: timeOfDay)
        key.look(at: voyagingLightTarget)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.color = UIColor(rgb: palette.fill)
        fill.light?.intensity = 180
        fill.position = SCNVector3(5, 3, 6)
        fill.look(at: voyagingLightTarget)
        return [ambient, key, fill]
    }

    // MARK: - シーン(装い: 船スタジオ)

    /// 装い専用の夜の海。Web版の Canvas と同じく、船と航海士のどちらを
    /// 表示しても背景・照明・カメラはこの一つの世界を使い続ける。
    static func makeDressStudioWorld(
        nativeMetalRollout: MetalOceanProgram.RolloutScene
    ) -> SCNScene {
        let oceanAppearance = makeVoyagingOceanAppearance(
            timeOfDay: .night,
            palette: .voyagingNight
        )
        let scene = SCNScene()
        scene.background.contents = nightBG
        scene.fogColor = nightBG
        scene.fogStartDistance = 11
        scene.fogEndDistance = 30
        scene.rootNode.addChildNode(
            HomeIslandOceanEffects.makeScene(
                layout: .timerVoyage,
                appearance: oceanAppearance,
                nativeMetalRollout: nativeMetalRollout
            ).root
        )
        scene.rootNode.addChildNode(makeStars(count: 900))
        scene.rootNode.addChildNode(makeMoon(position: SCNVector3(-8.5, 5.6, -14)))

        // NightSea と SailorStage の中間値。背景世界の光は切替時にも変えず、
        // 船と航海士が同じ月明かりの中にいるようにする。
        let lights = makeLights()
        lights[0].light?.intensity = 520
        lights[1].light?.intensity = 1_250
        lights[2].light?.intensity = 240
        lights.forEach { scene.rootNode.addChildNode($0) }
        let camera = makeCamera(
            position: SCNVector3(3.1, 1.7, 4.3),
            target: SCNVector3(0, 0.7, 0),
            fov: 40
        )
        // 全画面の縦長viewportでもFOVを縦方向で固定する。SceneKitの自動選択に
        // 任せると横幅基準になり、端末比率によって船が極端に拡大される。
        camera.camera?.projectionDirection = .vertical
        scene.rootNode.addChildNode(camera)
        return scene
    }

    /// 装い世界へ差し込む船。背景やカメラを含めないため、表示対象だけを
    /// 入れ替えても視点が飛ばない。
    static func makeBoatStudioSubject(parts: BoatParts) -> SCNNode {
        let travel = SCNNode()
        travel.name = "travel"
        // 全画面では操作パネルが海の上へ重なるため、カード用の実寸のままだと
        // 船が上下のUIを覆う。世界の中心は変えず、展示物だけを一段引いて見せる。
        travel.scale = SCNVector3(0.55, 0.55, 0.55)
        let bob = SCNNode()
        bob.name = "boatBob"
        bob.addChildNode(makeBoatStudioModel(parts))
        travel.addChildNode(bob)
        return travel
    }

    static func makeBoatStudioModel(_ parts: BoatParts) -> SCNNode {
        let oceanAppearance = makeVoyagingOceanAppearance(
            timeOfDay: .night,
            palette: .voyagingNight
        )
        return makeBoatModel(
            parts,
            seaBounce: oceanAppearance.sea,
            sunDirection: oceanAppearance.sunDirection,
            sunColor: oceanAppearance.sun
        )
    }

    // MARK: - 航海士(プレイヤー)

    /// 低ポリの航海士。フードのローブ+暗い顔+背の二又マント+手のランタン。
    static func makeNavigator() -> SCNNode {
        let group = SCNNode()
        group.name = "navigator"
        let coat = UIColor(rgb: 0xF0997B)
        let cape = UIColor(rgb: 0x1A1130)
        let face = UIColor(rgb: 0x2A2140)

        let coatGeo = SCNCone(topRadius: 0.13, bottomRadius: 0.34, height: 0.85)
        coatGeo.radialSegmentCount = 10
        coatGeo.firstMaterial = unlitMaterial(coat)
        let coatNode = SCNNode(geometry: coatGeo)
        coatNode.position = SCNVector3(0, 0.42, 0)
        group.addChildNode(coatNode)

        let headGeo = SCNSphere(radius: 0.15)
        headGeo.segmentCount = 12
        headGeo.firstMaterial = flatMaterial(face)
        let headNode = SCNNode(geometry: headGeo)
        headNode.position = SCNVector3(0, 0.92, 0.02)
        group.addChildNode(headNode)

        let hoodGeo = SCNCone(topRadius: 0, bottomRadius: 0.19, height: 0.42)
        hoodGeo.radialSegmentCount = 8
        hoodGeo.firstMaterial = unlitMaterial(coat)
        let hoodNode = SCNNode(geometry: hoodGeo)
        hoodNode.position = SCNVector3(0, 1.05, -0.04)
        hoodNode.eulerAngles.x = -0.15
        group.addChildNode(hoodNode)

        let capePath = UIBezierPath()
        capePath.move(to: CGPoint(x: -0.28, y: 0))
        capePath.addLine(to: CGPoint(x: 0.28, y: 0))
        capePath.addLine(to: CGPoint(x: 0.18, y: -0.72))
        capePath.addLine(to: CGPoint(x: 0, y: -0.52))
        capePath.addLine(to: CGPoint(x: -0.18, y: -0.72))
        capePath.close()
        let capeGeo = SCNShape(path: capePath, extrusionDepth: 0.02)
        capeGeo.firstMaterial = flatMaterial(cape)
        let capeNode = SCNNode(geometry: capeGeo)
        capeNode.position = SCNVector3(0, 0.86, -0.17)
        capeNode.eulerAngles.x = 0.12
        group.addChildNode(capeNode)

        let lanternGeo = SCNSphere(radius: 0.07)
        let lm = SCNMaterial()
        lm.lightingModel = .constant
        lm.diffuse.contents = ember
        lm.emission.contents = ember
        lanternGeo.firstMaterial = lm
        let lanternNode = SCNNode(geometry: lanternGeo)
        lanternNode.position = SCNVector3(0.27, 0.52, 0.17)
        group.addChildNode(lanternNode)

        return group
    }

}

// MARK: - アニメータ(Web useFrame 相当)

/// Web VoyagingWorld の船・航跡・カモメを毎フレーム駆動する。
final class VoyagingHomeAnimator: NSObject {
    private struct DesiredState {
        var revision: UInt64 = 0
        var resting = false
        var elapsedSeconds: Float = 0
        var localSailorPose: PhoenixPose?
        var localSailorRole: VoyageSceneKit.CompanionDeckRole?
        var companions: [VoyageSceneKit.CompanionDeckMember] = []
        var reduceMotion = false
    }

    private struct DesiredUpdate {
        let revision: UInt64
        let localSailorRoleChanged: Bool
        let enteredReducedMotion: Bool
    }

    private let desiredStateLock = NSLock()
    private var desiredState = DesiredState()
    private var appliedDesiredRevision: UInt64 = 0
    private var resting = false
    private var elapsedSeconds: Float = 0
    private var localSailorPose: PhoenixPose?
    private var localSailorRole: VoyageSceneKit.CompanionDeckRole?
    private var reduceMotion = false
    private var frozenOceanTime = HomeIslandOceanEffects.currentTime
    private let flock: [(radius: Float, height: Float, omega: Float, flap: Float, phase: Float)] = [
        (4.2, 2.3, 0.085, 2.1, 0.0), (5.0, 2.8, -0.065, 1.7, 0.8),
        (4.6, 2.0, 0.11, 2.5, 1.6), (5.6, 3.2, 0.055, 1.6, 2.4),
        (3.9, 2.6, -0.1, 2.3, 3.2), (6.0, 2.2, 0.07, 1.9, 4.0),
        (5.2, 3.5, -0.05, 1.5, 4.8), (4.4, 3.0, 0.095, 2.2, 5.6),
        (6.6, 2.5, -0.045, 1.8, 6.1), (3.6, 3.3, 0.125, 2.6, 2.0)
    ]
    private var startTime: TimeInterval?
    private var lastTime: TimeInterval = 0
    private weak var scene: SCNScene?
    private weak var marineScene: SCNScene?
    private weak var travel: SCNNode?
    private weak var bob: SCNNode?
    private weak var approachingIsland: SCNNode?
    private weak var seaMaterial: SCNMaterial?
    private var gulls: [SCNNode] = []
    private let sailor = PhoenixAnimator()

    private let marineController = HomeIslandMarineDynamics.BoatController(
        field: .init(layout: .timerVoyage),
        tuning: HomeIslandMarineDynamics.boatTuning(forSceneScale: 0.55)
    )

    /// 同行の航海の同乗者。船のノードの下にぶら下げるので、甲板の揺れも
    /// 傾きもそのまま受け継ぐ。
    private final class CompanionVisual {
        let node: SCNNode
        let animator = PhoenixAnimator()

        init(node: SCNNode) {
            self.node = node
        }
    }

    private weak var boat: SCNNode?
    private weak var localSailor: SCNNode?
    private var desiredCompanions: [VoyageSceneKit.CompanionDeckMember] = []
    private var companionVisuals: [String: CompanionVisual] = [:]
    private var companionsAreSeated = true

    /// 帆としぶきへ実際に渡している風の強さ。段階が変わっても数秒かけて寄せる。
    private var windStrength: Float = 0
    private var sailMaterials: [SCNMaterial] = []
    private var boatSurfaceMaterials: [SCNMaterial] = []
    private var spraySystems: VoyageBowSpray.Systems = .empty
    private var sprayIsActive = false

    /// 旗の位相。速さを経過時間に掛けるのではなく、毎フレーム足す。
    ///
    /// 掛け算だと、風が変わって周波数が動いた瞬間に位相が `t × Δω` だけ飛ぶ。
    /// 一時間航海したあとの `t` は大きいので、段階が上がるちょうどその瞬間に
    /// 船が震えて見えてしまう。休憩の出入りでも同じことが起きる。
    private var flagPhase: Float = 0

    /// 風の強さが目標へ寄る速さ(時定数・秒)。出航・休憩明けはこの四倍ほど、
    /// おおよそ二秒半かけて次の絵に落ち着く。
    private static let windEase: Float = 0.625
    /// A single non-animated step lands damped navigator joints on their target.
    private static let staticPoseSnapDelta: Float = 4

    /// 休憩中は帆を緩めて凪へ戻す。再開すれば全力の風に戻る。
    private var windTarget: Float {
        resting ? 0.10 : VoyageWind.sailingStrength
    }

    /// SwiftUI writes only this lock-protected target. Renderer-owned values and
    /// SceneKit objects are updated together at the start of the next frame.
    @discardableResult
    func updateDesiredState(
        resting: Bool,
        elapsedSeconds: Int,
        localSailorPose: PhoenixPose?,
        localSailorRole: VoyageSceneKit.CompanionDeckRole?,
        companions: [VoyageSceneKit.CompanionDeckMember],
        reduceMotion: Bool
    ) -> UInt64 {
        desiredStateLock.lock()
        desiredState.revision &+= 1
        desiredState.resting = resting
        desiredState.elapsedSeconds = Float(max(0, elapsedSeconds))
        desiredState.localSailorPose = localSailorPose
        desiredState.localSailorRole = localSailorRole
        desiredState.companions = companions
        desiredState.reduceMotion = reduceMotion
        let revision = desiredState.revision
        desiredStateLock.unlock()
        return revision
    }

    private func consumeDesiredState() -> DesiredUpdate {
        desiredStateLock.lock()
        let snapshot = desiredState
        desiredStateLock.unlock()
        guard snapshot.revision != appliedDesiredRevision else {
            return DesiredUpdate(
                revision: appliedDesiredRevision,
                localSailorRoleChanged: false,
                enteredReducedMotion: false
            )
        }

        let roleChanged = localSailorRole != snapshot.localSailorRole
        let wasReducingMotion = reduceMotion
        resting = snapshot.resting
        elapsedSeconds = max(elapsedSeconds, snapshot.elapsedSeconds)
        localSailorPose = snapshot.localSailorPose
        localSailorRole = snapshot.localSailorRole
        if desiredCompanions != snapshot.companions {
            desiredCompanions = snapshot.companions
            companionsAreSeated = false
        }
        reduceMotion = snapshot.reduceMotion
        if reduceMotion, !wasReducingMotion {
            frozenOceanTime = HomeIslandOceanEffects.currentTime
        }
        appliedDesiredRevision = snapshot.revision
        return DesiredUpdate(
            revision: snapshot.revision,
            localSailorRoleChanged: roleChanged,
            enteredReducedMotion: reduceMotion && !wasReducingMotion
        )
    }

    private func bind(_ scene: SCNScene) {
        self.scene = scene
        travel = scene.rootNode.childNode(withName: "travel", recursively: false)
        bob = scene.rootNode.childNode(withName: "boatBob", recursively: true)
        boat = scene.rootNode.childNode(withName: "boatModel", recursively: true)
        localSailor = boat?.childNode(withName: "navigator", recursively: true)
        applyLocalSailorRole()
        // 作り直したシーンでは、前の船に乗せた同乗者のノードごと席を空ける。
        companionVisuals.removeAll()
        companionsAreSeated = false
        approachingIsland = scene.rootNode.childNode(withName: "approachingIsland", recursively: false)
        seaMaterial = scene.rootNode
            .childNode(withName: HomeIslandOceanEffects.surfaceNodeName, recursively: true)?
            .geometry?.firstMaterial
        gulls = scene.rootNode.childNode(withName: "gulls", recursively: false)?.childNodes ?? []
        sailMaterials = VoyageSailFlutter.materials(in: scene.rootNode)
        boatSurfaceMaterials = boat.map(VoyageSceneKit.styledBoatMaterials(in:)) ?? []
        spraySystems = VoyageBowSpray.systems(in: scene.rootNode)
        // 作り直したシーンでも、いま吹いている風の続きから始める。
        applyWind(windStrength, at: 0)
        placeApproachingIsland()
    }

    private func applyLocalSailorRole() {
        guard let localSailor else { return }
        PhoenixNavigator.applyPalette(
            localSailorRole?.palette ?? NavigatorCustomization.currentPalette,
            to: localSailor
        )
        if let localSailorRole {
            // ローカル航海士も役割の定位置へ移す。誰の端末で見ても、同じ人が
            // 同じ席・色・仕草になる。座標は既存アンカーからの相対差分。
            let seat = VoyageSceneKit.companionDeckSeat(for: localSailorRole)
            localSailor.position = SCNVector3(
                seat.position.x - VoyageSceneKit.navigatorDeckPosition.x,
                seat.position.y - VoyageSceneKit.navigatorDeckPosition.y,
                seat.position.z - VoyageSceneKit.navigatorDeckPosition.z
            )
            localSailor.eulerAngles.y = seat.facing.rawValue
        } else {
            localSailor.position = SCNVector3Zero
            localSailor.eulerAngles.y = .pi / 2
        }
    }

    /// 船のノードが揃ってから呼ぶ。まだ組み上がっていなければ何もせず、
    /// 次のフレームでもう一度試す。
    private func syncCompanions() {
        guard !companionsAreSeated, let boat, let scene else { return }

        let seating = VoyageSceneKit.companionDeckSeating(for: desiredCompanions)
        let seatedIDs = Set(seating.map(\.id))
        for id in Array(companionVisuals.keys) where !seatedIDs.contains(id) {
            companionVisuals.removeValue(forKey: id)?.node.removeFromParentNode()
        }
        for (id, seat) in seating {
            if let visual = companionVisuals[id] {
                visual.node.position = seat.position
                visual.node.eulerAngles.y = seat.facing.rawValue
                PhoenixNavigator.applyPalette(seat.role.palette, to: visual.node)
                visual.animator.pose = seat.role.pose
                if reduceMotion {
                    visual.animator.step(t: 0, dt: Self.staticPoseSnapDelta)
                }
                continue
            }
            let node = VoyageSceneKit.makeCompanionNavigator(id: id, role: seat.role)
            node.position = seat.position
            node.eulerAngles.y = seat.facing.rawValue
            boat.addChildNode(node)
            if reduceMotion {
                node.opacity = 1
            } else {
                node.opacity = 0
                node.runAction(.fadeIn(duration: 0.4))
            }
            let visual = CompanionVisual(node: node)
            visual.animator.pose = seat.role.pose
            visual.animator.bind(to: node, in: scene)
            if reduceMotion {
                visual.animator.step(t: 0, dt: Self.staticPoseSnapDelta)
            }
            companionVisuals[id] = visual
        }
        companionsAreSeated = true
    }

    /// 帆には休憩中の微風を残すが、しぶきは航行中だけ三層別に駆動する。
    private func applyWind(_ wind: Float, at t: Float) {
        for material in sailMaterials {
            material.setValue(NSNumber(value: wind), forKey: "uWind")
        }
        let shouldSpray = !resting && !reduceMotion && wind > 0.0005
        if shouldSpray {
            spraySystems.apply(.sailing(wind: wind, at: t))
        } else if sprayIsActive {
            // 描画を止める前に既存粒も消し、Reduce Motionで静止粒を残さない。
            spraySystems.reset()
        } else {
            spraySystems.apply(.zero)
        }
        sprayIsActive = shouldSpray
    }

    private func placeApproachingIsland() {
        // Web: k = 1 + 1.2 * exp(-elapsed / 1500)。
        // 開始直後は遠く、作業した時間だけゆっくり最終位置へ近づく。
        let k = 1 + 1.2 * exp(-elapsedSeconds / 1_500)
        approachingIsland?.position = SCNVector3(6.5 * k, 0, -5.5 * k)
    }

    /// Returns the desired-state revision after a complete reduced-motion frame.
    /// The coordinator uses it to stop rendering only if no newer state arrived.
    func renderFrame(
        _ renderer: SCNSceneRenderer,
        updateAtTime time: TimeInterval
    ) -> UInt64? {
        guard let currentScene = renderer.scene else { return nil }
        let desiredUpdate = consumeDesiredState()
        let sceneChanged = scene !== currentScene
        if sceneChanged {
            bind(currentScene)
        } else if desiredUpdate.localSailorRoleChanged {
            applyLocalSailorRole()
        }
        if startTime == nil { startTime = time; lastTime = time }
        let t = Float(time - (startTime ?? time))
        let dt = Float(min(max(time - lastTime, 0), 0.1))
        let animationTime: Float = reduceMotion ? 0 : t
        let animationDelta: Float = reduceMotion ? 0 : dt
        lastTime = time
        let oceanTime = reduceMotion
            ? frozenOceanTime
            : HomeIslandOceanEffects.currentTime
        seaMaterial?.setValue(
            NSNumber(value: oceanTime),
            forKey: "uTime"
        )
        if !resting, !reduceMotion {
            elapsedSeconds += animationDelta
        }
        placeApproachingIsland()

        // 段階が上がった瞬間に絵が飛ばないよう、目標へ 2 秒半かけて寄せる。
        if reduceMotion {
            windStrength = 0
        } else {
            let target = windTarget
            if abs(target - windStrength) > 0.0005 {
                windStrength += (target - windStrength)
                    * min(1, animationDelta / VoyagingHomeAnimator.windEase)
            } else {
                windStrength = target
            }
        }
        applyWind(windStrength, at: oceanTime)

        // Scene rebuilds arrive through SwiftUI, but marine controller state is
        // only touched from this renderer callback.
        if marineScene !== currentScene {
            marineController.reset(buoyancyNode: bob)
            marineScene = currentScene
        }
        if let travel, let bob {
            let frame = marineController.update(
                boatRoot: travel,
                buoyancyNode: bob,
                oceanTime: oceanTime,
                deltaTime: animationDelta,
                reduceMotion: reduceMotion,
                propulsionSpeed: resting || reduceMotion ? 0 : windStrength * 1.6
            )
            VoyageSceneKit.updateBoatWaterline(
                surface: frame.waterSurface,
                buoyancyNode: bob,
                materials: boatSurfaceMaterials
            )
            frame.wake.apply(to: seaMaterial)
        } else {
            marineController.reset()
            HomeIslandMarineDynamics.WakeState.inactive.apply(to: seaMaterial)
        }

        if reduceMotion {
            flagPhase = 0
        } else {
            flagPhase += animationDelta * (resting ? 1.2 : 5.2 + windStrength * 3.4)
        }

        if let bob {
            bob.childNode(withName: "boatFlag", recursively: true)?
                .eulerAngles.y = reduceMotion
                    ? 0
                    : sin(flagPhase) * (resting ? 0.07 : 0.22 + windStrength * 0.16)
        }

        for (index, bird) in gulls.enumerated() {
            guard flock.indices.contains(index) else { continue }
            let config = flock[index]
            let radius = config.radius
            let height = config.height
            let omega = config.omega
            let flap = config.flap
            let phase = config.phase
            let angle = phase + animationTime * omega
            bird.position = SCNVector3(
                cos(angle) * radius,
                height + sin(animationTime * 0.4 + phase) * 0.22,
                sin(angle) * radius
            )
            let vx = -sin(angle) * omega
            let vz = cos(angle) * omega
            bird.eulerAngles.y = atan2(-vx, -vz)
            bird.eulerAngles.z = omega > 0 ? -0.18 : 0.18
            let beat = -0.22 + sin(animationTime * flap + phase) * 0.34
            bird.childNode(withName: "leftWing", recursively: false)?.eulerAngles.z = beat
            bird.childNode(withName: "rightWing", recursively: false)?.eulerAngles.z = -beat
        }

        sailor.bindIfNeeded(currentScene)
        let sailorPose: PhoenixPose = resting
            ? .sit
            : (localSailorRole?.pose ?? localSailorPose ?? PhoenixPose.selected)
        let sailorPoseChanged = sailor.pose != sailorPose
        sailor.pose = sailorPose
        let sailorDelta = reduceMotion
            && (desiredUpdate.enteredReducedMotion || sceneChanged || sailorPoseChanged)
            ? Self.staticPoseSnapDelta
            : animationDelta
        sailor.step(t: animationTime, dt: sailorDelta)

        // 席が空いたまま、あるいは船が組み上がる前に届いた同乗者をここで拾う。
        syncCompanions()
        // 仲間の休憩までは分からない。甲板では立って海を見ている姿にする。
        for companion in companionVisuals.values {
            companion.animator.step(t: animationTime, dt: animationDelta)
        }
        return reduceMotion ? desiredUpdate.revision : nil
    }
}

// MARK: - SwiftUI ラッパ

/// ステップの見た目が変わったかを判定するための鍵(達成状態と達成日)。
/// これが変わったときだけシーンを作り直す。
func voyageStepsKey(_ steps: [VoyageStep]) -> String {
    steps.map { $0.doneAt.map { String(Int($0.timeIntervalSince1970)) } ?? "-" }.joined(separator: ",")
}

/// VoiceOverの調整操作でも、ピンチと同じカメラズームを使えるSceneKitビュー。
/// 実ジェスチャと別経路を持たせることで、ズーム状態を自動検証できるようにもする。
final class VoyagingSceneKitView: SCNView {
    var onAccessibilityZoom: ((Float) -> Void)?
    var onKeyboardEscape: (() -> Void)?
    var onKeyboardPrimaryAction: (() -> Void)?
    var onKeyboardCycleAction: ((Bool) -> Void)?

    /// iPadの外付けキーボードと「Designed for iPad」のMacで、
    /// 港そのものをメニューと同じように移動・決定できるようにする。
    /// タイマーやSwiftUIパネル表示中はfalseにし、前面UIへキー入力を譲る。
    var capturesHarborKeyboard = false {
        didSet {
            guard capturesHarborKeyboard != oldValue else { return }
            if capturesHarborKeyboard {
                becomeFirstResponder()
            } else {
                resignFirstResponder()
            }
        }
    }

    override var canBecomeFirstResponder: Bool { capturesHarborKeyboard }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, capturesHarborKeyboard {
            becomeFirstResponder()
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        guard capturesHarborKeyboard else { return nil }
        return [
            UIKeyCommand(
                input: UIKeyCommand.inputLeftArrow,
                modifierFlags: [],
                action: #selector(handleHarborKeyCommand(_:))
            ),
            UIKeyCommand(
                input: UIKeyCommand.inputUpArrow,
                modifierFlags: [],
                action: #selector(handleHarborKeyCommand(_:))
            ),
            UIKeyCommand(
                input: UIKeyCommand.inputRightArrow,
                modifierFlags: [],
                action: #selector(handleHarborKeyCommand(_:))
            ),
            UIKeyCommand(
                input: UIKeyCommand.inputDownArrow,
                modifierFlags: [],
                action: #selector(handleHarborKeyCommand(_:))
            ),
            UIKeyCommand(
                input: "\r",
                modifierFlags: [],
                action: #selector(handleHarborKeyCommand(_:))
            ),
            UIKeyCommand(
                input: " ",
                modifierFlags: [],
                action: #selector(handleHarborKeyCommand(_:))
            ),
            UIKeyCommand(
                input: UIKeyCommand.inputEscape,
                modifierFlags: [],
                action: #selector(handleHarborKeyCommand(_:))
            )
        ]
    }

    @objc private func handleHarborKeyCommand(_ command: UIKeyCommand) {
        switch command.input {
        case UIKeyCommand.inputLeftArrow, UIKeyCommand.inputUpArrow:
            onKeyboardCycleAction?(true)
        case UIKeyCommand.inputRightArrow, UIKeyCommand.inputDownArrow:
            onKeyboardCycleAction?(false)
        case "\r", " ":
            onKeyboardPrimaryAction?()
        case UIKeyCommand.inputEscape:
            onKeyboardEscape?()
        default:
            break
        }
    }

    override func accessibilityIncrement() {
        onAccessibilityZoom?(0.78)
    }

    override func accessibilityDecrement() {
        onAccessibilityZoom?(1.28)
    }
}

/// ログイン後に最初に見せる、Web VoyagingWorld と同じ航海中の世界。
enum VoyagingHomeSceneRenderingMode: Equatable {
    case interactive
    /// 初回導入はカメラ操作を持たず、30fps / 2xに抑えて説明を優先する。
    case guidedIntroduction
}

struct VoyagingHomeSceneView: UIViewRepresentable {
    var showIsland: Bool
    var timeOfDay: AftideHomeTimeOfDay = .night
    var date: Date = .now
    var resting: Bool = false
    var elapsedSeconds: Int = 0
    var boatParts: BoatParts = BoatCustomization.currentParts
    var boatAppearanceKey: String = BoatCustomization.voyageRenderingKey
    /// 同行の航海の同乗者。順番がそのまま甲板の席順になる。
    var companions: [VoyageSceneKit.CompanionDeckMember] = []
    /// 通常航海など、色を変えずに仕草だけ上書きするときに使う。
    var localSailorPose: PhoenixPose?

    /// 同行の航海では、ローカルの航海士も4つの役割のどれかに固定する。
    /// ホストはコーラルのランタン役、同行者はミストの見張り役。
    var localSailorRole: VoyageSceneKit.CompanionDeckRole?
    var azimuthOffset: Float = 0
    var polarOffset: Float = 0
    var distanceScale: Float = 1
    var renderingMode: VoyagingHomeSceneRenderingMode = .interactive
    var onTapWorld: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    func makeCoordinator() -> Coordinator {
        Coordinator(onTapWorld: onTapWorld)
    }

    func makeUIView(context: Context) -> VoyagingSceneKitView {
        let metalProfile = MetalRenderingProfile.current
        let view = VoyagingSceneKitView(
            frame: .zero,
            options: MetalRenderingProfile.sceneViewOptions()
        )
        let guidedIntroduction = renderingMode == .guidedIntroduction
        let scene = VoyageSceneKit.makeVoyagingScene(
            showIsland: showIsland,
            timeOfDay: timeOfDay,
            date: date,
            boatParts: boatParts,
            nativeMetalRollout: .timerVoyage
        )
        view.scene = scene
        view.backgroundColor = UIColor(rgb: timeOfDay.palette.sky)
        view.antialiasingMode = guidedIntroduction
            ? .multisampling2X
            : metalProfile.antialiasingMode
        view.preferredFramesPerSecond = guidedIntroduction
            ? 30
            : metalProfile.interactiveFramesPerSecond
        view.contentScaleFactor = guidedIntroduction
            ? min(UIScreen.main.scale, 2)
            : UIScreen.main.scale
        view.autoenablesDefaultLighting = false
        view.isMultipleTouchEnabled = !guidedIntroduction
        view.isAccessibilityElement = true
        view.accessibilityTraits.insert(.adjustable)
        view.accessibilityLabel = LF.text("360° voyage view")
        view.accessibilityHint = LF.text(
            "Drag to look around. Pinch to zoom. Double-tap to reset the view."
        )
        // Web OrbitControls と同じ、船を中心にした球面オービット。
        // カメラの上方向はworld +Yへ固定し、回転後のロールを発生させない。
        view.allowsCameraControl = false
        let reduceMotion = accessibilityReduceMotion || UIAccessibility.isReduceMotionEnabled
        view.pointOfView = view.scene?.rootNode.childNode(withName: "camera", recursively: false)
        context.coordinator.attach(to: view)
        context.coordinator.setOrbit(
            azimuthOffset: azimuthOffset,
            polarOffset: polarOffset,
            distanceScale: distanceScale
        )
        if !guidedIntroduction {
            context.coordinator.installGestures(on: view)
        }
        view.onAccessibilityZoom = { [weak coordinator = context.coordinator] factor in
            coordinator?.zoom(by: factor)
        }
        context.coordinator.showIsland = showIsland
        context.coordinator.timeOfDay = timeOfDay
        context.coordinator.boatAppearanceKey = boatAppearanceKey
        context.coordinator.setDate(date)
        context.coordinator.updateAnimationState(
            resting: resting,
            elapsedSeconds: elapsedSeconds,
            localSailorPose: localSailorPose,
            localSailorRole: localSailorRole,
            companions: companions,
            reduceMotion: reduceMotion
        )
        return view
    }

    func updateUIView(_ view: VoyagingSceneKitView, context: Context) {
        if context.coordinator.showIsland != showIsland ||
            context.coordinator.timeOfDay != timeOfDay ||
            context.coordinator.boatAppearanceKey != boatAppearanceKey {
            context.coordinator.showIsland = showIsland
            context.coordinator.timeOfDay = timeOfDay
            context.coordinator.boatAppearanceKey = boatAppearanceKey
            let scene = VoyageSceneKit.makeVoyagingScene(
                showIsland: showIsland,
                timeOfDay: timeOfDay,
                date: date,
                boatParts: boatParts,
                nativeMetalRollout: .timerVoyage
            )
            view.scene = scene
            view.backgroundColor = UIColor(rgb: timeOfDay.palette.sky)
            view.pointOfView = view.scene?.rootNode.childNode(withName: "camera", recursively: false)
            context.coordinator.bindCamera()
        }
        context.coordinator.setDate(date)
        context.coordinator.onTapWorld = onTapWorld
        context.coordinator.setOrbit(
            azimuthOffset: azimuthOffset,
            polarOffset: polarOffset,
            distanceScale: distanceScale
        )
        context.coordinator.updateAnimationState(
            resting: resting,
            elapsedSeconds: elapsedSeconds,
            localSailorPose: localSailorPose,
            localSailorRole: localSailorRole,
            companions: companions,
            reduceMotion: accessibilityReduceMotion || UIAccessibility.isReduceMotionEnabled
        )
    }

    static func dismantleUIView(_ view: VoyagingSceneKitView, coordinator: Coordinator) {
        coordinator.stopCameraLoop()
        view.delegate = nil
        view.isPlaying = false
        view.rendersContinuously = false
        view.onAccessibilityZoom = nil
        view.scene = nil
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate, UIGestureRecognizerDelegate {
        private let animator = VoyagingHomeAnimator()
        var showIsland = false
        var timeOfDay: AftideHomeTimeOfDay = .night
        var boatAppearanceKey = ""
        private var reduceMotion = false
        private var latestAnimatorRevision: UInt64 = 0
        var onTapWorld: () -> Void
        private weak var view: SCNView?
        private weak var camera: SCNNode?
        private weak var moon: SCNNode?
        private weak var seaMaterial: SCNMaterial?
        private var framePacing = MetalOceanFramePacingMonitor()
        private var hasReducedRenderingQuality = false
        private let performanceLogger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "Landfall",
            category: "MetalOceanPerformance"
        )

        // Web VoyagingWorld:
        // camera [-5.6, 2.4, 8.6], target [0.8, 1.15, 0], fov 38
        // min/max distance 4...16, polar 0.12π...0.49π, damping 0.05
        private let target = SCNVector3(0.8, 1.15, 0)
        private let initialPosition = SCNVector3(-5.6, 2.4, 8.6)
        private let minimumDistance: Float = 4
        private let maximumDistance: Float = 16
        private let minimumPolar: Float = .pi * 0.12
        private let maximumPolar: Float = .pi * 0.49
        private let dampingFactor: Float = 0.05
        private lazy var initialDistance: Float = {
            let dx = initialPosition.x - target.x
            let dy = initialPosition.y - target.y
            let dz = initialPosition.z - target.z
            return sqrt(dx * dx + dy * dy + dz * dz)
        }()
        private lazy var initialAzimuth: Float = {
            atan2(initialPosition.x - target.x, initialPosition.z - target.z)
        }()
        private lazy var initialPolar: Float = {
            acos((initialPosition.y - target.y) / initialDistance)
        }()

        private var azimuth: Float = 0
        private var polar: Float = 0
        private var distance: Float = 0
        private var azimuthDelta: Float = 0
        private var polarDelta: Float = 0
        private var previousPanTranslation = CGPoint.zero
        private var previousPinchScale: CGFloat = 1
        private var externalAzimuthOffset: Float = 0
        private var externalPolarOffset: Float = 0
        private var externalDistanceScale: Float = 1
        private var orbitIsInitialized = false
        private var cameraDisplayLink: CADisplayLink?

        init(onTapWorld: @escaping () -> Void) {
            self.onTapWorld = onTapWorld
        }

        deinit {
            cameraDisplayLink?.invalidate()
        }

        func stopCameraLoop() {
            cameraDisplayLink?.invalidate()
            cameraDisplayLink = nil
        }

        func attach(to view: SCNView) {
            self.view = view
            framePacing.reset()
            hasReducedRenderingQuality = false
            bindCamera()
            bindMoon()
        }

        /// Publishes a coherent main-thread snapshot. No animator or SceneKit
        /// state is mutated until the renderer consumes this revision.
        func updateAnimationState(
            resting: Bool,
            elapsedSeconds: Int,
            localSailorPose: PhoenixPose?,
            localSailorRole: VoyageSceneKit.CompanionDeckRole?,
            companions: [VoyageSceneKit.CompanionDeckMember],
            reduceMotion: Bool
        ) {
            latestAnimatorRevision = animator.updateDesiredState(
                resting: resting,
                elapsedSeconds: elapsedSeconds,
                localSailorPose: localSailorPose,
                localSailorRole: localSailorRole,
                companions: companions,
                reduceMotion: reduceMotion
            )
            configureAnimationLoop(reduceMotion: reduceMotion)
        }

        /// Reduced Motion still renders one complete static frame. The delegate
        /// is detached only after that revision has reset boat pose, wake and foam.
        private func configureAnimationLoop(reduceMotion value: Bool) {
            guard let view else { return }
            reduceMotion = value
            if value {
                azimuthDelta = 0
                polarDelta = 0
            }
            view.delegate = self
            view.rendersContinuously = true
            view.isPlaying = true
            if value { view.setNeedsDisplay() }
        }

        private func finishReducedMotionFrame(revision: UInt64) {
            guard reduceMotion,
                  revision == latestAnimatorRevision,
                  let view
            else { return }
            view.rendersContinuously = false
            view.isPlaying = false
            view.delegate = nil
        }

        func installGestures(on view: SCNView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.cancelsTouchesInView = true
            pan.delegate = self
            view.addGestureRecognizer(pan)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
            pinch.cancelsTouchesInView = false
            pinch.delaysTouchesBegan = false
            pinch.delaysTouchesEnded = false
            pinch.delegate = self
            view.addGestureRecognizer(pinch)

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(onDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            view.addGestureRecognizer(doubleTap)

            let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
            tap.require(toFail: doubleTap)
            tap.require(toFail: pan)
            view.addGestureRecognizer(tap)

            let displayLink = CADisplayLink(target: self, selector: #selector(onCameraFrame))
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: 30,
                maximum: 60,
                preferred: 60
            )
            displayLink.add(to: .main, forMode: .common)
            cameraDisplayLink = displayLink
        }

        func bindCamera() {
            camera = view?.scene?.rootNode.childNode(withName: "camera", recursively: false)
            bindSeaMaterial()
            bindMoon()
            if !orbitIsInitialized {
                azimuth = initialAzimuth
                polar = initialPolar
                distance = initialDistance
                orbitIsInitialized = true
            }
            applyCamera()
            updateAccessibilityValue()
        }

        private func bindSeaMaterial() {
            let material = view?.scene?.rootNode
                .childNode(withName: HomeIslandOceanEffects.surfaceNodeName, recursively: true)?
                .geometry?.firstMaterial
            guard seaMaterial !== material else { return }
            seaMaterial = material
            framePacing.reset()
        }

        private func bindMoon() {
            moon = view?.scene?.rootNode.childNode(
                withName: LandfallMoonEffects.rootNodeName,
                recursively: false
            )
        }

        func setDate(_ date: Date) {
            if moon == nil { bindMoon() }
            LandfallMoonEffects.update(moon, phase: .current(at: date))
        }

        func setOrbit(azimuthOffset: Float, polarOffset: Float, distanceScale: Float) {
            guard orbitIsInitialized else { return }

            // SwiftUI更新のたびにユーザー操作を上書きせず、外部指定が変わった差分だけ反映する。
            let safeScale = max(distanceScale, 0.001)
            if externalAzimuthOffset != azimuthOffset {
                azimuth += azimuthOffset - externalAzimuthOffset
            }
            if externalPolarOffset != polarOffset {
                polar += polarOffset - externalPolarOffset
            }
            if externalDistanceScale != safeScale {
                distance *= safeScale / max(externalDistanceScale, 0.001)
            }
            externalAzimuthOffset = azimuthOffset
            externalPolarOffset = polarOffset
            externalDistanceScale = safeScale

            clampOrbit()
            applyCamera()
            updateAccessibilityValue()
        }

        @objc private func onPan(_ gesture: UIPanGestureRecognizer) {
            guard let view else { return }
            let height = Float(max(view.bounds.height, 1))

            switch gesture.state {
            case .began:
                previousPanTranslation = gesture.translation(in: view)
            case .changed:
                let translation = gesture.translation(in: view)
                let deltaX = Float(translation.x - previousPanTranslation.x)
                let deltaY = Float(translation.y - previousPanTranslation.y)
                previousPanTranslation = translation

                // Three.js OrbitControls:
                // rotateLeft(2π * dx / clientHeight), rotateUp(2π * dy / clientHeight)
                azimuthDelta -= 2 * .pi * deltaX / height
                polarDelta -= 2 * .pi * deltaY / height
                stepOrbit()
            case .ended, .cancelled, .failed:
                previousPanTranslation = .zero
            default:
                break
            }
        }

        @objc private func onPinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                previousPinchScale = max(gesture.scale, 0.001)
            case .changed:
                let currentScale = max(gesture.scale, 0.001)
                let ratio = Float(currentScale / previousPinchScale)
                previousPinchScale = currentScale

                distance = min(max(distance / ratio, minimumDistance), maximumDistance)
                applyCamera()
                updateAccessibilityValue()
            case .ended, .cancelled, .failed:
                previousPinchScale = 1
            default:
                break
            }
        }

        @objc private func onTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            onTapWorld()
        }

        @objc private func onDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            azimuth = initialAzimuth + externalAzimuthOffset
            polar = initialPolar + externalPolarOffset
            distance = min(
                max(initialDistance * externalDistanceScale, minimumDistance),
                maximumDistance
            )
            azimuthDelta = 0
            polarDelta = 0
            clampOrbit()
            applyCamera()
            updateAccessibilityValue()
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            (gestureRecognizer is UIPanGestureRecognizer &&
                otherGestureRecognizer is UIPinchGestureRecognizer) ||
            (gestureRecognizer is UIPinchGestureRecognizer &&
                otherGestureRecognizer is UIPanGestureRecognizer)
        }

        func zoom(by factor: Float) {
            distance = min(max(distance * factor, minimumDistance), maximumDistance)
            applyCamera()
            updateAccessibilityValue()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        private func updateAccessibilityValue() {
            guard let view else { return }
            let magnification = Int((initialDistance / max(distance, 0.01) * 100).rounded())
            view.accessibilityValue = LF.format("Zoom %lld%%", Int64(magnification))
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            if seaMaterial?.program != nil,
               framePacing.observe(
                   at: time,
                   targetFramesPerSecond: view?.preferredFramesPerSecond ?? 60
               ) {
                reduceRenderingQualityIfNeeded()
            }
            guard let revision = animator.renderFrame(renderer, updateAtTime: time)
            else { return }
            DispatchQueue.main.async { [weak self] in
                self?.finishReducedMotionFrame(revision: revision)
            }
        }

        private func reduceRenderingQualityIfNeeded() {
            guard !hasReducedRenderingQuality else { return }
            hasReducedRenderingQuality = true
#if DEBUG
            print("[MetalOceanPerformance] Sustained overload detected")
#endif
            DispatchQueue.main.async { [weak self] in
                guard let self, let view = self.view else { return }
                view.contentScaleFactor = min(UIScreen.main.scale, 2)
                view.antialiasingMode = .multisampling2X
                self.performanceLogger.notice(
                    "Reduced voyage ocean resolution after sustained frame pacing pressure"
                )
            }
        }

        @objc private func onCameraFrame() {
            guard !reduceMotion else { return }
            stepOrbit()
        }

        private func stepOrbit() {
            let appliedFactor: Float = reduceMotion ? 1 : dampingFactor
            azimuth += azimuthDelta * appliedFactor
            polar += polarDelta * appliedFactor

            if reduceMotion {
                azimuthDelta = 0
                polarDelta = 0
            } else {
                azimuthDelta *= 1 - dampingFactor
                polarDelta *= 1 - dampingFactor
                if abs(azimuthDelta) < 0.00001 { azimuthDelta = 0 }
                if abs(polarDelta) < 0.00001 { polarDelta = 0 }
            }

            clampOrbit()
            applyCamera()
        }

        private func clampOrbit() {
            polar = min(max(polar, minimumPolar), maximumPolar)
            distance = min(max(distance, minimumDistance), maximumDistance)
        }

        private func applyCamera() {
            guard let camera else { return }
            let sinPolar = sin(polar)
            camera.position = SCNVector3(
                target.x + distance * sinPolar * sin(azimuth),
                target.y + distance * cos(polar),
                target.z + distance * sinPolar * cos(azimuth)
            )
            camera.camera?.fieldOfView = 38
            camera.look(
                at: target,
                up: SCNVector3(0, 1, 0),
                localFront: SCNVector3(0, 0, -1)
            )
        }
    }
}
