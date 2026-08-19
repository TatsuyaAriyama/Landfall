import SceneKit
import UIKit

/// 航海の風。出航した瞬間から全力で吹く。
///
/// 描画へ渡す強さはアニメータが数秒かけて寄せるので、出航や休憩明けで絵が
/// 飛ぶことはない。帆の孕みも波しぶきの量も、すべてこの一つの強さから派生する。
enum VoyageWind {
    /// 航海中の風の強さ。休憩中はアニメータがこれを緩めて凪へ戻す。
    static let sailingStrength: Float = 1
}

// MARK: - 帆

/// 帆布を頂点シェーダで波打たせる。
///
/// 帆は縁を桁とマストに張られているので、変位は中央ほど大きく縁で 0 になる
/// 釣鐘型の重みを掛ける。これで帆が支柱から剥がれることがない。`uWind` が 0 の
/// 間は変位も 0 なので、タイマー以外の画面(船のカスタマイズ、仲間の航海)では
/// モデルの見た目を一切変えない。
enum VoyageSailFlutter {
    static let sailMaterialNames: Set<String> = ["LF_BoatMainSail", "LF_BoatJib"]

    private static let geometryShader = """
    #pragma arguments
    float uWind;
    float3 uSailMin;
    float3 uSailSpan;
    float3 uSailNormal;
    float3 uChordAxis;
    float3 uRiseAxis;
    float uSailThrow;
    #pragma body
    float3 rel = (_geometry.position.xyz - uSailMin) / max(uSailSpan, float3(0.0001));
    float u = clamp(dot(rel, uChordAxis), 0.0, 1.0);
    float v = clamp(dot(rel, uRiseAxis), 0.0, 1.0);
    // 縁で 0、腹で 1。帆が張られている辺からは決して離れない。
    float belly = sin(3.14159265 * u) * sin(3.14159265 * v);
    float t = scn_frame.time;
    // 風は前縁から後縁へ抜ける。位相を弦方向へずらすと皺が走って見える。
    float phase = u * 7.4 + v * 2.6 - t * 3.1;
    float ripple = sin(phase) * 0.62 + sin(phase * 1.73 + 1.1) * 0.26;
    // 孕みは片側だけ。往復させると布ではなく膜に見えるので、押し出したまま揺らす。
    float billow = 0.55 + 0.45 * sin(t * 1.35 + v * 0.8);
    float amount = (billow + ripple * 0.55) * belly * uWind * uSailThrow;
    _geometry.position.xyz += uSailNormal * amount;

    // 面の傾きも同じ式の微分で追う。これがないと、動いているのに陰影だけが
    // 止まって見え、板が滑っているようになる。
    float chordSpan = max(dot(uSailSpan, uChordAxis), 0.0001);
    float dRipple = (cos(phase) * 0.62 + cos(phase * 1.73 + 1.1) * 0.26 * 1.73) * 7.4;
    float dBelly = 3.14159265 * cos(3.14159265 * u) * sin(3.14159265 * v);
    float dAmount = (dRipple * 0.55 * belly + (billow + ripple * 0.55) * dBelly)
        * uWind * uSailThrow;
    _geometry.normal = normalize(_geometry.normal - uChordAxis * (dAmount / chordSpan));
    """

    /// 帆の素材へシェーダを差し、帆の寸法から動く向きと量を決める。
    ///
    /// 帆がどの軸に薄いかはジオメトリの外接箱から測る。縦(マストに沿う辺)は
    /// 長さではなくワールドの上方向で決める — 帆は幅より背が高いので、長い辺を
    /// 弦とみなすと皺が横ではなく縦に走ってしまう。モデルの向きを直しても、
    /// 帆はいつでも自分の面に垂直な、いま孕んでいる側へ膨らむ。
    static func install(on node: SCNNode, material: SCNMaterial) {
        guard let geometry = node.geometry else { return }
        let box = geometry.boundingBox
        let lower = [box.min.x, box.min.y, box.min.z]
        let upper = [box.max.x, box.max.y, box.max.z]
        let extents = (0..<3).map { max(upper[$0] - lower[$0], Float(0.0001)) }
        guard let thinIndex = extents.indices.min(by: { extents[$0] < extents[$1] })
        else { return }
        let up = node.simdConvertVector(SIMD3<Float>(0, 1, 0), from: nil)
        let across = (0..<3).filter { $0 != thinIndex }
        guard let riseIndex = across.max(by: { abs(up[$0]) < abs(up[$1]) }),
              let chordIndex = across.first(where: { $0 != riseIndex })
        else { return }
        // 布は片側だけへ孕む。モデルが既に膨らんでいる側 — 外接箱が原点から
        // 離れている側 — へ押し出す。軸が反転して読み込まれても帆が凹まない。
        let bellySign: Float = abs(upper[thinIndex]) >= abs(lower[thinIndex]) ? 1 : -1

        var modifiers = material.shaderModifiers ?? [:]
        modifiers[.geometry] = geometryShader
        material.shaderModifiers = modifiers

        material.setValue(box.min, forKey: "uSailMin")
        material.setValue(
            SCNVector3(extents[0], extents[1], extents[2]),
            forKey: "uSailSpan"
        )
        material.setValue(basis(thinIndex, sign: bellySign), forKey: "uSailNormal")
        material.setValue(basis(chordIndex), forKey: "uChordAxis")
        material.setValue(basis(riseIndex), forKey: "uRiseAxis")
        // 孕みの深さは帆自身の厚み(モデルの膨らみ)を基準にする。元の膨らみの
        // 倍ほど押し出すと、遠景でも布が風を受けているとわかり、近景でも
        // マストを突き抜けない。
        material.setValue(
            NSNumber(value: max(extents[thinIndex], 0.05) * 1.15),
            forKey: "uSailThrow"
        )
        material.setValue(NSNumber(value: Float(0)), forKey: "uWind")
    }

    /// 差し込んだ帆の素材を集める。アニメータが毎フレーム `uWind` を書く先。
    static func materials(in root: SCNNode) -> [SCNMaterial] {
        var found: [SCNMaterial] = []
        root.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            for material in geometry.materials {
                guard let name = material.name,
                      sailMaterialNames.contains(name),
                      material.shaderModifiers?[.geometry] != nil,
                      !found.contains(where: { $0 === material })
                else { continue }
                found.append(material)
            }
        }
        return found
    }

    private static func basis(_ index: Int, sign: Float = 1) -> SCNVector3 {
        switch index {
        case 0: SCNVector3(sign, 0, 0)
        case 1: SCNVector3(0, sign, 0)
        default: SCNVector3(0, 0, sign)
        }
    }
}

// MARK: - 波しぶき

/// 舳先が波を切って上げるしぶき。左右一対の粒子で、風の強さだけ量が増える。
enum VoyageBowSpray {
    static let nodeName = "voyageBowSpray"

    /// 片側の最大発生数。寿命 0.55 秒なので、同時に生きる粒は 70 前後に収まる。
    static let peakBirthRate: CGFloat = 128

    /// 舳先の左右へ粒子を置いた入れ物を返す。船体(bob)へ足して使う。
    static func makeNode() -> SCNNode {
        let root = SCNNode()
        root.name = nodeName
        let image = dropletImage()
        for side in [Float(1), Float(-1)] {
            let node = SCNNode()
            // 船体は舳先が +x。喫水線のすぐ上、舷側の外へ少し出した位置から出す。
            node.position = SCNVector3(1.24, 0.10, 0.22 * side)
            node.addParticleSystem(makeSystem(image: image, side: side))
            root.addChildNode(node)
        }
        return root
    }

    static func systems(in root: SCNNode) -> [SCNParticleSystem] {
        guard let container = root.childNode(withName: nodeName, recursively: true) else {
            return []
        }
        return container.childNodes.flatMap { $0.particleSystems ?? [] }
    }

    private static func makeSystem(image: UIImage, side: Float) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.particleImage = image
        system.birthRate = 0
        system.emissionDuration = 1
        system.loops = true
        system.particleLifeSpan = 0.55
        system.particleLifeSpanVariation = 0.22
        // 舷側を離れず、舳先の高さより上へは行かない速さ。上限 v^2/2a はおよそ
        // 0.13 — 甲板の縁までで、帆にはかからない。
        system.particleVelocity = 1.15
        system.particleVelocityVariation = 0.45
        // 外へ、そして上へ。舷側を舐めるのではなく、切った波が跳ねる角度。
        system.emittingDirection = SCNVector3(0.46, 0.78, 0.43 * side)
        system.spreadingAngle = 22
        system.acceleration = SCNVector3(0, -5.0, 0)
        // 粒は小さく、数で見せる。大きい粒はしぶきではなく泡に見える。
        system.particleSize = 0.020
        system.particleSizeVariation = 0.010
        system.particleColor = UIColor(white: 1, alpha: 0.92)
        system.particleColorVariation = SCNVector4(0, 0.04, 0.10, 0.18)
        system.blendMode = .alpha
        system.isLightingEnabled = false
        system.sortingMode = .none
        system.isAffectedByGravity = false
        system.particleAngularVelocity = 0
        // 点から出すと筋になる。舷側に沿った細い箱にすると、面で上がる飛沫になる。
        let shape = SCNBox(width: 0.05, height: 0.02, length: 0.20, chamferRadius: 0)
        system.emitterShape = shape
        system.birthLocation = .volume

        // 空中で細り、消えぎわに透ける。出っぱなしの白い点にしないための二本。
        let size = CAKeyframeAnimation(keyPath: "size")
        size.values = [0.62, 1.0, 0.58]
        size.keyTimes = [0, 0.26, 1.0]
        let sizeController = SCNParticlePropertyController(animation: size)
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0.0, 1.0, 0.85, 0.0]
        opacity.keyTimes = [0, 0.14, 0.55, 1.0]
        let opacityController = SCNParticlePropertyController(animation: opacity)
        system.propertyControllers = [
            .size: sizeController,
            .opacity: opacityController,
        ]
        return system
    }

    /// 縁のぼけた白い粒。画像を同梱せずに済ませるため、その場で描く。
    private static func dropletImage() -> UIImage {
        let side: CGFloat = 32
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { context in
            let cgContext = context.cgContext
            let colors = [
                UIColor(white: 1, alpha: 1).cgColor,
                UIColor(white: 1, alpha: 0.72).cgColor,
                UIColor(white: 1, alpha: 0).cgColor,
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.26, 1]
            ) else { return }
            let center = CGPoint(x: side / 2, y: side / 2)
            cgContext.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: side / 2,
                options: []
            )
        }
    }
}
