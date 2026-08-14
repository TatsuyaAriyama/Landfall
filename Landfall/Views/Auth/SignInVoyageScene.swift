import SceneKit
import SwiftUI
import UIKit

/// 最新Web `SignInVoyageWorld` と同じ、ログイン専用の航海背景。
/// ホームや港のシーンを変更せず、共有の船・航海士・島だけをログイン用に配置し直す。
struct SignInVoyageSceneView: UIViewRepresentable {
    let timeOfDay: AftideHomeTimeOfDay
    let date: Date
    let animate: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = SignInVoyageSceneFactory.backgroundColor(for: timeOfDay)
        view.isOpaque = true
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.isUserInteractionEnabled = false
        view.preferredFramesPerSecond = 60
        view.scene = SignInVoyageSceneFactory.makeScene(timeOfDay: timeOfDay, date: date)
        view.pointOfView = view.scene?.rootNode.childNode(
            withName: "camera",
            recursively: false
        )
        view.delegate = context.coordinator
        context.coordinator.bind(view: view, timeOfDay: timeOfDay)
        context.coordinator.setDate(date)
        context.coordinator.setAnimating(animate)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if context.coordinator.timeOfDay != timeOfDay {
            view.backgroundColor = SignInVoyageSceneFactory.backgroundColor(for: timeOfDay)
            view.scene = SignInVoyageSceneFactory.makeScene(timeOfDay: timeOfDay, date: date)
            view.pointOfView = view.scene?.rootNode.childNode(
                withName: "camera",
                recursively: false
            )
            context.coordinator.bind(view: view, timeOfDay: timeOfDay)
        }
        context.coordinator.setDate(date)
        context.coordinator.updateViewport(view.bounds.size)
        context.coordinator.setAnimating(animate)
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        private struct Gull {
            let radius: Float
            let height: Float
            let omega: Float
            let flap: Float
            let phase: Float
        }

        var timeOfDay: AftideHomeTimeOfDay = .night

        private weak var view: SCNView?
        private weak var camera: SCNNode?
        private weak var moon: SCNNode?
        private weak var bob: SCNNode?
        private weak var wake: SCNNode?
        private var gulls: [SCNNode] = []
        private var baseCamera = SCNVector3(-5.8, 3, 11.8)
        private var portrait = true
        private var viewportConfigured = false
        private var startTime: TimeInterval?
        private var lastTime: TimeInterval = 0
        private let sailor = PhoenixAnimator()

        /// Web `SIGN_IN_GULLS` と同じ6羽。
        private let flock: [Gull] = [
            Gull(radius: 3.8, height: 2.5, omega: 0.08, flap: 2.1, phase: 0),
            Gull(radius: 4.8, height: 3.1, omega: -0.06, flap: 1.7, phase: 1.2),
            Gull(radius: 4.2, height: 2.1, omega: 0.10, flap: 2.4, phase: 2.4),
            Gull(radius: 5.4, height: 3.5, omega: -0.05, flap: 1.6, phase: 3.6),
            Gull(radius: 3.5, height: 3.0, omega: 0.11, flap: 2.3, phase: 4.8),
            Gull(radius: 5.8, height: 2.6, omega: 0.045, flap: 1.8, phase: 5.8)
        ]

        func bind(view: SCNView, timeOfDay: AftideHomeTimeOfDay) {
            self.view = view
            self.timeOfDay = timeOfDay
            camera = view.scene?.rootNode.childNode(withName: "camera", recursively: false)
            moon = view.scene?.rootNode.childNode(
                withName: LandfallMoonEffects.rootNodeName,
                recursively: false
            )
            bob = view.scene?.rootNode.childNode(withName: "boatBob", recursively: true)
            wake = view.scene?.rootNode.childNode(withName: "wake", recursively: true)
            gulls = view.scene?.rootNode
                .childNode(withName: "gulls", recursively: false)?
                .childNodes ?? []
            startTime = nil
            lastTime = 0
            viewportConfigured = false
            sailor.pose = .idle
            sailor.animate = true
            updateViewport(view.bounds.size)
            applyFrame(time: 0, delta: 0)
        }

        func setDate(_ date: Date) {
            LandfallMoonEffects.update(moon, phase: .current(at: date))
        }

        func updateViewport(_ size: CGSize) {
            guard size.width > 0, size.height > 0 else { return }
            let nextPortrait = size.width / max(size.height, 1) < 0.72
            guard nextPortrait != portrait || !viewportConfigured else { return }
            portrait = nextPortrait
            viewportConfigured = true
            baseCamera = nextPortrait
                ? SCNVector3(-5.8, 3, 11.8)
                : SCNVector3(-6.5, 2.55, 9.8)
            applyCamera(time: 0)
        }

        func setAnimating(_ value: Bool) {
            guard let view else { return }
            view.rendersContinuously = value
            view.isPlaying = value
            if !value {
                applyFrame(time: 0, delta: 0)
                view.setNeedsDisplay()
            }
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard view?.isPlaying == true else { return }
            if startTime == nil {
                startTime = time
                lastTime = time
            }
            let elapsed = Float(time - (startTime ?? time))
            let delta = Float(min(max(time - lastTime, 0), 0.1))
            lastTime = time
            applyFrame(time: elapsed, delta: delta)
        }

        private func applyFrame(time: Float, delta: Float) {
            if let bob {
                bob.position.y = sin(time * 0.8) * 0.06
                bob.eulerAngles.z = sin(time * 0.6) * 0.03
                bob.eulerAngles.x = sin(time * 0.5 + 1.2) * 0.015
                bob.childNode(withName: "boatFlag", recursively: true)?
                    .eulerAngles.y = sin(time * 5.2) * 0.22
            }
            wake?.opacity = CGFloat(0.34 + sin(time * 1.4) * 0.07)

            if let scene = view?.scene {
                sailor.bindIfNeeded(scene)
                sailor.step(t: time, dt: delta)
            }

            let center = SCNVector3(1.2, 0, -1.5)
            for (index, bird) in gulls.enumerated() {
                guard flock.indices.contains(index) else {
                    bird.isHidden = true
                    continue
                }
                let config = flock[index]
                let angle = config.phase + time * config.omega
                bird.position = SCNVector3(
                    center.x + cos(angle) * config.radius,
                    config.height + sin(time * 0.4 + config.phase) * 0.22,
                    center.z + sin(angle) * config.radius
                )
                let velocityX = -sin(angle) * config.omega
                let velocityZ = cos(angle) * config.omega
                bird.eulerAngles.y = atan2(-velocityX, -velocityZ)
                bird.eulerAngles.z = config.omega > 0 ? -0.18 : 0.18
                let beat = -0.22 + sin(time * config.flap + config.phase) * 0.34
                bird.childNode(withName: "leftWing", recursively: false)?
                    .eulerAngles.z = beat
                bird.childNode(withName: "rightWing", recursively: false)?
                    .eulerAngles.z = -beat
            }
            applyCamera(time: time)
        }

        private func applyCamera(time: Float) {
            guard let camera else { return }
            camera.position = SCNVector3(
                baseCamera.x + sin(time * 0.12) * 0.08,
                baseCamera.y + sin(time * 0.2) * 0.035,
                baseCamera.z + cos(time * 0.12) * 0.06
            )
            camera.look(
                at: SCNVector3(0.2, 0.85, -0.5),
                up: SCNVector3(0, 1, 0),
                localFront: SCNVector3(0, 0, -1)
            )
        }
    }
}

private enum SignInVoyageSceneFactory {
    private struct Palette {
        let sky: UInt
        let fog: UInt
        let sea: UInt
        let seaDeep: UInt
        let reflection: UInt
        let ambient: UInt
        let key: UInt
        let fill: UInt
        let stars: Int
        let moon: Bool
    }

    static func makeScene(timeOfDay: AftideHomeTimeOfDay, date: Date) -> SCNScene {
        let palette = palette(for: timeOfDay)
        let scene = VoyageSceneKit.makeVoyagingScene(
            showIsland: true,
            timeOfDay: timeOfDay,
            date: date
        )
        scene.background.contents = UIColor(rgb: palette.sky)
        scene.fogColor = UIColor(rgb: palette.fog)
        scene.fogStartDistance = 13
        scene.fogEndDistance = 35

        restageStars(in: scene, count: palette.stars)
        restageCelestial(in: scene, timeOfDay: timeOfDay, date: date, palette: palette)
        recolorSea(in: scene, palette: palette)
        recolorLights(in: scene, palette: palette)

        if let island = scene.rootNode.childNode(
            withName: "approachingIsland",
            recursively: false
        ) {
            // Web: outer [0.8,-0.05,-6.3] + Island local [3.5,0,-0.9]。
            island.position = SCNVector3(4.3, -0.05, -7.2)
            island.scale = SCNVector3(0.82, 0.82, 0.82)
        }
        if let travel = scene.rootNode.childNode(withName: "travel", recursively: false) {
            travel.position = SCNVector3(-1.65, 0, 0.45)
            travel.eulerAngles.y = 0.1
            travel.scale = SCNVector3(0.68, 0.68, 0.68)
        }
        scene.rootNode.childNode(withName: "gulls", recursively: false)?
            .isHidden = timeOfDay == .night

        if let camera = scene.rootNode.childNode(withName: "camera", recursively: false) {
            camera.camera?.fieldOfView = 40
            camera.camera?.projectionDirection = .vertical
            camera.camera?.zNear = 0.1
            camera.camera?.zFar = 200
        }
        return scene
    }

    static func backgroundColor(for timeOfDay: AftideHomeTimeOfDay) -> UIColor {
        UIColor(rgb: palette(for: timeOfDay).sky)
    }

    private static func restageStars(in scene: SCNScene, count: Int) {
        for node in scene.rootNode.childNodes
        where node.geometry?.elements.first?.primitiveType == .point {
            node.removeFromParentNode()
        }
        guard count > 0 else { return }
        let stars = VoyageSceneKit.makeStars(count: count)
        stars.name = "signinStars"
        stars.geometry?.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.82)
        scene.rootNode.addChildNode(stars)
    }

    private static func restageCelestial(
        in scene: SCNScene,
        timeOfDay: AftideHomeTimeOfDay,
        date: Date,
        palette: Palette
    ) {
        let positions: [AftideHomeTimeOfDay: SCNVector3] = [
            .morning: SCNVector3(-5.4, 2.1, -8.5),
            .day: SCNVector3(0.8, 6.1, -9.5),
            .evening: SCNVector3(5.8, 2, -8.5),
            .night: SCNVector3(5.6, 4.2, -8.5)
        ]
        if palette.moon,
           let moon = scene.rootNode.childNode(
               withName: LandfallMoonEffects.rootNodeName,
               recursively: false
           ) {
            moon.position = positions[timeOfDay] ?? SCNVector3(5.6, 4.2, -8.5)
            moon.scale = SCNVector3(0.38, 0.38, 0.38)
            LandfallMoonEffects.update(moon, phase: .current(at: date))
            return
        }

        guard let node = scene.rootNode.childNode(
            withName: "voyagingSun",
            recursively: false
        ), let sphere = node.geometry as? SCNSphere else { return }

        node.name = "signinCelestial"
        node.position = positions[timeOfDay] ?? SCNVector3(5.6, 4.2, -8.5)
        node.scale = SCNVector3(1, 1, 1)
        sphere.radius = 0.72
        let material = sphere.firstMaterial ?? SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(rgb: palette.reflection)
        material.emission.contents = UIColor(rgb: palette.reflection)
        material.emission.intensity = 0.35
        sphere.firstMaterial = material
    }

    private static func recolorSea(in scene: SCNScene, palette: Palette) {
        let root = scene.rootNode.childNode(withName: "voyagingSea", recursively: false)
        let surface = root?.childNode(withName: "voyagingSeaSurface", recursively: false)
        surface?.geometry?.firstMaterial?.setValue(vector(palette.sea), forKey: "uSea")
        surface?.geometry?.firstMaterial?.setValue(vector(palette.seaDeep), forKey: "uDeep")
        surface?.geometry?.firstMaterial?.setValue(vector(palette.reflection), forKey: "uLight")
        surface?.geometry?.firstMaterial?.setValue(vector(palette.fog), forKey: "uFog")
        root?.childNode(withName: "voyagingSeaUnderlay", recursively: false)?
            .geometry?.firstMaterial?.diffuse.contents = UIColor(rgb: palette.seaDeep)
    }

    private static func recolorLights(in scene: SCNScene, palette: Palette) {
        for node in scene.rootNode.childNodes {
            guard let light = node.light else { continue }
            if light.type == .ambient {
                light.color = UIColor(rgb: palette.ambient)
                light.intensity = 480
            } else if node.position.x < 0 {
                light.color = UIColor(rgb: palette.key)
                light.intensity = 1_200
            } else {
                light.color = UIColor(rgb: palette.fill)
                light.intensity = 220
            }
        }
    }

    private static func palette(for timeOfDay: AftideHomeTimeOfDay) -> Palette {
        switch timeOfDay {
        case .morning:
            Palette(
                sky: 0xE8B789, fog: 0xA7C7B9, sea: 0x5C9F98, seaDeep: 0x386F70,
                reflection: 0xFFE1AE, ambient: 0xFFE0BD, key: 0xFFD19B,
                fill: 0xB9E4D8, stars: 0, moon: false
            )
        case .day:
            Palette(
                sky: 0x77C6D7, fog: 0x8FC9CC, sea: 0x3B9299, seaDeep: 0x246C78,
                reflection: 0xFFF0B8, ambient: 0xE1F7F3, key: 0xFFF2C2,
                fill: 0x9DE0D7, stars: 0, moon: false
            )
        case .evening:
            Palette(
                sky: 0xB85F58, fog: 0x795F5B, sea: 0x3E7272, seaDeep: 0x274D55,
                reflection: 0xFFC07E, ambient: 0xF3B79B, key: 0xFFBD7B,
                fill: 0x79AFA6, stars: 70, moon: false
            )
        case .night:
            Palette(
                sky: 0x123830, fog: 0x123830, sea: 0x1E5348, seaDeep: 0x123830,
                reflection: 0xBFD6C6, ambient: 0xFFE9C8, key: 0xEADEBD,
                fill: 0x5DCAA5, stars: 380, moon: true
            )
        }
    }

    private static func vector(_ rgb: UInt) -> SCNVector3 {
        SCNVector3(
            Float((rgb >> 16) & 0xFF) / 255,
            Float((rgb >> 8) & 0xFF) / 255,
            Float(rgb & 0xFF) / 255
        )
    }
}
