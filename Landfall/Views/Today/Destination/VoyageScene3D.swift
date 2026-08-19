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
    static let ripple = UIColor(rgb: 0x7FB8A6)    // 波紋
    static let returnOrange = UIColor(rgb: 0xF5822A) // 帰帆色(制覇の旗・達成日)

    // 航路(Web VoyageScene と同値)。ステップの島は「そう簡単には届かない目標」なので、
    // 航路を長くとって一つ一つを遠くに置く(島の間に開けた海を残す)。
    static let xStart: Float = -56.0
    static let xEnd: Float = -2.0

    // カード(ホームの主役)の establishing 構図。航海の全景を、引き+俯瞰の斜め(3/4)で
    // 綺麗に一望する(真横を避ける)。没入エディタの入場もここから寄っていく(Web と同値)。
    static let cardCamPos = SCNVector3(-26.0, 20.0, 52)
    static let cardCamTarget = SCNVector3(-26.25, 1.2, -0.15)
    static let cardCamFov: CGFloat = 42
    static let routeApproachPower: Float = 2.15

    static func boatX(_ ratio: Double) -> Float {
        let progress = Float(min(max(ratio, 0), 1))
        return xStart + pow(progress, routeApproachPower) * (xEnd - xStart)
    }

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

    // MARK: - 海(Webのシェーダを Metal に移植)

    /// Webと同じ四層の海面変形。外周だけ振幅を落とし、夜空との境界を隠す。
    private static let seaGeometryShader = """
    #pragma body
    float2 p = _geometry.position.xy;
    float t = scn_frame.time;
    float warpPhase = p.x * 0.055 + p.y * 0.083 - t * 0.18;
    float warp = sin(warpPhase) * 1.35;
    float2 q = p + float2(warp, -warp * 0.55);
    float phaseA = q.y * 0.135 + q.x * 0.095 - t * 0.34;
    float phaseB = q.y * 0.115 - q.x * 0.105 + t * 0.27;
    float phaseC = q.y * 0.410 + q.x * 0.330 - t * 0.58;
    float phaseD = q.y * 0.880 - q.x * 0.630 + t * 0.92;
    float height =
        sin(phaseA) * 0.150
        + sin(phaseB) * 0.090
        + sin(phaseC) * 0.026
        + sin(phaseD) * 0.006;
    float edge = 1.0 - smoothstep(66.0, 88.0, length(p));
    float dhdx =
        cos(phaseA) * 0.150 * 0.095
        + cos(phaseB) * 0.090 * -0.105
        + cos(phaseC) * 0.026 * 0.330
        + cos(phaseD) * 0.006 * -0.630;
    float dhdy =
        cos(phaseA) * 0.150 * 0.135
        + cos(phaseB) * 0.090 * 0.115
        + cos(phaseC) * 0.026 * 0.410
        + cos(phaseD) * 0.006 * 0.880;
    _geometry.position.z += height * edge;
    _geometry.normal = normalize(float3(-dhdx * edge, -dhdy * edge, 1.0));
    """

    /// 深色の谷・空の反射・割れた月光を重ね、平面の色模様ではなく海面として見せる。
    private static let seaSurfaceShader = """
    #pragma arguments
    float moonX;
    #pragma body
    float2 uv = _surface.diffuseTexcoord;
    // Web Sea は半径90のXY円盤で、local +Y = world -Z。
    // SceneKitのPlaneも同じ向きへ倒しているため、uv.yを反転してはいけない。
    // 濃淡の基準半径は従来の30を維持し、外側は夜色へ自然に溶かす。
    float2 p = float2((uv.x - 0.5) * 180.0, (uv.y - 0.5) * 180.0);
    float distanceFromBoat = length(p);
    float3 seaC = float3(0.1176, 0.3255, 0.2824);   // #1E5348
    float3 deepC = float3(0.0706, 0.2196, 0.1882);  // #123830
    float3 moonC = float3(0.7490, 0.8392, 0.7765);  // #BFD6C6
    float t = scn_frame.time;
    float warp = sin(p.x * 0.055 + p.y * 0.083 - t * 0.18) * 1.35;
    float2 q = p + float2(warp, -warp * 0.55);
    float phaseA = q.y * 0.135 + q.x * 0.095 - t * 0.34;
    float phaseB = q.y * 0.115 - q.x * 0.105 + t * 0.27;
    float phaseC = q.y * 0.410 + q.x * 0.330 - t * 0.58;
    float phaseD = q.y * 0.880 - q.x * 0.630 + t * 0.92;
    float height =
        sin(phaseA) * 0.150
        + sin(phaseB) * 0.090
        + sin(phaseC) * 0.026
        + sin(phaseD) * 0.006;
    float2 slope = float2(
        cos(phaseA) * 0.150 * 0.095
            + cos(phaseB) * 0.090 * -0.105
            + cos(phaseC) * 0.026 * 0.330
            + cos(phaseD) * 0.006 * -0.630,
        cos(phaseA) * 0.150 * 0.135
            + cos(phaseB) * 0.090 * 0.115
            + cos(phaseC) * 0.026 * 0.410
            + cos(phaseD) * 0.006 * 0.880
    );
    float depth = smoothstep(7.0, 72.0, distanceFromBoat);
    float3 col = mix(seaC, deepC, 0.12 + depth * 0.68);
    float directionalShade = clamp(0.5 + slope.x * 3.4 + slope.y * 3.0, 0.0, 1.0);
    col *= 0.93 + directionalShade * 0.10;
    float trough = 1.0 - smoothstep(-0.14, 0.015, height);
    float crest = smoothstep(0.040, 0.185, height);
    col = mix(col, deepC, trough * 0.26);
    col = mix(col, moonC, crest * 0.070);
    col = mix(col, mix(deepC, moonC, 0.24), smoothstep(40.0, 88.0, distanceFromBoat) * 0.14);

    float grainA = sin(
        p.y * 0.72 + sin(p.x * 0.31) * 1.7
        + sin(p.y * 0.13 + p.x * 0.27) * 2.2 - t * 0.92
    );
    float grainB = sin(
        p.x * 0.81 + sin(p.y * 0.36) * 1.3
        - sin(p.x * 0.11 - p.y * 0.23) * 1.8 + t * 0.61
    );
    col *= 0.985 + grainA * grainB * 0.025
        * (1.0 - smoothstep(34.0, 82.0, distanceFromBoat));
    float broken = 0.5 + 0.5 * sin(
        p.y * 1.42 - p.x * 1.91 + sin(p.x * 0.17) * 2.1 - t * 1.16
    );
    float capGlint = smoothstep(0.80, 0.98, broken)
        * smoothstep(0.035, 0.18, height)
        * (1.0 - smoothstep(25.0, 76.0, distanceFromBoat));
    col = mix(col, moonC, capGlint * 0.095);

    float laneWarp = sin(p.y * 0.22 - t * 0.38) * 0.55
        + sin(p.y * 0.57 + t * 0.24) * 0.22;
    float dx = p.x - moonX + laneWarp;
    float along = smoothstep(-5.0, 13.0, p.y);
    float w = mix(2.8, 0.7, along);
    float band = exp(-(dx * dx) / (w * w));
    float shimmer = 0.5 + 0.5
        * sin(p.y * 1.17 - t * 1.28)
        * sin(p.x * 1.63 + t * 0.61);
    float streak = band * along * smoothstep(0.24, 0.84, shimmer)
        * (0.44 + crest * 0.56) * 0.5;
    col = mix(col, moonC, streak);
    col = mix(col, deepC, smoothstep(68.0, 90.0, distanceFromBoat) * 0.82);
    // SceneKitはリニア色空間で描くため、sRGBで計算した色をリニアへ変換して渡す
    // (これをしないと全体が白っぽく浮く)。
    _surface.diffuse = float4(pow(clamp(col, 0.0, 1.0), float3(2.2)), 1.0);
    """

    static func makeSea(moonX: Float) -> SCNNode {
        // Web: 180角の細分化平面。最遠航路(-56)でも海面の外へ出ない。
        let plane = SCNPlane(width: 180, height: 180)
        plane.widthSegmentCount = 140
        plane.heightSegmentCount = 140
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = seaBase
        m.isDoubleSided = true
        m.shaderModifiers = [
            .geometry: seaGeometryShader,
            .surface: seaSurfaceShader
        ]
        m.setValue(NSNumber(value: moonX), forKey: "moonX")
        plane.firstMaterial = m
        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2
        return node
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

    /// 水平線。霧に沈む海の縁の、sandの淡い一線(Web Horizon)。
    static func makeHorizon() -> SCNNode {
        let plane = SCNPlane(width: 180, height: 0.08)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = sand.withAlphaComponent(0.22)
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        plane.firstMaterial = m
        let node = SCNNode(geometry: plane)
        node.position = SCNVector3(0, 0.04, -20)
        return node
    }

    // MARK: - 壮大な目的地の島

    /// 航海のすべての画面で共有する目的地の島。遠景では段状の長い稜線、
    /// 近景では浜から山頂へ続く道・灯り・岩・植生まで読める密度にする。
    static func makeIsland(
        position: SCNVector3 = SCNVector3(3.5, 0, -0.9),
        scale: SCNVector3 = SCNVector3(1.34, 1.38, 1.34),
        includesCustomAssets: Bool = true
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

        let foamGeo = SCNTorus(ringRadius: 3.34, pipeRadius: 0.09)
        foamGeo.ringSegmentCount = 72
        foamGeo.pipeSegmentCount = 7
        let foamMaterial = unlitMaterial(UIColor(rgb: 0xD8EBDD).withAlphaComponent(0.58))
        foamMaterial.writesToDepthBuffer = false
        foamGeo.firstMaterial = foamMaterial
        let foam = SCNNode(geometry: foamGeo)
        foam.position = SCNVector3(0, 0.055, 0.08)
        foam.scale = SCNVector3(1.02, 1, 0.74)
        group.addChildNode(foam)

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

    /// Webと同じBlenderソースから出力した完成船。簡易プリミティブを組み直さず、
    /// 船体・甲板・舷縁・索具の形と座標系を両プラットフォームで共有する。
    static func makeBoatModel(_ parts: BoatParts) -> SCNNode {
        guard let url = Bundle.main.url(forResource: "landfall_boat", withExtension: "usdz"),
              let importedScene = try? SCNScene(url: url, options: nil) else {
            assertionFailure("landfall_boat.usdz could not be loaded")
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
                switch material.name {
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

    // MARK: - 波紋・航跡(Web Ripples / Wake)

    /// 平たいリング(RingGeometry 0.9..1.0 相当)。
    private static func makeRingNode(index: Int) -> SCNNode {
        let path = UIBezierPath(ovalIn: CGRect(x: -1, y: -1, width: 2, height: 2))
        path.append(UIBezierPath(ovalIn: CGRect(x: -0.9, y: -0.9, width: 1.8, height: 1.8)).reversing())
        path.usesEvenOddFillRule = true
        path.flatness = 0.02
        let shape = SCNShape(path: path, extrusionDepth: 0)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = ripple
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        shape.firstMaterial = m
        let node = SCNNode(geometry: shape)
        node.name = "ripple\(index)"
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(0, 0.02 + Float(index) * 0.004, 0)
        let s = 1.5 + Float(index) * 1.6
        node.scale = SCNVector3(s, s, 1)
        node.opacity = CGFloat(0.12 - Double(index) * 0.03)
        return node
    }

    static func makeRipples() -> SCNNode {
        let group = SCNNode()
        group.name = "ripples"
        for i in 0..<3 { group.addChildNode(makeRingNode(index: i)) }
        return group
    }

    /// 航跡。船尾から後ろへ、白い帯が尾に向かってフェードする(Web Wake のグラデ)。
    static func makeWake() -> SCNNode {
        // 旧64x8 bitmapと同じ2.3x0.4の帯を、頂点alphaの補間だけで描く。
        // tail=0 → 70%=0.5 → 船尾=0.9の勾配なので、見た目とnode opacity契約は不変。
        let segmentCount = 12
        var vertices: [SCNVector3] = []
        var colors: [SIMD4<Float>] = []
        var indices: [UInt32] = []
        vertices.reserveCapacity((segmentCount + 1) * 2)
        colors.reserveCapacity((segmentCount + 1) * 2)
        indices.reserveCapacity(segmentCount * 6)

        for column in 0...segmentCount {
            let progress = Float(column) / Float(segmentCount)
            let x = -1.15 + progress * 2.3
            let alpha: Float
            if progress <= 0.7 {
                alpha = progress / 0.7 * 0.5
            } else {
                alpha = 0.5 + (progress - 0.7) / 0.3 * 0.4
            }
            vertices.append(SCNVector3(x, 0, -0.2))
            vertices.append(SCNVector3(x, 0, 0.2))
            colors.append(SIMD4(1, 1, 1, alpha))
            colors.append(SIMD4(1, 1, 1, alpha))

            guard column < segmentCount else { continue }
            let near = UInt32(column * 2)
            let far = UInt32((column + 1) * 2)
            indices += [near, near + 1, far, near + 1, far + 1, far]
        }

        let colorData = colors.withUnsafeBytes { Data($0) }
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD4<Float>>.stride
        )
        let element = indices.withUnsafeBufferPointer {
            SCNGeometryElement(
                data: Data(buffer: $0),
                primitiveType: .triangles,
                primitiveCount: indices.count / 3,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )
        }
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), colorSource],
            elements: [element]
        )
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.white
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.isDoubleSided = true
        geometry.firstMaterial = material

        let node = SCNNode(geometry: geometry)
        node.name = "wake"
        node.position = SCNVector3(-2.15, 0.025, 0)
        node.opacity = 0.34
        return node
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

    // MARK: - シーン(目的地)

    /// 目的地の航海シーン。Web VoyageScene と同じ構図:
    /// 夜の海・星・月(カード=x1.8の月の出 / 没入=左上奥)・水平線・右奥の島・ブイ・船。
    static func makeScene(ratio: Double, steps: [VoyageStep], immersive: Bool = false) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = nightBG
        let moonX: Float = immersive ? -8 : 1.8
        scene.rootNode.addChildNode(makeSea(moonX: moonX))
        scene.rootNode.addChildNode(makeStars(count: immersive ? 620 : 380))
        scene.rootNode.addChildNode(makeMoon(
            position: immersive ? SCNVector3(-8, 3.2, -16) : SCNVector3(1.8, 1.25, -14)
        ))
        scene.rootNode.addChildNode(makeHorizon())
        scene.rootNode.addChildNode(makeIsland())
        for (i, step) in steps.enumerated() {
            scene.rootNode.addChildNode(
                makeStepIslet(index: i, total: steps.count, done: step.done, doneAt: step.doneAt)
            )
        }

        // 航路上の船。波紋+航跡ごと進む(Web: group scale 0.55, rot y 0.1)。
        let travel = SCNNode()
        travel.name = "travel"
        travel.position = SCNVector3(boatX(ratio), 0, 0)
        travel.eulerAngles.y = 0.1
        travel.scale = SCNVector3(0.35, 0.35, 0.35)
        travel.addChildNode(makeRipples())
        travel.addChildNode(makeWake())
        let bob = SCNNode()
        bob.name = "boatBob"
        let boat = makeBoatModel(BoatCustomization.currentParts)
        attachNavigator(to: boat)
        bob.addChildNode(boat)
        // 自分の航海士を船首寄りの甲板に立たせる(舳先を見て進む姿)。
        // 船体は x=-1.02(船尾)〜1.32(舳先の先端)で、舷縁は y≈0.5〜0.58。
        // 原点が足元なので舷縁の上(y=0.57)に置く。マスト(x=0.1)とメインセイルを
        // 避けつつ、舳先の反りに脚が入らない x=0.88 に。帆に隠れないよう
        // 手前の舷側(z=+0.22)へ寄せる。
        travel.addChildNode(bob)
        if immersive {
            // 船タップの当たり判定(船体+帆を覆う。Web BOAT_HIT_GEO)+ タップ波紋リング。
            travel.addChildNode(makeTapRing())
            let hit = SCNNode(geometry: SCNBox(width: 3.0, height: 2.6, length: 1.6, chamferRadius: 0))
            hit.name = "boatHit"
            hit.position = SCNVector3(0.1, 1.0, 0)
            hit.opacity = 0
            travel.addChildNode(hit)
        }
        scene.rootNode.addChildNode(travel)

        if immersive {
            scene.rootNode.addChildNode(makeShootingStar())
            scene.rootNode.addChildNode(makeIslandLabel())
        }

        makeLights().forEach { scene.rootNode.addChildNode($0) }
        scene.rootNode.addChildNode(
            makeCamera(position: cardCamPos, target: cardCamTarget, fov: cardCamFov)
        )
        return scene
    }

    // MARK: - シーン(上陸)

    /// 航海中と同じ海・船・航海士・島を、浜へ到着した瞬間の構図へ組み直す。
    /// 静止画へ切り替えず、航海の世界がそのまま上陸記録へ続く。
    static func makeLandfallScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = nightBG
        scene.rootNode.addChildNode(makeSea(moonX: -5.2))
        scene.rootNode.addChildNode(makeStars(count: 560))
        scene.rootNode.addChildNode(makeMoon(position: SCNVector3(-5.2, 3.6, -17)))
        scene.rootNode.addChildNode(makeHorizon())

        let islandPosition = SCNVector3(1.65, 0, -0.72)
        let island = makeIsland(
            position: islandPosition,
            scale: SCNVector3(1.16, 1.16, 1.16)
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
        travel.addChildNode(makeRipples())
        let bob = SCNNode()
        bob.name = "landfallBoatBob"
        let boat = makeBoatModel(BoatCustomization.currentParts)
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

    /// Web Gulls と同じ10羽の低ポリの群れ。各ノードの軌道値はKVCでアニメータへ渡す。
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
        let vertices = [
            SCNVector3(0, 0, 0), SCNVector3(1, 0.06, -0.12), SCNVector3(0.34, 0, 0.24)
        ]
        let source = SCNGeometrySource(vertices: vertices)
        var indices: [UInt32] = [0, 1, 2]
        let data = Data(bytes: &indices, count: indices.count * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(data: data, primitiveType: .triangles, primitiveCount: 1, bytesPerIndex: 4)
        for (index, gull) in flock.enumerated() {
            let bird = SCNNode()
            bird.name = "gull_\(index)"
            bird.scale = SCNVector3(gull.scale, gull.scale, gull.scale)
            for wingIndex in 0..<2 {
                let geometry = SCNGeometry(sources: [source], elements: [element])
                let material = unlitMaterial(sand)
                material.diffuse.contents = sand.withAlphaComponent(0.5)
                geometry.firstMaterial = material
                let wing = SCNNode(geometry: geometry)
                wing.name = wingIndex == 0 ? "leftWing" : "rightWing"
                wing.scale.x = wingIndex == 0 ? -1 : 1
                wing.eulerAngles.z = wingIndex == 0 ? -0.22 : 0.22
                bird.addChildNode(wing)
            }
            root.addChildNode(bird)
        }
        return root
    }

    /// Web VoyagingWorld の定数をそのまま使うログイン後の航海ホーム。
    /// Webと同様、航海を始めた時刻ではなく現在の朝・昼・夕・夜を海へ反映する。
    static func makeVoyagingScene(
        showIsland: Bool,
        timeOfDay: AftideHomeTimeOfDay = .night,
        date: Date = .now
    ) -> SCNScene {
        let palette = timeOfDay == .night ? AftideHomePalette.voyagingNight : timeOfDay.palette
        let scene = SCNScene()
        scene.background.contents = UIColor(rgb: palette.sky)
        scene.fogColor = UIColor(rgb: palette.fog)
        scene.fogStartDistance = 12
        scene.fogEndDistance = 34
        if palette.stars > 0 {
            scene.rootNode.addChildNode(makeStars(count: palette.stars))
        }

        scene.rootNode.addChildNode(makeVoyagingCelestial(timeOfDay: timeOfDay, date: date))
        scene.rootNode.addChildNode(
            HomeIslandOceanEffects.makeScene(layout: .timerVoyage).root
        )
        // Web Horizon と同じ、z=-20の細い平面。円形の水平線は投影位置が変わり、
        // 同じカメラ定数でも世界全体が上下にずれて見えるため使わない。
        scene.rootNode.addChildNode(makeHorizon())
        scene.rootNode.addChildNode(makeVoyagingGulls())

        if showIsland {
            // Web ApproachingIsland と同じ二重group構造。開始時の距離はアニメータが
            // 経過時間から決め、25分ほどかけて最終位置へ近づける。
            let approach = SCNNode()
            approach.name = "approachingIsland"
            approach.scale = SCNVector3(0.7, 0.7, 0.7)
            approach.addChildNode(makeIsland())
            scene.rootNode.addChildNode(approach)
        }

        let travel = SCNNode()
        travel.name = "travel"
        travel.eulerAngles.y = 0.1
        travel.scale = SCNVector3(0.55, 0.55, 0.55)
        travel.addChildNode(makeWake())
        let bob = SCNNode()
        bob.name = "boatBob"
        let boat = makeBoatModel(BoatCustomization.currentParts)
        attachNavigator(to: boat)
        bob.addChildNode(boat)
        // しぶきは船体と一緒に上下する。甲板が波へ落ちた拍子に上がって見える。
        bob.addChildNode(VoyageBowSpray.makeNode())
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
        camera.camera?.exposureOffset = 0.32
        // タイマーの近景だけ、甲板・航海士・島の接地感を補う。
        // ブルームや被写界深度は輪郭をぼかすため使わず、控えめなAOと色調整に留める。
        camera.camera?.contrast = 0.06
        camera.camera?.saturation = 1.04
        camera.camera?.screenSpaceAmbientOcclusionIntensity = 0.42
        camera.camera?.screenSpaceAmbientOcclusionRadius = 1.25
        camera.camera?.screenSpaceAmbientOcclusionBias = 0.025
        camera.camera?.screenSpaceAmbientOcclusionDepthThreshold = 2.0
        scene.rootNode.addChildNode(camera)
        return scene
    }

    /// 平面の頂点自体を上下させる三層の波。XY平面のlocal +Zが、ノード回転後のworld +Y。
    /// 外周は水平線へ自然につなぐため振幅を落とす。
    private static let voyagingSeaClockOrigin = ProcessInfo.processInfo.systemUptime

    /// SCNSceneごとの`scn_frame.time`へ、process内で共有する経過時間を足す。
    /// 遷移Sceneからguided Sceneへ作り直しても波・反射の位相が巻き戻らない。
    private static var voyagingSeaTimeOffset: Float {
        let origin = voyagingSeaClockOrigin
        return Float(ProcessInfo.processInfo.systemUptime - origin)
    }

    private static let voyagingSeaGeometryShader = """
    #pragma arguments
    float uVoyageTimeOffset;
    #pragma body
    float2 p = _geometry.position.xy;
    float t = scn_frame.time + uVoyageTimeOffset;
    float phaseA = p.x * 0.31 + p.y * 0.17 - t * 0.72;
    float phaseB = -p.x * 0.19 + p.y * 0.43 + t * 0.51;
    float phaseC = p.x * 0.91 + p.y * 0.67 - t * 1.16;
    float edge = 1.0 - smoothstep(21.0, 29.0, length(p));
    float height =
        sin(phaseA) * 0.070
        + sin(phaseB) * 0.042
        + sin(phaseC) * 0.014;
    float dhdx =
        cos(phaseA) * 0.070 * 0.31
        + cos(phaseB) * 0.042 * -0.19
        + cos(phaseC) * 0.014 * 0.91;
    float dhdy =
        cos(phaseA) * 0.070 * 0.17
        + cos(phaseB) * 0.042 * 0.43
        + cos(phaseC) * 0.014 * 0.67;
    _geometry.position.z += height * edge;
    _geometry.normal = normalize(float3(-dhdx * edge, -dhdy * edge, 1.0));
    """

    /// 波高・傾斜から陰影を作り、遠景の空色反射、細かな波頭、船尾の航跡を重ねる。
    /// 色はPCCSパレットのsRGB値なので、最後にlinearへ変換して白っぽい映像を防ぐ。
    private static let voyagingSeaSurfaceShader = """
    #pragma arguments
    float3 uSea;
    float3 uDeep;
    float3 uLight;
    float3 uFog;
    float uVoyageTimeOffset;
    #pragma body
    float2 p = (_surface.diffuseTexcoord - float2(0.5)) * 60.0;
    float r = length(p) / 30.0;
    float t = scn_frame.time + uVoyageTimeOffset;

    float phaseA = p.x * 0.31 + p.y * 0.17 - t * 0.72;
    float phaseB = -p.x * 0.19 + p.y * 0.43 + t * 0.51;
    float phaseC = p.x * 0.91 + p.y * 0.67 - t * 1.16;
    float height =
        sin(phaseA) * 0.070
        + sin(phaseB) * 0.042
        + sin(phaseC) * 0.014;
    float2 slope = float2(
        cos(phaseA) * 0.070 * 0.31
            + cos(phaseB) * 0.042 * -0.19
            + cos(phaseC) * 0.014 * 0.91,
        cos(phaseA) * 0.070 * 0.17
            + cos(phaseB) * 0.042 * 0.43
            + cos(phaseC) * 0.014 * 0.67
    );
    float3 waveNormal = normalize(float3(-slope, 1.0));

    float depth = smoothstep(0.08, 1.0, r);
    float3 col = mix(uSea, uDeep, depth * 0.72);
    // 波の向きに応じた明暗。単なる模様ではなく面の起伏として読める強さ。
    float facing = clamp(dot(waveNormal, normalize(float3(-0.28, 0.18, 0.94))), 0.0, 1.0);
    float directionalShade = clamp(
        0.5 + slope.x * 7.2 + slope.y * 5.4,
        0.0,
        1.0
    );
    col *= 0.84 + directionalShade * 0.24;

    // 遠景では空と霧を水面へ薄く映し込み、水平線へ連続させる。
    float grazing = smoothstep(0.30, 0.96, r);
    col = mix(col, mix(uLight, uFog, 0.52), grazing * 0.16);

    // 高い波頭だけに出る不規則な反射。均等な白線にしない。
    float micro = sin(p.x * 3.8 - p.y * 2.7 + t * 1.7)
        * sin(p.x * 1.6 + p.y * 4.1 - t * 1.1);
    float crest = smoothstep(0.060, 0.115, height + micro * 0.018);
    float broken = 0.58 + 0.42 * sin(p.x * 2.9 + p.y * 1.7 - t * 1.4);
    col = mix(col, uLight, crest * broken * 0.18);

    // 日月の反射は一本の帯ではなく、波で細かく切れた光片として描く。
    float lane = exp(-((p.x - 5.1) * (p.x - 5.1)) / 6.4);
    float shimmer = 0.5 + 0.5
        * sin(p.y * 1.23 - t * 1.19)
        * sin(p.x * 1.08 + t * 0.54);
    float specular = pow(facing, 52.0) * (0.45 + 0.55 * max(micro, 0.0));
    col = mix(col, uLight, clamp(lane * shimmer * 0.21 + specular * 0.20, 0.0, 0.34));

    // 船尾(-X)に残る、幅が少しずつ広がる二筋の航跡。
    float aft = (1.0 - smoothstep(-0.45, 0.35, p.x)) * smoothstep(-19.0, -1.1, p.x);
    float wakeWidth = 0.20 + max(-p.x, 0.0) * 0.045;
    float wakeL = exp(-pow((p.y - wakeWidth) / 0.15, 2.0));
    float wakeR = exp(-pow((p.y + wakeWidth) / 0.15, 2.0));
    float wakeBreak = 0.45 + 0.55 * sin(-p.x * 2.6 + t * 1.9);
    col = mix(col, uLight, aft * (wakeL + wakeR) * wakeBreak * 0.13);

    _surface.diffuse = float4(pow(clamp(col, 0.0, 1.0), float3(2.2)), 1.0);
    """

    private static func makeVoyagingSea(palette: AftideHomePalette) -> SCNNode {
        let root = SCNNode()
        root.name = "voyagingSea"

        let plane = SCNPlane(width: 60, height: 60)
        // 約1.6万頂点。60fpsを保ちつつ、近景で波の輪郭が角張らない密度。
        plane.widthSegmentCount = 128
        plane.heightSegmentCount = 128
        let material = SCNMaterial()
        // WebのShaderMaterialと同じ非照明。PBR光を重ねると同じ#1E5348でも
        // iOSだけ明るい緑へ転ぶため、波の陰影・反射はsurface shader内で完結させる。
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(rgb: palette.sea)
        material.isDoubleSided = true
        material.shaderModifiers = [
            .geometry: voyagingSeaGeometryShader,
            .surface: voyagingSeaSurfaceShader
        ]
        material.setValue(colorVector(palette.sea), forKey: "uSea")
        material.setValue(colorVector(palette.seaDeep), forKey: "uDeep")
        material.setValue(colorVector(palette.reflection), forKey: "uLight")
        material.setValue(colorVector(palette.fog), forKey: "uFog")
        material.setValue(
            NSNumber(value: voyagingSeaTimeOffset),
            forKey: "uVoyageTimeOffset"
        )
        plane.firstMaterial = material
        let surface = SCNNode(geometry: plane)
        surface.name = "voyagingSeaSurface"
        surface.eulerAngles.x = -.pi / 2
        root.addChildNode(surface)

        // 波が持ち上がった隙間から背景色が覗かないための深い水の下地。
        let underlayPlane = SCNPlane(width: 60, height: 60)
        underlayPlane.firstMaterial = unlitMaterial(UIColor(rgb: palette.seaDeep))
        let underlay = SCNNode(geometry: underlayPlane)
        underlay.name = "voyagingSeaUnderlay"
        underlay.position.y = -0.14
        underlay.eulerAngles.x = -.pi / 2
        root.addChildNode(underlay)
        return root
    }

    private static func makeVoyagingHorizon(palette: AftideHomePalette) -> SCNNode {
        // カメラを360°回しても途切れない、水平方向を一周する淡い水平線。
        let ring = SCNTorus(ringRadius: 25, pipeRadius: 0.022)
        ring.ringSegmentCount = 128
        ring.pipeSegmentCount = 5
        let material = unlitMaterial(UIColor(rgb: palette.reflection))
        material.diffuse.contents = UIColor(rgb: palette.reflection).withAlphaComponent(0.14)
        material.writesToDepthBuffer = false
        ring.firstMaterial = material
        let node = SCNNode(geometry: ring)
        node.name = "voyagingHorizon"
        node.position = SCNVector3(0.8, 0.035, 0)
        return node
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
        let sphere = SCNSphere(radius: timeOfDay == .night ? 1.1 : 1.25)
        sphere.segmentCount = 24
        let material = unlitMaterial(UIColor(rgb: palette.reflection))
        material.emission.contents = UIColor(rgb: palette.reflection)
        material.emission.intensity = timeOfDay == .night ? 0.9 : 0.62
        sphere.firstMaterial = material
        let node = SCNNode(geometry: sphere)
        node.name = "voyagingSun"
        node.position = SCNVector3(
            timeOfDay == .morning ? -5.2 : (timeOfDay == .day ? 0.8 : 5.1),
            timeOfDay == .day ? 5.1 : (timeOfDay == .evening ? 1.25 : 3.3),
            -5.5
        )
        node.scale = timeOfDay == .night
            ? SCNVector3(0.4, 0.4, 0.4)
            : SCNVector3(0.72, 0.72, 0.72)
        return node
    }

    private static func makeVoyagingLights(
        timeOfDay: AftideHomeTimeOfDay
    ) -> [SCNNode] {
        let palette = timeOfDay == .night ? AftideHomePalette.voyagingNight : timeOfDay.palette
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(rgb: palette.ambient)
        ambient.light?.intensity = timeOfDay == .day ? 850 : 520

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.color = UIColor(rgb: palette.key)
        key.light?.intensity = timeOfDay == .day ? 1_450 : 1_080
        key.position = SCNVector3(-6, 8, -5)
        key.look(at: SCNVector3(0.8, 1.15, 0))

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.color = UIColor(rgb: palette.fill)
        fill.light?.intensity = 240
        fill.position = SCNVector3(5, 3, 6)
        fill.look(at: SCNVector3(0.8, 1.15, 0))
        return [ambient, key, fill]
    }

    private static func colorVector(_ rgb: UInt) -> SCNVector3 {
        SCNVector3(
            Float((rgb >> 16) & 0xFF) / 255,
            Float((rgb >> 8) & 0xFF) / 255,
            Float(rgb & 0xFF) / 255
        )
    }

    // MARK: - 没入エディタ専用の部品(Web VoyageWorld)

    /// タップ波紋リング(船タップで一周広がる)。既定は非表示。
    private static func makeTapRing() -> SCNNode {
        let path = UIBezierPath(ovalIn: CGRect(x: -1, y: -1, width: 2, height: 2))
        path.append(UIBezierPath(ovalIn: CGRect(x: -0.9, y: -0.9, width: 1.8, height: 1.8)).reversing())
        path.usesEvenOddFillRule = true
        path.flatness = 0.02
        let shape = SCNShape(path: path, extrusionDepth: 0)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = ripple
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        shape.firstMaterial = m
        let node = SCNNode(geometry: shape)
        node.name = "tapRing"
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(0, 0.03, 0)
        node.isHidden = true
        return node
    }

    /// 流れ星。細長い淡いプレーン。既定は非表示。動きはコーディネータが与える。
    private static func makeShootingStar() -> SCNNode {
        let plane = SCNPlane(width: 1.8, height: 0.035)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = sand
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        plane.firstMaterial = m
        let node = SCNNode(geometry: plane)
        node.name = "shootingStar"
        node.isHidden = true
        node.opacity = 0
        return node
    }

    /// 島の上に浮かぶ、入力中の島名ラベル(ビルボード)。テキストはコーディネータが更新する。
    static func makeIslandLabel() -> SCNNode {
        let plane = SCNPlane(width: 0.01, height: 0.01)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        plane.firstMaterial = m
        let node = SCNNode(geometry: plane)
        node.name = "islandLabel"
        node.position = SCNVector3(3.5, 1.9, -0.9)
        node.constraints = [SCNBillboardConstraint()]
        node.isHidden = true
        return node
    }

    /// 島名ラベルのテクスチャ(と縦横)を更新する。空なら隠す。
    static func updateIslandLabel(_ node: SCNNode, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { node.isHidden = true; return }
        let font = UIFont.systemFont(ofSize: 48, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: sand]
        let textSize = (trimmed as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 28
        let w = textSize.width + pad * 2
        let h = textSize.height + pad
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h))
        let image = renderer.image { _ in
            (trimmed as NSString).draw(
                at: CGPoint(x: pad, y: pad / 2), withAttributes: attrs
            )
        }
        node.geometry?.firstMaterial?.diffuse.contents = image
        // 世界の高さ ~0.62 に合わせて横幅を決める。
        let worldH: CGFloat = 0.62
        let worldW = worldH * (w / h)
        (node.geometry as? SCNPlane)?.width = worldW
        (node.geometry as? SCNPlane)?.height = worldH
        node.isHidden = false
    }

    // MARK: - シーン(装い: 船スタジオ)

    /// 装い専用の夜の海。Web版の Canvas と同じく、船と航海士のどちらを
    /// 表示しても背景・照明・カメラはこの一つの世界を使い続ける。
    static func makeDressStudioWorld() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = nightBG
        scene.fogColor = nightBG
        scene.fogStartDistance = 11
        scene.fogEndDistance = 30
        scene.rootNode.addChildNode(makeSea(moonX: -8.5))
        scene.rootNode.addChildNode(makeStars(count: 900))
        scene.rootNode.addChildNode(makeMoon(position: SCNVector3(-8.5, 5.6, -14)))
        scene.rootNode.addChildNode(makeRipples())

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
        bob.addChildNode(makeBoatModel(parts))
        travel.addChildNode(bob)
        return travel
    }

    /// 夜の海に浮かぶ自分の船(Web BoatStudio NightSea)。
    static func makeBoatStudioScene(parts: BoatParts) -> SCNScene {
        let scene = makeDressStudioWorld()
        scene.rootNode.addChildNode(makeBoatStudioSubject(parts: parts))
        return scene
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

    static func makeNavigatorScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = nightBG
        scene.rootNode.addChildNode(makeSea(moonX: -8))
        scene.rootNode.addChildNode(makeStars(count: 320))
        scene.rootNode.addChildNode(makeMoon(position: SCNVector3(-8, 4.2, -14)))
        let nav = makeNavigator()
        nav.scale = SCNVector3(1.7, 1.7, 1.7)
        scene.rootNode.addChildNode(nav)
        makeLights().forEach { scene.rootNode.addChildNode($0) }
        scene.rootNode.addChildNode(
            makeCamera(position: SCNVector3(0, 1.6, 4.2), target: SCNVector3(0, 1.05, 0), fov: 40)
        )
        return scene
    }
}

// MARK: - アニメータ(Web useFrame 相当)

/// Web VoyagingWorld の船・航跡・カモメを毎フレーム駆動する。
final class VoyagingHomeAnimator: NSObject, SCNSceneRendererDelegate {
    var resting = false
    private var elapsedSeconds: Float = 0
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
    private weak var bob: SCNNode?
    private weak var wake: SCNNode?
    private weak var approachingIsland: SCNNode?
    private weak var seaMaterial: SCNMaterial?
    private var gulls: [SCNNode] = []
    private let sailor = PhoenixAnimator()

    /// 帆としぶきへ実際に渡している風の強さ。段階が変わっても数秒かけて寄せる。
    private var windStrength: Float = 0
    private var sailMaterials: [SCNMaterial] = []
    private var spraySystems: [SCNParticleSystem] = []

    /// 船の揺れと旗の位相。速さを経過時間に掛けるのではなく、毎フレーム足す。
    ///
    /// 掛け算だと、風が変わって周波数が動いた瞬間に位相が `t × Δω` だけ飛ぶ。
    /// 一時間航海したあとの `t` は大きいので、段階が上がるちょうどその瞬間に
    /// 船が震えて見えてしまう。休憩の出入りでも同じことが起きる。
    private var bobPhase: Float = 0
    private var rollPhase: Float = 0
    private var pitchPhase: Float = 1.2
    private var flagPhase: Float = 0

    /// 風の強さが目標へ寄る速さ(時定数・秒)。出航・休憩明けはこの四倍ほど、
    /// おおよそ二秒半かけて次の絵に落ち着く。
    private static let windEase: Float = 0.625

    /// 休憩中は帆を緩めて凪へ戻す。再開すれば全力の風に戻る。
    private var windTarget: Float {
        resting ? 0.10 : VoyageWind.sailingStrength
    }

    func setElapsedSeconds(_ seconds: Int) {
        elapsedSeconds = max(elapsedSeconds, Float(max(0, seconds)))
        placeApproachingIsland()
    }

    private func bind(_ scene: SCNScene) {
        self.scene = scene
        bob = scene.rootNode.childNode(withName: "boatBob", recursively: true)
        wake = scene.rootNode.childNode(withName: "wake", recursively: true)
        approachingIsland = scene.rootNode.childNode(withName: "approachingIsland", recursively: false)
        seaMaterial = scene.rootNode
            .childNode(withName: HomeIslandOceanEffects.surfaceNodeName, recursively: true)?
            .geometry?.firstMaterial
        gulls = scene.rootNode.childNode(withName: "gulls", recursively: false)?.childNodes ?? []
        sailMaterials = VoyageSailFlutter.materials(in: scene.rootNode)
        spraySystems = VoyageBowSpray.systems(in: scene.rootNode)
        // 作り直したシーンでも、いま吹いている風の続きから始める。
        applyWind(windStrength, at: 0)
        placeApproachingIsland()
    }

    /// 風の強さを絵へ配る。帆の孕み、しぶきの量、航跡の白さがここで揃う。
    private func applyWind(_ wind: Float, at t: Float) {
        for material in sailMaterials {
            material.setValue(NSNumber(value: wind), forKey: "uWind")
        }
        if !spraySystems.isEmpty {
            // 一定量を出し続けると霧になる。舳先が波を叩く拍に合わせて波を作り、
            // 谷でも細く出し続けることで、途切れずに脈を打つ飛沫にする。
            let surge = max(0, sin(t * 1.9))
            let beat = 0.34 + 0.66 * powf(surge, 2.2)
            let rate = CGFloat(wind * beat) * VoyageBowSpray.peakBirthRate
            for system in spraySystems {
                system.birthRate = rate
            }
        }
    }

    private func placeApproachingIsland() {
        // Web: k = 1 + 1.2 * exp(-elapsed / 1500)。
        // 開始直後は遠く、作業した時間だけゆっくり最終位置へ近づく。
        let k = 1 + 1.2 * exp(-elapsedSeconds / 1_500)
        approachingIsland?.position = SCNVector3(6.5 * k, 0, -5.5 * k)
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let currentScene = renderer.scene else { return }
        if scene !== currentScene { bind(currentScene) }
        if startTime == nil { startTime = time; lastTime = time }
        let t = Float(time - (startTime ?? time))
        let dt = Float(min(max(time - lastTime, 0), 0.1))
        lastTime = time
        seaMaterial?.setValue(
            NSNumber(value: HomeIslandOceanEffects.currentTime),
            forKey: "uTime"
        )
        if !resting {
            elapsedSeconds += dt
            placeApproachingIsland()
        }

        // 段階が上がった瞬間に絵が飛ばないよう、目標へ 2 秒半かけて寄せる。
        let target = windTarget
        if abs(target - windStrength) > 0.0005 {
            windStrength += (target - windStrength) * min(1, dt / VoyagingHomeAnimator.windEase)
        } else {
            windStrength = target
        }
        applyWind(windStrength, at: t)

        // 風が強いほど大きく速く揺れ、風上へわずかに傾く。
        let swell = 1 + windStrength * 0.55
        bobPhase += dt * (resting ? 0.34 : 0.8 + windStrength * 0.35)
        rollPhase += dt * (resting ? 0.28 : 0.6)
        pitchPhase += dt * (resting ? 0.25 : 0.5)
        flagPhase += dt * (resting ? 1.2 : 5.2 + windStrength * 3.4)

        if let bob {
            let heel = windStrength * 0.055
            bob.position.y = sin(bobPhase) * (resting ? 0.025 : 0.06) * swell
            bob.eulerAngles.z = sin(rollPhase) * (resting ? 0.012 : 0.03) * swell - heel
            bob.eulerAngles.x = sin(pitchPhase) * (resting ? 0.007 : 0.015) * swell
            bob.childNode(withName: "boatFlag", recursively: true)?
                .eulerAngles.y = sin(flagPhase) * (resting ? 0.07 : 0.22 + windStrength * 0.16)
        }
        wake?.opacity = CGFloat(
            (0.34 + sin(t * 1.4) * 0.07) * (1 + windStrength * 0.62)
        )

        for (index, bird) in gulls.enumerated() {
            guard flock.indices.contains(index) else { continue }
            let config = flock[index]
            let radius = config.radius
            let height = config.height
            let omega = config.omega
            let flap = config.flap
            let phase = config.phase
            let angle = phase + t * omega
            bird.position = SCNVector3(
                cos(angle) * radius,
                height + sin(t * 0.4 + phase) * 0.22,
                sin(angle) * radius
            )
            let vx = -sin(angle) * omega
            let vz = cos(angle) * omega
            bird.eulerAngles.y = atan2(-vx, -vz)
            bird.eulerAngles.z = omega > 0 ? -0.18 : 0.18
            let beat = -0.22 + sin(t * flap + phase) * 0.34
            bird.childNode(withName: "leftWing", recursively: false)?.eulerAngles.z = beat
            bird.childNode(withName: "rightWing", recursively: false)?.eulerAngles.z = -beat
        }

        sailor.bindIfNeeded(currentScene)
        sailor.pose = resting ? .sit : PhoenixPose.selected
        sailor.step(t: t, dt: dt)
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
        let view = VoyagingSceneKitView()
        let guidedIntroduction = renderingMode == .guidedIntroduction
        view.scene = VoyageSceneKit.makeVoyagingScene(
            showIsland: showIsland,
            timeOfDay: timeOfDay,
            date: date
        )
        view.backgroundColor = UIColor(rgb: timeOfDay.palette.sky)
        view.antialiasingMode = guidedIntroduction ? .multisampling2X : .multisampling4X
        view.preferredFramesPerSecond = guidedIntroduction ? 30 : 60
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
        view.rendersContinuously = !reduceMotion
        view.isPlaying = !reduceMotion
        context.coordinator.reduceMotion = reduceMotion
        view.delegate = reduceMotion ? nil : context.coordinator
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
        context.coordinator.setDate(date)
        context.coordinator.animator.resting = resting
        context.coordinator.animator.setElapsedSeconds(elapsedSeconds)
        return view
    }

    func updateUIView(_ view: VoyagingSceneKitView, context: Context) {
        if context.coordinator.showIsland != showIsland ||
            context.coordinator.timeOfDay != timeOfDay {
            context.coordinator.showIsland = showIsland
            context.coordinator.timeOfDay = timeOfDay
            view.scene = VoyageSceneKit.makeVoyagingScene(
                showIsland: showIsland,
                timeOfDay: timeOfDay,
                date: date
            )
            view.backgroundColor = UIColor(rgb: timeOfDay.palette.sky)
            view.pointOfView = view.scene?.rootNode.childNode(withName: "camera", recursively: false)
            context.coordinator.bindCamera()
        }
        context.coordinator.setDate(date)
        context.coordinator.onTapWorld = onTapWorld
        context.coordinator.animator.resting = resting
        context.coordinator.animator.setElapsedSeconds(elapsedSeconds)
        context.coordinator.setReduceMotion(
            accessibilityReduceMotion || UIAccessibility.isReduceMotionEnabled
        )
        context.coordinator.setOrbit(
            azimuthOffset: azimuthOffset,
            polarOffset: polarOffset,
            distanceScale: distanceScale
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
        let animator = VoyagingHomeAnimator()
        var showIsland = false
        var timeOfDay: AftideHomeTimeOfDay = .night
        var reduceMotion = false
        var onTapWorld: () -> Void
        private weak var view: SCNView?
        private weak var camera: SCNNode?
        private weak var moon: SCNNode?

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
            bindCamera()
            bindMoon()
        }

        /// 設定アプリやControl Centerから表示中にReduce Motionが変わった場合も、
        /// SCNViewの描画loopとdelegateを同じframeで安全に切り替える。
        func setReduceMotion(_ value: Bool) {
            guard reduceMotion != value, let view else { return }
            reduceMotion = value
            view.rendersContinuously = !value
            view.isPlaying = !value
            view.delegate = value ? nil : self
            if value {
                azimuthDelta = 0
                polarDelta = 0
                view.setNeedsDisplay()
            }
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
            animator.renderer(renderer, updateAtTime: time)
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
