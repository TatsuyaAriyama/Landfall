import SceneKit
import SwiftUI
import UIKit

/// 「忘却の海」序章だけで使う、画像テクスチャを一切持たない3Dシーン。
/// 海と星、既存の船・航海士以外は、このファイル内のSceneKitジオメトリで組み立てる。
struct ForgottenSeaPrologueSceneView: UIViewRepresentable {
    let beat: Int
    let animate: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor(rgb: 0x061719)
        view.isOpaque = true
        view.antialiasingMode = .multisampling2X
        view.contentScaleFactor = min(UIScreen.main.scale, 2)
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.isUserInteractionEnabled = false
        view.preferredFramesPerSecond = 30
        view.scene = ForgottenSeaPrologueSceneFactory.makeScene()
        view.pointOfView = view.scene?.rootNode.childNode(
            withName: ForgottenSeaPrologueSceneFactory.cameraName,
            recursively: false
        )
        view.delegate = context.coordinator

        context.coordinator.install(
            in: view,
            beat: Self.resolvedDebugBeat(beat),
            animate: Self.resolvedAnimation(animate)
        )
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.update(
            beat: Self.resolvedDebugBeat(beat),
            animate: Self.resolvedAnimation(animate)
        )
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.stop()
        view.delegate = nil
        view.isPlaying = false
        view.rendersContinuously = false
        view.scene = nil
    }

    private static func resolvedDebugBeat(_ value: Int) -> Int {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["LANDFALL_PROLOGUE_BEAT"],
           let forced = Int(raw) {
            return min(max(forced, 0), 5)
        }
        #endif
        return min(max(value, 0), 5)
    }

    private static func resolvedAnimation(_ value: Bool) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["LANDFALL_PROLOGUE_STATIC"] == "1" {
            return false
        }
        #endif
        return value
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        private weak var view: SCNView?
        private weak var scene: SCNScene?
        private weak var camera: SCNNode?
        private weak var cameraTarget: SCNNode?
        private weak var vessel: SCNNode?
        private weak var posePivot: SCNNode?
        private weak var stars: SCNNode?
        private weak var fog: SCNNode?
        private weak var lighthouseRotor: SCNNode?
        private weak var lighthouseBeam: SCNNode?
        private weak var lighthouseLamp: SCNNode?
        private weak var lighthouseLight: SCNNode?
        private weak var routeMarkers: SCNNode?
        private weak var journal: SCNNode?
        private weak var journalPageHinge: SCNNode?
        private weak var deckFlame: SCNNode?
        private weak var heldFlame: SCNNode?
        private weak var deckFlameLight: SCNNode?
        private weak var heldFlameLight: SCNNode?
        private weak var marinerLantern: SCNNode?
        private weak var nativeLanternArm: SCNNode?
        private weak var lanternHoldingArm: SCNNode?
        private var closeSails: [SCNNode] = []

        private var currentBeat = -1
        private var animationEnabled = true
        private var startTime: TimeInterval?
        private var lastTime: TimeInterval = 0
        private var beatStartTime: TimeInterval?
        private let navigatorAnimator = PhoenixAnimator()

        func install(in view: SCNView, beat: Int, animate: Bool) {
            self.view = view
            scene = view.scene
            bindNodes()
            navigatorAnimator.animate = animate
            apply(beat: beat, animated: false)
            setAnimating(animate)
        }

        func update(beat: Int, animate: Bool) {
            if animationEnabled != animate {
                navigatorAnimator.animate = animate
                setAnimating(animate)
            }
            if currentBeat != beat {
                apply(beat: beat, animated: animate)
            }
        }

        func stop() {
            animationEnabled = false
            navigatorAnimator.animate = false
            view?.isPlaying = false
            view?.rendersContinuously = false
            view = nil
            scene = nil
        }

        private func bindNodes() {
            guard let root = scene?.rootNode else { return }
            camera = root.childNode(
                withName: ForgottenSeaPrologueSceneFactory.cameraName,
                recursively: false
            )
            cameraTarget = root.childNode(
                withName: ForgottenSeaPrologueSceneFactory.cameraTargetName,
                recursively: false
            )
            vessel = root.childNode(withName: "prologueVessel", recursively: false)
            posePivot = root.childNode(withName: "prologuePosePivot", recursively: true)
            stars = root.childNode(withName: "prologueStars", recursively: false)
            fog = root.childNode(withName: "prologueFog", recursively: false)
            lighthouseRotor = root.childNode(withName: "prologueLighthouseRotor", recursively: true)
            lighthouseBeam = root.childNode(withName: "prologueLighthouseBeam", recursively: true)
            lighthouseLamp = root.childNode(withName: "prologueLighthouseLamp", recursively: true)
            lighthouseLight = root.childNode(withName: "prologueLighthouseLight", recursively: true)
            routeMarkers = root.childNode(withName: "prologueRouteMarkers", recursively: false)
            journal = root.childNode(withName: "prologueJournal", recursively: true)
            journalPageHinge = root.childNode(withName: "prologueJournalPageHinge", recursively: true)
            deckFlame = root.childNode(withName: "prologueDeckFlame", recursively: true)
            heldFlame = root.childNode(withName: "prologueHeldFlame", recursively: true)
            deckFlameLight = root.childNode(withName: "prologueDeckFlameLight", recursively: true)
            heldFlameLight = root.childNode(withName: "prologueHeldFlameLight", recursively: true)
            marinerLantern = root.childNode(withName: "prologueMarinerLantern", recursively: true)
            nativeLanternArm = root.childNode(withName: "prologueNativeLanternArm", recursively: true)
            lanternHoldingArm = root.childNode(withName: "prologueLanternHoldingArm", recursively: true)
            closeSails = ["LF_BoatMainSail", "LF_BoatJib"].compactMap {
                root.childNode(withName: $0, recursively: true)
            }

            navigatorAnimator.bindIfNeeded(scene ?? SCNScene())
        }

        private func setAnimating(_ value: Bool) {
            animationEnabled = value
            guard let view else { return }
            view.isPlaying = value
            view.rendersContinuously = value
            if !value {
                settleNavigator()
                applyContinuousFrame(time: 0, delta: 0)
                view.setNeedsDisplay()
            }
        }

        private func settleNavigator() {
            guard let scene else { return }
            navigatorAnimator.bindIfNeeded(scene)
            navigatorAnimator.pose = finalPose(for: currentBeat)
            for index in 0..<8 {
                navigatorAnimator.step(t: Float(index) * 0.2, dt: 0.2)
            }
        }

        private func apply(beat value: Int, animated: Bool) {
            let beat = min(max(value, 0), 5)
            currentBeat = beat
            beatStartTime = nil

            let pose = ForgottenSeaPrologueSceneFactory.cameraPoses[beat]
            let duration: TimeInterval = animated ? (beat == 5 ? 2.15 : 1.65) : 0

            camera?.removeAllActions()
            cameraTarget?.removeAllActions()
            posePivot?.removeAllActions()
            journalPageHinge?.removeAllActions()

            SCNTransaction.begin()
            SCNTransaction.animationDuration = duration
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(
                controlPoints: 0.22,
                0.72,
                0.20,
                1.0
            )

            camera?.position = pose.position
            cameraTarget?.position = pose.target
            camera?.camera?.fieldOfView = pose.fieldOfView

            let rig = rigState(for: beat)
            posePivot?.position = rig.position
            posePivot?.eulerAngles = rig.eulerAngles

            let starOpacity: CGFloat = beat >= 2 ? 0 : 1
            stars?.opacity = starOpacity
            lighthouseBeam?.opacity = beat >= 2 ? 0 : 0.34
            lighthouseLamp?.opacity = beat >= 2 ? 0.10 : 1
            lighthouseLight?.light?.intensity = beat >= 2 ? 0 : 1_050

            fog?.opacity = fogOpacity(for: beat)
            journal?.opacity = beat >= 4 ? 1 : 0
            journalPageHinge?.eulerAngles.z = beat == 5 ? 0.04 : .pi - 0.04
            nativeLanternArm?.opacity = beat == 5 ? 0 : 1
            lanternHoldingArm?.opacity = beat == 5 ? 1 : 0
            marinerLantern?.position = beat == 5
                ? SCNVector3(0.072, 0, 0)
                : SCNVector3Zero
            for sail in closeSails {
                sail.opacity = beat >= 4 ? 0.06 : 1
            }

            if beat < 4 {
                deckFlame?.opacity = 0
                heldFlame?.opacity = 0
                deckFlameLight?.light?.intensity = 0
                heldFlameLight?.light?.intensity = 0
            } else if beat == 4 {
                deckFlame?.opacity = 0.48
                heldFlame?.opacity = 0
                deckFlameLight?.light?.intensity = 24
                heldFlameLight?.light?.intensity = 0
            } else if animated {
                deckFlame?.opacity = 0.72
                heldFlame?.opacity = 0
                deckFlameLight?.light?.intensity = 28
                heldFlameLight?.light?.intensity = 0
            } else {
                deckFlame?.opacity = 0
                heldFlame?.opacity = 0.82
                deckFlameLight?.light?.intensity = 0
                heldFlameLight?.light?.intensity = 48
            }

            SCNTransaction.commit()

            applyRouteState(for: beat, duration: duration)
            applyFogDistances(for: beat)
            navigatorAnimator.pose = initialPose(for: beat)

            // 横たわっている間は一度だけ.restを反映し、capeの毎frame再生成を避ける。
            if animated, beat < 3, let scene {
                navigatorAnimator.bindIfNeeded(scene)
                navigatorAnimator.step(t: 0, dt: 0.2)
            }

            if !animated {
                settleNavigator()
                applyContinuousFrame(time: 0, delta: 0)
                view?.setNeedsDisplay()
            }
        }

        private func applyRouteState(for beat: Int, duration: TimeInterval) {
            guard let routeMarkers else { return }
            for (index, marker) in routeMarkers.childNodes.enumerated() {
                marker.removeAllActions()
                let surfaceY: Float = 0.035
                let sunk = beat >= 1
                if duration <= 0 {
                    marker.position.y = sunk ? -1.45 - Float(index) * 0.08 : surfaceY
                    marker.opacity = sunk ? 0 : 1
                    continue
                }
                SCNTransaction.begin()
                SCNTransaction.animationDuration = duration + Double(index) * 0.12
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                marker.position.y = sunk ? -1.45 - Float(index) * 0.08 : surfaceY
                marker.opacity = sunk ? 0 : 1
                SCNTransaction.commit()
            }
        }

        private func applyFogDistances(for beat: Int) {
            guard let scene else { return }
            let distances: [(CGFloat, CGFloat)] = [
                (8, 42), (5, 27), (4, 21), (7, 34), (9, 43), (13, 58),
            ]
            let value = distances[beat]
            scene.fogStartDistance = value.0
            scene.fogEndDistance = value.1
        }

        private func initialPose(for beat: Int) -> PhoenixPose {
            switch beat {
            case 0...3: .rest
            case 4: .sit
            default: animationEnabled ? .sit : .raise
            }
        }

        private func finalPose(for beat: Int) -> PhoenixPose {
            switch beat {
            case 0...3: .rest
            case 4: .sit
            default: .raise
            }
        }

        private func rigState(for beat: Int) -> (position: SCNVector3, eulerAngles: SCNVector3) {
            switch beat {
            case 0...2:
                (SCNVector3(-0.10, 0, 0), SCNVector3(0, 0, Float.pi / 2))
            case 3:
                (SCNVector3(-0.08, 0.01, 0), SCNVector3(0, 0, 1.15))
            case 4:
                (SCNVector3(-0.03, 0.02, 0), SCNVector3(0, 0, 0.18))
            default:
                (SCNVector3(0, 0, 0), SCNVector3Zero)
            }
        }

        private func fogOpacity(for beat: Int) -> CGFloat {
            [0.70, 0.93, 1.0, 0.84, 0.58, 0.40][beat]
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard animationEnabled, let scene else { return }
            if startTime == nil {
                startTime = time
                lastTime = time
            }
            if beatStartTime == nil { beatStartTime = time }
            let elapsed = Float(time - (startTime ?? time))
            let delta = Float(min(max(time - lastTime, 0), 0.1))
            let beatElapsed = Float(time - (beatStartTime ?? time))
            lastTime = time

            navigatorAnimator.bindIfNeeded(scene)
            updateNarrativePose(beatElapsed: beatElapsed)
            if currentBeat >= 4 {
                navigatorAnimator.step(t: elapsed, dt: delta)
            }
            applyContinuousFrame(time: elapsed, delta: delta)
        }

        private func updateNarrativePose(beatElapsed: Float) {
            switch currentBeat {
            case 0...3:
                navigatorAnimator.pose = .rest
            case 4:
                navigatorAnimator.pose = .sit
            case 5:
                if beatElapsed < 1.05 {
                    navigatorAnimator.pose = .sit
                } else if beatElapsed < 2.45 {
                    navigatorAnimator.pose = .idle
                } else {
                    navigatorAnimator.pose = .raise
                }

                let transfer = min(max((beatElapsed - 2.0) / 0.85, 0), 1)
                deckFlame?.opacity = CGFloat(1 - transfer)
                heldFlame?.opacity = CGFloat(transfer)
                deckFlameLight?.light?.intensity = CGFloat(28 * (1 - transfer))
                heldFlameLight?.light?.intensity = CGFloat(48 * transfer)
            default:
                navigatorAnimator.pose = .idle
            }
        }

        private func applyContinuousFrame(time: Float, delta: Float) {
            if animationEnabled {
                vessel?.position.y = sin(time * 0.62) * 0.045
                vessel?.eulerAngles.z = sin(time * 0.46 + 0.8) * 0.018
                vessel?.eulerAngles.x = sin(time * 0.38) * 0.012
                lighthouseRotor?.eulerAngles.y = time * 0.34
                updateFog(time: time)
            }

            let flicker = animationEnabled
                ? 0.86 + sin(time * 9.2) * 0.08 + sin(time * 15.7 + 0.8) * 0.05
                : 0.92
            animateFlame(deckFlame, amount: flicker)
            animateFlame(heldFlame, amount: 0.96 + (flicker - 0.92) * 0.72)
        }

        private func updateFog(time: Float) {
            guard let fog else { return }
            for (index, bank) in fog.childNodes.enumerated() {
                let value = Float(index)
                bank.position.x = -14 + Float(index % 7) * 4.7
                    + sin(time * (0.055 + value * 0.002) + value) * 3.2
                bank.position.y = 0.52 + Float(index % 3) * 0.62
                    + sin(time * 0.13 + value * 0.7) * 0.18
                bank.position.z = -2.5 - Float(index % 5) * 4.5
                    + cos(time * 0.045 + value) * 2.0
            }
        }

        private func animateFlame(_ flame: SCNNode?, amount: Float) {
            guard let flame else { return }
            flame.scale = SCNVector3(
                0.92 + (amount - 0.9) * 0.38,
                amount,
                0.92 + (amount - 0.9) * 0.24
            )
            flame.eulerAngles.y += animationEnabled ? 0.012 : 0
        }
    }
}

private enum ForgottenSeaPrologueSceneFactory {
    static let cameraName = "prologueCamera"
    static let cameraTargetName = "prologueCameraTarget"

    struct CameraPose {
        let position: SCNVector3
        let target: SCNVector3
        let fieldOfView: CGFloat
    }

    static let cameraPoses: [CameraPose] = [
        CameraPose(
            position: SCNVector3(-5.8, 3.35, 8.4),
            target: SCNVector3(0.4, 0.35, -3.2),
            fieldOfView: 47
        ),
        CameraPose(
            position: SCNVector3(1.7, 5.7, 8.1),
            target: SCNVector3(1.4, -0.15, -7.0),
            fieldOfView: 49
        ),
        CameraPose(
            position: SCNVector3(-3.5, 1.75, 5.8),
            target: SCNVector3(0.8, 0.30, -4.5),
            fieldOfView: 43
        ),
        CameraPose(
            position: SCNVector3(4.15, 2.30, 5.6),
            target: SCNVector3(5.0, 2.10, -15.0),
            fieldOfView: 38
        ),
        CameraPose(
            position: SCNVector3(4.25, 1.72, 1.55),
            target: SCNVector3(0.34, 0.72, 0.02),
            fieldOfView: 43
        ),
        CameraPose(
            position: SCNVector3(4.45, 1.95, 1.30),
            target: SCNVector3(0.48, 0.82, 0.08),
            fieldOfView: 41
        ),
    ]

    static func makeScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor(rgb: 0x061719)
        scene.fogColor = UIColor(rgb: 0x102A2C)
        scene.fogStartDistance = 8
        scene.fogEndDistance = 42
        scene.fogDensityExponent = 1.18

        let sea = VoyageSceneKit.makeSea(moonX: -4.5)
        sea.name = "prologueSea"
        sea.position.y = -0.08
        scene.rootNode.addChildNode(sea)

        let stars = VoyageSceneKit.makeStars(count: 520)
        stars.name = "prologueStars"
        stars.geometry?.firstMaterial?.diffuse.contents = UIColor(rgb: 0xD5DDD2)
            .withAlphaComponent(0.68)
        scene.rootNode.addChildNode(stars)

        scene.rootNode.addChildNode(makeFog())
        scene.rootNode.addChildNode(makeRouteMarkers())
        scene.rootNode.addChildNode(makeLighthouse())
        scene.rootNode.addChildNode(makeVessel())
        addLights(to: scene.rootNode)
        addCamera(to: scene.rootNode)
        return scene
    }

    private static func makeVessel() -> SCNNode {
        let vessel = SCNNode()
        vessel.name = "prologueVessel"
        vessel.position = SCNVector3Zero
        vessel.eulerAngles.y = 0.10
        vessel.scale = SCNVector3(1.34, 1.34, 1.34)

        let boat = VoyageSceneKit.makeBoatModel(BoatCustomization.currentParts)
        boat.name = "prologueAgedBoat"
        weatherBoat(boat)
        vessel.addChildNode(boat)
        vessel.addChildNode(makeWeatheredDeck())

        let posePivot = SCNNode()
        posePivot.name = "prologuePosePivot"
        let navigator = PhoenixNavigator.makeNavigatorNode()
        // PhoenixAnimatorの探索契約なので、navigator自身の名前は変更しない。
        navigator.scale = SCNVector3(0.62, 0.62, 0.62)
        posePivot.addChildNode(navigator)

        if let anchor = boat.childNode(withName: "Navigator_Anchor", recursively: true) {
            anchor.addChildNode(posePivot)
        } else {
            posePivot.position = VoyageSceneKit.navigatorDeckPosition
            vessel.addChildNode(posePivot)
        }

        if let lantern = navigator.childNode(withName: "lantern", recursively: true) {
            installMarinerLantern(on: lantern, navigator: navigator)
        }

        let journal = makeJournal()
        journal.position = SCNVector3(-0.02, 0.57, -0.31)
        journal.eulerAngles.y = -0.22
        journal.opacity = 0
        vessel.addChildNode(journal)

        let deckFlame = makeFlame(
            name: "prologueDeckFlame",
            lightName: "prologueDeckFlameLight"
        )
        deckFlame.position = SCNVector3(0.40, 0.69, -0.30)
        deckFlame.scale = SCNVector3(0.78, 0.78, 0.78)
        deckFlame.opacity = 0
        vessel.addChildNode(deckFlame)
        return vessel
    }

    private static func weatherBoat(_ boat: SCNNode) {
        boat.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }
            geometry.materials = geometry.materials.map { source in
                let material = (source.copy() as? SCNMaterial) ?? source
                switch material.name {
                case "LF_BoatHull":
                    material.diffuse.contents = UIColor(rgb: 0x5B594D)
                case "LF_BoatDeck":
                    material.diffuse.contents = UIColor(rgb: 0x3B3128)
                case "LF_BoatMainSail", "LF_BoatJib":
                    material.diffuse.contents = UIColor(rgb: 0x777468)
                    material.roughness.contents = 1.0
                case "LF_BoatStripe", "LF_BoatFlag":
                    node.opacity = 0.18
                case "LF_BoatWood", "LF_BoatWoodDark":
                    material.diffuse.contents = UIColor(rgb: 0x34251D)
                case "LF_BoatMetal":
                    material.diffuse.contents = UIColor(rgb: 0x4C3D35)
                case "LF_BoatLanternGlow":
                    material.emission.intensity = 0.12
                default:
                    break
                }
                return material
            }
        }
    }

    private static func makeWeatheredDeck() -> SCNNode {
        let root = SCNNode()
        root.name = "prologueWeatheredDeck"
        let colors: [UInt] = [0x44352A, 0x514033, 0x382B24, 0x5A4736]
        for index in 0..<7 {
            let plank = SCNBox(
                width: 1.74 + CGFloat(index % 2) * 0.10,
                height: 0.035,
                length: 0.13,
                chamferRadius: 0.012
            )
            plank.firstMaterial = material(colors[index % colors.count], roughness: 1)
            let node = SCNNode(geometry: plank)
            node.position = SCNVector3(
                -0.08 + Float(index % 3) * 0.015,
                0.525 + Float(index % 2) * 0.006,
                -0.40 + Float(index) * 0.135
            )
            node.eulerAngles.y = Float(index % 3 - 1) * 0.012
            root.addChildNode(node)
        }

        let railMaterial = material(0x30231D, roughness: 0.96)
        for (x, z) in [(-0.72 as Float, -0.50 as Float), (0.45, -0.50), (-0.70, 0.50)] {
            let post = SCNCylinder(radius: 0.028, height: 0.46)
            post.radialSegmentCount = 7
            post.firstMaterial = railMaterial
            let postNode = SCNNode(geometry: post)
            postNode.position = SCNVector3(x, 0.74, z)
            postNode.eulerAngles.z = x > 0 ? 0.13 : -0.05
            root.addChildNode(postNode)
        }
        return root
    }

    private static func makeJournal() -> SCNNode {
        let root = SCNNode()
        root.name = "prologueJournal"

        let coverMaterial = material(0x46352B, roughness: 0.88)
        let pageMaterial = material(0xE7D6AA, roughness: 0.98)
        let edgeMaterial = material(0xBDAE87, roughness: 1)

        let cover = SCNBox(width: 0.82, height: 0.045, length: 0.56, chamferRadius: 0.035)
        cover.firstMaterial = coverMaterial
        let coverNode = SCNNode(geometry: cover)
        root.addChildNode(coverNode)

        for layer in 0..<3 {
            let pages = SCNBox(
                width: 0.74 - CGFloat(layer) * 0.014,
                height: 0.014,
                length: 0.50 - CGFloat(layer) * 0.008,
                chamferRadius: 0.022
            )
            pages.firstMaterial = layer == 0 ? edgeMaterial : pageMaterial
            let pagesNode = SCNNode(geometry: pages)
            pagesNode.position.y = 0.030 + Float(layer) * 0.012
            root.addChildNode(pagesNode)
        }

        let rightPage = SCNBox(width: 0.36, height: 0.012, length: 0.49, chamferRadius: 0.018)
        rightPage.firstMaterial = pageMaterial
        let rightPageNode = SCNNode(geometry: rightPage)
        rightPageNode.position = SCNVector3(0.19, 0.078, 0)
        root.addChildNode(rightPageNode)

        let hinge = SCNNode()
        hinge.name = "prologueJournalPageHinge"
        hinge.position = SCNVector3(0, 0.084, 0)
        hinge.eulerAngles.z = .pi - 0.04
        let leftPage = SCNBox(width: 0.36, height: 0.010, length: 0.49, chamferRadius: 0.018)
        leftPage.firstMaterial = pageMaterial
        let leftPageNode = SCNNode(geometry: leftPage)
        leftPageNode.position.x = -0.19
        hinge.addChildNode(leftPageNode)
        root.addChildNode(hinge)

        let spine = SCNCylinder(radius: 0.026, height: 0.53)
        spine.radialSegmentCount = 10
        spine.firstMaterial = coverMaterial
        let spineNode = SCNNode(geometry: spine)
        spineNode.position = SCNVector3(0, 0.044, 0)
        spineNode.eulerAngles.x = .pi / 2
        root.addChildNode(spineNode)
        return root
    }

    /// PhoenixAnimatorが振り子制御する既存`lantern`ノードは残し、その内側だけを
    /// 航海用ランタンと、肘の曲がりが読める保持腕へ差し替える。
    private static func installMarinerLantern(on lantern: SCNNode, navigator: SCNNode) {
        // 既存の簡易コーン/球はAnimatorの探索契約を壊さず非表示にする。
        lantern.childNodes.forEach { $0.isHidden = true }
        lantern.addChildNode(makeMarinerLantern())

        guard let arm = navigator.childNode(withName: "armR", recursively: true) else { return }

        // 最終ビート以外は元の腕形状をそのまま見せ、回帰を避ける。
        let nativeArm = SCNNode()
        nativeArm.name = "prologueNativeLanternArm"
        let nativeChildren = arm.childNodes.filter { $0 !== lantern }
        for child in nativeChildren {
            child.removeFromParentNode()
            nativeArm.addChildNode(child)
        }
        arm.addChildNode(nativeArm)

        let holdingArm = makeLanternHoldingArm()
        holdingArm.opacity = 0
        arm.addChildNode(holdingArm)
    }

    /// 肩を起点に、わずかに前へ出た肘から手首へ戻る二分割の腕。
    /// ランタンの親ピボットは元の手元に置いたままなので、Animatorの鉛直補正も保たれる。
    private static func makeLanternHoldingArm() -> SCNNode {
        let root = SCNNode()
        root.name = "prologueLanternHoldingArm"

        let skin = material(0xF0997B, roughness: 0.72)
        let sleeve = material(0x7A3B22, roughness: 0.84)
        let glove = material(0x4A1B0C, roughness: 0.90)

        let shoulder = SCNNode(geometry: SCNSphere(radius: 0.047))
        shoulder.geometry?.firstMaterial = skin
        shoulder.geometry?.subdivisionLevel = 1
        shoulder.position = SCNVector3(0, -0.012, 0)
        root.addChildNode(shoulder)

        let elbow = SCNVector3(0.065, -0.145, 0.035)
        root.addChildNode(makeRod(
            from: SCNVector3(0, -0.025, 0),
            to: elbow,
            radius: 0.037,
            material: skin
        ))
        root.addChildNode(makeRod(
            from: SCNVector3(0.025, -0.082, 0.016),
            to: elbow,
            radius: 0.052,
            material: sleeve
        ))

        let elbowJoint = SCNNode(geometry: SCNSphere(radius: 0.043))
        elbowJoint.geometry?.firstMaterial = sleeve
        elbowJoint.geometry?.subdivisionLevel = 1
        elbowJoint.position = elbow
        root.addChildNode(elbowJoint)

        let wrist = SCNVector3(0.022, -0.267, 0.008)
        root.addChildNode(makeRod(
            from: elbow,
            to: wrist,
            radius: 0.033,
            material: skin
        ))

        let cuff = SCNTorus(ringRadius: 0.038, pipeRadius: 0.010)
        cuff.ringSegmentCount = 12
        cuff.pipeSegmentCount = 5
        cuff.firstMaterial = sleeve
        let cuffNode = SCNNode(geometry: cuff)
        cuffNode.position = wrist
        root.addChildNode(cuffNode)

        let hand = SCNNode(geometry: SCNSphere(radius: 0.049))
        hand.geometry?.firstMaterial = glove
        hand.geometry?.subdivisionLevel = 1
        hand.position = SCNVector3(0.037, -0.290, 0.005)
        hand.scale = SCNVector3(0.92, 1.05, 0.92)
        root.addChildNode(hand)

        // 指が持ち手へ掛かる小さなシルエットを足し、手とランタンの隙間を消す。
        root.addChildNode(makeRod(
            from: SCNVector3(0.056, -0.295, 0.014),
            to: SCNVector3(0.073, -0.335, 0.006),
            radius: 0.012,
            material: glove,
            radialSegments: 6
        ))
        return root
    }

    /// 画像を使わず、金属・ガラス・炎をSceneKitプリミティブだけで組む航海灯。
    private static func makeMarinerLantern() -> SCNNode {
        let root = SCNNode()
        root.name = "prologueMarinerLantern"

        let brass = material(0x8B6735, roughness: 0.46)
        brass.metalness.contents = 0.68
        let darkBrass = material(0x3E3021, roughness: 0.62)
        darkBrass.metalness.contents = 0.76

        let glass = SCNMaterial()
        glass.lightingModel = .physicallyBased
        glass.diffuse.contents = UIColor(rgb: 0xBFD9D3).withAlphaComponent(0.20)
        glass.specular.contents = UIColor.white.withAlphaComponent(0.86)
        glass.roughness.contents = 0.08
        glass.metalness.contents = 0
        glass.fresnelExponent = 1.8
        glass.blendMode = .alpha
        glass.isDoubleSided = true
        glass.writesToDepthBuffer = false
        glass.readsFromDepthBuffer = true

        // 指で提げる楕円形のベイルハンドル。短いロッドで曲線を作る。
        let handleSteps = 10
        var handlePoints: [SCNVector3] = []
        for index in 0...handleSteps {
            let angle = Float.pi * Float(index) / Float(handleSteps)
            handlePoints.append(SCNVector3(
                cos(angle) * 0.092,
                -0.108 + sin(angle) * 0.103,
                0
            ))
        }
        for index in 0..<handleSteps {
            root.addChildNode(makeRod(
                from: handlePoints[index],
                to: handlePoints[index + 1],
                radius: 0.010,
                material: darkBrass,
                radialSegments: 6
            ))
        }
        root.addChildNode(makeRod(
            from: SCNVector3(-0.028, -0.008, 0),
            to: SCNVector3(0.028, -0.008, 0),
            radius: 0.013,
            material: brass,
            radialSegments: 7
        ))

        for x: Float in [-0.092, 0.092] {
            let rivet = SCNNode(geometry: SCNSphere(radius: 0.018))
            rivet.geometry?.firstMaterial = brass
            rivet.position = SCNVector3(x, -0.108, 0)
            root.addChildNode(rivet)
        }

        let chimney = SCNCylinder(radius: 0.034, height: 0.038)
        chimney.radialSegmentCount = 10
        chimney.firstMaterial = darkBrass
        let chimneyNode = SCNNode(geometry: chimney)
        chimneyNode.position.y = -0.096
        root.addChildNode(chimneyNode)

        let crown = SCNCone(topRadius: 0.043, bottomRadius: 0.106, height: 0.064)
        crown.radialSegmentCount = 12
        crown.firstMaterial = brass
        let crownNode = SCNNode(geometry: crown)
        crownNode.position.y = -0.143
        root.addChildNode(crownNode)

        let chamber = SCNCylinder(radius: 0.074, height: 0.172)
        chamber.radialSegmentCount = 18
        chamber.firstMaterial = glass
        let chamberNode = SCNNode(geometry: chamber)
        chamberNode.name = "prologueLanternGlass"
        chamberNode.position.y = -0.256
        chamberNode.renderingOrder = 44
        root.addChildNode(chamberNode)

        for y: Float in [-0.169, -0.343] {
            let ring = SCNTorus(ringRadius: 0.078, pipeRadius: 0.009)
            ring.ringSegmentCount = 16
            ring.pipeSegmentCount = 5
            ring.firstMaterial = darkBrass
            let ringNode = SCNNode(geometry: ring)
            ringNode.position.y = y
            root.addChildNode(ringNode)
        }

        // 四本のガードがガラスを守る、古い船灯らしいケージ形状。
        for angle in stride(from: Float.pi / 4, to: Float.pi * 2, by: Float.pi / 2) {
            let x = cos(angle) * 0.079
            let z = sin(angle) * 0.079
            root.addChildNode(makeRod(
                from: SCNVector3(x, -0.166, z),
                to: SCNVector3(x, -0.346, z),
                radius: 0.008,
                material: darkBrass,
                radialSegments: 6
            ))
        }

        // ガラス面に細い反射を入れ、透明体であることを小画面でも読ませる。
        let highlightMaterial = SCNMaterial()
        highlightMaterial.lightingModel = .constant
        highlightMaterial.diffuse.contents = UIColor(rgb: 0xD8ECE7).withAlphaComponent(0.28)
        highlightMaterial.emission.contents = UIColor(rgb: 0xB9D8D2)
        highlightMaterial.emission.intensity = 0.14
        highlightMaterial.blendMode = .add
        highlightMaterial.writesToDepthBuffer = false
        let highlight = SCNBox(width: 0.008, height: 0.128, length: 0.003, chamferRadius: 0.002)
        highlight.firstMaterial = highlightMaterial
        let highlightNode = SCNNode(geometry: highlight)
        highlightNode.position = SCNVector3(-0.026, -0.254, 0.074)
        highlightNode.renderingOrder = 45
        root.addChildNode(highlightNode)

        let lowerCanopy = SCNCone(topRadius: 0.102, bottomRadius: 0.074, height: 0.055)
        lowerCanopy.radialSegmentCount = 12
        lowerCanopy.firstMaterial = brass
        let lowerCanopyNode = SCNNode(geometry: lowerCanopy)
        lowerCanopyNode.position.y = -0.371
        root.addChildNode(lowerCanopyNode)

        let reservoir = SCNCylinder(radius: 0.074, height: 0.056)
        reservoir.radialSegmentCount = 12
        reservoir.firstMaterial = darkBrass
        let reservoirNode = SCNNode(geometry: reservoir)
        reservoirNode.position.y = -0.416
        root.addChildNode(reservoirNode)

        let foot = SCNCylinder(radius: 0.091, height: 0.024)
        foot.radialSegmentCount = 12
        foot.firstMaterial = brass
        let footNode = SCNNode(geometry: foot)
        footNode.position.y = -0.455
        root.addChildNode(footNode)

        let flame = makeLanternFlame()
        flame.position.y = -0.335
        flame.opacity = 0
        root.addChildNode(flame)
        return root
    }

    private static func makeLanternFlame() -> SCNNode {
        let root = SCNNode()
        root.name = "prologueHeldFlame"

        let outerMaterial = material(
            0xEF7B32,
            roughness: 0.22,
            emission: 0xFF8538,
            emissionIntensity: 1.4
        )
        let coreMaterial = material(
            0xFFE2A0,
            roughness: 0.18,
            emission: 0xFFD990,
            emissionIntensity: 2.2
        )

        let outer = SCNSphere(radius: 0.043)
        outer.segmentCount = 10
        outer.firstMaterial = outerMaterial
        let outerNode = SCNNode(geometry: outer)
        outerNode.position.y = 0.068
        outerNode.scale = SCNVector3(0.78, 1.28, 0.72)
        root.addChildNode(outerNode)

        let tip = SCNCone(topRadius: 0.004, bottomRadius: 0.027, height: 0.090)
        tip.radialSegmentCount = 8
        tip.firstMaterial = outerMaterial
        let tipNode = SCNNode(geometry: tip)
        tipNode.position = SCNVector3(-0.006, 0.135, 0)
        tipNode.eulerAngles.z = -0.12
        root.addChildNode(tipNode)

        let core = SCNSphere(radius: 0.027)
        core.segmentCount = 9
        core.firstMaterial = coreMaterial
        let coreNode = SCNNode(geometry: core)
        coreNode.position = SCNVector3(0.006, 0.052, 0.006)
        coreNode.scale = SCNVector3(0.72, 1.12, 0.72)
        root.addChildNode(coreNode)

        let lightNode = SCNNode()
        lightNode.name = "prologueHeldFlameLight"
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.light?.color = UIColor(rgb: 0xFF9A55)
        lightNode.light?.intensity = 0
        lightNode.light?.attenuationStartDistance = 0.06
        lightNode.light?.attenuationEndDistance = 1.45
        lightNode.light?.castsShadow = false
        lightNode.position.y = 0.085
        root.addChildNode(lightNode)
        return root
    }

    private static func makeRod(
        from: SCNVector3,
        to: SCNVector3,
        radius: CGFloat,
        material: SCNMaterial,
        radialSegments: Int = 8
    ) -> SCNNode {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let dz = to.z - from.z
        let length = sqrt(dx * dx + dy * dy + dz * dz)
        let geometry = SCNCylinder(radius: radius, height: CGFloat(length))
        geometry.radialSegmentCount = radialSegments
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(
            (from.x + to.x) / 2,
            (from.y + to.y) / 2,
            (from.z + to.z) / 2
        )
        // SCNCylinderのlocal +Yをロッド方向へ回す。look-atは縦棒でupと
        // directionが共線になり基底が退化するため、明示的なaxis-angleを使う。
        if length > 0.000_001 {
            let directionX = dx / length
            let directionY = dy / length
            let directionZ = dz / length
            let axisX = directionZ
            let axisZ = -directionX
            let axisLength = sqrt(axisX * axisX + axisZ * axisZ)
            if axisLength > 0.000_001 {
                let angle = acos(min(max(directionY, -1), 1))
                node.rotation = SCNVector4(axisX / axisLength, 0, axisZ / axisLength, angle)
            } else if directionY < 0 {
                node.eulerAngles.x = Float.pi
            }
        }
        return node
    }

    private static func makeFlame(name: String, lightName: String) -> SCNNode {
        let root = SCNNode()
        root.name = name

        let glowMaterial = material(
            0xE36B2D,
            roughness: 0.30,
            emission: 0xFF7B31,
            emissionIntensity: 0.8
        )
        let coreMaterial = material(
            0xFFD27A,
            roughness: 0.24,
            emission: 0xFFD27A,
            emissionIntensity: 1.6
        )

        let outer = SCNCone(topRadius: 0.012, bottomRadius: 0.085, height: 0.25)
        outer.radialSegmentCount = 7
        outer.firstMaterial = glowMaterial
        let outerNode = SCNNode(geometry: outer)
        outerNode.position.y = 0.125
        outerNode.eulerAngles.z = -0.10
        root.addChildNode(outerNode)

        let core = SCNCone(topRadius: 0.006, bottomRadius: 0.045, height: 0.15)
        core.radialSegmentCount = 7
        core.firstMaterial = coreMaterial
        let coreNode = SCNNode(geometry: core)
        coreNode.position = SCNVector3(0.015, 0.085, 0.008)
        root.addChildNode(coreNode)

        let lightNode = SCNNode()
        lightNode.name = lightName
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.light?.color = UIColor(rgb: 0xFF974D)
        lightNode.light?.intensity = 0
        lightNode.light?.attenuationStartDistance = 0.1
        lightNode.light?.attenuationEndDistance = 1.8
        lightNode.light?.castsShadow = false
        lightNode.light?.shadowRadius = 5
        lightNode.position.y = 0.13
        root.addChildNode(lightNode)
        return root
    }

    private static func makeFog() -> SCNNode {
        let root = SCNNode()
        root.name = "prologueFog"
        let fogMaterial = material(0xA4B8AE, roughness: 1)
        fogMaterial.lightingModel = .constant
        fogMaterial.diffuse.contents = UIColor(rgb: 0xA4B8AE).withAlphaComponent(0.055)
        fogMaterial.blendMode = .alpha
        fogMaterial.writesToDepthBuffer = false
        fogMaterial.readsFromDepthBuffer = true

        for index in 0..<14 {
            let sphere = SCNSphere(radius: 1)
            sphere.segmentCount = 10
            sphere.firstMaterial = fogMaterial
            let bank = SCNNode(geometry: sphere)
            bank.name = "prologueFogBank\(index)"
            bank.scale = SCNVector3(
                4.8 + Float(index % 4) * 1.25,
                0.48 + Float(index % 3) * 0.16,
                2.8 + Float(index % 5) * 0.52
            )
            bank.position = SCNVector3(
                -14 + Float(index % 7) * 4.7,
                0.52 + Float(index % 3) * 0.62,
                -2.5 - Float(index % 5) * 4.5
            )
            bank.renderingOrder = 20 + index
            root.addChildNode(bank)
        }
        return root
    }

    private static func makeRouteMarkers() -> SCNNode {
        let root = SCNNode()
        root.name = "prologueRouteMarkers"
        let stone = material(0x354443, roughness: 1)
        let metal = material(0x675A47, roughness: 0.82)
        let dimGlow = material(
            0xA47942,
            roughness: 0.45,
            emission: 0xC79047,
            emissionIntensity: 0.45
        )

        for index in 0..<6 {
            let marker = SCNNode()
            marker.name = "prologueRouteMarker\(index)"
            let progress = Float(index + 1) / 7
            marker.position = SCNVector3(
                progress * 5 + (index.isMultiple(of: 2) ? -0.42 : 0.38),
                0.035,
                -2.2 - progress * 11.6
            )

            let base = SCNCylinder(radius: 0.24, height: 0.10)
            base.radialSegmentCount = 8
            base.firstMaterial = stone
            marker.addChildNode(SCNNode(geometry: base))

            let post = SCNCylinder(radius: 0.035, height: 0.62)
            post.radialSegmentCount = 7
            post.firstMaterial = metal
            let postNode = SCNNode(geometry: post)
            postNode.position.y = 0.34
            marker.addChildNode(postNode)

            let ring = SCNTorus(ringRadius: 0.11, pipeRadius: 0.022)
            ring.ringSegmentCount = 16
            ring.pipeSegmentCount = 5
            ring.firstMaterial = dimGlow
            let ringNode = SCNNode(geometry: ring)
            ringNode.position.y = 0.67
            ringNode.eulerAngles.x = .pi / 2
            marker.addChildNode(ringNode)
            root.addChildNode(marker)
        }
        return root
    }

    private static func makeLighthouse() -> SCNNode {
        let root = SCNNode()
        root.name = "prologueLighthouse"
        root.position = SCNVector3(5, -0.08, -15)

        let rockMaterial = material(0x263837, roughness: 1)
        let towerMaterial = material(0x67716B, roughness: 0.98)
        let ironMaterial = material(0x26302F, roughness: 0.82)
        let lampMaterial = material(
            0xE7BD67,
            roughness: 0.28,
            emission: 0xFFD98A,
            emissionIntensity: 4.0
        )

        let rock = SCNCone(topRadius: 0.78, bottomRadius: 1.45, height: 0.48)
        rock.radialSegmentCount = 9
        rock.firstMaterial = rockMaterial
        let rockNode = SCNNode(geometry: rock)
        rockNode.position.y = 0.18
        root.addChildNode(rockNode)

        let tower = SCNCone(topRadius: 0.42, bottomRadius: 0.72, height: 3.5)
        tower.radialSegmentCount = 14
        tower.firstMaterial = towerMaterial
        let towerNode = SCNNode(geometry: tower)
        towerNode.position.y = 2.05
        root.addChildNode(towerNode)

        let balcony = SCNTorus(ringRadius: 0.58, pipeRadius: 0.055)
        balcony.ringSegmentCount = 24
        balcony.pipeSegmentCount = 6
        balcony.firstMaterial = ironMaterial
        let balconyNode = SCNNode(geometry: balcony)
        balconyNode.position.y = 3.86
        root.addChildNode(balconyNode)

        let room = SCNCylinder(radius: 0.43, height: 0.68)
        room.radialSegmentCount = 10
        room.firstMaterial = ironMaterial
        let roomNode = SCNNode(geometry: room)
        roomNode.position.y = 4.16
        root.addChildNode(roomNode)

        let rotor = SCNNode()
        rotor.name = "prologueLighthouseRotor"
        rotor.position.y = 4.18
        let lamp = SCNSphere(radius: 0.18)
        lamp.segmentCount = 14
        lamp.firstMaterial = lampMaterial
        let lampNode = SCNNode(geometry: lamp)
        lampNode.name = "prologueLighthouseLamp"
        rotor.addChildNode(lampNode)

        let beamMaterial = material(0xF0D9A4, roughness: 1)
        beamMaterial.lightingModel = .constant
        beamMaterial.diffuse.contents = UIColor(rgb: 0xF0D9A4).withAlphaComponent(0.075)
        beamMaterial.emission.contents = UIColor(rgb: 0xF0D9A4)
        beamMaterial.emission.intensity = 0.22
        beamMaterial.blendMode = .add
        beamMaterial.writesToDepthBuffer = false
        let beam = SCNCone(topRadius: 1.35, bottomRadius: 0.07, height: 12)
        beam.radialSegmentCount = 18
        beam.firstMaterial = beamMaterial
        let beamNode = SCNNode(geometry: beam)
        beamNode.name = "prologueLighthouseBeam"
        beamNode.position = SCNVector3(0, 0, 6)
        beamNode.eulerAngles.x = .pi / 2
        beamNode.opacity = 0.34
        rotor.addChildNode(beamNode)

        let lightNode = SCNNode()
        lightNode.name = "prologueLighthouseLight"
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.light?.color = UIColor(rgb: 0xFFD98A)
        lightNode.light?.intensity = 1_050
        lightNode.light?.attenuationStartDistance = 0.4
        lightNode.light?.attenuationEndDistance = 17
        rotor.addChildNode(lightNode)
        root.addChildNode(rotor)

        let roof = SCNCone(topRadius: 0.02, bottomRadius: 0.58, height: 0.52)
        roof.radialSegmentCount = 10
        roof.firstMaterial = ironMaterial
        let roofNode = SCNNode(geometry: roof)
        roofNode.position.y = 4.75
        root.addChildNode(roofNode)
        return root
    }

    private static func addLights(to root: SCNNode) {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(rgb: 0x8CA49B)
        ambient.light?.intensity = 330
        root.addChildNode(ambient)

        let moon = SCNNode()
        moon.light = SCNLight()
        moon.light?.type = .directional
        moon.light?.color = UIColor(rgb: 0xC4D1C9)
        moon.light?.intensity = 720
        moon.position = SCNVector3(-7, 10, 6)
        moon.look(at: SCNVector3Zero)
        root.addChildNode(moon)

        let seaFill = SCNNode()
        seaFill.light = SCNLight()
        seaFill.light?.type = .directional
        seaFill.light?.color = UIColor(rgb: 0x315E59)
        seaFill.light?.intensity = 190
        seaFill.position = SCNVector3(8, 4, -8)
        seaFill.look(at: SCNVector3Zero)
        root.addChildNode(seaFill)
    }

    private static func addCamera(to root: SCNNode) {
        let target = SCNNode()
        target.name = cameraTargetName
        target.position = cameraPoses[0].target
        root.addChildNode(target)

        let camera = SCNNode()
        camera.name = cameraName
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = cameraPoses[0].fieldOfView
        camera.camera?.zNear = 0.06
        camera.camera?.zFar = 240
        camera.camera?.wantsHDR = true
        camera.camera?.wantsExposureAdaptation = false
        camera.camera?.exposureOffset = -0.30
        camera.camera?.contrast = 0.13
        camera.camera?.saturation = 0.76
        camera.camera?.bloomIntensity = 0.14
        camera.camera?.bloomThreshold = 1.08
        camera.camera?.bloomBlurRadius = 7
        camera.camera?.vignettingIntensity = 0.74
        camera.camera?.vignettingPower = 0.82
        camera.position = cameraPoses[0].position

        let look = SCNLookAtConstraint(target: target)
        look.isGimbalLockEnabled = true
        look.localFront = SCNVector3(0, 0, -1)
        camera.constraints = [look]
        root.addChildNode(camera)
    }

    private static func material(
        _ color: UInt,
        roughness: CGFloat,
        emission: UInt? = nil,
        emissionIntensity: CGFloat = 0
    ) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(rgb: color)
        material.roughness.contents = roughness
        material.metalness.contents = 0
        if let emission {
            material.emission.contents = UIColor(rgb: emission)
            material.emission.intensity = emissionIntensity
        }
        return material
    }
}
