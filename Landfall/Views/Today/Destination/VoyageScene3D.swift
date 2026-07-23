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

    // 航路(Web VoyageScene と同値)
    static let xStart: Float = -3.6
    static let xEnd: Float = 1.8

    static func boatX(_ ratio: Double) -> Float {
        xStart + Float(min(max(ratio, 0), 1)) * (xEnd - xStart)
    }

    // MARK: - 素材

    /// 低ポリのフラット陰影(面法線をフラグメントで再計算)。flatShading 相当。
    private static let flatShade: [SCNShaderModifierEntryPoint: String] = [
        .surface: "_surface.normal = normalize(cross(dfdx(_surface.position), dfdy(_surface.position)));"
    ]

    static func flatMaterial(_ color: UIColor, doubleSided: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = color
        m.isDoubleSided = doubleSided
        m.shaderModifiers = flatShade
        return m
    }

    static func unlitMaterial(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.isDoubleSided = true
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
        beachGeo.firstMaterial = flatMaterial(beach)
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
    /// 端に向けて幅を絞って上から見ても船形にする(頂点を後処理)。
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

        // SCNShape の頂点再構築(端へ向けた幅絞り)は実行環境によって描画されない
        // ことがあるため行わない。三日月の側面プロフィール+面取り+フラット陰影が
        // 見た目の主役なので、押し出しのままで Web の読みは保てる。
        let shape = SCNShape(path: path, extrusionDepth: 0.5)
        shape.chamferRadius = 0.13
        shape.chamferMode = .both
        shape.firstMaterial = flatMaterial(color)
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
        geo.firstMaterial = flatMaterial(color, doubleSided: true)
        return geo
    }

    /// 帆船一式(Web BoatModel)。"boatBob" 直下に組み、揺れは外側のアニメータが担う。
    static func makeBoatModel(sail: UIColor, hull: UIColor) -> SCNNode {
        let model = SCNNode()
        model.name = "boatModel"

        let hullNode = SCNNode(geometry: makeHullGeometry(color: hull))
        hullNode.name = "boatHull"
        model.addChildNode(hullNode)

        // デッキ(少し暗い同系色の薄い蓋)
        let deckGeo = SCNCylinder(radius: 1, height: 0.06)
        deckGeo.radialSegmentCount = 14
        deckGeo.firstMaterial = flatMaterial(hull.scaled(0.72))
        let deckNode = SCNNode(geometry: deckGeo)
        deckNode.name = "boatDeck"
        deckNode.position = SCNVector3(0.05, 0.47, 0)
        deckNode.scale = SCNVector3(0.82, 1, 0.3)
        model.addChildNode(deckNode)

        // マスト
        let mastGeo = SCNCone(topRadius: 0.035, bottomRadius: 0.028, height: 2.3)
        mastGeo.radialSegmentCount = 8
        mastGeo.firstMaterial = flatMaterial(wood)
        let mastNode = SCNNode(geometry: mastGeo)
        mastNode.position = SCNVector3(0.1, 1.42, 0)
        model.addChildNode(mastNode)

        // ブーム+メインセイル(わずかに開いたトリム)
        let rig = SCNNode()
        rig.position = SCNVector3(0.1, 0, 0)
        rig.eulerAngles.y = 0.16
        let boomGeo = SCNCylinder(radius: 0.024, height: 1.15)
        boomGeo.radialSegmentCount = 8
        boomGeo.firstMaterial = flatMaterial(wood)
        let boomNode = SCNNode(geometry: boomGeo)
        boomNode.position = SCNVector3(-0.55, 0.68, 0)
        boomNode.eulerAngles.z = .pi / 2
        rig.addChildNode(boomNode)
        let mainNode = SCNNode(geometry: makeSailGeometry(width: 1.0, height: 1.8, bulge: 0.16, shear: 0, color: sail))
        mainNode.name = "boatSail"
        mainNode.position = SCNVector3(0, 0.72, 0)
        rig.addChildNode(mainNode)
        model.addChildNode(rig)

        // ジブ(前帆): 舳先からマスト頂へ斜めのラフ
        let jibNode = SCNNode(geometry: makeSailGeometry(width: 0.72, height: 1.5, bulge: 0.1, shear: 0.92, color: sail))
        jibNode.name = "boatSail"
        jibNode.position = SCNVector3(1.1, 0.62, 0)
        jibNode.eulerAngles.y = 0.12
        model.addChildNode(jibNode)

        return model
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

    // MARK: - ブイ(Web StepBuoys)

    static func makeBuoy(index: Int, total: Int, done: Bool) -> SCNNode {
        let group = SCNNode()
        group.name = "buoy_\(index)"
        let pole = SCNCone(topRadius: 0.03, bottomRadius: 0.04, height: 0.5)
        pole.radialSegmentCount = 6
        pole.firstMaterial = flatMaterial(wood)
        let poleNode = SCNNode(geometry: pole)
        poleNode.position = SCNVector3(0, 0.25, 0)
        group.addChildNode(poleNode)
        let top = SCNSphere(radius: 0.12)
        top.segmentCount = 10
        let m = SCNMaterial()
        if done {
            m.lightingModel = .constant
            m.diffuse.contents = ember
        } else {
            m.lightingModel = .lambert
            m.diffuse.contents = buoyDim
            m.shaderModifiers = flatShade
        }
        top.firstMaterial = m
        let topNode = SCNNode(geometry: top)
        topNode.position = SCNVector3(0, 0.55, 0)
        group.addChildNode(topNode)
        let x = xStart + (Float(index + 1) / Float(total + 1)) * (xEnd - xStart)
        group.position = SCNVector3(x, 0, 0.5)
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
            scene.rootNode.addChildNode(makeBuoy(index: i, total: steps.count, done: done))
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
        bob.addChildNode(makeBoatModel(
            sail: BoatCustomization.uiColor(.sail),
            hull: BoatCustomization.uiColor(.hull)
        ))
        travel.addChildNode(bob)
        scene.rootNode.addChildNode(travel)

        makeLights().forEach { scene.rootNode.addChildNode($0) }
        scene.rootNode.addChildNode(
            makeCamera(position: SCNVector3(0.4, 2.5, 8.2), target: SCNVector3(0, 0.35, 0), fov: 36)
        )
        return scene
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
        bob.addChildNode(makeBoatModel(sail: parts.sail, hull: parts.hull))
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
        // 波紋(Web Ripples: 周期7秒・位相ずらし3枚)
        for (i, node) in rippleNodes.enumerated() {
            let phase = (t / 7 + Float(i) / 3).truncatingRemainder(dividingBy: 1)
            let s = 0.8 + phase * 5.5
            node.scale = SCNVector3(s, s, 1)
            node.opacity = CGFloat(sin(min(phase * 3, 1) * .pi / 2) * (1 - phase) * 0.2)
        }
        // 航跡の明滅(Web Wake)
        wake?.opacity = CGFloat(0.34 + sin(t * 1.4) * 0.07)
        // カメラのごくわずかな揺れ(酔わない振幅。Web VoyageSea)
        if swayCamera, let camera {
            camera.position = SCNVector3(0.4 + sin(t * 0.22) * 0.07, 2.5 + sin(t * 0.35 + 1.0) * 0.04, 8.2)
            camera.look(at: SCNVector3(0, 0.35, 0))
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
        // 色が変わったら、シーンを作り直さず素材だけ差し替える(手回しの視点を保つ)。
        guard key != context.coordinator.key else { return }
        context.coordinator.key = key
        guard let model = view.scene?.rootNode.childNode(withName: "boatModel", recursively: true) else { return }
        model.enumerateChildNodes { node, _ in
            switch node.name {
            case "boatHull": node.geometry?.firstMaterial?.diffuse.contents = parts.hull
            case "boatDeck": node.geometry?.firstMaterial?.diffuse.contents = parts.hull.scaled(0.72)
            case "boatSail": node.geometry?.firstMaterial?.diffuse.contents = parts.sail
            default: break
            }
        }
        // リグ(ブーム下)の帆も拾う。
        model.childNodes.forEach { rig in
            rig.childNodes.forEach { node in
                if node.name == "boatSail" {
                    node.geometry?.firstMaterial?.diffuse.contents = parts.sail
                }
            }
        }
    }

    private var key: String { "\(parts.sail.hashValue)|\(parts.hull.hashValue)" }

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
