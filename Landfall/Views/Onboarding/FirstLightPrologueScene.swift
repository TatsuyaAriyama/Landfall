import OSLog
import SceneKit
import SwiftUI
import UIKit

/// The short opening remains inside the same SceneKit world as Home Island.
/// Camera direction supplies the story: the player begins beside the lantern
/// room, then the shot descends to the one object on the beach that does not
/// belong there.
struct FirstLightPrologueSceneView: UIViewRepresentable {
    enum Stage: Equatable {
        case lighthouse
        case bottle
        case letter
    }

    let stage: Stage
    let animate: Bool
    let onBottleTapped: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(owner: self)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = FirstLightPrologueSceneFactory.makeScene(animate: animate)
        view.pointOfView = view.scene?.rootNode.childNode(
            withName: FirstLightPrologueSceneFactory.cameraName,
            recursively: false
        )
        view.backgroundColor = FirstLightPrologueSceneFactory.skyColor
        view.isOpaque = true
        view.antialiasingMode = .multisampling2X
        view.contentScaleFactor = min(UIScreen.main.scale, 2)
        view.preferredFramesPerSecond = 30
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.rendersContinuously = animate
        view.isPlaying = animate
        view.accessibilityIdentifier = "first-light-prologue-scene"

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        context.coordinator.install(on: view)
        context.coordinator.apply(stage: stage, animated: false)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.owner = self
        context.coordinator.setAnimating(animate)
        context.coordinator.apply(stage: stage, animated: animate)
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        view.gestureRecognizers?.forEach(view.removeGestureRecognizer)
        view.delegate = nil
        view.isPlaying = false
        view.rendersContinuously = false
        coordinator.stop()
        view.scene = nil
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var owner: FirstLightPrologueSceneView

        private weak var view: SCNView?
        private weak var scene: SCNScene?
        private weak var camera: SCNNode?
        private weak var cameraTarget: SCNNode?
        private weak var bottleGlow: SCNNode?
        private weak var lighthouseRotor: SCNNode?
        private weak var seaMaterial: SCNMaterial?
        private var currentStage: Stage?
        private var startTime: TimeInterval?
        private var animationEnabled = true
        private var framePacing = MetalOceanFramePacingMonitor()
        private var hasReducedRenderingQuality = false
        private let performanceLogger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "Landfall",
            category: "MetalOceanPerformance"
        )

        init(owner: FirstLightPrologueSceneView) {
            self.owner = owner
        }

        func install(on view: SCNView) {
            self.view = view
            scene = view.scene
            camera = view.scene?.rootNode.childNode(
                withName: FirstLightPrologueSceneFactory.cameraName,
                recursively: false
            )
            cameraTarget = view.scene?.rootNode.childNode(
                withName: FirstLightPrologueSceneFactory.cameraTargetName,
                recursively: false
            )
            bottleGlow = view.scene?.rootNode.childNode(
                withName: FirstLightPrologueSceneFactory.bottleGlowName,
                recursively: true
            )
            lighthouseRotor = view.scene?.rootNode.childNode(
                withName: FirstLightPrologueSceneFactory.lighthouseRotorName,
                recursively: true
            )
            seaMaterial = view.scene?.rootNode
                .childNode(withName: HomeIslandOceanEffects.surfaceNodeName, recursively: true)?
                .geometry?.firstMaterial
            framePacing.reset()
            view.delegate = self
        }

        func stop() {
            animationEnabled = false
            view = nil
            scene = nil
        }

        func setAnimating(_ enabled: Bool) {
            animationEnabled = enabled
            view?.rendersContinuously = enabled
            view?.isPlaying = enabled
            if !enabled {
                settleStaticFrame()
                view?.setNeedsDisplay()
            }
        }

        func apply(stage: Stage, animated: Bool) {
            guard currentStage != stage || currentStage == nil else { return }
            currentStage = stage

            let pose = FirstLightPrologueSceneFactory.cameraPose(for: stage)
            let duration: TimeInterval = animated ? (stage == .bottle ? 2.8 : 1.0) : 0
            camera?.removeAllActions()
            cameraTarget?.removeAllActions()

            SCNTransaction.begin()
            SCNTransaction.animationDuration = duration
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(
                controlPoints: 0.22,
                0.72,
                0.18,
                1
            )
            camera?.position = pose.position
            cameraTarget?.position = pose.target
            camera?.camera?.fieldOfView = pose.fieldOfView
            updateCameraDirection()
            bottleGlow?.opacity = stage == .lighthouse ? 0.02 : 0.10
            SCNTransaction.commit()

            if !animationEnabled {
                settleStaticFrame()
                view?.setNeedsDisplay()
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard currentStage == .bottle, let view else { return }
            let point = gesture.location(in: view)
            let hits = view.hitTest(
                point,
                options: [
                    .searchMode: SCNHitTestSearchMode.all.rawValue,
                    .boundingBoxOnly: true,
                    .ignoreHiddenNodes: true,
                ]
            )
            guard hits.contains(where: { hit in
                var node: SCNNode? = hit.node
                while let current = node {
                    if current.name == FirstLightPrologueSceneFactory.bottleHitName {
                        return true
                    }
                    node = current.parent
                }
                return false
            }) else { return }

            DispatchQueue.main.async { [weak self] in
                self?.owner.onBottleTapped()
            }
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard animationEnabled, scene != nil else { return }
            if startTime == nil {
                startTime = time
            }
            let elapsed = Float(time - (startTime ?? time))
            seaMaterial?.setValue(
                NSNumber(value: HomeIslandOceanEffects.currentTime),
                forKey: "uTime"
            )

            lighthouseRotor?.eulerAngles.y = elapsed * 0.24
            let pulse = 0.84 + sin(elapsed * 2.4) * 0.12
            bottleGlow?.scale = SCNVector3(pulse, pulse, pulse)
            updateCameraDirection()
            if seaMaterial?.program != nil,
               framePacing.observe(at: time, targetFramesPerSecond: 30) {
                reduceRenderingQualityIfNeeded()
            }
        }

        private func settleStaticFrame() {
            guard scene != nil else { return }
            updateCameraDirection()
            bottleGlow?.scale = SCNVector3(0.9, 0.9, 0.9)
            seaMaterial?.setValue(NSNumber(value: Float(0)), forKey: "uTime")
        }

        private func updateCameraDirection() {
            guard let camera, let cameraTarget else { return }
            camera.look(
                at: cameraTarget.presentation.position,
                up: SCNVector3(0, 1, 0),
                localFront: SCNVector3(0, 0, -1)
            )
        }

        private func reduceRenderingQualityIfNeeded() {
            guard !hasReducedRenderingQuality else { return }
            hasReducedRenderingQuality = true
#if DEBUG
            print("[MetalOceanPerformance] First Light overload detected")
#endif
            DispatchQueue.main.async { [weak self] in
                guard let self, let view = self.view else { return }
                view.contentScaleFactor = min(view.contentScaleFactor, 1.5)
                self.performanceLogger.notice(
                    "Reduced First Light render scale after frame pacing pressure"
                )
            }
        }
    }
}

private enum FirstLightPrologueSceneFactory {
    struct CameraPose {
        let position: SCNVector3
        let target: SCNVector3
        let fieldOfView: CGFloat
    }

    static let cameraName = "firstLightCamera"
    static let cameraTargetName = "firstLightCameraTarget"
    static let bottleHitName = "firstLightBottleHitTarget"
    static let bottleGlowName = "firstLightBottleGlow"
    static let lighthouseRotorName = "firstLightLighthouseRotor"
    static let skyColor = UIColor(rgb: 0x071B1A)

    private static let surfaceY: Float = 0.10
    private static let lighthousePosition = SCNVector3(-1.9, surfaceY, -2.4)
    private static let bottlePosition = SCNVector3(2.8, surfaceY + 0.08, 4.0)

    static func cameraPose(for stage: FirstLightPrologueSceneView.Stage) -> CameraPose {
        switch stage {
        case .lighthouse:
            CameraPose(
                position: SCNVector3(4.8, 7.4, 6.6),
                target: SCNVector3(-1.9, 6.45, -1.4),
                fieldOfView: 38
            )
        case .bottle:
            CameraPose(
                position: SCNVector3(5.65, 1.42, 6.72),
                target: bottlePosition,
                fieldOfView: 44
            )
        case .letter:
            CameraPose(
                position: SCNVector3(4.65, 0.92, 5.45),
                target: bottlePosition,
                fieldOfView: 38
            )
        }
    }

    static func makeScene(animate: Bool) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = skyColor
        scene.fogColor = UIColor(rgb: 0x173937)
        scene.fogStartDistance = 24
        scene.fogEndDistance = 72
        scene.lightingEnvironment.contents = UIColor(rgb: 0xB9D7CF)
        scene.lightingEnvironment.intensity = 0.72

        let oceanAppearance = HomeIslandOceanEffects.Appearance(
            shallow: 0x267E7A,
            sea: 0x0D5B69,
            deep: 0x062F3C,
            light: 0xDCE9DD,
            sky: 0x071B1A,
            horizon: 0x426D6A,
            sun: 0xE6D9B8,
            fog: 0x173937,
            sunDirection: SCNVector3(-0.42, 0.78, 0.46),
            sunStrength: 0.24
        )
        scene.rootNode.addChildNode(
            HomeIslandOceanEffects.makeScene(
                layout: HomeIslandOceanEffects.Layout(
                    width: 180,
                    depth: 180,
                    widthSegments: MetalRenderingProfile.current.oceanSegments(base: 140),
                    depthSegments: MetalRenderingProfile.current.oceanSegments(base: 140),
                    centerX: 0,
                    surfaceY: surfaceY,
                    includesShoreline: true,
                    rootName: "firstLightSea"
                ),
                appearance: oceanAppearance,
                islandScale: 0.72,
                nativeMetalRollout: .entryExperience
            ).root
        )

        let stars = VoyageSceneKit.makeStars(count: 220)
        stars.opacity = 0.54
        scene.rootNode.addChildNode(stars)

        let moon = VoyageSceneKit.makeMoon(position: SCNVector3(-13, 12.5, -28))
        moon.scale = SCNVector3(0.72, 0.72, 0.72)
        moon.opacity = 0.72
        scene.rootNode.addChildNode(moon)

        addIsland(to: scene.rootNode)
        addLighthouse(to: scene.rootNode)
        addCampfire(to: scene.rootNode)
        addNature(to: scene.rootNode)
        addBottle(to: scene.rootNode)
        addLights(to: scene.rootNode)

        let camera = SCNNode()
        camera.name = cameraName
        camera.camera = SCNCamera()
        camera.camera?.zNear = 0.08
        camera.camera?.zFar = 180
        camera.camera?.wantsHDR = true
        camera.camera?.wantsExposureAdaptation = true
        camera.camera?.exposureOffset = -0.34
        camera.camera?.bloomIntensity = 0.22
        camera.camera?.bloomThreshold = 1.08
        camera.camera?.bloomBlurRadius = 6
        let pose = cameraPose(for: .lighthouse)
        camera.position = pose.position
        camera.camera?.fieldOfView = pose.fieldOfView
        scene.rootNode.addChildNode(camera)

        let target = SCNNode()
        target.name = cameraTargetName
        target.position = pose.target
        scene.rootNode.addChildNode(target)
        camera.look(
            at: target.position,
            up: SCNVector3(0, 1, 0),
            localFront: SCNVector3(0, 0, -1)
        )

        if !animate {
            scene.rootNode.enumerateChildNodes { node, _ in
                node.removeAllActions()
            }
        }
        return scene
    }

    private static func addIsland(to root: SCNNode) {
        guard let foundation = AssetPlacementRuntime.makeAssetNode(
            resourceName: HomeIslandMetrics.foundationResourceName
        ) else { return }
        foundation.name = "firstLightShallowIsland"
        HomeIslandSandSurface.apply(to: foundation)
        // The authored Home Island is compressed vertically and lowered until
        // its broad sand apron almost meets the sea. This keeps the familiar
        // coastline while making the prologue feel younger and more exposed.
        foundation.scale = SCNVector3(0.72, 0.22, 0.72)
        foundation.position = SCNVector3(0, -0.04, 0)
        root.addChildNode(foundation)
    }

    private static func addLighthouse(to root: SCNNode) {
        guard let lighthouse = AssetPlacementRuntime.makeAssetNode(
            resourceName: "weathered_lighthouse"
        ) else { return }
        lighthouse.name = "firstLightLighthouse"
        lighthouse.position = lighthousePosition
        lighthouse.eulerAngles.y = 0
        lighthouse.scale = SCNVector3(1.35, 1.35, 1.35)

        let rotor = lighthouse.childNode(
            withName: "LF_LighthouseBeaconRotor_Mesh",
            recursively: true
        ) ?? lighthouse.childNode(
            withName: "LF_LighthouseBeaconRotor",
            recursively: true
        )
        rotor?.name = lighthouseRotorName
        root.addChildNode(lighthouse)
    }

    private static func addCampfire(to root: SCNNode) {
        guard let campfire = AssetPlacementRuntime.makeAssetNode(
            resourceName: "campfire_circle"
        ) else { return }
        campfire.name = "firstLightCampfire"
        campfire.position = SCNVector3(2.4, surfaceY, -1.5)
        campfire.eulerAngles.y = 0.45
        campfire.scale = SCNVector3(0.72, 0.72, 0.72)
        root.addChildNode(campfire)
    }

    private static func addNature(to root: SCNNode) {
        let placements: [(String, Float, Float, Float, Float)] = [
            ("palm_tree", -5.7, -3.2, 0.64, 0.28),
            ("dune_grass_patch", -6.1, -0.8, 0.60, 0.14),
            ("dune_grass_patch", -4.8, -4.2, 0.54, -0.28),
            ("dune_grass_patch", 1.0, -5.1, 0.62, 0.44),
            ("dune_grass_patch", 5.4, -3.5, 0.56, -0.72),
            ("dune_grass_patch", -5.7, 3.7, 0.58, 0.31),
            ("dune_grass_patch", 5.8, 1.8, 0.52, -0.18),
        ]
        for (index, placement) in placements.enumerated() {
            guard let node = AssetPlacementRuntime.makeAssetNode(
                resourceName: placement.0
            ) else { continue }
            node.name = "firstLightNature\(index)"
            node.position = SCNVector3(placement.1, surfaceY, placement.2)
            node.eulerAngles.y = placement.4
            node.scale = SCNVector3(
                placement.3,
                placement.3,
                placement.3
            )
            root.addChildNode(node)
        }
    }

    private static func addBottle(to root: SCNNode) {
        let bottleRoot = SCNNode()
        bottleRoot.name = bottleHitName
        bottleRoot.position = bottlePosition
        bottleRoot.eulerAngles = SCNVector3(1.18, -0.24, 0.52)

        bottleRoot.addChildNode(makeMessageBottle())

        // The invisible volume gives a finger a generous target without
        // making the small real-world bottle look like a treasure chest.
        let targetGeometry = SCNSphere(radius: 0.42)
        targetGeometry.segmentCount = 12
        let targetMaterial = SCNMaterial()
        targetMaterial.lightingModel = .constant
        targetMaterial.diffuse.contents = UIColor.clear
        targetMaterial.transparency = 0
        targetMaterial.colorBufferWriteMask = []
        targetMaterial.readsFromDepthBuffer = false
        targetMaterial.writesToDepthBuffer = false
        targetGeometry.firstMaterial = targetMaterial
        let target = SCNNode(geometry: targetGeometry)
        target.name = bottleHitName
        bottleRoot.addChildNode(target)

        let glowGeometry = SCNSphere(radius: 0.23)
        glowGeometry.segmentCount = 24
        let glowMaterial = SCNMaterial()
        glowMaterial.lightingModel = .constant
        glowMaterial.diffuse.contents = UIColor(rgb: 0xFFE19A).withAlphaComponent(0.07)
        glowMaterial.emission.contents = UIColor(rgb: 0xFFD77A)
        glowMaterial.emission.intensity = 0.18
        glowMaterial.transparency = 0.22
        glowMaterial.blendMode = .add
        glowMaterial.writesToDepthBuffer = false
        glowGeometry.firstMaterial = glowMaterial
        let glow = SCNNode(geometry: glowGeometry)
        glow.name = bottleGlowName
        bottleRoot.addChildNode(glow)

        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .omni
        light.light?.color = UIColor(rgb: 0xFFD989)
        light.light?.intensity = 10
        light.light?.attenuationStartDistance = 0.15
        light.light?.attenuationEndDistance = 1.9
        bottleRoot.addChildNode(light)
        root.addChildNode(bottleRoot)
    }

    private static func addLights(to root: SCNNode) {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(rgb: 0x86A39D)
        ambient.light?.intensity = 310
        root.addChildNode(ambient)

        let dawn = SCNNode()
        dawn.light = SCNLight()
        dawn.light?.type = .directional
        dawn.light?.color = UIColor(rgb: 0xFFE1B7)
        dawn.light?.intensity = 1_050
        dawn.eulerAngles = SCNVector3(-0.72, -0.58, -0.12)
        dawn.light?.castsShadow = true
        dawn.light?.shadowMode = .deferred
        dawn.light?.shadowColor = UIColor.black.withAlphaComponent(0.48)
        dawn.light?.shadowRadius = 5
        dawn.light?.shadowMapSize = CGSize(width: 1_024, height: 1_024)
        root.addChildNode(dawn)

        let firelight = SCNNode()
        firelight.position = SCNVector3(2.4, 0.78, -1.5)
        firelight.light = SCNLight()
        firelight.light?.type = .omni
        firelight.light?.color = UIColor(rgb: 0xFFAE62)
        firelight.light?.intensity = 420
        firelight.light?.attenuationStartDistance = 0.3
        firelight.light?.attenuationEndDistance = 7
        root.addChildNode(firelight)
    }

    /// A real message bottle rather than one of the drink props. The sealed
    /// paper is visible through the glass in the close beach shot.
    private static func makeMessageBottle() -> SCNNode {
        let root = SCNNode()
        root.name = "firstLightMessageBottle"

        let glass = SCNMaterial()
        glass.name = "first-light-bottle-glass"
        glass.lightingModel = .physicallyBased
        glass.diffuse.contents = UIColor(rgb: 0x9FD7C8).withAlphaComponent(0.22)
        glass.emission.contents = UIColor(rgb: 0x78B9A8)
        glass.emission.intensity = 0.16
        glass.roughness.contents = 0.12
        glass.metalness.contents = 0
        glass.transparency = 0.48
        glass.blendMode = .alpha
        glass.isDoubleSided = true

        let bodyGeometry = SCNCylinder(radius: 0.12, height: 0.34)
        bodyGeometry.radialSegmentCount = 24
        bodyGeometry.firstMaterial = glass
        let body = SCNNode(geometry: bodyGeometry)
        root.addChildNode(body)

        let shoulderGeometry = SCNCone(
            topRadius: 0.055,
            bottomRadius: 0.12,
            height: 0.10
        )
        shoulderGeometry.radialSegmentCount = 24
        shoulderGeometry.firstMaterial = glass
        let shoulder = SCNNode(geometry: shoulderGeometry)
        shoulder.position.y = 0.22
        root.addChildNode(shoulder)

        let neckGeometry = SCNCylinder(radius: 0.055, height: 0.13)
        neckGeometry.radialSegmentCount = 20
        neckGeometry.firstMaterial = glass
        let neck = SCNNode(geometry: neckGeometry)
        neck.position.y = 0.335
        root.addChildNode(neck)

        let lipGeometry = SCNTorus(ringRadius: 0.058, pipeRadius: 0.012)
        lipGeometry.ringSegmentCount = 20
        lipGeometry.pipeSegmentCount = 6
        lipGeometry.firstMaterial = glass
        let lip = SCNNode(geometry: lipGeometry)
        lip.position.y = 0.405
        root.addChildNode(lip)

        let corkMaterial = SCNMaterial()
        corkMaterial.lightingModel = .physicallyBased
        corkMaterial.diffuse.contents = UIColor(rgb: 0x9A6E43)
        corkMaterial.roughness.contents = 0.92
        let corkGeometry = SCNCylinder(radius: 0.045, height: 0.09)
        corkGeometry.radialSegmentCount = 12
        corkGeometry.firstMaterial = corkMaterial
        let cork = SCNNode(geometry: corkGeometry)
        cork.position.y = 0.42
        root.addChildNode(cork)

        let paperMaterial = SCNMaterial()
        paperMaterial.lightingModel = .physicallyBased
        paperMaterial.diffuse.contents = UIColor(rgb: 0xE9D6A4)
        paperMaterial.roughness.contents = 0.88
        paperMaterial.emission.contents = UIColor(rgb: 0xC99F55)
        paperMaterial.emission.intensity = 0.12
        let paperGeometry = SCNCylinder(radius: 0.035, height: 0.22)
        paperGeometry.radialSegmentCount = 16
        paperGeometry.firstMaterial = paperMaterial
        let paper = SCNNode(geometry: paperGeometry)
        paper.name = "firstLightRolledLetter"
        paper.eulerAngles.z = 0.34
        paper.position = SCNVector3(0.025, -0.015, 0)
        root.addChildNode(paper)

        root.scale = SCNVector3(0.86, 0.86, 0.86)
        return root
    }
}
