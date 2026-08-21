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
    case idle, walk, lookout, raise, hail, point, stargaze, rest, sit, chart, lie
    var id: String { rawValue }
    static var selectableCases: [PhoenixPose] {
        allCases.filter { $0 != .lie }
    }
    var title: LocalizedStringKey {
        switch self {
        case .idle: "Idle"
        case .walk: "Walk"
        case .lookout: "Look out"
        case .raise: "Raise"
        case .hail: "Wave"
        case .point: "Sight land"
        case .stargaze: "Stargaze"
        case .rest: "Rest"
        case .sit: "Sit"
        case .chart: "Read chart"
        case .lie: "Lie down"
        }
    }

    /// 装いで選んだ航海士の仕草。船の上でもこの姿で立つ(船の色と同じくローカル保存)。
    private static let storageKey = "navigator.pose"

    static var selected: PhoenixPose {
        get {
            guard let raw = UserDefaults.standard.string(forKey: storageKey),
                  let pose = PhoenixPose(rawValue: raw) else { return .idle }
            return pose
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: storageKey) }
    }

    static func resetSelection() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

private struct PoseBase {
    var armRx: Float, armRz: Float, armLx: Float, armLz: Float
    var lean: Float, wind: Float, headX: Float, scan: Float, scanSpeed: Float
    var turn: Float, sway: Float, breathAmp: Float, breathSpeed: Float
    var glow: Float, sit: Float
}
private func poseBase(_ p: PhoenixPose) -> PoseBase {
    switch p {
    case .idle:
        return PoseBase(armRx: 0, armRz: 0.14, armLx: 0, armLz: -0.14, lean: 0, wind: 1, headX: 0, scan: 0.14, scanSpeed: 0.3, turn: 0, sway: 1, breathAmp: 1, breathSpeed: 0.85, glow: 1.5, sit: 0)
    case .walk:
        return PoseBase(armRx: 0, armRz: 0.12, armLx: 0, armLz: -0.12, lean: 0.09, wind: 1.7, headX: 0, scan: 0.05, scanSpeed: 0.3, turn: 0, sway: 1, breathAmp: 1, breathSpeed: 0.85, glow: 1.5, sit: 0)
    case .lookout:
        return PoseBase(armRx: 0.02, armRz: 0.16, armLx: -2.3, armLz: 0.14, lean: 0.02, wind: 1.2, headX: -0.02, scan: 0.46, scanSpeed: 0.55, turn: 0.4, sway: 0.7, breathAmp: 1, breathSpeed: 0.8, glow: 1.5, sit: 0)
    case .raise:
        return PoseBase(armRx: -2.35, armRz: 0.06, armLx: 0, armLz: -0.16, lean: -0.04, wind: 1.15, headX: -0.14, scan: 0.14, scanSpeed: 0.3, turn: 0, sway: 1, breathAmp: 1, breathSpeed: 0.85, glow: 2.3, sit: 0)
    case .hail:
        return PoseBase(armRx: 0, armRz: 0.14, armLx: 0, armLz: -2.55, lean: 0, wind: 1.1, headX: 0, scan: 0.14, scanSpeed: 0.3, turn: 0, sway: 1, breathAmp: 1, breathSpeed: 0.85, glow: 1.5, sit: 0)
    case .point:
        return PoseBase(armRx: 0.1, armRz: 0.12, armLx: -1.8, armLz: 0.06, lean: 0.14, wind: 1.45, headX: -0.08, scan: 0.02, scanSpeed: 0.2, turn: 0, sway: 0.25, breathAmp: 0.8, breathSpeed: 0.9, glow: 1.6, sit: 0)
    case .stargaze:
        return PoseBase(armRx: 0.3, armRz: 0.2, armLx: -2.58, armLz: 0.1, lean: -0.1, wind: 0.8, headX: -0.46, scan: 0.2, scanSpeed: 0.16, turn: 0, sway: 0.5, breathAmp: 1.2, breathSpeed: 0.7, glow: 0.85, sit: 0)
    case .rest:
        return PoseBase(armRx: -0.8, armRz: -0.3, armLx: -0.86, armLz: 0.32, lean: 0.07, wind: 0.75, headX: 0.32, scan: 0.05, scanSpeed: 0.22, turn: 0, sway: 0.6, breathAmp: 1.75, breathSpeed: 0.58, glow: 2, sit: 0)
    case .sit:
        return PoseBase(armRx: 0.62, armRz: 0.3, armLx: 0.62, armLz: -0.3, lean: -0.04, wind: 0.7, headX: -0.05, scan: 0.13, scanSpeed: 0.18, turn: 0, sway: 0.45, breathAmp: 0.75, breathSpeed: 0.6, glow: 1.8, sit: 1)
    case .chart:
        // 右手だけを海図の巻き軸へ伸ばし、左手は身体の横へ自然に下げる。
        return PoseBase(armRx: -1.1, armRz: 0.62, armLx: -0.12, armLz: -0.18, lean: 0.13, wind: 0.58, headX: 0.38, scan: 0.05, scanSpeed: 0.14, turn: 0.12, sway: 0.16, breathAmp: 0.65, breathSpeed: 0.58, glow: 1.35, sit: 0)
    case .lie:
        return PoseBase(armRx: -0.72, armRz: 0.22, armLx: -0.78, armLz: -0.22, lean: 0, wind: 0.12, headX: 0.16, scan: 0.035, scanSpeed: 0.10, turn: 0, sway: 0.16, breathAmp: 0.45, breathSpeed: 0.42, glow: 0.55, sit: 0)
    }
}

enum PhoenixNavigator {
    /// アセットの接触面とキャラの関節姿勢を結ぶ共通リグ。
    /// 横になる等の姿勢は、同じ型のプリセットを追加して再利用する。
    struct ContactPoseRig {
        let rootToSurface: Float
        let primaryLegPitch: Float
        let secondaryLegPitch: Float
    }

    static let seatedRig = ContactPoseRig(
        rootToSurface: 0.135,
        primaryLegPitch: -1.05,
        secondaryLegPitch: 1.05
    )

    // 配色。ローブの三色(robe/trim/deep)だけが装いで替わり、
    // 砂色・夜色・ランタンの灯は誰の航海士でも同じままにする。
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

    // 島で色を替えるときは、船の帆と同じように素材へ名前で当てて塗り替える
    // (組み直すと歩行の姿勢や結びつけが切れるため)。
    static let robeMaterialName = "LF_NavRobe"
    static let trimMaterialName = "LF_NavTrim"
    static let deepMaterialName = "LF_NavDeep"

    private static func robeMat(_ p: NavigatorPalette) -> SCNMaterial {
        named(mat(p.robe, roughness: 0.8), robeMaterialName)
    }
    private static func trimMat(_ p: NavigatorPalette) -> SCNMaterial {
        named(mat(p.trim, roughness: 0.85), trimMaterialName)
    }
    private static func deepMat(_ p: NavigatorPalette) -> SCNMaterial {
        named(mat(p.deep, roughness: 0.9), deepMaterialName)
    }
    private static func named(_ material: SCNMaterial, _ name: String) -> SCNMaterial {
        material.name = name
        return material
    }

    /// すでに立っている航海士の三色だけを塗り替える。
    static func applyPalette(_ palette: NavigatorPalette, to navigator: SCNNode) {
        navigator.enumerateChildNodes { node, _ in
            guard let materials = node.geometry?.materials else { return }
            for material in materials {
                switch material.name {
                case robeMaterialName: material.diffuse.contents = palette.robe
                case trimMaterialName: material.diffuse.contents = palette.trim
                case deepMaterialName: material.diffuse.contents = palette.deep
                default: continue
                }
            }
        }
    }
    private static var sandMat: SCNMaterial { mat(sand, roughness: 0.85) }
    private static var ropeMat: SCNMaterial { mat(sand, roughness: 0.95) }
    private static var collarMat: SCNMaterial {
        mat(midnight, roughness: 0.7, doubleSided: true)
    }
    private static var faceMat: SCNMaterial { mat(midnight, roughness: 0.6) }
    private static var capeMat: SCNMaterial { mat(midnight, roughness: 0.9, doubleSided: true) }
    private static var eyeMat: SCNMaterial {
        mat(sand, roughness: 0.7, emission: sand, emissionIntensity: 0.85)
    }

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
        let width = 0.17 + 0.25 * pow(v, 1.1)
        let length = 0.40 + 0.10 * pow(abs(u), 2.4)
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

    /// 自分の航海士は装いで選んだ色で組む。港で見かける他人には自分の色を
    /// 着せられないので、遠くの航海士は `.default`(熾火)を渡す。
    static func makeNavigatorNode(
        palette: NavigatorPalette = NavigatorCustomization.currentPalette
    ) -> SCNNode {
        let root = SCNNode()
        root.name = "navigator"
        // 正面 +Z で組んだ素体を、船の船首 +X へ向ける。
        // Web PhoenixModel と同じ +π/2。以前の -π/2 は -X（船尾）を向かせていた。
        root.eulerAngles.y = .pi / 2
        #if DEBUG
        if let y = ProcessInfo.processInfo.environment["LANDFALL_NAV_YAW"], let deg = Float(y) {
            root.eulerAngles.y = deg * .pi / 180
        }
        #endif

        // Web版と同じ接地単位。仕草で脚や裾が床を割るときは、このまとまりを
        // 持ち上げるため、身体の各部をroot直下へばらばらに置かない。
        let contact = SCNNode()
        contact.name = "contact"
        contact.position.y = 0.015
        root.addChildNode(contact)

        // 脚(股関節 + 膝ピボット)。立位の輪郭は従来のまま、座位では
        // 上腿を前へ、膝下を下へ向けられる二関節構造にする。
        for s: Float in [1, -1] {
            let leg = SCNNode()
            leg.name = s == 1 ? "legR" : "legL"
            leg.position = SCNVector3(s * 0.088, 0.42, 0)

            let knee = SCNNode()
            knee.name = s == 1 ? "kneeR" : "kneeL"
            knee.position = SCNVector3(0, -0.18, 0.02)

            let ankle = SCNNode(geometry: cyl(top: 0.042, bottom: 0.048, h: 0.18, mat: deepMat(palette)))
            ankle.position = SCNVector3(0, -0.04, 0)
            knee.addChildNode(ankle)
            let cuff = SCNNode(geometry: cyl(top: 0.062, bottom: 0.07, h: 0.06, mat: trimMat(palette)))
            cuff.position = SCNVector3(0, -0.125, 0.01)
            knee.addChildNode(cuff)
            let boot = SCNNode(geometry: sphere(0.075, seg: 14, mat: deepMat(palette)))
            boot.position = SCNVector3(0, -0.188, 0.07)
            boot.scale = SCNVector3(0.95, 0.68, 1.55)
            knee.addChildNode(boot)
            let soleGeometry = SCNBox(width: 0.115, height: 0.026, length: 0.2, chamferRadius: 0.006)
            soleGeometry.firstMaterial = trimMat(palette)
            let sole = SCNNode(geometry: soleGeometry)
            sole.position = SCNVector3(0, -0.224, 0.068)
            knee.addChildNode(sole)
            let heelGeometry = SCNBox(width: 0.1, height: 0.03, length: 0.055, chamferRadius: 0.005)
            heelGeometry.firstMaterial = deepMat(palette)
            let heel = SCNNode(geometry: heelGeometry)
            heel.position = SCNVector3(0, -0.238, -0.008)
            knee.addChildNode(heel)
            leg.addChildNode(knee)
            contact.addChildNode(leg)
        }

        // 体(呼吸のまとまり)
        let core = SCNNode()
        core.name = "core"

        // コート: 裾へ広がる袍 + 裾内の深錆の縁
        let skirt = SCNNode()
        skirt.name = "skirt"
        skirt.addChildNode(SCNNode(geometry: lathe(coatProfile, segments: 22, material: robeMat(palette))))
        let hem = SCNNode(geometry: lathe(hemProfile, segments: 22, material: trimMat(palette)))
        hem.name = "skirtHem"
        skirt.addChildNode(hem)
        core.addChildNode(skirt)

        // 腰のベルトと留め具。Web版と同寸法で、袍の胴位置を明確にする。
        let belt = SCNNode(geometry: torus(ring: 0.176, pipe: 0.021, mat: deepMat(palette)))
        belt.position = SCNVector3(0, 0.585, 0)
        core.addChildNode(belt)
        let buckleGeometry = SCNBox(width: 0.05, height: 0.038, length: 0.016, chamferRadius: 0.003)
        buckleGeometry.firstMaterial = sandMat
        let buckle = SCNNode(geometry: buckleGeometry)
        buckle.position = SCNVector3(0, 0.585, 0.172)
        core.addChildNode(buckle)

        // 肩マント
        let mantle = SCNNode(geometry: lathe(mantleProfile, segments: 22, material: robeMat(palette)))
        mantle.position = SCNVector3(0, 0.78, 0)
        core.addChildNode(mantle)

        // 胸の羅針図。真鍮の環・夜色の盤・八方位の針をWeb版と同寸法で重ねる。
        let clasp = SCNNode()
        clasp.position = SCNVector3(0, 0.868, 0.178)
        clasp.eulerAngles.x = -0.34
        let roseRim = SCNNode(geometry: torus(ring: 0.044, pipe: 0.0095, mat: sandMat))
        roseRim.eulerAngles.x = .pi / 2
        clasp.addChildNode(roseRim)
        let roseFace = SCNNode(geometry: cyl(top: 0.038, bottom: 0.038, h: 0.007, mat: faceMat))
        roseFace.eulerAngles.x = .pi / 2
        clasp.addChildNode(roseFace)
        for k in 0..<8 {
            let a = Float(k) * .pi / 4
            let cardinal = k % 2 == 0
            let len: Float = cardinal ? 0.032 : 0.019
            let point = SCNNode(geometry: cone(bottom: 0.0085, h: 0.032, seg: 4, mat: sandMat))
            point.position = SCNVector3(cos(a) * len / 2, sin(a) * len / 2, 0.006)
            point.eulerAngles.z = a - .pi / 2
            point.scale = SCNVector3(cardinal ? 1 : 0.66, len / 0.032, 0.28)
            clasp.addChildNode(point)
        }
        let roseHub = SCNNode(geometry: sphere(0.0075, seg: 10, mat: sandMat))
        roseHub.position.z = 0.008
        clasp.addChildNode(roseHub)
        core.addChildNode(clasp)

        // 前が開いた立ち襟。太い砂色のトーラスは首が浮き輪のように見えるため、
        // Web版と同じ夜色の布へ置き換える。
        let collar = SCNNode(
            geometry: openLathe(
                [
                    (0.12, 0), (0.115, 0.028), (0.106, 0.055), (0.094, 0.078)
                ],
                segments: 22,
                gap: 1.05,
                material: collarMat
            )
        )
        collar.position = SCNVector3(0, 0.935, 0)
        core.addChildNode(collar)

        // フードを留める船綱。輪・正面を少し外した結び目・二本の端を重ねる。
        let rope = SCNNode()
        rope.position = SCNVector3(0, 0.905, 0)
        rope.addChildNode(SCNNode(geometry: torus(ring: 0.15, pipe: 0.0125, mat: ropeMat)))
        let knotGroup = SCNNode()
        knotGroup.eulerAngles.y = -0.62
        let knot = SCNNode(geometry: sphere(0.022, seg: 10, mat: ropeMat))
        knot.position = SCNVector3(0, -0.004, 0.147)
        knot.scale = SCNVector3(1.15, 0.85, 0.85)
        knotGroup.addChildNode(knot)
        for s: Float in [1, -1] {
            let tail = SCNNode(
                geometry: cyl(top: 0.0115, bottom: 0.008, h: 0.072, mat: ropeMat)
            )
            tail.position = SCNVector3(s * 0.021, -0.042, 0.151)
            tail.eulerAngles = SCNVector3(0.14, 0, s * 0.32)
            knotGroup.addChildNode(tail)
        }
        rope.addChildNode(knotGroup)
        core.addChildNode(rope)

        // マント(布の格子。毎フレーム波打つ)
        let cape = SCNNode(geometry: makeCapeGeometry(time: 0, wind: 1))
        cape.name = "cape"
        cape.position = SCNVector3(0, 0.93, -0.04)
        core.addChildNode(cape)

        // 頭(尖ったフード + 闇に灯る両目)
        let head = SCNNode()
        head.name = "head"
        head.position = SCNVector3(0, 0.98, 0)
        let hood = SCNNode(geometry: makeHoodGeometry(palette))
        hood.position = SCNVector3(0, -0.02, 0)
        hood.eulerAngles.x = -0.03
        head.addChildNode(hood)
        let face = SCNNode(geometry: sphere(0.075, seg: 14, mat: faceMat))
        face.position = SCNVector3(0, 0.03, 0.006)
        face.scale = SCNVector3(0.98, 1.05, 0.9)
        head.addChildNode(face)
        for s: Float in [1, -1] {
            let eye = SCNNode(geometry: sphere(0.016, seg: 10, mat: eyeMat))
            eye.position = SCNVector3(s * 0.028, 0.022, 0.094)
            head.addChildNode(eye)
        }
        core.addChildNode(head)

        // 左腕(手を休める)
        let armL = makeArm(lantern: false, palette: palette)
        armL.name = "armL"
        armL.position = SCNVector3(-0.163, 0.8, 0.035)
        armL.eulerAngles.z = -0.14
        core.addChildNode(armL)

        // 右腕 + ランタン(今日の灯を提げる)
        let armR = makeArm(lantern: true, palette: palette)
        armR.name = "armR"
        armR.position = SCNVector3(0.163, 0.8, 0.035)
        armR.eulerAngles.z = 0.14
        core.addChildNode(armR)

        // 同行の航海で広げる海図。両面へ描き込んであるため、後ろを向いて
        // 読んでいてもカメラを回せば内容まで見える。
        let chart = makeChart()
        chart.name = "navigatorChart"
        // 胴体との間に空間を作り、右手で下角を持って海図をまっすぐ立てる。
        // 肩より上へ出すことで、背面からでも海図の矩形が身体と混ざらない。
        chart.position = SCNVector3(0, 0.85, 0.36)
        chart.opacity = 0
        core.addChildNode(chart)

        contact.addChildNode(core)
        return root
    }

    private static func makeChart() -> SCNNode {
        let group = SCNNode()
        let texture = makeChartTexture()
        let borderMaterial = mat(UIColor(rgb: 0x274C4A), roughness: 0.9, doubleSided: true)
        let backingGeometry = SCNBox(width: 0.47, height: 0.295, length: 0.018, chamferRadius: 0.018)
        backingGeometry.firstMaterial = borderMaterial
        group.addChildNode(SCNNode(geometry: backingGeometry))

        // SceneKitのBox UVへ任せず、表裏それぞれに専用Planeを置く。
        // 海図の線が引き伸ばされず、濃緑の縁が衣装との境界になる。
        for side: Float in [-1, 1] {
            let parchment = mat(UIColor.white, roughness: 0.94, doubleSided: false)
            parchment.diffuse.contents = texture
            parchment.diffuse.wrapS = .clamp
            parchment.diffuse.wrapT = .clamp
            let faceGeometry = SCNPlane(width: 0.44, height: 0.265)
            faceGeometry.cornerRadius = 0.012
            faceGeometry.firstMaterial = parchment
            let face = SCNNode(geometry: faceGeometry)
            face.position.z = side * 0.011
            if side < 0 { face.eulerAngles.y = .pi }
            group.addChildNode(face)
        }

        let rollMaterial = mat(UIColor(rgb: 0xC5A56B), roughness: 0.96)
        for side: Float in [-1, 1] {
            let rollGeometry = SCNCylinder(radius: 0.017, height: 0.255)
            rollGeometry.radialSegmentCount = 10
            rollGeometry.firstMaterial = rollMaterial
            let roll = SCNNode(geometry: rollGeometry)
            roll.position = SCNVector3(side * 0.222, 0, 0.018)
            group.addChildNode(roll)
        }
        return group
    }

    /// 羊皮紙へ海岸線・測地格子・破線航路・島影・羅針図を描く。
    /// 3Dプリミティブを細かく重ねるより縮小時の線が崩れず、ストア画像でも読める。
    private static func makeChartTexture() -> UIImage {
        let size = CGSize(width: 640, height: 384)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            UIColor(rgb: 0xE9D7A8).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            cg.setStrokeColor(UIColor(rgb: 0xB89B66).withAlphaComponent(0.48).cgColor)
            cg.setLineWidth(2)
            for x: CGFloat in stride(from: 64, through: 576, by: 64) {
                cg.move(to: CGPoint(x: x, y: 0)); cg.addLine(to: CGPoint(x: x, y: 384))
            }
            for y: CGFloat in stride(from: 64, through: 320, by: 64) {
                cg.move(to: CGPoint(x: 0, y: y)); cg.addLine(to: CGPoint(x: 640, y: y))
            }
            cg.strokePath()

            let coast = UIBezierPath()
            coast.move(to: CGPoint(x: 0, y: 60))
            coast.addCurve(to: CGPoint(x: 118, y: 112), controlPoint1: CGPoint(x: 48, y: 48), controlPoint2: CGPoint(x: 62, y: 142))
            coast.addCurve(to: CGPoint(x: 196, y: 210), controlPoint1: CGPoint(x: 172, y: 84), controlPoint2: CGPoint(x: 143, y: 208))
            coast.addCurve(to: CGPoint(x: 120, y: 384), controlPoint1: CGPoint(x: 240, y: 284), controlPoint2: CGPoint(x: 160, y: 320))
            coast.addLine(to: CGPoint(x: 0, y: 384))
            coast.close()
            UIColor(rgb: 0x8DA67B).withAlphaComponent(0.82).setFill()
            coast.fill()
            UIColor(rgb: 0x385B58).withAlphaComponent(0.86).setStroke()
            coast.lineWidth = 7
            coast.stroke()

            let islands = [
                CGRect(x: 286, y: 92, width: 48, height: 28),
                CGRect(x: 392, y: 238, width: 68, height: 38),
                CGRect(x: 500, y: 112, width: 38, height: 24),
            ]
            for island in islands {
                let shape = UIBezierPath(ovalIn: island)
                UIColor(rgb: 0x8DA67B).setFill(); shape.fill()
                UIColor(rgb: 0x385B58).setStroke(); shape.lineWidth = 5; shape.stroke()
            }

            cg.setStrokeColor(UIColor(rgb: 0xB4513D).cgColor)
            cg.setLineWidth(9)
            cg.setLineDash(phase: 0, lengths: [18, 13])
            cg.move(to: CGPoint(x: 155, y: 296))
            cg.addCurve(to: CGPoint(x: 520, y: 126), control1: CGPoint(x: 260, y: 340), control2: CGPoint(x: 414, y: 98))
            cg.strokePath()
            cg.setLineDash(phase: 0, lengths: [])

            let center = CGPoint(x: 530, y: 292)
            cg.setStrokeColor(UIColor(rgb: 0x385B58).cgColor)
            cg.setLineWidth(6)
            cg.strokeEllipse(in: CGRect(x: center.x - 47, y: center.y - 47, width: 94, height: 94))
            for index in 0..<8 {
                let angle = CGFloat(index) * .pi / 4
                let inner: CGFloat = index.isMultiple(of: 2) ? 10 : 20
                cg.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                cg.addLine(to: CGPoint(x: center.x + cos(angle) * 42, y: center.y + sin(angle) * 42))
            }
            cg.strokePath()
            UIColor(rgb: 0xB4513D).setFill()
            UIBezierPath(ovalIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)).fill()
        }
    }

    private static func makeArm(lantern hasLantern: Bool, palette: NavigatorPalette) -> SCNNode {
        let arm = SCNNode()
        let upper = SCNNode(geometry: cyl(top: 0.036, bottom: 0.044, h: 0.22, mat: robeMat(palette)))
        upper.position = SCNVector3(0, -0.1, 0)
        arm.addChildNode(upper)
        let sleeve = SCNNode(geometry: cyl(top: 0.046, bottom: 0.064, h: 0.1, mat: trimMat(palette)))
        sleeve.position = SCNVector3(0, -0.22, 0)
        arm.addChildNode(sleeve)
        let hand = SCNNode(geometry: sphere(0.048, seg: 12, mat: deepMat(palette)))
        hand.position = SCNVector3(0, -0.28, 0)
        arm.addChildNode(hand)

        if hasLantern {
            let lan = SCNNode()
            lan.name = "lantern"
            lan.position = SCNVector3(0, -0.33, 0)
            let handle = SCNNode(geometry: cyl(top: 0.008, bottom: 0.008, h: 0.06, mat: trimMat(palette)))
            handle.position = SCNVector3(0, -0.03, 0)
            lan.addChildNode(handle)
            let cap = SCNNode(geometry: cone(bottom: 0.058, h: 0.05, seg: 6, mat: trimMat(palette)))
            cap.position = SCNVector3(0, -0.075, 0)
            lan.addChildNode(cap)
            let glowMat = mat(self.lantern, roughness: 0.8, emission: self.lantern, emissionIntensity: 1.5)
            let glow = SCNNode(geometry: sphere(0.042, seg: 12, mat: glowMat))
            glow.name = "lanternGlow"
            glow.position = SCNVector3(0, -0.14, 0)
            lan.addChildNode(glow)
            let base = SCNNode(geometry: cyl(top: 0.045, bottom: 0.05, h: 0.02, mat: trimMat(palette)))
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

    /// 前面を開けた回転体。three.js LatheGeometry と同じく
    /// x=sin(phi)*radius / z=cos(phi)*radius で頂点を置く。
    private static func openLathe(
        _ profile: [(r: Float, y: Float)],
        segments: Int,
        gap: Float,
        material: SCNMaterial
    ) -> SCNGeometry {
        let span = 2 * Float.pi - gap
        var verts: [SCNVector3] = []
        for p in profile {
            for j in 0...segments {
                let phi = gap / 2 + Float(j) / Float(segments) * span
                verts.append(
                    SCNVector3(p.r * sin(phi), p.y, p.r * cos(phi))
                )
            }
        }
        let stride = segments + 1
        var indices: [UInt32] = []
        for i in 0..<(profile.count - 1) {
            for j in 0..<segments {
                let a = UInt32(i * stride + j)
                let b = a + 1
                let d = UInt32((i + 1) * stride + j)
                let e = d + 1
                indices += [a, d, b, b, d, e]
            }
        }
        return mesh(verts, indices, material: material)
    }

    /// Web版の「前面が開き、先だけ背へ流れる布フード」を同じ輪郭で生成する。
    private static func makeHoodGeometry(_ palette: NavigatorPalette) -> SCNGeometry {
        let profile: [(r: Float, y: Float)] = [
            (0.148, -0.06), (0.14, 0), (0.126, 0.055),
            (0.104, 0.105), (0.07, 0.15), (0, 0.185),
        ]
        let segments = 20
        let gap: Float = 0.72
        let span = 2 * Float.pi - gap
        var verts: [SCNVector3] = []
        for p in profile {
            let k = max(0, (p.y - profile[0].y) / (profile.last!.y - profile[0].y))
            for j in 0...segments {
                let t = gap / 2 + Float(j) / Float(segments) * span
                // ThreeのLatheGeometryは開口を+Zへ向ける。以前のcos/sin順では
                // 開口だけが+Xへ90度ずれ、正面カメラから顔と目が見えなかった。
                verts.append(
                    SCNVector3(
                        p.r * sin(t),
                        p.y,
                        p.r * cos(t) - k * k * 0.05
                    )
                )
            }
        }
        let stride = segments + 1
        var indices: [UInt32] = []
        for i in 0..<(profile.count - 1) {
            for j in 0..<segments {
                let a = UInt32(i * stride + j)
                let b = a + 1
                let d = UInt32((i + 1) * stride + j)
                let e = d + 1
                indices += [a, d, b, b, d, e]
            }
        }
        return mesh(
            verts, indices,
            material: named(
                mat(palette.robe, roughness: 0.85, doubleSided: true),
                robeMaterialName
            )
        )
    }

    // コート/肩マントの回転体プロフィール(Web LatheGeometry の点列。r=半径, y=高さ)
    private static let coatProfile: [(r: Float, y: Float)] = [
        (0.235, 0.3), (0.225, 0.36), (0.205, 0.44), (0.185, 0.52), (0.165, 0.62),
        (0.148, 0.7), (0.135, 0.78), (0.118, 0.86), (0.105, 0.92),
    ]
    /// コート下端に沿う本来の裾帯。以前はコート全体の複製を縦に潰していたため、
    /// 座位で座面より下へ別の袍が突き抜けていた。
    private static let hemProfile: [(r: Float, y: Float)] = [
        (0.238, 0.296), (0.235, 0.315), (0.229, 0.345), (0.222, 0.375),
    ]
    private static let mantleProfile: [(r: Float, y: Float)] = [
        (0.2, 0), (0.185, 0.05), (0.16, 0.11), (0.128, 0.155), (0.1, 0.175),
    ]

    // MARK: シーン(夜の海に立つ航海士。Web BoatStudio SailorStage 相当)

    static func makeNavigatorStage() -> SCNNode {
        let stage = SCNNode()
        stage.name = "navigatorStage"
        // PhoenixModel本体の+π/2を相殺して、顔・胸・つま先の+Zを
        // スタジオの正面に合わせる。
        stage.eulerAngles.y = -.pi / 2
        // 全画面の上部操作と下部パネルの間へ全身が収まる展示倍率。
        stage.scale = SCNVector3(0.95, 0.95, 0.95)
        stage.addChildNode(makeNavigatorNode())
        return stage
    }

    static func makeScene() -> SCNScene {
        let scene = VoyageSceneKit.makeDressStudioWorld()
        scene.rootNode.addChildNode(makeNavigatorStage())
        return scene
    }
}

// MARK: - アニメータ(Web PhoenixModel useFrame の移植)

/// Continuous locomotion values supplied by an owning world. When absent, the
/// animator preserves the legacy time-based walk used by voyage and wardrobe
/// scenes. Home Island supplies this every frame as its procedural Blend Space.
struct PhoenixLocomotionAnimationState: Equatable {
    var normalizedSpeed: Float = 0
    var gaitPhase: Float = 0
    var turnIntensity: Float = 0
    var verticalVelocity: Float = 0
    var isGrounded = true
    var landingImpact: Float = 0
    var fatigue: Float = 0
    var slopePitch: Float = 0
    var slopeRoll: Float = 0
    var leftFootGroundOffset: Float = 0
    var rightFootGroundOffset: Float = 0
    var deckBalance: Float = 0
    /// Local-space contact height used to visually absorb a logical step-up or
    /// step-down without moving the authoritative collision root.
    var groundingOffset: Float = 0
}

final class PhoenixAnimator: NSObject, SCNSceneRendererDelegate {
    var pose: PhoenixPose = .idle
    var animate = true
    var locomotionState: PhoenixLocomotionAnimationState?

    private var startTime: TimeInterval?
    private var lastTime: TimeInterval = 0
    private weak var boundScene: SCNScene?
    private weak var boundNavigator: SCNNode?
    private var usesExplicitNavigatorBinding = false
    private weak var contact: SCNNode?
    private weak var core: SCNNode?
    private weak var skirt: SCNNode?
    private weak var head: SCNNode?
    private weak var armR: SCNNode?
    private weak var armL: SCNNode?
    private weak var legR: SCNNode?
    private weak var legL: SCNNode?
    private weak var kneeR: SCNNode?
    private weak var kneeL: SCNNode?
    private weak var lantern: SCNNode?
    private weak var chart: SCNNode?
    private weak var cape: SCNNode?
    private weak var glowMat: SCNMaterial?
    private var rippleNodes: [SCNNode] = []

    // ポーズ基本角の現在値(POSE_BASE へ減衰補間)
    private var armRx: Float = 0, armRz: Float = 0.14
    private var armLx: Float = 0, armLz: Float = -0.14
    private var lean: Float = 0, wind: Float = 1
    private var headX: Float = 0, scan: Float = 0.14, scanSpeed: Float = 0.3
    private var turn: Float = 0, sway: Float = 1
    private var breathAmp: Float = 1, breathSpeed: Float = 0.85
    private var glow: Float = 1.5, sit: Float = 0, lie: Float = 0
    private var breathPhase: Float = 0, scanPhase: Float = 0

    private func bindComponents(
        to navigator: SCNNode,
        scene: SCNScene?,
        includesSceneRipples: Bool
    ) {
        boundScene = scene
        boundNavigator = navigator
        contact = navigator.childNode(withName: "contact", recursively: true)
        core = navigator.childNode(withName: "core", recursively: true)
        skirt = navigator.childNode(withName: "skirt", recursively: true)
        head = navigator.childNode(withName: "head", recursively: true)
        armR = navigator.childNode(withName: "armR", recursively: true)
        armL = navigator.childNode(withName: "armL", recursively: true)
        legR = navigator.childNode(withName: "legR", recursively: true)
        legL = navigator.childNode(withName: "legL", recursively: true)
        kneeR = navigator.childNode(withName: "kneeR", recursively: true)
        kneeL = navigator.childNode(withName: "kneeL", recursively: true)
        lantern = navigator.childNode(withName: "lantern", recursively: true)
        chart = navigator.childNode(withName: "navigatorChart", recursively: true)
        cape = navigator.childNode(withName: "cape", recursively: true)
        glowMat = navigator.childNode(
            withName: "lanternGlow",
            recursively: true
        )?.geometry?.firstMaterial
        if includesSceneRipples, let scene {
            rippleNodes = (0..<3).compactMap {
                scene.rootNode.childNode(withName: "ripple\($0)", recursively: true)
            }
        } else {
            rippleNodes = []
        }
    }

    private func bind(_ scene: SCNScene) {
        usesExplicitNavigatorBinding = false
        guard let navigator = scene.rootNode.childNode(
            withName: "navigator",
            recursively: true
        ) else { return }
        bindComponents(to: navigator, scene: scene, includesSceneRipples: true)
    }

    /// Binds this animator to one navigator instance instead of the first node
    /// named `navigator` in a scene. Multiplayer scenes contain several copies
    /// of the model, so every visitor must own a separately bound animator.
    func bind(to navigator: SCNNode, in scene: SCNScene? = nil) {
        usesExplicitNavigatorBinding = true
        bindComponents(
            to: navigator,
            scene: scene,
            includesSceneRipples: false
        )
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard animate, let scene = renderer.scene else { return }
        if usesExplicitNavigatorBinding {
            if core == nil, let boundNavigator {
                bindComponents(
                    to: boundNavigator,
                    scene: boundScene,
                    includesSceneRipples: false
                )
            }
        } else if boundScene !== scene || core == nil {
            bind(scene)
        }
        if startTime == nil { startTime = time; lastTime = time }
        let t = Float(time - (startTime ?? time))
        let dt = Float(min(max(time - lastTime, 0), 0.1))
        lastTime = time

        step(t: t, dt: dt)

        // 足元の波紋(Web Ripples: 周期7秒・位相ずらし3枚)。海の演出。
        for (i, node) in rippleNodes.enumerated() {
            let phase = (t / 7 + Float(i) / 3).truncatingRemainder(dividingBy: 1)
            let s = 0.8 + phase * 5.5
            node.scale = SCNVector3(s, s, 1)
            node.opacity = CGFloat(sin(min(phase * 3, 1) * .pi / 2) * (1 - phase) * 0.2)
        }
    }

    /// 航海士の1フレーム分の動き。目的地の船上など、別のシーンからも呼べるように
    /// 切り出してある(bind 済みであることが前提)。
    func step(t: Float, dt: Float) {
        let base = poseBase(pose)
        armRx = damp(armRx, base.armRx, 6, dt)
        armRz = damp(armRz, base.armRz, 6, dt)
        armLx = damp(armLx, base.armLx, 6, dt)
        armLz = damp(armLz, base.armLz, 6, dt)
        lean = damp(lean, base.lean, 6, dt)
        let locomotionWind = (locomotionState?.normalizedSpeed ?? 0) * 2.1
        wind = damp(wind, base.wind + locomotionWind, 4, dt)
        headX = damp(headX, base.headX, 6, dt)
        scan = damp(scan, base.scan, 6, dt)
        scanSpeed = damp(scanSpeed, base.scanSpeed, 6, dt)
        turn = damp(turn, base.turn, 6, dt)
        sway = damp(sway, base.sway, 6, dt)
        breathAmp = damp(breathAmp, base.breathAmp, 6, dt)
        breathSpeed = damp(breathSpeed, base.breathSpeed, 6, dt)
        glow = damp(glow, base.glow, 3, dt)
        sit = damp(sit, base.sit, pose == .sit ? 1.5 : 6, dt)
        lie = damp(lie, pose == .lie ? 1 : 0, pose == .lie ? 2.2 : 7, dt)
        breathPhase += dt * breathSpeed
        scanPhase += dt * scanSpeed

        // マント: 布の波(頂点を書き直す)
        if let cape { cape.geometry = PhoenixNavigator.makeCapeGeometry(time: t, wind: wind) }

        let walking = pose == .walk
        let locomotion = locomotionState
        let speedBlend = walking
            ? min(max(locomotion?.normalizedSpeed ?? 0.48, 0), 1)
            : 0
        let phase = locomotion?.gaitPhase ?? t * 5.4
        let step = sin(phase)
        let grounded = locomotion?.isGrounded ?? true
        let landingImpact = locomotion?.landingImpact ?? 0
        let fatigue = locomotion?.fatigue ?? 0
        let turnIntensity = locomotion?.turnIntensity ?? 0
        let deckBalance = locomotion?.deckBalance ?? 0
        let drop = sit * 0.3

        // Web版の接地補正。座る途中でブーツや裾が海面を割らないよう、
        // 身体全体をわずかに持ち上げる。
        if let contact {
            contact.position.y = damp(
                contact.position.y,
                0.015 + sit * 0.12 + (locomotion?.groundingOffset ?? 0),
                12,
                dt
            )
        }

        // 体: 待機は呼吸、歩行は歩調の弾み
        if let core {
            let standingBreath = sin(breathPhase) * 0.018 * breathAmp
                * (1 - sit) * (1 - lie * 0.75)
            let locomotionBounce = abs(cos(phase)) * (0.020 + speedBlend * 0.032)
            let airborneLift: Float = grounded ? 0 : 0.035
            core.position.y = (walking ? locomotionBounce : standingBreath)
                - drop - landingImpact * 0.085 + airborneLift
            core.eulerAngles.x = lean
                + speedBlend * 0.13
                + fatigue * 0.045
                + sin(breathPhase + 0.9) * 0.01 * (breathAmp + fatigue * 1.4)
            core.eulerAngles.y = sin(scanPhase - 0.55) * turn
            core.eulerAngles.z = walking
                ? step * (0.018 + speedBlend * 0.025)
                    - turnIntensity * speedBlend * 0.055
                : sin(breathPhase * 0.72) * deckBalance * 0.035
        }
        if let skirt {
            // 衣装は立位・座位で同じ形を保つ。座位専用の拡縮や透明化は行わず、
            // 身体の関節だけで姿勢を作る。
            skirt.position = SCNVector3Zero
            skirt.scale = SCNVector3(1, 1, 1)
        }
        // 首: ポーズごとの上下と見渡し。
        if let head {
            head.eulerAngles.y = sin(scanPhase) * scan * (1 - speedBlend * 0.72)
            head.eulerAngles.x = headX - speedBlend * 0.035 + fatigue * 0.055
            head.eulerAngles.z = sin(breathPhase + 2.1) * 0.02 * breathAmp
        }
        // 脚: 歩行は股関節で交互に振る。座位は上腿だけを前へ倒し、膝で
        // 同じ角度を打ち消して膝下とブーツを自然に下へ垂らす。
        let legSwing: Float = walking ? 0.30 + speedBlend * 0.50 : 0
        let airborneTuck: Float = grounded ? 0 : 0.34
        let legSit = PhoenixNavigator.seatedRig.primaryLegPitch * sit
        let kneeSit = PhoenixNavigator.seatedRig.secondaryLegPitch * sit
        if let legR {
            let plantWeight = max(-step, 0)
            let groundOffset = (locomotion?.rightFootGroundOffset ?? 0) * plantWeight
            legR.position.x = 0.088 + deckBalance * 0.035
            legR.position.y = 0.42 - drop + groundOffset
            legR.eulerAngles.x = damp(
                legR.eulerAngles.x,
                step * legSwing + legSit - airborneTuck,
                10 + speedBlend * 4,
                dt
            )
        }
        if let legL {
            let plantWeight = max(step, 0)
            let groundOffset = (locomotion?.leftFootGroundOffset ?? 0) * plantWeight
            legL.position.x = -0.088 - deckBalance * 0.035
            legL.position.y = 0.42 - drop + groundOffset
            legL.eulerAngles.x = damp(
                legL.eulerAngles.x,
                -step * legSwing + legSit - airborneTuck,
                10 + speedBlend * 4,
                dt
            )
        }
        if let kneeR {
            kneeR.eulerAngles.x = damp(
                kneeR.eulerAngles.x,
                kneeSit + airborneTuck * 1.45 + landingImpact * 0.24,
                10,
                dt
            )
        }
        if let kneeL {
            kneeL.eulerAngles.x = damp(
                kneeL.eulerAngles.x,
                kneeSit + airborneTuck * 1.45 + landingImpact * 0.24,
                10,
                dt
            )
        }

        // 腕: 基本角 + ポーズごとの振動
        let armSwing: Float = walking
            ? -step * (0.20 + speedBlend * 0.34)
            : sin(breathPhase + 0.4) * 0.03 * (sway + deckBalance * 0.5)
        if let armR {
            armR.eulerAngles.x = armRx + armSwing
            armR.eulerAngles.z = armRz
        }
        if let armL {
            let wave: Float = pose == .hail ? sin(t * 7.2) * 0.3 : 0
            armL.eulerAngles.x = armLx + (walking ? step * 0.32 : sin(breathPhase + 1.1) * 0.025 * sway)
            armL.eulerAngles.z = armLz + wave
        }
        // ランタン: 腕の傾きを打ち消して常にほぼ鉛直に垂れる振り子
        if let lantern {
            lantern.eulerAngles.x = -(armRx + armSwing)
                + sin(phase * 0.58) * (walking ? 0.14 + speedBlend * 0.20 : 0.1 * sway)
            lantern.eulerAngles.z = sin(phase * 0.45 + 0.6)
                * (0.10 + speedBlend * 0.16) * sway
            // Fade the hand lantern while sleeping so it cannot clip through
            // the rope bed or the navigator's resting body.
            lantern.opacity = CGFloat(1 - lie)
        }
        if let chart {
            let shown = pose == .chart ? 1.0 : 0.0
            chart.opacity = CGFloat(shown)
            chart.eulerAngles = SCNVector3Zero
        }
        glowMat?.emission.intensity = CGFloat(glow + sin(t * 2.1) * 0.2 * glow)
    }

    /// 外部シーン(目的地の船上など)から使うときの束ね直し。
    func bindIfNeeded(_ scene: SCNScene) {
        if usesExplicitNavigatorBinding || boundScene !== scene || core == nil {
            bind(scene)
        }
    }
}

// MARK: - 装いの全画面共通スタジオ

/// Web版の一つのCanvasと同じ構成。背景・カメラ・操作状態は生かしたまま、
/// 船と航海士の表示ノードだけを切り替える。
struct DressStudioSceneView: UIViewRepresentable {
    var parts: BoatParts
    var pose: PhoenixPose
    var showsNavigator: Bool
    var resetToken: Int

    func makeCoordinator() -> DressStudioCoordinator {
        DressStudioCoordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = VoyageSceneKit.makeDressStudioWorld()
        scene.rootNode.addChildNode(VoyageSceneKit.makeBoatStudioSubject(parts: parts))
        scene.rootNode.addChildNode(PhoenixNavigator.makeNavigatorStage())

        view.scene = scene
        view.backgroundColor = VoyageSceneKit.nightBG
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.preferredFramesPerSecond = 60

        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        view.rendersContinuously = !reduceMotion
        view.isPlaying = !reduceMotion
        view.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)

        context.coordinator.install(
            on: view,
            parts: parts,
            pose: pose,
            showsNavigator: showsNavigator,
            resetToken: resetToken,
            animate: !reduceMotion
        )
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.update(
            parts: parts,
            pose: pose,
            showsNavigator: showsNavigator,
            resetToken: resetToken
        )
    }
}

/// drei OrbitControls のスタジオ設定。モード切替時もカメラ位置を保ち、
/// 新しい注視点と距離制限だけを適用するのがWeb版の実際の挙動。
private struct DressOrbit {
    var target = SCNVector3(0, 0.7, 0)
    var radius: Float = 1
    var azimuth: Float = 0
    var polar: Float = .pi / 2
    var minRadius: Float = 3.4
    var maxRadius: Float = 9
    var minPolar: Float = .pi * 0.18
    var maxPolar: Float = .pi * 0.52

    mutating func capture(camera: SCNNode, target nextTarget: SCNVector3) {
        target = nextTarget
        let dx = camera.position.x - target.x
        let dy = camera.position.y - target.y
        let dz = camera.position.z - target.z
        radius = max(0.001, sqrt(dx * dx + dy * dy + dz * dz))
        azimuth = atan2(dx, dz)
        polar = acos(max(-1, min(1, dy / radius)))
        clamp()
    }

    mutating func configureForNavigator(_ enabled: Bool, camera: SCNNode) {
        if enabled {
            minRadius = 1.45
            maxRadius = 5
            minPolar = .pi * 0.14
            maxPolar = .pi * 0.56
            capture(camera: camera, target: SCNVector3(0, 0.8, 0))
        } else {
            minRadius = 3.4
            maxRadius = 9
            minPolar = .pi * 0.18
            maxPolar = .pi * 0.52
            capture(camera: camera, target: SCNVector3(0, 0.7, 0))
        }
    }

    /// 初期の横斜め構図へ即座に戻す。船と航海士で対象の大きさだけ変える。
    mutating func reset(forNavigator enabled: Bool) {
        if enabled {
            target = SCNVector3(0, 0.8, 0)
            radius = 2.75
            minRadius = 1.45
            maxRadius = 5
            minPolar = .pi * 0.14
            maxPolar = .pi * 0.56
        } else {
            target = SCNVector3(0, 0.7, 0)
            radius = 5.38
            minRadius = 3.4
            maxRadius = 9
            minPolar = .pi * 0.18
            maxPolar = .pi * 0.52
        }
        azimuth = 0.625
        polar = enabled ? 1.35 : 1.38
        clamp()
    }

    mutating func clamp() {
        radius = max(minRadius, min(maxRadius, radius))
        polar = max(minPolar, min(maxPolar, polar))
    }

    func apply(to camera: SCNNode) {
        let horizontal = radius * sin(polar)
        camera.position = SCNVector3(
            target.x + horizontal * sin(azimuth),
            target.y + radius * cos(polar),
            target.z + horizontal * cos(azimuth)
        )
        // OrbitControlsはcamera.up=(0,1,0)を守る。単引数のlook(at:)へ任せると
        // 連続更新でロールが混ざり、切替後に世界ごと斜めへ倒れてしまう。
        camera.look(
            at: target,
            up: SCNVector3(0, 1, 0),
            localFront: SCNVector3(0, 0, -1)
        )
    }
}

final class DressStudioCoordinator: NSObject, SCNSceneRendererDelegate, UIGestureRecognizerDelegate {
    private weak var view: SCNView?
    private weak var camera: SCNNode?
    private weak var boat: SCNNode?
    private weak var navigator: SCNNode?
    private weak var bob: SCNNode?

    private let phoenixAnimator = PhoenixAnimator()
    private var orbit = DressOrbit()
    private var showsNavigator: Bool?
    private var partsKey = ""
    private var animate = true
    private var autoRotate = true
    private var angularVelocity = CGPoint.zero
    private var lastResetToken = 0
    private var startTime: TimeInterval?
    private var lastTime: TimeInterval = 0

    func install(
        on view: SCNView,
        parts: BoatParts,
        pose: PhoenixPose,
        showsNavigator: Bool,
        resetToken: Int,
        animate: Bool
    ) {
        self.view = view
        self.animate = animate
        phoenixAnimator.animate = animate
        phoenixAnimator.pose = pose

        let root = view.scene?.rootNode
        camera = root?.childNode(withName: "camera", recursively: false)
        boat = root?.childNode(withName: "travel", recursively: false)
        navigator = root?.childNode(withName: "navigatorStage", recursively: false)
        bob = root?.childNode(withName: "boatBob", recursively: true)
        partsKey = key(for: parts)
        lastResetToken = resetToken

        if let camera {
            orbit.capture(camera: camera, target: SCNVector3(0, 0.7, 0))
            orbit.apply(to: camera)
        }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        view.addGestureRecognizer(pinch)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        view.addGestureRecognizer(doubleTap)

        update(parts: parts, pose: pose, showsNavigator: showsNavigator, resetToken: resetToken)
    }

    func update(parts: BoatParts, pose: PhoenixPose, showsNavigator: Bool, resetToken: Int) {
        phoenixAnimator.pose = pose
        updatePartsIfNeeded(parts)

        if self.showsNavigator != showsNavigator, let camera {
            self.showsNavigator = showsNavigator
            boat?.isHidden = showsNavigator
            navigator?.isHidden = !showsNavigator

            // 表示対象を切り替えても向きは保ち、距離制限と注視点だけを合わせる。
            orbit.configureForNavigator(showsNavigator, camera: camera)
            orbit.apply(to: camera)
            angularVelocity = .zero
            autoRotate = animate && !showsNavigator
        }

        if lastResetToken != resetToken {
            lastResetToken = resetToken
            resetView()
        }
    }

    private func updatePartsIfNeeded(_ parts: BoatParts) {
        let nextKey = key(for: parts)
        guard nextKey != partsKey else { return }
        partsKey = nextKey
        bob?.childNode(withName: "boatModel", recursively: false)?.removeFromParentNode()
        bob?.addChildNode(VoyageSceneKit.makeBoatModel(parts))
    }

    private func key(for parts: BoatParts) -> String {
        let stripe = parts.stripe?.hashValue ?? 0
        return "\(parts.shipID)|\(parts.sail.hashValue)|\(parts.jib.hashValue)|\(parts.hull.hashValue)|\(stripe)|\(parts.flag)"
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view, let camera else { return }
        let height = max(view.bounds.height, 1)
        let radiansPerPoint = 2 * CGFloat.pi / height
        let delta = gesture.translation(in: view)
        gesture.setTranslation(.zero, in: view)

        if gesture.state == .began {
            autoRotate = false
            angularVelocity = .zero
        }

        orbit.azimuth -= Float(delta.x * radiansPerPoint)
        orbit.polar -= Float(delta.y * radiansPerPoint)
        orbit.clamp()
        orbit.apply(to: camera)

        if gesture.state == .ended {
            let velocity = gesture.velocity(in: view)
            angularVelocity = CGPoint(
                x: -velocity.x * radiansPerPoint,
                y: -velocity.y * radiansPerPoint
            )
        } else if gesture.state == .cancelled || gesture.state == .failed {
            angularVelocity = .zero
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let camera else { return }
        if gesture.state == .began {
            autoRotate = false
            angularVelocity = .zero
        }
        orbit.radius /= Float(max(gesture.scale, 0.01))
        gesture.scale = 1
        orbit.clamp()
        orbit.apply(to: camera)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        resetView()
    }

    private func resetView() {
        guard let camera else { return }
        orbit.reset(forNavigator: showsNavigator == true)
        orbit.apply(to: camera)
        angularVelocity = .zero
        autoRotate = animate && showsNavigator != true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard animate, let camera else { return }
        if startTime == nil {
            startTime = time
            lastTime = time
        }
        let t = Float(time - (startTime ?? time))
        let dt = Float(min(max(time - lastTime, 0), 0.1))
        lastTime = time

        phoenixAnimator.renderer(renderer, updateAtTime: time)

        if let bob {
            bob.position.y = sin(t * 0.8) * 0.06
            bob.eulerAngles.z = sin(t * 0.6) * 0.03
            bob.eulerAngles.x = sin(t * 0.5 + 1.2) * 0.015
            bob.childNode(withName: "boatFlag", recursively: true)?
                .eulerAngles.y = sin(t * 5.2) * 0.22
        }

        // Web OrbitControls autoRotateSpeed=0.6 ≒ 100秒で一周。
        if autoRotate {
            orbit.azimuth -= 2 * .pi / 100 * dt
        }

        if abs(angularVelocity.x) > 0.001 || abs(angularVelocity.y) > 0.001 {
            orbit.azimuth += Float(angularVelocity.x) * dt
            orbit.polar += Float(angularVelocity.y) * dt
            let decay = CGFloat(exp(-5 * dt))
            angularVelocity.x *= decay
            angularVelocity.y *= decay
        }
        orbit.clamp()
        orbit.apply(to: camera)
    }
}
