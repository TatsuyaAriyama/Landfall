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

    private struct Frame {
        let node: SCNNode
        let minimum: SCNVector3
        let span: SCNVector3
        let normal: SCNVector3
        let chordAxis: SCNVector3
        let riseAxis: SCNVector3
        let sailThrow: Float
    }

    private static let geometryShader = """
    #pragma arguments
    float uWind;
    float3 uSailMin;
    float3 uSailSpan;
    float4x4 uSailLocalToFrame;
    float3 uSailNormal;
    float3 uChordAxis;
    float3 uRiseAxis;
    float3 uChordTangent;
    float3 uRiseTangent;
    float uSailThrow;
    #pragma body
    float3 frameP = (uSailLocalToFrame * float4(_geometry.position.xyz, 1.0)).xyz;
    float3 rel = (frameP - uSailMin) / max(uSailSpan, float3(0.0001));
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

    // 面の傾きも同じ式の縦横微分で追う。弦方向だけを更新すると、高さ方向へ
    // 走る皺の陰影が止まり、大きな帆ほど規則的な光帯に見える。
    float chordSpan = max(dot(uSailSpan, uChordAxis), 0.0001);
    float riseSpan = max(dot(uSailSpan, uRiseAxis), 0.0001);
    float dRipplePhase = cos(phase) * 0.62
        + cos(phase * 1.73 + 1.1) * 0.26 * 1.73;
    float dBellyU = 3.14159265 * cos(3.14159265 * u)
        * sin(3.14159265 * v);
    float dBellyV = 3.14159265 * sin(3.14159265 * u)
        * cos(3.14159265 * v);
    float shape = billow + ripple * 0.55;
    float dShapeU = dRipplePhase * 7.4 * 0.55;
    float dShapeV = cos(t * 1.35 + v * 0.8) * 0.45 * 0.8
        + dRipplePhase * 2.6 * 0.55;
    float dAmountU = (dShapeU * belly + shape * dBellyU)
        * uWind * uSailThrow;
    float dAmountV = (dShapeV * belly + shape * dBellyV)
        * uWind * uSailThrow;
    _geometry.normal = normalize(
        _geometry.normal
            - uChordTangent * (dAmountU / chordSpan)
            - uRiseTangent * (dAmountV / riseSpan)
    );
    """

    /// 主帆と前帆を変形フレームとして先に測り、同じ帆へ縫い付けられた
    /// 補修布にも最寄りのフレームを渡す。別メッシュでも変形が剥がれない。
    static func install(in root: SCNNode) {
        var anchors: [(
            node: SCNNode,
            material: SCNMaterial,
            frame: Frame,
            center: SIMD3<Float>
        )] = []
        root.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry,
                  let frame = makeFrame(for: node)
            else { return }
            for material in geometry.materials {
                guard let name = material.name,
                      sailMaterialNames.contains(name)
                else { continue }
                anchors.append((node, material, frame, center(of: node, in: root)))
            }
        }
        guard !anchors.isEmpty else { return }
        for anchor in anchors {
            install(on: anchor.node, material: anchor.material, frame: anchor.frame)
        }

        root.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            let attachmentCenter = center(of: node, in: root)
            for material in geometry.materials where isSailAttachment(
                node: node,
                material: material
            ) {
                guard let anchor = anchors.min(by: {
                    distanceSquared(attachmentCenter, $0.center)
                        < distanceSquared(attachmentCenter, $1.center)
                }) else { continue }
                install(on: node, material: material, frame: anchor.frame)
            }
        }
    }

    /// 帆の素材へシェーダを差し、基準帆の寸法から動く向きと量を決める。
    ///
    /// 帆がどの軸に薄いかはジオメトリの外接箱から測る。縦(マストに沿う辺)は
    /// 長さではなくワールドの上方向で決める — 帆は幅より背が高いので、長い辺を
    /// 弦とみなすと皺が横ではなく縦に走ってしまう。モデルの向きを直しても、
    /// 帆はいつでも自分の面に垂直な、いま孕んでいる側へ膨らむ。
    private static func makeFrame(for node: SCNNode) -> Frame? {
        guard let geometry = node.geometry else { return nil }
        let box = geometry.boundingBox
        let lower = [box.min.x, box.min.y, box.min.z]
        let upper = [box.max.x, box.max.y, box.max.z]
        let extents = (0..<3).map { max(upper[$0] - lower[$0], Float(0.0001)) }
        guard let thinIndex = extents.indices.min(by: { extents[$0] < extents[$1] })
        else { return nil }
        let up = node.simdConvertVector(SIMD3<Float>(0, 1, 0), from: nil)
        let across = (0..<3).filter { $0 != thinIndex }
        guard let riseIndex = across.max(by: { abs(up[$0]) < abs(up[$1]) }),
              let chordIndex = across.first(where: { $0 != riseIndex })
        else { return nil }
        // 布は片側だけへ孕む。モデルが既に膨らんでいる側 — 外接箱が原点から
        // 離れている側 — へ押し出す。軸が反転して読み込まれても帆が凹まない。
        let bellySign: Float = abs(upper[thinIndex]) >= abs(lower[thinIndex]) ? 1 : -1

        return Frame(
            node: node,
            minimum: box.min,
            span: SCNVector3(extents[0], extents[1], extents[2]),
            normal: basis(thinIndex, sign: bellySign),
            chordAxis: basis(chordIndex),
            riseAxis: basis(riseIndex),
            sailThrow: max(extents[thinIndex], 0.05) * 1.15
        )
    }

    private static func install(
        on node: SCNNode,
        material: SCNMaterial,
        frame: Frame
    ) {
        let localToFrame = node.simdConvertTransform(
            matrix_identity_float4x4,
            to: frame.node
        )

        var modifiers = material.shaderModifiers ?? [:]
        modifiers[.geometry] = geometryShader
        material.shaderModifiers = modifiers

        material.setValue(frame.minimum, forKey: "uSailMin")
        material.setValue(frame.span, forKey: "uSailSpan")
        material.setValue(
            NSValue(scnMatrix4: SCNMatrix4(localToFrame)),
            forKey: "uSailLocalToFrame"
        )
        material.setValue(
            converted(frame.normal, from: frame.node, to: node),
            forKey: "uSailNormal"
        )
        material.setValue(frame.chordAxis, forKey: "uChordAxis")
        material.setValue(frame.riseAxis, forKey: "uRiseAxis")
        material.setValue(
            converted(frame.chordAxis, from: frame.node, to: node),
            forKey: "uChordTangent"
        )
        material.setValue(
            converted(frame.riseAxis, from: frame.node, to: node),
            forKey: "uRiseTangent"
        )
        // 孕みの深さは帆自身の厚み(モデルの膨らみ)を基準にする。元の膨らみの
        // 倍ほど押し出すと、遠景でも布が風を受けているとわかり、近景でも
        // マストを突き抜けない。
        material.setValue(
            NSNumber(value: frame.sailThrow),
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
                guard material.shaderModifiers?[.geometry]?
                    .contains("uSailLocalToFrame") == true,
                      !found.contains(where: { $0 === material })
                else { continue }
                found.append(material)
            }
        }
        return found
    }

    private static func isSailAttachment(
        node: SCNNode,
        material: SCNMaterial
    ) -> Bool {
        let identity = "\(node.name ?? "") \(material.name ?? "")".lowercased()
        return identity.contains("sailpatch")
            || identity.contains("sail_patch")
            || identity.contains("sailrepair")
            || identity.contains("sail_repair")
    }

    private static func center(of node: SCNNode, in root: SCNNode) -> SIMD3<Float> {
        let box = node.boundingBox
        let local = SIMD3<Float>(
            (box.min.x + box.max.x) * 0.5,
            (box.min.y + box.max.y) * 0.5,
            (box.min.z + box.max.z) * 0.5
        )
        return root.simdConvertPosition(local, from: node)
    }

    private static func distanceSquared(
        _ lhs: SIMD3<Float>,
        _ rhs: SIMD3<Float>
    ) -> Float {
        simd_length_squared(lhs - rhs)
    }

    private static func converted(
        _ vector: SCNVector3,
        from source: SCNNode,
        to target: SCNNode
    ) -> SCNVector3 {
        let sourceVector = SIMD3<Float>(vector.x, vector.y, vector.z)
        let local = simd_normalize(
            target.simdConvertVector(sourceVector, from: source)
        )
        return SCNVector3(local.x, local.y, local.z)
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

    struct HullProfile {
        let bowContactX: Float
        let waterlineLength: Float
        let halfBeam: Float

        static let standard = HullProfile(
            bowContactX: 1.34,
            waterlineLength: 2.34,
            halfBeam: 0.57
        )
    }

    struct Palette {
        let sea: UIColor
        let highlight: UIColor
    }

    struct Rates {
        static let zero = Rates(streaks: 0, mist: 0, flecks: 0, impulse: 0)

        let streaks: CGFloat
        let mist: CGFloat
        let flecks: CGFloat
        let impulse: CGFloat

        /// Derives each burst from the same wave field that lifts the hull.
        /// `oceanTime` must use `HomeIslandOceanEffects.currentTime` so spray,
        /// buoyancy and the Metal surface reach the bow on the same frame.
        static func sailing(
            wind: Float,
            at oceanTime: Float,
            bowWorldXZ: SIMD2<Float>? = nil
        ) -> Rates {
            let strength = CGFloat(min(max(wind, 0), 1))
            let samplePosition = bowWorldXZ ?? fallbackBowSamplePosition
            let sample = sprayWaveField.sample(
                atWorldXZ: samplePosition,
                time: oceanTime
            )
            let previous = sprayWaveField.sample(
                atWorldXZ: samplePosition,
                time: oceanTime - impactSampleInterval
            )
            let rise = max(
                (sample.displacement - previous.displacement) / impactSampleInterval,
                0
            )
            let risingImpact = min(rise * 8.2, 1)
            let crestContact = min(
                max((sample.displacement + 0.025) / 0.18, 0),
                1
            )
            let impact = CGFloat(min(risingImpact * 0.78 + crestContact * 0.22, 1))
            // A stronger collision changes the motion of the spray, not only
            // the number of identical particles emitted on that frame.
            let impulse = min(strength * 0.44 + impact * 0.72, 1)
            return Rates(
                // A bow continuously peels two thin sheets from the water.
                // Crests thicken those sheets and add mist and heavy flecks;
                // they do not switch the entire contact effect on from zero.
                streaks: 22 * strength * (0.30 + impact * 0.70),
                mist: 10 * strength * (0.18 + impact * 0.82),
                flecks: 12 * strength * pow(impact, 1.80),
                impulse: impulse
            )
        }

        private static let sprayWaveField = HomeIslandMarineDynamics.WaveField(
            layout: .timerVoyage
        )
        /// Login/prologue scenes have no marine controller, so they retain the
        /// authored bow point. Voyage scenes pass their frame's true world bow.
        private static let fallbackBowSamplePosition = SIMD2<Float>(1.20, 0)
        private static let impactSampleInterval: Float = 0.12
    }

    /// レイヤーを配列の順序で識別しない、アニメータ向けの型付きハンドル。
    struct Systems {
        static let empty = Systems(streaks: [], mist: [], flecks: [])

        let streaks: [SCNParticleSystem]
        let mist: [SCNParticleSystem]
        let flecks: [SCNParticleSystem]

        func apply(_ rates: Rates) {
            set(
                streaks,
                rate: rates.streaks,
                impulse: rates.impulse,
                velocity: 0.90...1.32,
                size: 0.060...0.095
            )
            set(
                mist,
                rate: rates.mist,
                impulse: rates.impulse,
                velocity: 0.42...0.68,
                size: 0.090...0.150
            )
            set(
                flecks,
                rate: rates.flecks,
                impulse: rates.impulse,
                velocity: 0.58...1.00,
                size: 0.018...0.030
            )
        }

        func reset() {
            apply(.zero)
            for system in all { system.reset() }
        }

        private var all: [SCNParticleSystem] {
            streaks + mist + flecks
        }

        private func set(
            _ systems: [SCNParticleSystem],
            rate: CGFloat,
            impulse: CGFloat,
            velocity: ClosedRange<CGFloat>,
            size: ClosedRange<CGFloat>
        ) {
            let amount = min(max(impulse, 0), 1)
            for system in systems {
                system.birthRate = rate
                system.particleVelocity = velocity.lowerBound
                    + (velocity.upperBound - velocity.lowerBound) * amount
                system.particleSize = size.lowerBound
                    + (size.upperBound - size.lowerBound) * amount
            }
        }
    }

    private enum Layer: String, CaseIterable {
        case streaks
        case mist
        case flecks

        var nodeName: String { "\(VoyageBowSpray.nodeName)-\(rawValue)" }
    }

    /// Measures only low geometry crossing the authored waterline. Tall merged
    /// rigging and bowsprits cannot pull the emitter ahead of the physical hull.
    static func hullProfile(in root: SCNNode, waterline: Float) -> HullProfile {
        var minimumX = Float.greatestFiniteMagnitude
        var maximumX = -Float.greatestFiniteMagnitude
        var minimumZ = Float.greatestFiniteMagnitude
        var maximumZ = -Float.greatestFiniteMagnitude

        root.enumerateChildNodes { node, _ in
            guard node.geometry != nil else { return }
            let bounds = node.boundingBox
            let corners = [
                SCNVector3(bounds.min.x, bounds.min.y, bounds.min.z),
                SCNVector3(bounds.min.x, bounds.min.y, bounds.max.z),
                SCNVector3(bounds.min.x, bounds.max.y, bounds.min.z),
                SCNVector3(bounds.min.x, bounds.max.y, bounds.max.z),
                SCNVector3(bounds.max.x, bounds.min.y, bounds.min.z),
                SCNVector3(bounds.max.x, bounds.min.y, bounds.max.z),
                SCNVector3(bounds.max.x, bounds.max.y, bounds.min.z),
                SCNVector3(bounds.max.x, bounds.max.y, bounds.max.z),
            ].map { node.convertPosition($0, to: root) }
            let xValues = corners.map(\.x)
            let yValues = corners.map(\.y)
            let zValues = corners.map(\.z)
            guard let lowest = yValues.min(),
                  let highest = yValues.max(),
                  lowest <= waterline + 0.02,
                  highest <= waterline + 1.15
            else { return }

            minimumX = min(minimumX, xValues.min() ?? minimumX)
            maximumX = max(maximumX, xValues.max() ?? maximumX)
            minimumZ = min(minimumZ, zValues.min() ?? minimumZ)
            maximumZ = max(maximumZ, zValues.max() ?? maximumZ)
        }

        guard minimumX.isFinite, maximumX.isFinite,
              minimumZ.isFinite, maximumZ.isFinite
        else { return .standard }
        let hullLength = max(maximumX - minimumX, 0.1)
        return HullProfile(
            bowContactX: maximumX - max(hullLength * 0.018, 0.035),
            waterlineLength: hullLength,
            halfBeam: max(max(abs(minimumZ), abs(maximumZ)), 0.1)
        )
    }

    static func makeNode(palette: Palette, hull: HullProfile) -> SCNNode {
        let root = SCNNode()
        root.name = nodeName
        for layer in Layer.allCases {
            let layerNode = SCNNode()
            layerNode.name = layer.nodeName
            for side in [Float(1), Float(-1)] {
                let emitter = SCNNode()
                emitter.position = position(for: layer, side: side, hull: hull)
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

    private static func position(
        for layer: Layer,
        side: Float,
        hull: HullProfile
    ) -> SCNVector3 {
        switch layer {
        case .streaks:
            SCNVector3(hull.bowContactX, 0.08, hull.halfBeam * 0.33 * side)
        case .mist:
            SCNVector3(hull.bowContactX - 0.06, 0.03, hull.halfBeam * 0.40 * side)
        case .flecks:
            SCNVector3(hull.bowContactX - 0.04, 0.01, hull.halfBeam * 0.42 * side)
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
            system.particleVelocity = 1.12
            system.particleVelocityVariation = 0.24
            system.emittingDirection = SCNVector3(0.32, 0.68, 0.58 * side)
            system.spreadingAngle = 14
            system.acceleration = SCNVector3(0, -5.8, 0)
            system.particleSize = 0.027
            system.particleSizeVariation = 0.006
            system.particleColor = palette.highlight.withAlphaComponent(0.28)
            system.particleColorVariation = SCNVector4(0.04, 0.10, 0.10, 0.10)
            system.particleAngle = radians(side > 0 ? -28 : 28)
            system.particleAngleVariation = radians(9)
            system.particleAngularVelocityVariation = radians(18)
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
            system.particleLifeSpan = 0.36
            system.particleLifeSpanVariation = 0.08
            system.particleVelocity = 0.54
            system.particleVelocityVariation = 0.12
            system.emittingDirection = SCNVector3(0.18, 0.28, 0.48 * side)
            system.spreadingAngle = 24
            system.acceleration = SCNVector3(0, -1.6, 0)
            system.particleSize = 0.11
            system.particleSizeVariation = 0.022
            system.particleColor = palette.highlight.withAlphaComponent(0.11)
            system.particleColorVariation = SCNVector4(0.05, 0.10, 0.10, 0.035)
            system.particleAngle = radians(side > 0 ? -11 : 11)
            system.particleAngleVariation = radians(9)
            system.particleAngularVelocityVariation = radians(7)
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
            system.particleLifeSpan = 0.14
            system.particleLifeSpanVariation = 0.05
            system.particleVelocity = 0.78
            system.particleVelocityVariation = 0.22
            system.emittingDirection = SCNVector3(-0.10, 0.22, 0.82 * side)
            system.spreadingAngle = 13
            system.acceleration = SCNVector3(0, -6.0, 0)
            system.particleSize = 0.018
            system.particleSizeVariation = 0.005
            system.particleColor = palette.sea.withAlphaComponent(0.22)
            system.particleColorVariation = SCNVector4(0.08, 0.16, 0.14, 0.14)
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
        let side: CGFloat = 64
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.saveGState()
            let ribbon = UIBezierPath()
            ribbon.move(to: CGPoint(x: 24, y: 5))
            ribbon.addCurve(
                to: CGPoint(x: 41, y: 58),
                controlPoint1: CGPoint(x: 20, y: 18),
                controlPoint2: CGPoint(x: 45, y: 41)
            )
            ribbon.addCurve(
                to: CGPoint(x: 24, y: 5),
                controlPoint1: CGPoint(x: 35, y: 40),
                controlPoint2: CGPoint(x: 29, y: 19)
            )
            ribbon.addClip()
            let colors = [
                UIColor(white: 1, alpha: 0).cgColor,
                UIColor(white: 1, alpha: 0.46).cgColor,
                UIColor(white: 1, alpha: 0.72).cgColor,
                UIColor(white: 1, alpha: 0.28).cgColor,
                UIColor(white: 1, alpha: 0).cgColor,
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.18, 0.48, 0.80, 1]
            ) else {
                cgContext.restoreGState()
                return
            }
            cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: side / 2, y: 4),
                end: CGPoint(x: side / 2, y: 60),
                options: []
            )
            cgContext.restoreGState()
        }
    }

    private static func makeMistImage() -> UIImage {
        let side: CGFloat = 64
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.saveGState()
            let sheet = UIBezierPath()
            sheet.move(to: CGPoint(x: 3, y: 34))
            sheet.addCurve(
                to: CGPoint(x: 61, y: 27),
                controlPoint1: CGPoint(x: 18, y: 17),
                controlPoint2: CGPoint(x: 45, y: 20)
            )
            sheet.addCurve(
                to: CGPoint(x: 3, y: 34),
                controlPoint1: CGPoint(x: 43, y: 39),
                controlPoint2: CGPoint(x: 17, y: 47)
            )
            sheet.addClip()
            let colors = [
                UIColor(white: 1, alpha: 0).cgColor,
                UIColor(white: 1, alpha: 0.30).cgColor,
                UIColor(white: 1, alpha: 0.18).cgColor,
                UIColor(white: 1, alpha: 0).cgColor,
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.25, 0.62, 1]
            ) else {
                cgContext.restoreGState()
                return
            }
            cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 2, y: side / 2),
                end: CGPoint(x: 62, y: side / 2),
                options: []
            )
            cgContext.restoreGState()
        }
    }

    private static func makeFleckImage() -> UIImage {
        let side: CGFloat = 32
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.saveGState()
            UIBezierPath(roundedRect: CGRect(x: 4, y: 15, width: 24, height: 2),
                         cornerRadius: 1).addClip()
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
                start: CGPoint(x: 4, y: side / 2),
                end: CGPoint(x: 28, y: side / 2),
                options: []
            )
            cgContext.restoreGState()
        }
    }
}
