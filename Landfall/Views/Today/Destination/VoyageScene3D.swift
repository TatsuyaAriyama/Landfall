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

enum VoyageSceneKit {
    // 配色(web/src/three と同値)
    static let nightBG = UIColor(rgb: 0x123830)   // NIGHT_BG
    static let seaBase = UIColor(rgb: 0x1E5348)   // SEA_COLOR
    static let seaDeep = nightBG
    static let sand = UIColor(rgb: 0xEADEBD)      // SAND(帆・島・月光)
    static let beach = UIColor(rgb: 0xDCCFA9)     // BEACH(浜)
    static let wood = UIColor(rgb: 0x5A2A15)      // WOOD(マスト・ブーム)
    static let ember = UIColor(rgb: 0xF3C065)     // 点灯ブイ
    static let buoyDim = UIColor(rgb: 0x4A3A2A)   // 未達ブイ
    static let ripple = UIColor(rgb: 0x7FB8A6)    // 波紋

    // 航路(Web VoyageScene と同値)。目標の島は遠い — 航路を長くとって一つ一つを離す。
    static let xStart: Float = -5.2
    static let xEnd: Float = 2.6

    // カード(ホームの主役)の establishing 構図。航海の全景を、引き+俯瞰の斜め(3/4)で
    // 綺麗に一望する(真横を避ける)。没入エディタの入場もここから寄っていく(Web と同値)。
    static let cardCamPos = SCNVector3(2.2, 8.2, 14.0)
    static let cardCamTarget = SCNVector3(0.2, 0.5, 0.2)
    static let cardCamFov: CGFloat = 44

    static func boatX(_ ratio: Double) -> Float {
        xStart + Float(min(max(ratio, 0), 1)) * (xEnd - xStart)
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

    /// 放射グラデ(縁だけ夜色へ)+中心の月明かりの溜まり+月の真下に立つ月光の筋(シマー付き)。
    private static let seaSurfaceShader = """
    #pragma arguments
    float moonX;
    #pragma body
    float2 uv = _surface.diffuseTexcoord;
    float2 p = float2((uv.x - 0.5) * 80.0, (0.5 - uv.y) * 80.0);
    float r = length(p) / 30.0;
    float3 seaC = float3(0.1176, 0.3255, 0.2824);   // #1E5348
    float3 deepC = float3(0.0706, 0.2196, 0.1882);  // #123830
    float3 moonC = float3(0.7490, 0.8392, 0.7765);  // #BFD6C6
    float3 col = mix(seaC, deepC, smoothstep(0.42, 1.0, r));
    col += (moonC - seaC) * 0.06 * (1.0 - smoothstep(0.0, 0.5, r));
    float dx = p.x - moonX;
    float along = smoothstep(-5.0, 13.0, p.y);
    float w = mix(2.8, 0.7, along);
    float band = exp(-(dx * dx) / (w * w));
    float t = scn_frame.time;
    float shimmer = 0.55 + 0.45 * sin(p.y * 1.1 - t * 1.4) * sin(p.x * 0.9 + t * 0.7);
    float streak = clamp(band * along * shimmer, 0.0, 1.0) * 0.5;
    col = mix(col, moonC, streak);
    // SceneKitはリニア色空間で描くため、sRGBで計算した色をリニアへ変換して渡す
    // (これをしないと全体が白っぽく浮く)。
    _surface.diffuse = float4(pow(col, 2.2), 1.0);
    """

    static func makeSea(moonX: Float) -> SCNNode {
        let plane = SCNPlane(width: 80, height: 80)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = seaBase
        m.shaderModifiers = [.surface: seaSurfaceShader]
        m.setValue(NSNumber(value: moonX), forKey: "moonX")
        plane.firstMaterial = m
        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2
        return node
    }

    // MARK: - 空(月・星・水平線)

    static func makeMoon(position: SCNVector3) -> SCNNode {
        let sphere = SCNSphere(radius: 1.1)
        sphere.segmentCount = 20
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = nightBG
        m.emission.contents = sand
        m.emission.intensity = 0.95   // Web emissiveIntensity 0.95
        sphere.firstMaterial = m
        let node = SCNNode(geometry: sphere)
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
        let plane = SCNPlane(width: 60, height: 0.08)
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

    // MARK: - 島(Web Island と同配置)

    static func makeIsland() -> SCNNode {
        let group = SCNNode()
        group.name = "island"

        let beachGeo = SCNCone(topRadius: 1.9, bottomRadius: 2.05, height: 0.07)
        beachGeo.radialSegmentCount = 9
        beachGeo.firstMaterial = litMaterial(beach, roughness: 0.95)
        let beachNode = SCNNode(geometry: beachGeo)
        beachNode.position = SCNVector3(0, 0.03, 0.1)
        group.addChildNode(beachNode)

        let hill = SCNCone(topRadius: 0, bottomRadius: 1.25, height: 1.05)
        hill.radialSegmentCount = 7
        hill.firstMaterial = flatMaterial(sand)
        let hillNode = SCNNode(geometry: hill)
        hillNode.position = SCNVector3(0, 0.5, 0)
        hillNode.eulerAngles.y = 0.4
        group.addChildNode(hillNode)

        let hill2 = SCNCone(topRadius: 0, bottomRadius: 0.85, height: 0.72)
        hill2.radialSegmentCount = 6
        hill2.firstMaterial = flatMaterial(sand)
        let hill2Node = SCNNode(geometry: hill2)
        hill2Node.position = SCNVector3(0.8, 0.34, 0.35)
        hill2Node.eulerAngles.y = 1.1
        group.addChildNode(hill2Node)

        let knoll = SCNSphere(radius: 0.6)
        knoll.segmentCount = 8
        knoll.firstMaterial = flatMaterial(sand)
        let knollNode = SCNNode(geometry: knoll)
        knollNode.position = SCNVector3(-0.85, 0.08, 0.25)
        group.addChildNode(knollNode)

        group.position = SCNVector3(3.5, 0, -0.9)
        return group
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

    /// 帆船一式(Web BoatModel 完全移植)。"boatBob" 直下に組み、揺れは外側のアニメータが担う。
    static func makeBoatModel(_ parts: BoatParts) -> SCNNode {
        let model = SCNNode()
        model.name = "boatModel"

        // 船体
        let hullNode = SCNNode(geometry: makeHullGeometry(color: parts.hull))
        hullNode.name = "boatHull"
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
        let size = CGSize(width: 64, height: 8)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let colors = [
                UIColor.white.withAlphaComponent(0).cgColor,
                UIColor.white.withAlphaComponent(0.5).cgColor,
                UIColor.white.withAlphaComponent(0.9).cgColor,
            ] as CFArray
            let locations: [CGFloat] = [0, 0.7, 1]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero, end: CGPoint(x: size.width, y: 0), options: []
                )
            }
        }
        let plane = SCNPlane(width: 2.3, height: 0.4)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        plane.firstMaterial = m
        let node = SCNNode(geometry: plane)
        node.name = "wake"
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(-2.15, 0.025, 0)
        node.opacity = 0.34
        return node
    }

    // MARK: - ステップの小島(航路に浮かぶ低ポリの島。巡っていく)

    static let verdant = UIColor(rgb: 0x5DCAA5)   // 達成した島の緑
    static let isletRock = UIColor(rgb: 0x7A6B57) // 小岩

    /// ステップ1つ=航路に浮かぶ「島」。目標地点なので存在感を持たせる(船と釣り合う大きさ)。
    /// 未達=静かな砂の島、達成=緑が芽吹き浜に灯がともる。前後に散らして群島に。ピンは廃止。
    static func makeStepIslet(index: Int, total: Int, done: Bool) -> SCNNode {
        let group = SCNNode()
        group.name = "step_\(index)"

        // 浜(水際の平たい円盤)
        let beachGeo = SCNCone(topRadius: 0.56, bottomRadius: 0.74, height: 0.09)
        beachGeo.radialSegmentCount = 9
        beachGeo.firstMaterial = litMaterial(beach, roughness: 0.95)
        let beachNode = SCNNode(geometry: beachGeo)
        beachNode.position = SCNVector3(0, 0.045, 0)
        group.addChildNode(beachNode)

        // 丘(低ポリの山)。達成=芽吹いた緑で高く、未達=静かな砂で低め。
        let hillH: Float = done ? 0.72 : 0.52
        let hillGeo = SCNCone(topRadius: 0, bottomRadius: 0.46, height: CGFloat(hillH))
        hillGeo.radialSegmentCount = 6
        hillGeo.firstMaterial = litMaterial(done ? verdant : sand, roughness: 0.9)
        let hillNode = SCNNode(geometry: hillGeo)
        hillNode.position = SCNVector3(-0.05, 0.09 + hillH / 2, 0)
        hillNode.eulerAngles.y = Float(index) * 1.7   // 島ごとに向きを変えて表情を出す
        group.addChildNode(hillNode)

        // 副丘(小さな二つ目の起伏)でシルエットに厚みを出す
        let knollGeo = SCNCone(topRadius: 0, bottomRadius: 0.3, height: done ? 0.4 : 0.3)
        knollGeo.radialSegmentCount = 6
        knollGeo.firstMaterial = litMaterial(done ? verdant : sand, roughness: 0.9)
        let knollNode = SCNNode(geometry: knollGeo)
        knollNode.position = SCNVector3(0.34, 0.09 + (done ? 0.2 : 0.15), 0.12)
        knollNode.eulerAngles.y = Float(index) * 0.9
        group.addChildNode(knollNode)

        // 小岩(シルエットに変化を与える)
        let rockGeo = SCNSphere(radius: 0.17)
        rockGeo.segmentCount = 6
        rockGeo.firstMaterial = litMaterial(isletRock, roughness: 0.95)
        let rockNode = SCNNode(geometry: rockGeo)
        rockNode.position = SCNVector3(-0.42, 0.07, 0.18)
        rockNode.scale = SCNVector3(1, 0.66, 1)
        group.addChildNode(rockNode)

        if done {
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
        }

        // 前後に散らして群島感を出す(一直線に並べない)。
        let x = xStart + (Float(index + 1) / Float(total + 1)) * (xEnd - xStart)
        let z: Float = 0.7 + Float(index % 2) * 0.7
        group.position = SCNVector3(x, 0, z)
        return group
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
    static func makeScene(ratio: Double, steps: [Bool], immersive: Bool = false) -> SCNScene {
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
        for (i, done) in steps.enumerated() {
            scene.rootNode.addChildNode(makeStepIslet(index: i, total: steps.count, done: done))
        }

        // 航路上の船。波紋+航跡ごと進む(Web: group scale 0.55, rot y 0.1)。
        let travel = SCNNode()
        travel.name = "travel"
        travel.position = SCNVector3(boatX(ratio), 0, 0)
        travel.eulerAngles.y = 0.1
        travel.scale = SCNVector3(0.55, 0.55, 0.55)
        travel.addChildNode(makeRipples())
        travel.addChildNode(makeWake())
        let bob = SCNNode()
        bob.name = "boatBob"
        bob.addChildNode(makeBoatModel(BoatCustomization.currentParts))
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

    /// 夜の海に浮かぶ自分の船(Web BoatStudio NightSea)。
    static func makeBoatStudioScene(parts: BoatParts) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = nightBG
        scene.rootNode.addChildNode(makeSea(moonX: -8.5))
        scene.rootNode.addChildNode(makeStars(count: 620))
        scene.rootNode.addChildNode(makeMoon(position: SCNVector3(-8.5, 5.6, -14)))
        let travel = SCNNode()
        travel.name = "travel"
        travel.addChildNode(makeRipples())
        let bob = SCNNode()
        bob.name = "boatBob"
        bob.addChildNode(makeBoatModel(parts))
        travel.addChildNode(bob)
        scene.rootNode.addChildNode(travel)
        makeLights().forEach { scene.rootNode.addChildNode($0) }
        scene.rootNode.addChildNode(
            makeCamera(position: SCNVector3(3.1, 1.7, 4.3), target: SCNVector3(0, 0.7, 0), fov: 40)
        )
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

/// 船の揺れ・波紋・航跡・進行・カメラのゆらぎを毎フレーム駆動する。
/// Web BoatModel/Ripples/Wake/VoyageSea の式と同値。
final class VoyageAnimator: NSObject, SCNSceneRendererDelegate {
    var targetX: Float = 0
    /// カメラをゆらすか(カードのみ。手回し可の画面では触らない)。
    var swayCamera = false
    var animate = true

    private var startTime: TimeInterval?
    private weak var boundScene: SCNScene?
    private weak var travel: SCNNode?
    private weak var bob: SCNNode?
    private weak var wake: SCNNode?
    private weak var camera: SCNNode?
    private var rippleNodes: [SCNNode] = []
    private var lastTime: TimeInterval = 0

    private func bind(_ scene: SCNScene) {
        boundScene = scene
        let root = scene.rootNode
        travel = root.childNode(withName: "travel", recursively: false)
        bob = travel?.childNode(withName: "boatBob", recursively: false)
        wake = travel?.childNode(withName: "wake", recursively: true)
        camera = root.childNode(withName: "camera", recursively: false)
        rippleNodes = (0..<3).compactMap { root.childNode(withName: "ripple\($0)", recursively: true) }
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard animate, let scene = renderer.scene else { return }
        if boundScene !== scene { bind(scene) }
        if startTime == nil { startTime = time; lastTime = time }
        let t = Float(time - (startTime ?? time))
        let dt = Float(min(max(time - lastTime, 0), 0.1))
        lastTime = time

        // 進行(ratio変化へ滑らかに寄せる。Web damp 1.1)
        if let travel {
            let x = travel.position.x
            travel.position.x = x + (targetX - x) * min(1, 1.6 * dt)
        }
        // 錨泊の揺れ(Web BoatModel)
        if let bob {
            bob.position.y = sin(t * 0.8) * 0.06
            bob.eulerAngles.z = sin(t * 0.6) * 0.03
            bob.eulerAngles.x = sin(t * 0.5 + 1.2) * 0.015
        }
        // 旗のはためき(Web flagGroup rot.y = sin(t*5.2)*0.22)。再構築されうるので毎回探す。
        if let flag = bob?.childNode(withName: "boatFlag", recursively: true) {
            flag.eulerAngles.y = sin(t * 5.2) * 0.22
        }
        // 波紋(Web Ripples: 周期7秒・位相ずらし3枚)
        for (i, node) in rippleNodes.enumerated() {
            let phase = (t / 7 + Float(i) / 3).truncatingRemainder(dividingBy: 1)
            let s = 0.8 + phase * 5.5
            node.scale = SCNVector3(s, s, 1)
            node.opacity = CGFloat(sin(min(phase * 3, 1) * .pi / 2) * (1 - phase) * 0.2)
        }
        // 航跡の明滅(Web Wake)
        wake?.opacity = CGFloat(0.34 + sin(t * 1.4) * 0.07)
        // カメラのごくわずかな揺れ(酔わない振幅。Web VoyageSea)。establishing 構図を基準に揺らす。
        if swayCamera, let camera {
            let b = VoyageSceneKit.cardCamPos
            camera.position = SCNVector3(b.x + sin(t * 0.22) * 0.10, b.y + sin(t * 0.35 + 1.0) * 0.06, b.z)
            camera.look(at: VoyageSceneKit.cardCamTarget)
        }
    }
}

// MARK: - SwiftUI ラッパ

/// 目的地の3Dビュー。ratio で船が進み、steps でブイが点灯する。
struct VoyageSceneView: UIViewRepresentable {
    var ratio: Double
    var steps: [Bool]
    var animate: Bool = true
    var allowsCameraControl: Bool = false
    /// 没入(全画面)構図か。月が左上奥になり、星が増える(Web VoyageWorld)。
    var immersive: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = VoyageSceneKit.makeScene(ratio: ratio, steps: steps, immersive: immersive)
        view.backgroundColor = VoyageSceneKit.nightBG
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = allowsCameraControl
        view.autoenablesDefaultLighting = false
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        view.rendersContinuously = animate && !reduceMotion
        let animator = context.coordinator.animator
        animator.animate = animate && !reduceMotion
        animator.targetX = VoyageSceneKit.boatX(ratio)
        animator.swayCamera = !allowsCameraControl
        view.delegate = animator
        context.coordinator.stepsKey = steps.map { $0 ? "1" : "0" }.joined()
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let key = steps.map { $0 ? "1" : "0" }.joined()
        if key != context.coordinator.stepsKey {
            // ブイの本数/点灯が変わったらシーンを作り直す。
            context.coordinator.stepsKey = key
            view.scene = VoyageSceneKit.makeScene(ratio: ratio, steps: steps, immersive: immersive)
        }
        context.coordinator.animator.targetX = VoyageSceneKit.boatX(ratio)
        view.allowsCameraControl = allowsCameraControl
    }

    final class Coordinator {
        let animator = VoyageAnimator()
        var stepsKey = ""
    }
}

/// 装い: 海に浮かぶ自分の船(色をカスタム)。ドラッグで一周できる。
struct BoatSceneView: UIViewRepresentable {
    var parts: BoatParts

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = VoyageSceneKit.makeBoatStudioScene(parts: parts)
        view.backgroundColor = VoyageSceneKit.nightBG
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        view.rendersContinuously = !reduceMotion
        context.coordinator.animator.animate = !reduceMotion
        view.delegate = context.coordinator.animator
        context.coordinator.key = key
        // ゆっくり一周して船体まで見せる(Web BoatStudio の autoRotate 相当)。
        if !reduceMotion,
           let travel = view.scene?.rootNode.childNode(withName: "travel", recursively: false) {
            travel.runAction(.repeatForever(.rotateBy(x: 0, y: -2 * .pi, z: 0, duration: 48)), forKey: "turn")
        }
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        // 色・ライン・旗が変わったら、船だけ作り直す(カメラの手回し視点は保たれる)。
        guard key != context.coordinator.key else { return }
        context.coordinator.key = key
        guard let bob = view.scene?.rootNode.childNode(withName: "boatBob", recursively: true) else { return }
        bob.childNode(withName: "boatModel", recursively: false)?.removeFromParentNode()
        bob.addChildNode(VoyageSceneKit.makeBoatModel(parts))
    }

    private var key: String {
        let stripe = parts.stripe?.hashValue ?? 0
        return "\(parts.sail.hashValue)|\(parts.jib.hashValue)|\(parts.hull.hashValue)|\(stripe)|\(parts.flag)"
    }

    final class Coordinator {
        let animator = VoyageAnimator()
        var key = ""
    }
}

/// 装い: 海に立つ自分の航海士(プレイヤー)。ドラッグで一周できる。
struct NavigatorSceneView: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = VoyageSceneKit.makeNavigatorScene()
        view.backgroundColor = VoyageSceneKit.nightBG
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.rendersContinuously = !UIAccessibility.isReduceMotionEnabled
        if !UIAccessibility.isReduceMotionEnabled,
           let nav = view.scene?.rootNode.childNode(withName: "navigator", recursively: false) {
            let up = SCNAction.moveBy(x: 0, y: 0.05, z: 0, duration: 2.2)
            up.timingMode = .easeInEaseOut
            nav.runAction(.repeatForever(.sequence([up, up.reversed()])), forKey: "bob")
        }
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}
}

// MARK: - 没入エディタの世界(Web VoyageWorld 相当)

enum VoyagePhase { case enter, idle, exit }

/// 目的地の没入エディタの3D世界。押すとカードの遠景から近景へドリーインし、
/// idle中は自前のオービット操作で一周でき、ブイ/船/月をタップできる。閉じるは逆再生。
struct ImmersiveVoyageView: UIViewRepresentable {
    var ratio: Double
    var steps: [Bool]
    var islandName: String
    /// 閉じる要求(true にするとドリーアウト→onClosed)。
    var closeRequested: Bool
    var onToggleStep: (Int) -> Void
    /// idle(操作可能)になったら true。遷移中は編集UIを隠すために使う。
    var onIdleChange: (Bool) -> Void
    var onClosed: () -> Void
    var onTapBoat: () -> Void
    /// 海など「何も無い所」をタップしたとき(編集UIを隠して世界に入り込む)。
    var onTapWorld: () -> Void

    func makeCoordinator() -> WorldCoordinator {
        WorldCoordinator(onToggleStep: onToggleStep, onIdleChange: onIdleChange,
                         onClosed: onClosed, onTapBoat: onTapBoat, onTapWorld: onTapWorld)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = VoyageSceneKit.makeScene(ratio: ratio, steps: steps, immersive: true)
        view.backgroundColor = VoyageSceneKit.nightBG
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false            // オービットは自前(Web OrbitControls と同じ制約)
        view.autoenablesDefaultLighting = false
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        view.rendersContinuously = !reduceMotion

        let coord = context.coordinator
        coord.attach(view: view, reduceMotion: reduceMotion)
        coord.targetX = VoyageSceneKit.boatX(ratio)
        coord.stepsKey = steps.map { $0 ? "1" : "0" }.joined()
        if let label = view.scene?.rootNode.childNode(withName: "islandLabel", recursively: false) {
            VoyageSceneKit.updateIslandLabel(label, text: islandName)
        }
        view.delegate = coord

        // 視点操作: 1本指パン=回転 / ピンチ=ズーム(カメラコントローラを自前駆動)。タップ=各操作。
        let pan = UIPanGestureRecognizer(target: coord, action: #selector(WorldCoordinator.onPan(_:)))
        pan.maximumNumberOfTouches = 1   // 2本指(ピンチ)では回転させない
        view.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: coord, action: #selector(WorldCoordinator.onPinch(_:)))
        view.addGestureRecognizer(pinch)
        let tap = UITapGestureRecognizer(target: coord, action: #selector(WorldCoordinator.onTap(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coord = context.coordinator
        let key = steps.map { $0 ? "1" : "0" }.joined()
        if key != coord.stepsKey {
            coord.stepsKey = key
            coord.rebuildBuoys(steps: steps)
        }
        coord.targetX = VoyageSceneKit.boatX(ratio)
        if let label = view.scene?.rootNode.childNode(withName: "islandLabel", recursively: false) {
            VoyageSceneKit.updateIslandLabel(label, text: islandName)
        }
        if closeRequested { coord.requestExit() }
    }
}

/// 没入世界の駆動役。カメラ(ドリー/オービット)・タップ・毎フレームの演出。
final class WorldCoordinator: NSObject, SCNSceneRendererDelegate {
    private let onToggleStep: (Int) -> Void
    private let onIdleChange: (Bool) -> Void
    private let onClosed: () -> Void
    private let onTapBoat: () -> Void
    private let onTapWorld: () -> Void

    init(onToggleStep: @escaping (Int) -> Void, onIdleChange: @escaping (Bool) -> Void,
         onClosed: @escaping () -> Void, onTapBoat: @escaping () -> Void,
         onTapWorld: @escaping () -> Void) {
        self.onToggleStep = onToggleStep
        self.onIdleChange = onIdleChange
        self.onClosed = onClosed
        self.onTapBoat = onTapBoat
        self.onTapWorld = onTapWorld
    }

    var targetX: Float = 0
    var stepsKey = ""
    private weak var view: SCNView?
    private weak var scene: SCNScene?
    private weak var camera: SCNNode?
    private var reduceMotion = false

    // 遠景(カードと同じ establishing 構図)/近景。
    private let farPos = VoyageSceneKit.cardCamPos
    private let farTarget = VoyageSceneKit.cardCamTarget
    private let dolly = 1.2

    private var phase: VoyagePhase = .enter
    private var phaseStart: TimeInterval?
    private var fromPos = SCNVector3Zero

    // 近景のオービット状態(target 周りの球面座標)。
    private var target = SCNVector3(0, 0.5, -0.5)
    private var distance: Float = 7.5
    private var azimuth: Float = 0
    private var polar: Float = .pi * 0.34
    private var maxPolar: Float = .pi * 0.46
    private let minPolar: Float = .pi * 0.16
    private let minDist: Float = 3.2
    private let maxDist: Float = 11

    private var startTime: TimeInterval?
    private var lastTime: TimeInterval = 0
    private var exitRequested = false
    /// idle に入って視点操作(回転/ズーム)を受け付けてよいか。
    private var orbitEnabled = false

    // 演出タイマ
    private var boatHopAt: TimeInterval = -.infinity
    private var moonGlowAt: TimeInterval = -.infinity
    private var shootNextAt: TimeInterval = 6
    private var shootStartAt: TimeInterval?
    private var shootFrom = SCNVector3Zero
    private var shootVel = SCNVector3Zero

    func attach(view: SCNView, reduceMotion: Bool) {
        self.view = view
        self.scene = view.scene
        self.reduceMotion = reduceMotion
        camera = view.scene?.rootNode.childNode(withName: "camera", recursively: false)
        view.pointOfView = camera
        computeNear()
        if reduceMotion {
            // ジャンプカット: 最初から近景で idle。
            phase = .idle
            camera?.position = nearPos()
            camera?.look(at: target)
            enableOrbit()
            onIdleChange(true)
        } else {
            phase = .enter
            camera?.position = farPos
            camera?.look(at: farTarget)
            onIdleChange(false)
        }
    }

    /// 近景の構図を、船の位置(targetX)と画面アスペクトから決める(Web WorldScene.near)。
    private func computeNear() {
        let aspect = Float((view?.bounds.width ?? 1) / max(view?.bounds.height ?? 1, 1))
        let islandX: Float = 3.5
        let wide = aspect >= 1.05
        let boatX = targetX
        let tx = boatX + (islandX - boatX) * (wide ? 0.5 : 0.08)
        let pos: SCNVector3
        if wide {
            pos = SCNVector3(tx - 1.2, 1.9, 5.4)
            target = SCNVector3(tx, 0.5, -0.5)
            maxPolar = .pi * 0.52
        } else {
            pos = SCNVector3(tx - 1.0, 1.9, 7.2)
            target = SCNVector3(tx, -0.25, -0.5)
            maxPolar = .pi * 0.46
        }
        // pos から球面座標(distance/azimuth/polar)を得る。
        let off = SCNVector3(pos.x - target.x, pos.y - target.y, pos.z - target.z)
        distance = max(minDist, min(maxDist, off.length))
        polar = max(minPolar, min(maxPolar, acos(off.y / max(distance, 0.0001))))
        azimuth = atan2(off.x, off.z)
    }

    private func nearPos() -> SCNVector3 {
        SCNVector3(
            target.x + distance * sin(polar) * sin(azimuth),
            target.y + distance * cos(polar),
            target.z + distance * sin(polar) * cos(azimuth)
        )
    }

    /// idle の視点操作。回転は SceneKit 標準コントローラの慣性付きターンテーブル(drei
    /// OrbitControls 相当)を、パン=回転 / ピンチ=ズーム として自前ジェスチャで駆動する
    /// (allowsCameraControl だとズームの当たりが不安定なため、明示的に効かせる)。
    private func enableOrbit() {
        guard let view else { return }
        view.pointOfView = camera
        let c = view.defaultCameraController
        c.pointOfView = camera
        c.interactionMode = .orbitTurntable
        c.target = target
        c.automaticTarget = false
        c.inertiaEnabled = true          // = enableDamping
        // 水平線の下(海中)へ潜らせず、真上へも回り込ませない(Web polar 0.16π..0.46π 相当)。
        c.minimumVerticalAngle = 4
        c.maximumVerticalAngle = 68
        orbitEnabled = true
    }

    func requestExit() {
        guard phase == .idle, !exitRequested else { return }
        exitRequested = true
        orbitEnabled = false                // 退場ドリー中は視点操作を止める
        if reduceMotion { onClosed(); return }
        onIdleChange(false)
        phase = .exit
        phaseStart = nil
    }

    // MARK: 視点操作(パン=回転 / ピンチ=ズーム)

    @objc func onPan(_ g: UIPanGestureRecognizer) {
        guard orbitEnabled, let view else { return }
        let c = view.defaultCameraController
        let loc = g.location(in: view)
        let vp = view.bounds.size
        switch g.state {
        case .began:
            c.beginInteraction(loc, withViewport: vp)
        case .changed:
            c.continueInteraction(loc, withViewport: vp, sensitivity: 1.0)
        case .ended, .cancelled:
            let v = g.velocity(in: view)
            c.endInteraction(loc, withViewport: vp, velocity: CGPoint(x: v.x / 120, y: v.y / 120))
        default:
            break
        }
    }

    @objc func onPinch(_ g: UIPinchGestureRecognizer) {
        guard orbitEnabled, let view, let cam = camera else { return }
        let c = view.defaultCameraController
        // 指を広げる(scale>1)= 拡大(近づく)。
        let delta = Float(g.scale - 1) * 4.0
        g.scale = 1
        c.dolly(by: delta, onScreenPoint: CGPoint(x: view.bounds.midX, y: view.bounds.midY), viewport: view.bounds.size)
        // 近づき/離れすぎを防ぐ(注視点からの距離を [3, 26] にクランプ)。
        let off = SCNVector3(cam.position.x - target.x, cam.position.y - target.y, cam.position.z - target.z)
        let d = off.length
        let minD: Float = 3, maxD: Float = 26
        if d < minD || d > maxD {
            let k = max(minD, min(maxD, d)) / max(d, 0.0001)
            cam.position = SCNVector3(target.x + off.x * k, target.y + off.y * k, target.z + off.z * k)
        }
    }

    // MARK: タップ(ブイ/船/月/外側)

    @objc func onTap(_ g: UITapGestureRecognizer) {
        guard phase == .idle, let v = view else { return }
        let p = g.location(in: v)
        let hits = v.hitTest(p, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue])
        for hit in hits {
            var node: SCNNode? = hit.node
            while let n = node {
                if let name = n.name {
                    if name.hasPrefix("step_"), name != "step_glow", let idx = Int(name.dropFirst(5)) {
                        onToggleStep(idx)   // 反転・plink・保存は SwiftUI 側
                        return
                    }
                    if name == "boatHit" || name == "boatModel" {
                        boatHopAt = lastTime
                        onTapBoat()
                        return
                    }
                    if name == "moon" { moonGlowAt = lastTime; return }
                }
                node = n.parent
            }
        }
        // どのオブジェクトにも当たらない = 海など「外側」のタップ。編集UIを隠して世界に入り込む。
        onTapWorld()
    }

    // MARK: ブイの作り直し(数や達成が変わったとき。カメラは保つ)

    func rebuildBuoys(steps: [Bool]) {
        guard let root = scene?.rootNode else { return }
        root.childNodes.filter { $0.name?.hasPrefix("step_") == true }.forEach { $0.removeFromParentNode() }
        for (i, done) in steps.enumerated() {
            root.addChildNode(VoyageSceneKit.makeStepIslet(index: i, total: steps.count, done: done))
        }
    }

    // MARK: 毎フレーム

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let scene else { return }
        if startTime == nil { startTime = time; lastTime = time }
        let t = Float(time - (startTime ?? time))
        let dt = Float(min(max(time - lastTime, 0), 0.1))
        lastTime = time
        let root = scene.rootNode

        // カメラのドリー(enter/exit)。
        if phase == .enter || phase == .exit, !reduceMotion {
            if phaseStart == nil {
                phaseStart = time
                fromPos = phase == .enter ? farPos : (camera?.position ?? farPos)
            }
            let raw = Float(min((time - (phaseStart ?? time)) / dolly, 1))
            let k = easeInOutCubic(raw)
            let toPos = phase == .enter ? nearPos() : farPos
            let fromT = phase == .enter ? farTarget : target
            let toT = phase == .enter ? target : farTarget
            camera?.position = fromPos.lerp(toPos, k)
            camera?.look(at: fromT.lerp(toT, k))
            if raw >= 1 {
                // 完了通知・カメラ操作の有効化はメインスレッドで(ここは描画スレッド)。
                if phase == .enter {
                    phase = .idle
                    camera?.position = nearPos()
                    camera?.look(at: target)
                    DispatchQueue.main.async { self.enableOrbit(); self.onIdleChange(true) }
                } else {
                    DispatchQueue.main.async { self.onClosed() }
                }
            }
        }

        let travel = root.childNode(withName: "travel", recursively: false)
        // 進行(ratio 変化へ滑らかに寄せる)。
        if let travel {
            travel.position.x += (targetX - travel.position.x) * min(1, 1.6 * dt)
        }
        // 船の揺れ / タップのホップ。
        if let bob = travel?.childNode(withName: "boatBob", recursively: false) {
            let hop = Float((time - boatHopAt) / 1.1)
            if hop >= 0, hop < 1 {
                let hp = min(hop / 0.32, 1)
                bob.position.y = sin(.pi * hp) * 0.22
            } else {
                bob.position.y = sin(t * 0.8) * 0.06
            }
            bob.eulerAngles.z = sin(t * 0.6) * 0.03
            bob.eulerAngles.x = sin(t * 0.5 + 1.2) * 0.015
        }
        // タップ波紋リング。
        if let ring = travel?.childNode(withName: "tapRing", recursively: false) {
            let rp = Float((time - boatHopAt) / 1.1)
            if rp >= 0, rp < 1 {
                ring.isHidden = false
                let s = 1 + rp * 3.6
                ring.scale = SCNVector3(s, s, 1)
                ring.opacity = CGFloat((1 - rp) * 0.42)
            } else {
                ring.isHidden = true
            }
        }
        // 波紋 3枚。
        for i in 0..<3 {
            if let node = travel?.childNode(withName: "ripple\(i)", recursively: true) {
                let phase = (t / 7 + Float(i) / 3).truncatingRemainder(dividingBy: 1)
                let s = 0.8 + phase * 5.5
                node.scale = SCNVector3(s, s, 1)
                node.opacity = CGFloat(sin(min(phase * 3, 1) * .pi / 2) * (1 - phase) * 0.2)
            }
        }
        travel?.childNode(withName: "wake", recursively: true)?.opacity = CGFloat(0.34 + sin(t * 1.4) * 0.07)

        // 月のタップ発光。
        if let moon = root.childNode(withName: "moon", recursively: false) {
            let p = Float((time - moonGlowAt) / 1.3)
            moon.geometry?.firstMaterial?.emission.intensity = (p >= 0 && p < 1) ? CGFloat(0.95 + sin(.pi * p) * 0.8) : 0.95
        }

        // 流れ星。
        updateShootingStar(root: root, time: time)
    }

    private func updateShootingStar(root: SCNNode, time: TimeInterval) {
        guard !reduceMotion, let star = root.childNode(withName: "shootingStar", recursively: false) else { return }
        if shootStartAt == nil {
            if time < shootNextAt { return }
            shootStartAt = time
            let sign: Float = Bool.random() ? 1 : -1
            shootFrom = SCNVector3(-sign * (3 + Float.random(in: 0...6)), 6 + Float.random(in: 0...3.5), -21 - Float.random(in: 0...4))
            shootVel = SCNVector3(sign * (8 + Float.random(in: 0...4)), -(2 + Float.random(in: 0...2)), 0)
            return
        }
        let p = Float((time - (shootStartAt ?? time)) / 1.5)
        if p >= 1 {
            shootStartAt = nil
            shootNextAt = time + 8 + Double(Float.random(in: 0...12))
            star.isHidden = true
            return
        }
        star.isHidden = false
        star.position = SCNVector3(shootFrom.x + shootVel.x * p, shootFrom.y + shootVel.y * p, shootFrom.z + shootVel.z * p)
        star.eulerAngles.z = atan2(shootVel.y, shootVel.x)
        star.opacity = CGFloat(sin(.pi * p) * 0.5)
    }
}

private func easeInOutCubic(_ v: Float) -> Float {
    let d = Double(v)
    let r = d < 0.5 ? 4 * d * d * d : 1 - pow(-2 * d + 2, 3) / 2
    return Float(r)
}

private extension SCNVector3 {
    var length: Float { sqrt(x * x + y * y + z * z) }
    func lerp(_ to: SCNVector3, _ k: Float) -> SCNVector3 {
        SCNVector3(x + (to.x - x) * k, y + (to.y - y) * k, z + (to.z - z) * k)
    }
}
