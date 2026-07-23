import SceneKit
import SwiftUI
import UIKit

// 目的地の夜の海(実3D / SceneKit)。Web版 VoyageScene を移植。
// 低ポリ・フラット・グラデ無し・影無しの世界観に合わせる:
//   夜の海(平面)/ 二つ丘の島 / 低ポリ帆船(進捗で前進)/ 月(発光)/ ステップのブイ(達成で点灯)。

private extension UIColor {
    /// 0xRRGGBB から UIColor(SceneKit用。トレイトに依存しない固定色)。
    convenience init(rgb: UInt) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum VoyageSceneKit {
    // 配色(LFColor と同値)
    static let sea = UIColor(rgb: 0x184A40)       // harborTeal(海)
    static let seaDeep = UIColor(rgb: 0x123830)   // 縁/背景に溶ける夜色
    static let sand = UIColor(rgb: 0xEADEBD)      // harborSand(帆・島)
    static let ember = UIColor(rgb: 0xF3C065)     // emberGold(月・点灯ブイ)
    static let dim = UIColor(rgb: 0x3A3226)       // 未達ブイ
    static let mast = UIColor(rgb: 0x4A1B0C)      // deepRust(マスト)

    // 航路(Web と同じ X_START→X_END)
    static let xStart: Float = -3.4
    static let xEnd: Float = 1.8
    static let islandPos = SCNVector3(3.8, 0, -0.9)

    /// 進捗 ratio(0..1)で船の位置を返す。
    static func boatX(_ ratio: Double) -> Float {
        xStart + Float(min(max(ratio, 0), 1)) * (xEnd - xStart)
    }

    // 低ポリのフラット陰影(面ごとの法線をフラグメントで再計算)。
    private static let flatShade: [SCNShaderModifierEntryPoint: String] = [
        .surface: "_surface.normal = normalize(cross(dfdx(_surface.position), dfdy(_surface.position)));"
    ]

    private static func flatMaterial(_ color: UIColor, flat: Bool = true) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = color
        m.isDoubleSided = true
        if flat { m.shaderModifiers = flatShade }
        return m
    }

    private static func unlitMaterial(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.isDoubleSided = true
        return m
    }

    // MARK: - シーン

    static func makeScene(ratio: Double, steps: [Bool]) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = seaDeep
        scene.rootNode.addChildNode(makeSea())
        scene.rootNode.addChildNode(makeMoon())
        scene.rootNode.addChildNode(makeIsland())
        for (i, done) in steps.enumerated() {
            scene.rootNode.addChildNode(makeBuoy(index: i, total: steps.count, done: done))
        }
        scene.rootNode.addChildNode(makeBoat(ratio: ratio))
        makeLights().forEach { scene.rootNode.addChildNode($0) }
        scene.rootNode.addChildNode(makeCamera())
        return scene
    }

    private static func makeSea() -> SCNNode {
        let plane = SCNPlane(width: 80, height: 80)
        plane.firstMaterial = unlitMaterial(sea)
        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2   // 水平に寝かせる
        node.position = SCNVector3(0, 0, -6)
        return node
    }

    private static func makeMoon() -> SCNNode {
        let sphere = SCNSphere(radius: 1.1)
        sphere.segmentCount = 18
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = ember
        m.emission.contents = sand
        sphere.firstMaterial = m
        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(-0.4, 2.35, -13)   // 上部のテキスト帯を避け、空の低めに置く
        // 月光の水面反射は、フラットな板だとスラブに見えてしまうので、
        // 後日シェーダで放射グラデ+筋として作る(第2段)。今は月のみ。
        return node
    }

    private static func makeIsland() -> SCNNode {
        let group = SCNNode()
        // 浜(平たい円柱)。大きすぎるとスロープに見えるので、丘の裾を囲む程度に抑える。
        let beach = SCNCylinder(radius: 1.25, height: 0.1)
        beach.radialSegmentCount = 9
        beach.firstMaterial = flatMaterial(sand)
        let beachNode = SCNNode(geometry: beach)
        beachNode.position = SCNVector3(0, 0.03, 0)
        group.addChildNode(beachNode)
        // 大きい丘(円錐)
        let hill = SCNCone(topRadius: 0, bottomRadius: 1.25, height: 1.5)
        hill.radialSegmentCount = 7
        hill.firstMaterial = flatMaterial(sand)
        let hillNode = SCNNode(geometry: hill)
        hillNode.position = SCNVector3(-0.2, 0.75, 0)
        group.addChildNode(hillNode)
        // 小さい丘
        let hill2 = SCNCone(topRadius: 0, bottomRadius: 0.85, height: 0.95)
        hill2.radialSegmentCount = 6
        hill2.firstMaterial = flatMaterial(sand)
        let hill2Node = SCNNode(geometry: hill2)
        hill2Node.position = SCNVector3(0.8, 0.5, 0.35)
        group.addChildNode(hill2Node)
        // 手前の小丘(半球)
        let knoll = SCNSphere(radius: 0.6)
        knoll.segmentCount = 8
        knoll.firstMaterial = flatMaterial(sand)
        let knollNode = SCNNode(geometry: knoll)
        knollNode.position = SCNVector3(-0.85, 0.1, 0.3)
        group.addChildNode(knollNode)
        group.position = islandPos
        return group
    }

    /// 低ポリ帆船。船体・帆・前帆は Web BoatShape の 2D シルエットを SCNShape で押し出す。
    private static func makeBoat(ratio: Double) -> SCNNode {
        let group = SCNNode()
        group.name = "boat"

        // 船体(横長・低い台形。押し出しで幅を持たせる)。
        let hull = UIBezierPath()
        hull.move(to: CGPoint(x: -0.95, y: 0))
        hull.addLine(to: CGPoint(x: 0.95, y: 0))
        hull.addLine(to: CGPoint(x: 0.7, y: -0.34))
        hull.addLine(to: CGPoint(x: -0.7, y: -0.34))
        hull.close()
        let hullGeo = SCNShape(path: hull, extrusionDepth: 0.62)
        hullGeo.chamferRadius = 0.03
        hullGeo.firstMaterial = flatMaterial(sand)
        let hullNode = SCNNode(geometry: hullGeo)
        hullNode.position = SCNVector3(0, 0.2, -0.31)  // 押し出し中心をz=0へ
        group.addChildNode(hullNode)

        // マスト
        let mastGeo = SCNCylinder(radius: 0.028, height: 1.5)
        mastGeo.firstMaterial = flatMaterial(mast, flat: false)
        let mastNode = SCNNode(geometry: mastGeo)
        mastNode.position = SCNVector3(0.05, 1.0, 0)
        group.addChildNode(mastNode)

        // メインセイル(三角)
        let mainSail = UIBezierPath()
        mainSail.move(to: CGPoint(x: 0, y: 0))
        mainSail.addLine(to: CGPoint(x: 0, y: 1.35))
        mainSail.addLine(to: CGPoint(x: -0.78, y: 0.05))
        mainSail.close()
        let mainGeo = SCNShape(path: mainSail, extrusionDepth: 0.02)
        mainGeo.firstMaterial = unlitMaterial(sand)
        let mainNode = SCNNode(geometry: mainGeo)
        mainNode.position = SCNVector3(0.04, 0.28, 0)
        group.addChildNode(mainNode)

        // 前帆(ジブ)
        let jib = UIBezierPath()
        jib.move(to: CGPoint(x: 0, y: 0))
        jib.addLine(to: CGPoint(x: 0, y: 1.15))
        jib.addLine(to: CGPoint(x: 0.62, y: 0.04))
        jib.close()
        let jibGeo = SCNShape(path: jib, extrusionDepth: 0.02)
        jibGeo.firstMaterial = unlitMaterial(sand)
        let jibNode = SCNNode(geometry: jibGeo)
        jibNode.position = SCNVector3(0.06, 0.28, 0)
        group.addChildNode(jibNode)

        group.position = SCNVector3(boatX(ratio), 0, 0)
        group.eulerAngles.y = 0.12
        return group
    }

    /// ステップの目印。柱+上球。達成で ember 点灯・未達は暗色。
    private static func makeBuoy(index: Int, total: Int, done: Bool) -> SCNNode {
        let group = SCNNode()
        group.name = "buoy_\(index)"
        let pole = SCNCylinder(radius: 0.03, height: 0.5)
        pole.firstMaterial = flatMaterial(mast, flat: false)
        let poleNode = SCNNode(geometry: pole)
        poleNode.position = SCNVector3(0, 0.25, 0)
        group.addChildNode(poleNode)
        let top = SCNSphere(radius: 0.12)
        top.segmentCount = 8
        let m = SCNMaterial()
        m.lightingModel = done ? .constant : .lambert
        m.diffuse.contents = done ? ember : dim
        if done { m.emission.contents = ember }
        top.firstMaterial = m
        let topNode = SCNNode(geometry: top)
        topNode.name = "buoyTop"
        topNode.position = SCNVector3(0, 0.55, 0)
        group.addChildNode(topNode)
        let x = xStart + (Float(index + 1) / Float(total + 1)) * (xEnd - xStart)
        group.position = SCNVector3(x, 0, 0.5)
        return group
    }

    private static func makeCamera() -> SCNNode {
        let cam = SCNCamera()
        cam.fieldOfView = 38
        cam.zNear = 0.1
        cam.zFar = 200
        let node = SCNNode()
        node.camera = cam
        node.position = SCNVector3(0.4, 2.5, 8.2)
        node.look(at: SCNVector3(0, 0.45, 0))   // 固定の斜め視点。制約ではなく向きを直接設定。
        return node
    }

    private static func makeLights() -> [SCNNode] {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(rgb: 0xFFE9C8)
        ambient.intensity = 380
        let ambientNode = SCNNode()
        ambientNode.light = ambient

        let key = SCNLight()
        key.type = .directional
        key.color = sand
        key.intensity = 900
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(-6, 8, -5)
        keyNode.eulerAngles = SCNVector3(-1.0, -0.6, 0)

        return [ambientNode, keyNode]
    }
}

// MARK: - SwiftUI ラッパ

/// 目的地の3Dビュー。ratio で船が進み、steps でブイが点灯する。
/// カードは操作不可(固定視点)、没入時は allowsCameraControl で手回し可。
struct VoyageSceneView: UIViewRepresentable {
    var ratio: Double
    var steps: [Bool]
    var animate: Bool = true
    var allowsCameraControl: Bool = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = VoyageSceneKit.makeScene(ratio: ratio, steps: steps)
        view.backgroundColor = VoyageSceneKit.seaDeep
        view.antialiasingMode = .multisampling2X
        view.allowsCameraControl = allowsCameraControl
        view.autoenablesDefaultLighting = false
        // 常時描画(船のゆれ・進行のアニメを回す)。reduce-motion 時は静止でよいが、
        // 初期フレームは必ず描く。
        view.rendersContinuously = !UIAccessibility.isReduceMotionEnabled
        context.coordinator.ratio = ratio
        context.coordinator.stepsKey = steps.map { $0 ? "1" : "0" }.joined()
        applyBob(view, animate: animate)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let key = steps.map { $0 ? "1" : "0" }.joined()
        // ステップ構成が変わったらシーンを作り直す(ブイの本数/配置が変わるため)。
        if key != context.coordinator.stepsKey {
            view.scene = VoyageSceneKit.makeScene(ratio: ratio, steps: steps)
            context.coordinator.stepsKey = key
            context.coordinator.ratio = ratio
            applyBob(view, animate: animate)
            return
        }
        // 進捗だけの変化は船の位置を動かす(アニメで滑らかに)。
        if ratio != context.coordinator.ratio,
           let boat = view.scene?.rootNode.childNode(withName: "boat", recursively: false) {
            context.coordinator.ratio = ratio
            let move = SCNAction.move(
                to: SCNVector3(VoyageSceneKit.boatX(ratio), boat.position.y, boat.position.z),
                duration: animate ? 0.9 : 0
            )
            move.timingMode = .easeInEaseOut
            boat.runAction(move)
        }
        view.allowsCameraControl = allowsCameraControl
    }

    /// 船のゆっくりした上下ゆれ(reduce-motion ではオフ)。
    private func applyBob(_ view: SCNView, animate: Bool) {
        guard animate, !UIAccessibility.isReduceMotionEnabled,
              let boat = view.scene?.rootNode.childNode(withName: "boat", recursively: false)
        else { return }
        let up = SCNAction.moveBy(x: 0, y: 0.06, z: 0, duration: 2.0)
        up.timingMode = .easeInEaseOut
        let down = up.reversed()
        boat.runAction(.repeatForever(.sequence([up, down])), forKey: "bob")
    }

    final class Coordinator {
        var ratio: Double = -1
        var stepsKey: String = ""
    }
}
