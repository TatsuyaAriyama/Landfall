import SceneKit
import SwiftUI
import UIKit

/// Web版ホームと同じ4つの海。DEBUGではスクリーンショット確認用に
/// `LANDFALL_HOME_TIME=morning/day/evening/night` で固定できる。
enum AftideHomeTimeOfDay: String {
    case morning
    case day
    case evening
    case night

    static func current(at date: Date = Date()) -> Self {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["LANDFALL_HOME_TIME"],
           let override = Self(rawValue: value) {
            return override
        }
        #endif
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: return .morning
        case 11..<17: return .day
        case 17..<20: return .evening
        default: return .night
        }
    }

    var palette: AftideHomePalette {
        switch self {
        case .morning:
            AftideHomePalette(
                sky: 0xEDC49D, fog: 0xA9CCC2, sea: 0x69AAA6, seaDeep: 0x3B7B80,
                reflection: 0xFFE3B7, ambient: 0xFFE1C1, key: 0xFFD39E, fill: 0xBDE5D9,
                ink: 0x173F3C, glass: 0xF6EEE1, stars: 0, moon: false
            )
        case .day:
            AftideHomePalette(
                sky: 0x8BCFDB, fog: 0x93C9C8, sea: 0x56A9AA, seaDeep: 0x327A84,
                reflection: 0xFFF0C2, ambient: 0xE7FAF5, key: 0xFFF2C5, fill: 0xA5E1D8,
                ink: 0x123B40, glass: 0xE7F4EF, stars: 0, moon: false
            )
        case .evening:
            AftideHomePalette(
                sky: 0xC97668, fog: 0x916F68, sea: 0x568A88, seaDeep: 0x365F67,
                reflection: 0xFFD092, ambient: 0xF5BEA2, key: 0xFFC382, fill: 0x83B8AE,
                ink: 0xFFF0DA, glass: 0x173F43, stars: 90, moon: false
            )
        case .night:
            AftideHomePalette(
                sky: 0x183F3B, fog: 0x37625D, sea: 0x34776D, seaDeep: 0x1F514D,
                reflection: 0xD8EBDD, ambient: 0xF4E4C9, key: 0xF0E5CC, fill: 0x73AE95,
                ink: 0xF4F1EC, glass: 0x102F2C, stars: 430, moon: true
            )
        }
    }
}

struct AftideHomePalette {
    let sky: UInt
    let fog: UInt
    let sea: UInt
    let seaDeep: UInt
    let reflection: UInt
    let ambient: UInt
    let key: UInt
    let fill: UInt
    let ink: UInt
    let glass: UInt
    let stars: Int
    let moon: Bool

    var inkColor: Color { Color(hex: ink) }
    var glassColor: Color { Color(hex: glass) }
}

extension AftideHomePalette {
    /// Web VoyagingWorld の固定夜色。ホームの時刻連動パレットとは分け、
    /// タイマーだけWebと同じ海・霧・月光・操作パネルへ揃える。
    static let voyagingNight = AftideHomePalette(
        sky: 0x123830,
        fog: 0x123830,
        sea: 0x1E5348,
        seaDeep: 0x123830,
        reflection: 0xBFD6C6,
        ambient: 0xFFE9C8,
        key: 0xEADEBD,
        fill: 0x5DCAA5,
        ink: 0xF4F1EC,
        glass: 0x0D2A24,
        stars: 380,
        moon: true
    )
}

/// Web `destinationIslandDistance` を基準に、縦長のiPhoneでも目標として読める距離曲線。
func aftideDestinationDistance(_ ratio: Double) -> Float {
    let progress = min(1, max(0, ratio))
    if progress == 0 { return 110 }
    if progress == 1 { return 18 }
    return Float(110 + (18 - 110) * pow(progress, 2.15))
}

/// ホームの船・カメラと、島内の3Dスタジオ座標を往復する単一の定義。
/// 進捗で島の距離が変わっても、マーカーとホームの映像がずれない。
enum AftideHomeWorldReference {
    static let islandScale: Float = 1.24
    static let islandYaw: Float = -0.16
    static let boatWorldPosition = SCNVector3Zero
    static let cameraWorldPosition = SCNVector3(0.80, 2.18, 0.34)

    static func islandLocalPosition(
        of worldPosition: SCNVector3,
        progressRatio: Double
    ) -> SCNVector3 {
        let distance = aftideDestinationDistance(progressRatio)
        let translatedX = worldPosition.x - distance
        let translatedZ = worldPosition.z
        let inverseYaw = -islandYaw
        let cosine = cos(inverseYaw)
        let sine = sin(inverseYaw)
        return SCNVector3(
            (translatedX * cosine + translatedZ * sine) / islandScale,
            worldPosition.y / islandScale,
            (-translatedX * sine + translatedZ * cosine) / islandScale
        )
    }

    static func boatIslandPosition(progressRatio: Double) -> SCNVector3 {
        islandLocalPosition(of: boatWorldPosition, progressRatio: progressRatio)
    }

    static func cameraIslandPosition(progressRatio: Double) -> SCNVector3 {
        islandLocalPosition(of: cameraWorldPosition, progressRatio: progressRatio)
    }

    /// ホームのカメラは島の中心から少し上を見る。
    static let cameraTargetIslandPosition = SCNVector3(0, 0.32 / islandScale, 0)
}

/// 最新Webホームの `DestinationBackdropWorld` をネイティブで描く。
/// ホームは航海士の一人称、目的地編集では同じ世界の船後方へ引いて見渡す。
struct AboardDestinationHomeSceneView: UIViewRepresentable {
    let ratio: Double
    let timeOfDay: AftideHomeTimeOfDay
    let active: Bool
    let editingDestination: Bool
    var onCameraTransitionCompleted: (Bool) -> Void = { _ in }
    var onTapWorld: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onCameraTransitionCompleted: onCameraTransitionCompleted,
            onTapWorld: onTapWorld
        )
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.isOpaque = false
        let maximumFPS = min(120, UIScreen.main.maximumFramesPerSecond)
        // ProMotion端末では過剰なMSAAより120fpsを優先する。描画倍率2xでも
        // iPhone上は十分に精細で、海のフラグメント負荷を安定させられる。
        view.antialiasingMode = maximumFPS > 60 ? .multisampling2X : .multisampling4X
        view.contentScaleFactor = min(UIScreen.main.scale, 2)
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.isUserInteractionEnabled = editingDestination
        view.preferredFramesPerSecond = maximumFPS
        view.scene = AftideHomeSceneFactory.makeScene(
            timeOfDay: timeOfDay,
            distance: aftideDestinationDistance(ratio)
        )
        view.pointOfView = view.scene?.rootNode.childNode(withName: "homeCamera", recursively: false)
        view.delegate = context.coordinator
        context.coordinator.bind(
            view: view,
            timeOfDay: timeOfDay,
            distance: aftideDestinationDistance(ratio)
        )
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.onPan(_:))
        )
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.onPinch(_:))
        )
        view.addGestureRecognizer(pinch)
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.onTapWorld(_:))
        )
        // 見渡すドラッグの指を離した瞬間に「世界タップ」と誤判定しない。
        // pan が成立しなかった短い接触だけをUI開閉として扱う。
        tap.require(toFail: pan)
        view.addGestureRecognizer(tap)
        context.coordinator.setEditing(editingDestination, animated: false)
        context.coordinator.setActive(active)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let distance = aftideDestinationDistance(ratio)
        if context.coordinator.timeOfDay != timeOfDay {
            view.scene = AftideHomeSceneFactory.makeScene(
                timeOfDay: timeOfDay,
                distance: distance
            )
            view.pointOfView = view.scene?.rootNode.childNode(withName: "homeCamera", recursively: false)
            context.coordinator.bind(view: view, timeOfDay: timeOfDay, distance: distance)
        } else {
            context.coordinator.setDistance(distance)
        }
        context.coordinator.onCameraTransitionCompleted = onCameraTransitionCompleted
        context.coordinator.onTapWorldAction = onTapWorld
        context.coordinator.setEditing(editingDestination)
        context.coordinator.setActive(active)
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        enum CameraPhase {
            case home
            case zoomingOut
            case editor
            case zoomingIn
        }

        var onCameraTransitionCompleted: (Bool) -> Void
        var onTapWorldAction: () -> Void
        var timeOfDay: AftideHomeTimeOfDay = .morning
        private weak var view: SCNView?
        private weak var scene: SCNScene?
        private weak var camera: SCNNode?
        private weak var cameraTarget: SCNNode?
        private weak var island: SCNNode?
        private weak var vessel: SCNNode?
        private weak var navigator: SCNNode?
        private weak var seaMaterial: SCNMaterial?
        private var gulls: [SCNNode] = []
        private var targetDistance: Float = 110
        private var currentDistance: Float = 110
        private var startTime: TimeInterval?
        private var lastTime: TimeInterval?
        private var active = true
        private let reduceMotion = UIAccessibility.isReduceMotionEnabled
        private var cameraPhase: CameraPhase = .home
        private var editingRequested = false
        private var orbitRadius: Float = 20
        private var orbitAzimuth: Float = 0
        private var orbitPolar: Float = .pi * 0.36
        private var targetOrbitRadius: Float = 20
        private var targetOrbitAzimuth: Float = 0
        private var targetOrbitPolar: Float = .pi * 0.36
        private var minOrbitRadius: Float = 18
        private var maxOrbitRadius: Float = 60
        private var previousPanTranslation = CGPoint.zero

        private let gullConfig: [(radius: Float, height: Float, omega: Float, phase: Float)] = [
            (3.2, 4.8, 0.08, 0.2),
            (4.6, 5.4, -0.06, 2.1),
            (3.8, 4.3, 0.10, 4.2)
        ]

        init(
            onCameraTransitionCompleted: @escaping (Bool) -> Void,
            onTapWorld: @escaping () -> Void
        ) {
            self.onCameraTransitionCompleted = onCameraTransitionCompleted
            self.onTapWorldAction = onTapWorld
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(onAssetStudioWorldDidChange),
                name: .assetStudioWorldDidChange,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        /// ホームのSCNViewはSwiftUI上で再利用されるため、保存だけでは
        /// makeUIViewが再実行されない。保存通知で同じ視点状態を保ったまま世界を再構築する。
        @objc private func onAssetStudioWorldDidChange() {
            guard let view else { return }
            let wasEditing = editingRequested
            let wasActive = active
            let distance = targetDistance

            view.scene = AftideHomeSceneFactory.makeScene(
                timeOfDay: timeOfDay,
                distance: distance
            )
            view.pointOfView = view.scene?.rootNode.childNode(
                withName: "homeCamera",
                recursively: false
            )
            bind(view: view, timeOfDay: timeOfDay, distance: distance)
            if wasEditing {
                setEditing(true, animated: false)
            }
            setActive(wasActive)
        }

        func bind(
            view: SCNView,
            timeOfDay: AftideHomeTimeOfDay,
            distance: Float
        ) {
            self.view = view
            self.scene = view.scene
            self.timeOfDay = timeOfDay
            targetDistance = distance
            currentDistance = distance
            camera = view.scene?.rootNode.childNode(withName: "homeCamera", recursively: false)
            cameraTarget = view.scene?.rootNode.childNode(
                withName: "homeCameraTarget",
                recursively: false
            )
            island = view.scene?.rootNode.childNode(withName: "homeIsland", recursively: false)
            vessel = view.scene?.rootNode.childNode(withName: "homeVessel", recursively: false)
            navigator = view.scene?.rootNode.childNode(
                withName: "homeNavigator",
                recursively: true
            )
            seaMaterial = view.scene?.rootNode
                .childNode(withName: "homeSea", recursively: false)?
                .geometry?.firstMaterial
            gulls = (0..<3).compactMap {
                view.scene?.rootNode.childNode(withName: "homeGull\($0)", recursively: true)
            }
            startTime = nil
            lastTime = nil
            cameraPhase = .home
            editingRequested = false
            navigator?.isHidden = true
            updateCamera(time: 0)
            view.setNeedsDisplay()
        }

        func setDistance(_ value: Float) {
            targetDistance = value
            if reduceMotion || !active {
                currentDistance = value
                island?.position.x = value
                updateCamera(time: 0)
                view?.setNeedsDisplay()
            } else if cameraPhase == .editor {
                island?.position.x = value
            }
        }

        func setActive(_ value: Bool) {
            active = value
            guard let view else { return }
            let shouldAnimate = (value || editingRequested) && !reduceMotion
            view.rendersContinuously = shouldAnimate
            view.isPlaying = shouldAnimate
            if !shouldAnimate {
                seaMaterial?.setValue(NSNumber(value: Float(0)), forKey: "uTime")
                updateCamera(time: 0)
                view.setNeedsDisplay()
            }
        }

        /// ホームの船上視点と、航路全体を望む編集視点を同じシーン内で往復する。
        /// Scene/船/島は一度も作り直さない。
        func setEditing(_ value: Bool, animated: Bool = true) {
            guard value != editingRequested else { return }
            editingRequested = value
            guard let view, let camera, let cameraTarget else { return }

            camera.removeAllActions()
            cameraTarget.removeAllActions()
            let duration = reduceMotion || !animated ? 0 : 1.25
            let pose = value ? editorPose() : homePose(time: 0)
            cameraPhase = value ? .zoomingOut : .zoomingIn
            view.isUserInteractionEnabled = value
            if value {
                navigator?.isHidden = false
                scene?.fogStartDistance = 240
                scene?.fogEndDistance = 540
            }

            SCNTransaction.begin()
            SCNTransaction.animationDuration = duration
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(
                controlPoints: value ? 0.22 : 0.40,
                value ? 0.72 : 0.0,
                value ? 0.20 : 0.20,
                1.0
            )
            camera.position = pose.position
            cameraTarget.position = pose.target
            camera.camera?.fieldOfView = value ? 48 : 46
            SCNTransaction.completionBlock = { [weak self] in
                DispatchQueue.main.async {
                    guard let self, self.editingRequested == value else { return }
                    self.cameraPhase = value ? .editor : .home
                    if value {
                        // 入場時の視線を保ったまま、回転支点だけを同じ視線上の
                        // 船の少し前へ移す。航路中央を中心に巨大旋回しなくなる。
                        let orbitTarget = self.editorOrbitTarget(
                            position: pose.position,
                            lookTarget: pose.target
                        )
                        self.cameraTarget?.position = orbitTarget
                        self.configureOrbit(position: pose.position, target: orbitTarget)
                    } else {
                        self.navigator?.isHidden = true
                        self.scene?.fogStartDistance = 65
                        self.scene?.fogEndDistance = 220
                        self.updateCamera(time: 0)
                    }
                    self.onCameraTransitionCompleted(value)
                }
            }
            SCNTransaction.commit()
            view.setNeedsDisplay()
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard active, !reduceMotion else { return }
            if startTime == nil {
                startTime = time
                lastTime = time
            }
            let elapsed = Float(time - (startTime ?? time))
            let delta = Float(min(max(time - (lastTime ?? time), 0), 0.1))
            lastTime = time

            // Web THREE.MathUtils.damp(distance, target, 0.8, delta) と同じ指数追従。
            let alpha = 1 - exp(-0.8 * delta)
            currentDistance += (targetDistance - currentDistance) * alpha
            island?.position.x = currentDistance
            seaMaterial?.setValue(NSNumber(value: elapsed), forKey: "uTime")
            if cameraPhase == .home {
                updateCamera(time: elapsed)
            } else if cameraPhase == .editor {
                updateOrbit(delta: delta)
            }
            updateGulls(time: elapsed)
        }

        private func updateCamera(time: Float) {
            guard let camera, let cameraTarget else { return }
            let bounds = view?.bounds.size ?? .zero
            let portrait = bounds.width <= 0 || bounds.width / max(bounds.height, 1) < 0.76
            let roll = active && !reduceMotion ? sin(time * 0.52) * 0.012 : 0
            let rise = active && !reduceMotion ? sin(time * 0.68 + 0.7) * 0.035 : 0
            // 甲板上の航海士の一人称。本人はホーム中だけ隠し、
            // 目的地を開くと同じ甲板上へ現れる。
            camera.position = SCNVector3(
                portrait ? 0.80 : 0.74,
                (portrait ? 2.18 : 2.02) + rise,
                0.34
            )
            cameraTarget.position = SCNVector3(currentDistance, destinationFocusHeight(), 0)
            camera.eulerAngles.z = roll
            vessel?.position.y = rise * 0.45
            vessel?.eulerAngles.x = -roll * 0.55
            vessel?.eulerAngles.z = roll * 0.35
        }

        private struct CameraPose {
            var position: SCNVector3
            var target: SCNVector3
        }

        private func homePose(time: Float) -> CameraPose {
            let bounds = view?.bounds.size ?? .zero
            let portrait = bounds.width <= 0 || bounds.width / max(bounds.height, 1) < 0.76
            return CameraPose(
                position: SCNVector3(
                    portrait ? 0.80 : 0.74,
                    portrait ? 2.18 : 2.02,
                    0.34
                ),
                target: SCNVector3(currentDistance, destinationFocusHeight(), 0)
            )
        }

        /// 島が遠い間は水平線を、到着が近づいたら山頂を含む島全体の中心を向く。
        /// 新しい高低差のある島でも、ホームの縦長画面で頂上が切れない。
        private func destinationFocusHeight() -> Float {
            let proximity = min(1, max(0, (110 - currentDistance) / (110 - 18)))
            return 0.32 + 2.0 * pow(proximity, 2)
        }

        /// 編集開始時は世界の外へ飛ばず、船の少し後ろへだけ引く。
        /// 航路全体を見たいときは、この位置から明示的に縮小できる。
        private func editorPose() -> CameraPose {
            let centerX = currentDistance * 0.5
            return CameraPose(
                position: SCNVector3(-7.0, 4.6, 1.9),
                target: SCNVector3(centerX, 0.38, 0)
            )
        }

        /// editorPoseの見た目を変えない、同一直線上の近い回転支点。
        private func editorOrbitTarget(
            position: SCNVector3,
            lookTarget: SCNVector3
        ) -> SCNVector3 {
            let denominator = lookTarget.x - position.x
            let raw = abs(denominator) > 0.001
                ? (0.15 - position.x) / denominator
                : 0.5
            let amount = min(0.82, max(0.08, raw))
            return SCNVector3(
                position.x + (lookTarget.x - position.x) * amount,
                position.y + (lookTarget.y - position.y) * amount,
                position.z + (lookTarget.z - position.z) * amount
            )
        }

        private func configureOrbit(position: SCNVector3, target: SCNVector3) {
            let offset = SCNVector3(
                position.x - target.x,
                position.y - target.y,
                position.z - target.z
            )
            orbitRadius = max(1, sqrt(offset.x * offset.x + offset.y * offset.y + offset.z * offset.z))
            orbitAzimuth = atan2(offset.x, offset.z)
            orbitPolar = acos(max(-1, min(1, offset.y / orbitRadius)))
            targetOrbitRadius = orbitRadius
            targetOrbitAzimuth = orbitAzimuth
            targetOrbitPolar = min(.pi * 0.46, max(.pi * 0.26, orbitPolar))
            minOrbitRadius = max(18, orbitRadius * 0.55)
            // 開始構図より遠くへは引かない。拡大後の復帰上限でもある。
            maxOrbitRadius = orbitRadius
            if maxOrbitRadius < minOrbitRadius + 2 {
                maxOrbitRadius = minOrbitRadius + 2
            }
        }

        private func updateOrbit(delta: Float) {
            // 入力を直接カメラへ入れず、時間基準の減衰で追う。60/120fpsの
            // どちらでも同じ速度になり、指を離した時も急停止しない。
            let follow = 1 - exp(-11.5 * min(max(delta, 0), 0.1))
            var azimuthDelta = targetOrbitAzimuth - orbitAzimuth
            while azimuthDelta > .pi { azimuthDelta -= 2 * .pi }
            while azimuthDelta < -.pi { azimuthDelta += 2 * .pi }
            orbitAzimuth += azimuthDelta * follow
            orbitPolar += (targetOrbitPolar - orbitPolar) * follow
            orbitRadius += (targetOrbitRadius - orbitRadius) * follow
            applyOrbit()
        }

        private func applyOrbit() {
            guard cameraPhase == .editor, let camera, let cameraTarget else { return }
            let target = cameraTarget.position
            camera.position = SCNVector3(
                target.x + orbitRadius * sin(orbitPolar) * sin(orbitAzimuth),
                target.y + orbitRadius * cos(orbitPolar),
                target.z + orbitRadius * sin(orbitPolar) * cos(orbitAzimuth)
            )
            view?.setNeedsDisplay()
        }

        @objc func onPan(_ gesture: UIPanGestureRecognizer) {
            guard cameraPhase == .editor, let view else { return }
            switch gesture.state {
            case .began:
                previousPanTranslation = gesture.translation(in: view)
            case .changed:
                let translation = gesture.translation(in: view)
                let delta = CGPoint(
                    x: translation.x - previousPanTranslation.x,
                    y: translation.y - previousPanTranslation.y
                )
                previousPanTranslation = translation
                // 1画面のドラッグでほぼ半周。小さな指移動では狙いを外さない感度。
                targetOrbitAzimuth -= Float(delta.x) * 0.0034
                targetOrbitPolar = max(
                    .pi * 0.26,
                    min(.pi * 0.46, targetOrbitPolar - Float(delta.y) * 0.0026)
                )
            case .ended:
                // 指の速度を最大約7度の短い余韻へ変換。フリックで暴走はさせない。
                let velocity = gesture.velocity(in: view)
                let azimuthTail = max(-0.12, min(0.12, Float(velocity.x) * -0.000055))
                let polarTail = max(-0.06, min(0.06, Float(velocity.y) * -0.000035))
                targetOrbitAzimuth += azimuthTail
                targetOrbitPolar = max(
                    .pi * 0.26,
                    min(.pi * 0.46, targetOrbitPolar + polarTail)
                )
            default:
                break
            }
        }

        @objc func onPinch(_ gesture: UIPinchGestureRecognizer) {
            guard cameraPhase == .editor else { return }
            if gesture.state == .changed {
                let scale = pow(Float(gesture.scale), 0.72)
                targetOrbitRadius = max(
                    minOrbitRadius,
                    min(maxOrbitRadius, targetOrbitRadius / scale)
                )
                gesture.scale = 1
            }
        }

        @objc func onTapWorld(_ gesture: UITapGestureRecognizer) {
            guard cameraPhase == .editor, gesture.state == .ended else { return }
            onTapWorldAction()
        }

        private func updateGulls(time: Float) {
            for (index, bird) in gulls.enumerated() where gullConfig.indices.contains(index) {
                let config = gullConfig[index]
                let angle = config.phase + time * config.omega
                bird.position = SCNVector3(
                    18 + cos(angle) * config.radius,
                    config.height + sin(time * 0.4 + config.phase) * 0.22,
                    -3 + sin(angle) * config.radius
                )
                let beat = -0.18 + sin(time * (1.8 + Float(index) * 0.2) + config.phase) * 0.34
                bird.childNode(withName: "leftWing", recursively: false)?.eulerAngles.z = beat
                bird.childNode(withName: "rightWing", recursively: false)?.eulerAngles.z = -beat
            }
        }
    }
}

enum AftideHomeSceneFactory {
    static func makeScene(
        timeOfDay: AftideHomeTimeOfDay,
        distance: Float
    ) -> SCNScene {
        let palette = timeOfDay.palette
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        scene.fogColor = UIColor(rgb: palette.fog)
        scene.fogStartDistance = 65
        scene.fogEndDistance = 220
        scene.fogDensityExponent = 1

        scene.rootNode.addChildNode(makeSea(palette: palette))
        scene.rootNode.addChildNode(makeNavigatorPOVBoat())

        // 目的地詳細・航海中・共有画面と同じ作り込まれた島を使い、
        // ホームだけ簡略化された山に戻らないよう一つのモデルへ統一する。
        let island = VoyageSceneKit.makeIsland(
            position: SCNVector3Zero,
            scale: SCNVector3(1, 1, 1)
        )
        island.name = "homeIsland"
        island.position = SCNVector3(distance, 0, 0)
        island.scale = SCNVector3(
            AftideHomeWorldReference.islandScale,
            AftideHomeWorldReference.islandScale,
            AftideHomeWorldReference.islandScale
        )
        scene.rootNode.addChildNode(island)

        // 縦長画面でも日月が左上UIへ潜らず、Web版と同じ空の中央寄りに見える位置。
        let celestialZ: Float = -2.5
        let celestial = makeCelestial(
            moon: palette.moon,
            color: UIColor(rgb: palette.reflection)
        )
        celestial.position = SCNVector3(
            timeOfDay == .morning ? 42 : (timeOfDay == .day ? 48 : 46),
            timeOfDay == .day ? 14 : (timeOfDay == .evening ? 7 : 10),
            celestialZ
        )
        scene.rootNode.addChildNode(celestial)

        if palette.stars > 0 {
            scene.rootNode.addChildNode(makeStars(count: palette.stars))
        }
        if timeOfDay != .night {
            scene.rootNode.addChildNode(makeGulls())
        }

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(rgb: palette.ambient)
        ambient.light?.intensity = timeOfDay == .day ? 1_000 : 680
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.color = UIColor(rgb: palette.key)
        key.light?.intensity = timeOfDay == .day ? 1_550 : 1_250
        key.position = SCNVector3(-6, 11, 7)
        key.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.color = UIColor(rgb: palette.fill)
        fill.light?.intensity = 420
        fill.position = SCNVector3(18, 7, -9)
        fill.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(fill)

        let camera = SCNNode()
        camera.name = "homeCamera"
        let cameraComponent = SCNCamera()
        cameraComponent.fieldOfView = 46
        cameraComponent.zNear = 0.08
        cameraComponent.zFar = 640
        cameraComponent.wantsHDR = true
        cameraComponent.exposureOffset = -0.08
        cameraComponent.contrast = 0.08
        camera.camera = cameraComponent
        camera.position = AftideHomeWorldReference.cameraWorldPosition

        let cameraTarget = SCNNode()
        cameraTarget.name = "homeCameraTarget"
        cameraTarget.position = SCNVector3(distance, 0.32, 0)
        scene.rootNode.addChildNode(cameraTarget)

        let look = SCNLookAtConstraint(target: cameraTarget)
        look.isGimbalLockEnabled = true
        look.localFront = SCNVector3(0, 0, -1)
        camera.constraints = [look]
        scene.rootNode.addChildNode(camera)

        return scene
    }

    /// 船上から見える海面を実際に上下させる。長いうねりを中心にして、
    /// 規則的な縞にならないよう低周波の歪みを各波へ加える。
    private static let seaGeometryShader = """
    #pragma arguments
    float uTime;
    #pragma body
    float2 p = _geometry.position.xy;
    float forward = p.x + 24.0;
    float lateral = p.y;
    float warpPhase = forward * 0.046 + lateral * 0.061 - uTime * 0.17;
    float warp = sin(warpPhase) * 0.62;
    float phaseA = forward * 0.120 + lateral * 0.075 + warp - uTime * 0.32;
    float phaseB = forward * 0.110 - lateral * 0.105 - warp * 0.35 + uTime * 0.25;
    float phaseC = forward * 0.380 + lateral * 0.310 - uTime * 0.57;
    float phaseD = forward * 0.900 - lateral * 0.600 + uTime * 0.90;
    float height =
        sin(phaseA) * 0.200
        + sin(phaseB) * 0.105
        + sin(phaseC) * 0.025
        + sin(phaseD) * 0.006;
    float dWarpX = cos(warpPhase) * 0.62 * 0.046;
    float dWarpY = cos(warpPhase) * 0.62 * 0.061;
    float dhdx =
        cos(phaseA) * 0.200 * (0.120 + dWarpX)
        + cos(phaseB) * 0.105 * (0.110 - dWarpX * 0.35)
        + cos(phaseC) * 0.025 * 0.380
        + cos(phaseD) * 0.006 * 0.900;
    float dhdy =
        cos(phaseA) * 0.200 * (0.075 + dWarpY)
        + cos(phaseB) * 0.105 * (-0.105 - dWarpY * 0.35)
        + cos(phaseC) * 0.025 * 0.310
        + cos(phaseD) * 0.006 * -0.600;
    float edgeX = 1.0 - smoothstep(104.0, 120.0, abs(p.x));
    float edgeY = 1.0 - smoothstep(72.0, 84.0, abs(p.y));
    float edge = edgeX * edgeY;
    _geometry.position.z += height * edge;
    _geometry.normal = normalize(float3(-dhdx * edge, -dhdy * edge, 1.0));
    """

    /// 波高と傾斜を使って、谷の深色・波頭の反射・遠景の空映りを別々に描く。
    /// 旧版の長い均等な光線はやめ、短く割れた反射だけを残す。
    private static let seaShader = """
    #pragma arguments
    float uTime;
    float3 uSea;
    float3 uDeep;
    float3 uLight;
    float3 uFog;
    float uLightLane;
    float uReflection;
    #pragma body
    float forward = (_surface.diffuseTexcoord.x - 0.5) * 240.0 + 24.0;
    float lateral = (_surface.diffuseTexcoord.y - 0.5) * 170.0;
    float ahead = max(forward, 0.0);
    float warpPhase = forward * 0.046 + lateral * 0.061 - uTime * 0.17;
    float warp = sin(warpPhase) * 0.62;
    float phaseA = forward * 0.120 + lateral * 0.075 + warp - uTime * 0.32;
    float phaseB = forward * 0.110 - lateral * 0.105 - warp * 0.35 + uTime * 0.25;
    float phaseC = forward * 0.380 + lateral * 0.310 - uTime * 0.57;
    float phaseD = forward * 0.900 - lateral * 0.600 + uTime * 0.90;
    float height =
        sin(phaseA) * 0.200
        + sin(phaseB) * 0.105
        + sin(phaseC) * 0.025
        + sin(phaseD) * 0.006;
    float dWarpX = cos(warpPhase) * 0.62 * 0.046;
    float dWarpY = cos(warpPhase) * 0.62 * 0.061;
    float2 slope = float2(
        cos(phaseA) * 0.200 * (0.120 + dWarpX)
            + cos(phaseB) * 0.105 * (0.110 - dWarpX * 0.35)
            + cos(phaseC) * 0.025 * 0.380
            + cos(phaseD) * 0.006 * 0.900,
        cos(phaseA) * 0.200 * (0.075 + cos(warpPhase) * 0.62 * 0.061)
            + cos(phaseB) * 0.105 * (-0.105 - cos(warpPhase) * 0.62 * 0.061 * 0.35)
            + cos(phaseC) * 0.025 * 0.310
            + cos(phaseD) * 0.006 * -0.600
    );

    float depthMix = smoothstep(4.0, 108.0, ahead);
    float3 col = mix(uSea, uDeep, 0.10 + depthMix * 0.64);
    float directionalShade = clamp(0.5 + slope.x * 3.0 + slope.y * 2.6, 0.0, 1.0);
    col *= 0.93 + directionalShade * 0.10;
    float trough = 1.0 - smoothstep(-0.17, 0.015, height);
    float crest = smoothstep(0.055, 0.245, height);
    col = mix(col, uDeep, trough * 0.30);
    col = mix(col, uLight, crest * 0.075);

    // 水平線に近い面では空と霧が薄く映り、近景の暗い谷との差が奥行きになる。
    float grazing = smoothstep(30.0, 112.0, ahead);
    col = mix(col, mix(uLight, uFog, 0.58), grazing * 0.14);
    float grainA = sin(
      forward * 0.72 + sin(lateral * 0.31) * 1.7
      + sin(forward * 0.13 + lateral * 0.27) * 2.2 - uTime * 0.92
    );
    float grainB = sin(
      lateral * 0.81 + sin(forward * 0.36) * 1.3
      - sin(lateral * 0.11 - forward * 0.23) * 1.8 + uTime * 0.61
    );
    float surfaceGrain = grainA * grainB;
    col *= 0.985 + surfaceGrain * 0.025
      * (1.0 - smoothstep(34.0, 108.0, ahead));
    float broken = 0.5 + 0.5 * sin(
      forward * 1.73 - lateral * 2.11 + sin(lateral * 0.16) * 1.8 - uTime * 1.12
    );
    float capGlint = smoothstep(0.78, 0.98, broken)
      * smoothstep(0.04, 0.20, height)
      * (1.0 - smoothstep(22.0, 94.0, ahead));
    col = mix(col, uLight, capGlint * 0.095);

    float laneWidth = mix(2.2, 5.8, smoothstep(4.0, 75.0, ahead));
    float laneWarp = sin(ahead * 0.20 - uTime * 0.36) * 0.58
      + sin(ahead * 0.53 + uTime * 0.22) * 0.24;
    float laneDelta = (lateral - uLightLane + laneWarp) / laneWidth;
    float lane = exp(-(laneDelta * laneDelta));
    float shimmer = 0.5 + 0.5
      * sin(ahead * 1.17 - uTime * 1.28)
      * sin(lateral * 1.63 + uTime * 0.61);
    float reflectionFade =
      smoothstep(3.0, 18.0, ahead) * (1.0 - smoothstep(92.0, 122.0, ahead));
    float reflected =
      lane * reflectionFade * smoothstep(0.24, 0.84, shimmer) * uReflection
      * (0.44 + crest * 0.56);
    col = mix(col, uLight, clamp(reflected, 0.0, 0.58));
    col = mix(col, uFog, smoothstep(94.0, 138.0, ahead));
    _surface.diffuse = float4(pow(clamp(col, 0.0, 1.0), float3(2.2)), 1.0);
    """

    private static func makeSea(palette: AftideHomePalette) -> SCNNode {
        let plane = SCNPlane(width: 240, height: 170)
        // うねりの輪郭を保ちつつ、120fps端末でも余裕を残す約1.4万頂点。
        plane.widthSegmentCount = 144
        plane.heightSegmentCount = 96
        let material = SCNMaterial()
        material.name = "homeSeaMaterial"
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(rgb: palette.sea)
        material.isDoubleSided = true
        material.shaderModifiers = [
            .geometry: seaGeometryShader,
            .surface: seaShader
        ]
        material.setValue(NSNumber(value: Float(0)), forKey: "uTime")
        material.setValue(vector(UIColor(rgb: palette.sea)), forKey: "uSea")
        material.setValue(vector(UIColor(rgb: palette.seaDeep)), forKey: "uDeep")
        material.setValue(vector(UIColor(rgb: palette.reflection)), forKey: "uLight")
        material.setValue(vector(UIColor(rgb: palette.fog)), forKey: "uFog")
        material.setValue(NSNumber(value: 5.2), forKey: "uLightLane")
        material.setValue(NSNumber(value: palette.moon ? 0.52 : 0.34), forKey: "uReflection")
        plane.firstMaterial = material

        let node = SCNNode(geometry: plane)
        node.name = "homeSea"
        node.position = SCNVector3(24, 0, 0)
        node.eulerAngles.x = -.pi / 2
        return node
    }

    private static func makeNavigatorPOVBoat() -> SCNNode {
        let vessel = SCNNode()
        vessel.name = "homeVessel"

        // 港・航海中・Web版と同じ landfall_boat モデルとカスタムカラーを使う。
        // ホームから本人を見せる。航海士のすぐ後ろにカメラを置き、
        // 目的地編集へ引いても同じ甲板上の同じキャラクターを保つ。
        let boat = VoyageSceneKit.makeBoatModel(BoatCustomization.currentParts)
        boat.name = "homeWebBoat"
        let sailor = PhoenixNavigator.makeNavigatorNode()
        sailor.name = "homeNavigator"
        sailor.scale = SCNVector3(
            VoyageSceneKit.navigatorDeckScale,
            VoyageSceneKit.navigatorDeckScale,
            VoyageSceneKit.navigatorDeckScale
        )
        sailor.isHidden = true
        if let anchor = boat.childNode(withName: "Navigator_Anchor", recursively: true) {
            anchor.addChildNode(sailor)
        } else {
            sailor.position = VoyageSceneKit.navigatorDeckPosition
            boat.addChildNode(sailor)
        }
        boat.scale = SCNVector3(2.2, 2.2, 2.2)
        vessel.addChildNode(boat)
        return vessel
    }

    static func makeIsland() -> SCNNode {
        let root = SCNNode()

        let shadow = SCNCylinder(radius: 3.05, height: 0.012)
        shadow.radialSegmentCount = 56
        shadow.firstMaterial = constant(UIColor(rgb: 0x0B2927).withAlphaComponent(0.20))
        let shadowNode = SCNNode(geometry: shadow)
        shadowNode.scale.z = 0.66
        shadowNode.position = SCNVector3(0.08, 0.012, 0.08)
        root.addChildNode(shadowNode)

        let foam = SCNTorus(ringRadius: 3.08, pipeRadius: 0.15)
        foam.ringSegmentCount = 72
        foam.pipeSegmentCount = 8
        foam.firstMaterial = constant(UIColor(rgb: 0xDCEBE1).withAlphaComponent(0.58))
        let foamNode = SCNNode(geometry: foam)
        foamNode.scale.z = 0.66
        foamNode.position.y = 0.027
        root.addChildNode(foamNode)

        let beach = SCNCylinder(radius: 3.08, height: 0.12)
        beach.radialSegmentCount = 48
        beach.firstMaterial = lit(UIColor(rgb: 0xD8CDA7), roughness: 0.92)
        let beachNode = SCNNode(geometry: beach)
        beachNode.scale.z = 0.68
        beachNode.position.y = 0.065
        root.addChildNode(beachNode)

        let terrain = SCNNode(geometry: makeTerrain())
        terrain.position.y = 0.08
        root.addChildNode(terrain)

        // 正面(+X方向)からも一枚岩の円錐に見えないよう、海から読める三峰を
        // 奥行きではなく左右(Z)へ分ける。遠景では雄大な稜線、近景では
        // 低ポリの岩峰として既存の地形へ自然に重なる。
        let peakSpecs: [(x: Float, z: Float, radius: CGFloat, height: CGFloat, color: UInt)] = [
            (-0.12, -0.78, 0.70, 2.45, 0xA8A77D),
            (0.18, 0.12, 0.78, 2.95, 0xC7C29A),
            (-0.28, 0.86, 0.58, 1.92, 0x8FA178)
        ]
        for (index, peak) in peakSpecs.enumerated() {
            let geometry = SCNCone(
                topRadius: 0.05,
                bottomRadius: peak.radius,
                height: peak.height
            )
            geometry.radialSegmentCount = index == 1 ? 9 : 8
            geometry.firstMaterial = lit(
                UIColor(rgb: peak.color),
                roughness: 0.94
            )
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(
                peak.x,
                0.16 + Float(peak.height) * 0.5,
                peak.z
            )
            node.eulerAngles.y = Float(index) * 0.57
            root.addChildNode(node)
        }

        let rockPositions: [(Float, Float, Float, Float)] = [
            (-1.72, 0.31, 0.54, 1.06),
            (1.74, 0.28, -0.40, 0.90),
            (1.22, 0.36, 0.76, 0.78)
        ]
        for (index, value) in rockPositions.enumerated() {
            let rock = SCNSphere(radius: 0.24)
            rock.segmentCount = 6
            rock.firstMaterial = lit(UIColor(rgb: 0x827861), roughness: 0.95)
            let node = SCNNode(geometry: rock)
            node.position = SCNVector3(value.0, value.1, value.2)
            node.scale = SCNVector3(value.3, value.3 * 0.82, value.3)
            node.eulerAngles = SCNVector3(Float(index) * 0.18, Float(index) * 0.7, 0.1)
            root.addChildNode(node)
        }

        let shrubColors: [UInt] = [0x547A64, 0x63866C, 0x4D705D, 0x6E8E70]
        let shrubPositions: [(Float, Float, Float, Float)] = [
            (-1.55, 0.46, -0.50, 1.05),
            (-1.18, 0.57, -0.62, 1.20),
            (-0.78, 0.68, -0.55, 1.00),
            (-0.34, 0.72, -0.42, 1.18),
            (0.12, 0.64, -0.52, 0.96),
            (0.54, 0.58, -0.48, 1.13),
            (0.96, 0.50, -0.42, 0.94),
            (1.36, 0.41, -0.32, 1.02),
            (-0.92, 0.54, 0.34, 0.90),
            (-0.44, 0.62, 0.45, 1.04),
            (0.05, 0.58, 0.50, 0.88),
            (0.52, 0.52, 0.44, 1.00)
        ]
        for (index, value) in shrubPositions.enumerated() {
            let shrub = SCNSphere(radius: 0.22)
            shrub.segmentCount = 7
            shrub.firstMaterial = lit(
                UIColor(rgb: shrubColors[index % shrubColors.count]),
                roughness: 0.96
            )
            let node = SCNNode(geometry: shrub)
            node.position = SCNVector3(value.0, value.1, value.2)
            node.scale = SCNVector3(value.3, value.3, value.3)
            root.addChildNode(node)
        }
        return root
    }

    private static func makeTerrain(segments: Int = 36, rings: Int = 8) -> SCNGeometry {
        var vertices: [SCNVector3] = [SCNVector3(0, terrainHeight(x: 0, z: 0, radius: 0), 0)]
        var colors: [UIColor] = [terrainColor(height: vertices[0].y)]
        var indices: [UInt32] = []

        for ring in 1...rings {
            let radius = Float(ring) / Float(rings)
            for segment in 0..<segments {
                let angle = Float(segment) / Float(segments) * 2 * .pi
                let coast = 1 + sin(angle * 3 + 0.4) * 0.055 + cos(angle * 5 - 0.7) * 0.035
                let x = cos(angle) * 2.72 * radius * coast
                let z = sin(angle) * 1.55 * radius * (1 + sin(angle * 4 + 0.2) * 0.045)
                let y = terrainHeight(x: x, z: z, radius: radius)
                vertices.append(SCNVector3(x, y, z))
                colors.append(terrainColor(height: y))
            }
        }

        for segment in 0..<segments {
            let next = (segment + 1) % segments
            indices += [0, UInt32(1 + next), UInt32(1 + segment)]
        }
        if rings >= 2 {
            for ring in 2...rings {
                let previous = 1 + (ring - 2) * segments
                let current = 1 + (ring - 1) * segments
                for segment in 0..<segments {
                    let next = (segment + 1) % segments
                    let a = UInt32(previous + segment)
                    let b = UInt32(previous + next)
                    let c = UInt32(current + segment)
                    let d = UInt32(current + next)
                    indices += [a, b, c, b, d, c]
                }
            }
        }

        var normals = [SCNVector3](repeating: SCNVector3Zero, count: vertices.count)
        for index in stride(from: 0, to: indices.count, by: 3) {
            let ia = Int(indices[index])
            let ib = Int(indices[index + 1])
            let ic = Int(indices[index + 2])
            let normal = cross(subtract(vertices[ib], vertices[ia]), subtract(vertices[ic], vertices[ia]))
            normals[ia] = add(normals[ia], normal)
            normals[ib] = add(normals[ib], normal)
            normals[ic] = add(normals[ic], normal)
        }
        normals = normals.map(normalize)

        let element = indices.withUnsafeBufferPointer {
            SCNGeometryElement(
                data: Data(buffer: $0),
                primitiveType: .triangles,
                primitiveCount: indices.count / 3,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )
        }
        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: vertices),
                SCNGeometrySource(normals: normals),
                colorSource(colors)
            ],
            elements: [element]
        )
        let material = lit(.white, roughness: 0.88)
        material.diffuse.contents = UIColor.white
        geometry.firstMaterial = material
        return geometry
    }

    private static func terrainHeight(x: Float, z: Float, radius: Float) -> Float {
        if radius >= 0.995 { return 0.09 }
        let main = 1.28 * exp(-(((x + 0.55) * (x + 0.55)) / 1.3 + ((z + 0.35) * (z + 0.35)) / 0.42))
        let east = 0.94 * exp(-(((x - 0.72) * (x - 0.72)) / 1.05 + ((z - 0.36) * (z - 0.36)) / 0.38))
        let ridge = 0.48 * exp(-(((x + 0.02) * (x + 0.02)) / 1.5 + (z * z) / 0.52))
        let coastFade = pow(1 - radius, 0.48)
        let foothill = 0.28 * pow(1 - radius, 0.7)
        let texture = (sin(x * 4.1 + z * 1.7) + sin(x * 1.8 - z * 5.2))
            * 0.035 * pow(1 - radius, 1.25)
        return max(0.08, 0.08 + foothill + (main + east + ridge) * coastFade + texture)
    }

    private static func terrainColor(height: Float) -> UIColor {
        let low = UIColor(rgb: 0xB9B58B)
        let mid = UIColor(rgb: 0x8FA178)
        let high = UIColor(rgb: 0xA8A77D)
        let mix = min(1, max(0, (height - 0.12) / (1.52 - 0.12)))
        if mix < 0.55 {
            return blend(low, mid, mix / 0.55)
        }
        return blend(mid, high, (mix - 0.55) / 0.45)
    }

    private static func makeCelestial(moon: Bool, color: UIColor) -> SCNNode {
        let sphere = SCNSphere(radius: moon ? 1.1 : 1.35)
        sphere.segmentCount = 28
        let material = constant(color)
        material.emission.contents = color
        material.emission.intensity = moon ? 0.82 : 0.62
        sphere.firstMaterial = material
        return SCNNode(geometry: sphere)
    }

    private static func makeStars(count: Int) -> SCNNode {
        var state: UInt64 = 0x9E3779B97F4A7C15
        func random() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float((state >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
        }
        var points: [SCNVector3] = []
        for _ in 0..<count {
            points.append(
                SCNVector3(
                    18 + random() * 88,
                    4 + random() * 42,
                    -55 + random() * 110
                )
            )
        }
        let source = SCNGeometrySource(vertices: points)
        let indices = (0..<UInt32(points.count)).map { $0 }
        let element = indices.withUnsafeBufferPointer {
            SCNGeometryElement(
                data: Data(buffer: $0),
                primitiveType: .point,
                primitiveCount: points.count,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )
        }
        element.pointSize = 0.08
        element.minimumPointScreenSpaceRadius = 0.6
        element.maximumPointScreenSpaceRadius = 1.6
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.firstMaterial = constant(UIColor(rgb: 0xEADEBD).withAlphaComponent(0.72))
        return SCNNode(geometry: geometry)
    }

    private static func makeGulls() -> SCNNode {
        let root = SCNNode()
        let vertices = [
            SCNVector3(0, 0, 0),
            SCNVector3(0.42, 0.025, -0.05),
            SCNVector3(0.15, 0, 0.09)
        ]
        let indices: [UInt32] = [0, 1, 2]
        let element = indices.withUnsafeBufferPointer {
            SCNGeometryElement(
                data: Data(buffer: $0),
                primitiveType: .triangles,
                primitiveCount: 1,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )
        }
        for index in 0..<3 {
            let bird = SCNNode()
            bird.name = "homeGull\(index)"
            for left in [true, false] {
                let geometry = SCNGeometry(
                    sources: [SCNGeometrySource(vertices: vertices)],
                    elements: [element]
                )
                geometry.firstMaterial = constant(UIColor(rgb: 0xEADEBD).withAlphaComponent(0.72))
                let wing = SCNNode(geometry: geometry)
                wing.name = left ? "leftWing" : "rightWing"
                wing.scale.x = left ? -1 : 1
                bird.addChildNode(wing)
            }
            root.addChildNode(bird)
        }
        return root
    }

    private static func lit(
        _ color: UIColor,
        roughness: CGFloat,
        doubleSided: Bool = false
    ) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.roughness.contents = roughness
        material.metalness.contents = 0
        material.isDoubleSided = doubleSided
        return material
    }

    private static func constant(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color
        material.isDoubleSided = true
        material.writesToDepthBuffer = color.cgColor.alpha >= 1
        return material
    }

    private static func cylinder(
        from: SCNVector3,
        to: SCNVector3,
        radius: CGFloat,
        color: UIColor
    ) -> SCNNode {
        let delta = subtract(to, from)
        let length = CGFloat(sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z))
        let geometry = SCNCylinder(radius: radius, height: length)
        geometry.radialSegmentCount = 7
        geometry.firstMaterial = lit(color, roughness: 0.86)
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(
            (from.x + to.x) / 2,
            (from.y + to.y) / 2,
            (from.z + to.z) / 2
        )
        node.look(at: to, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
        return node
    }

    private static func vector(_ color: UIColor) -> SCNVector3 {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: nil)
        return SCNVector3(Float(red), Float(green), Float(blue))
    }

    private static func colorSource(_ colors: [UIColor]) -> SCNGeometrySource {
        let values: [SIMD4<Float>] = colors.map { color in
            let rgb = vector(color)
            return SIMD4(rgb.x, rgb.y, rgb.z, Float(color.cgColor.alpha))
        }
        let data = values.withUnsafeBytes { Data($0) }
        return SCNGeometrySource(
            data: data,
            semantic: .color,
            vectorCount: values.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD4<Float>>.stride
        )
    }

    private static func blend(_ a: UIColor, _ b: UIColor, _ t: Float) -> UIColor {
        let av = vector(a)
        let bv = vector(b)
        return UIColor(
            red: CGFloat(av.x + (bv.x - av.x) * t),
            green: CGFloat(av.y + (bv.y - av.y) * t),
            blue: CGFloat(av.z + (bv.z - av.z) * t),
            alpha: 1
        )
    }

    private static func subtract(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
        SCNVector3(a.x - b.x, a.y - b.y, a.z - b.z)
    }

    private static func add(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
        SCNVector3(a.x + b.x, a.y + b.y, a.z + b.z)
    }

    private static func cross(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
        SCNVector3(
            a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x
        )
    }

    private static func normalize(_ value: SCNVector3) -> SCNVector3 {
        let length = sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
        guard length > 0.0001 else { return SCNVector3(0, 1, 0) }
        return SCNVector3(value.x / length, value.y / length, value.z / length)
    }
}
