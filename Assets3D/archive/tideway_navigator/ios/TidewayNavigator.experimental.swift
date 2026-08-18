// Experimental Tideway iOS integration archived on 2026-08-11.
// It is intentionally outside the synchronized app source tree.
import CryptoKit
import SceneKit
import UIKit
import simd

private enum TidewayMotionFormat {
    static let magic = Data("TWMOTN03".utf8)
    static let schemaVersion: UInt16 = 3
    static let maximumBones = 64
    static let maximumFrames = 4_096
}

private struct TidewayJointPose {
    let position: SIMD3<Float>
    let orientation: simd_quatf
    let scale: SIMD3<Float>

    static func interpolate(
        _ lhs: TidewayJointPose,
        _ rhs: TidewayJointPose,
        fraction: Float
    ) -> TidewayJointPose {
        let weight = min(max(fraction, 0), 1)
        var rhsOrientation = rhs.orientation
        if simd_dot(lhs.orientation.vector, rhsOrientation.vector) < 0 {
            rhsOrientation = simd_quatf(vector: -rhsOrientation.vector)
        }
        return TidewayJointPose(
            position: simd_mix(
                lhs.position,
                rhs.position,
                SIMD3<Float>(repeating: weight)
            ),
            orientation: simd_slerp(lhs.orientation, rhsOrientation, weight),
            scale: simd_mix(
                lhs.scale,
                rhs.scale,
                SIMD3<Float>(repeating: weight)
            )
        )
    }
}

private struct TidewayBinaryCursor {
    let data: Data
    var offset = 0

    var remainingCount: Int { data.count - offset }

    mutating func readData(count: Int) -> Data? {
        guard count >= 0, offset <= data.count - count else { return nil }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }

    mutating func readInteger<T: FixedWidthInteger>(_ type: T.Type) -> T? {
        let count = MemoryLayout<T>.size
        guard count > 0, offset <= data.count - count else { return nil }
        let value = data.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: offset, as: T.self)
        }
        offset += count
        return T(littleEndian: value)
    }

    mutating func readFloat() -> Float? {
        guard let bits = readInteger(UInt32.self) else { return nil }
        return Float(bitPattern: bits)
    }

    mutating func readString() -> String? {
        guard let length = readInteger(UInt16.self),
              length <= 512,
              let bytes = readData(count: Int(length))
        else { return nil }
        return String(data: bytes, encoding: .utf8)
    }
}

/// Fixed-size, SceneKit-evaluated joint animation generated from the USDZ by
/// `Tools/RenderHarness/TidewayMotionCompiler.swift`. The original USD player
/// is deliberately not copied: copied UsdSkel animations lose their skeleton
/// binding on current SceneKit releases.
private final class TidewayMotionLibrary {
    struct Clip {
        let name: String
        let normalizedName: String
        let startFrame: Int
        let frameCount: Int
        let loops: Bool
        let authoredSpeed: Float

        func duration(fps: Float) -> Float {
            Float(max(frameCount - 1, 1)) / fps
        }
    }

    let assetVersion: Int
    let fps: Float
    let authoredHeight: Float
    let sitSurfaceHeight: Float
    let walkGroundSpeed: Float
    let runGroundSpeed: Float
    let boneNames: [String]
    let parentIndices: [Int]
    let clips: [Clip]
    let frames: [TidewayJointPose]
    let frameCount: Int
    let assetHashMatches: Bool

    private let clipsByName: [String: Clip]

    init?(
        data: Data,
        assetData: Data
    ) {
        var cursor = TidewayBinaryCursor(data: data)
        guard cursor.readData(count: TidewayMotionFormat.magic.count)
                == TidewayMotionFormat.magic,
              cursor.readInteger(UInt16.self) == TidewayMotionFormat.schemaVersion,
              let rawAssetVersion = cursor.readInteger(UInt16.self),
              let rawFPS = cursor.readInteger(UInt16.self),
              let rawBoneCount = cursor.readInteger(UInt16.self),
              let rawClipCount = cursor.readInteger(UInt16.self),
              cursor.readInteger(UInt16.self) != nil,
              let rawFrameCount = cursor.readInteger(UInt32.self),
              let authoredHeight = cursor.readFloat(),
              let sitSurfaceHeight = cursor.readFloat(),
              let walkGroundSpeed = cursor.readFloat(),
              let runGroundSpeed = cursor.readFloat(),
              let expectedAssetHash = cursor.readData(count: SHA256.byteCount)
        else { return nil }

        let boneCount = Int(rawBoneCount)
        let clipCount = Int(rawClipCount)
        let frameCount = Int(rawFrameCount)
        guard (1...120).contains(Int(rawFPS)),
              (1...TidewayMotionFormat.maximumBones).contains(boneCount),
              (1...128).contains(clipCount),
              (2...TidewayMotionFormat.maximumFrames).contains(frameCount),
              authoredHeight.isFinite, authoredHeight > 0.1,
              sitSurfaceHeight.isFinite, sitSurfaceHeight > 0,
              walkGroundSpeed.isFinite, walkGroundSpeed > 0,
              runGroundSpeed.isFinite, runGroundSpeed > walkGroundSpeed
        else { return nil }

        var boneNames: [String] = []
        var parentIndices: [Int] = []
        boneNames.reserveCapacity(boneCount)
        parentIndices.reserveCapacity(boneCount)
        for _ in 0..<boneCount {
            guard let name = cursor.readString(), !name.isEmpty,
                  let rawParentIndex = cursor.readInteger(Int16.self)
            else { return nil }
            let parentIndex = Int(rawParentIndex)
            guard parentIndex == -1 || (0..<boneCount).contains(parentIndex) else {
                return nil
            }
            boneNames.append(name)
            parentIndices.append(parentIndex)
        }
        guard Set(boneNames).count == boneNames.count else { return nil }

        var clips: [Clip] = []
        clips.reserveCapacity(clipCount)
        for _ in 0..<clipCount {
            guard let name = cursor.readString(), !name.isEmpty,
                  let rawStartFrame = cursor.readInteger(UInt32.self),
                  let rawClipFrameCount = cursor.readInteger(UInt32.self),
                  let flags = cursor.readInteger(UInt16.self),
                  cursor.readInteger(UInt16.self) != nil,
                  let authoredSpeed = cursor.readFloat()
            else { return nil }
            let startFrame = Int(rawStartFrame)
            let clipFrameCount = Int(rawClipFrameCount)
            guard startFrame >= 0,
                  clipFrameCount >= 2,
                  startFrame <= frameCount - clipFrameCount,
                  authoredSpeed.isFinite, authoredSpeed >= 0
            else { return nil }
            clips.append(
                Clip(
                    name: name,
                    normalizedName: Self.normalize(name),
                    startFrame: startFrame,
                    frameCount: clipFrameCount,
                    loops: flags & 1 == 1,
                    authoredSpeed: authoredSpeed
                )
            )
        }
        guard Set(clips.map(\.normalizedName)).count == clips.count else { return nil }

        let poseCount = frameCount.multipliedReportingOverflow(by: boneCount)
        guard !poseCount.overflow,
              poseCount.partialValue <= Int.max / (10 * MemoryLayout<Float>.size),
              cursor.remainingCount == poseCount.partialValue * 10 * MemoryLayout<Float>.size
        else { return nil }
        var frames: [TidewayJointPose] = []
        frames.reserveCapacity(poseCount.partialValue)
        for _ in 0..<poseCount.partialValue {
            guard let px = cursor.readFloat(), let py = cursor.readFloat(),
                  let pz = cursor.readFloat(), let qx = cursor.readFloat(),
                  let qy = cursor.readFloat(), let qz = cursor.readFloat(),
                  let qw = cursor.readFloat(), let sx = cursor.readFloat(),
                  let sy = cursor.readFloat(), let sz = cursor.readFloat()
            else { return nil }
            let position = SIMD3<Float>(px, py, pz)
            let quaternion = simd_quatf(ix: qx, iy: qy, iz: qz, r: qw)
            let scale = SIMD3<Float>(sx, sy, sz)
            guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
                  quaternion.vector.x.isFinite, quaternion.vector.y.isFinite,
                  quaternion.vector.z.isFinite, quaternion.vector.w.isFinite,
                  simd_length(quaternion.vector) > 0.5,
                  scale.x.isFinite, scale.y.isFinite, scale.z.isFinite
            else { return nil }
            frames.append(
                TidewayJointPose(
                    position: position,
                    orientation: simd_normalize(quaternion),
                    scale: scale
                )
            )
        }

        let normalizedNames = Set(clips.map(\.normalizedName))
        guard ["idle", "walk", "run", "sit"].allSatisfy(normalizedNames.contains) else {
            return nil
        }
        self.assetVersion = Int(rawAssetVersion)
        self.fps = Float(rawFPS)
        self.authoredHeight = authoredHeight
        self.sitSurfaceHeight = sitSurfaceHeight
        self.walkGroundSpeed = walkGroundSpeed
        self.runGroundSpeed = runGroundSpeed
        self.boneNames = boneNames
        self.parentIndices = parentIndices
        self.clips = clips
        self.frames = frames
        self.frameCount = frameCount
        self.assetHashMatches = Data(SHA256.hash(data: assetData)) == expectedAssetHash
        self.clipsByName = Dictionary(
            uniqueKeysWithValues: clips.map { ($0.normalizedName, $0) }
        )
    }

    func clip(named name: String) -> Clip? {
        clipsByName[Self.normalize(name)]
    }

    func firstClip(named candidates: [String]) -> Clip? {
        candidates.lazy.compactMap(clip(named:)).first
    }

    func sample(_ clip: Clip, phase: Float, into output: inout [TidewayJointPose]) {
        guard output.count == boneNames.count else { return }
        let clampedPhase: Float
        if clip.loops {
            clampedPhase = phase - floor(phase)
        } else {
            clampedPhase = min(max(phase, 0), 1)
        }
        let intervalCount = max(clip.frameCount - 1, 1)
        let framePosition = clampedPhase * Float(intervalCount)
        let lowerLocalFrame = min(Int(floor(framePosition)), intervalCount)
        let upperLocalFrame = min(lowerLocalFrame + 1, intervalCount)
        let fraction = framePosition - Float(lowerLocalFrame)
        let lowerOffset = (clip.startFrame + lowerLocalFrame) * boneNames.count
        let upperOffset = (clip.startFrame + upperLocalFrame) * boneNames.count
        for boneIndex in boneNames.indices {
            output[boneIndex] = TidewayJointPose.interpolate(
                frames[lowerOffset + boneIndex],
                frames[upperOffset + boneIndex],
                fraction: fraction
            )
        }
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// Blender-authored navigator used only while exploring the home island.
///
/// Movement, grounding and collision remain owned by `HomeIslandSceneView`.
/// This type is deliberately limited to loading the visual hierarchy and
/// animating it in place, so replacing the character cannot invalidate saved
/// island placements or the existing walking rules.
enum TidewayNavigator {
    static let resourceName = "tideway_navigator"
    static let contactShadowName = "tideway-contact-shadow"
    static let contactShadowOpacity: CGFloat = 0.21
    static let homeIslandScale: Float = 0.78

    struct Instance {
        let node: SCNNode
        let usesImportedAsset: Bool
        /// Root-to-seat distance after asset-height normalization, before the
        /// Home Island's outer character scale is applied.
        let normalizedRootToSeatSurface: Float
        let walkGroundSpeed: Float
        fileprivate let motionLibrary: TidewayMotionLibrary?
    }

    /// The exported names are a small runtime contract between Blender and iOS.
    /// Rejecting a partial rig is safer than showing a character with detached
    /// limbs; the procedural navigator remains the lossless fallback.
    fileprivate static let requiredRigNames = [
        "root", "contact", "core", "head",
        "armL", "armR", "forearmL", "forearmR",
        "legL", "legR", "kneeL", "kneeR",
        "cape", "lantern",
    ]

    /// Visual target before Home Island adds its outer scene scale. Authored
    /// source dimensions live in the generated motion header, not Swift.
    private static let normalizedHeight: Float = 1.35

    static func makeHomeIslandInstance(bundle: Bundle = .main) -> Instance {
        guard let importedAsset = loadImportedNode(bundle: bundle) else {
            return fallbackInstance()
        }
        let imported = importedAsset.node

        let nodes = namedNodes(in: imported)
        let missing = requiredRigNames.filter { nodes[$0] == nil }
        guard missing.isEmpty else {
            #if DEBUG
            print("TidewayNavigator: invalid rig; missing \(missing.joined(separator: ", "))")
            #endif
            return fallbackInstance()
        }

        let bounds = imported.boundingBox
        let boundsMin = bounds.min
        let boundsMax = bounds.max
        let authoredHeight = boundsMax.y - boundsMin.y
        guard authoredHeight.isFinite, authoredHeight > 0.05 else {
            #if DEBUG
            print("TidewayNavigator: unusable authored height \(authoredHeight)")
            #endif
            return fallbackInstance()
        }

        let motionLibrary = loadMotionLibrary(
            bundle: bundle,
            assetURL: importedAsset.url
        )
        let motionDimensionsAreValid: Bool
        if let motionLibrary {
            let relativeError = abs(motionLibrary.authoredHeight - authoredHeight)
                / motionLibrary.authoredHeight
            motionDimensionsAreValid = relativeError <= 0.02
            #if DEBUG
            if !motionLibrary.assetHashMatches {
                print("TidewayNavigator: motion/asset hash mismatch; using Showcase fallback")
            }
            if !motionDimensionsAreValid {
                print("TidewayNavigator: motion authoredHeight does not match SceneKit bounds")
            }
            #endif
        } else {
            motionDimensionsAreValid = false
        }
        let motionContract = motionDimensionsAreValid ? motionLibrary : nil
        let trustedMotion = motionContract?.assetHashMatches == true
            ? motionContract
            : nil
        let sourceHeight = trustedMotion?.authoredHeight ?? authoredHeight
        let scale = normalizedHeight / sourceHeight
        let normalization = SCNNode()
        normalization.name = "tideway-normalization"
        normalization.scale = SCNVector3(scale, scale, scale)
        normalization.position.y = -boundsMin.y * scale
        normalization.addChildNode(imported)

        let navigator = SCNNode()
        navigator.name = "navigator"
        navigator.addChildNode(normalization)
        navigator.addChildNode(makeContactShadowNode())
        return Instance(
            node: navigator,
            usesImportedAsset: true,
            normalizedRootToSeatSurface: (trustedMotion?.sitSurfaceHeight
                ?? PhoenixNavigator.seatedRig.rootToSurface / max(scale, 0.0001)) * scale,
            walkGroundSpeed: trustedMotion?.walkGroundSpeed ?? 1,
            motionLibrary: motionContract
        )
    }

    /// SceneKit's deferred sun shadow is intentionally soft and almost
    /// disappears over pale sand on a phone-sized render. This small constant-
    /// lit ellipse restores contact without adding another realtime light or
    /// shadow map. It stays attached to the world-contact root, not the rig, so
    /// imported clips can never lift it with the character's body.
    private static func makeContactShadowNode() -> SCNNode {
        let plane = SCNPlane(width: 0.22, height: 0.058)
        plane.widthSegmentCount = 1
        plane.heightSegmentCount = 1

        let material = SCNMaterial()
        material.name = "tideway-contact-shadow-material"
        material.lightingModel = .constant
        material.diffuse.contents = contactShadowTexture
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.blendMode = .alpha
        plane.materials = [material]

        let node = SCNNode(geometry: plane)
        node.name = contactShadowName
        node.eulerAngles.x = -.pi / 2
        node.position.y = 0.012
        node.opacity = contactShadowOpacity
        node.renderingOrder = 3
        return node
    }

    private static let contactShadowTexture: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 64, height: 16), format: format)
            .image { context in
                let colors = [
                    UIColor.black.withAlphaComponent(0.92).cgColor,
                    UIColor.black.withAlphaComponent(0.42).cgColor,
                    UIColor.clear.cgColor,
                ] as CFArray
                guard let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: colors,
                    locations: [0, 0.56, 1]
                ) else { return }
                let graphics = context.cgContext
                graphics.translateBy(x: 32, y: 8)
                graphics.scaleBy(x: 1, y: 0.25)
                graphics.drawRadialGradient(
                    gradient,
                    startCenter: .zero,
                    startRadius: 0,
                    endCenter: .zero,
                    endRadius: 30,
                    options: [.drawsAfterEndLocation]
                )
            }
    }()

    fileprivate static func namedNodes(in root: SCNNode) -> [String: SCNNode] {
        let requiredLookup = Dictionary(
            uniqueKeysWithValues: requiredRigNames.map { ($0.lowercased(), $0) }
        )
        var result: [String: SCNNode] = [:]

        func collect(_ node: SCNNode) {
            if let name = node.name,
               let canonical = requiredLookup[name.lowercased()],
               result[canonical] == nil {
                result[canonical] = node
            }
            node.childNodes.forEach(collect)
        }
        collect(root)
        return result
    }

    private static func loadImportedNode(bundle: Bundle) -> (node: SCNNode, url: URL)? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "usdz") else {
            #if DEBUG
            print("TidewayNavigator: \(resourceName).usdz is not bundled; using fallback")
            #endif
            return nil
        }

        if let reference = SCNReferenceNode(url: url) {
            reference.load()
            reference.name = "tideway-import"
            return (reference, url)
        }

        guard let scene = try? SCNScene(url: url, options: nil) else {
            #if DEBUG
            print("TidewayNavigator: failed to load \(url.lastPathComponent)")
            #endif
            return nil
        }
        let container = SCNNode()
        container.name = "tideway-import"
        for child in scene.rootNode.childNodes {
            child.removeFromParentNode()
            container.addChildNode(child)
        }
        return (container, url)
    }

    private static func loadMotionLibrary(
        bundle: Bundle,
        assetURL: URL
    ) -> TidewayMotionLibrary? {
        guard let motionURL = bundle.url(forResource: resourceName, withExtension: "twmotion"),
              let motionData = try? Data(contentsOf: motionURL, options: .mappedIfSafe),
              let assetData = try? Data(contentsOf: assetURL, options: .mappedIfSafe),
              let library = TidewayMotionLibrary(data: motionData, assetData: assetData)
        else {
            #if DEBUG
            print("TidewayNavigator: generated motion unavailable or invalid")
            #endif
            return nil
        }
        return library
    }

    private static func fallbackInstance() -> Instance {
        let fallback = PhoenixNavigator.makeNavigatorNode()
        fallback.name = "navigator"
        return Instance(
            node: fallback,
            usesImportedAsset: false,
            normalizedRootToSeatSurface: PhoenixNavigator.seatedRig.rootToSurface,
            walkGroundSpeed: 1,
            motionLibrary: nil
        )
    }
}

/// Drives the imported navigator without taking ownership of world movement.
/// Separate named clips are preferred when available. Blender's USD exporter
/// currently emits one concatenated `Tideway_Showcase`; its original SceneKit
/// player retains the skeleton binding, so the animator samples validated clip
/// ranges by time offset. A lightweight pivot animator remains the final safety
/// net for an unknown or incomplete export.
final class TidewayAnimator: NSObject, SCNSceneRendererDelegate {
    var pose: PhoenixPose = .idle
    /// Actual Home Island ground speed in world units per second. This keeps
    /// the imported foot cadence matched to joystick displacement.
    var locomotionSpeed: Float = 0
    /// Actual outer-node yaw velocity in radians per second. v3 turn/bank
    /// clips can respond without changing collision-owned world rotation.
    var yawRate: Float = 0
    /// Fully blocked movement transitions to Idle immediately so feet cannot
    /// cycle against an obstacle while the stick remains held.
    var movementBlocked = false

    private enum Motion: String, CaseIterable {
        case idle, walk, run, sit
    }

    private struct ShowcaseRange {
        let start: TimeInterval
        let end: TimeInterval
        let loops: Bool

        var duration: TimeInterval { max(end - start, 1 / 24) }
    }

    private struct RestTransform {
        let position: SCNVector3
        let eulerAngles: SCNVector3
        let scale: SCNVector3
    }

    private enum SampledMode {
        case idle, locomotion, sit, standing
    }

    private let fallbackAnimator = PhoenixAnimator()
    private weak var boundScene: SCNScene?
    private weak var navigator: SCNNode?
    private var usesImportedAsset = false
    private var rigNodes: [String: SCNNode] = [:]
    private var restTransforms: [String: RestTransform] = [:]
    private var clipPlayers: [Motion: [SCNAnimationPlayer]] = [:]
    private var usesImportedClips = false
    private var showcasePlayer: SCNAnimationPlayer?
    private var usesShowcaseAnimation = false
    private var activeMotion: Motion?
    private var pendingMotion: Motion?
    private var showcasePhase: TimeInterval = 0
    private var showcaseBlend: CGFloat = 0
    private var showcaseStarted = false
    private var startTime: TimeInterval?
    private var lastTime: TimeInterval?
    private var walkWeight: Float = 0
    private var sitWeight: Float = 0
    private var motionLibrary: TidewayMotionLibrary?
    private var sampledBones: [SCNNode] = []
    private var usesSampledMotion = false
    private var sampledMode: SampledMode?
    private var sampledModeElapsed: Float = 0
    private var locomotionPhase: Float = 0
    private var transitionElapsed: Float = 0
    private var transitionDuration: Float = 0.18
    private var sampledOutput: [TidewayJointPose] = []
    private var sampledA: [TidewayJointPose] = []
    private var sampledB: [TidewayJointPose] = []
    private var transitionOrigin: [TidewayJointPose] = []
    private var idleVariantIndex = 0
    private var nextIdleVariantTime: Float = 3.8
    private var activeIdleVariant: TidewayMotionLibrary.Clip?
    private var idleVariantElapsed: Float = 0
    private var stateOneShotClip: TidewayMotionLibrary.Clip?
    private var stateOneShotElapsed: Float = 0
    private var showcaseRanges: [Motion: ShowcaseRange] = [:]

    func bind(_ instance: TidewayNavigator.Instance, in scene: SCNScene) {
        boundScene = scene
        navigator = instance.node
        usesImportedAsset = instance.usesImportedAsset
        activeMotion = nil
        pendingMotion = nil
        showcasePhase = 0
        showcaseBlend = 0
        showcaseStarted = false
        startTime = nil
        lastTime = nil
        walkWeight = 0
        sitWeight = 0
        motionLibrary = instance.motionLibrary
        sampledBones.removeAll()
        usesSampledMotion = false
        sampledMode = nil
        sampledModeElapsed = 0
        locomotionPhase = 0
        transitionElapsed = 0
        sampledOutput.removeAll()
        sampledA.removeAll()
        sampledB.removeAll()
        transitionOrigin.removeAll()
        idleVariantIndex = 0
        nextIdleVariantTime = 3.8
        activeIdleVariant = nil
        idleVariantElapsed = 0
        stateOneShotClip = nil
        stateOneShotElapsed = 0
        showcaseRanges = makeShowcaseRanges(from: instance.motionLibrary)

        guard usesImportedAsset else {
            rigNodes.removeAll()
            restTransforms.removeAll()
            clipPlayers.removeAll()
            usesImportedClips = false
            showcasePlayer = nil
            usesShowcaseAnimation = false
            fallbackAnimator.bindIfNeeded(scene)
            return
        }


        if let library = instance.motionLibrary,
           library.assetHashMatches,
           let bones = bindSampledBones(library: library, in: instance.node) {
            sampledBones = bones
            let initialPose = Array(library.frames.prefix(library.boneNames.count))
            sampledOutput = initialPose
            sampledA = initialPose
            sampledB = initialPose
            transitionOrigin = initialPose
            usesSampledMotion = true
            removeAllAnimations(in: instance.node)
            applySampledPose(initialPose)
            #if DEBUG
            print(
                "TidewayAnimator: sampled motion v\(library.assetVersion), "
                    + "\(library.boneNames.count) bones, \(library.frameCount) frames"
            )
            #endif
            return
        }

        rigNodes = TidewayNavigator.namedNodes(in: instance.node)
        clipPlayers = collectClipPlayers(from: instance.node)
        usesImportedClips = Motion.allCases.allSatisfy { !(clipPlayers[$0] ?? []).isEmpty }
        showcasePlayer = findValidatedShowcasePlayer(
            in: instance.node,
            ranges: showcaseRanges
        )
        usesShowcaseAnimation = !usesImportedClips && showcasePlayer != nil

        // Imported clips may auto-play as soon as a reference node loads. Stop
        // every player before capturing the neutral transform used by the
        // procedural fallback.
        stopAllAnimations(in: instance.node)
        if let showcasePlayer, usesShowcaseAnimation {
            showcasePlayer.speed = 0
            showcasePlayer.blendFactor = 0
            showcasePlayer.animation.blendInDuration = 0
            showcasePlayer.animation.blendOutDuration = 0
            showcasePlayer.animation.repeatCount = CGFloat.greatestFiniteMagnitude
        }
        restTransforms = Dictionary(uniqueKeysWithValues: rigNodes.map { name, node in
            (
                name,
                RestTransform(
                    position: node.position,
                    eulerAngles: node.eulerAngles,
                    scale: node.scale
                )
            )
        })
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let scene = renderer.scene else { return }
        if boundScene !== scene {
            // Scene replacement is unexpected on Home Island. Falling back is
            // preferable to binding a character from an unrelated scene.
            usesImportedAsset = false
            fallbackAnimator.bindIfNeeded(scene)
        }

        guard usesImportedAsset else {
            fallbackAnimator.pose = pose
            fallbackAnimator.renderer(renderer, updateAtTime: time)
            return
        }

        if startTime == nil {
            startTime = time
            lastTime = time
        }
        let elapsed = Float(time - (startTime ?? time))
        let deltaTime = Float(min(max(time - (lastTime ?? time), 0), 0.05))
        lastTime = time

        if usesSampledMotion {
            stepSampledMotion(deltaTime: deltaTime)
            return
        }
        let motion = motion(for: pose)
        if usesImportedClips {
            transitionToImportedClipIfNeeded(motion, deltaTime: deltaTime)
            return
        }
        if usesShowcaseAnimation {
            stepShowcaseAnimation(motion: motion, deltaTime: deltaTime)
            return
        }
        stepProceduralAnimation(time: elapsed, deltaTime: deltaTime, motion: motion)
    }

    private func motion(for pose: PhoenixPose) -> Motion {
        switch pose {
        case .walk:
            let walkThreshold = (motionLibrary?.walkGroundSpeed ?? 1) * 1.38
            let runThreshold = (motionLibrary?.runGroundSpeed ?? 1.6) * 0.82
            if locomotionSpeed >= runThreshold { return .run }
            if locomotionSpeed <= walkThreshold { return .walk }
            // Hysteresis avoids switching clips every frame while the stick
            // hovers around the walk/run boundary.
            if activeMotion == .run || pendingMotion == .run { return .run }
            return .walk
        case .sit:
            return .sit
        default:
            return .idle
        }
    }

    private func bindSampledBones(
        library: TidewayMotionLibrary,
        in root: SCNNode
    ) -> [SCNNode]? {
        var nodesByName: [String: SCNNode] = [:]
        var duplicateNames = Set<String>()
        func collect(_ node: SCNNode) {
            if let name = node.name, library.boneNames.contains(name) {
                if nodesByName[name] == nil {
                    nodesByName[name] = node
                } else {
                    duplicateNames.insert(name)
                }
            }
            node.childNodes.forEach(collect)
        }
        collect(root)
        guard duplicateNames.isEmpty else {
            #if DEBUG
            print("TidewayAnimator: duplicate sampled bones \(duplicateNames.sorted())")
            #endif
            return nil
        }
        let bones = library.boneNames.compactMap { nodesByName[$0] }
        guard bones.count == library.boneNames.count else {
            #if DEBUG
            let missing = library.boneNames.filter { nodesByName[$0] == nil }
            print("TidewayAnimator: sampled motion missing bones \(missing)")
            #endif
            return nil
        }
        let indices = Dictionary(
            uniqueKeysWithValues: bones.enumerated().map {
                (ObjectIdentifier($0.element), $0.offset)
            }
        )
        for (boneIndex, bone) in bones.enumerated() {
            var ancestor = bone.parent
            var actualParentIndex = -1
            while let candidate = ancestor {
                if let index = indices[ObjectIdentifier(candidate)] {
                    actualParentIndex = index
                    break
                }
                ancestor = candidate.parent
            }
            guard actualParentIndex == library.parentIndices[boneIndex] else {
                #if DEBUG
                print("TidewayAnimator: parent mismatch for \(library.boneNames[boneIndex])")
                #endif
                return nil
            }
        }
        return bones
    }

    private func makeShowcaseRanges(
        from library: TidewayMotionLibrary?
    ) -> [Motion: ShowcaseRange] {
        guard let library else { return [:] }
        var result: [Motion: ShowcaseRange] = [:]
        for motion in Motion.allCases {
            guard let clip = library.clip(named: motion.rawValue) else { continue }
            let start = TimeInterval(clip.startFrame) / TimeInterval(library.fps)
            let end = TimeInterval(clip.startFrame + clip.frameCount - 1)
                / TimeInterval(library.fps)
            result[motion] = ShowcaseRange(start: start, end: end, loops: clip.loops)
        }
        return result
    }

    private func stepSampledMotion(deltaTime: Float) {
        guard let library = motionLibrary,
              sampledBones.count == library.boneNames.count,
              sampledOutput.count == library.boneNames.count
        else {
            usesSampledMotion = false
            return
        }

        let requestedMode: SampledMode
        switch pose {
        case .sit:
            requestedMode = .sit
        case .walk where locomotionSpeed > 0.035 && !movementBlocked:
            requestedMode = .locomotion
        default:
            if sampledMode == .sit,
               library.firstClip(named: ["StandUp", "SitToIdle"]) != nil {
                requestedMode = .standing
            } else if sampledMode == .standing,
                      let stand = library.firstClip(named: ["StandUp", "SitToIdle"]),
                      sampledModeElapsed < stand.duration(fps: library.fps),
                      pose != .walk {
                requestedMode = .standing
            } else {
                requestedMode = .idle
            }
        }

        if sampledMode != requestedMode {
            let previousMode = sampledMode
            transitionOrigin = sampledOutput
            sampledMode = requestedMode
            sampledModeElapsed = 0
            transitionElapsed = 0
            transitionDuration = movementBlocked ? 0.10 : 0.18
            activeIdleVariant = nil
            idleVariantElapsed = 0
            stateOneShotClip = transitionClip(
                from: previousMode,
                to: requestedMode,
                library: library
            )
            stateOneShotElapsed = 0
            if requestedMode == .idle {
                nextIdleVariantTime = 3.8
            }
        }
        sampledModeElapsed += max(deltaTime, 0)

        if let oneShot = stateOneShotClip {
            stateOneShotElapsed += max(deltaTime, 0)
            let duration = oneShot.duration(fps: library.fps)
            library.sample(
                oneShot,
                phase: min(stateOneShotElapsed / max(duration, 0.001), 1),
                into: &sampledA
            )
            if stateOneShotElapsed >= duration {
                stateOneShotClip = nil
            }
        } else {
            sampleModePose(
                sampledMode ?? .idle,
                library: library,
                deltaTime: deltaTime,
                into: &sampledA
            )
        }

        transitionElapsed += max(deltaTime, 0)
        if transitionElapsed < transitionDuration,
           transitionOrigin.count == sampledA.count {
            let linear = transitionElapsed / max(transitionDuration, 0.001)
            let weight = linear * linear * (3 - 2 * linear)
            blendSampledPose(
                transitionOrigin,
                sampledA,
                weight: weight,
                into: &sampledOutput
            )
        } else {
            sampledOutput = sampledA
        }
        applySampledPose(sampledOutput)
    }

    private func transitionClip(
        from oldMode: SampledMode?,
        to newMode: SampledMode,
        library: TidewayMotionLibrary
    ) -> TidewayMotionLibrary.Clip? {
        switch (oldMode, newMode) {
        case (.idle?, .locomotion):
            return library.firstClip(named: ["IdleToWalk", "WalkStart", "StartWalk"])
        case (.locomotion?, .idle) where !movementBlocked:
            let prefersLeft = locomotionPhase < 0.25 || locomotionPhase >= 0.75
            return library.firstClip(named: prefersLeft
                ? ["WalkStopL", "WalkToIdleL", "WalkStop", "WalkToIdle"]
                : ["WalkStopR", "WalkToIdleR", "WalkStop", "WalkToIdle"])
        case (_, .sit):
            return library.firstClip(named: ["SitDown"])
        case (.sit?, .standing):
            return library.firstClip(named: ["StandUp", "SitToIdle"])
        default:
            return nil
        }
    }

    private func sampleModePose(
        _ mode: SampledMode,
        library: TidewayMotionLibrary,
        deltaTime: Float,
        into output: inout [TidewayJointPose]
    ) {
        switch mode {
        case .idle:
            sampleIdle(library: library, deltaTime: deltaTime, into: &output)
        case .locomotion:
            sampleLocomotion(library: library, deltaTime: deltaTime, into: &output)
        case .sit:
            sampleSit(library: library, into: &output)
        case .standing:
            if let stand = library.firstClip(named: ["StandUp", "SitToIdle"]) {
                library.sample(
                    stand,
                    phase: min(sampledModeElapsed / max(stand.duration(fps: library.fps), 0.001), 1),
                    into: &output
                )
            } else if let idle = library.clip(named: "Idle") {
                library.sample(idle, phase: 0, into: &output)
            }
        }
    }

    private func sampleIdle(
        library: TidewayMotionLibrary,
        deltaTime: Float,
        into output: inout [TidewayJointPose]
    ) {
        guard let idle = library.clip(named: "Idle") else { return }
        if activeIdleVariant == nil, sampledModeElapsed >= nextIdleVariantTime {
            let variants = library.clips.filter {
                $0.normalizedName.hasPrefix("idle")
                    && $0.normalizedName != "idle"
                    && !$0.normalizedName.contains("towalk")
            }
            if !variants.isEmpty {
                activeIdleVariant = variants[idleVariantIndex % variants.count]
                idleVariantIndex += 1
                idleVariantElapsed = 0
            }
            nextIdleVariantTime = sampledModeElapsed + 4.2 + Float(idleVariantIndex % 3)
        }
        if let variant = activeIdleVariant {
            idleVariantElapsed += max(deltaTime, 0)
            let duration = variant.duration(fps: library.fps)
            library.sample(
                variant,
                phase: min(idleVariantElapsed / max(duration, 0.001), 1),
                into: &output
            )
            if idleVariantElapsed >= duration {
                activeIdleVariant = nil
            }
        } else {
            library.sample(
                idle,
                phase: sampledModeElapsed / max(idle.duration(fps: library.fps), 0.001),
                into: &output
            )
        }
    }

    private func sampleLocomotion(
        library: TidewayMotionLibrary,
        deltaTime: Float,
        into output: inout [TidewayJointPose]
    ) {
        guard let walk = library.clip(named: "Walk"),
              let run = library.clip(named: "Run")
        else { return }
        let speed = max(locomotionSpeed, 0)
        let lowerBlendSpeed = library.walkGroundSpeed * 1.20
        let upperBlendSpeed = max(
            lowerBlendSpeed + 0.1,
            library.runGroundSpeed * 0.90
        )
        let linearRunWeight = min(
            max((speed - lowerBlendSpeed) / (upperBlendSpeed - lowerBlendSpeed), 0),
            1
        )
        let runWeight = linearRunWeight * linearRunWeight * (3 - 2 * linearRunWeight)
        let walkStrideDistance = library.walkGroundSpeed * walk.duration(fps: library.fps)
        let runStrideDistance = library.runGroundSpeed * run.duration(fps: library.fps)
        let strideDistance = walkStrideDistance
            + (runStrideDistance - walkStrideDistance) * runWeight
        if strideDistance > 0.001 {
            locomotionPhase += speed * max(deltaTime, 0) / strideDistance
            locomotionPhase -= floor(locomotionPhase)
        }
        library.sample(walk, phase: locomotionPhase, into: &output)
        library.sample(run, phase: locomotionPhase, into: &sampledB)
        blendSampledPoseInPlace(&output, with: sampledB, weight: runWeight)

        let turnWeight = min(abs(yawRate) / 4.5, 1) * 0.55
        if turnWeight > 0.01 {
            let names: [String]
            if yawRate >= 0 {
                names = runWeight > 0.55
                    ? ["RunTurnLeft", "WalkTurnLeft", "TurnLeft"]
                    : ["WalkTurnLeft", "RunTurnLeft", "TurnLeft"]
            } else {
                names = runWeight > 0.55
                    ? ["RunTurnRight", "WalkTurnRight", "TurnRight"]
                    : ["WalkTurnRight", "RunTurnRight", "TurnRight"]
            }
            if let turn = library.firstClip(named: names) {
                library.sample(turn, phase: locomotionPhase, into: &sampledB)
                blendSampledPoseInPlace(&output, with: sampledB, weight: turnWeight)
            }
        }
    }

    private func sampleSit(
        library: TidewayMotionLibrary,
        into output: inout [TidewayJointPose]
    ) {
        let sitDown = library.firstClip(named: ["SitDown", "Sit"])
        guard let sitDown else { return }
        let downDuration = sitDown.duration(fps: library.fps)
        if sampledModeElapsed < downDuration {
            library.sample(
                sitDown,
                phase: sampledModeElapsed / max(downDuration, 0.001),
                into: &output
            )
        } else if let sitIdle = library.firstClip(named: ["SitIdle", "IdleSit"]) {
            library.sample(
                sitIdle,
                phase: (sampledModeElapsed - downDuration)
                    / max(sitIdle.duration(fps: library.fps), 0.001),
                into: &output
            )
        } else {
            library.sample(sitDown, phase: 1, into: &output)
        }
    }

    private func blendSampledPose(
        _ lhs: [TidewayJointPose],
        _ rhs: [TidewayJointPose],
        weight: Float,
        into output: inout [TidewayJointPose]
    ) {
        guard lhs.count == rhs.count, output.count == lhs.count else { return }
        for index in lhs.indices {
            output[index] = TidewayJointPose.interpolate(
                lhs[index],
                rhs[index],
                fraction: weight
            )
        }
    }

    private func blendSampledPoseInPlace(
        _ output: inout [TidewayJointPose],
        with rhs: [TidewayJointPose],
        weight: Float
    ) {
        guard output.count == rhs.count else { return }
        for index in output.indices {
            output[index] = TidewayJointPose.interpolate(
                output[index],
                rhs[index],
                fraction: weight
            )
        }
    }

    private func applySampledPose(_ jointPoses: [TidewayJointPose]) {
        guard jointPoses.count == sampledBones.count else { return }
        for (jointPose, bone) in zip(jointPoses, sampledBones) {
            bone.simdPosition = jointPose.position
            bone.simdOrientation = jointPose.orientation
            bone.simdScale = jointPose.scale
        }
    }

    private func collectClipPlayers(from root: SCNNode) -> [Motion: [SCNAnimationPlayer]] {
        var result: [Motion: [SCNAnimationPlayer]] = [:]

        func collect(_ node: SCNNode) {
            for key in node.animationKeys {
                guard let player = node.animationPlayer(forKey: key) else { continue }
                let identifier = "\(key) \(node.name ?? "")".lowercased()
                guard let motion = Motion.allCases.first(where: {
                    identifier.contains($0.rawValue)
                }) else { continue }
                player.animation.blendInDuration = 0.18
                player.animation.blendOutDuration = 0.18
                player.animation.repeatCount = CGFloat.greatestFiniteMagnitude
                result[motion, default: []].append(player)
            }
            node.childNodes.forEach(collect)
        }
        collect(root)
        return result
    }

    /// Accept a concatenated player only when its generated motion contract
    /// covers exactly the same timeline. Clip offsets never live in Swift.
    private func findValidatedShowcasePlayer(
        in root: SCNNode,
        ranges: [Motion: ShowcaseRange]
    ) -> SCNAnimationPlayer? {
        var candidates: [SCNAnimationPlayer] = []

        func collect(_ node: SCNNode) {
            for key in node.animationKeys where key.lowercased().contains("showcase") {
                if let player = node.animationPlayer(forKey: key) {
                    candidates.append(player)
                }
            }
            node.childNodes.forEach(collect)
        }
        collect(root)

        guard candidates.count == 1,
              let player = candidates.first,
              let expectedDuration = ranges.values.map(\.end).max()
        else { return nil }
        guard abs(player.animation.duration - expectedDuration) <= 0.06 else {
            #if DEBUG
            print(
                "TidewayAnimator: unexpected Showcase duration "
                    + "\(player.animation.duration); using procedural animation"
            )
            #endif
            return nil
        }
        return player
    }

    private func stopAllAnimations(in root: SCNNode) {
        for key in root.animationKeys {
            root.animationPlayer(forKey: key)?.stop()
        }
        root.childNodes.forEach(stopAllAnimations)
    }

    private func removeAllAnimations(in root: SCNNode) {
        root.removeAllAnimations()
        root.childNodes.forEach(removeAllAnimations)
    }

    private func transitionToImportedClipIfNeeded(_ motion: Motion, deltaTime: Float) {
        if activeMotion != motion {
            if let activeMotion {
                for player in clipPlayers[activeMotion] ?? [] {
                    player.stop(withBlendOutDuration: 0.18)
                }
            }
            for player in clipPlayers[motion] ?? [] {
                player.speed = CGFloat(playbackRate(for: motion))
                player.play()
            }
            activeMotion = motion
        }
        for player in clipPlayers[motion] ?? [] {
            player.speed = CGFloat(playbackRate(for: motion))
        }
    }

    private func stepShowcaseAnimation(motion requestedMotion: Motion, deltaTime: Float) {
        guard let player = showcasePlayer else {
            usesShowcaseAnimation = false
            return
        }
        if !showcaseStarted {
            showcaseStarted = true
            activeMotion = requestedMotion
            pendingMotion = nil
            showcasePhase = 0
            showcaseBlend = 0
            player.speed = 0
            player.play()
        }

        if requestedMotion == activeMotion {
            pendingMotion = nil
        } else {
            pendingMotion = requestedMotion
        }

        // Fade through the authored neutral pose before jumping between ranges
        // on the one skeleton-bound player. `blendFactor` is intentionally used
        // instead of copying the player: copied USD SkelAnimations lose their
        // binding on current SceneKit releases.
        // A complete fade-out/fade-in transition is about 0.18 seconds.
        let blendStep = CGFloat(max(deltaTime, 0)) * 11
        if pendingMotion != nil {
            showcaseBlend = max(0, showcaseBlend - blendStep)
            if showcaseBlend <= 0.001, let next = pendingMotion {
                activeMotion = next
                pendingMotion = nil
                showcasePhase = 0
            }
        } else {
            showcaseBlend = min(1, showcaseBlend + blendStep)
        }
        player.blendFactor = showcaseBlend

        guard let activeMotion,
              let range = showcaseRanges[activeMotion]
        else { return }
        showcasePhase += TimeInterval(max(deltaTime, 0) * playbackRate(for: activeMotion))
        if range.loops {
            showcasePhase.formTruncatingRemainder(dividingBy: range.duration)
        } else {
            showcasePhase = min(showcasePhase, range.duration)
        }
        player.animation.timeOffset = range.start + showcasePhase
    }

    private func playbackRate(for motion: Motion) -> Float {
        switch motion {
        case .idle:
            return 1
        case .walk:
            guard locomotionSpeed > 0.05 else { return 1 }
            let groundSpeed = motionLibrary?.walkGroundSpeed ?? 1
            return min(max(locomotionSpeed / groundSpeed, 0.62), 1.75)
        case .run:
            guard locomotionSpeed > 0.05 else { return 1 }
            let groundSpeed = motionLibrary?.runGroundSpeed ?? 1.6
            return min(max(locomotionSpeed / groundSpeed, 0.78), 1.45)
        case .sit:
            // The authored two-second settle reaches the seat during the
            // existing Home Island contact transition without feeling heavy.
            return 1.85
        }
    }

    private func stepProceduralAnimation(
        time: Float,
        deltaTime: Float,
        motion: Motion
    ) {
        let response = 1 - exp(-10 * max(deltaTime, 0))
        let isLocomoting = motion == .walk || motion == .run
        walkWeight += ((isLocomoting ? 1 : 0) - walkWeight) * response
        sitWeight += ((motion == .sit ? 1 : 0) - sitWeight) * response

        let strideRate: Float = motion == .run ? 9.2 : 6.4
        let stride = sin(time * strideRate)
        let stepLift = abs(cos(time * strideRate))
        let breath = sin(time * 1.7)

        apply("contact", positionY: sitWeight * 0.08)
        apply(
            "core",
            positionY: breath * 0.012 * (1 - walkWeight)
                + stepLift * 0.025 * walkWeight
                - sitWeight * 0.20,
            rotationX: walkWeight * 0.06,
            rotationZ: stride * 0.025 * walkWeight
        )
        apply(
            "head",
            rotationX: -walkWeight * 0.025 - sitWeight * 0.05,
            rotationY: breath * 0.035 * (1 - walkWeight),
            rotationZ: -stride * 0.018 * walkWeight
        )

        let armSwing = stride * 0.48 * walkWeight
        apply(
            "armL",
            rotationX: armSwing + sitWeight * 0.45,
            rotationZ: -sitWeight * 0.18
        )
        apply(
            "armR",
            rotationX: -armSwing + sitWeight * 0.45,
            rotationZ: sitWeight * 0.18
        )
        apply(
            "forearmL",
            rotationX: -abs(stride) * 0.10 * walkWeight - sitWeight * 0.36
        )
        apply(
            "forearmR",
            rotationX: -abs(stride) * 0.10 * walkWeight - sitWeight * 0.36
        )

        let legSwing = stride * 0.62 * walkWeight
        apply("legL", rotationX: -legSwing - sitWeight * 0.98)
        apply("legR", rotationX: legSwing - sitWeight * 0.98)
        apply(
            "kneeL",
            rotationX: max(0, legSwing) * 0.34 + sitWeight * 1.05
        )
        apply(
            "kneeR",
            rotationX: max(0, -legSwing) * 0.34 + sitWeight * 1.05
        )

        apply(
            "cape",
            rotationX: -walkWeight * 0.12 + sin(time * 2.4) * 0.025,
            rotationZ: stride * 0.035 * walkWeight
        )
        apply(
            "lantern",
            rotationX: -armSwing * 0.42 + sin(time * 1.9) * 0.035,
            rotationZ: sin(time * 1.3 + 0.7) * 0.035
        )
    }

    private func apply(
        _ name: String,
        positionY: Float = 0,
        rotationX: Float = 0,
        rotationY: Float = 0,
        rotationZ: Float = 0
    ) {
        guard let node = rigNodes[name], let rest = restTransforms[name] else { return }
        node.position = SCNVector3(
            rest.position.x,
            rest.position.y + positionY,
            rest.position.z
        )
        node.eulerAngles = SCNVector3(
            rest.eulerAngles.x + rotationX,
            rest.eulerAngles.y + rotationY,
            rest.eulerAngles.z + rotationZ
        )
        node.scale = rest.scale
    }
}
