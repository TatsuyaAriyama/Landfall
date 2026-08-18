import CryptoKit
import Foundation
import Metal
import SceneKit
import simd

// Build after Blender has exported the USDZ:
//
// xcrun swiftc Tools/RenderHarness/TidewayMotionCompiler.swift \
//   -o /tmp/tideway-motion-compiler \
//   -framework SceneKit -framework Metal -framework CryptoKit
// /tmp/tideway-motion-compiler \
//   Assets3D/archive/tideway_navigator/tideway_navigator.usdz \
//   Assets3D/source/tideway_navigator.motion.json \
//   Assets3D/archive/tideway_navigator/tideway_navigator.twmotion

private enum MotionFormat {
    static let magic = Data("TWMOTN03".utf8)
    static let schemaVersion: UInt16 = 3
    static let maxBones = 64
    static let maxFrames = 4_096
}

private struct Manifest: Decodable {
    struct Clip: Decodable {
        let name: String
        /// One-based, inclusive Blender/Showcase frame.
        let startFrame: Int
        /// One-based, inclusive Blender/Showcase frame. Loop endpoints must
        /// duplicate their first pose exactly.
        let endFrame: Int
        let loop: Bool
        let authoredSpeed: Float?
    }

    let schemaVersion: Int
    let assetVersion: Int
    let fps: Int
    let authoredHeight: Float
    let sitSurfaceHeight: Float
    let walkGroundSpeed: Float
    let runGroundSpeed: Float
    let rootMotion: Bool
    let frontAxis: String
    let clips: [Clip]
}

private struct JointPose {
    let position: SIMD3<Float>
    let orientation: simd_quatf
    let scale: SIMD3<Float>
}

private struct ImportedRig {
    let root: SCNNode
    let player: SCNAnimationPlayer
    let bones: [SCNNode]
    let parentIndices: [Int16]
}

private extension Data {
    mutating func appendInteger<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendFloat(_ value: Float) {
        appendInteger(value.bitPattern)
    }

    mutating func appendString(_ value: String) throws {
        let bytes = Data(value.utf8)
        guard bytes.count <= Int(UInt16.max) else {
            throw CompilerError.invalidManifest("string is too long: \(value.prefix(32))")
        }
        appendInteger(UInt16(bytes.count))
        append(bytes)
    }
}

private enum CompilerError: LocalizedError {
    case invalidArguments
    case invalidManifest(String)
    case invalidAsset(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "usage: TidewayMotionCompiler asset.usdz manifest.json output.twmotion"
        case let .invalidManifest(reason):
            return "invalid Tideway motion manifest: \(reason)"
        case let .invalidAsset(reason):
            return "invalid Tideway SceneKit asset: \(reason)"
        }
    }
}

private func findShowcasePlayer(in root: SCNNode) -> SCNAnimationPlayer? {
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
    return candidates.count == 1 ? candidates[0] : nil
}

private func stopAnimations(in root: SCNNode) {
    for key in root.animationKeys {
        root.animationPlayer(forKey: key)?.stop()
    }
    root.childNodes.forEach(stopAnimations)
}

private func canonicalSkinBones(in root: SCNNode) throws -> [SCNNode] {
    var boneLists: [[SCNNode]] = []
    root.enumerateChildNodes { node, _ in
        if let bones = node.skinner?.bones, !bones.isEmpty {
            boneLists.append(bones)
        }
    }
    guard let canonical = boneLists.first, !canonical.isEmpty else {
        throw CompilerError.invalidAsset("no SCNSkinner bones")
    }
    let names = canonical.map { $0.name ?? "" }
    guard names.allSatisfy({ !$0.isEmpty }), Set(names).count == names.count else {
        throw CompilerError.invalidAsset("skin bone names must be non-empty and unique")
    }
    for bones in boneLists.dropFirst() where bones.map({ $0.name ?? "" }) != names {
        throw CompilerError.invalidAsset("skinners do not share one canonical bone order")
    }
    return canonical
}

private func parentIndices(for bones: [SCNNode]) throws -> [Int16] {
    let indices = Dictionary(
        uniqueKeysWithValues: bones.enumerated().map { (ObjectIdentifier($0.element), $0.offset) }
    )
    return try bones.map { bone in
        var ancestor = bone.parent
        while let candidate = ancestor {
            if let index = indices[ObjectIdentifier(candidate)] {
                guard index <= Int(Int16.max) else {
                    throw CompilerError.invalidAsset("bone parent index overflow")
                }
                return Int16(index)
            }
            ancestor = candidate.parent
        }
        return -1
    }
}

private func loadRig(from url: URL) throws -> ImportedRig {
    guard let reference = SCNReferenceNode(url: url) else {
        throw CompilerError.invalidAsset("SCNReferenceNode rejected \(url.lastPathComponent)")
    }
    reference.load()
    guard let player = findShowcasePlayer(in: reference) else {
        throw CompilerError.invalidAsset("expected exactly one animation key containing Showcase")
    }
    let bones = try canonicalSkinBones(in: reference)
    let parents = try parentIndices(for: bones)
    stopAnimations(in: reference)
    player.speed = 0
    player.blendFactor = 1
    player.animation.repeatCount = .greatestFiniteMagnitude
    player.play()
    return ImportedRig(root: reference, player: player, bones: bones, parentIndices: parents)
}

private func validate(_ manifest: Manifest, rig: ImportedRig) throws {
    guard manifest.schemaVersion == Int(MotionFormat.schemaVersion) else {
        throw CompilerError.invalidManifest("schemaVersion must be \(MotionFormat.schemaVersion)")
    }
    guard (1...120).contains(manifest.fps) else {
        throw CompilerError.invalidManifest("fps must be 1...120")
    }
    guard manifest.rootMotion == false else {
        throw CompilerError.invalidManifest("rootMotion must be false")
    }
    guard manifest.frontAxis == "+Z" else {
        throw CompilerError.invalidManifest("SceneKit frontAxis must be +Z")
    }
    guard manifest.authoredHeight.isFinite, manifest.authoredHeight > 0.1,
          manifest.sitSurfaceHeight.isFinite, manifest.sitSurfaceHeight > 0,
          manifest.walkGroundSpeed.isFinite, manifest.walkGroundSpeed > 0,
          manifest.runGroundSpeed.isFinite,
          manifest.runGroundSpeed > manifest.walkGroundSpeed
    else {
        throw CompilerError.invalidManifest("invalid authored dimensions or locomotion speeds")
    }
    guard !manifest.clips.isEmpty else {
        throw CompilerError.invalidManifest("clips cannot be empty")
    }
    let normalizedNames = manifest.clips.map { $0.name.lowercased() }
    guard Set(normalizedNames).count == normalizedNames.count else {
        throw CompilerError.invalidManifest("clip names must be unique")
    }
    for required in ["idle", "walk", "run", "sit"] where !normalizedNames.contains(required) {
        throw CompilerError.invalidManifest("missing required clip \(required)")
    }
    let lastFrame = manifest.clips.map(\.endFrame).max() ?? 0
    guard lastFrame <= MotionFormat.maxFrames,
          manifest.clips.allSatisfy({ $0.startFrame >= 1 && $0.endFrame > $0.startFrame })
    else {
        throw CompilerError.invalidManifest("invalid clip frame range")
    }
    let expectedDuration = TimeInterval(lastFrame - 1) / TimeInterval(manifest.fps)
    guard abs(rig.player.animation.duration - expectedDuration) <= 1.5 / Double(manifest.fps) else {
        throw CompilerError.invalidAsset(
            "Showcase duration \(rig.player.animation.duration) does not cover manifest frame \(lastFrame)"
        )
    }
    guard rig.bones.count <= MotionFormat.maxBones else {
        throw CompilerError.invalidAsset("bone budget exceeded: \(rig.bones.count)")
    }

    let bounds = rig.root.boundingBox
    let sceneKitHeight = Float(bounds.max.y - bounds.min.y)
    let heightError = abs(sceneKitHeight - manifest.authoredHeight) / manifest.authoredHeight
    guard sceneKitHeight.isFinite, heightError <= 0.02 else {
        throw CompilerError.invalidAsset(
            "authoredHeight mismatch: manifest \(manifest.authoredHeight), SceneKit \(sceneKitHeight)"
        )
    }
}

private func samplePose(_ node: SCNNode) -> JointPose {
    let presentation = node.presentation
    return JointPose(
        position: presentation.simdPosition,
        orientation: simd_normalize(presentation.simdOrientation),
        scale: presentation.simdScale
    )
}

private func maxDifference(_ lhs: JointPose, _ rhs: JointPose) -> Float {
    let position = simd_length(lhs.position - rhs.position)
    let scale = simd_length(lhs.scale - rhs.scale)
    let orientation = 1 - abs(simd_dot(lhs.orientation.vector, rhs.orientation.vector))
    return max(position, scale, orientation)
}

private func sample(
    manifest: Manifest,
    rig: ImportedRig
) throws -> [[JointPose]] {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw CompilerError.invalidAsset("Metal device unavailable")
    }
    let scene = SCNScene()
    scene.rootNode.addChildNode(rig.root)
    let cameraNode = SCNNode()
    cameraNode.camera = SCNCamera()
    cameraNode.position = SCNVector3(0, 1, 4)
    scene.rootNode.addChildNode(cameraNode)
    let renderer = SCNRenderer(device: device)
    renderer.scene = scene
    renderer.pointOfView = cameraNode

    let frameCount = manifest.clips.map(\.endFrame).max() ?? 0
    var frames: [[JointPose]] = []
    frames.reserveCapacity(frameCount)
    for frame in 1...frameCount {
        rig.player.animation.timeOffset = TimeInterval(frame - 1) / TimeInterval(manifest.fps)
        _ = renderer.snapshot(
            atTime: TimeInterval(frame) / 60,
            with: CGSize(width: 1, height: 1),
            antialiasingMode: .none
        )
        frames.append(rig.bones.map(samplePose))
    }

    for clip in manifest.clips where clip.loop {
        let first = frames[clip.startFrame - 1]
        let last = frames[clip.endFrame - 1]
        let difference = zip(first, last).map(maxDifference).max() ?? 0
        guard difference <= 0.0002 else {
            throw CompilerError.invalidAsset(
                "loop \(clip.name) endpoints differ by \(difference); duplicate the first pose at the end"
            )
        }
    }

    for rootName in ["root", "contact"] {
        guard let index = rig.bones.firstIndex(where: { $0.name?.lowercased() == rootName }) else {
            throw CompilerError.invalidAsset("missing root-motion guard bone \(rootName)")
        }
        let reference = frames[0][index]
        let drift = frames.map { maxDifference(reference, $0[index]) }.max() ?? 0
        guard drift <= 0.0002 else {
            throw CompilerError.invalidAsset("root motion detected on \(rootName): \(drift)")
        }
    }
    return frames
}

private func encode(
    manifest: Manifest,
    assetHash: Data,
    rig: ImportedRig,
    frames: [[JointPose]]
) throws -> Data {
    guard assetHash.count == SHA256.byteCount else {
        throw CompilerError.invalidAsset("unexpected SHA-256 size")
    }
    var data = Data()
    data.append(MotionFormat.magic)
    data.appendInteger(MotionFormat.schemaVersion)
    data.appendInteger(UInt16(manifest.assetVersion))
    data.appendInteger(UInt16(manifest.fps))
    data.appendInteger(UInt16(rig.bones.count))
    data.appendInteger(UInt16(manifest.clips.count))
    data.appendInteger(UInt16(0))
    data.appendInteger(UInt32(frames.count))
    data.appendFloat(manifest.authoredHeight)
    data.appendFloat(manifest.sitSurfaceHeight)
    data.appendFloat(manifest.walkGroundSpeed)
    data.appendFloat(manifest.runGroundSpeed)
    data.append(assetHash)

    for (bone, parentIndex) in zip(rig.bones, rig.parentIndices) {
        try data.appendString(bone.name ?? "")
        data.appendInteger(parentIndex)
    }
    for clip in manifest.clips {
        try data.appendString(clip.name)
        data.appendInteger(UInt32(clip.startFrame - 1))
        data.appendInteger(UInt32(clip.endFrame - clip.startFrame + 1))
        data.appendInteger(UInt16(clip.loop ? 1 : 0))
        data.appendInteger(UInt16(0))
        data.appendFloat(clip.authoredSpeed ?? 0)
    }
    for frame in frames {
        for pose in frame {
            data.appendFloat(pose.position.x)
            data.appendFloat(pose.position.y)
            data.appendFloat(pose.position.z)
            data.appendFloat(pose.orientation.imag.x)
            data.appendFloat(pose.orientation.imag.y)
            data.appendFloat(pose.orientation.imag.z)
            data.appendFloat(pose.orientation.real)
            data.appendFloat(pose.scale.x)
            data.appendFloat(pose.scale.y)
            data.appendFloat(pose.scale.z)
        }
    }
    return data
}

private func run() throws {
    guard CommandLine.arguments.count == 4 else { throw CompilerError.invalidArguments }
    let assetURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let manifestURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])
    let manifest = try JSONDecoder().decode(
        Manifest.self,
        from: Data(contentsOf: manifestURL)
    )
    let rig = try loadRig(from: assetURL)
    try validate(manifest, rig: rig)
    let frames = try sample(manifest: manifest, rig: rig)
    let assetData = try Data(contentsOf: assetURL)
    let assetHash = Data(SHA256.hash(data: assetData))
    let encoded = try encode(
        manifest: manifest,
        assetHash: assetHash,
        rig: rig,
        frames: frames
    )
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try encoded.write(to: outputURL, options: .atomic)
    print("TIDEWAY_MOTION_OUTPUT=\(outputURL.path)")
    print("TIDEWAY_ASSET_SHA256=\(assetHash.map { String(format: "%02x", $0) }.joined())")
    print("TIDEWAY_MOTION_BONES=\(rig.bones.count)")
    print("TIDEWAY_MOTION_FRAMES=\(frames.count)")
    print("TIDEWAY_MOTION_BYTES=\(encoded.count)")
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
