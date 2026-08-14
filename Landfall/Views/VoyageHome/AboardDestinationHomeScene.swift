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

/// ホームの機能を、画面上のメニューではなく港の中の物として扱う。
/// 値はSceneKitノードにも保存し、子メッシュを押しても親を辿って同じ機能を開く。
enum HomeHarborHotspot: String, CaseIterable {
    case work
    case destination
    case logbook
    case island
    case harbor
    case style

    var accessibilityLabel: String {
        switch self {
        case .work: LF.text("Work items")
        case .destination: LF.text("Destinations")
        case .logbook: LF.text("Logbook")
        case .island: PlayerProfile.islandName
        case .harbor: LF.text("Harbor")
        case .style: LF.text("Style")
        }
    }
}

private enum HomeHarborHitTest {
    static let categoryBitMask = 1 << 8
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
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let ratio: Double
    let steps: [VoyageStep]
    let timeOfDay: AftideHomeTimeOfDay
    let date: Date
    let active: Bool
    let editingDestination: Bool
    let voyaging: Bool
    let voyageResting: Bool
    let voyageElapsedSeconds: Int
    let showsVoyageIsland: Bool
    var homeOverlayPresented = false
    var onCameraTransitionCompleted: (Bool) -> Void = { _ in }
    var onVoyageTransitionCompleted: (Bool) -> Void = { _ in }
    var onTapWorld: () -> Void = {}
    var onActivateHotspot: (HomeHarborHotspot) -> Void = { _ in }
    var onDismissHomeOverlay: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onCameraTransitionCompleted: onCameraTransitionCompleted,
            onVoyageTransitionCompleted: onVoyageTransitionCompleted,
            onTapWorld: onTapWorld,
            onActivateHotspot: onActivateHotspot,
            onDismissHomeOverlay: onDismissHomeOverlay
        )
    }

    func makeUIView(context: Context) -> VoyagingSceneKitView {
        let view = VoyagingSceneKitView()
        view.backgroundColor = .clear
        view.isOpaque = false
        let maximumFPS = min(120, UIScreen.main.maximumFramesPerSecond)
        // ProMotion端末では過剰なMSAAより120fpsを優先する。描画倍率2xでも
        // iPhone上は十分に精細で、海のフラグメント負荷を安定させられる。
        view.antialiasingMode = maximumFPS > 60 ? .multisampling2X : .multisampling4X
        view.contentScaleFactor = min(UIScreen.main.scale, 2)
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.isUserInteractionEnabled = true
        view.preferredFramesPerSecond = maximumFPS
        view.scene = AftideHomeSceneFactory.makeScene(
            timeOfDay: timeOfDay,
            distance: aftideDestinationDistance(ratio),
            steps: steps,
            date: date
        )
        view.pointOfView = view.scene?.rootNode.childNode(withName: "homeCamera", recursively: false)
        view.delegate = context.coordinator
        context.coordinator.bind(
            view: view,
            timeOfDay: timeOfDay,
            distance: aftideDestinationDistance(ratio),
            steps: steps,
            date: date
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
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.onDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        doubleTap.isEnabled = false
        context.coordinator.doubleTapRecognizer = doubleTap
        view.addGestureRecognizer(doubleTap)
        let hover = UIHoverGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.onHover(_:))
        )
        view.addGestureRecognizer(hover)
        // 見渡すドラッグの指を離した瞬間に「世界タップ」と誤判定しない。
        // pan が成立しなかった短い接触だけをUI開閉として扱う。
        tap.require(toFail: pan)
        tap.require(toFail: doubleTap)
        view.addGestureRecognizer(tap)
        context.coordinator.setEditing(editingDestination, animated: false)
        context.coordinator.setVoyageState(
            resting: voyageResting,
            elapsedSeconds: voyageElapsedSeconds,
            showsIsland: showsVoyageIsland
        )
        context.coordinator.setVoyaging(voyaging, animated: false)
        context.coordinator.setReduceMotion(
            accessibilityReduceMotion || UIAccessibility.isReduceMotionEnabled
        )
        view.onAccessibilityZoom = { [weak coordinator = context.coordinator] factor in
            coordinator?.accessibilityZoom(by: factor)
        }
        view.onKeyboardCycleAction = { [weak coordinator = context.coordinator] reverse in
            coordinator?.cycleKeyboardHotspot(reverse: reverse)
        }
        view.onKeyboardPrimaryAction = { [weak coordinator = context.coordinator] in
            coordinator?.activateKeyboardHotspot()
        }
        view.onKeyboardEscape = { [weak coordinator = context.coordinator] in
            coordinator?.dismissHomeOverlay()
        }
        context.coordinator.setHomeOverlayPresented(homeOverlayPresented)
        context.coordinator.setActive(active)
        return view
    }

    func updateUIView(_ view: VoyagingSceneKitView, context: Context) {
        let distance = aftideDestinationDistance(ratio)
        var rebuiltScene = false
        let wasReturningToHome = context.coordinator.isReturningToHome
        if context.coordinator.timeOfDay != timeOfDay,
           !context.coordinator.isVoyageWorldActive {
            rebuiltScene = true
            view.scene = AftideHomeSceneFactory.makeScene(
                timeOfDay: timeOfDay,
                distance: distance,
                steps: steps,
                date: date
            )
            view.pointOfView = view.scene?.rootNode.childNode(withName: "homeCamera", recursively: false)
            context.coordinator.bind(
                view: view,
                timeOfDay: timeOfDay,
                distance: distance,
                steps: steps,
                date: date
            )
        } else {
            context.coordinator.setDistance(distance)
            context.coordinator.setSteps(steps)
            context.coordinator.setDate(date)
        }
        context.coordinator.onCameraTransitionCompleted = onCameraTransitionCompleted
        context.coordinator.onVoyageTransitionCompleted = onVoyageTransitionCompleted
        context.coordinator.onTapWorldAction = onTapWorld
        context.coordinator.onActivateHotspot = onActivateHotspot
        context.coordinator.onDismissHomeOverlay = onDismissHomeOverlay
        context.coordinator.setReduceMotion(
            accessibilityReduceMotion || UIAccessibility.isReduceMotionEnabled
        )
        context.coordinator.setHomeOverlayPresented(homeOverlayPresented)
        context.coordinator.setEditing(editingDestination)
        context.coordinator.setVoyageState(
            resting: voyageResting,
            elapsedSeconds: voyageElapsedSeconds,
            showsIsland: showsVoyageIsland
        )
        context.coordinator.setVoyaging(
            voyaging,
            animated: !rebuiltScene,
            force: rebuiltScene && wasReturningToHome
        )
        context.coordinator.setActive(active)
    }

    static func dismantleUIView(_ view: VoyagingSceneKitView, coordinator: Coordinator) {
        view.onAccessibilityZoom = nil
        view.onKeyboardCycleAction = nil
        view.onKeyboardPrimaryAction = nil
        view.onKeyboardEscape = nil
        view.capturesHarborKeyboard = false
        view.delegate = nil
        view.isPlaying = false
        view.rendersContinuously = false
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        enum CameraPhase {
            case home
            case zoomingOut
            case editor
            case zoomingIn
            case departing
            case timer
            case returning
        }

        var onCameraTransitionCompleted: (Bool) -> Void
        var onVoyageTransitionCompleted: (Bool) -> Void
        var onTapWorldAction: () -> Void
        var onActivateHotspot: (HomeHarborHotspot) -> Void
        var onDismissHomeOverlay: () -> Void
        var timeOfDay: AftideHomeTimeOfDay = .morning
        private weak var view: SCNView?
        private weak var scene: SCNScene?
        private weak var camera: SCNNode?
        private weak var cameraTarget: SCNNode?
        private weak var island: SCNNode?
        private weak var stepIslets: SCNNode?
        private weak var vessel: SCNNode?
        private weak var timerBoatBob: SCNNode?
        private weak var timerWake: SCNNode?
        private weak var navigator: SCNNode?
        private weak var homeHarbor: SCNNode?
        private weak var seaMaterial: SCNMaterial?
        private weak var moon: SCNNode?
        private weak var timerApproachingIsland: SCNNode?
        private weak var hoveredHotspotNode: SCNNode?
        private weak var keyboardView: VoyagingSceneKitView?
        weak var doubleTapRecognizer: UITapGestureRecognizer?
        private var gulls: [SCNNode] = []
        private var targetDistance: Float = 110
        private var currentDistance: Float = 110
        private var voyageSteps: [VoyageStep] = []
        private var currentDate = Date()
        private var stepsKey = ""
        private var startTime: TimeInterval?
        private var lastTime: TimeInterval?
        private var active = true
        private var reduceMotion = false
        private var frozenOceanTime = HomeIslandOceanEffects.currentTime
        private var voyageTransitionGeneration = 0
        private var capturedHomeRenderingSettings = false
        private var homePreferredFramesPerSecond = 60
        private var homeContentScaleFactor: CGFloat = 2
        private var homeAntialiasingMode: SCNAntialiasingMode = .multisampling4X
        private var cameraPhase: CameraPhase = .home
        private var editingRequested = false
        private var voyagingRequested = false
        private var voyageResting = false
        private var voyageElapsedSeconds: Float = 0
        private var showsVoyageIsland = false
        private let navigatorAnimator = PhoenixAnimator()
        private var orbitRadius: Float = 20
        private var orbitAzimuth: Float = 0
        private var orbitPolar: Float = .pi * 0.36
        private var targetOrbitRadius: Float = 20
        private var targetOrbitAzimuth: Float = 0
        private var targetOrbitPolar: Float = .pi * 0.36
        private var minOrbitRadius: Float = 18
        private var maxOrbitRadius: Float = 60
        private var previousPanTranslation = CGPoint.zero
        private var homeOverlayPresented = false
        private var keyboardHotspotIndex: Int?

        var isReturningToHome: Bool {
            cameraPhase == .returning
        }

        var isVoyageWorldActive: Bool {
            voyagingRequested || cameraPhase == .departing || cameraPhase == .timer
                || cameraPhase == .returning
        }

        private let gullConfig: [(radius: Float, height: Float, omega: Float, phase: Float)] = [
            (3.2, 4.8, 0.08, 0.2),
            (4.6, 5.4, -0.06, 2.1),
            (3.8, 4.3, 0.10, 4.2)
        ]

        init(
            onCameraTransitionCompleted: @escaping (Bool) -> Void,
            onVoyageTransitionCompleted: @escaping (Bool) -> Void,
            onTapWorld: @escaping () -> Void,
            onActivateHotspot: @escaping (HomeHarborHotspot) -> Void,
            onDismissHomeOverlay: @escaping () -> Void
        ) {
            self.onCameraTransitionCompleted = onCameraTransitionCompleted
            self.onVoyageTransitionCompleted = onVoyageTransitionCompleted
            self.onTapWorldAction = onTapWorld
            self.onActivateHotspot = onActivateHotspot
            self.onDismissHomeOverlay = onDismissHomeOverlay
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
            let wasVoyaging = voyagingRequested
            let wasActive = active
            let distance = targetDistance

            view.scene = AftideHomeSceneFactory.makeScene(
                timeOfDay: timeOfDay,
                distance: distance,
                steps: voyageSteps,
                date: currentDate
            )
            view.pointOfView = view.scene?.rootNode.childNode(
                withName: "homeCamera",
                recursively: false
            )
            bind(
                view: view,
                timeOfDay: timeOfDay,
                distance: distance,
                steps: voyageSteps,
                date: currentDate
            )
            if wasEditing {
                setEditing(true, animated: false)
            }
            if wasVoyaging {
                setVoyageState(
                    resting: voyageResting,
                    elapsedSeconds: Int(voyageElapsedSeconds),
                    showsIsland: showsVoyageIsland
                )
                setVoyaging(true, animated: false)
            }
            setActive(wasActive)
        }

        func bind(
            view: SCNView,
            timeOfDay: AftideHomeTimeOfDay,
            distance: Float,
            steps: [VoyageStep],
            date: Date
        ) {
            self.view = view
            keyboardView = view as? VoyagingSceneKitView
            self.scene = view.scene
            if !capturedHomeRenderingSettings {
                capturedHomeRenderingSettings = true
                homePreferredFramesPerSecond = view.preferredFramesPerSecond
                homeContentScaleFactor = view.contentScaleFactor
                homeAntialiasingMode = view.antialiasingMode
            }
            self.timeOfDay = timeOfDay
            targetDistance = distance
            currentDistance = distance
            voyageSteps = steps
            currentDate = date
            stepsKey = voyageStepsKey(steps)
            camera = view.scene?.rootNode.childNode(withName: "homeCamera", recursively: false)
            cameraTarget = view.scene?.rootNode.childNode(
                withName: "homeCameraTarget",
                recursively: false
            )
            island = view.scene?.rootNode.childNode(withName: "homeIsland", recursively: false)
            stepIslets = view.scene?.rootNode.childNode(
                withName: "homeStepIslets",
                recursively: false
            )
            vessel = view.scene?.rootNode.childNode(withName: "homeVessel", recursively: false)
            timerBoatBob = vessel?.childNode(withName: "homeBoatBob", recursively: false)
            timerWake = vessel?.childNode(withName: "homeTimerWake", recursively: false)
            navigator = view.scene?.rootNode.childNode(
                withName: "homeNavigator",
                recursively: true
            )
            homeHarbor = view.scene?.rootNode.childNode(
                withName: "homeHarbor",
                recursively: false
            )
            seaMaterial = view.scene?.rootNode
                .childNode(withName: HomeIslandOceanEffects.surfaceNodeName, recursively: true)?
                .geometry?.firstMaterial
            moon = view.scene?.rootNode.childNode(
                withName: LandfallMoonEffects.rootNodeName,
                recursively: true
            )
            timerApproachingIsland = view.scene?.rootNode.childNode(
                withName: "timerApproachingIsland",
                recursively: false
            )
            LandfallMoonEffects.update(moon, phase: .current(at: date))
            gulls = (0..<3).compactMap {
                view.scene?.rootNode.childNode(withName: "homeGull\($0)", recursively: true)
            }
            startTime = nil
            lastTime = nil
            cameraPhase = .home
            editingRequested = false
            voyagingRequested = false
            doubleTapRecognizer?.isEnabled = false
            navigator?.isHidden = false
            timerWake?.opacity = 0
            configureHomeAccessibility()
            updateCamera(time: 0)
            view.setNeedsDisplay()
        }

        func setDate(_ date: Date) {
            currentDate = date
            LandfallMoonEffects.update(moon, phase: .current(at: date))
            view?.setNeedsDisplay()
        }

        func setDistance(_ value: Float) {
            targetDistance = value
            if reduceMotion || !active {
                currentDistance = value
                island?.position.x = value
                AftideHomeSceneFactory.layoutStepIslets(stepIslets, distance: value)
                if cameraPhase == .home {
                    updateCamera(time: 0)
                }
                view?.setNeedsDisplay()
            } else if cameraPhase == .editor {
                island?.position.x = value
            }
        }

        /// 下書きの増減・達成反転を、ホームと共有中の3D航路へ即時反映する。
        func setSteps(_ value: [VoyageStep]) {
            let key = voyageStepsKey(value)
            guard key != stepsKey else { return }
            let previousCount = voyageSteps.count
            voyageSteps = value
            stepsKey = key
            guard let root = scene?.rootNode else { return }

            stepIslets?.removeFromParentNode()
            let route = AftideHomeSceneFactory.makeStepIslets(
                steps: value,
                distance: currentDistance
            )
            root.addChildNode(route)
            stepIslets = route

            if value.count > previousCount, !reduceMotion {
                for node in route.childNodes.dropFirst(previousCount) {
                    let finalScale = node.scale.x
                    node.scale = SCNVector3(0.02, 0.02, 0.02)
                    let emerge = SCNAction.scale(to: CGFloat(finalScale), duration: 0.42)
                    emerge.timingMode = .easeOut
                    node.runAction(emerge, forKey: "home-step-islet-emerge")
                }
            }
            view?.setNeedsDisplay()
        }

        func setActive(_ value: Bool) {
            active = value
            guard let view else { return }
            let shouldAnimate = (value || editingRequested) && !reduceMotion
            view.rendersContinuously = shouldAnimate
            view.isPlaying = shouldAnimate
            if !shouldAnimate {
                seaMaterial?.setValue(
                    NSNumber(value: reduceMotion ? frozenOceanTime : HomeIslandOceanEffects.currentTime),
                    forKey: "uTime"
                )
                if cameraPhase == .home {
                    updateCamera(time: 0)
                } else if cameraPhase == .editor || cameraPhase == .timer {
                    applyOrbit()
                }
                view.setNeedsDisplay()
            }
        }

        func setReduceMotion(_ value: Bool) {
            guard reduceMotion != value else { return }
            reduceMotion = value
            if value {
                frozenOceanTime = HomeIslandOceanEffects.currentTime
                seaMaterial?.setValue(NSNumber(value: frozenOceanTime), forKey: "uTime")
                if cameraPhase == .departing || cameraPhase == .returning {
                    setVoyaging(voyagingRequested, animated: false, force: true)
                }
            }
            setActive(active)
        }

        /// 前面にSwiftUIのパネルが出ている間は、背後の港をVoiceOverや
        /// キーボードで操作できないようにする。閉じた瞬間に同じ世界へ戻す。
        func setHomeOverlayPresented(_ value: Bool) {
            guard homeOverlayPresented != value else { return }
            homeOverlayPresented = value
            guard cameraPhase == .home else {
                keyboardView?.capturesHarborKeyboard = false
                return
            }
            view?.isUserInteractionEnabled = !value
            configureHomeAccessibility()
        }

        /// ホームの船上視点と、航路全体を望む編集視点を同じシーン内で往復する。
        /// Scene/船/島は一度も作り直さない。
        func setEditing(_ value: Bool, animated: Bool = true) {
            guard !voyagingRequested else { return }
            guard value != editingRequested else { return }
            editingRequested = value
            guard let view, let camera, let cameraTarget else { return }

            camera.removeAllActions()
            cameraTarget.removeAllActions()
            let duration = reduceMotion || !animated ? 0 : 1.25
            let pose = value ? editorPose() : homePose(time: 0)
            cameraPhase = value ? .zoomingOut : .zoomingIn
            view.isUserInteractionEnabled = true
            view.isAccessibilityElement = false
            view.accessibilityCustomActions = nil
            keyboardView?.capturesHarborKeyboard = false
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
            camera.camera?.fieldOfView = value ? 48 : currentHomeProfile().fieldOfView
            homeHarbor?.opacity = value ? 0 : 1
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
                        self.navigator?.isHidden = false
                        self.scene?.fogStartDistance = 65
                        self.scene?.fogEndDistance = 220
                        self.updateCamera(time: 0)
                        self.configureHomeAccessibility()
                    }
                    self.onCameraTransitionCompleted(value)
                }
            }
            SCNTransaction.commit()
            view.setNeedsDisplay()
        }

        func setVoyageState(
            resting: Bool,
            elapsedSeconds: Int,
            showsIsland: Bool
        ) {
            voyageResting = resting
            let suppliedElapsed = Float(max(0, elapsedSeconds))
            voyageElapsedSeconds = voyagingRequested
                ? max(voyageElapsedSeconds, suppliedElapsed)
                : suppliedElapsed
            showsVoyageIsland = showsIsland
            if cameraPhase == .timer {
                timerApproachingIsland?.opacity = showsIsland ? 1 : 0
            } else if cameraPhase == .home, !voyagingRequested {
                timerApproachingIsland?.opacity = 0
            }
            placeTimerApproachingIsland()
        }

        /// Moves the existing home camera and vessel into the exact composition
        /// used by the timer. No SCNScene or ocean node is replaced.
        func setVoyaging(
            _ value: Bool,
            animated: Bool = true,
            force: Bool = false
        ) {
            guard force || value != voyagingRequested else { return }
            voyagingRequested = value
            guard let view, let camera, let cameraTarget, let vessel else { return }

            voyageTransitionGeneration &+= 1
            let generation = voyageTransitionGeneration

            camera.removeAllActions()
            cameraTarget.removeAllActions()
            vessel.removeAllActions()
            let duration = reduceMotion || !animated ? 0 : 1.55
            cameraPhase = value ? .departing : .returning
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            view.accessibilityCustomActions = nil
            keyboardView?.capturesHarborKeyboard = false
            doubleTapRecognizer?.isEnabled = false
            animateFog(
                toStart: value ? 12 : 65,
                end: value ? 34 : 220,
                duration: duration
            )

            if value {
                applyTimerRenderingSettings(to: view)
                navigator?.isHidden = false
                timerApproachingIsland?.isHidden = false
            }

            let pose = value ? timerPose() : homePose(time: 0)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = duration
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(
                controlPoints: value ? 0.18 : 0.36,
                value ? 0.76 : 0.0,
                value ? 0.22 : 0.22,
                1.0
            )
            camera.position = pose.position
            cameraTarget.position = pose.target
            camera.camera?.fieldOfView = value ? 38 : currentHomeProfile().fieldOfView
            camera.camera?.exposureOffset = 0.32
            camera.camera?.contrast = value ? 0.06 : 0.08
            camera.camera?.saturation = value ? 1.04 : 1.0
            camera.camera?.screenSpaceAmbientOcclusionIntensity = value ? 0.42 : 0
            camera.camera?.screenSpaceAmbientOcclusionRadius = value ? 1.25 : 0
            camera.camera?.screenSpaceAmbientOcclusionBias = value ? 0.025 : 0
            camera.camera?.screenSpaceAmbientOcclusionDepthThreshold = value ? 2.0 : 0
            vessel.scale = value
                ? SCNVector3(0.25, 0.25, 0.25)
                : SCNVector3(1, 1, 1)
            vessel.position = SCNVector3Zero
            vessel.eulerAngles.x = 0
            vessel.eulerAngles.y = value ? 0.1 : 0
            vessel.eulerAngles.z = 0
            timerBoatBob?.position = SCNVector3Zero
            timerBoatBob?.eulerAngles = SCNVector3Zero
            timerWake?.opacity = value ? 0.34 : 0
            island?.opacity = value ? 0 : 1
            stepIslets?.opacity = value ? 0 : 1
            homeHarbor?.opacity = value ? 0 : 1
            timerApproachingIsland?.opacity = value && showsVoyageIsland ? 1 : 0
            SCNTransaction.completionBlock = { [weak self] in
                DispatchQueue.main.async {
                    guard let self,
                          self.voyageTransitionGeneration == generation,
                          self.voyagingRequested == value
                    else { return }
                    if value {
                        self.cameraPhase = .timer
                        self.doubleTapRecognizer?.isEnabled = true
                        self.scene?.fogStartDistance = 12
                        self.scene?.fogEndDistance = 34
                        self.configureTimerOrbit()
                        view.isUserInteractionEnabled = true
                        view.isAccessibilityElement = true
                        view.accessibilityTraits.insert(.adjustable)
                        view.accessibilityLabel = LF.text("360° voyage view")
                        view.accessibilityHint = LF.text(
                            "Drag to look around. Pinch to zoom. Double-tap to reset the view."
                        )
                        self.updateAccessibilityValue()
                    } else {
                        self.cameraPhase = .home
                        self.doubleTapRecognizer?.isEnabled = false
                        self.scene?.fogStartDistance = 65
                        self.scene?.fogEndDistance = 220
                        self.navigator?.isHidden = false
                        self.timerApproachingIsland?.isHidden = true
                        self.timerApproachingIsland?.opacity = 0
                        self.restoreHomeRenderingSettings(on: view)
                        self.updateCamera(time: 0)
                        self.configureHomeAccessibility()
                    }
                    self.onVoyageTransitionCompleted(value)
                }
            }
            SCNTransaction.commit()
            view.setNeedsDisplay()
        }

        private func applyTimerRenderingSettings(to view: SCNView) {
            // The work timer can stay open for hours. Preserve the previous
            // native-resolution/4x-MSAA image while capping animation at 60fps
            // so ProMotion devices do not double the sustained GPU workload.
            view.preferredFramesPerSecond = 60
            view.contentScaleFactor = UIScreen.main.scale
            view.antialiasingMode = .multisampling4X
        }

        private func restoreHomeRenderingSettings(on view: SCNView) {
            view.preferredFramesPerSecond = homePreferredFramesPerSecond
            view.contentScaleFactor = homeContentScaleFactor
            view.antialiasingMode = homeAntialiasingMode
        }

        private func animateFog(
            toStart targetStart: CGFloat,
            end targetEnd: CGFloat,
            duration: TimeInterval
        ) {
            guard let scene else { return }
            scene.rootNode.removeAction(forKey: "home-timer-fog-transition")
            guard duration > 0 else {
                scene.fogStartDistance = targetStart
                scene.fogEndDistance = targetEnd
                return
            }
            let sourceStart = scene.fogStartDistance
            let sourceEnd = scene.fogEndDistance
            let action = SCNAction.customAction(duration: duration) { [weak scene] _, elapsed in
                let raw = min(max(elapsed / CGFloat(duration), 0), 1)
                let eased = raw * raw * (3 - 2 * raw)
                scene?.fogStartDistance = sourceStart + (targetStart - sourceStart) * eased
                scene?.fogEndDistance = sourceEnd + (targetEnd - sourceEnd) * eased
            }
            scene.rootNode.runAction(action, forKey: "home-timer-fog-transition")
        }

        private func timerPose() -> CameraPose {
            CameraPose(
                position: SCNVector3(-5.6, 2.4, 8.6),
                target: SCNVector3(0.8, 1.15, 0)
            )
        }

        private func configureTimerOrbit() {
            let pose = timerPose()
            let offset = SCNVector3(
                pose.position.x - pose.target.x,
                pose.position.y - pose.target.y,
                pose.position.z - pose.target.z
            )
            orbitRadius = sqrt(offset.x * offset.x + offset.y * offset.y + offset.z * offset.z)
            orbitAzimuth = atan2(offset.x, offset.z)
            orbitPolar = acos(max(-1, min(1, offset.y / orbitRadius)))
            targetOrbitRadius = orbitRadius
            targetOrbitAzimuth = orbitAzimuth
            targetOrbitPolar = orbitPolar
            minOrbitRadius = 4
            maxOrbitRadius = 16
            updateAccessibilityValue()
        }

        private func placeTimerApproachingIsland() {
            let k: Float = 1 + 1.2 * exp(-voyageElapsedSeconds / 1_500)
            timerApproachingIsland?.position = SCNVector3(6.5 * k, 0, -5.5 * k)
        }

        private func updateTimerMotion(time: Float, delta: Float) {
            guard let vessel else { return }
            if !voyageResting {
                voyageElapsedSeconds += delta
                placeTimerApproachingIsland()
            }
            let bobRate: Float = voyageResting ? 0.34 : 0.8
            let bob = timerBoatBob ?? vessel
            bob.position.y = sin(time * bobRate) * (voyageResting ? 0.025 : 0.06)
            bob.eulerAngles.z = sin(time * (voyageResting ? 0.28 : 0.6))
                * (voyageResting ? 0.012 : 0.03)
            bob.eulerAngles.x = sin(time * (voyageResting ? 0.25 : 0.5) + 1.2)
                * (voyageResting ? 0.007 : 0.015)
            bob.childNode(withName: "boatFlag", recursively: true)?
                .eulerAngles.y = sin(time * (voyageResting ? 1.2 : 5.2))
                    * (voyageResting ? 0.07 : 0.22)
            timerWake?.opacity = CGFloat(0.34 + sin(time * 1.4) * 0.07)
            if let scene {
                navigatorAnimator.bindIfNeeded(scene)
            }
            navigatorAnimator.pose = voyageResting ? .sit : PhoenixPose.selected
            navigatorAnimator.step(t: time, dt: delta)
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
            AftideHomeSceneFactory.layoutStepIslets(stepIslets, distance: currentDistance)
            seaMaterial?.setValue(
                NSNumber(value: HomeIslandOceanEffects.currentTime),
                forKey: "uTime"
            )
            if cameraPhase == .home {
                updateCamera(time: elapsed)
                if let scene {
                    navigatorAnimator.bindIfNeeded(scene)
                }
                navigatorAnimator.pose = PhoenixPose.selected
                navigatorAnimator.step(t: elapsed, dt: delta)
            } else if cameraPhase == .editor {
                updateOrbit(delta: delta)
            } else if cameraPhase == .timer {
                updateTimerMotion(time: elapsed, delta: delta)
                updateOrbit(delta: delta)
            } else if cameraPhase == .departing || cameraPhase == .returning {
                updateTimerMotion(time: elapsed, delta: delta)
            }
            updateGulls(time: elapsed)
        }

        private func updateCamera(time: Float) {
            guard let camera, let cameraTarget else { return }
            let profile = currentHomeProfile()
            let roll = active && !reduceMotion ? sin(time * 0.52) * 0.012 : 0
            let rise = active && !reduceMotion ? sin(time * 0.68 + 0.7) * 0.035 : 0
            // 港・船・航海士を同時に見せる三人称の港景色。世界座標は全端末共通で、
            // カメラだけを3段階に分けるためiPhone/iPad/Macで別世界にならない。
            camera.position = SCNVector3(
                profile.position.x,
                profile.position.y + rise,
                profile.position.z
            )
            camera.camera?.fieldOfView = profile.fieldOfView
            cameraTarget.position = profile.target
            camera.eulerAngles.z = roll * 0.55
            vessel?.position.y = rise * 0.45
            vessel?.eulerAngles.x = -roll * 0.55
            vessel?.eulerAngles.z = roll * 0.35
        }

        private struct CameraPose {
            var position: SCNVector3
            var target: SCNVector3
        }

        private func homePose(time: Float) -> CameraPose {
            let profile = currentHomeProfile()
            return CameraPose(
                position: profile.position,
                target: profile.target
            )
        }

        private func currentHomeProfile() -> HomeCameraProfile {
            let bounds = view?.bounds.size ?? .zero
            return HomeCameraProfile(
                aspect: bounds.width / max(bounds.height, 1),
                width: bounds.width
            )
        }

        private struct HomeCameraProfile {
            let position: SCNVector3
            let target: SCNVector3
            let fieldOfView: CGFloat

            init(aspect: CGFloat, width: CGFloat) {
                if width < 600 {
                    // iPhone縦は水平画角が最も狭い。港の両端を切らず、
                    // 船・航海士・6つの操作物を一枚に収める。
                    position = SCNVector3(-0.20, 7.50, 21.50)
                    target = SCNVector3(0.30, 0.80, -3.70)
                    fieldOfView = 46
                } else if width < 900 || aspect < 1.05 {
                    // iPad縦・Split View・小さなMacウインドウ。
                    position = SCNVector3(-0.50, 7.00, 17.50)
                    target = SCNVector3(0.30, 0.75, -3.70)
                    fieldOfView = 44
                } else {
                    // iPad横・Mac。左右の港全体を一枚の舞台として見せる。
                    position = SCNVector3(-1.00, 6.00, 14.50)
                    target = SCNVector3(0.40, 0.70, -3.50)
                    fieldOfView = 42
                }
            }
        }

        private func configureHomeAccessibility() {
            guard cameraPhase == .home, let view else { return }
            guard !homeOverlayPresented else {
                view.isUserInteractionEnabled = false
                view.isAccessibilityElement = false
                view.accessibilityCustomActions = nil
                keyboardView?.capturesHarborKeyboard = false
                return
            }
            view.isUserInteractionEnabled = true
            keyboardView?.capturesHarborKeyboard = true
            view.isAccessibilityElement = true
            view.accessibilityTraits = [.allowsDirectInteraction]
            view.accessibilityLabel = LF.text("Harbor")
            view.accessibilityHint = LF.text("Choose a place in the harbor.")
            view.accessibilityValue = nil
            view.accessibilityCustomActions = HomeHarborHotspot.allCases.map { hotspot in
                UIAccessibilityCustomAction(
                    name: hotspot.accessibilityLabel
                ) { [weak self] _ in
                    guard let self else { return false }
                    self.onActivateHotspot(hotspot)
                    Haptics.tap(.light)
                    return true
                }
            }
        }

        func cycleKeyboardHotspot(reverse: Bool) {
            guard cameraPhase == .home, !homeOverlayPresented else { return }
            let hotspots = HomeHarborHotspot.allCases
            guard !hotspots.isEmpty else { return }
            if let current = keyboardHotspotIndex {
                keyboardHotspotIndex = (current + (reverse ? -1 : 1) + hotspots.count)
                    % hotspots.count
            } else {
                keyboardHotspotIndex = reverse ? hotspots.count - 1 : 0
            }
            guard let index = keyboardHotspotIndex else { return }
            let hotspot = hotspots[index]
            if let node = scene?.rootNode.childNode(
                withName: "homeHotspot:\(hotspot.rawValue)",
                recursively: true
            ) {
                pulse(node)
            }
            view?.accessibilityValue = hotspot.accessibilityLabel
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(
                    notification: .announcement,
                    argument: hotspot.accessibilityLabel
                )
            }
        }

        func activateKeyboardHotspot() {
            guard cameraPhase == .home, !homeOverlayPresented else { return }
            let hotspots = HomeHarborHotspot.allCases
            guard !hotspots.isEmpty else { return }
            let index = keyboardHotspotIndex ?? 0
            keyboardHotspotIndex = index
            let hotspot = hotspots[index]
            onActivateHotspot(hotspot)
            Haptics.tap(.light)
        }

        func dismissHomeOverlay() {
            guard cameraPhase == .home else { return }
            onDismissHomeOverlay()
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
            guard cameraPhase == .editor || cameraPhase == .timer,
                  let camera,
                  let cameraTarget
            else { return }
            let target = cameraTarget.position
            camera.position = SCNVector3(
                target.x + orbitRadius * sin(orbitPolar) * sin(orbitAzimuth),
                target.y + orbitRadius * cos(orbitPolar),
                target.z + orbitRadius * sin(orbitPolar) * cos(orbitAzimuth)
            )
            view?.setNeedsDisplay()
        }

        @objc func onPan(_ gesture: UIPanGestureRecognizer) {
            guard cameraPhase == .editor || cameraPhase == .timer, let view else { return }
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
                let azimuthSensitivity: Float = cameraPhase == .timer
                    ? (2 * .pi / Float(max(view.bounds.height, 1)))
                    : 0.0034
                targetOrbitAzimuth -= Float(delta.x) * azimuthSensitivity
                targetOrbitPolar = max(
                    cameraPhase == .timer ? .pi * 0.12 : .pi * 0.26,
                    min(
                        cameraPhase == .timer ? .pi * 0.49 : .pi * 0.46,
                        targetOrbitPolar - Float(delta.y)
                            * (cameraPhase == .timer ? azimuthSensitivity : 0.0026)
                    )
                )
                if reduceMotion {
                    orbitAzimuth = targetOrbitAzimuth
                    orbitPolar = targetOrbitPolar
                    applyOrbit()
                }
            case .ended:
                // 指の速度を最大約7度の短い余韻へ変換。フリックで暴走はさせない。
                let velocity = gesture.velocity(in: view)
                let azimuthTail = max(-0.12, min(0.12, Float(velocity.x) * -0.000055))
                let polarTail = max(-0.06, min(0.06, Float(velocity.y) * -0.000035))
                targetOrbitAzimuth += azimuthTail
                targetOrbitPolar = max(
                    cameraPhase == .timer ? .pi * 0.12 : .pi * 0.26,
                    min(
                        cameraPhase == .timer ? .pi * 0.49 : .pi * 0.46,
                        targetOrbitPolar + polarTail
                    )
                )
                if reduceMotion {
                    orbitAzimuth = targetOrbitAzimuth
                    orbitPolar = targetOrbitPolar
                    applyOrbit()
                }
            default:
                break
            }
        }

        @objc func onPinch(_ gesture: UIPinchGestureRecognizer) {
            guard cameraPhase == .editor || cameraPhase == .timer else { return }
            if gesture.state == .changed {
                let scale = pow(Float(gesture.scale), 0.72)
                targetOrbitRadius = max(
                    minOrbitRadius,
                    min(maxOrbitRadius, targetOrbitRadius / scale)
                )
                gesture.scale = 1
                if reduceMotion {
                    orbitRadius = targetOrbitRadius
                    applyOrbit()
                }
                updateAccessibilityValue()
            }
        }

        @objc func onTapWorld(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            if cameraPhase == .home,
               let view,
               let hotspot = hotspot(at: gesture.location(in: view)) {
                pulse(hotspot.node)
                onActivateHotspot(hotspot.kind)
                Haptics.tap(.light)
                return
            }
            guard cameraPhase == .editor || cameraPhase == .timer else { return }
            onTapWorldAction()
        }

        @objc func onHover(_ gesture: UIHoverGestureRecognizer) {
            guard cameraPhase == .home, let view else {
                hoveredHotspotNode = nil
                return
            }
            switch gesture.state {
            case .began, .changed:
                guard let result = hotspot(at: gesture.location(in: view)) else {
                    hoveredHotspotNode = nil
                    return
                }
                guard hoveredHotspotNode !== result.node else { return }
                hoveredHotspotNode = result.node
                keyboardHotspotIndex = HomeHarborHotspot.allCases.firstIndex(of: result.kind)
                pulse(result.node)
            case .ended, .cancelled, .failed:
                hoveredHotspotNode = nil
            default:
                break
            }
        }

        private func hotspot(
            at point: CGPoint
        ) -> (kind: HomeHarborHotspot, node: SCNNode)? {
            guard let view else { return nil }
            let results = view.hitTest(
                point,
                options: [
                    SCNHitTestOption.categoryBitMask: HomeHarborHitTest.categoryBitMask,
                    SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue,
                    SCNHitTestOption.ignoreHiddenNodes: true,
                    SCNHitTestOption.boundingBoxOnly: false
                ]
            )
            for result in results {
                var node: SCNNode? = result.node
                while let current = node {
                    if let name = current.name,
                       name.hasPrefix("homeHotspot:"),
                       let kind = HomeHarborHotspot(
                           rawValue: String(name.dropFirst("homeHotspot:".count))
                       ) {
                        return (kind, current)
                    }
                    if current.name == "homeVessel" {
                        return (.work, current)
                    }
                    if current.name == "homeIsland" {
                        return (.destination, current)
                    }
                    node = current.parent
                }
            }
            return nil
        }

        private func pulse(_ node: SCNNode) {
            guard !reduceMotion else { return }
            node.removeAction(forKey: "home-hotspot-pulse")
            let original = node.scale
            let up = SCNAction.scale(
                to: CGFloat(original.x * 1.06),
                duration: 0.10
            )
            up.timingMode = .easeOut
            let down = SCNAction.customAction(duration: 0.16) { target, elapsed in
                let progress = min(1, max(0, elapsed / 0.16))
                let factor = 1.06 - 0.06 * progress
                target.scale = SCNVector3(
                    original.x * Float(factor),
                    original.y * Float(factor),
                    original.z * Float(factor)
                )
            }
            down.timingMode = .easeInEaseOut
            node.runAction(.sequence([up, down]), forKey: "home-hotspot-pulse")
        }

        @objc func onDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard cameraPhase == .timer, gesture.state == .ended else { return }
            configureTimerOrbit()
            applyOrbit()
            updateAccessibilityValue()
            Haptics.tap(.soft)
        }

        func accessibilityZoom(by factor: Float) {
            guard cameraPhase == .timer else { return }
            targetOrbitRadius = max(
                minOrbitRadius,
                min(maxOrbitRadius, targetOrbitRadius * factor)
            )
            if reduceMotion {
                orbitRadius = targetOrbitRadius
                applyOrbit()
            }
            updateAccessibilityValue()
            Haptics.tap(.light)
        }

        private func updateAccessibilityValue() {
            guard cameraPhase == .timer, let view else { return }
            let initial = timerPose()
            let dx = initial.position.x - initial.target.x
            let dy = initial.position.y - initial.target.y
            let dz = initial.position.z - initial.target.z
            let initialRadius = sqrt(dx * dx + dy * dy + dz * dz)
            let magnification = Int((initialRadius / max(targetOrbitRadius, 0.01) * 100).rounded())
            view.accessibilityValue = LF.format("Zoom %lld%%", Int64(magnification))
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
        distance: Float,
        steps: [VoyageStep],
        date: Date = .now
    ) -> SCNScene {
        let palette = timeOfDay.palette
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        scene.fogColor = UIColor(rgb: palette.fog)
        scene.fogStartDistance = 65
        scene.fogEndDistance = 220
        scene.fogDensityExponent = 1

        let ocean = HomeIslandOceanEffects.makeScene(layout: .voyageHome)
        scene.rootNode.addChildNode(ocean.root)
        let vessel = makeNavigatorPOVBoat()
        markHotspot(vessel, as: .work)
        scene.rootNode.addChildNode(vessel)
        scene.rootNode.addChildNode(makeHomeHarbor(palette: palette))
        scene.rootNode.addChildNode(makeStepIslets(steps: steps, distance: distance))

        // 目的地詳細・航海中・共有画面と同じ作り込まれた島を使い、
        // ホームだけ簡略化された山に戻らないよう一つのモデルへ統一する。
        let island = VoyageSceneKit.makeIsland(
            position: SCNVector3Zero,
            scale: SCNVector3(1, 1, 1)
        )
        island.name = "homeIsland"
        markHotspot(island, as: .destination)
        island.position = SCNVector3(distance, 0, 0)
        island.scale = SCNVector3(
            AftideHomeWorldReference.islandScale,
            AftideHomeWorldReference.islandScale,
            AftideHomeWorldReference.islandScale
        )
        scene.rootNode.addChildNode(island)

        // Kept in the same world and revealed only after departure. Its scale
        // and route match the existing timer scene, while the home destination
        // can fade away without rebuilding the SceneKit hierarchy.
        let timerIsland = SCNNode()
        timerIsland.name = "timerApproachingIsland"
        timerIsland.scale = SCNVector3(0.7, 0.7, 0.7)
        timerIsland.opacity = 0
        timerIsland.addChildNode(VoyageSceneKit.makeIsland())
        scene.rootNode.addChildNode(timerIsland)

        // 縦長画面でも日月が左上UIへ潜らず、Web版と同じ空の中央寄りに見える位置。
        let celestialZ: Float = -2.5
        let celestial = makeCelestial(
            moon: palette.moon,
            color: UIColor(rgb: palette.reflection),
            phase: .current(at: date)
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
        // Match My Island so the shared constant-material sea has the same
        // luminance here instead of appearing roughly 0.4 EV darker.
        cameraComponent.exposureOffset = 0.32
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

    /// ホームの船(原点)から目的地までを結ぶ中継島群。ステップ数と島数を必ず一致させる。
    static func makeStepIslets(steps: [VoyageStep], distance: Float) -> SCNNode {
        let route = SCNNode()
        route.name = "homeStepIslets"
        for (index, step) in steps.enumerated() {
            route.addChildNode(
                VoyageSceneKit.makeStepIslet(
                    index: index,
                    total: steps.count,
                    done: step.done,
                    doneAt: step.doneAt
                )
            )
        }
        layoutStepIslets(route, distance: distance)
        return route
    }

    /// 目的地が進捗で近づいても、各島を船と目的地の間へ均等に保つ。
    static func layoutStepIslets(_ route: SCNNode?, distance: Float) {
        guard let route else { return }
        let islets = route.childNodes
        guard !islets.isEmpty else { return }
        let count = islets.count
        let spacing = distance / Float(count + 1)
        // 着岸直前でも重なりすぎないよう、群島全体だけを段階的に縮小する。
        let routeScale = min(1.38, max(0.46, spacing / 2.4))
        for (index, islet) in islets.enumerated() {
            let progress = Float(index + 1) / Float(count + 1)
            let lane = Float(index % 3) - 1
            let routeX = distance * progress
            // 船上カメラから離れるほど透視で急激に小さくなるため、距離に比例して補正する。
            // これによりホーム上の見かけは、手前の船と同程度の存在感を保つ。
            let perspectiveCompensation = 1 + routeX / 18
            let perspectiveScale = routeScale * perspectiveCompensation
            let laneWidth = 1.35 + min(perspectiveScale, 6) * 0.42
            islet.position = SCNVector3(routeX, 0, lane * laneWidth)
            islet.scale = SCNVector3(perspectiveScale, perspectiveScale, perspectiveScale)
            // 島と一緒に日付文字まで巨大化させず、従来の読みやすい大きさを保つ。
            if let dateLabel = islet.childNode(withName: "step_date", recursively: false) {
                let labelScale = 0.80 / perspectiveCompensation
                dateLabel.scale = SCNVector3(labelScale, labelScale, labelScale)
            }
            // 達成旗も遠近補正で巨大化させず、島の小さな印に留める。
            if let flag = islet.childNode(withName: "step_flag", recursively: false) {
                let flagScale = 0.62 / perspectiveCompensation
                flag.scale = SCNVector3(flagScale, flagScale, flagScale)
            }
        }
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
        let bob = SCNNode()
        bob.name = "homeBoatBob"
        bob.addChildNode(boat)
        vessel.addChildNode(bob)

        // Keep the existing timer wake in this world as well. The wrapper
        // compensates for the 2.2x home boat so the departure endpoint is the
        // original timer's exact effective 0.55 scale.
        let wakeWrapper = SCNNode()
        wakeWrapper.name = "homeTimerWake"
        wakeWrapper.scale = SCNVector3(2.2, 2.2, 2.2)
        wakeWrapper.opacity = 0
        wakeWrapper.addChildNode(VoyageSceneKit.makeWake())
        vessel.addChildNode(wakeWrapper)
        return vessel
    }

    /// 船の背後にある小さな港。機能ボタンを並べるのではなく、積荷・本・鐘・
    /// 衣装箱・島模型そのものが入口になる。すべてプリミティブなので画面密度や
    /// OSに依存せず、iPhone / iPad / Designed for iPad on Macで同じ世界を共有できる。
    private static func makeHomeHarbor(palette: AftideHomePalette) -> SCNNode {
        let root = SCNNode()
        root.name = "homeHarbor"

        let wood = UIColor(rgb: 0x7A5134)
        let darkWood = UIColor(rgb: 0x4C2F22)
        let rope = UIColor(rgb: 0xD8C69C)
        let brass = UIColor(rgb: 0xD5B56D)
        let paper = UIColor(rgb: 0xEADEBD)
        let ink = UIColor(rgb: 0x173F3C)
        let moss = UIColor(rgb: 0x5D8B72)

        let deckGeometry = SCNBox(
            width: 10.0,
            height: 0.28,
            length: 4.6,
            chamferRadius: 0.08
        )
        deckGeometry.widthSegmentCount = 8
        deckGeometry.firstMaterial = lit(wood, roughness: 0.92)
        let deck = SCNNode(geometry: deckGeometry)
        deck.position = SCNVector3(0.20, 0.20, -4.05)
        root.addChildNode(deck)

        // 船と港を一続きに見せる短い渡り板。
        let gangwayGeometry = SCNBox(
            width: 1.25,
            height: 0.16,
            length: 3.1,
            chamferRadius: 0.04
        )
        gangwayGeometry.firstMaterial = lit(wood, roughness: 0.9)
        let gangway = SCNNode(geometry: gangwayGeometry)
        gangway.position = SCNVector3(-2.15, 0.18, -1.85)
        gangway.eulerAngles.y = -0.08
        root.addChildNode(gangway)

        for x: Float in [-3.65, -1.65, 0.35, 2.35, 4.35] {
            let post = SCNNode(
                geometry: SCNCylinder(radius: 0.105, height: 1.24)
            )
            post.geometry?.firstMaterial = lit(darkWood, roughness: 0.94)
            post.position = SCNVector3(x, 0.45, -4.45)
            root.addChildNode(post)
        }

        // 積荷：作業項目と出航。
        let cargo = hotspotRoot(.work, label: LF.text("Work items"), at: SCNVector3(-3.40, 0.34, -2.70))
        for (offset, size) in [
            (SCNVector3(-0.34, 0.30, 0.02), SCNVector3(0.62, 0.60, 0.62)),
            (SCNVector3(0.31, 0.25, 0.07), SCNVector3(0.58, 0.50, 0.54)),
            (SCNVector3(0.02, 0.78, -0.03), SCNVector3(0.52, 0.48, 0.50))
        ] {
            let box = SCNBox(
                width: CGFloat(size.x),
                height: CGFloat(size.y),
                length: CGFloat(size.z),
                chamferRadius: 0.035
            )
            box.firstMaterial = lit(wood, roughness: 0.94)
            let node = SCNNode(geometry: box)
            node.position = offset
            cargo.addChildNode(node)
        }
        addRopeBand(to: cargo, color: rope)
        root.addChildNode(cargo)

        // 衣装箱：航海士の装い。
        let style = hotspotRoot(.style, label: LF.text("Style"), at: SCNVector3(-3.40, 0.34, -4.15))
        let chest = SCNBox(width: 1.10, height: 0.64, length: 0.72, chamferRadius: 0.10)
        chest.firstMaterial = lit(darkWood, roughness: 0.88)
        let chestNode = SCNNode(geometry: chest)
        chestNode.position.y = 0.33
        style.addChildNode(chestNode)
        let chestBand = SCNBox(width: 0.16, height: 0.69, length: 0.76, chamferRadius: 0.02)
        chestBand.firstMaterial = lit(brass, roughness: 0.46)
        let chestBandNode = SCNNode(geometry: chestBand)
        chestBandNode.position.y = 0.33
        style.addChildNode(chestBandNode)
        root.addChildNode(style)

        // 航海誌：開いた本を載せた低い書見台。
        let logbook = hotspotRoot(.logbook, label: LF.text("Logbook"), at: SCNVector3(3.55, 0.34, -5.55))
        let stand = SCNCylinder(radius: 0.42, height: 0.58)
        stand.radialSegmentCount = 8
        stand.firstMaterial = lit(darkWood, roughness: 0.9)
        let standNode = SCNNode(geometry: stand)
        standNode.position.y = 0.29
        logbook.addChildNode(standNode)
        for sign: Float in [-1, 1] {
            let page = SCNBox(width: 0.53, height: 0.035, length: 0.68, chamferRadius: 0.025)
            page.firstMaterial = lit(paper, roughness: 0.96)
            let pageNode = SCNNode(geometry: page)
            pageNode.position = SCNVector3(sign * 0.25, 0.66, 0)
            pageNode.eulerAngles.z = sign * -0.16
            logbook.addChildNode(pageNode)
        }
        root.addChildNode(logbook)

        // 港：遠くからも見分けやすい真鍮の鐘。
        let harbor = hotspotRoot(.harbor, label: LF.text("Harbor"), at: SCNVector3(-3.40, 0.34, -5.55))
        let bellPost = SCNNode(geometry: SCNCylinder(radius: 0.10, height: 1.24))
        bellPost.geometry?.firstMaterial = lit(darkWood, roughness: 0.9)
        bellPost.position.y = 0.62
        harbor.addChildNode(bellPost)
        let arm = SCNNode(geometry: SCNBox(width: 0.92, height: 0.10, length: 0.12, chamferRadius: 0.03))
        arm.geometry?.firstMaterial = lit(darkWood, roughness: 0.9)
        arm.position = SCNVector3(0.22, 1.12, 0)
        harbor.addChildNode(arm)
        let bell = SCNNode(geometry: SCNCone(topRadius: 0.12, bottomRadius: 0.31, height: 0.42))
        bell.geometry?.firstMaterial = lit(brass, roughness: 0.42, doubleSided: true)
        bell.position = SCNVector3(0.46, 0.84, 0)
        harbor.addChildNode(bell)
        root.addChildNode(harbor)

        // 自分の島：苔色の小さな島模型。
        let island = hotspotRoot(.island, label: PlayerProfile.islandName, at: SCNVector3(3.55, 0.34, -4.15))
        let pedestal = SCNCylinder(radius: 0.58, height: 0.18)
        pedestal.radialSegmentCount = 10
        pedestal.firstMaterial = lit(darkWood, roughness: 0.9)
        let pedestalNode = SCNNode(geometry: pedestal)
        pedestalNode.position.y = 0.09
        island.addChildNode(pedestalNode)
        for (x, height, radius): (Float, CGFloat, CGFloat) in [
            (-0.22, 0.68, 0.34),
            (0.18, 0.92, 0.42),
            (0.43, 0.55, 0.28)
        ] {
            let hill = SCNCone(topRadius: 0.02, bottomRadius: radius, height: height)
            hill.radialSegmentCount = 7
            hill.firstMaterial = lit(moss, roughness: 0.96)
            let hillNode = SCNNode(geometry: hill)
            hillNode.position = SCNVector3(x, Float(height) * 0.5 + 0.18, 0)
            island.addChildNode(hillNode)
        }
        root.addChildNode(island)

        // 目的地の操作台。遠い島自体も押せるが、未設定時も入口を失わない。
        let destination = hotspotRoot(
            .destination,
            label: LF.text("Destinations"),
            at: SCNVector3(3.55, 0.34, -2.70)
        )
        let mapTable = SCNCylinder(radius: 0.56, height: 0.63)
        mapTable.radialSegmentCount = 8
        mapTable.firstMaterial = lit(wood, roughness: 0.91)
        let mapTableNode = SCNNode(geometry: mapTable)
        mapTableNode.position.y = 0.315
        destination.addChildNode(mapTableNode)
        let compass = SCNTorus(ringRadius: 0.31, pipeRadius: 0.045)
        compass.ringSegmentCount = 16
        compass.pipeSegmentCount = 5
        compass.firstMaterial = lit(brass, roughness: 0.44)
        let compassNode = SCNNode(geometry: compass)
        compassNode.position.y = 0.66
        destination.addChildNode(compassNode)
        for angle in stride(from: Float.zero, to: Float.pi * 2, by: Float.pi / 4) {
            let needle = cylinder(
                from: SCNVector3Zero,
                to: SCNVector3(cos(angle) * 0.25, 0, sin(angle) * 0.25),
                radius: 0.018,
                color: ink
            )
            needle.position.y += 0.68
            destination.addChildNode(needle)
        }
        root.addChildNode(destination)

        // 温かい港灯。灯りだけでなく器も残し、昼間もシルエットが読める。
        for x: Float in [-3.65, 4.35] {
            let lantern = SCNNode()
            let pole = SCNNode(geometry: SCNCylinder(radius: 0.075, height: 1.65))
            pole.geometry?.firstMaterial = lit(darkWood, roughness: 0.92)
            pole.position.y = 0.825
            lantern.addChildNode(pole)
            let glow = SCNNode(geometry: SCNSphere(radius: 0.17))
            glow.geometry?.firstMaterial = constant(UIColor(rgb: 0xF3C065).withAlphaComponent(0.92))
            glow.position.y = 1.55
            lantern.addChildNode(glow)
            let light = SCNLight()
            light.type = .omni
            light.color = UIColor(rgb: 0xF3C065)
            light.intensity = palette.moon ? 230 : 70
            light.attenuationStartDistance = 0.5
            light.attenuationEndDistance = 5
            glow.light = light
            lantern.position = SCNVector3(x, 0.34, -4.10)
            root.addChildNode(lantern)
        }

        return root
    }

    private static func hotspotRoot(
        _ hotspot: HomeHarborHotspot,
        label: String,
        at position: SCNVector3
    ) -> SCNNode {
        let root = SCNNode()
        root.position = position
        markHotspot(root, as: hotspot)

        let ring = SCNTorus(ringRadius: 0.64, pipeRadius: 0.018)
        ring.ringSegmentCount = 24
        ring.pipeSegmentCount = 5
        ring.firstMaterial = constant(UIColor(rgb: 0xF3C065).withAlphaComponent(0.60))
        let ringNode = SCNNode(geometry: ring)
        ringNode.position.y = 0.035
        root.addChildNode(ringNode)

        let hitBox = SCNBox(width: 1.48, height: 1.65, length: 1.22, chamferRadius: 0.08)
        let hitMaterial = constant(UIColor.white.withAlphaComponent(0.001))
        hitMaterial.writesToDepthBuffer = false
        hitMaterial.readsFromDepthBuffer = false
        hitBox.firstMaterial = hitMaterial
        let hitNode = SCNNode(geometry: hitBox)
        hitNode.position.y = 0.78
        hitNode.categoryBitMask = HomeHarborHitTest.categoryBitMask
        root.addChildNode(hitNode)

        let textGeometry = SCNText(string: label, extrusionDepth: 0.012)
        textGeometry.font = UIFont.systemFont(ofSize: 0.62, weight: .bold)
        textGeometry.flatness = 0.08
        textGeometry.firstMaterial = constant(UIColor(rgb: 0x173F3C))
        let textNode = SCNNode(geometry: textGeometry)
        let bounds = textGeometry.boundingBox
        textNode.pivot = SCNMatrix4MakeTranslation(
            (bounds.max.x + bounds.min.x) * 0.5,
            bounds.min.y,
            0
        )
        let labelScale: Float = 0.24
        textNode.scale = SCNVector3(labelScale, labelScale, labelScale)
        textNode.position.z = 0.031

        let textWidth = CGFloat(bounds.max.x - bounds.min.x) * CGFloat(labelScale)
        let plate = SCNBox(
            width: max(0.88, textWidth + 0.28),
            height: 0.38,
            length: 0.045,
            chamferRadius: 0.10
        )
        plate.firstMaterial = constant(UIColor(rgb: 0xF4EBD7).withAlphaComponent(0.92))
        let plateNode = SCNNode(geometry: plate)

        let labelNode = SCNNode()
        labelNode.position = SCNVector3(0, 1.62, 0.05)
        labelNode.addChildNode(plateNode)
        labelNode.addChildNode(textNode)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .Y
        labelNode.constraints = [billboard]
        root.addChildNode(labelNode)
        return root
    }

    private static func markHotspot(_ node: SCNNode, as hotspot: HomeHarborHotspot) {
        if node.name == nil {
            node.name = "homeHotspot:\(hotspot.rawValue)"
        }
        node.categoryBitMask = HomeHarborHitTest.categoryBitMask
        node.enumerateChildNodes { child, _ in
            child.categoryBitMask = HomeHarborHitTest.categoryBitMask
        }
    }

    private static func addRopeBand(to root: SCNNode, color: UIColor) {
        for x: Float in [-0.34, 0.34] {
            let band = SCNNode(geometry: SCNBox(width: 0.06, height: 1.18, length: 0.70, chamferRadius: 0.02))
            band.geometry?.firstMaterial = lit(color, roughness: 0.96)
            band.position = SCNVector3(x, 0.52, 0)
            root.addChildNode(band)
        }
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

    private static func makeCelestial(
        moon: Bool,
        color: UIColor,
        phase: LandfallLunarPhase
    ) -> SCNNode {
        if moon {
            return LandfallMoonEffects.makeNode(phase: phase)
        }
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
