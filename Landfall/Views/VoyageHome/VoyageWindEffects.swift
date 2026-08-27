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

/// 舳先が波を切る瞬間を、飛沫・霧・海面の細片に分けて描く。
enum VoyageBowSpray {
    static let nodeName = "voyageBowSpray"

    struct Palette {
        let sea: UIColor
        let highlight: UIColor
    }

    struct Rates {
        static let zero = Rates(streaks: 0, mist: 0, flecks: 0)

        let streaks: CGFloat
        let mist: CGFloat
        let flecks: CGFloat

        static func sailing(wind: Float, at time: Float) -> Rates {
            let strength = CGFloat(min(max(wind, 0), 1))
            let wave = max(0, sin(time * 1.9))
            let primaryImpact = powf(wave, 2.3)
            let secondaryImpact = powf(max(0, sin(time * 3.7 + 1.1)), 5) * 0.32
            let impact = min(primaryImpact + secondaryImpact, 1)
            let surfaceWave = max(0, sin(time * 1.9 - 0.72))
            return Rates(
                streaks: 32 * strength * CGFloat(0.34 + impact * 0.66),
                mist: 12 * strength * CGFloat(impact),
                flecks: 44 * strength
                    * CGFloat(0.22 + powf(surfaceWave, 1.45) * 0.78)
            )
        }
    }

    /// レイヤーを配列の順序で識別しない、アニメータ向けの型付きハンドル。
    struct Systems {
        static let empty = Systems(streaks: [], mist: [], flecks: [])

        let streaks: [SCNParticleSystem]
        let mist: [SCNParticleSystem]
        let flecks: [SCNParticleSystem]

        func apply(_ rates: Rates) {
            set(streaks, rate: rates.streaks)
            set(mist, rate: rates.mist)
            set(flecks, rate: rates.flecks)
        }

        func reset() {
            apply(.zero)
            for system in all { system.reset() }
        }

        private var all: [SCNParticleSystem] {
            streaks + mist + flecks
        }

        private func set(_ systems: [SCNParticleSystem], rate: CGFloat) {
            for system in systems { system.birthRate = rate }
        }
    }

    private enum Layer: String, CaseIterable {
        case streaks
        case mist
        case flecks

        var nodeName: String { "\(VoyageBowSpray.nodeName)-\(rawValue)" }
    }

    static func makeNode(palette: Palette) -> SCNNode {
        let root = SCNNode()
        root.name = nodeName
        for layer in Layer.allCases {
            let layerNode = SCNNode()
            layerNode.name = layer.nodeName
            for side in [Float(1), Float(-1)] {
                let emitter = SCNNode()
                emitter.position = position(for: layer, side: side)
                emitter.addParticleSystem(
                    makeSystem(layer: layer, side: side, palette: palette)
                )
                layerNode.addChildNode(emitter)
            }
            root.addChildNode(layerNode)
        }
        return root
    }

    static func systems(in root: SCNNode) -> Systems {
        guard let container = root.childNode(withName: nodeName, recursively: true) else {
            return .empty
        }
        func systems(for layer: Layer) -> [SCNParticleSystem] {
            container.childNode(withName: layer.nodeName, recursively: false)?
                .childNodes.flatMap { $0.particleSystems ?? [] } ?? []
        }
        return Systems(
            streaks: systems(for: .streaks),
            mist: systems(for: .mist),
            flecks: systems(for: .flecks)
        )
    }

    private static func position(for layer: Layer, side: Float) -> SCNVector3 {
        switch layer {
        case .streaks: SCNVector3(1.24, 0.08, 0.19 * side)
        case .mist: SCNVector3(1.18, 0.03, 0.23 * side)
        case .flecks: SCNVector3(1.20, 0.01, 0.24 * side)
        }
    }

    private static func makeSystem(
        layer: Layer,
        side: Float,
        palette: Palette
    ) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.birthRate = 0
        system.emissionDuration = 1
        system.loops = true
        system.blendMode = .alpha
        system.isLightingEnabled = false
        system.sortingMode = .none
        system.isAffectedByGravity = false
        system.isAffectedByPhysicsFields = false
        system.isLocal = false
        system.birthLocation = .volume
        system.birthDirection = .constant

        switch layer {
        case .streaks:
            system.particleImage = streakImage
            system.particleLifeSpan = 0.22
            system.particleLifeSpanVariation = 0.05
            system.particleVelocity = 1.05
            system.particleVelocityVariation = 0.24
            system.emittingDirection = SCNVector3(0.32, 0.68, 0.58 * side)
            system.spreadingAngle = 17
            system.acceleration = SCNVector3(0, -5.8, 0)
            system.particleSize = 0.026
            system.particleSizeVariation = 0.009
            system.particleColor = palette.highlight.withAlphaComponent(0.32)
            system.particleColorVariation = SCNVector4(0.04, 0.10, 0.10, 0.16)
            system.particleAngle = radians(side > 0 ? -24 : 24)
            system.particleAngleVariation = radians(14)
            system.particleAngularVelocityVariation = radians(60)
            system.emitterShape = SCNBox(
                width: 0.045,
                height: 0.015,
                length: 0.16,
                chamferRadius: 0
            )
            system.propertyControllers = controllers(
                size: [0.18, 1.0, 0.20],
                opacity: [0, 0.72, 0.32, 0]
            )

        case .mist:
            system.particleImage = mistImage
            system.particleLifeSpan = 0.42
            system.particleLifeSpanVariation = 0.10
            system.particleVelocity = 0.45
            system.particleVelocityVariation = 0.12
            system.emittingDirection = SCNVector3(0.18, 0.34, 0.44 * side)
            system.spreadingAngle = 32
            system.acceleration = SCNVector3(0, -1.8, 0)
            system.particleSize = 0.082
            system.particleSizeVariation = 0.025
            system.particleColor = palette.highlight.withAlphaComponent(0.09)
            system.particleColorVariation = SCNVector4(0.05, 0.10, 0.10, 0.05)
            system.particleAngleVariation = radians(180)
            system.particleAngularVelocityVariation = radians(20)
            system.emitterShape = SCNBox(
                width: 0.10,
                height: 0.03,
                length: 0.24,
                chamferRadius: 0
            )
            system.propertyControllers = controllers(
                size: [0.30, 1.10, 1.48],
                opacity: [0, 0.76, 0.30, 0]
            )

        case .flecks:
            system.particleImage = fleckImage
            system.particleLifeSpan = 0.16
            system.particleLifeSpanVariation = 0.05
            system.particleVelocity = 0.72
            system.particleVelocityVariation = 0.22
            system.emittingDirection = SCNVector3(-0.10, 0.22, 0.82 * side)
            system.spreadingAngle = 16
            system.acceleration = SCNVector3(0, -6.0, 0)
            system.particleSize = 0.019
            system.particleSizeVariation = 0.008
            system.particleColor = palette.sea.withAlphaComponent(0.38)
            system.particleColorVariation = SCNVector4(0.08, 0.16, 0.14, 0.24)
            system.particleAngle = radians(side > 0 ? -68 : 68)
            system.particleAngleVariation = radians(34)
            system.particleAngularVelocityVariation = radians(80)
            system.emitterShape = SCNBox(
                width: 0.08,
                height: 0.015,
                length: 0.22,
                chamferRadius: 0
            )
            system.propertyControllers = controllers(
                size: [0.45, 1.0, 0.26],
                opacity: [0, 0.85, 0.42, 0]
            )
        }
        return system
    }

    private static func controllers(
        size: [Double],
        opacity: [Double]
    ) -> [SCNParticleSystem.ParticleProperty: SCNParticlePropertyController] {
        let sizeAnimation = CAKeyframeAnimation(keyPath: "size")
        sizeAnimation.values = size.map(NSNumber.init(value:))
        sizeAnimation.keyTimes = normalizedTimes(count: size.count)
        let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnimation.values = opacity.map(NSNumber.init(value:))
        opacityAnimation.keyTimes = normalizedTimes(count: opacity.count)
        return [
            .size: SCNParticlePropertyController(animation: sizeAnimation),
            .opacity: SCNParticlePropertyController(animation: opacityAnimation),
        ]
    }

    private static func normalizedTimes(count: Int) -> [NSNumber] {
        guard count > 1 else { return [0] }
        return (0..<count).map { NSNumber(value: Double($0) / Double(count - 1)) }
    }

    private static func radians(_ degrees: CGFloat) -> CGFloat {
        degrees * .pi / 180
    }

    private static let streakImage = makeStreakImage()
    private static let mistImage = makeMistImage()
    private static let fleckImage = makeFleckImage()

    private static func makeStreakImage() -> UIImage {
        let side: CGFloat = 32
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.saveGState()
            let droplet = UIBezierPath()
            droplet.move(to: CGPoint(x: 16, y: 5))
            droplet.addCurve(
                to: CGPoint(x: 16, y: 27),
                controlPoint1: CGPoint(x: 22, y: 13),
                controlPoint2: CGPoint(x: 22, y: 22)
            )
            droplet.addCurve(
                to: CGPoint(x: 16, y: 5),
                controlPoint1: CGPoint(x: 10, y: 22),
                controlPoint2: CGPoint(x: 10, y: 13)
            )
            droplet.addClip()
            let colors = [
                UIColor(white: 1, alpha: 0).cgColor,
                UIColor(white: 1, alpha: 0.72).cgColor,
                UIColor(white: 1, alpha: 0.46).cgColor,
                UIColor(white: 1, alpha: 0).cgColor,
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.22, 0.62, 1]
            ) else {
                cgContext.restoreGState()
                return
            }
            cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: side / 2, y: 4),
                end: CGPoint(x: side / 2, y: 28),
                options: []
            )
            cgContext.restoreGState()
        }
    }

    private static func makeMistImage() -> UIImage {
        let side: CGFloat = 32
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { context in
            let colors = [
                UIColor(white: 1, alpha: 0.54).cgColor,
                UIColor(white: 1, alpha: 0.18).cgColor,
                UIColor(white: 1, alpha: 0).cgColor,
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.36, 1]
            ) else { return }
            let center = CGPoint(x: side / 2, y: side / 2)
            context.cgContext.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: side / 2,
                options: []
            )
        }
    }

    private static func makeFleckImage() -> UIImage {
        let side: CGFloat = 32
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.saveGState()
            UIBezierPath(
                roundedRect: CGRect(x: 7, y: 14, width: 18, height: 4),
                cornerRadius: 2
            ).addClip()
            let colors = [
                UIColor(white: 1, alpha: 0).cgColor,
                UIColor(white: 1, alpha: 0.82).cgColor,
                UIColor(white: 1, alpha: 0).cgColor,
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.50, 1]
            ) else {
                cgContext.restoreGState()
                return
            }
            cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 7, y: side / 2),
                end: CGPoint(x: 25, y: side / 2),
                options: []
            )
            cgContext.restoreGState()
        }
    }
}
