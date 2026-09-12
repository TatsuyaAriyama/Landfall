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
        let view = SCNView(frame: .zero, options: MetalRenderingProfile.sceneViewOptions())
        view.scene = FirstLightPrologueSceneFactory.makeScene(animate: animate)
        view.pointOfView = view.scene?.rootNode.childNode(
            withName: FirstLightPrologueSceneFactory.cameraName,
            recursively: false
        )
        view.backgroundColor = FirstLightPrologueSceneFactory.skyColor
        view.isOpaque = true
        view.antialiasingMode = .multisampling4X
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
        context.coordinator.apply(stage: stage, animated: animate)
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
            let duration: TimeInterval = stage == .lighthouse ? 7.5 : (stage == .bottle ? 3.6 : 1.2)
            guard let camera, let cameraTarget else { return }
            let origin = camera.position
            let originTarget = cameraTarget.position
            let originFieldOfView = camera.camera?.fieldOfView ?? pose.fieldOfView
            camera.removeAllActions()
            cameraTarget.removeAllActions()

            // Move the lens and its subject on the same clock. Mixing a model
            // camera position with a presentation target twists the view during
            // the long descent, even though both endpoints look correct.
            if animated {
                camera.runAction(.customAction(duration: duration) { [weak cameraTarget] node, elapsed in
                    let t = min(Float(elapsed / CGFloat(duration)), 1)
                    let eased = t * t * t * (t * (t * 6 - 15) + 10)
                    func blend(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
                        SCNVector3(a.x + (b.x - a.x) * eased,
                                   a.y + (b.y - a.y) * eased,
                                   a.z + (b.z - a.z) * eased)
                    }
                    node.position = blend(origin, pose.position)
                    cameraTarget?.position = blend(originTarget, pose.target)
                    node.camera?.fieldOfView = originFieldOfView
                        + (pose.fieldOfView - originFieldOfView) * CGFloat(eased)
                    node.look(at: blend(originTarget, pose.target),
                              up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
                }, forKey: "prologueCameraMove")
            } else {
                camera.position = pose.position
                cameraTarget.position = pose.target
                camera.camera?.fieldOfView = pose.fieldOfView
                updateCameraDirection()
            }
            bottleGlow?.opacity = stage == .lighthouse ? 0.02 : 0.10

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
            let hitBottle = hits.contains(where: { hit in
                var node: SCNNode? = hit.node
                while let current = node {
                    if current.name == FirstLightPrologueSceneFactory.bottleHitName {
                        return true
                    }
                    node = current.parent
                }
                return false
            })
            // A screen-space touch allowance needs no invisible geometry;
            // transparent hit spheres can still contaminate HDR rendering.
            let bottle = view.scene?.rootNode.childNode(
                withName: FirstLightPrologueSceneFactory.bottleHitName, recursively: true
            )
            let projected = bottle.map { view.projectPoint($0.worldPosition) }
            let nearBottle = projected.map {
                $0.z >= 0 && $0.z <= 1
                    && hypot(point.x - CGFloat($0.x), point.y - CGFloat($0.y)) <= 44
            } ?? false
            guard hitBottle || nearBottle else { return }

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
                at: cameraTarget.position,
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
    static let lighthouseRotorName = LighthouseBeaconAnimation.pivotName
    static let skyColor = UIColor(rgb: 0x071B1A)

    private static let seaLevel: Float = 0.10
    private static let surfaceY: Float = 0.32
    private static let lighthousePosition = SCNVector3(-1.9, surfaceY, -2.4)
    private static let bottlePosition = SCNVector3(2.8, surfaceY + 0.15, 4.0)

    static func cameraPose(for stage: FirstLightPrologueSceneView.Stage) -> CameraPose {
        switch stage {
        case .lighthouse:
            CameraPose(
                position: SCNVector3(6.0, 8.1, 11.2),
                target: SCNVector3(-2.2, 6.1, -2.4),
                fieldOfView: 43
            )
        case .bottle:
            CameraPose(
                position: SCNVector3(4.25, 1.17, 5.85),
                target: SCNVector3(2.8, surfaceY + 0.20, 4.0),
                fieldOfView: 42
            )
        case .letter:
            CameraPose(
                position: SCNVector3(4.65, 1.14, 5.45),
                target: bottlePosition,
                fieldOfView: 38
            )
        }
    }

    static func makeScene(animate: Bool) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = makeSky()
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
                    surfaceY: seaLevel,
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
        // A fixed exposure keeps the lantern and pale letter from causing a
        // visible brightness pump as the camera crosses the shoreline.
        camera.camera?.wantsExposureAdaptation = false
        camera.camera?.exposureOffset = -0.18
        camera.camera?.bloomIntensity = 0.32
        camera.camera?.bloomThreshold = 1.08
        camera.camera?.bloomBlurRadius = 6
        let pose = cameraPose(for: .lighthouse)
        camera.position = animate ? SCNVector3(7.1, 8.7, 13.0) : pose.position
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

    private static func makeSky() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 512), format: format).image { context in
            let colors = [UIColor(rgb: 0x041214).cgColor,
                          UIColor(rgb: 0x102F35).cgColor,
                          UIColor(rgb: 0x426663).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors, locations: [0, 0.55, 1]) else { return }
            context.cgContext.drawLinearGradient(gradient, start: .zero,
                                                  end: CGPoint(x: 0, y: 512), options: [])
        }
    }

    private static func addIsland(to root: SCNNode) {
        guard let foundation = AssetPlacementRuntime.makeAssetNode(
            resourceName: HomeIslandMetrics.foundationResourceName
        ) else { return }
        foundation.name = "firstLightShallowIsland"
        HomeIslandSandSurface.apply(to: foundation)
        foundation.enumerateChildNodes { node, _ in
            node.geometry?.materials.forEach { material in
                if material.name == "home-island-pristine-sand" {
                    material.emission.intensity = 0.025
                }
            }
        }
        // Keep the compressed beach above wave crests. Coincident ocean and
        // sand planes produce moving straight cuts through the close-up.
        foundation.scale = SCNVector3(0.72, 0.22, 0.72)
        foundation.position = SCNVector3(0, surfaceY - (HomeIslandMetrics.surfaceY + 0.018) * 0.22, 0)
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

        root.addChildNode(lighthouse)
        if let pivot = LighthouseBeaconAnimation.rotationPivot(in: lighthouse) {
            // The prologue's renderer drives this same pivot at its own speed.
            // Stop the runtime loop so two clocks cannot animate the lens.
            pivot.removeAction(forKey: LighthouseBeaconAnimation.rotationActionKey)
        }

        let lantern = SCNNode()
        lantern.position = SCNVector3(lighthousePosition.x, surfaceY + 7.16, lighthousePosition.z)
        lantern.light = SCNLight()
        lantern.light?.type = .omni
        lantern.light?.color = UIColor(rgb: 0xFFD28B)
        lantern.light?.intensity = 520
        lantern.light?.attenuationStartDistance = 0.3
        lantern.light?.attenuationEndDistance = 4.5
        root.addChildNode(lantern)
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

        root.addChildNode(bottleRoot)
    }

    private static func addLights(to root: SCNNode) {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(rgb: 0x86A39D)
        ambient.light?.intensity = 220
        root.addChildNode(ambient)

        let dawn = SCNNode()
        dawn.light = SCNLight()
        dawn.light?.type = .directional
        dawn.light?.color = UIColor(rgb: 0xFFE1B7)
        dawn.light?.intensity = 680
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
        firelight.light?.intensity = 120
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
        glass.diffuse.contents = UIColor(rgb: 0x72B8A4).withAlphaComponent(0.64)
        glass.emission.contents = UIColor(rgb: 0x78B9A8)
        glass.emission.intensity = 0.035
        glass.roughness.contents = 0.22
        glass.metalness.contents = 0
        glass.transparency = 0.82
        glass.blendMode = .alpha
        glass.isDoubleSided = false
        glass.writesToDepthBuffer = false

        let bodyGeometry = makeBottleGlassGeometry()
        bodyGeometry.firstMaterial = glass
        let body = SCNNode(geometry: bodyGeometry)
        root.addChildNode(body)

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

    /// One revolved shell avoids the opaque internal end caps and overlapping
    /// transparent surfaces of stacked cylinders and cones.
    private static func makeBottleGlassGeometry() -> SCNGeometry {
        let profile: [(radius: Float, y: Float)] = [
            (0.001, -0.18), (0.085, -0.18), (0.108, -0.17),
            (0.12, -0.145), (0.12, 0.13), (0.116, 0.17),
            (0.102, 0.20), (0.076, 0.235), (0.057, 0.26),
            (0.055, 0.285), (0.055, 0.40),
        ]
        let segments = 48
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        for (ring, point) in profile.enumerated() {
            let previous = profile[max(0, ring - 1)]
            let next = profile[min(profile.count - 1, ring + 1)]
            let dr = next.radius - previous.radius
            let dy = next.y - previous.y
            let length = max(sqrt(dr * dr + dy * dy), 0.0001)
            for segment in 0...segments {
                let angle = Float(segment) / Float(segments) * .pi * 2
                vertices.append(SCNVector3(point.radius * cos(angle), point.y,
                                           point.radius * sin(angle)))
                normals.append(SCNVector3(dy * cos(angle) / length, -dr / length,
                                          dy * sin(angle) / length))
                if ring < profile.count - 1, segment < segments {
                    let a = Int32(ring * (segments + 1) + segment)
                    let b = a + Int32(segments + 1)
                    indices += [a, b, a + 1, a + 1, b, b + 1]
                }
            }
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: vertices),
                                     SCNGeometrySource(normals: normals)],
                           elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }
}
