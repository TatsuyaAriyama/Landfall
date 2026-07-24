import SceneKit
import SwiftUI
import UIKit

// 航海士(プレイヤーキャラクター)。Web版 PhoenixModel.tsx の忠実移植。
// ローブの体積 + 燕尾のケープ(布の格子) + 尖ったフード + 提げたランタン。
// 世界(船・島)が低ポリ・フラットなのに対し、キャラクターだけは高解像度の
// スムースシェーディングで「生きもの」を際立たせる。ポーズ: 待機/歩く/掲げる/手を振る。
// 原点=接地点(足元 y=0)、前方=+X、全高≈1.35。

// MARK: - ベクトル小道具(このファイル内)

private func v3add(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
    SCNVector3(a.x + b.x, a.y + b.y, a.z + b.z)
}
private func v3sub(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
    SCNVector3(a.x - b.x, a.y - b.y, a.z - b.z)
}
private func v3cross(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
    SCNVector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}
private func v3norm(_ a: SCNVector3) -> SCNVector3 {
    let l = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
    return l > 1e-6 ? SCNVector3(a.x / l, a.y / l, a.z / l) : SCNVector3(0, 1, 0)
}
/// 指数減衰の補間(three MathUtils.damp と同式)。
private func damp(_ cur: Float, _ target: Float, _ lambda: Float, _ dt: Float) -> Float {
    cur + (target - cur) * (1 - exp(-lambda * dt))
}

// MARK: - ポーズ

enum PhoenixPose: String, CaseIterable, Identifiable {
    case idle, walk, raise, hail
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .idle: "Idle"
        case .walk: "Walk"
        case .raise: "Raise"
        case .hail: "Wave"
        }
    }
}

private struct PoseBase {
    var armRx: Float, armRz: Float, armLx: Float, armLz: Float, lean: Float, wind: Float
}
private func poseBase(_ p: PhoenixPose) -> PoseBase {
    switch p {
    case .idle:  return PoseBase(armRx: 0, armRz: 0.14, armLx: 0, armLz: -0.14, lean: 0, wind: 1)
    case .walk:  return PoseBase(armRx: 0, armRz: 0.12, armLx: 0, armLz: -0.12, lean: 0.09, wind: 1.7)
    case .raise: return PoseBase(armRx: -2.35, armRz: 0.06, armLx: 0, armLz: -0.16, lean: -0.04, wind: 1.15)
    case .hail:  return PoseBase(armRx: 0, armRz: 0.14, armLx: 0, armLz: -2.55, lean: 0, wind: 1.1)
    }
}

enum PhoenixNavigator {
    // 配色(Web PhoenixModel と同値)
    static let coral = UIColor(rgb: 0xF0997B)
    static let rust = UIColor(rgb: 0x7A3B22)
    static let rustDeep = UIColor(rgb: 0x4A1B0C)
    static let sand = UIColor(rgb: 0xEADEBD)
    static let midnight = UIColor(rgb: 0x1A1130)
    static let lantern = UIColor(rgb: 0xF3C065)

    // 布の格子(ケープ)
    static let capeRows = 16
    static let capeCols = 13

    // MARK: 素材(スムースシェーディングの PBR。フラット法線modifierは付けない)

    static func mat(_ color: UIColor, roughness: CGFloat, doubleSided: Bool = false,
                    emission: UIColor? = nil, emissionIntensity: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = 0.0
        m.isDoubleSided = doubleSided
        if let emission {
            m.emission.contents = emission
            m.emission.intensity = emissionIntensity
        }
        return m
    }

    private static var coralMat: SCNMaterial { mat(coral, roughness: 0.8) }
    private static var rustMat: SCNMaterial { mat(rust, roughness: 0.85) }
    private static var rustDeepMat: SCNMaterial { mat(rustDeep, roughness: 0.9) }
    private static var sandMat: SCNMaterial { mat(sand, roughness: 0.85) }
    private static var faceMat: SCNMaterial { mat(midnight, roughness: 0.6) }
    private static var capeMat: SCNMaterial { mat(midnight, roughness: 0.9, doubleSided: true) }
    private static var eyeMat: SCNMaterial { mat(sand, roughness: 0.7, emission: sand, emissionIntensity: 0.55) }

    // MARK: 汎用メッシュ(スムース法線)

    private static func mesh(_ verts: [SCNVector3], _ indices: [UInt32],
                             material: SCNMaterial) -> SCNGeometry {
        var normals = [SCNVector3](repeating: SCNVector3(0, 0, 0), count: verts.count)
        var i = 0
        while i + 2 < indices.count {
            let a = Int(indices[i]), b = Int(indices[i + 1]), c = Int(indices[i + 2])
            let n = v3cross(v3sub(verts[b], verts[a]), v3sub(verts[c], verts[a]))
            normals[a] = v3add(normals[a], n)
            normals[b] = v3add(normals[b], n)
            normals[c] = v3add(normals[c], n)
            i += 3
        }
        let nrm = normals.map { v3norm($0) }
        let vsrc = SCNGeometrySource(vertices: verts)
        let nsrc = SCNGeometrySource(normals: nrm)
        var idx = indices
        let data = Data(bytes: &idx, count: idx.count * MemoryLayout<UInt32>.size)
        let elem = SCNGeometryElement(data: data, primitiveType: .triangles,
                                      primitiveCount: indices.count / 3, bytesPerIndex: 4)
        let geo = SCNGeometry(sources: [vsrc, nsrc], elements: [elem])
        geo.firstMaterial = material
        return geo
    }

    /// 回転体(three LatheGeometry 相当)。profile=(半径, 高さ) を Y軸まわりに segments 分割で回す。
    private static func lathe(_ profile: [(r: Float, y: Float)], segments: Int,
                             material: SCNMaterial) -> SCNGeometry {
        var verts: [SCNVector3] = []
        for p in profile {
            for j in 0..<segments {
                let t = Float(j) / Float(segments) * 2 * .pi
                verts.append(SCNVector3(p.r * cos(t), p.y, p.r * sin(t)))
            }
        }
        var indices: [UInt32] = []
        for i in 0..<(profile.count - 1) {
            for j in 0..<segments {
                let a = UInt32(i * segments + j)
                let b = UInt32(i * segments + (j + 1) % segments)
                let d = UInt32((i + 1) * segments + j)
                let e = UInt32((i + 1) * segments + (j + 1) % segments)
                indices += [a, d, b, b, d, e]
            }
        }
        return mesh(verts, indices, material: material)
    }

    // MARK: ケープ(布の格子)

    /// 布の一点。u:-1..1(左→右)、v:0..1(肩→裾)。Web capePoint と同式。
    static func capePoint(_ u: Float, _ v: Float, _ time: Float, _ wind: Float) -> SCNVector3 {
        let width = 0.16 + 0.21 * pow(v, 1.15)
        let length = 0.38 + 0.19 * pow(abs(u), 1.4)
        let flutter = pow(v, 1.5) * wind
        let t = time * (0.7 + 0.3 * wind)
        let x = u * width + flutter * sin(t * 1.3 + v * 2.0) * 0.02
        let y = -v * length + flutter * sin(u * 2.4 + t * 1.9) * 0.012
        let z = -0.02
            - (0.24 + (wind - 1) * 0.09) * pow(v, 1.1)
            + flutter * (sin(v * 5.2 - t * 2.1) * 0.05 + sin(u * 2.6 + t * 1.5) * 0.04)
        return SCNVector3(x, y, z)
    }

    private static var capeIndices: [UInt32] = {
        var idx: [UInt32] = []
        for r in 0..<(capeRows - 1) {
            for c in 0..<(capeCols - 1) {
                let a = UInt32(r * capeCols + c)
                let b = a + 1
                let d = UInt32((r + 1) * capeCols + c)
                let e = d + 1
                idx += [a, d, b, b, d, e]
            }
        }
        return idx
    }()

    /// 現在時刻・風のケープ形状(頂点)。
    static func capeVerts(time: Float, wind: Float) -> [SCNVector3] {
        var verts: [SCNVector3] = []
        verts.reserveCapacity(capeRows * capeCols)
        for r in 0..<capeRows {
            let v = Float(r) / Float(capeRows - 1)
            for c in 0..<capeCols {
                let u = Float(c) / Float(capeCols - 1) * 2 - 1
                verts.append(capePoint(u, v, time, wind))
            }
        }
        return verts
    }

    static func makeCapeGeometry(time: Float, wind: Float) -> SCNGeometry {
        mesh(capeVerts(time: time, wind: wind), capeIndices, material: capeMat)
    }

    // MARK: 航海士の組み立て(名前付きピボット)

    static func makeNavigatorNode() -> SCNNode {
        let root = SCNNode()
        root.name = "navigator"
        root.eulerAngles.y = .pi / 2   // 正面 +Z で組み、+X 向きへ

        // 脚(股関節ピボット)。足首は裾内、丸いブーツのつま先が前へ覗く。
        for s: Float in [1, -1] {
            let leg = SCNNode()
            leg.name = s == 1 ? "legR" : "legL"
            leg.position = SCNVector3(s * 0.088, 0.42, 0)
            let ankle = SCNNode(geometry: cyl(top: 0.042, bottom: 0.048, h: 0.18, mat: rustDeepMat))
            ankle.position = SCNVector3(0, -0.22, 0.02)
            leg.addChildNode(ankle)
            let cuff = SCNNode(geometry: cyl(top: 0.062, bottom: 0.07, h: 0.06, mat: rustMat))
            cuff.position = SCNVector3(0, -0.305, 0.03)
            leg.addChildNode(cuff)
            let boot = SCNNode(geometry: sphere(0.075, seg: 14, mat: rustDeepMat))
            boot.position = SCNVector3(0, -0.368, 0.09)
            boot.scale = SCNVector3(0.95, 0.68, 1.55)
            leg.addChildNode(boot)
            root.addChildNode(leg)
        }

        // 体(呼吸のまとまり)
        let core = SCNNode()
        core.name = "core"

        // コート: 裾へ広がる袍 + 裾内の深錆の縁
        core.addChildNode(SCNNode(geometry: lathe(coatProfile, segments: 22, material: coralMat)))
        let hem = SCNNode(geometry: lathe(coatProfile, segments: 22, material: rustMat))
        hem.position = SCNVector3(0, -0.02, 0)
        hem.scale = SCNVector3(0.97, 0.35, 0.97)
        core.addChildNode(hem)

        // 肩マント
        let mantle = SCNNode(geometry: lathe(mantleProfile, segments: 22, material: coralMat))
        mantle.position = SCNVector3(0, 0.78, 0)
        core.addChildNode(mantle)

        // 留め具(sand の環 + midnight の芯)
        let clasp = SCNNode()
        clasp.position = SCNVector3(0, 0.868, 0.178)
        clasp.eulerAngles.x = -0.34
        clasp.addChildNode(SCNNode(geometry: torus(ring: 0.036, pipe: 0.011, mat: sandMat)))
        let pin = SCNNode(geometry: cyl(top: 0.019, bottom: 0.019, h: 0.02, mat: faceMat))
        pin.eulerAngles.x = .pi / 2
        clasp.addChildNode(pin)
        core.addChildNode(clasp)

        // 襟巻き
        let scarf = SCNNode(geometry: torus(ring: 0.105, pipe: 0.034, mat: sandMat))
        scarf.position = SCNVector3(0, 0.96, 0)
        scarf.eulerAngles.x = .pi / 2 + 0.08
        core.addChildNode(scarf)

        // マント(布の格子。毎フレーム波打つ)
        let cape = SCNNode(geometry: makeCapeGeometry(time: 0, wind: 1))
        cape.name = "cape"
        cape.position = SCNVector3(0, 0.93, -0.04)
        core.addChildNode(cape)

        // 頭(尖ったフード + 闇に灯る両目)
        let head = SCNNode()
        head.name = "head"
        head.position = SCNVector3(0, 0.98, 0)
        let hood = SCNNode(geometry: cone(bottom: 0.125, h: 0.3, seg: 18, mat: coralMat))
        hood.position = SCNVector3(0, 0.12, 0)
        hood.eulerAngles.x = -0.05
        head.addChildNode(hood)
        let face = SCNNode(geometry: sphere(0.075, seg: 14, mat: faceMat))
        face.position = SCNVector3(0, 0.045, 0.062)
        face.scale = SCNVector3(1, 1.1, 0.55)
        head.addChildNode(face)
        for s: Float in [1, -1] {
            let eye = SCNNode(geometry: sphere(0.015, seg: 8, mat: eyeMat))
            eye.position = SCNVector3(s * 0.028, 0.052, 0.099)
            head.addChildNode(eye)
        }
        core.addChildNode(head)

        // 左腕(手を休める)
        let armL = makeArm(lantern: false)
        armL.name = "armL"
        armL.position = SCNVector3(-0.14, 0.8, 0.01)
        armL.eulerAngles.z = -0.14
        core.addChildNode(armL)

        // 右腕 + ランタン(今日の灯を提げる)
        let armR = makeArm(lantern: true)
        armR.name = "armR"
        armR.position = SCNVector3(0.14, 0.8, 0.01)
        armR.eulerAngles.z = 0.14
        core.addChildNode(armR)

        root.addChildNode(core)
        return root
    }

    private static func makeArm(lantern hasLantern: Bool) -> SCNNode {
        let arm = SCNNode()
        let upper = SCNNode(geometry: cyl(top: 0.036, bottom: 0.044, h: 0.22, mat: coralMat))
        upper.position = SCNVector3(0, -0.1, 0)
        arm.addChildNode(upper)
        let sleeve = SCNNode(geometry: cyl(top: 0.046, bottom: 0.064, h: 0.1, mat: coralMat))
        sleeve.position = SCNVector3(0, -0.22, 0)
        arm.addChildNode(sleeve)
        let hand = SCNNode(geometry: sphere(0.048, seg: 12, mat: rustDeepMat))
        hand.position = SCNVector3(0, -0.28, 0)
        arm.addChildNode(hand)

        if hasLantern {
            let lan = SCNNode()
            lan.name = "lantern"
            lan.position = SCNVector3(0, -0.33, 0)
            let handle = SCNNode(geometry: cyl(top: 0.008, bottom: 0.008, h: 0.06, mat: rustMat))
            handle.position = SCNVector3(0, -0.03, 0)
            lan.addChildNode(handle)
            let cap = SCNNode(geometry: cone(bottom: 0.058, h: 0.05, seg: 6, mat: rustMat))
            cap.position = SCNVector3(0, -0.075, 0)
            lan.addChildNode(cap)
            let glowMat = mat(self.lantern, roughness: 0.8, emission: self.lantern, emissionIntensity: 1.5)
            let glow = SCNNode(geometry: sphere(0.042, seg: 12, mat: glowMat))
            glow.name = "lanternGlow"
            glow.position = SCNVector3(0, -0.14, 0)
            lan.addChildNode(glow)
            let base = SCNNode(geometry: cyl(top: 0.045, bottom: 0.05, h: 0.02, mat: rustMat))
            base.eulerAngles.x = .pi   // 底皿(六角の広い側を下に)
            base.position = SCNVector3(0, -0.19, 0)
            lan.addChildNode(base)
            arm.addChildNode(lan)
        }
        return arm
    }

    // MARK: プリミティブ(スムース)

    private static func cyl(top: CGFloat, bottom: CGFloat, h: CGFloat, mat: SCNMaterial) -> SCNGeometry {
        let g: SCNGeometry
        if abs(top - bottom) < 0.0001 {
            let c = SCNCylinder(radius: top, height: h); c.radialSegmentCount = 12; g = c
        } else {
            let c = SCNCone(topRadius: top, bottomRadius: bottom, height: h); c.radialSegmentCount = 12; g = c
        }
        g.firstMaterial = mat
        return g
    }
    private static func cone(bottom: CGFloat, h: CGFloat, seg: Int, mat: SCNMaterial) -> SCNGeometry {
        let c = SCNCone(topRadius: 0, bottomRadius: bottom, height: h)
        c.radialSegmentCount = seg
        c.firstMaterial = mat
        return c
    }
    private static func sphere(_ r: CGFloat, seg: Int, mat: SCNMaterial) -> SCNGeometry {
        let s = SCNSphere(radius: r); s.segmentCount = seg; s.firstMaterial = mat; return s
    }
    private static func torus(ring: CGFloat, pipe: CGFloat, mat: SCNMaterial) -> SCNGeometry {
        let t = SCNTorus(ringRadius: ring, pipeRadius: pipe)
        t.ringSegmentCount = 18; t.pipeSegmentCount = 9; t.firstMaterial = mat; return t
    }

    // コート/肩マントの回転体プロフィール(Web LatheGeometry の点列。r=半径, y=高さ)
    private static let coatProfile: [(r: Float, y: Float)] = [
        (0.235, 0.3), (0.225, 0.36), (0.205, 0.44), (0.185, 0.52), (0.165, 0.62),
        (0.148, 0.7), (0.135, 0.78), (0.118, 0.86), (0.105, 0.92),
    ]
    private static let mantleProfile: [(r: Float, y: Float)] = [
        (0.2, 0), (0.185, 0.05), (0.16, 0.11), (0.125, 0.17), (0.095, 0.21), (0.078, 0.24),
    ]

    // MARK: シーン(夜の海に立つ航海士。Web BoatStudio SailorStage 相当)

    static func makeScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = VoyageSceneKit.nightBG
        scene.rootNode.addChildNode(VoyageSceneKit.makeSea(moonX: -8.5))
        scene.rootNode.addChildNode(VoyageSceneKit.makeStars(count: 900))
        scene.rootNode.addChildNode(VoyageSceneKit.makeMoon(position: SCNVector3(-8.5, 5.6, -14)))
        scene.rootNode.addChildNode(VoyageSceneKit.makeRipples())

        let nav = makeNavigatorNode()
        nav.scale = SCNVector3(0.95, 0.95, 0.95)
        scene.rootNode.addChildNode(nav)

        VoyageSceneKit.makeLights().forEach { scene.rootNode.addChildNode($0) }

        let cam = SCNCamera()
        cam.fieldOfView = 40
        cam.zNear = 0.05
        cam.zFar = 200
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.bloomIntensity = 0
        let camNode = SCNNode()
        camNode.name = "camera"
        camNode.camera = cam
        camNode.position = SCNVector3(1.7, 1.35, 3.4)
        camNode.look(at: SCNVector3(0, 0.62, 0))
        scene.rootNode.addChildNode(camNode)
        return scene
    }
}

// MARK: - アニメータ(Web PhoenixModel useFrame の移植)

final class PhoenixAnimator: NSObject, SCNSceneRendererDelegate {
    var pose: PhoenixPose = .idle
    var animate = true

    private var startTime: TimeInterval?
    private var lastTime: TimeInterval = 0
    private weak var boundScene: SCNScene?
    private weak var core: SCNNode?
    private weak var head: SCNNode?
    private weak var armR: SCNNode?
    private weak var armL: SCNNode?
    private weak var legR: SCNNode?
    private weak var legL: SCNNode?
    private weak var lantern: SCNNode?
    private weak var cape: SCNNode?
    private weak var glowMat: SCNMaterial?

    // ポーズ基本角の現在値(POSE_BASE へ減衰補間)
    private var armRx: Float = 0, armRz: Float = 0.14
    private var armLx: Float = 0, armLz: Float = -0.14
    private var lean: Float = 0, wind: Float = 1

    private func bind(_ scene: SCNScene) {
        boundScene = scene
        guard let nav = scene.rootNode.childNode(withName: "navigator", recursively: true) else { return }
        core = nav.childNode(withName: "core", recursively: true)
        head = nav.childNode(withName: "head", recursively: true)
        armR = nav.childNode(withName: "armR", recursively: true)
        armL = nav.childNode(withName: "armL", recursively: true)
        legR = nav.childNode(withName: "legR", recursively: true)
        legL = nav.childNode(withName: "legL", recursively: true)
        lantern = nav.childNode(withName: "lantern", recursively: true)
        cape = nav.childNode(withName: "cape", recursively: true)
        glowMat = nav.childNode(withName: "lanternGlow", recursively: true)?.geometry?.firstMaterial
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard animate, let scene = renderer.scene else { return }
        if boundScene !== scene || core == nil { bind(scene) }
        if startTime == nil { startTime = time; lastTime = time }
        let t = Float(time - (startTime ?? time))
        let dt = Float(min(max(time - lastTime, 0), 0.1))
        lastTime = time

        let base = poseBase(pose)
        armRx = damp(armRx, base.armRx, 6, dt)
        armRz = damp(armRz, base.armRz, 6, dt)
        armLx = damp(armLx, base.armLx, 6, dt)
        armLz = damp(armLz, base.armLz, 6, dt)
        lean = damp(lean, base.lean, 6, dt)
        wind = damp(wind, base.wind, 4, dt)

        // マント: 布の波(頂点を書き直す)
        if let cape { cape.geometry = PhoenixNavigator.makeCapeGeometry(time: t, wind: wind) }

        let walking = pose == .walk
        let stride: Float = 5.4
        let step = sin(t * stride)

        // 体: 待機は呼吸、歩行は歩調の弾み
        if let core {
            core.position.y = walking ? abs(cos(t * stride)) * 0.035 : sin(t * 0.85) * 0.018
            core.eulerAngles.x = lean + sin(t * 0.85 + 0.9) * 0.01
            core.eulerAngles.z = walking ? step * 0.03 : 0
        }
        // 首: 見渡し。掲げ(raise)は灯を見上げる
        if let head {
            head.eulerAngles.y = sin(t * 0.3) * (walking ? 0.05 : 0.14)
            head.eulerAngles.x = pose == .raise ? -0.14 : 0
            head.eulerAngles.z = sin(t * 0.85 + 2.1) * 0.02
        }
        // 脚: 歩行は股関節から交互に振る
        let legSwing: Float = walking ? 0.55 : 0
        if let legR { legR.eulerAngles.x = damp(legR.eulerAngles.x, step * legSwing, 10, dt) }
        if let legL { legL.eulerAngles.x = damp(legL.eulerAngles.x, -step * legSwing, 10, dt) }

        // 腕: 基本角 + ポーズごとの振動
        let armSwing: Float = walking ? -step * 0.32 : sin(t * 0.85 + 0.4) * 0.03
        if let armR {
            armR.eulerAngles.x = armRx + armSwing
            armR.eulerAngles.z = armRz
        }
        if let armL {
            let wave: Float = pose == .hail ? sin(t * 7.2) * 0.3 : 0
            armL.eulerAngles.x = armLx + (walking ? step * 0.32 : sin(t * 0.85 + 1.1) * 0.025)
            armL.eulerAngles.z = armLz + wave
        }
        // ランタン: 腕の傾きを打ち消して常にほぼ鉛直に垂れる振り子
        if let lantern {
            lantern.eulerAngles.x = -(armRx + armSwing) + sin(t * 0.9) * (walking ? 0.2 : 0.1)
            lantern.eulerAngles.z = sin(t * 0.7 + 0.6) * 0.12
        }
        // 灯: 掲げたときはひときわ明るく
        let glowBase: Float = pose == .raise ? 2.3 : 1.5
        glowMat?.emission.intensity = CGFloat(glowBase + sin(t * 2.1) * 0.3)
    }
}

// MARK: - SwiftUI ラッパ

/// 装い: 夜の海に立つ航海士。ドラッグで一周・ピンチで寄れる。ポーズを切り替えられる。
struct PhoenixNavigatorView: UIViewRepresentable {
    var pose: PhoenixPose

    func makeCoordinator() -> PhoenixAnimator { PhoenixAnimator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = PhoenixNavigator.makeScene()
        view.backgroundColor = VoyageSceneKit.nightBG
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        view.rendersContinuously = !reduceMotion
        let animator = context.coordinator
        animator.animate = !reduceMotion
        animator.pose = pose
        view.pointOfView = view.scene?.rootNode.childNode(withName: "camera", recursively: false)
        view.delegate = animator
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.pose = pose
    }
}
