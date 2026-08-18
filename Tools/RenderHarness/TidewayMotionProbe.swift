import AppKit
import CryptoKit
import Metal
import SceneKit
import simd

struct PackedTransform: Codable {
    let px: Float
    let py: Float
    let pz: Float
    let qx: Float
    let qy: Float
    let qz: Float
    let qw: Float
    let sx: Float
    let sy: Float
    let sz: Float
}

struct PackedClip: Codable {
    let name: String
    let startFrame: Int
    let endFrame: Int
    let loops: Bool
    let authoredSpeed: Float?
}

struct MotionArchive: Codable {
    let magic: String
    let version: Int
    let assetSHA256: String
    let fps: Int
    let boneNames: [String]
    let clips: [PackedClip]
    let frames: [[PackedTransform]]
}

struct ImportedCharacter {
    let node: SCNNode
    let player: SCNAnimationPlayer
    let bones: [SCNNode]
}

private func findShowcasePlayer(in root: SCNNode) -> SCNAnimationPlayer? {
    for key in root.animationKeys where key.lowercased().contains("showcase") {
        if let player = root.animationPlayer(forKey: key) {
            return player
        }
    }
    for child in root.childNodes {
        if let player = findShowcasePlayer(in: child) {
            return player
        }
    }
    return nil
}

private func stopAnimations(in root: SCNNode, remove: Bool) {
    for key in root.animationKeys {
        if remove {
            root.removeAnimation(forKey: key)
        } else {
            root.animationPlayer(forKey: key)?.stop()
        }
    }
    root.childNodes.forEach { stopAnimations(in: $0, remove: remove) }
}

private func skinBones(in root: SCNNode) throws -> [SCNNode] {
    var canonical: [SCNNode]?
    root.enumerateChildNodes { node, _ in
        guard let bones = node.skinner?.bones, !bones.isEmpty else { return }
        if canonical == nil {
            canonical = bones
        }
    }
    guard let bones = canonical, !bones.isEmpty else {
        throw NSError(domain: "TidewayMotionProbe", code: 3)
    }
    guard bones.allSatisfy({ !($0.name ?? "").isEmpty }) else {
        throw NSError(domain: "TidewayMotionProbe", code: 4)
    }
    return bones
}

private func makeCharacter(url: URL, removeAnimation: Bool) throws -> ImportedCharacter {
    guard let reference = SCNReferenceNode(url: url) else {
        throw NSError(domain: "TidewayMotionProbe", code: 1)
    }
    reference.load()
    guard let player = findShowcasePlayer(in: reference) else {
        throw NSError(domain: "TidewayMotionProbe", code: 2)
    }
    let bones = try skinBones(in: reference)
    stopAnimations(in: reference, remove: removeAnimation)
    if !removeAnimation {
        player.speed = 0
        player.blendFactor = 1
        player.animation.repeatCount = .greatestFiniteMagnitude
        player.play()
    }

    let bounds = reference.boundingBox
    let height = bounds.max.y - bounds.min.y
    let scale = 1.35 / height
    let normalization = SCNNode()
    normalization.scale = SCNVector3(scale, scale, scale)
    normalization.position.y = -bounds.min.y * scale
    normalization.addChildNode(reference)
    return ImportedCharacter(node: normalization, player: player, bones: bones)
}

private func pack(_ node: SCNNode) -> PackedTransform {
    let presentation = node.presentation
    let position = presentation.simdPosition
    let orientation = presentation.simdOrientation
    let scale = presentation.simdScale
    return PackedTransform(
        px: position.x, py: position.y, pz: position.z,
        qx: orientation.imag.x, qy: orientation.imag.y,
        qz: orientation.imag.z, qw: orientation.real,
        sx: scale.x, sy: scale.y, sz: scale.z
    )
}

private func interpolate(
    _ lhs: PackedTransform,
    _ rhs: PackedTransform,
    fraction: Float
) -> PackedTransform {
    let position = simd_mix(
        SIMD3<Float>(lhs.px, lhs.py, lhs.pz),
        SIMD3<Float>(rhs.px, rhs.py, rhs.pz),
        SIMD3<Float>(repeating: fraction)
    )
    let scale = simd_mix(
        SIMD3<Float>(lhs.sx, lhs.sy, lhs.sz),
        SIMD3<Float>(rhs.sx, rhs.sy, rhs.sz),
        SIMD3<Float>(repeating: fraction)
    )
    let leftOrientation = simd_normalize(
        simd_quatf(ix: lhs.qx, iy: lhs.qy, iz: lhs.qz, r: lhs.qw)
    )
    var rightOrientation = simd_normalize(
        simd_quatf(ix: rhs.qx, iy: rhs.qy, iz: rhs.qz, r: rhs.qw)
    )
    if simd_dot(leftOrientation.vector, rightOrientation.vector) < 0 {
        rightOrientation = simd_quatf(vector: -rightOrientation.vector)
    }
    let orientation = simd_slerp(leftOrientation, rightOrientation, fraction)
    return PackedTransform(
        px: position.x, py: position.y, pz: position.z,
        qx: orientation.imag.x, qy: orientation.imag.y,
        qz: orientation.imag.z, qw: orientation.real,
        sx: scale.x, sy: scale.y, sz: scale.z
    )
}

private func apply(_ transforms: [PackedTransform], to bones: [SCNNode]) {
    precondition(transforms.count == bones.count)
    for (transform, bone) in zip(transforms, bones) {
        bone.simdPosition = SIMD3<Float>(transform.px, transform.py, transform.pz)
        bone.simdOrientation = simd_normalize(
            simd_quatf(
                ix: transform.qx,
                iy: transform.qy,
                iz: transform.qz,
                r: transform.qw
            )
        )
        bone.simdScale = SIMD3<Float>(transform.sx, transform.sy, transform.sz)
    }
}

private func addStage(to scene: SCNScene) -> SCNNode {
    let floor = SCNFloor()
    floor.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.82, green: 0.88, blue: 0.84, alpha: 1)
    floor.firstMaterial?.roughness.contents = 0.9
    scene.rootNode.addChildNode(SCNNode(geometry: floor))

    let key = SCNLight()
    key.type = .directional
    key.intensity = 1_000
    key.color = NSColor(calibratedRed: 1, green: 0.92, blue: 0.80, alpha: 1)
    let keyNode = SCNNode()
    keyNode.light = key
    keyNode.eulerAngles = SCNVector3(-0.72, -0.58, 0)
    scene.rootNode.addChildNode(keyNode)

    let ambient = SCNLight()
    ambient.type = .ambient
    ambient.intensity = 360
    ambient.color = NSColor(calibratedRed: 0.72, green: 0.84, blue: 0.90, alpha: 1)
    let ambientNode = SCNNode()
    ambientNode.light = ambient
    scene.rootNode.addChildNode(ambientNode)

    let target = SCNNode()
    target.position = SCNVector3(0, 0.72, 0)
    scene.rootNode.addChildNode(target)
    let camera = SCNCamera()
    camera.fieldOfView = 34
    camera.zNear = 0.01
    camera.zFar = 100
    let cameraNode = SCNNode()
    cameraNode.camera = camera
    cameraNode.position = SCNVector3(2.15, 1.28, 3.25)
    let constraint = SCNLookAtConstraint(target: target)
    constraint.isGimbalLockEnabled = true
    cameraNode.constraints = [constraint]
    scene.rootNode.addChildNode(cameraNode)
    return cameraNode
}

private func write(_ image: NSImage, to url: URL) throws {
    guard let data = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: data),
          let png = bitmap.representation(using: .png, properties: [:])
    else { throw NSError(domain: "TidewayMotionProbe", code: 5) }
    try png.write(to: url, options: .atomic)
}

guard CommandLine.arguments.count == 3 else {
    fatalError("usage: TidewayMotionProbe asset.usdz output-directory")
}
let assetURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let sourceScene = SCNScene()
let sourceCamera = addStage(to: sourceScene)
let source = try makeCharacter(url: assetURL, removeAnimation: false)
sourceScene.rootNode.addChildNode(source.node)
guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal unavailable") }
let sourceRenderer = SCNRenderer(device: device)
sourceRenderer.scene = sourceScene
sourceRenderer.pointOfView = sourceCamera

var sampledFrames: [[PackedTransform]] = []
for frame in 1...282 {
    source.player.animation.timeOffset = TimeInterval(frame - 1) / 24
    _ = sourceRenderer.snapshot(
        atTime: TimeInterval(frame) / 60,
        with: CGSize(width: 16, height: 16),
        antialiasingMode: .none
    )
    sampledFrames.append(source.bones.map(pack))
}

let assetData = try Data(contentsOf: assetURL)
let archive = MotionArchive(
    magic: "TWMOTION",
    version: 1,
    assetSHA256: SHA256.hash(data: assetData).map { String(format: "%02x", $0) }.joined(),
    fps: 24,
    boneNames: source.bones.map { $0.name! },
    clips: [
        PackedClip(name: "Idle", startFrame: 1, endFrame: 96, loops: true, authoredSpeed: nil),
        PackedClip(name: "Walk", startFrame: 106, endFrame: 130, loops: true, authoredSpeed: 0.87),
        PackedClip(name: "Run", startFrame: 140, endFrame: 156, loops: true, authoredSpeed: 1.77),
        PackedClip(name: "Wave", startFrame: 166, endFrame: 225, loops: false, authoredSpeed: nil),
        PackedClip(name: "Sit", startFrame: 235, endFrame: 282, loops: false, authoredSpeed: nil),
    ],
    frames: sampledFrames
)
let encoder = PropertyListEncoder()
encoder.outputFormat = .binary
let encoded = try encoder.encode(archive)
let motionURL = outputURL.appendingPathComponent("tideway-v2.twmotion")
try encoded.write(to: motionURL, options: .atomic)
let decoded = try PropertyListDecoder().decode(MotionArchive.self, from: Data(contentsOf: motionURL))
precondition(decoded.assetSHA256 == archive.assetSHA256)
precondition(decoded.boneNames == archive.boneNames)

let targetScene = SCNScene()
targetScene.background.contents = NSColor(calibratedRed: 0.76, green: 0.86, blue: 0.83, alpha: 1)
let targetCamera = addStage(to: targetScene)
let target = try makeCharacter(url: assetURL, removeAnimation: true)
precondition(target.bones.map { $0.name! } == decoded.boneNames)
targetScene.rootNode.addChildNode(target.node)
let targetRenderer = SCNRenderer(device: device)
targetRenderer.scene = targetScene
targetRenderer.pointOfView = targetCamera

// Quarter-cycle poses are intentionally different enough that a valid result
// visibly proves rotation/translation interpolation while remaining one fully
// opaque, single-skinned character.
let walkFrame = decoded.frames[111]
let runFrame = decoded.frames[143]
let fractions: [Float] = [0, 0.25, 0.5, 0.75, 1]
for (index, fraction) in fractions.enumerated() {
    let pose = zip(walkFrame, runFrame).map {
        interpolate($0.0, $0.1, fraction: fraction)
    }
    apply(pose, to: target.bones)
    let image = targetRenderer.snapshot(
        atTime: 1 + TimeInterval(index) / 60,
        with: CGSize(width: 720, height: 720),
        antialiasingMode: .multisampling4X
    )
    try write(image, to: outputURL.appendingPathComponent(String(format: "bone-blend-%02d.png", index)))
}

let benchmarkIterations = 10_000
let benchmarkStart = CFAbsoluteTimeGetCurrent()
for index in 0..<benchmarkIterations {
    let fraction = Float(index % 101) / 100
    let pose = zip(walkFrame, runFrame).map {
        interpolate($0.0, $0.1, fraction: fraction)
    }
    apply(pose, to: target.bones)
}
let benchmarkDuration = CFAbsoluteTimeGetCurrent() - benchmarkStart
let microsecondsPerPose = benchmarkDuration * 1_000_000 / Double(benchmarkIterations)
print("motion_file=\(motionURL.path)")
print("asset_sha256=\(archive.assetSHA256)")
print("bones=\(archive.boneNames.count) frames=\(archive.frames.count) bytes=\(encoded.count)")
print(String(format: "pose_blend_apply_us=%.3f", microsecondsPerPose))
print("proof_output=\(outputURL.path)")
