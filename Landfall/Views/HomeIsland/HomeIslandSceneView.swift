import SceneKit
import SwiftUI
import UIKit
import simd

/// 「自分の島」のカメラ操作バーからSceneKitへ送る一回限りの指示。
enum HomeIslandCameraAction: Equatable {
    case reset
    case moveForward
    case moveBackward
    case moveLeft
    case moveRight
    case zoomIn
    case zoomOut
}

struct HomeIslandCameraRequest: Equatable {
    let id = UUID()
    let action: HomeIslandCameraAction
}

/// カメラモードのシャッターをSceneKitへ一度だけ届けるための要求。
struct HomeIslandCaptureRequest: Equatable {
    let id = UUID()
}

/// SwiftUIの船ボタンをSceneKit上の乗船判定へ一度だけ届けるための要求。
struct HomeIslandBoatBoardingRequest: Equatable {
    let id = UUID()
}

enum HomeIslandPlacementRejection: Equatable {
    /// A spot the island keeps for itself: the step off the jetty, or the
    /// notice board. Props never reserve space from each other.
    case reserved
    case outsideBuildArea
    case coastRequired
    /// This kind of prop has reached its per-island limit.
    case limitReached
}

enum HomeIslandMode: Equatable {
    case arrival
    case explore
    case edit
    case camera
    case departure
}

/// Close third-person construction framing. Editing should feel like the
/// navigator is shaping the place they live in, not operating a distant map.
private enum HomeIslandBuildCameraTuning {
    static let elevation: Float = 0.34
    static let radius: Float = 8.4
    static let minimumRadius: Float = 4.6
    // Far enough back to frame the whole island while arranging it.
    static let maximumRadius: Float = 26.0
    static let targetHeight: Float = 0.72
    static let fieldOfView: CGFloat = 46
    static let horizontalTargetLimit: Float = 18
}

/// A network-neutral snapshot of one navigator in a shared Home Island scene.
/// Firestore-specific timestamps and room metadata stay in the multiplayer
/// service; SceneKit only needs a stable identity and the visible pose.
struct HomeIslandRemotePlayerState: Identifiable, Equatable, Sendable {
    let id: String
    var x: Float
    var z: Float
    var yaw: Float
    var pose: String
    var scene: String
    var phase: String
    var seatPlacementID: String?
    var seatSlotID: String?
    var arrivalNonce: String?
    var isVisible: Bool

    init(
        id: String,
        x: Float,
        z: Float,
        yaw: Float,
        pose: String = PhoenixPose.idle.rawValue,
        scene: String = "island",
        phase: String = "explore",
        seatPlacementID: String? = nil,
        seatSlotID: String? = nil,
        arrivalNonce: String? = nil,
        isVisible: Bool = true
    ) {
        self.id = id
        self.x = x
        self.z = z
        self.yaw = yaw
        self.pose = pose
        self.scene = scene
        self.phase = phase
        self.seatPlacementID = seatPlacementID
        self.seatSlotID = seatSlotID
        self.arrivalNonce = arrivalNonce
        self.isVisible = isVisible
    }

    var phoenixPose: PhoenixPose {
        PhoenixPose(rawValue: pose) ?? .idle
    }
}

/// Simulatorや外付けキーボードで、WASD/矢印キーを長押しして移動するためのSceneKitビュー。
/// UIKeyCommandの単発入力ではなく押下状態を毎フレーム渡すため、斜め移動も滑らかに扱える。
private final class HomeIslandInteractiveSceneView: SCNView {
    var keyboardMovementHandler: ((HomeIslandWalkInput, TimeInterval) -> Void)?
    var gamepadMovementHandler: ((HomeIslandWalkInput, TimeInterval) -> Void)?
    var gamepadLookHandler: ((_ x: Float, _ y: Float, _ deltaTime: TimeInterval) -> Void)?

    private var heldMovementKeys: Set<UIKeyboardHIDUsage> = []
    private var keyboardDisplayLink: CADisplayLink?
    private var lastKeyboardTimestamp: CFTimeInterval?
    private let gamepadRouter = HomeIslandGamepadInputRouter()

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            becomeFirstResponder()
            gamepadRouter.movementHandler = { [weak self] input, deltaTime in
                self?.gamepadMovementHandler?(input, deltaTime)
            }
            gamepadRouter.lookHandler = { [weak self] x, y, deltaTime in
                self?.gamepadLookHandler?(x, y, deltaTime)
            }
            gamepadRouter.start()
        } else {
            stopKeyboardMovement()
            gamepadRouter.stop()
        }
    }

    override func resignFirstResponder() -> Bool {
        stopKeyboardMovement()
        return super.resignFirstResponder()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let movementKeys = Set(presses.compactMap(\.key?.keyCode).filter(isHandledKey))
        guard !movementKeys.isEmpty else {
            super.pressesBegan(presses, with: event)
            return
        }
        heldMovementKeys.formUnion(movementKeys)
        startKeyboardMovementIfNeeded()
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        releaseMovementKeys(from: presses)
        let containsOnlyMovementKeys = presses.allSatisfy {
            $0.key.map { isHandledKey($0.keyCode) } ?? false
        }
        if !containsOnlyMovementKeys { super.pressesEnded(presses, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        releaseMovementKeys(from: presses)
        super.pressesCancelled(presses, with: event)
    }

    private func isMovementKey(_ key: UIKeyboardHIDUsage) -> Bool {
        switch key {
        case .keyboardW, .keyboardA, .keyboardS, .keyboardD,
             .keyboardUpArrow, .keyboardDownArrow, .keyboardLeftArrow, .keyboardRightArrow:
            return true
        default:
            return false
        }
    }

    private func isHandledKey(_ key: UIKeyboardHIDUsage) -> Bool {
        isMovementKey(key)
            || key == .keyboardLeftShift
            || key == .keyboardRightShift
            || key == .keyboardSpacebar
    }

    private func releaseMovementKeys(from presses: Set<UIPress>) {
        for press in presses {
            if let key = press.key?.keyCode { heldMovementKeys.remove(key) }
        }
        if heldMovementKeys.isEmpty { stopKeyboardMovement() }
    }

    private func startKeyboardMovementIfNeeded() {
        guard keyboardDisplayLink == nil else { return }
        lastKeyboardTimestamp = nil
        let displayLink = CADisplayLink(target: self, selector: #selector(handleKeyboardFrame(_:)))
        displayLink.add(to: .main, forMode: .common)
        keyboardDisplayLink = displayLink
    }

    private func stopKeyboardMovement() {
        heldMovementKeys.removeAll()
        keyboardDisplayLink?.invalidate()
        keyboardDisplayLink = nil
        lastKeyboardTimestamp = nil
        keyboardMovementHandler?(.zero, 0)
    }

    @objc private func handleKeyboardFrame(_ displayLink: CADisplayLink) {
        guard !heldMovementKeys.isEmpty else {
            stopKeyboardMovement()
            return
        }
        let previousTimestamp = lastKeyboardTimestamp ?? displayLink.timestamp
        let deltaTime = min(max(displayLink.timestamp - previousTimestamp, 0), 0.05)
        lastKeyboardTimestamp = displayLink.timestamp

        let left = heldMovementKeys.contains(.keyboardA)
            || heldMovementKeys.contains(.keyboardLeftArrow)
        let right = heldMovementKeys.contains(.keyboardD)
            || heldMovementKeys.contains(.keyboardRightArrow)
        let forward = heldMovementKeys.contains(.keyboardW)
            || heldMovementKeys.contains(.keyboardUpArrow)
        let backward = heldMovementKeys.contains(.keyboardS)
            || heldMovementKeys.contains(.keyboardDownArrow)
        let sprint = heldMovementKeys.contains(.keyboardLeftShift)
            || heldMovementKeys.contains(.keyboardRightShift)
        let jump = heldMovementKeys.contains(.keyboardSpacebar)
        let digitalStrength: Float = sprint ? 1 : 0.72
        var input = HomeIslandWalkInput(
            x: ((right ? 1 : 0) - (left ? 1 : 0)) * digitalStrength,
            forward: ((forward ? 1 : 0) - (backward ? 1 : 0)) * digitalStrength,
            sprintRequested: sprint,
            jumpRequested: jump
        )
        let magnitude = sqrt(input.x * input.x + input.forward * input.forward)
        if magnitude > 1 {
            input.x /= magnitude
            input.forward /= magnitude
        }
        keyboardMovementHandler?(input, deltaTime)
    }
}

/// いま向かっている目的地を、島の海の景色として描くための最小の入力。
/// 進捗だけを渡し、距離・大きさ・向きは `HomeIslandMetrics` が決める。
struct HomeIslandDestinationBearing: Equatable {
    var name: String
    var progressRatio: Double
}

/// The consumer home-island canvas.  It intentionally exposes only placement,
/// selection and camera gestures; none of 3D Studio's terrain or transform tools
/// are reachable from this scene.
struct HomeIslandSceneView: UIViewRepresentable {
    @ObservedObject var store: HomeIslandStore
    @Binding var placementAssetID: String?
    var playerLevel: Int
    var cameraResetToken: Int
    var cameraRequest: HomeIslandCameraRequest?
    var captureRequest: HomeIslandCaptureRequest?
    var boatBoardingRequest: HomeIslandBoatBoardingRequest?
    var mode: HomeIslandMode
    /// 歩いているときの明るさ。写真モードのスライダはここからの増減。
    static let baseExposureOffset: Float = 0.82
    /// 写真モードでの増減(EV)。0 のあいだは歩いているときと同じ明るさ。
    var cameraExposureOffset: Float
    var cameraInteractionLocked: Bool
    var walkInput: HomeIslandWalkInput
    /// 飾りを掴んだ瞬間。移動は指を離した位置で確定するので、HUDはこの
    /// あいだだけ「動かしています」の顔をしていればよい。
    var onMoveBegan: () -> Void = {}
    var onMoveCompleted: () -> Void
    var onMoveBlockedChanged: (Bool) -> Void = { _ in }
    var onPlacementCompleted: (UUID) -> Void
    var onPlacementRejected: (HomeIslandPlacementRejection) -> Void
    /// Also carries the build-mode pickup as `carry:<uuid>`; see `handleLongPress`.
    var onAssetActivated: (String) -> Void
    var onAssetInteractionDenied: (String) -> Void
    var onArrivalCompleted: () -> Void
    var onJettyPresenceChanged: (Bool) -> Void
    /// Reports whether the navigator stands close enough to the fixed notice
    /// board for a tap on it to be the obvious next action.
    var onNoticeBoardProximityChanged: (Bool) -> Void = { _ in }
    var onBoatBoardingStarted: () -> Void
    var onDepartureCompleted: () -> Void
    var onCaptured: (UUID, UIImage) -> Void
    /// Home-embedded worlds start with the boat already moored instead of
    /// replaying the standalone island arrival sequence.
    var startsMooredAtIsland = false
    /// A showcase host may keep the island in a fixed overview. The interactive
    /// home disables this so walking, editing and camera controls retain their
    /// standalone behaviour after the arrival sequence is skipped.
    var locksMooredOverview = true
    /// In the app home, touching the boat opens the work-item selection UI. The
    /// existing standalone behavior still boards immediately when this is false.
    var boatTapOpensSelection = false
    /// The home HUD can temporarily turn the island camera into a boat showcase.
    /// This remains separate from `mode` so editing, photography and boarding
    /// keep their existing state machines.
    var boatCustomizationActive = false
    var boatAppearanceID = BoatCustomization.selectedSailID
    /// 自分の島では、航海士を触ると色を替える小さな表示が出る。
    /// 訪問先や見せるだけの島では触っても何も起きない。
    var navigatorTapOpensColors = false
    var navigatorAppearanceID = NavigatorCustomization.selectedID
    var onNavigatorSelected: () -> Void = {}
    /// 桟橋の正面の沖に浮かべる目的地の島。目的地が無い間は海のままにする。
    var destinationBearing: HomeIslandDestinationBearing?
    /// 目的地を決めている間は、この島から沖の目的地を見つめる構図に預ける。
    var destinationGazeActive = false
    var onBoatSelected: () -> Void = {}
    /// Other room members, already filtered for membership and staleness by
    /// the multiplayer service. The local ID is ignored if it is echoed back.
    var remotePlayers: [HomeIslandRemotePlayerState] = []
    var localPlayerID: String? = nil
    /// Emits a coalesced local transform while it changes. The networking layer
    /// remains responsible for write throttling and idle heartbeats.
    var onLocalPlayerStateChanged: (HomeIslandRemotePlayerState) -> Void = { _ in }

    /// カメラを一時的に構図へ預けている状態(船の見た目替え / 目的地の目線)。
    /// この間は歩行も追従カメラも止め、決めた画を保つ。
    var cameraShowcaseActive: Bool {
        boatCustomizationActive || destinationGazeActive
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(owner: self)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = HomeIslandInteractiveSceneView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        // Walking is renderer-driven and must remain responsive even when the
        // user asks to reduce non-essential motion. The arrival/camera effects
        // themselves are shortened or skipped below.
        view.rendersContinuously = true
        view.isPlaying = true
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.delegate = context.coordinator
        context.coordinator.install(in: view)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.update(owner: self)
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate, UIGestureRecognizerDelegate {
        private var owner: HomeIslandSceneView
        private weak var view: SCNView?
        private var placementParent = SCNNode()
        private var placementNodes: [UUID: SCNNode] = [:]
        private let remotePlayersParent = SCNNode()
        private var remotePlayerVisuals: [String: RemotePlayerVisual] = [:]
        private let remotePlayersLock = NSLock()
        private weak var camera: SCNNode?
        private weak var cameraTarget: SCNNode?
        private weak var seaMaterial: SCNMaterial?
        private var oceanReduceMotionEnabled = UIAccessibility.isReduceMotionEnabled
        private var frozenOceanTime = HomeIslandOceanEffects.currentTime
        private weak var foundationNode: SCNNode?
        private weak var destinationIslandNode: SCNNode?
        private var renderedDestinationBearing: HomeIslandDestinationBearing?
        private var renderedDestinationGaze = false
        private var renderedGazeDistance: Float?
        private var destinationGazeCameraSnapshot: BoatCustomizationCameraSnapshot?
        private weak var fixedNoticeBoardNode: SCNNode?
        private var fixedHarborSeatAssets: [FixedHarborSeatAsset] = []
        private var fixedHarborWalkingObstacles: [WalkingObstacle] = []
        private weak var navigatorNode: SCNNode?
        private weak var arrivalBoat: SCNNode?
        private weak var arrivalBoatBob: SCNNode?
        private weak var arrivalBoatModel: SCNNode?
        private weak var arrivalBoatNavigator: SCNNode?
        private weak var arrivalGangplank: SCNNode?
        private var selectedOutline: SCNNode?
        private let footprintParent = SCNNode()
        private var footprintNodes: [SCNNode] = []
        private var distanceSinceFootprint: Float = 0
        private var nextFootprintIsLeft = true
        private let navigatorAnimator = PhoenixAnimator()
        private var azimuth: Float = 0.72
        private var elevation: Float = 0.42
        private var radius: Float = 30.8
        private var initialAzimuth: Float = 0
        private var initialElevation: Float = 0
        private var initialRadius: Float = 0
        private var initialCameraTarget = SCNVector3Zero
        private var pinchAnchorWorldPoint: SCNVector3?
        private var moveDragPlacementID: UUID?
        private var moveDragLastGroundPoint: SCNVector3?
        private var moveDragPosition: SCNVector3?
        private var selectionMoveBlocked = false
        private var selectionMovePanActive = false
        private var selectionMoveTouchPlacementID: UUID?
        private var renderedResetToken = 0
        private var processedCameraRequestID: UUID?
        private var processedCaptureRequestID: UUID?
        private var processedBoatBoardingRequestID: UUID?
        private var lastFrameTime: TimeInterval?
        private var renderedMode: HomeIslandMode = .arrival
        private var renderedBoatCustomizationActive = false
        private var renderedBoatAppearanceID = ""
        private var renderedNavigatorAppearanceID = NavigatorCustomization.selectedID
        private var boatCustomizationCameraSnapshot: BoatCustomizationCameraSnapshot?
        private weak var orbitPanRecognizer: UIPanGestureRecognizer?
        /// UIKit supplies orbit intent while SceneKit owns the final Explore
        /// camera pose. The lock makes the handoff explicit across their threads.
        private let exploreOrbitLock = NSLock()
        private var pendingExploreOrbitAngles: (azimuth: Float, elevation: Float)?
        private weak var movementPanRecognizer: UIPanGestureRecognizer?
        private weak var runningJumpRecognizer: UILongPressGestureRecognizer?
        private weak var twoFingerPanRecognizer: UIPanGestureRecognizer?
        private weak var pinchRecognizer: UIPinchGestureRecognizer?
        private weak var longPressRecognizer: UILongPressGestureRecognizer?
        private weak var doubleTapRecognizer: UITapGestureRecognizer?
        private var touchWalkInput = HomeIslandWalkInput.zero
        private var keyboardWalkInput = HomeIslandWalkInput.zero
        /// In build mode the left thumb region drives the camera across the
        /// island — the touch equivalent of WASD, which pans the same target.
        /// The navigator does not walk while building, so the region is free.
        private var editCameraPanInput = HomeIslandWalkInput.zero
        private var gamepadWalkInput = HomeIslandWalkInput.zero
        private var externalWalkInput = HomeIslandWalkInput.zero
        /// One-shot phone jump input. Kept until the renderer consumes it so a
        /// short tap cannot disappear during a frame hitch or app-side update.
        /// Access is protected by `walkInputLock` together with cached input.
        private var pendingTouchJump = false
        private var movementFeedbackSent = false
        private var runningJumpBeganAt: TimeInterval?
        private var runningJumpBeganPoint: CGPoint?
        private var arrivalStarted = false
        private var arrivalFinished = false
        private var arrivalNavigatorIsWalking = false
        private var renderedNavigatorOnArrivalJetty: Bool?
        private var reportedNavigatorOnArrivalJetty: Bool?
        private var renderedNavigatorNearNoticeBoard: Bool?
        private var reportedNavigatorNearNoticeBoard: Bool?
        private var boardingRequested = false
        private var departureStarted = false
        private var arrivalBoatStopPosition = SCNVector3(0, -0.35, 20.2)
        private var arrivalJettyWalkSurface: JettyWalkSurface?
        private var cachedWalkInput = HomeIslandWalkInput.zero
        private let walkInputLock = NSLock()
        private let locomotionTuning: HomeIslandLocomotionTuning
        private let locomotionMotor: HomeIslandLocomotionMotor
        private let locomotionCameraController: HomeIslandLocomotionCameraController
        private let locomotionAudio = HomeIslandLocomotionAudio()
        private var locomotionFrame: HomeIslandLocomotionFrame?
        private var cameraMotion = HomeIslandCameraMotion()
        private var lastLocomotionDeltaTime: Float = 1 / 60
        private var lastWindIntensity: Float = 0
        private var walkingObstacles: [WalkingObstacle] = []
        private var ruinsWalkObstacles: [RuinsWalkObstacle] = []
        private var jettyWalkSurfaces: [JettyWalkSurface] = []
        private var lookoutWalkSurfaces: [LookoutWalkSurface] = []
        private var placedSeatSlots: [PlacedSeatSlot] = []
#if DEBUG
        private var seatDemoDidBegin = false
#endif
        private var seatInteractionState = SeatInteractionState.free
        private var navigatorRootToSeatSurface = PhoenixNavigator.seatedRig.rootToSurface
            * NavigatorAppearance.islandScale
        private var contactReentryBlockedUntil: TimeInterval = 0
        private var snapFacingOnNextMovement = false
        private var renderedLocalPlayerID: String?
        private var lastReportedLocalPlayerState: HomeIslandRemotePlayerState?
        private var lastLocalPlayerReportTime: TimeInterval = -.infinity

        private final class RemotePlayerVisual {
            let node: SCNNode
            let animator: PhoenixAnimator
            var targetPosition: SCNVector3
            var targetYaw: Float
            var targetPose: PhoenixPose
            var targetSeatAddress: HomeIslandSeatAddress?
            var animationTime: Float = 0
            var lastArrivalNonce: String?
            var isArrivalAnimating = false
            var arrivalPose = PhoenixPose.idle
            var arrivalBoat: SCNNode?
            var arrivalBoatNavigator: SCNNode?
            var arrivalGangplank: SCNNode?

            init(
                node: SCNNode,
                animator: PhoenixAnimator,
                targetPosition: SCNVector3,
                targetYaw: Float,
                targetPose: PhoenixPose,
                targetSeatAddress: HomeIslandSeatAddress?
            ) {
                self.node = node
                self.animator = animator
                self.targetPosition = targetPosition
                self.targetYaw = targetYaw
                self.targetPose = targetPose
                self.targetSeatAddress = targetSeatAddress
            }
        }

        private struct BoatCustomizationCameraSnapshot {
            let azimuth: Float
            let elevation: Float
            let radius: Float
            let target: SCNVector3
            let fieldOfView: CGFloat
        }

        private enum ArrivalMotion {
            static let boatY: Float = -0.12
            static let boatScale: Float = 0.92
            static let offshoreStartDistance: Float = 5
            static let berthLeadDistance: Float = 1.70
            static let openWaterDuration: TimeInterval = 1.80
            static let berthingDuration: TimeInterval = 1.25
            static let mooringSettleDuration: TimeInterval = 0.25
            static let transferDuration: TimeInterval = 0.72
            static let jettySettleDuration: TimeInterval = 0.55
        }

        private enum NavigatorAppearance {
            static let islandScale: Float = 0.78
        }

        private enum NavigatorCollision {
            static let radius: Float = 0.32
        }

        private enum DepartureMotion {
            static let boardingRadius: Float = 1.15
            static let approachSpeed: Float = 2.20
            static let approachDurationRange: ClosedRange<TimeInterval> = 0.18...0.55
            static let transferSpeed: Float = 1.90
            static let transferDurationRange: ClosedRange<TimeInterval> = 0.58...0.82
            static let gangplankRetractDuration: TimeInterval = 0.20
            static let voyageDuration: TimeInterval = 5.45
            static let voyageDistance: Float = 12.60
            static let outwardDrift: Float = 0.85
        }

        private struct WalkingObstacle {
            let x: Float
            let z: Float
            let radius: Float
        }

        /// 航海士の座位と、各アセットの座面をつなぐ共通寸法。
        /// 座面ソケットは「表面」を示し、キャラ側の接触高さはここで一度だけ引く。
        /// アセットを拡縮しても航海士自体の寸法は変わらない。
        private enum NavigatorSeatMetrics {
            static let surfaceClearance: Float = 0.008
            static let backrestClearance: Float = 0.145
            /// Council-table seats face away from their approach marker, so the
            /// navigator root belongs slightly inside the socket, toward the table.
            static let tableForwardInset: Float = 0.10
        }

        /// A lying navigator is rotated around the model root at its feet.
        /// Sleep sockets mark the centre of the authored bed surface, so the
        /// root is shifted back by half the visible body length and raised by
        /// half its width. These dimensions stay independent of asset scale.
        private enum NavigatorSleepMetrics {
            static let bodyCenterFromRoot: Float = 0.49
            static let surfaceClearance: Float = 0.145
            static let roll: Float = -.pi / 2
        }

        /// Runtime-resolved sockets for assets with more than one seat. The
        /// stable ID is suitable for a future multiplayer occupancy record.
        private struct PlacedSeatSlot {
            let placementID: UUID
            let slotID: String
            let motion: HomeIslandContactMotion
            let seatNode: SCNNode
            let approachNode: SCNNode
            let facesAwayFromApproach: Bool
            let seatPlanarOffset: Float?
            let approachClearance: Float?
            let obstacleCenter: SCNVector3
            let obstacleRadius: Float

            var address: HomeIslandSeatAddress {
                HomeIslandSeatAddress(placementID: placementID, slotID: slotID)
            }

            var contactFacingDirection: SCNVector3 {
                let surface = seatNode.presentation.worldPosition
                let approach = approachNode.presentation.worldPosition
                if motion == .lie {
                    let worldAxis = seatNode.presentation.convertVector(
                        SCNVector3(1, 0, 0),
                        to: nil
                    )
                    let length = sqrt(
                        worldAxis.x * worldAxis.x + worldAxis.z * worldAxis.z
                    )
                    if length > 0.001 {
                        return SCNVector3(
                            worldAxis.x / length,
                            0,
                            worldAxis.z / length
                        )
                    }
                }
                let outwardX = approach.x - surface.x
                let outwardZ = approach.z - surface.z
                let outwardLength = sqrt(outwardX * outwardX + outwardZ * outwardZ)
                guard outwardLength > 0.001 else { return SCNVector3(0, 0, 1) }
                let direction: Float = facesAwayFromApproach ? -1 : 1
                return SCNVector3(
                    outwardX / outwardLength * direction,
                    0,
                    outwardZ / outwardLength * direction
                )
            }

            func contactWorldPosition(rootToSeatSurface: Float) -> SCNVector3 {
                let surface = seatNode.presentation.worldPosition
                let facing = contactFacingDirection
                if motion == .lie {
                    return SCNVector3(
                        surface.x - facing.x * NavigatorSleepMetrics.bodyCenterFromRoot,
                        surface.y + NavigatorSleepMetrics.surfaceClearance,
                        surface.z - facing.z * NavigatorSleepMetrics.bodyCenterFromRoot
                    )
                }
                let approach = approachNode.presentation.worldPosition
                let outwardX = approach.x - surface.x
                let outwardZ = approach.z - surface.z
                let outwardLength = sqrt(outwardX * outwardX + outwardZ * outwardZ)
                let outwardOffset = seatPlanarOffset ?? (facesAwayFromApproach
                    ? -NavigatorSeatMetrics.tableForwardInset
                    : NavigatorSeatMetrics.backrestClearance)
                return SCNVector3(
                    surface.x + outwardX / max(outwardLength, 0.001)
                        * outwardOffset,
                    surface.y
                        - rootToSeatSurface
                        + NavigatorSeatMetrics.surfaceClearance,
                    surface.z + outwardZ / max(outwardLength, 0.001)
                        * outwardOffset
                )
            }

            var approachWorldPosition: SCNVector3 {
                let authored = approachNode.presentation.worldPosition
                guard let approachClearance else { return authored }

                let dx = authored.x - obstacleCenter.x
                let dz = authored.z - obstacleCenter.z
                let authoredRadius = sqrt(dx * dx + dz * dz)
                guard authoredRadius > 0.001 else { return authored }

                // Small seats use their authored approach socket as a facing
                // direction. Keep the actual standing point outside both the
                // prop and the navigator collision radii at every asset scale.
                let safeRadius = max(
                    authoredRadius,
                    obstacleRadius + NavigatorCollision.radius + approachClearance
                )
                return SCNVector3(
                    obstacleCenter.x + dx / authoredRadius * safeRadius,
                    authored.y,
                    obstacleCenter.z + dz / authoredRadius * safeRadius
                )
            }
        }

        private struct FixedHarborSeatAsset {
            let id: UUID
            let assetID: String
            let node: SCNNode
            let obstacleCenter: SCNVector3
            let obstacleRadius: Float
        }

        private struct InteractiveSeat {
            let address: HomeIslandSeatAddress
            let motion: HomeIslandContactMotion
            let seatPosition: SCNVector3
            let approachPosition: SCNVector3?
            let obstacleCenter: SCNVector3
            let obstacleRadius: Float
            let facingDirection: SCNVector3
        }

        private enum SeatInteractionState {
            case free
            case approaching(InteractiveSeat)
            case settling(InteractiveSeat)
            case seated(InteractiveSeat)
            case standingUp(InteractiveSeat)
            case leaving(InteractiveSeat)

            var seat: InteractiveSeat? {
                switch self {
                case .free:
                    nil
                case let .approaching(seat), let .settling(seat), let .seated(seat),
                     let .standingUp(seat), let .leaving(seat):
                    seat
                }
            }

            var keepsNavigatorOnSeat: Bool {
                switch self {
                case .free:
                    false
                default:
                    true
                }
            }
        }

        /// Keeps the ruined stonework solid while leaving the authored arch opening walkable.
        private struct RuinsWalkObstacle {
            let transform: HomeIslandTransform

            private func localPosition(x: Float, z: Float) -> (x: Float, z: Float) {
                let dx = x - transform.x
                let dz = z - transform.z
                let cosine = cos(transform.yaw)
                let sine = sin(transform.yaw)
                return (
                    dx * cosine - dz * sine,
                    dx * sine + dz * cosine
                )
            }

            func blocks(x: Float, z: Float, playerRadius: Float) -> Bool {
                let local = localPosition(x: x, z: z)
                let scale = max(transform.scale, 0.05)

                // The mesh spans roughly x ±1.85 and z -0.72...1.22 in model space.
                // A little player clearance keeps contact with the broken walls natural.
                let outerHalfWidth = 1.85 * scale + playerRadius * 0.18
                let outerNearEdge = -0.72 * scale - playerRadius * 0.12
                let outerFarEdge = 1.22 * scale + playerRadius * 0.12
                guard abs(local.x) <= outerHalfWidth,
                      local.z >= outerNearEdge,
                      local.z <= outerFarEdge
                else { return false }

                // The central opening follows the placement's rotation and scale.
                // Its gameplay clearance is kept large enough for the navigator at small scales.
                let passageHalfWidth = max(0.34, 0.52 * scale)
                return abs(local.x) > passageHalfWidth
            }
        }

        /// The cliff lookout is a raised deck reached by five timber steps.
        /// Its authored dimensions are mirrored here so walking, standing
        /// height and the rail line all agree with what the model shows.
        ///
        /// Blender authors the asset +Y forward; USDZ import turns that into
        /// SceneKit -Z, so the stairs — built along Blender -Y — climb toward
        /// local +Z here.
        private struct LookoutWalkSurface {
            let transform: HomeIslandTransform

            /// Deck planks: 2.16 wide, spanning local z -0.82 ... 0.78, topped
            /// at 1.0525 above the model's footing.
            private static let deckHalfWidth: Float = 1.08
            private static let deckFarZ: Float = -0.82
            private static let deckMouthZ: Float = 0.78
            private static let deckTopY: Float = 1.0525
            /// Five treads, 0.78 wide, stepping down away from the deck.
            private static let stairHalfWidth: Float = 0.39
            private static let stairFirstZ: Float = 1.00
            private static let stairDepth: Float = 0.34
            private static let stairSpacing: Float = 0.27
            private static let stairTopY: Float = 0.94
            private static let stairRise: Float = 0.17
            private static let stairCount = 5

            private func localPosition(x: Float, z: Float) -> (x: Float, z: Float) {
                let dx = x - transform.x
                let dz = z - transform.z
                let cosine = cos(transform.yaw)
                let sine = sin(transform.yaw)
                return (
                    dx * cosine - dz * sine,
                    dx * sine + dz * cosine
                )
            }

            private var scale: Float { max(transform.scale, 0.05) }

            /// Local z of the last tread's outer edge, where sand meets timber.
            private var stairOuterZ: Float {
                Self.stairFirstZ
                    + Self.stairSpacing * Float(Self.stairCount - 1)
                    + Self.stairDepth * 0.5
            }

            private func isOnDeck(local: (x: Float, z: Float), inset: Float) -> Bool {
                abs(local.x) <= Self.deckHalfWidth * scale - inset
                    && local.z >= Self.deckFarZ * scale + inset
                    && local.z <= Self.deckMouthZ * scale
            }

            private func isOnStairs(local: (x: Float, z: Float), widthPadding: Float) -> Bool {
                abs(local.x) <= Self.stairHalfWidth * scale + widthPadding
                    && local.z >= Self.deckMouthZ * scale
                    && local.z <= stairOuterZ * scale
            }

            /// Where the navigator's capsule centre may stand. The deck is
            /// inset by half a body so the model never hangs over the edge;
            /// the stairs are widened slightly so a diagonal approach still
            /// finds them.
            func contains(x: Float, z: Float, playerRadius: Float) -> Bool {
                let local = localPosition(x: x, z: z)
                return isOnDeck(local: local, inset: playerRadius * 0.55)
                    || isOnStairs(local: local, widthPadding: playerRadius * 0.35)
            }

            /// Foot probes use the authored footprint without the body inset,
            /// so a position accepted above always samples timber.
            func containsGroundSurface(x: Float, z: Float, playerRadius: Float) -> Bool {
                let local = localPosition(x: x, z: z)
                return isOnDeck(local: local, inset: 0)
                    || isOnStairs(local: local, widthPadding: playerRadius * 0.5)
            }

            func height(
                x: Float,
                z: Float,
                playerRadius: Float,
                baseHeight: Float
            ) -> Float {
                let local = localPosition(x: x, z: z)
                let deckTop = HomeIslandMetrics.surfaceY + Self.deckTopY * scale
                guard local.z > Self.deckMouthZ * scale else { return deckTop }
                // Steps, not a ramp: report the tread the foot is actually on
                // so the walk motor climbs one riser at a time.
                let travelled = (local.z / scale - Self.stairFirstZ + Self.stairDepth * 0.5)
                let index = Int(floor(travelled / Self.stairSpacing))
                let clamped = min(max(index, 0), Self.stairCount - 1)
                let treadTop = Self.stairTopY - Self.stairRise * Float(clamped)
                return max(
                    baseHeight,
                    HomeIslandMetrics.surfaceY + treadTop * scale
                )
            }

            /// The rope rail, the two posts flanking the stairs, and the open
            /// drop beneath the deck. Everything but the stair mouth is solid,
            /// which is what makes the steps the only way up.
            func blocksRail(x: Float, z: Float, playerRadius: Float) -> Bool {
                let local = localPosition(x: x, z: z)
                let clearance = playerRadius * 0.92
                let halfWidth = Self.deckHalfWidth * scale
                let farZ = Self.deckFarZ * scale
                let mouthZ = Self.deckMouthZ * scale
                guard local.x >= -halfWidth - clearance,
                      local.x <= halfWidth + clearance,
                      local.z >= farZ - clearance,
                      local.z <= mouthZ + clearance
                else { return false }
                // Comfortably inside the deck: standing on it, not crossing it.
                if abs(local.x) <= halfWidth - clearance,
                   local.z >= farZ + clearance,
                   local.z <= mouthZ {
                    return false
                }
                // The stair mouth stays open across the tread's full width.
                let mouthHalfWidth = Self.stairHalfWidth * scale + playerRadius * 0.35
                if abs(local.x) <= mouthHalfWidth, local.z >= mouthZ - clearance {
                    return false
                }
                return true
            }
        }

        private struct JettyWalkSurface {
            let transform: HomeIslandTransform

            private func localPosition(x: Float, z: Float) -> (x: Float, z: Float) {
                let dx = x - transform.x
                let dz = z - transform.z
                let cosine = cos(transform.yaw)
                let sine = sin(transform.yaw)
                return (
                    dx * cosine - dz * sine,
                    dx * sine + dz * cosine
                )
            }

            func contains(x: Float, z: Float, playerRadius: Float) -> Bool {
                let local = localPosition(x: x, z: z)
                let scale = max(transform.scale, 0.05)
                let halfWidth = max(0.16, 0.68 * scale - playerRadius * 0.62)
                let seawardEnd = HomeIslandMetrics.jettyDeckSeawardEndLocalZ * scale
                    + playerRadius * 0.42
                // Slightly overlap the sand so the player can step onto the ramp.
                let landwardEnd = HomeIslandMetrics.jettyDeckLandwardEndLocalZ * scale
                let isOnMainDeck = abs(local.x) <= halfWidth
                    && local.z >= seawardEnd
                    && local.z <= landwardEnd
                let floatCenterX = HomeIslandMetrics.boardingFloatCenterLocalX * scale
                let floatCenterZ = HomeIslandMetrics.boardingFloatCenterLocalZ * scale
                let floatHalfWidth = max(
                    0.16,
                    HomeIslandMetrics.boardingFloatHalfWidth * scale - playerRadius * 0.32
                )
                let floatHalfLength = max(
                    0.22,
                    HomeIslandMetrics.boardingFloatHalfLength * scale - playerRadius * 0.22
                )
                let isOnBoardingFloat = abs(local.x - floatCenterX) <= floatHalfWidth
                    && abs(local.z - floatCenterZ) <= floatHalfLength
                // Overlap both authored walkable regions. The former values
                // left tiny non-walkable seams at the first and last stair,
                // which made descending feel blocked.
                let connectorOverlap = playerRadius * 0.12
                let connectorNearX = HomeIslandMetrics.boardingConnectorNearLocalX * scale
                    - connectorOverlap
                let connectorFarX = HomeIslandMetrics.boardingConnectorFarLocalX * scale
                    + connectorOverlap
                let connectorHalfLength = HomeIslandMetrics.boardingConnectorHalfLength * scale
                    + connectorOverlap
                let isOnConnector = local.x >= connectorNearX
                    && local.x <= connectorFarX
                    && abs(local.z - floatCenterZ) <= connectorHalfLength
                return isOnMainDeck || isOnBoardingFloat || isOnConnector
            }

            /// Physical surface lookup is deliberately wider than the capsule
            /// centre corridor so foot probes still see timber near an edge.
            /// Its connector padding, however, must exactly cover the expanded
            /// gameplay route or an accepted position can sample the sea below.
            func containsGroundSurface(x: Float, z: Float, playerRadius: Float) -> Bool {
                let local = localPosition(x: x, z: z)
                let scale = max(transform.scale, 0.05)
                let isOnMainDeck = abs(local.x) <= 0.68 * scale
                    && local.z >= HomeIslandMetrics.jettyDeckSeawardEndLocalZ * scale
                    && local.z <= HomeIslandMetrics.jettyDeckLandwardEndLocalZ * scale
                let floatCenterX = HomeIslandMetrics.boardingFloatCenterLocalX * scale
                let floatCenterZ = HomeIslandMetrics.boardingFloatCenterLocalZ * scale
                let isOnBoardingFloat = abs(local.x - floatCenterX)
                        <= HomeIslandMetrics.boardingFloatHalfWidth * scale
                    && abs(local.z - floatCenterZ)
                        <= HomeIslandMetrics.boardingFloatHalfLength * scale
                let connectorOverlap = playerRadius * 0.12
                let isOnConnector = local.x
                        >= HomeIslandMetrics.boardingConnectorNearLocalX * scale
                            - connectorOverlap
                    && local.x
                        <= HomeIslandMetrics.boardingConnectorFarLocalX * scale
                            + connectorOverlap
                    && abs(local.z - floatCenterZ)
                        <= HomeIslandMetrics.boardingConnectorHalfLength * scale
                            + connectorOverlap
                return isOnMainDeck || isOnBoardingFloat || isOnConnector
            }

            /// Blocks the authored toe board and rope line even where the long
            /// jetty overlaps walkable shore sand. The reduced body allowance
            /// matches the stylized navigator capsule while leaving a generous
            /// central lane on the deliberately narrow handcrafted deck.
            func blocksRail(x: Float, z: Float, playerRadius: Float) -> Bool {
                let local = localPosition(x: x, z: z)
                let scale = max(transform.scale, 0.05)
                let seawardEnd = HomeIslandMetrics.jettyRailSeawardEndLocalZ * scale
                let landwardEnd = HomeIslandMetrics.jettyRailLandwardEndLocalZ * scale
                guard local.z >= seawardEnd, local.z <= landwardEnd else { return false }
                // Derive the rope opening from the same connector footprint
                // used by walkability. The older z-only gate left a thin
                // collision strip at either end of the sloped connector,
                // allowing the capsule to become trapped between the ropes.
                let gatePadding = playerRadius * 0.18
                let connectorNearX = HomeIslandMetrics.boardingConnectorNearLocalX * scale
                    - gatePadding
                let connectorFarX = HomeIslandMetrics.boardingConnectorFarLocalX * scale
                    + gatePadding
                let connectorCenterZ = HomeIslandMetrics.boardingFloatCenterLocalZ * scale
                let connectorHalfLength = HomeIslandMetrics.boardingConnectorHalfLength * scale
                    + gatePadding
                let isBoardingGate = local.x >= connectorNearX
                    && local.x <= connectorFarX
                    && abs(local.z - connectorCenterZ) <= connectorHalfLength
                if isBoardingGate { return false }
                let railCenter = HomeIslandMetrics.jettyRailCenterLocalX * scale
                let railClearance = 0.055 * scale + playerRadius * 0.24
                return abs(abs(local.x) - railCenter) <= railClearance
            }

            func worldPosition(localX: Float, localZ: Float) -> (x: Float, z: Float) {
                let scale = max(transform.scale, 0.05)
                let scaledX = localX * scale
                let scaledZ = localZ * scale
                let cosine = cos(transform.yaw)
                let sine = sin(transform.yaw)
                return (
                    transform.x + scaledX * cosine + scaledZ * sine,
                    transform.z - scaledX * sine + scaledZ * cosine
                )
            }

            func height(
                x: Float,
                z: Float,
                playerRadius: Float,
                baseHeight: Float
            ) -> Float {
                let local = localPosition(x: x, z: z)
                let localZ = local.z
                let scale = max(transform.scale, 0.05)
                let flatDeck = HomeIslandMetrics.surfaceY + 0.445 * scale
                let floatCenterX = HomeIslandMetrics.boardingFloatCenterLocalX * scale
                let floatCenterZ = HomeIslandMetrics.boardingFloatCenterLocalZ * scale
                let lowDeck = HomeIslandMetrics.surfaceY - 0.215 * scale
                // Ground sampling must cover every point accepted by
                // `contains`. Previously its narrower connector rectangle
                // exposed strips that were walkable but sampled the water or
                // island beneath the stairs.
                let connectorOverlap = playerRadius * 0.12
                let connectorNearX = HomeIslandMetrics.boardingConnectorNearLocalX * scale
                    - connectorOverlap
                let connectorFarX = HomeIslandMetrics.boardingConnectorFarLocalX * scale
                    + connectorOverlap
                let connectorHalfLength = HomeIslandMetrics.boardingConnectorHalfLength * scale
                    + connectorOverlap
                if local.x >= connectorNearX,
                   local.x <= connectorFarX,
                   abs(local.z - floatCenterZ) <= connectorHalfLength {
                    // The harbor asset is four overlapping timber steps, not
                    // a ramp. Match the authored top faces so feet do not sink
                    // through the boards and the motor can step one riser at a
                    // time in either direction. The first/top tread differs
                    // from the main deck by only 0.02 model units, so treating
                    // it as deck height avoids a needless micro-step.
                    let authoredTop = HomeIslandBoardingStairProfile.authoredTop(
                        at: local.x / scale
                    )
                    return HomeIslandMetrics.surfaceY + authoredTop * scale
                }
                let isOnFloat = abs(local.x - floatCenterX)
                        <= HomeIslandMetrics.boardingFloatHalfWidth * scale
                    && abs(local.z - floatCenterZ)
                        <= HomeIslandMetrics.boardingFloatHalfLength * scale
                if isOnFloat { return lowDeck }
                let rampStart = 1.70 * scale
                let shoreEnd = 2.30 * scale
                guard localZ > rampStart else { return max(baseHeight, flatDeck) }
                let progress = min(max((localZ - rampStart) / max(shoreEnd - rampStart, 0.001), 0), 1)
                let shoreHeight = max(baseHeight, HomeIslandMetrics.surfaceY + 0.055 * scale)
                return flatDeck + (shoreHeight - flatDeck) * progress
            }

            func normal(
                x: Float,
                z: Float,
                playerRadius: Float,
                baseHeight: (Float, Float) -> Float
            ) -> SIMD3<Float> {
                let local = localPosition(x: x, z: z)
                let scale = max(transform.scale, 0.05)
                let connectorOverlap = playerRadius * 0.12
                let connectorNearX = HomeIslandMetrics.boardingConnectorNearLocalX * scale
                    - connectorOverlap
                let connectorFarX = HomeIslandMetrics.boardingConnectorFarLocalX * scale
                    + connectorOverlap
                let connectorCenterZ = HomeIslandMetrics.boardingFloatCenterLocalZ * scale
                let connectorHalfLength = HomeIslandMetrics.boardingConnectorHalfLength * scale
                    + connectorOverlap
                let isOnBoardingFloat = abs(
                    local.x - HomeIslandMetrics.boardingFloatCenterLocalX * scale
                ) <= HomeIslandMetrics.boardingFloatHalfWidth * scale
                    && abs(local.z - connectorCenterZ)
                        <= HomeIslandMetrics.boardingFloatHalfLength * scale
                if local.x >= connectorNearX,
                   local.x <= connectorFarX,
                   abs(local.z - connectorCenterZ) <= connectorHalfLength
                    || isOnBoardingFloat {
                    // Each tread is level. Returning the old interpolated ramp
                    // normal tilted the entire navigator sideways by up to the
                    // body-angle clamp and disabled the motor's step smoothing.
                    return SIMD3<Float>(0, 1, 0)
                }
                if abs(local.x) <= 0.68 * scale,
                   local.z <= 1.70 * scale {
                    return SIMD3<Float>(0, 1, 0)
                }
                let epsilon: Float = 0.08
                let left = height(
                    x: x - epsilon,
                    z: z,
                    playerRadius: playerRadius,
                    baseHeight: baseHeight(x - epsilon, z)
                )
                let right = height(
                    x: x + epsilon,
                    z: z,
                    playerRadius: playerRadius,
                    baseHeight: baseHeight(x + epsilon, z)
                )
                let near = height(
                    x: x,
                    z: z - epsilon,
                    playerRadius: playerRadius,
                    baseHeight: baseHeight(x, z - epsilon)
                )
                let far = height(
                    x: x,
                    z: z + epsilon,
                    playerRadius: playerRadius,
                    baseHeight: baseHeight(x, z + epsilon)
                )
                return simd_normalize(SIMD3<Float>(
                    left - right,
                    epsilon * 2,
                    near - far
                ))
            }
        }

        init(owner: HomeIslandSceneView) {
            self.owner = owner
            let tuning = HomeIslandLocomotionTuning.standard
            locomotionTuning = tuning
            locomotionMotor = HomeIslandLocomotionMotor(tuning: tuning)
            locomotionCameraController = HomeIslandLocomotionCameraController(tuning: tuning)
        }

        func install(in view: SCNView) {
            self.view = view
            let scene = makeScene()
            view.scene = scene
            view.pointOfView = camera
            if let interactiveView = view as? HomeIslandInteractiveSceneView {
                interactiveView.keyboardMovementHandler = { [weak self] input, deltaTime in
                    self?.handleKeyboardMovement(input, deltaTime: Float(deltaTime))
                }
                interactiveView.gamepadMovementHandler = { [weak self] input, deltaTime in
                    self?.handleGamepadMovement(input, deltaTime: Float(deltaTime))
                }
                interactiveView.gamepadLookHandler = { [weak self] x, y, deltaTime in
                    self?.handleGamepadLook(x: x, y: y, deltaTime: Float(deltaTime))
                }
            }

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.delegate = self
            view.addGestureRecognizer(tap)

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 1
            pan.allowedScrollTypesMask = [.continuous, .discrete]
            pan.delegate = self
            view.addGestureRecognizer(pan)
            orbitPanRecognizer = pan

            // The lower-left part of the scene is a broad, invisible dynamic
            // thumbstick. A separate recognizer lets the other thumb orbit the
            // camera at the same time without placing permanent UI over the island.
            let movementPan = UIPanGestureRecognizer(
                target: self,
                action: #selector(handleMovementPan(_:))
            )
            movementPan.minimumNumberOfTouches = 1
            movementPan.maximumNumberOfTouches = 1
            movementPan.delegate = self
            view.addGestureRecognizer(movementPan)
            movementPanRecognizer = movementPan

            // A second thumb can jump while the first thumb continues to
            // steer. Zero-duration long press gives us an independent touch
            // stream; moving it becomes camera orbit, while a short stationary
            // touch is consumed as a jump without adding a visible button.
            let runningJump = UILongPressGestureRecognizer(
                target: self,
                action: #selector(handleRunningJumpPress(_:))
            )
            runningJump.minimumPressDuration = 0
            runningJump.allowableMovement = 14
            runningJump.cancelsTouchesInView = false
            runningJump.delegate = self
            view.addGestureRecognizer(runningJump)
            runningJumpRecognizer = runningJump

            let twoFingerPan = UIPanGestureRecognizer(
                target: self,
                action: #selector(handleTwoFingerPan(_:))
            )
            twoFingerPan.minimumNumberOfTouches = 2
            twoFingerPan.maximumNumberOfTouches = 2
            twoFingerPan.delegate = self
            view.addGestureRecognizer(twoFingerPan)
            twoFingerPanRecognizer = twoFingerPan

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            view.addGestureRecognizer(pinch)
            pinchRecognizer = pinch

            let longPress = UILongPressGestureRecognizer(
                target: self,
                action: #selector(handleLongPress(_:))
            )
            longPress.minimumPressDuration = 0.42
            longPress.allowableMovement = 12
            longPress.delegate = self
            view.addGestureRecognizer(longPress)
            longPressRecognizer = longPress

            let reset = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            reset.numberOfTapsRequired = 2
            reset.delegate = self
            tap.require(toFail: reset)
            view.addGestureRecognizer(reset)
            doubleTapRecognizer = reset

            syncPlacements()
            syncRemotePlayers()
            if owner.startsMooredAtIsland {
                prepareMooredHome()
#if DEBUG
                scheduleSeatDemoIfRequested()
#endif
            } else {
                updateCamera()
                startArrivalIfNeeded()
            }
        }

        func update(owner: HomeIslandSceneView) {
            self.owner = owner
            cancelSelectionMovePreviewIfNeeded()
            if renderedLocalPlayerID != owner.localPlayerID {
                renderedLocalPlayerID = owner.localPlayerID
                lastReportedLocalPlayerState = nil
                lastLocalPlayerReportTime = -.infinity
            }
            externalWalkInput = owner.walkInput
            if owner.cameraInteractionLocked {
                touchWalkInput = .zero
                keyboardWalkInput = .zero
                gamepadWalkInput = .zero
                clearPendingTouchJump()
                storeCachedWalkInput(.zero)
            } else {
                refreshWalkInput()
            }
            updateExposure()
            syncPlacements()
            syncRemotePlayers()
            syncBoatAppearanceIfNeeded()
            syncNavigatorAppearanceIfNeeded()
            syncDestinationIslandIfNeeded()
            syncDestinationGazeCameraIfNeeded()
            if renderedMode != owner.mode {
                let previousMode = renderedMode
                renderedMode = owner.mode
                modeDidChange(from: previousMode, to: owner.mode)
            }
            syncBoatCustomizationCameraIfNeeded()
            if renderedResetToken != owner.cameraResetToken {
                renderedResetToken = owner.cameraResetToken
                resetCamera(animated: true)
            }
            processCameraRequestIfNeeded()
            processCaptureRequestIfNeeded()
            processBoatBoardingRequestIfNeeded()
        }

        private func updateExposure() {
            // 写真モードは構図を決める場所であって、暗くする場所ではない。
            // スライダは歩いているときの明るさからの増減として扱い、
            // 入った瞬間は同じ明るさのままにする(±0 EV)。
            let target = CGFloat(
                owner.mode == .camera
                    ? HomeIslandSceneView.baseExposureOffset + owner.cameraExposureOffset
                    : HomeIslandSceneView.baseExposureOffset
            )
            guard let sceneCamera = camera?.camera,
                  abs(sceneCamera.exposureOffset - target) > 0.001
            else { return }
            sceneCamera.exposureOffset = target
        }

        /// 目的地の島を、桟橋の正面の沖へ出す/しまう/近づける。
        /// 島そのものは航海中・着岸と同じ `VoyageSceneKit.makeIsland` を使い、
        /// どの画面から見ても同じ目的地が見えるようにする。
        private func syncDestinationIslandIfNeeded() {
            guard renderedDestinationBearing != owner.destinationBearing else { return }
            let previous = renderedDestinationBearing
            renderedDestinationBearing = owner.destinationBearing

            guard let bearing = owner.destinationBearing else {
                destinationIslandNode?.removeFromParentNode()
                destinationIslandNode = nil
                view?.setNeedsDisplay()
                return
            }

            let node: SCNNode
            if let existing = destinationIslandNode {
                node = existing
            } else {
                guard let scene = view?.scene else {
                    // シーンがまだ無い最初の更新では作れない。次の更新でやり直す。
                    renderedDestinationBearing = previous
                    return
                }
                node = makeDestinationIslandNode()
                scene.rootNode.addChildNode(node)
                destinationIslandNode = node
            }

            let distance = HomeIslandMetrics.destinationIslandDistance(
                progressRatio: bearing.progressRatio
            )
            let position = SCNVector3(
                HomeIslandMetrics.destinationIslandBearingX,
                HomeIslandMetrics.destinationIslandWaterlineY,
                distance
            )
            // 目的地を決めた直後や再表示のときは、その場に現れてよい。進捗で近づく
            // ときだけ、視界の中で動いたことが分かる速さで寄せる。
            let animates = previous != nil
                && previous?.progressRatio != bearing.progressRatio
                && !UIAccessibility.isReduceMotionEnabled
            SCNTransaction.begin()
            SCNTransaction.animationDuration = animates ? 1.6 : 0
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            node.position = position
            SCNTransaction.commit()
            view?.setNeedsDisplay()
        }

        private func makeDestinationIslandNode() -> SCNNode {
            let anchor = SCNNode()
            anchor.name = "home-island-destination-island"
            anchor.eulerAngles.y = HomeIslandMetrics.destinationIslandYaw

            let scale = HomeIslandMetrics.destinationIslandScale
            let island = VoyageSceneKit.makeIsland(
                position: SCNVector3Zero,
                scale: SCNVector3(scale, scale, scale),
                // 遠景では読めない上に、島の影の範囲だけが広がる。
                includesCustomAssets: false
            )
            anchor.addChildNode(island)

            // 遠くの島までシャドウマップに含めると、足元の砂浜と小物の影が
            // 一気に粗くなる。目的地は影を落とさず、光だけを受ける。
            anchor.castsShadow = false
            anchor.enumerateChildNodes { child, _ in
                child.castsShadow = false
            }
            return anchor
        }

        /// 自分の航海士と、甲板に立つ自分の航海士だけを塗り替える。
        /// 遠くの相手は自分の装いを着ていないので触らない。
        private func syncNavigatorAppearanceIfNeeded() {
            guard renderedNavigatorAppearanceID != owner.navigatorAppearanceID else { return }
            renderedNavigatorAppearanceID = owner.navigatorAppearanceID

            let palette = (NavigatorCustomization.colors.first {
                $0.id == owner.navigatorAppearanceID
            } ?? NavigatorCustomization.colors[0]).palette
            let duration = UIAccessibility.isReduceMotionEnabled ? 0 : 0.18
            SCNTransaction.begin()
            SCNTransaction.animationDuration = duration
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
            for node in [navigatorNode, arrivalBoatNavigator].compactMap({ $0 }) {
                PhoenixNavigator.applyPalette(palette, to: node)
            }
            SCNTransaction.commit()
            view?.setNeedsDisplay()
        }

        private func syncBoatAppearanceIfNeeded() {
            guard renderedBoatAppearanceID != owner.boatAppearanceID,
                  let boat = arrivalBoatModel
            else { return }
            renderedBoatAppearanceID = owner.boatAppearanceID

            let option = BoatCustomization.sailColors.first {
                $0.id == owner.boatAppearanceID
            } ?? BoatCustomization.selectedSail
            let duration = UIAccessibility.isReduceMotionEnabled ? 0 : 0.18
            SCNTransaction.begin()
            SCNTransaction.animationDuration = duration
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
            boat.enumerateChildNodes { node, _ in
                guard let geometry = node.geometry else { return }
                for material in geometry.materials {
                    let isMainSail = material.name == "LF_BoatMainSail"
                        || node.name == "boatSailMain"
                    let isJib = material.name == "LF_BoatJib"
                        || node.name == "boatSailJib"
                    if isMainSail || isJib {
                        material.diffuse.contents = option.uiColor
                    }
                }
            }
            SCNTransaction.commit()
            view?.setNeedsDisplay()
        }

        private func syncBoatCustomizationCameraIfNeeded() {
            guard renderedBoatCustomizationActive != owner.boatCustomizationActive else {
                return
            }
            renderedBoatCustomizationActive = owner.boatCustomizationActive

            if owner.boatCustomizationActive {
                guard owner.mode == .explore,
                      let target = cameraTarget,
                      let sceneCamera = camera?.camera,
                      arrivalBoatModel != nil
                else { return }
                boatCustomizationCameraSnapshot = BoatCustomizationCameraSnapshot(
                    azimuth: azimuth,
                    elevation: elevation,
                    radius: radius,
                    target: target.position,
                    fieldOfView: sceneCamera.fieldOfView
                )

                // Match the familiar moored-home composition: the boat sits
                // large in the lower-right at a three-quarter angle, the pier
                // stays visible to the left, and open water fills the horizon.
                // Keeping this as a fixed berth view makes sail-color changes
                // easy to compare even if the player moved the explore camera.
                azimuth = nearestEquivalentAzimuth(to: 0.82)
                elevation = 0.30
                radius = 6.8
                let berthFocus = arrivalJettyLandingPath().landing
                let focusTarget = SCNVector3(
                    berthFocus.x,
                    berthFocus.y + 0.72,
                    berthFocus.z
                )
                animateBoatCustomizationCamera(
                    targetPosition: focusTarget,
                    fieldOfView: 48,
                    duration: 0.46
                )
                return
            }

            guard let snapshot = boatCustomizationCameraSnapshot,
                  cameraTarget != nil
            else { return }
            boatCustomizationCameraSnapshot = nil
            azimuth = snapshot.azimuth
            elevation = snapshot.elevation
            radius = snapshot.radius
            animateBoatCustomizationCamera(
                targetPosition: snapshot.target,
                fieldOfView: snapshot.fieldOfView,
                duration: 0.40
            )
        }

        /// 目的地を決めている間だけ、この島から沖の目的地を見つめる構図に移る。
        /// カメラは砂浜の高さから桟橋ごしに +Z を向き、島が近づくほど画角も広がる。
        private func syncDestinationGazeCameraIfNeeded() {
            let active = owner.destinationGazeActive && owner.mode == .explore
            let distance = owner.destinationBearing.map {
                HomeIslandMetrics.destinationIslandDistance(progressRatio: $0.progressRatio)
            }
            guard renderedDestinationGaze != active
                || (active && renderedGazeDistance != distance)
            else { return }
            let wasActive = renderedDestinationGaze
            renderedDestinationGaze = active
            renderedGazeDistance = distance

            if active {
                guard let target = cameraTarget,
                      let sceneCamera = camera?.camera
                else {
                    renderedDestinationGaze = wasActive
                    return
                }
                if destinationGazeCameraSnapshot == nil {
                    destinationGazeCameraSnapshot = BoatCustomizationCameraSnapshot(
                        azimuth: azimuth,
                        elevation: elevation,
                        radius: radius,
                        target: target.position,
                        fieldOfView: sceneCamera.fieldOfView
                    )
                }
                // 目的地がまだ無いときも、決めれば島が現れる沖を見せておく。
                let islandDistance = distance ?? HomeIslandMetrics.destinationIslandFarDistance
                // 桟橋の正面(-Z 側)から島の中心を見る。半径は島までの距離なので、
                // カメラは自然と自分の島の岸に立つ。
                azimuth = nearestEquivalentAzimuth(to: -.pi / 2)
                elevation = DestinationGaze.elevation
                radius = max(4, islandDistance - DestinationGaze.standoff)
                animateBoatCustomizationCamera(
                    targetPosition: SCNVector3(
                        HomeIslandMetrics.destinationIslandBearingX,
                        // 狙う高さは島の喫水ではなく海面から測る。島を沈めても
                        // カメラの目の高さが一緒に下がって桟橋に埋もれない。
                        HomeIslandMetrics.seaSurfaceY + DestinationGaze.aimHeight,
                        islandDistance
                    ),
                    fieldOfView: DestinationGaze.fieldOfView(distance: islandDistance),
                    duration: wasActive ? 0.9 : 0.72
                )
                return
            }

            guard let snapshot = destinationGazeCameraSnapshot,
                  cameraTarget != nil
            else { return }
            destinationGazeCameraSnapshot = nil
            azimuth = snapshot.azimuth
            elevation = snapshot.elevation
            radius = snapshot.radius
            animateBoatCustomizationCamera(
                targetPosition: snapshot.target,
                fieldOfView: snapshot.fieldOfView,
                duration: 0.44
            )
        }

        /// 目的地を見つめる構図の数値。Web / Android へ写せるよう一箇所に置く。
        private enum DestinationGaze {
            /// 岸に立った目の高さ。水平線とほぼ同じ高さから島を見る。
            static let elevation: Float = 0.03
            /// 島の中心より手前で止める距離。カメラが自分の島の岸に来る。
            static let standoff: Float = 6
            /// 島の中腹を狙う高さ(海面から)。
            static let aimHeight: Float = 3.2
            /// 遠いほど狭く覗き、近づくほど普段の画角へ戻る。
            static func fieldOfView(distance: Float) -> CGFloat {
                let islandRadius: Float = 3.4 * HomeIslandMetrics.destinationIslandScale
                let spread = 2 * atan(islandRadius / max(1, distance)) * 180 / .pi
                // 島が横幅のおよそ4割を占める見え方に揃える。
                return CGFloat(min(48, max(20, spread / 0.42)))
            }
        }

        private func animateBoatCustomizationCamera(
            targetPosition: SCNVector3,
            fieldOfView: CGFloat,
            duration: TimeInterval
        ) {
            let effectiveDuration = UIAccessibility.isReduceMotionEnabled ? 0 : duration
            SCNTransaction.begin()
            SCNTransaction.animationDuration = effectiveDuration
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cameraTarget?.position = targetPosition
            camera?.camera?.fieldOfView = fieldOfView
            updateCamera()
            SCNTransaction.commit()
            view?.setNeedsDisplay()
        }

        private func makeScene() -> SCNScene {
            let scene = SCNScene()
            scene.background.contents = UIColor.clear
            scene.fogColor = UIColor(rgb: 0xC9F3EA)
            scene.fogStartDistance = 52
            scene.fogEndDistance = 118
            scene.lightingEnvironment.contents = UIColor(rgb: 0xD9FFF5)
            scene.lightingEnvironment.intensity = 0.96

            let ocean = HomeIslandOceanEffects.makeScene()
            scene.rootNode.addChildNode(ocean.root)
            seaMaterial = ocean.animatedMaterial

            if let foundation = AssetPlacementRuntime.makeAssetNode(
                resourceName: HomeIslandMetrics.foundationResourceName
            ) {
                foundation.name = "home-island-locked-foundation"
                HomeIslandSandSurface.apply(to: foundation)
                scene.rootNode.addChildNode(foundation)
                foundationNode = foundation
            }

            if let jetty = AssetPlacementRuntime.makeAssetNode(resourceName: "wooden_jetty") {
                jetty.name = "home-island-locked-arrival-jetty"
                let coast = HomeIslandMetrics.arrivalJettyPosition
                let transform = HomeIslandTransform(
                    x: coast.x,
                    z: coast.z,
                    yaw: HomeIslandMetrics.arrivalJettyYaw,
                    scale: HomeIslandMetrics.arrivalJettyScale
                )
                installJettyCollision(on: jetty)
                transform.apply(to: jetty)
                scene.rootNode.addChildNode(jetty)
                arrivalJettyWalkSurface = JettyWalkSurface(transform: transform)
            }

            installHarborCommons(in: scene)

            if let noticeBoard = AssetPlacementRuntime.makeAssetNode(
                resourceName: "voyage_notice_board"
            ) {
                noticeBoard.name = "home-island-locked-notice-board"
                let position = HomeIslandMetrics.fixedNoticeBoardPosition
                HomeIslandTransform(
                    x: position.x,
                    z: position.z,
                    yaw: HomeIslandMetrics.fixedNoticeBoardYaw,
                    scale: HomeIslandMetrics.fixedNoticeBoardScale
                ).apply(to: noticeBoard)
                installNoticeBoardHitTarget(on: noticeBoard)
                scene.rootNode.addChildNode(noticeBoard)
                fixedNoticeBoardNode = noticeBoard
            }

            HomeIslandFootprintVisual.prewarm()
            footprintParent.name = "home-island-footprint-trail"
            scene.rootNode.addChildNode(footprintParent)

            placementParent.name = "home-island-player-placements"
            scene.rootNode.addChildNode(placementParent)

            remotePlayersParent.name = "home-island-remote-players"
            scene.rootNode.addChildNode(remotePlayersParent)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.color = UIColor(rgb: 0xF5F0DF)
            ambient.light?.intensity = 900
            scene.rootNode.addChildNode(ambient)

            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .directional
            key.light?.color = UIColor(rgb: 0xFFE8BE)
            key.light?.intensity = 1_550
            key.light?.castsShadow = true
            key.light?.categoryBitMask = 1
            key.light?.shadowMode = .deferred
            key.light?.shadowRadius = 4
            key.light?.shadowColor = UIColor.black.withAlphaComponent(0.26)
            key.light?.shadowMapSize = CGSize(width: 2_048, height: 2_048)
            key.position = SCNVector3(-7, 12, 8)
            key.look(at: SCNVector3Zero)
            scene.rootNode.addChildNode(key)

            let fill = SCNNode()
            fill.light = SCNLight()
            fill.light?.type = .directional
            fill.light?.color = UIColor(rgb: 0xA9CFC4)
            fill.light?.intensity = 460
            fill.position = SCNVector3(9, 7, -7)
            fill.look(at: SCNVector3Zero)
            scene.rootNode.addChildNode(fill)

            let target = SCNNode()
            target.name = "home-island-camera-target"
            target.position = SCNVector3(0, 0.34, 0)
            scene.rootNode.addChildNode(target)
            cameraTarget = target

            let cameraNode = SCNNode()
            cameraNode.name = "home-island-camera"
            let cameraComponent = SCNCamera()
            cameraComponent.fieldOfView = 48
            // Keep the full buildable width visible on portrait iPhones. With
            // the default vertical projection, the narrow horizontal field of
            // view crops a wide island even though the camera is far enough away.
            cameraComponent.projectionDirection = .horizontal
            cameraComponent.zNear = 0.08
            cameraComponent.zFar = 1_500
            // Exploration stays bright, while photo mode can lower the exposure
            // to preserve detail in pale sand and sunlit props.
            cameraComponent.wantsHDR = true
            cameraComponent.exposureOffset = CGFloat(HomeIslandSceneView.baseExposureOffset)
            cameraComponent.contrast = 0.05
            cameraNode.camera = cameraComponent
            scene.rootNode.addChildNode(cameraNode)
            camera = cameraNode

            let navigator = PhoenixNavigator.makeNavigatorNode()
            navigator.name = "navigator"
            navigator.scale = SCNVector3(
                NavigatorAppearance.islandScale,
                NavigatorAppearance.islandScale,
                NavigatorAppearance.islandScale
            )
            navigator.position = SCNVector3(0, HomeIslandMetrics.surfaceY, 6.68)
            navigator.eulerAngles.y = .pi
            navigator.opacity = 0
            scene.rootNode.addChildNode(navigator)
            navigatorNode = navigator
            navigatorRootToSeatSurface = PhoenixNavigator.seatedRig.rootToSurface
                * NavigatorAppearance.islandScale
            navigatorAnimator.bind(to: navigator, in: scene)

            #if DEBUG
            installDebugFootprintTrailIfRequested()
            #endif

            let travel = SCNNode()
            travel.name = "home-island-arrival-boat"
            travel.eulerAngles.y = .pi / 2 - 0.055
            travel.scale = SCNVector3(
                ArrivalMotion.boatScale,
                ArrivalMotion.boatScale,
                ArrivalMotion.boatScale
            )

            let bob = SCNNode()
            bob.name = "home-island-arrival-bob"
            let boat = VoyageSceneKit.makeBoatModel(BoatCustomization.currentParts)
            // The vessel now lies alongside the low float rather than pointing
            // under the high pier. Its customized beam determines the final
            // clearance, while the raised waterline keeps both decks close
            // enough for a short, believable gangplank.
            let halfBeam = max(
                abs(boat.boundingBox.min.z),
                abs(boat.boundingBox.max.z)
            ) * ArrivalMotion.boatScale
            let floatCenter = arrivalJettyWalkSurface?.worldPosition(
                localX: HomeIslandMetrics.boardingFloatCenterLocalX,
                localZ: HomeIslandMetrics.boardingFloatCenterLocalZ
            ) ?? (x: Float(-1.55), z: Float(12.0))
            let floatHalfWidth = HomeIslandMetrics.boardingFloatHalfWidth
                * HomeIslandMetrics.arrivalJettyScale
            arrivalBoatStopPosition = SCNVector3(
                floatCenter.x - floatHalfWidth - halfBeam - 0.28,
                ArrivalMotion.boatY,
                floatCenter.z
            )
            travel.position = SCNVector3(
                arrivalBoatStopPosition.x - 0.10,
                arrivalBoatStopPosition.y,
                arrivalBoatStopPosition.z + ArrivalMotion.offshoreStartDistance
            )
            let sailor = PhoenixNavigator.makeNavigatorNode()
            sailor.name = "home-island-boat-navigator"
            sailor.scale = SCNVector3(
                VoyageSceneKit.navigatorDeckScale,
                VoyageSceneKit.navigatorDeckScale,
                VoyageSceneKit.navigatorDeckScale
            )
            if let anchor = boat.childNode(withName: "Navigator_Anchor", recursively: true) {
                anchor.addChildNode(sailor)
            } else {
                sailor.position = VoyageSceneKit.navigatorDeckPosition
                boat.addChildNode(sailor)
            }
            bob.addChildNode(boat)
            travel.addChildNode(bob)
            scene.rootNode.addChildNode(travel)
            arrivalBoat = travel
            arrivalBoatBob = bob
            arrivalBoatModel = boat
            arrivalBoatNavigator = sailor
            renderedBoatAppearanceID = owner.boatAppearanceID

            if !UIAccessibility.isReduceMotionEnabled {
                let rise = SCNAction.moveBy(x: 0, y: 0.055, z: 0, duration: 1.25)
                rise.timingMode = .easeInEaseOut
                bob.runAction(.repeatForever(.sequence([rise, rise.reversed()])))
            }

            return scene
        }

        private func installHarborCommons(in scene: SCNScene) {
            fixedHarborSeatAssets.removeAll(keepingCapacity: true)
            fixedHarborWalkingObstacles.removeAll(keepingCapacity: true)

            @discardableResult
            func addAsset(
                _ resourceName: String,
                name: String,
                position: (x: Float, z: Float),
                yaw: Float = 0,
                scale: Float
            ) -> SCNNode? {
                guard let node = AssetPlacementRuntime.makeAssetNode(
                    resourceName: resourceName
                ) else { return nil }
                node.name = name
                HomeIslandTransform(
                    x: position.x,
                    z: position.z,
                    yaw: yaw,
                    scale: scale
                ).apply(to: node)
                scene.rootNode.addChildNode(node)
                return node
            }

            if let surface = arrivalJettyWalkSurface {
                let floatCenter = surface.worldPosition(
                    localX: HomeIslandMetrics.boardingFloatCenterLocalX,
                    localZ: HomeIslandMetrics.boardingFloatCenterLocalZ
                )
                addAsset(
                    "harbor_boarding_float",
                    name: "home-island-locked-boarding-float",
                    position: floatCenter,
                    yaw: HomeIslandMetrics.arrivalJettyYaw,
                    scale: HomeIslandMetrics.arrivalJettyScale
                )
            }

            // The council table and its stools are no longer authored into every
            // island. Both now ship as placeable `council_table` / `council_chair`
            // props the player arranges wherever they like.

            for (index, position) in HomeIslandMetrics.welcomeBeaconPositions.enumerated() {
                if addAsset(
                    "harbor_welcome_beacon",
                    name: "home-island-locked-welcome-beacon-\(index + 1)",
                    position: position,
                    yaw: .pi,
                    scale: HomeIslandMetrics.welcomeBeaconScale
                ) != nil {
                    fixedHarborWalkingObstacles.append(WalkingObstacle(
                        x: position.x,
                        z: position.z,
                        radius: 0.20
                    ))
                }
            }
        }

        private func syncPlacements() {
            let visiblePlacements = owner.store.placements.filter {
                HomeIslandAssetCatalog.isVisibleInCurrentBuild(assetID: $0.assetID)
            }
            let visibleIDs = Set(visiblePlacements.map(\.id))
            for (id, node) in placementNodes where !visibleIDs.contains(id) {
                node.removeFromParentNode()
                placementNodes[id] = nil
            }

            for placement in visiblePlacements {
                let node: SCNNode
                if let existing = placementNodes[placement.id] {
                    node = existing
                } else {
                    guard let loaded = AssetPlacementRuntime.makeAssetNode(
                        resourceName: placement.assetID
                    ) else { continue }
                    loaded.name = "home-placement:\(placement.id.uuidString)"
                    if placement.assetID == "wooden_jetty" {
                        installJettyCollision(on: loaded)
                    }
                    placementParent.addChildNode(loaded)
                    placementNodes[placement.id] = loaded
                    node = loaded
                }
                if moveDragPlacementID == placement.id,
                   let moveDragPosition {
                    placement.transform.apply(to: node)
                    node.position.x = moveDragPosition.x
                    node.position.z = moveDragPosition.z
                } else {
                    placement.transform.apply(to: node)
                }
            }
            walkingObstacles = visiblePlacements.compactMap { placement in
                guard placement.assetID != "mossy_ruins",
                      HomeIslandAssetCatalog.blocksWalking(assetID: placement.assetID) else {
                    return nil
                }
                let collisionRadius = HomeIslandAssetCatalog.walkingCollisionRadius(
                    assetID: placement.assetID,
                    scale: placement.transform.scale
                )
                return WalkingObstacle(
                    x: placement.transform.x,
                    z: placement.transform.z,
                    radius: collisionRadius
                )
            }
            if fixedNoticeBoardNode?.parent != nil {
                walkingObstacles.append(WalkingObstacle(
                    x: HomeIslandMetrics.fixedNoticeBoardPosition.x,
                    z: HomeIslandMetrics.fixedNoticeBoardPosition.z,
                    radius: HomeIslandMetrics.fixedNoticeBoardObstacleRadius
                ))
            }
            walkingObstacles.append(contentsOf: fixedHarborWalkingObstacles)
            ruinsWalkObstacles = visiblePlacements.compactMap { placement in
                guard placement.assetID == "mossy_ruins" else { return nil }
                return RuinsWalkObstacle(transform: placement.transform)
            }
            placedSeatSlots = visiblePlacements.flatMap { placement -> [PlacedSeatSlot] in
                guard let node = placementNodes[placement.id] else { return [] }
                return HomeIslandAssetCatalog.contactSlots(for: placement.assetID).compactMap { slot in
                    guard let seatNode = node.childNode(
                        withName: slot.seatNodeName,
                        recursively: true
                    ), let approachNode = node.childNode(
                        withName: slot.approachNodeName,
                        recursively: true
                    ) else { return nil }
                    return PlacedSeatSlot(
                        placementID: placement.id,
                        slotID: slot.id,
                        motion: slot.motion,
                        seatNode: seatNode,
                        approachNode: approachNode,
                        facesAwayFromApproach: slot.facesAwayFromApproach,
                        seatPlanarOffset: slot.seatPlanarOffset,
                        approachClearance: slot.approachClearance,
                        obstacleCenter: SCNVector3(
                            placement.transform.x,
                            HomeIslandMetrics.surfaceY,
                            placement.transform.z
                        ),
                        obstacleRadius: HomeIslandAssetCatalog.walkingCollisionRadius(
                            assetID: placement.assetID,
                            scale: placement.transform.scale
                        )
                    )
                }
            }
            placedSeatSlots += fixedHarborSeatAssets.flatMap { asset in
                HomeIslandAssetCatalog.contactSlots(for: asset.assetID).compactMap { slot in
                    guard let seatNode = asset.node.childNode(
                        withName: slot.seatNodeName,
                        recursively: true
                    ), let approachNode = asset.node.childNode(
                        withName: slot.approachNodeName,
                        recursively: true
                    ) else { return nil }
                    return PlacedSeatSlot(
                        placementID: asset.id,
                        slotID: slot.id,
                        motion: slot.motion,
                        seatNode: seatNode,
                        approachNode: approachNode,
                        facesAwayFromApproach: slot.facesAwayFromApproach,
                        seatPlanarOffset: slot.seatPlanarOffset,
                        approachClearance: slot.approachClearance,
                        obstacleCenter: asset.obstacleCenter,
                        obstacleRadius: asset.obstacleRadius
                    )
                }
            }
            if let activeAddress = seatInteractionState.seat?.address {
                let seatStillExists = placedSeatSlots.contains {
                    $0.address == activeAddress
                }
                if !seatStillExists {
                    cancelSeatInteraction()
                    if owner.mode == .explore { ensureNavigatorIsWalkable() }
                }
            }
#if DEBUG
            if ProcessInfo.processInfo.environment["LANDFALL_SEAT_DEMO"] != nil,
               !placedSeatSlots.isEmpty {
                scheduleSeatDemoIfRequested()
            }
#endif
            let playerJettySurfaces: [JettyWalkSurface] = owner.store.placements.compactMap {
                placement -> JettyWalkSurface? in
                guard placement.assetID == "wooden_jetty" else { return nil }
                return JettyWalkSurface(transform: placement.transform)
            }
            jettyWalkSurfaces = (arrivalJettyWalkSurface.map { [$0] } ?? [])
                + playerJettySurfaces
            lookoutWalkSurfaces = owner.store.placements.compactMap {
                placement -> LookoutWalkSurface? in
                guard placement.assetID == "cliff_lookout" else { return nil }
                return LookoutWalkSurface(transform: placement.transform)
            }
            updateSelectionOutline()
            view?.setNeedsDisplay()
        }

        private func syncRemotePlayers() {
            let localID = owner.localPlayerID?.trimmingCharacters(in: .whitespacesAndNewlines)
            var statesByID: [String: HomeIslandRemotePlayerState] = [:]
            for state in owner.remotePlayers {
                let id = state.id.trimmingCharacters(in: .whitespacesAndNewlines)
                guard statesByID.count < 12,
                      !id.isEmpty,
                      id != localID,
                      state.isVisible,
                      state.x.isFinite,
                      state.z.isFinite,
                      state.yaw.isFinite,
                      abs(state.x) <= 80,
                      abs(state.z) <= 80
                else { continue }
                let sanitized = HomeIslandRemotePlayerState(
                    id: id,
                    x: state.x,
                    z: state.z,
                    yaw: state.yaw,
                    pose: state.pose,
                    phase: state.phase,
                    seatPlacementID: state.seatPlacementID,
                    seatSlotID: state.seatSlotID,
                    arrivalNonce: state.arrivalNonce.map {
                        String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
                    },
                    isVisible: true
                )
                statesByID[id] = sanitized
            }

            var removedVisuals: [RemotePlayerVisual] = []
            var arrivalsToStart: [(id: String, nonce: String)] = []

            // Ground resolution asks SceneKit for a segment hit. Do it before
            // taking the remote-player lock: the render callback already owns
            // SceneKit's scene lock and must never wait on this lock in the
            // opposite order.
            var positionsByID: [String: SCNVector3] = [:]
            positionsByID.reserveCapacity(statesByID.count)
            for (id, state) in statesByID {
                positionsByID[id] = resolvedRemotePosition(for: state)
            }

            remotePlayersLock.lock()
            for id in Array(remotePlayerVisuals.keys) where statesByID[id] == nil {
                if let removed = remotePlayerVisuals.removeValue(forKey: id) {
                    removedVisuals.append(removed)
                }
            }

            for (id, state) in statesByID {
                guard let position = positionsByID[id] else { continue }
                if let visual = remotePlayerVisuals[id] {
                    visual.targetPosition = position
                    visual.targetYaw = state.yaw
                    visual.targetPose = state.phoenixPose
                    visual.targetSeatAddress = remoteSeatAddress(from: state)
                    if state.phase == "arrival",
                       let nonce = state.arrivalNonce,
                       !nonce.isEmpty,
                       visual.lastArrivalNonce != nonce {
                        visual.lastArrivalNonce = nonce
                        arrivalsToStart.append((id, nonce))
                    }
                    continue
                }

                // 港の相手は自分の装いを着ていない。遠くの航海士は既定の熾火で描く。
                let navigator = PhoenixNavigator.makeNavigatorNode(palette: .default)
                navigator.name = "home-island-remote-player:\(id)"
                navigator.scale = SCNVector3(
                    NavigatorAppearance.islandScale,
                    NavigatorAppearance.islandScale,
                    NavigatorAppearance.islandScale
                )
                navigator.position = position
                navigator.eulerAngles.y = state.yaw
                navigator.eulerAngles.z = state.phoenixPose == .lie
                    ? NavigatorSleepMetrics.roll
                    : 0
                navigator.opacity = 0
                remotePlayersParent.addChildNode(navigator)

                let animator = PhoenixAnimator()
                animator.pose = state.phoenixPose
                animator.bind(to: navigator, in: view?.scene)
                let visual = RemotePlayerVisual(
                    node: navigator,
                    animator: animator,
                    targetPosition: position,
                    targetYaw: state.yaw,
                    targetPose: state.phoenixPose,
                    targetSeatAddress: remoteSeatAddress(from: state)
                )
                remotePlayerVisuals[id] = visual
                if state.phase == "arrival",
                   let nonce = state.arrivalNonce,
                   !nonce.isEmpty {
                    visual.lastArrivalNonce = nonce
                    arrivalsToStart.append((id, nonce))
                } else {
                    navigator.runAction(
                        .fadeIn(duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.18)
                    )
                }
            }
            remotePlayersLock.unlock()

            for visual in removedVisuals {
                tearDownRemoteArrival(for: visual, removesNavigator: false)
                visual.node.removeAllActions()
                let duration = UIAccessibility.isReduceMotionEnabled ? 0 : 0.16
                visual.node.runAction(.sequence([
                    .fadeOut(duration: duration),
                    .removeFromParentNode(),
                ]))
            }
            for arrival in arrivalsToStart {
                startRemoteArrival(playerID: arrival.id, nonce: arrival.nonce)
            }
            resolveLocalSeatConflictIfNeeded()
            if !statesByID.isEmpty || !removedVisuals.isEmpty {
                view?.setNeedsDisplay()
            }
        }

        private func resolvedRemotePosition(
            for state: HomeIslandRemotePlayerState
        ) -> SCNVector3 {
            if state.phoenixPose == .sit
                || state.phoenixPose == .lie
                || state.phoenixPose == .idle,
               let placementID = state.seatPlacementID.flatMap(UUID.init(uuidString:)),
               let slotID = state.seatSlotID {
                let address = HomeIslandSeatAddress(
                    placementID: placementID,
                    slotID: slotID
                )
                if let slot = placedSeatSlots.first(where: { $0.address == address }) {
                    return slot.contactWorldPosition(
                        rootToSeatSurface: navigatorRootToSeatSurface
                    )
                }
            }
            return SCNVector3(
                state.x,
                groundHeight(x: state.x, z: state.z),
                state.z
            )
        }

        private func remoteSeatAddress(
            from state: HomeIslandRemotePlayerState
        ) -> HomeIslandSeatAddress? {
            guard let placementID = state.seatPlacementID.flatMap(UUID.init(uuidString:)),
                  let slotID = state.seatSlotID,
                  !slotID.isEmpty
            else { return nil }
            return HomeIslandSeatAddress(placementID: placementID, slotID: slotID)
        }

        /// Plays an observer-only version of the visitor's arrival. It uses a
        /// separate boat and action keys, so the local arrival/departure state
        /// machine and its camera choreography remain untouched.
        private func startRemoteArrival(playerID: String, nonce: String) {
            remotePlayersLock.lock()
            guard let visual = remotePlayerVisuals[playerID],
                  visual.lastArrivalNonce == nonce
            else {
                remotePlayersLock.unlock()
                return
            }
            let previousBoat = visual.arrivalBoat
            let previousGangplank = visual.arrivalGangplank
            visual.arrivalBoat = nil
            visual.arrivalBoatNavigator = nil
            visual.arrivalGangplank = nil
            visual.isArrivalAnimating = true
            visual.arrivalPose = .idle
            visual.node.removeAllActions()
            visual.node.opacity = 0
            visual.node.scale = SCNVector3(
                NavigatorAppearance.islandScale,
                NavigatorAppearance.islandScale,
                NavigatorAppearance.islandScale
            )
            remotePlayersLock.unlock()

            previousBoat?.removeAllActions()
            previousBoat?.removeFromParentNode()
            previousGangplank?.removeAllActions()
            previousGangplank?.removeFromParentNode()

            let remoteBerth = remoteArrivalBerth(for: playerID)
            let travel = SCNNode()
            travel.name = "home-island-remote-arrival-boat:\(playerID)"
            travel.eulerAngles.y = .pi / 2 - 0.055
            travel.scale = SCNVector3(
                ArrivalMotion.boatScale,
                ArrivalMotion.boatScale,
                ArrivalMotion.boatScale
            )
            travel.position = SCNVector3(
                remoteBerth.x,
                remoteBerth.y,
                remoteBerth.z + ArrivalMotion.offshoreStartDistance
            )

            // One boat model and one static deck sailor are enough for remote
            // observers. Camera nodes, physics bodies and the local bob state
            // machine are deliberately not duplicated.
            // Presence does not carry another member's customization. Use the
            // neutral fleet boat instead of incorrectly borrowing this
            // observer's selected sail color.
            let boat = VoyageSceneKit.makeBoatModel(BoatParts.default)
            let sailor = PhoenixNavigator.makeNavigatorNode(palette: .default)
            sailor.name = "home-island-remote-boat-navigator:\(playerID)"
            sailor.scale = SCNVector3(
                VoyageSceneKit.navigatorDeckScale,
                VoyageSceneKit.navigatorDeckScale,
                VoyageSceneKit.navigatorDeckScale
            )
            if let anchor = boat.childNode(withName: "Navigator_Anchor", recursively: true) {
                anchor.addChildNode(sailor)
            } else {
                sailor.position = VoyageSceneKit.navigatorDeckPosition
                boat.addChildNode(sailor)
            }
            travel.addChildNode(boat)

            remotePlayersLock.lock()
            guard let currentVisual = remotePlayerVisuals[playerID],
                  currentVisual === visual,
                  currentVisual.lastArrivalNonce == nonce,
                  currentVisual.isArrivalAnimating
            else {
                remotePlayersLock.unlock()
                return
            }
            currentVisual.arrivalBoat = travel
            currentVisual.arrivalBoatNavigator = sailor
            remotePlayersLock.unlock()
            remotePlayersParent.addChildNode(travel)

            if UIAccessibility.isReduceMotionEnabled {
                travel.position = remoteBerth
                travel.eulerAngles.y = .pi / 2
                travel.runAction(.sequence([
                    .wait(duration: 0.45),
                    .run { [weak self] _ in
                        DispatchQueue.main.async {
                            self?.beginRemoteLanding(playerID: playerID, nonce: nonce)
                        }
                    },
                ]), forKey: "remote-arrival")
                return
            }

            let openWaterTarget = SCNVector3(
                remoteBerth.x,
                remoteBerth.y,
                remoteBerth.z + ArrivalMotion.berthLeadDistance
            )
            let approach = SCNAction.move(
                to: openWaterTarget,
                duration: ArrivalMotion.openWaterDuration
            )
            approach.timingMode = .easeInEaseOut
            let align = SCNAction.rotateTo(
                x: 0,
                y: .pi / 2,
                z: 0,
                duration: ArrivalMotion.openWaterDuration,
                usesShortestUnitArc: true
            )
            align.timingMode = .easeInEaseOut
            let berth = SCNAction.move(
                to: remoteBerth,
                duration: ArrivalMotion.berthingDuration
            )
            berth.timingMode = .easeOut
            travel.runAction(.sequence([
                .group([approach, align]),
                berth,
                .wait(duration: ArrivalMotion.mooringSettleDuration),
                .run { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.beginRemoteLanding(playerID: playerID, nonce: nonce)
                    }
                },
            ]), forKey: "remote-arrival")
        }

        private func beginRemoteLanding(playerID: String, nonce: String) {
            remotePlayersLock.lock()
            guard let visual = remotePlayerVisuals[playerID],
                  visual.lastArrivalNonce == nonce,
                  visual.isArrivalAnimating,
                  visual.arrivalBoat != nil
            else {
                remotePlayersLock.unlock()
                return
            }

            let path = arrivalJettyLandingPath()
            let remoteBerth = remoteArrivalBerth(for: playerID)
            let fallbackStart = SCNVector3(
                remoteBerth.x,
                0.28,
                remoteBerth.z - 0.68
            )
            let transferStart = visual.arrivalBoatNavigator?.presentation.worldPosition
                ?? fallbackStart
            let transferDirection = path.transfer - transferStart
            let navigator = visual.node
            navigator.removeAllActions()
            navigator.position = transferStart
            navigator.eulerAngles.y = atan2(transferDirection.x, transferDirection.z)
            navigator.scale = SCNVector3(
                NavigatorAppearance.islandScale,
                NavigatorAppearance.islandScale,
                NavigatorAppearance.islandScale
            )
            navigator.opacity = 0
            visual.arrivalPose = .walk

            let deckSailor = visual.arrivalBoatNavigator
            let gangplank = makeArrivalGangplank(from: transferStart, to: path.transfer)
            gangplank.name = "home-island-remote-arrival-gangplank:\(playerID)"
            visual.arrivalGangplank = gangplank
            remotePlayersLock.unlock()

            gangplank.runAction(.fadeIn(duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.18))
            deckSailor?.runAction(.fadeOut(duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.18))

            if UIAccessibility.isReduceMotionEnabled {
                navigator.position = path.transfer
                navigator.scale = SCNVector3(
                    NavigatorAppearance.islandScale,
                    NavigatorAppearance.islandScale,
                    NavigatorAppearance.islandScale
                )
                navigator.opacity = 1
                finishRemoteArrival(playerID: playerID, nonce: nonce)
                return
            }

            let fadeIn = SCNAction.sequence([
                .wait(duration: 0.10),
                .fadeIn(duration: 0.18),
            ])
            let transfer = SCNAction.move(
                to: path.transfer,
                duration: ArrivalMotion.transferDuration
            )
            transfer.timingMode = .easeInEaseOut

            navigator.runAction(.sequence([
                .group([fadeIn, transfer]),
                .run { _ in
                    gangplank.runAction(.sequence([
                        .fadeOut(duration: 0.24),
                        .removeFromParentNode(),
                    ]))
                },
                .wait(duration: ArrivalMotion.jettySettleDuration),
                .run { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.finishRemoteArrival(playerID: playerID, nonce: nonce)
                    }
                },
            ]), forKey: "remote-landing")
        }

        /// Visitors queue in three parallel positions along the outside of the
        /// boarding float. The local boat keeps the closest berth while the
        /// deterministic fore/aft offsets keep simultaneous arrivals legible.
        private func remoteArrivalBerth(for playerID: String) -> SCNVector3 {
            let laneSeed = playerID.utf8.reduce(0) { partial, byte in
                (partial + Int(byte)) % 3
            }
            let lane = Float(laneSeed - 1)
            return SCNVector3(
                arrivalBoatStopPosition.x - 0.55 - abs(lane) * 0.12,
                arrivalBoatStopPosition.y,
                arrivalBoatStopPosition.z + lane * 1.75
            )
        }

        private func finishRemoteArrival(playerID: String, nonce: String) {
            remotePlayersLock.lock()
            guard let visual = remotePlayerVisuals[playerID],
                  visual.lastArrivalNonce == nonce,
                  visual.isArrivalAnimating
            else {
                remotePlayersLock.unlock()
                return
            }
            visual.isArrivalAnimating = false
            visual.arrivalPose = .idle
            let boat = visual.arrivalBoat
            let gangplank = visual.arrivalGangplank
            visual.arrivalBoat = nil
            visual.arrivalBoatNavigator = nil
            visual.arrivalGangplank = nil
            visual.node.opacity = 1
            visual.node.scale = SCNVector3(
                NavigatorAppearance.islandScale,
                NavigatorAppearance.islandScale,
                NavigatorAppearance.islandScale
            )
            remotePlayersLock.unlock()

            gangplank?.removeAllActions()
            gangplank?.runAction(.sequence([
                .fadeOut(duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.18),
                .removeFromParentNode(),
            ]))
            boat?.removeAllActions()
            boat?.runAction(.sequence([
                .fadeOut(duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.28),
                .removeFromParentNode(),
            ]))
        }

        private func tearDownRemoteArrival(
            for visual: RemotePlayerVisual,
            removesNavigator: Bool
        ) {
            visual.arrivalBoat?.removeAllActions()
            visual.arrivalBoat?.removeFromParentNode()
            visual.arrivalGangplank?.removeAllActions()
            visual.arrivalGangplank?.removeFromParentNode()
            visual.arrivalBoat = nil
            visual.arrivalBoatNavigator = nil
            visual.arrivalGangplank = nil
            visual.isArrivalAnimating = false
            visual.arrivalPose = .idle
            if removesNavigator {
                visual.node.removeAllActions()
                visual.node.removeFromParentNode()
            }
        }

        private func installJettyCollision(on node: SCNNode) {
            guard node.childNode(withName: "home-jetty-walk-collision", recursively: false) == nil
            else { return }
            let seawardEnd = HomeIslandMetrics.jettyDeckSeawardEndLocalZ
            let landwardEnd = HomeIslandMetrics.jettyDeckLandwardEndLocalZ
            let box = SCNBox(
                width: 1.26,
                height: 0.08,
                length: CGFloat(landwardEnd - seawardEnd),
                chamferRadius: 0.02
            )
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.clear
            material.transparency = 0
            material.readsFromDepthBuffer = false
            material.writesToDepthBuffer = false
            box.materials = [material]
            let collision = SCNNode(geometry: box)
            collision.name = "home-jetty-walk-collision"
            collision.position = SCNVector3(0, 0.405, (seawardEnd + landwardEnd) * 0.5)
            collision.physicsBody = SCNPhysicsBody(
                type: .static,
                shape: SCNPhysicsShape(geometry: box, options: [.type: SCNPhysicsShape.ShapeType.boundingBox])
            )
            node.addChildNode(collision)
        }

        private func installNoticeBoardHitTarget(on node: SCNNode) {
            let box = SCNBox(width: 2.20, height: 2.05, length: 0.70, chamferRadius: 0.04)
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.clear
            material.transparency = 0
            material.readsFromDepthBuffer = false
            material.writesToDepthBuffer = false
            box.materials = [material]
            let target = SCNNode(geometry: box)
            target.name = "home-island-fixed-notice-board-hit-target"
            target.position = SCNVector3(0, 0.94, 0)
            node.addChildNode(target)
        }

        private func updateSelectionOutline() {
            selectedOutline?.removeFromParentNode()
            selectedOutline = nil
            guard let selectedID = owner.store.selectedID,
                  let node = placementNodes[selectedID]
            else { return }

            // A rim around the prop itself rather than a cage around its
            // bounding box: the player is carrying the thing, so the thing is
            // what should light up. Blue reads as "this spot works", warm
            // orange as "not here".
            let color = selectionMoveBlocked
                ? UIColor(rgb: 0xF2A66F)
                : UIColor(rgb: 0x5CC0F0)
            let bounds = node.boundingBox
            let center = SCNVector3(
                (bounds.min.x + bounds.max.x) * 0.5,
                (bounds.min.y + bounds.max.y) * 0.5,
                (bounds.min.z + bounds.max.z) * 0.5
            )
            let shell = node.clone()
            shell.transform = SCNMatrix4Identity
            shell.position = SCNVector3(-center.x, -center.y, -center.z)
            shell.enumerateHierarchy { child, _ in
                child.physicsBody = nil
                child.castsShadow = false
                child.renderingOrder = -10
                guard let geometry = child.geometry?.copy() as? SCNGeometry else { return }
                let material = SCNMaterial()
                material.lightingModel = .constant
                material.diffuse.contents = color
                material.emission.contents = color
                // Seen from the inside, so only what pokes past the model's own
                // silhouette is drawn. Scaling the shell rather than pushing
                // vertices along their normals keeps it visible on meshes whose
                // normals are missing or flat-shaded into hard facets.
                material.cullMode = .front
                material.writesToDepthBuffer = false
                material.readsFromDepthBuffer = true
                geometry.materials = [material]
                child.geometry = geometry
            }

            // Parented to the prop, so the rim follows every drag and rotation.
            let holder = SCNNode()
            holder.name = "home-island-selection-outline"
            holder.position = center
            holder.scale = SCNVector3(1.06, 1.06, 1.06)
            holder.addChildNode(shell)
            node.addChildNode(holder)
            selectedOutline = holder
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let view,
                  !owner.cameraInteractionLocked
            else { return }
            view.becomeFirstResponder()
            let screenPoint = recognizer.location(in: view)

            if owner.mode == .camera {
                guard !owner.cameraInteractionLocked else { return }
                focusCamera(at: screenPoint)
                return
            }

            if owner.mode == .explore {
                // Interactions win over the invisible phone controls. A boat,
                // notice board, or prop must remain tappable wherever the
                // camera projects it, including the lower-left thumb zone.
                if hitFixedNoticeBoard(at: screenPoint) {
                    owner.onAssetActivated("fixed_notice_board")
                    return
                }
                if hitArrivalBoat(at: screenPoint) {
                    if owner.boatTapOpensSelection {
                        owner.onBoatSelected()
                    } else {
                        attemptBoatBoarding()
                    }
                    return
                }
                if owner.navigatorTapOpensColors, hitNavigator(at: screenPoint) {
                    owner.onNavigatorSelected()
                    return
                }
                guard let placementID = hitPlacement(at: screenPoint),
                      let placement = owner.store.placements.first(where: { $0.id == placementID })
                else {
                    // Phone-first jump: a short empty-space tap on the camera
                    // half of the screen jumps. The thumbstick half stays
                    // deliberately inert — a jump used to live there, which
                    // meant the steering thumb had to lift off to take one, so
                    // jumping while walking was impossible. With the jump on
                    // the camera side, the same touch works standing still or
                    // mid-stride, and `handleRunningJumpPress` covers the case
                    // where the steering thumb is already down.
                    if !isMovementControlPoint(screenPoint, in: view) {
                        triggerTouchJump()
                    }
                    return
                }
                if let interactionRadius = HomeIslandAssetCatalog.interactionRadius(
                    assetID: placement.assetID,
                    scale: placement.transform.scale
                ), let navigator = navigatorNode {
                    let dx = navigator.position.x - placement.transform.x
                    let dz = navigator.position.z - placement.transform.z
                    guard dx * dx + dz * dz <= interactionRadius * interactionRadius else {
                        owner.onAssetInteractionDenied(placement.assetID)
                        Haptics.error()
                        return
                    }
                }
                owner.onAssetActivated(placement.assetID)
                return
            }

            guard owner.mode == .edit else { return }

            if let assetID = owner.placementAssetID,
               let point = groundPoint(at: screenPoint) {
                guard assetID == "wooden_jetty"
                        || HomeIslandMetrics.contains(x: point.x, z: point.z)
                else {
                    owner.onPlacementRejected(.outsideBuildArea)
                    Haptics.error()
                    return
                }
                // Running out of a prop's allowance and standing on a reserved
                // spot used to report the same thing, which read as "you may
                // not overlap that" even though overlap is always allowed.
                let atLimit = !owner.store.canAdd(assetID: assetID)
                guard let placementID = owner.store.add(
                    assetID: assetID,
                    x: point.x,
                    z: point.z,
                    playerLevel: owner.playerLevel
                ) else {
                    if atLimit {
                        owner.onPlacementRejected(.limitReached)
                    } else {
                        owner.onPlacementRejected(
                            assetID == "wooden_jetty" ? .coastRequired : .reserved
                        )
                    }
                    Haptics.error()
                    return
                }
                // The palette selection survives a placement, so a grove or a
                // flower bed is tap-tap-tap instead of a trip back to the shelf
                // between every prop. It clears itself once the allowance runs
                // out, or when the player picks something else.
                let onPlacementCompleted = owner.onPlacementCompleted
                DispatchQueue.main.async {
                    onPlacementCompleted(placementID)
                }
                Haptics.tap(.light)
                return
            }

            // 一度のタップで物が瞬間移動しないよう、タップは選択だけを
            // 担う。移動はドラッグ、指を離した位置で確定。
            if let placementID = hitPlacement(at: screenPoint) {
                owner.store.select(placementID)
                Haptics.tap(.light)
            } else {
                owner.store.select(nil)
            }
        }

        private func triggerTouchJump() {
            walkInputLock.lock()
            pendingTouchJump = true
            walkInputLock.unlock()
        }

        private func clearPendingTouchJump() {
            walkInputLock.lock()
            pendingTouchJump = false
            walkInputLock.unlock()
        }

        private func hasExploreInteractiveTarget(at point: CGPoint) -> Bool {
            hitFixedNoticeBoard(at: point)
                || hitArrivalBoat(at: point)
                || (owner.navigatorTapOpensColors && hitNavigator(at: point))
                || hitPlacement(at: point) != nil
        }

        @objc private func handleRunningJumpPress(
            _ recognizer: UILongPressGestureRecognizer
        ) {
            guard owner.mode == .explore,
                  !owner.cameraInteractionLocked,
                  let view
            else {
                runningJumpBeganAt = nil
                runningJumpBeganPoint = nil
                return
            }
            switch recognizer.state {
            case .began:
                runningJumpBeganAt = CACurrentMediaTime()
                runningJumpBeganPoint = recognizer.location(in: view)
            case .ended:
                let point = recognizer.location(in: view)
                let start = runningJumpBeganPoint ?? point
                let duration = CACurrentMediaTime() - (runningJumpBeganAt ?? 0)
                runningJumpBeganAt = nil
                runningJumpBeganPoint = nil
                guard duration <= 0.24,
                      hypot(point.x - start.x, point.y - start.y) <= 14,
                      !hasExploreInteractiveTarget(at: point)
                else { return }
                triggerTouchJump()
            case .cancelled, .failed:
                runningJumpBeganAt = nil
                runningJumpBeganPoint = nil
            default:
                break
            }
        }

        private func focusCamera(at screenPoint: CGPoint) {
            guard let view, let target = cameraTarget else { return }
            let hits = view.hitTest(
                screenPoint,
                options: [.searchMode: SCNHitTestSearchMode.all.rawValue]
            )
            // 海と、はるか沖の目的地の島は「景色」。ピントの寄せ先にすると
            // カメラが島から遠く離れてしまうので、足元の島の中だけを狙う。
            let focusPoint = hits.first(where: {
                !isOceanNode($0.node) && !isDestinationIslandNode($0.node)
            })?.worldCoordinates
                ?? groundPoint(at: screenPoint).flatMap { point in
                    HomeIslandMetrics.contains(x: point.x, z: point.z) ? point : nil
                }
            guard let focusPoint else { return }
            target.position = focusPoint
            updateCamera(animated: 0.26)
            Haptics.tap(.light)
        }

        private func isOceanNode(_ node: SCNNode) -> Bool {
            var candidate: SCNNode? = node
            while let current = candidate {
                switch current.name {
                case HomeIslandOceanEffects.surfaceNodeName,
                     "home-island-ocean-root",
                     "home-island-ocean-underlay":
                    return true
                default:
                    candidate = current.parent
                }
            }
            return false
        }

        private func isDestinationIslandNode(_ node: SCNNode) -> Bool {
            guard let island = destinationIslandNode else { return false }
            return isDescendant(node, of: island)
        }

        private func hitArrivalBoat(at point: CGPoint) -> Bool {
            guard let view, let boat = arrivalBoat else { return false }
            let hits = view.hitTest(
                point,
                options: [.searchMode: SCNHitTestSearchMode.all.rawValue]
            )
            return hits.contains { hit in
                var candidate: SCNNode? = hit.node
                while let node = candidate {
                    if node === boat { return true }
                    candidate = node.parent
                }
                return false
            }
        }

        private func hitNavigator(at point: CGPoint) -> Bool {
            guard let view, let navigator = navigatorNode else { return false }
            let hits = view.hitTest(
                point,
                options: [.searchMode: SCNHitTestSearchMode.all.rawValue]
            )
            return hits.contains { hit in
                isDescendant(hit.node, of: navigator) || hit.node === navigator
            }
        }

        private func hitFixedNoticeBoard(at point: CGPoint) -> Bool {
            guard let view, let board = fixedNoticeBoardNode else { return false }
            let hits = view.hitTest(
                point,
                options: [.searchMode: SCNHitTestSearchMode.all.rawValue]
            )
            return hits.contains { hit in
                var candidate: SCNNode? = hit.node
                while let node = candidate {
                    if node === board { return true }
                    candidate = node.parent
                }
                return false
            }
        }

        private func attemptBoatBoarding() {
            guard owner.mode == .explore,
                  arrivalFinished,
                  !boardingRequested,
                  !departureStarted,
                  let navigator = navigatorNode
            else { return }
            let boardingPoint = arrivalJettyLandingPath().landing
            let dx = navigator.position.x - boardingPoint.x
            let dz = navigator.position.z - boardingPoint.z
            guard dx * dx + dz * dz
                    <= DepartureMotion.boardingRadius * DepartureMotion.boardingRadius
            else {
                owner.onAssetInteractionDenied("home_boat")
                Haptics.error()
                return
            }
            boardingRequested = true
            touchWalkInput = .zero
            keyboardWalkInput = .zero
            gamepadWalkInput = .zero
            storeCachedWalkInput(.zero)
            Haptics.tap(.medium)
            let onBoatBoardingStarted = owner.onBoatBoardingStarted
            DispatchQueue.main.async {
                onBoatBoardingStarted()
            }
        }

        private func hitPlacement(at point: CGPoint) -> UUID? {
            guard let view else { return nil }
            let hits = view.hitTest(
                point,
                options: [.searchMode: SCNHitTestSearchMode.all.rawValue]
            )
            for hit in hits {
                var candidate: SCNNode? = hit.node
                while let node = candidate {
                    if let name = node.name,
                       name.hasPrefix("home-placement:"),
                       let id = UUID(uuidString: String(name.dropFirst("home-placement:".count))) {
                        return id
                    }
                    candidate = node.parent
                }
            }
            return nil
        }

        /// 指の太さのぶんだけ広げた当たり判定の半径(pt)。
        ///
        /// 花や灯りのような細い飾りは、画面に映る面積が指先より小さい。
        /// 厳密なヒットだけを掴む条件にすると、数ピクセル外しただけで
        /// 「掴めなかった」ことになる。
        private static let grabSlop: CGFloat = 30

        private static let grabProbeDirections: [CGPoint] = {
            let diagonal = CGFloat(0.70710678)
            return [
                CGPoint(x: 1, y: 0),
                CGPoint(x: 0, y: 1),
                CGPoint(x: -1, y: 0),
                CGPoint(x: 0, y: -1),
                CGPoint(x: diagonal, y: diagonal),
                CGPoint(x: -diagonal, y: diagonal),
                CGPoint(x: diagonal, y: -diagonal),
                CGPoint(x: -diagonal, y: -diagonal)
            ]
        }()

        /// 選択中の飾りが、指のすぐ脇にいるか。
        private func selectedPlacementIsNear(_ point: CGPoint, within slop: CGFloat) -> Bool {
            guard owner.store.selectedID != nil, slop > 0 else { return false }
            for radius in [slop * 0.5, slop] {
                for direction in Self.grabProbeDirections {
                    if touchReachesSelectedPlacement(at: CGPoint(
                        x: point.x + direction.x * radius,
                        y: point.y + direction.y * radius
                    )) {
                        return true
                    }
                }
            }
            return false
        }

        /// この指がいま掴むもの。
        ///
        /// 選択中の物が指の下にあるなら、ほかの物の中に立っていて最前面に
        /// 出てこなくてもそれを掴む。そうでなければ、見えているとおり手前の
        /// 物を掴む。指の下に何もなければ何も掴まない — これが「触っていない
        /// 物が飛ぶ」を根本から断つ条件。
        ///
        /// 数ピクセル外したときの助けは、選択中の物にだけ効かせる。指のまわり
        /// から誰でも拾えるようにすると、掴んだつもりのない隣の飾りが代わりに
        /// 動く。掴む相手を変えるには、その飾りに正確に触れてもらう。
        private func grabCandidate(at point: CGPoint) -> UUID? {
            if touchReachesSelectedPlacement(at: point) {
                moveDebug("grab selected-under-finger \(shortID(owner.store.selectedID)) at \(point)")
                return owner.store.selectedID
            }
            if let hit = hitPlacement(at: point) {
                moveDebug("grab exact-hit \(shortID(hit)) asset=\(assetName(hit)) at \(point) selected=\(shortID(owner.store.selectedID))")
                return hit
            }
            guard selectedPlacementIsNear(point, within: Self.grabSlop) else {
                moveDebug("grab NONE at \(point) selected=\(shortID(owner.store.selectedID))")
                return nil
            }
            moveDebug("grab selected-near \(shortID(owner.store.selectedID)) at \(point)")
            return owner.store.selectedID
        }

        private func shortID(_ id: UUID?) -> String {
            guard let id else { return "none" }
            return String(id.uuidString.prefix(8))
        }

        private func assetName(_ id: UUID) -> String {
            owner.store.placements.first { $0.id == id }?.assetID ?? "?"
        }

        /// 指が実際に飾りを引きずっている最中か。
        private var propGrabInFlight: Bool {
            selectionMovePanActive
        }

        private func groundPoint(at point: CGPoint) -> SCNVector3? {
            guard let view else { return nil }
            let near = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 0))
            let far = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 1))
            let direction = far - near
            guard abs(direction.y) > 0.0001 else { return nil }
            let distance = (HomeIslandMetrics.surfaceY - near.y) / direction.y
            guard distance >= 0 else { return nil }
            let hit = near + direction * distance
            // Rays that graze the horizon meet the plane far out at sea. Those
            // points are geometrically valid and practically useless: anchoring
            // a drag on one made the next frame's delta enormous.
            guard hit.x.isFinite, hit.z.isFinite,
                  hit.x * hit.x + hit.z * hit.z
                    <= HomeIslandMetrics.groundRaycastLimit * HomeIslandMetrics.groundRaycastLimit
            else { return nil }
            return hit
        }

        /// A large thumb-reachable region instead of a fixed joystick. The
        /// right and upper portions remain available for direct camera orbit,
        /// and UIKit can track one finger in each region simultaneously.
        private func isMovementControlPoint(_ point: CGPoint, in view: UIView) -> Bool {
            guard owner.mode == .explore || owner.mode == .edit,
                  !owner.cameraInteractionLocked,
                  !owner.cameraShowcaseActive,
                  !boardingRequested
            else { return false }
            // While a prop is being carried the whole screen belongs to it.
            // Sharing the lower-left corner with the walk control meant a drag
            // that started there walked the navigator instead of moving what
            // the player was holding.
            if owner.mode == .edit, selectionMovePanActive {
                return false
            }
            let bounds = view.bounds
            let safeInsets = view.safeAreaInsets
            let usableTop = max(bounds.minY + safeInsets.top, bounds.minY)
            let usableBottom = min(bounds.maxY - safeInsets.bottom, bounds.maxY)
            let usableHeight = max(usableBottom - usableTop, 1)
            let movementTop = usableTop + usableHeight * 0.54
            let movementWidthRatio: CGFloat = bounds.width < 600 ? 0.58 : 0.48
            let movementRight = bounds.minX + bounds.width * movementWidthRatio
            return point.x >= bounds.minX
                && point.x <= movementRight
                && point.y >= movementTop
                && point.y <= usableBottom
        }

        @objc private func handleMovementPan(_ recognizer: UIPanGestureRecognizer) {
            guard owner.mode == .explore || owner.mode == .edit,
                  !owner.cameraInteractionLocked,
                  !owner.cameraShowcaseActive,
                  !boardingRequested,
                  let view
            else {
                resetTouchMovement()
                return
            }
            view.becomeFirstResponder()
            switch recognizer.state {
            case .began:
                movementFeedbackSent = false
                touchWalkInput = .zero
                refreshWalkInput()
            case .changed:
                let translation = recognizer.translation(in: view)
                let dx = Float(translation.x)
                let dy = Float(translation.y)
                let distance = sqrt(dx * dx + dy * dy)
                let maximumRadius = Float(min(
                    max(min(view.bounds.width, view.bounds.height) * 0.16, 56),
                    84
                ))
                let deadZone = max(maximumRadius * 0.12, 7)
                guard distance > deadZone else {
                    touchWalkInput = .zero
                    editCameraPanInput = .zero
                    refreshWalkInput()
                    return
                }
                let normalizedDistance = min(
                    max((distance - deadZone) / max(maximumRadius - deadZone, 1), 0),
                    1
                )
                // A slightly accelerated response gives precise walking close
                // to the origin and reaches full speed with an intentional drag.
                let response = pow(normalizedDistance, 0.86)
                touchWalkInput = HomeIslandWalkInput(
                    x: dx / max(distance, 0.001) * response,
                    forward: -dy / max(distance, 0.001) * response
                )
                if !movementFeedbackSent {
                    movementFeedbackSent = true
                    Haptics.tap(.light)
                }
                if owner.mode == .edit {
                    editCameraPanInput = touchWalkInput
                    touchWalkInput = .zero
                }
                refreshWalkInput()
            case .ended, .cancelled, .failed:
                editCameraPanInput = .zero
                resetTouchMovement()
            default:
                break
            }
        }

        private func resetTouchMovement() {
            touchWalkInput = .zero
            movementFeedbackSent = false
            refreshWalkInput()
        }

        private func refreshWalkInput() {
            guard !(owner.startsMooredAtIsland && owner.locksMooredOverview),
                  owner.mode == .explore,
                  !owner.cameraInteractionLocked,
                  !owner.cameraShowcaseActive,
                  !boardingRequested
            else {
                storeCachedWalkInput(.zero)
                return
            }
            // One primary device owns movement at a time. This prevents a
            // resting thumb and a controller from adding into an unintended
            // sprint, while retaining immediate fallback when either is released.
            let sourceDeadZone = locomotionTuning.inputDeadZone
            var input: HomeIslandWalkInput
            if gamepadWalkInput.magnitude > sourceDeadZone {
                input = gamepadWalkInput
            } else if touchWalkInput.magnitude > sourceDeadZone {
                input = touchWalkInput
            } else if keyboardWalkInput.magnitude > sourceDeadZone {
                input = keyboardWalkInput
            } else {
                input = externalWalkInput
            }
            // Buttons are independent from axis ownership: pressing gamepad A
            // while steering by touch jumps without dropping the touch axis.
            input.jumpRequested = input.jumpRequested
                || gamepadWalkInput.jumpRequested
                || keyboardWalkInput.jumpRequested
                || externalWalkInput.jumpRequested
            let magnitude = sqrt(input.x * input.x + input.forward * input.forward)
            if magnitude > 1 {
                input.x /= magnitude
                input.forward /= magnitude
            }
            storeCachedWalkInput(input)
        }

        private func storeCachedWalkInput(_ input: HomeIslandWalkInput) {
            walkInputLock.lock()
            cachedWalkInput = input
            walkInputLock.unlock()
        }

        private func currentCachedWalkInput() -> HomeIslandWalkInput {
            walkInputLock.lock()
            var input = cachedWalkInput
            if pendingTouchJump {
                input.jumpRequested = true
                pendingTouchJump = false
            }
            walkInputLock.unlock()
            return input
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard owner.mode != .arrival,
                  owner.mode != .departure,
                  !owner.cameraInteractionLocked,
                  let view
            else { return }
            view.becomeFirstResponder()

            // 新しいドラッグは必ず所有者を決め直す。前のドラッグの残りが
            // 効いていると、触っていない飾りが動く。
            if recognizer.state == .began {
                selectionMovePanActive = false
                // 指のないパン — トラックパッドのスクロール — で飾りを
                // 掴んではいけない。あれはカメラの寄り引き。
                if owner.mode == .edit,
                   owner.placementAssetID == nil,
                   recognizer.numberOfTouches > 0 {
                    // 掴む相手は指が触れた瞬間に決めてある(`shouldReceive`)。
                    // UIPanのしきい値を超えるまでに指が細い飾りから外れても、
                    // 掴んだものは変わらない。取りこぼしたときだけ拾い直す。
                    if selectionMoveTouchPlacementID == nil {
                        selectionMoveTouchPlacementID = grabCandidate(
                            at: recognizer.location(in: view)
                        )
                    }
                    selectionMovePanActive = selectionMoveTouchPlacementID != nil
                }
            }

            // 掴んでいるあいだ、この指はその飾りのもの。
            //
            // 指が離れた瞬間に `numberOfTouches` は 0 へ戻る。下の
            // ポインタ用の分岐を先に通すと、そこで `.ended` が食われて
            // `handleSelectionMove` に永久に届かない。移動は一度も確定せず、
            // ノードはプレビュー位置に取り残され、次の再描画で保存済みの
            // 座標へ弾き戻される — 「一つ前に触ったものが瞬間移動する」の
            // 正体はこれだった。確定を待つ側を先に見る。
            if selectionMovePanActive {
                handleSelectionMove(recognizer, in: view)
                if recognizer.state == .ended
                    || recognizer.state == .cancelled
                    || recognizer.state == .failed {
                    selectionMovePanActive = false
                }
                return
            }

            if recognizer.numberOfTouches == 0 {
                handlePointerScroll(recognizer)
                return
            }
            let translation = recognizer.translation(in: view)
            switch recognizer.state {
            case .began:
                initialAzimuth = azimuth
                initialElevation = elevation
            case .changed:
                let nextAzimuth = initialAzimuth + Float(translation.x) * 0.0064
                let nextElevation = initialElevation + Float(translation.y) * 0.0052
                if owner.mode == .explore {
                    queueExploreOrbit(azimuth: nextAzimuth, elevation: nextElevation)
                } else {
                    azimuth = nextAzimuth
                    elevation = nextElevation
                    updateCamera()
                }
            case .ended, .cancelled, .failed:
                let velocity = recognizer.velocity(in: view)
                if owner.mode == .explore {
                    let velocityAzimuth = recognizer.state == .ended
                        ? Float(velocity.x) * 0.00010
                        : 0
                    let velocityElevation = recognizer.state == .ended
                        ? Float(velocity.y) * 0.000075
                        : 0
                    queueExploreOrbit(
                        azimuth: initialAzimuth
                            + Float(translation.x) * 0.0064
                            + velocityAzimuth,
                        elevation: initialElevation
                            + Float(translation.y) * 0.0052
                            + velocityElevation
                    )
                } else {
                    if recognizer.state == .ended {
                        azimuth += Float(velocity.x) * 0.00010
                        elevation += Float(velocity.y) * 0.000075
                    }
                    updateCamera(animated: recognizer.state == .ended ? 0.18 : 0)
                }
            default:
                break
            }
        }

        private func queueExploreOrbit(azimuth: Float, elevation: Float) {
            exploreOrbitLock.lock()
            pendingExploreOrbitAngles = (azimuth, elevation)
            exploreOrbitLock.unlock()
        }

        private func applyPendingExploreOrbit() {
            exploreOrbitLock.lock()
            let pending = pendingExploreOrbitAngles
            pendingExploreOrbitAngles = nil
            exploreOrbitLock.unlock()
            guard let pending else { return }
            azimuth = pending.azimuth
            elevation = pending.elevation
        }

        /// Opt-in drag tracing: `SIMCTL_CHILD_LANDFALL_MOVE_DEBUG=1`.
        private static let moveDebugEnabled =
            ProcessInfo.processInfo.environment["LANDFALL_MOVE_DEBUG"] == "1"

        private func moveDebug(_ message: @autoclosure () -> String) {
            guard Self.moveDebugEnabled else { return }
            NSLog("LF_MOVE %@", message())
        }

        /// The furthest a prop may travel in one drag frame, in world units.
        /// A fast deliberate drag covers well under half of this in a frame,
        /// while the old 4.0 allowance still let one bad ground reading throw
        /// a prop most of the way across the island. A capped frame only lags
        /// the finger; the next frame catches up.
        private static let maximumMoveStep: Float = 1.2

        private func handleSelectionMove(
            _ recognizer: UIPanGestureRecognizer,
            in view: SCNView
        ) {
            let screenPoint = recognizer.location(in: view)
            if recognizer.state == .began {
                adoptTouchedPlacementIfNeeded(at: screenPoint)
            }

            // 動かすのは、この指が掴んだものだけ。「選択中だから」という
            // 理由だけで画面外の物が動くことは、もうない。
            guard let targetID = selectionMoveTouchPlacementID ?? moveDragPlacementID,
                  owner.store.selectedID == targetID,
                  let selected = owner.store.placements.first(where: { $0.id == targetID }),
                  let node = placementNodes[targetID]
            else {
                clearSelectionMoveDrag()
                return
            }
            switch recognizer.state {
            case .began:
                guard let point = groundPoint(at: screenPoint) else {
                    moveDebug("began NO-GROUND screen=\(screenPoint)")
                    return
                }
                moveDebug("began screen=\(screenPoint) ground=(\(point.x), \(point.z)) prop=(\(selected.transform.x), \(selected.transform.z))")
                moveDragPlacementID = selected.id
                moveDragLastGroundPoint = point
                moveDragPosition = SCNVector3(
                    selected.transform.x,
                    HomeIslandMetrics.surfaceY,
                    selected.transform.z
                )
                setSelectionMoveBlocked(false)
                let onMoveBegan = owner.onMoveBegan
                DispatchQueue.main.async {
                    onMoveBegan()
                }
            case .changed:
                guard let point = groundPoint(at: screenPoint) else { return }
                // The touch may have started on the sky or out past the usable
                // ground. Arm the drag on the first frame that does resolve
                // instead of dead-ending the whole gesture.
                guard moveDragPlacementID == selected.id,
                      let previousGroundPoint = moveDragLastGroundPoint,
                      let currentPosition = moveDragPosition
                else {
                    moveDragPlacementID = selected.id
                    moveDragLastGroundPoint = point
                    moveDragPosition = SCNVector3(
                        selected.transform.x,
                        HomeIslandMetrics.surfaceY,
                        selected.transform.z
                    )
                    setSelectionMoveBlocked(false)
                    moveDebug("armed late ground=(\(point.x), \(point.z))")
                    return
                }
                // Consume pointer deltas even while blocked. Absolute targeting
                // accumulated distance behind an obstacle and then jumped the
                // prop across it as soon as the far side became valid.
                // A frame's travel is capped. Camera-relative deltas can spike
                // when the finger crosses a shallow-angle part of the ground,
                // and an uncapped delta swept the prop to the far shore in one
                // frame — the prop simply vanished from under the finger.
                var delta = SIMD2<Float>(
                    point.x - previousGroundPoint.x,
                    point.z - previousGroundPoint.z
                )
                let deltaLength = simd_length(delta)
                if deltaLength > Self.maximumMoveStep {
                    delta *= Self.maximumMoveStep / deltaLength
                }
                let target = SIMD2<Float>(
                    currentPosition.x + delta.x,
                    currentPosition.z + delta.y
                )
                moveDebug("changed ground=(\(point.x), \(point.z)) target=(\(target.x), \(target.y))")
                let resolution = resolveSelectionMove(
                    selected: selected,
                    from: SIMD2<Float>(currentPosition.x, currentPosition.z),
                    toward: target
                )
                moveDebug("resolved=(\(resolution.transform.x), \(resolution.transform.z)) blocked=\(resolution.wasBlocked)")
                let transform = resolution.transform
                // The anchor advances by what the prop actually travelled, not
                // by what the finger asked for. A frame spent pinned against
                // the shoreline therefore builds no debt: the prop stays glued
                // to the finger's motion instead of lurching once it is free.
                moveDragLastGroundPoint = SCNVector3(
                    previousGroundPoint.x + (transform.x - currentPosition.x),
                    HomeIslandMetrics.surfaceY,
                    previousGroundPoint.z + (transform.z - currentPosition.z)
                )
                setSelectionMoveBlocked(resolution.wasBlocked)
                let worldPosition = SCNVector3(
                    transform.x,
                    HomeIslandMetrics.surfaceY,
                    transform.z
                )
                moveDragPosition = worldPosition
                node.position.x = worldPosition.x
                node.position.z = worldPosition.z
                node.eulerAngles.y = transform.yaw
                view.setNeedsDisplay()
            case .ended:
                // Fall back to the node's own previewed position: losing the
                // drag bookkeeping must not silently discard the move.
                guard let position = moveDragPosition ?? (moveDragPlacementID == nil ? nil : node.position)
                else {
                    // Nothing was ever picked up — a stray touch on the sky, or
                    // a tap too short to resolve ground. Leave the prop and the
                    // move mode exactly as they were.
                    moveDebug("ended unarmed, ignored")
                    clearSelectionMoveDrag()
                    return
                }
                moveDebug("ended commit=(\(position.x), \(position.z)) node=(\(node.position.x), \(node.position.z)) dragID=\(String(describing: moveDragPlacementID))")
                guard moveDragPlacementID == nil || moveDragPlacementID == selected.id
                else {
                    clearSelectionMoveDrag()
                    return
                }
                guard owner.store.moveSelected(x: position.x, z: position.z) else {
                    selected.transform.apply(to: node)
                    clearSelectionMoveDrag()
                    owner.onPlacementRejected(.reserved)
                    Haptics.error()
                    return
                }
                clearSelectionMoveDrag()
                owner.onMoveCompleted()
                Haptics.tap(.medium)
            case .cancelled, .failed:
                selected.transform.apply(to: node)
                clearSelectionMoveDrag()
            default:
                break
            }
        }

        /// 指が置かれた先の物を掴み、そのまま編集対象にする。
        ///
        /// かつては「移動モード中はどこをドラッグしても選択中の物が動く」
        /// 作りだった。細い飾りを数ピクセル外して触ると乗り換えが起きず、
        /// 離れた場所にある — たいていは一つ前に置いたばかりの — 物が
        /// 指の動きに引きずられて飛んだ。掴む相手は常に指の下にある物。
        ///
        /// 掴んだ時点で選択も移るので、続けて別の飾りを触れば、持ち替える
        /// ための操作を挟まずにそちらの編集へ入れる。
        private func adoptTouchedPlacementIfNeeded(at point: CGPoint) {
            guard let touched = selectionMoveTouchPlacementID ?? grabCandidate(at: point)
            else {
                selectionMoveTouchPlacementID = nil
                return
            }
            selectionMoveTouchPlacementID = touched
            guard touched != owner.store.selectedID else { return }
            owner.store.select(touched)
        }

        /// 指の下に選択中の物があるか。手前の物に隠れていても数える。
        private func touchReachesSelectedPlacement(at point: CGPoint) -> Bool {
            guard let view,
                  let selectedID = owner.store.selectedID,
                  let selectedNode = placementNodes[selectedID]
            else { return false }
            let hits = view.hitTest(
                point,
                options: [.searchMode: SCNHitTestSearchMode.all.rawValue]
            )
            return hits.contains { hit in
                hit.node === selectedNode || isDescendant(hit.node, of: selectedNode)
            }
        }

        private func clearSelectionMoveDrag() {
            moveDragPlacementID = nil
            moveDragLastGroundPoint = nil
            moveDragPosition = nil
            selectionMovePanActive = false
            selectionMoveTouchPlacementID = nil
            setSelectionMoveBlocked(false)
        }

        private func cancelSelectionMovePreviewIfNeeded() {
            // A drag under the finger owns the prop until it is released.
            // SwiftUI re-renders during the drag (the blocked-state chip alone
            // causes one), and cancelling here dropped the drag mid-flight:
            // the prop kept following the finger as a preview, but the release
            // no longer committed, so it snapped back to where it started.
            guard !selectionMovePanActive else { return }
            guard let moveDragPlacementID,
                  owner.mode != .edit
                    || owner.cameraInteractionLocked
                    || owner.store.selectedID != moveDragPlacementID
            else { return }

            if let stored = owner.store.placements.first(where: {
                $0.id == moveDragPlacementID
            }), let node = placementNodes[moveDragPlacementID] {
                stored.transform.apply(to: node)
            }
            self.moveDragPlacementID = nil
            moveDragLastGroundPoint = nil
            moveDragPosition = nil
            selectionMovePanActive = false
            selectionMoveTouchPlacementID = nil
            if selectionMoveBlocked {
                selectionMoveBlocked = false
                let onMoveBlockedChanged = owner.onMoveBlockedChanged
                DispatchQueue.main.async {
                    onMoveBlockedChanged(false)
                }
            }
        }

        private func setSelectionMoveBlocked(_ blocked: Bool) {
            guard selectionMoveBlocked != blocked else { return }
            selectionMoveBlocked = blocked
            updateSelectionOutline()
            owner.onMoveBlockedChanged(blocked)
            if blocked { Haptics.tap(.light) }
        }

        /// Sweeps the prop in short deterministic steps and falls back to each
        /// axis independently. This prevents tunnelling through small props and
        /// lets the dragged object slide along a neighbour or shoreline instead
        /// of feeling glued to the first collision point.
        private func resolveSelectionMove(
            selected: HomeIslandPlacement,
            from start: SIMD2<Float>,
            toward target: SIMD2<Float>
        ) -> (transform: HomeIslandTransform, wasBlocked: Bool) {
            let displacement = target - start
            let distance = simd_length(displacement)
            moveDebug("resolve distance=\(distance) steps=\(distance / 0.12)")
            let stepCount = min(64, max(1, Int(ceil(min(distance, 8) / 0.12))))
            let increment = displacement / Float(stepCount)
            var current = selected.transform
            current.x = start.x
            current.z = start.y
            var wasBlocked = false

            func valid(_ x: Float, _ z: Float) -> HomeIslandTransform? {
                owner.store.validTransform(
                    assetID: selected.assetID,
                    x: x,
                    z: z,
                    yaw: current.yaw,
                    scale: selected.transform.scale,
                    excluding: selected.id,
                    requireValidCoastPoint: selected.assetID == "wooden_jetty"
                )
            }

            for _ in 0..<stepCount {
                let desiredX = current.x + increment.x
                let desiredZ = current.z + increment.y
                if let direct = valid(desiredX, desiredZ) {
                    current = direct
                    continue
                }

                wasBlocked = true
                let xOnly = valid(desiredX, current.z)
                let zOnly = valid(current.x, desiredZ)
                if let xOnly, let zOnly {
                    current = abs(increment.x) >= abs(increment.y) ? xOnly : zOnly
                } else if let xOnly {
                    current = xOnly
                } else if let zOnly {
                    current = zOnly
                }
            }
            return (current, wasBlocked)
        }

        @objc private func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
            guard owner.mode == .edit || owner.mode == .camera,
                  !owner.cameraInteractionLocked,
                  let view,
                  let target = cameraTarget
            else { return }
            let translation = recognizer.translation(in: view)
            switch recognizer.state {
            case .began:
                initialCameraTarget = target.position
            case .changed:
                let sensitivity = max(radius, 2) * 0.00125
                let horizontal = Float(translation.x) * sensitivity
                let vertical = Float(translation.y) * sensitivity
                let basis = cameraGroundBasis()
                target.position = SCNVector3(
                    initialCameraTarget.x - basis.right.x * horizontal
                        + basis.forward.x * vertical,
                    initialCameraTarget.y,
                    initialCameraTarget.z - basis.right.z * horizontal
                        + basis.forward.z * vertical
                )
                updateCamera()
            default:
                break
            }
        }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard owner.mode != .arrival,
                  owner.mode != .departure,
                  !owner.cameraInteractionLocked,
                  let view,
                  let target = cameraTarget
            else { return }
            switch recognizer.state {
            case .began:
                initialRadius = radius
                initialCameraTarget = target.position
                pinchAnchorWorldPoint = groundPoint(at: recognizer.location(in: view))
            case .changed:
                radius = initialRadius / pow(Float(recognizer.scale), 0.86)
                if owner.mode == .edit || owner.mode == .camera,
                   let anchor = pinchAnchorWorldPoint {
                    let focusStrength = min(
                        max(1 - radius / max(initialRadius, 0.001), 0),
                        0.78
                    )
                    target.position = SCNVector3(
                        initialCameraTarget.x + (anchor.x - initialCameraTarget.x) * focusStrength,
                        initialCameraTarget.y + (anchor.y - initialCameraTarget.y) * focusStrength,
                        initialCameraTarget.z + (anchor.z - initialCameraTarget.z) * focusStrength
                    )
                }
                updateCamera()
            case .ended, .cancelled, .failed:
                pinchAnchorWorldPoint = nil
                updateCamera(animated: 0.10)
            default:
                break
            }
        }

        @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard owner.mode == .edit || owner.mode == .camera,
                  !owner.cameraInteractionLocked,
                  !selectionMovePanActive,
                  recognizer.state == .began,
                  let view
            else { return }
            if owner.mode == .camera {
                focusCamera(at: recognizer.location(in: view))
                return
            }
            // Pressing a prop picks it up directly: select it and enter move
            // mode in one gesture, instead of tap, read the dock, tap "move".
            if let placementID = hitPlacement(at: recognizer.location(in: view)) {
                owner.onAssetActivated("carry:\(placementID.uuidString)")
                Haptics.tap(.medium)
                return
            }
            guard let point = groundPoint(at: recognizer.location(in: view)),
                  let target = cameraTarget
            else { return }
            target.position = point
            updateCamera(animated: 0.24)
            Haptics.tap(.medium)
        }

        private func handlePointerScroll(_ recognizer: UIPanGestureRecognizer) {
            guard owner.mode != .arrival,
                  owner.mode != .departure,
                  !selectionMovePanActive,
                  !owner.cameraInteractionLocked,
                  let view
            else { return }
            let translation = recognizer.translation(in: view)
            switch recognizer.state {
            case .began:
                initialRadius = radius
            case .changed:
                radius = initialRadius * exp(Float(translation.y) * 0.006)
                updateCamera()
            case .ended, .cancelled, .failed:
                updateCamera(animated: 0.10)
            default:
                break
            }
        }

        @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard owner.mode != .arrival,
                  owner.mode != .departure,
                  !owner.cameraInteractionLocked,
                  recognizer.state == .ended
            else { return }
            resetCamera(animated: true)
        }

        private func resetCamera(animated: Bool) {
            if owner.mode == .explore {
                if owner.startsMooredAtIsland, owner.locksMooredOverview {
                    enterIslandOverviewCamera(animated: animated ? 0.36 : 0)
                } else {
                    enterExploreCamera(animated: animated ? 0.36 : 0)
                }
                return
            }
            if owner.mode == .edit {
                enterBuildCamera(animated: animated ? 0.36 : 0)
                return
            }
            azimuth = nearestEquivalentAzimuth(to: 0.72)
            elevation = owner.mode == .camera ? 0.38 : 0.42
            radius = owner.mode == .camera ? 25.5 : 30.8
            cameraTarget?.position = SCNVector3(0, 0.34, 0)
            guard animated else {
                updateCamera()
                return
            }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = UIAccessibility.isReduceMotionEnabled ? 0 : 0.42
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
            updateCamera()
            SCNTransaction.commit()
        }

        private func processCameraRequestIfNeeded() {
            guard owner.mode == .edit || owner.mode == .camera,
                  !owner.cameraInteractionLocked,
                  let request = owner.cameraRequest,
                  request.id != processedCameraRequestID
            else { return }
            processedCameraRequestID = request.id

            switch request.action {
            case .reset:
                resetCamera(animated: true)
            case .moveForward:
                nudgeCamera(forward: 1, right: 0)
            case .moveBackward:
                nudgeCamera(forward: -1, right: 0)
            case .moveLeft:
                nudgeCamera(forward: 0, right: -1)
            case .moveRight:
                nudgeCamera(forward: 0, right: 1)
            case .zoomIn:
                zoomCamera(by: 0.78)
            case .zoomOut:
                zoomCamera(by: 1.28)
            }
        }

        /// SCNViewだけを撮るため、SwiftUI側のシャッターやガイドは画像に入らない。
        private func processCaptureRequestIfNeeded() {
            guard owner.mode == .camera,
                  let request = owner.captureRequest,
                  request.id != processedCaptureRequestID,
                  let view
            else { return }
            processedCaptureRequestID = request.id

            SCNTransaction.flush()
            let image = view.snapshot()
            let onCaptured = owner.onCaptured
            DispatchQueue.main.async {
                onCaptured(request.id, image)
            }
        }

        private func processBoatBoardingRequestIfNeeded() {
            guard let request = owner.boatBoardingRequest,
                  request.id != processedBoatBoardingRequestID
            else { return }
            processedBoatBoardingRequestID = request.id
            if owner.startsMooredAtIsland {
                prepareNavigatorForEmbeddedBoarding()
            }
            attemptBoatBoarding()
        }

        private func nudgeCamera(forward: Float, right: Float) {
            guard let target = cameraTarget else { return }
            let step = min(max(radius * 0.08, 0.60), 3.0)
            let basis = cameraGroundBasis()
            target.position.x += (basis.forward.x * forward + basis.right.x * right) * step
            target.position.z += (basis.forward.z * forward + basis.right.z * right) * step
            updateCamera(animated: 0.18)
        }

        private func cameraGroundBasis() -> (forward: SCNVector3, right: SCNVector3) {
            (
                SCNVector3(-cos(azimuth), 0, -sin(azimuth)),
                SCNVector3(sin(azimuth), 0, -cos(azimuth))
            )
        }

        private func handleKeyboardMovement(
            _ input: HomeIslandWalkInput,
            deltaTime: Float
        ) {
            if owner.cameraInteractionLocked {
                keyboardWalkInput = .zero
                storeCachedWalkInput(.zero)
                return
            }
            if owner.startsMooredAtIsland,
               owner.locksMooredOverview,
               owner.mode == .explore {
                keyboardWalkInput = .zero
                storeCachedWalkInput(.zero)
                return
            }
            switch owner.mode {
            case .arrival, .departure:
                keyboardWalkInput = .zero
                storeCachedWalkInput(.zero)
            case .explore:
                keyboardWalkInput = input
                refreshWalkInput()
            case .edit, .camera:
                keyboardWalkInput = .zero
                storeCachedWalkInput(.zero)
                guard !owner.cameraInteractionLocked
                else { return }
                guard deltaTime > 0, let target = cameraTarget else { return }
                let speed = min(max(radius * 0.65, 5.0), 28.0)
                let distance = speed * min(deltaTime, 0.05)
                let basis = cameraGroundBasis()
                target.position.x += (
                    basis.forward.x * input.forward + basis.right.x * input.x
                ) * distance
                target.position.z += (
                    basis.forward.z * input.forward + basis.right.z * input.x
                ) * distance
                updateCamera()
            }
        }

        /// Slides the camera's ground target. Speed scales with how far out the
        /// camera is, so a zoomed-out survey crosses the island at the same
        /// apparent rate as a close-up nudge.
        private func panEditCamera(with input: HomeIslandWalkInput, deltaTime: Float) {
            guard !owner.cameraInteractionLocked,
                  deltaTime > 0,
                  let target = cameraTarget
            else { return }
            let speed = min(max(radius * 0.65, 5.0), 28.0)
            let distance = speed * min(deltaTime, 0.05)
            let basis = cameraGroundBasis()
            target.position.x += (
                basis.forward.x * input.forward + basis.right.x * input.x
            ) * distance
            target.position.z += (
                basis.forward.z * input.forward + basis.right.z * input.x
            ) * distance
            updateCamera()
        }

        private func handleGamepadMovement(
            _ input: HomeIslandWalkInput,
            deltaTime _: Float
        ) {
            guard owner.mode == .explore,
                  !owner.cameraInteractionLocked,
                  !owner.cameraShowcaseActive,
                  !boardingRequested
            else {
                gamepadWalkInput = .zero
                refreshWalkInput()
                return
            }
            gamepadWalkInput = input
            refreshWalkInput()
        }

        private func handleGamepadLook(x: Float, y: Float, deltaTime: Float) {
            guard owner.mode == .explore,
                  !owner.cameraInteractionLocked,
                  !owner.cameraShowcaseActive,
                  deltaTime > 0
            else { return }
            let dt = min(deltaTime, 0.05)
            let response: Float = 2.25
            queueExploreOrbit(
                azimuth: azimuth + x * response * dt,
                elevation: elevation - y * response * 0.72 * dt
            )
        }

        private func zoomCamera(by factor: Float) {
            radius *= factor
            updateCamera(animated: 0.18)
        }

        private func updateCamera(animated duration: TimeInterval = 0) {
            constrainCamera()
            guard let camera, let target = cameraTarget?.position else { return }
            let usesLocomotionCamera = owner.mode == .explore
                && !owner.cameraShowcaseActive
                && !(owner.startsMooredAtIsland && owner.locksMooredOverview)
            let renderedRadius = radius + (usesLocomotionCamera ? cameraMotion.pullback : 0)
            camera.camera?.zNear = Double(max(0.012, renderedRadius * 0.002))
            camera.camera?.zFar = Double(max(1_500, renderedRadius * 8))
            if usesLocomotionCamera {
                camera.camera?.fieldOfView = CGFloat(48 + cameraMotion.fovBoost)
            }
            if duration > 0 {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = UIAccessibility.isReduceMotionEnabled ? 0 : duration
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            }
            let horizontal = cos(elevation) * renderedRadius
            camera.position = SCNVector3(
                target.x + cos(azimuth) * horizontal,
                target.y + sin(elevation) * renderedRadius,
                target.z + sin(azimuth) * horizontal
            )
            camera.look(
                at: target,
                up: SCNVector3(0, 1, 0),
                localFront: SCNVector3(0, 0, -1)
            )
            if duration > 0 { SCNTransaction.commit() }
        }

        private func constrainCamera() {
            if !azimuth.isFinite { azimuth = 0.72 }
            // 目的地の目線は、島までの距離そのものを半径に使い、水平に近い高さから
            // 見る。歩き回るための仰角・距離・注視点の制限をここで当てると、
            // 沖の島まで届かず、見下ろす角度になってしまう。
            if owner.destinationGazeActive { return }
            elevation = min(max(elevation, 0.08), 1.28)
            switch owner.mode {
            case .explore:
                radius = owner.startsMooredAtIsland && owner.locksMooredOverview
                    ? min(max(radius, 11.5), 48)
                    : min(max(radius, 3.2), 11.5)
            case .camera:
                radius = min(max(radius, 3.2), 48)
            case .edit:
                radius = min(
                    max(radius, HomeIslandBuildCameraTuning.minimumRadius),
                    HomeIslandBuildCameraTuning.maximumRadius
                )
            case .arrival, .departure:
                radius = min(max(radius, 1.4), 420)
            }
            guard let target = cameraTarget else { return }
            let horizontalLimit: Float = switch owner.mode {
            case .camera:
                18
            case .edit:
                HomeIslandBuildCameraTuning.horizontalTargetLimit
            case .arrival, .explore, .departure:
                64
            }
            let minimumHeight: Float = owner.mode == .camera || owner.mode == .edit ? -1 : -12
            let maximumHeight: Float = owner.mode == .camera || owner.mode == .edit ? 18 : 96
            target.position.x = min(max(target.position.x, -horizontalLimit), horizontalLimit)
            target.position.y = min(max(target.position.y, minimumHeight), maximumHeight)
            target.position.z = min(max(target.position.z, -horizontalLimit), horizontalLimit)
        }

        private func nearestEquivalentAzimuth(to target: Float) -> Float {
            let fullTurn = Float.pi * 2
            let turns = round((azimuth - target) / fullTurn)
            return target + turns * fullTurn
        }

        private func animateArrivalCamera(
            target targetPosition: SCNVector3,
            azimuth targetAzimuth: Float,
            elevation targetElevation: Float,
            radius targetRadius: Float,
            fieldOfView: CGFloat,
            duration: TimeInterval,
            timingFunction: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ) {
            guard let camera, let cameraTarget else { return }
            azimuth = targetAzimuth
            elevation = targetElevation
            radius = targetRadius

            let effectiveDuration = UIAccessibility.isReduceMotionEnabled ? 0 : duration
            if effectiveDuration > 0 {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = effectiveDuration
                SCNTransaction.animationTimingFunction = timingFunction
            }

            cameraTarget.position = targetPosition
            camera.camera?.fieldOfView = fieldOfView
            camera.camera?.zNear = Double(max(0.012, targetRadius * 0.002))
            camera.camera?.zFar = Double(max(1_500, targetRadius * 8))
            let horizontal = cos(targetElevation) * targetRadius
            camera.position = SCNVector3(
                targetPosition.x + cos(targetAzimuth) * horizontal,
                targetPosition.y + sin(targetElevation) * targetRadius,
                targetPosition.z + sin(targetAzimuth) * horizontal
            )
            camera.look(
                at: targetPosition,
                up: SCNVector3(0, 1, 0),
                localFront: SCNVector3(0, 0, -1)
            )

            if effectiveDuration > 0 { SCNTransaction.commit() }
            view?.setNeedsDisplay()
        }

        private func startArrivalIfNeeded() {
            guard !arrivalStarted else { return }
            arrivalStarted = true
            renderedMode = .arrival
            storeCachedWalkInput(.zero)

            azimuth = 0.88
            elevation = 0.31
            radius = 26.0
            cameraTarget?.position = SCNVector3(-0.6, 0.85, 6.0)
            updateCamera()

            guard !UIAccessibility.isReduceMotionEnabled, let boat = arrivalBoat else {
                completeArrivalImmediately()
                return
            }

            let openWaterTarget = SCNVector3(
                arrivalBoatStopPosition.x - 0.025,
                arrivalBoatStopPosition.y,
                arrivalBoatStopPosition.z + ArrivalMotion.berthLeadDistance
            )
            let openWaterApproach = SCNAction.move(
                to: openWaterTarget,
                duration: ArrivalMotion.openWaterDuration
            )
            openWaterApproach.timingMode = .easeInEaseOut
            let alignWithJetty = SCNAction.rotateTo(
                x: 0,
                y: .pi / 2,
                z: 0,
                duration: ArrivalMotion.openWaterDuration,
                usesShortestUnitArc: true
            )
            alignWithJetty.timingMode = .easeInEaseOut

            let berth = SCNAction.move(
                to: arrivalBoatStopPosition,
                duration: ArrivalMotion.berthingDuration
            )
            berth.timingMode = .easeOut

            animateArrivalCamera(
                target: SCNVector3(-0.8, 0.88, 8.8),
                azimuth: 0.83,
                elevation: 0.30,
                radius: 22.0,
                fieldOfView: 48,
                duration: ArrivalMotion.openWaterDuration
            )

            boat.runAction(.sequence([
                .group([openWaterApproach, alignWithJetty]),
                .run { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.animateArrivalCamera(
                            target: SCNVector3(-1.0, 0.82, 11.1),
                            azimuth: 0.754,
                            elevation: 0.299,
                            radius: 12.8,
                            fieldOfView: 42,
                            duration: ArrivalMotion.berthingDuration,
                            timingFunction: CAMediaTimingFunction(
                                controlPoints: 0.22, 1.0, 0.36, 1.0
                            )
                        )
                    }
                },
                berth,
                .run { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.arrivalBoatBob?.removeAllActions()
                        let settle = SCNAction.move(
                            to: SCNVector3Zero,
                            duration: ArrivalMotion.mooringSettleDuration
                        )
                        settle.timingMode = .easeOut
                        self.arrivalBoatBob?.runAction(settle)
                    }
                },
                .wait(duration: ArrivalMotion.mooringSettleDuration),
                .run { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.beginLanding()
                    }
                },
            ]))
        }

        /// Installs the same island, saved placements, jetty, boat and navigator
        /// as the standalone experience, but at the stable post-arrival state.
        /// This is intentionally separate from `completeArrivalImmediately()` so
        /// an embedded home does not emit production arrival callbacks. An
        /// explicitly requested DEBUG seat demo is scheduled by `install(in:)`.
        private func prepareMooredHome() {
            guard !arrivalStarted else { return }
            arrivalStarted = true
            arrivalFinished = true
            renderedMode = owner.mode
            boardingRequested = false
            departureStarted = false
            storeCachedWalkInput(.zero)
            arrivalNavigatorIsWalking = false
            cancelSeatInteraction()

            arrivalBoat?.removeAllActions()
            arrivalBoat?.position = arrivalBoatStopPosition
            arrivalBoat?.eulerAngles = SCNVector3(0, Float.pi / 2, 0)
            arrivalBoat?.opacity = 1
            arrivalBoatBob?.removeAllActions()
            arrivalBoatBob?.position = SCNVector3Zero
            arrivalBoatNavigator?.opacity = 0
            arrivalGangplank?.removeFromParentNode()

            prepareNavigatorForEmbeddedBoarding()
            startMooredBoatMotion()
            if owner.locksMooredOverview {
                enterIslandOverviewCamera(animated: 0)
            } else {
                enterExploreCamera(animated: 0)
            }
            view?.setNeedsDisplay()
        }

        /// The embedded home deliberately has no walking controls. Keeping the
        /// navigator at the transfer end of the fixed jetty also lets the existing
        /// external boarding request pass its proximity guard without adding a
        /// second departure implementation.
        private func prepareNavigatorForEmbeddedBoarding() {
            guard let navigator = navigatorNode else { return }
            cancelSeatInteraction()
            let path = arrivalJettyLandingPath()
            let landing = path.landing
            navigator.removeAllActions()
            navigator.position = landing
            navigator.scale = SCNVector3(
                NavigatorAppearance.islandScale,
                NavigatorAppearance.islandScale,
                NavigatorAppearance.islandScale
            )
            navigator.opacity = 1
            let islandDirection = path.deck - landing
            navigator.eulerAngles.y = atan2(islandDirection.x, islandDirection.z)
            navigatorAnimator.pose = .idle
            arrivalNavigatorIsWalking = false
            storeCachedWalkInput(.zero)
        }

        private func beginLanding() {
            guard !arrivalFinished, let navigator = navigatorNode else { return }
            let path = arrivalJettyLandingPath()
            let landing = path.landing
            let islandDirection = path.deck - landing

            navigator.removeAllActions()
            navigator.position = landing
            navigator.eulerAngles.y = atan2(islandDirection.x, islandDirection.z)
            navigator.scale = SCNVector3(
                NavigatorAppearance.islandScale,
                NavigatorAppearance.islandScale,
                NavigatorAppearance.islandScale
            )
            navigator.opacity = 0
            navigatorAnimator.pose = .idle
            arrivalNavigatorIsWalking = false
            arrivalBoatNavigator?.runAction(.fadeOut(duration: 0.16))

            animateArrivalCamera(
                target: SCNVector3(
                    landing.x,
                    landing.y + 0.72,
                    landing.z
                ),
                azimuth: 0.77,
                elevation: 0.28,
                radius: 11.8,
                fieldOfView: 42,
                duration: ArrivalMotion.jettySettleDuration
            )

            navigator.runAction(.sequence([
                .wait(duration: 0.08),
                .fadeIn(duration: 0.20),
                .run { [weak self] _ in
                    guard let self else { return }
                    DispatchQueue.main.async {
                        self.animateArrivalCamera(
                            target: SCNVector3(
                                landing.x,
                                landing.y + 0.72,
                                landing.z
                            ),
                            azimuth: self.nearestEquivalentAzimuth(to: 0.82),
                            elevation: 0.30,
                            radius: 6.8,
                            fieldOfView: 48,
                            duration: ArrivalMotion.jettySettleDuration
                        )
                    }
                },
                .wait(duration: 0.24),
                .run { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.finishArrival()
                    }
                },
            ]))
        }

        private func arrivalJettyLandingPath() -> (
            transfer: SCNVector3,
            landing: SCNVector3,
            deck: SCNVector3
        ) {
            let fallbackCoast = HomeIslandMetrics.arrivalJettyPosition
            let surface = arrivalJettyWalkSurface
            let transferXZ = surface?.worldPosition(
                localX: HomeIslandMetrics.arrivalJettyTransferLocalX,
                localZ: HomeIslandMetrics.arrivalJettyTransferLocalZ
            ) ?? (x: fallbackCoast.x - 1.94, z: fallbackCoast.z + 3.00)
            let landingXZ = surface?.worldPosition(
                localX: HomeIslandMetrics.arrivalJettyLandingLocalX,
                localZ: HomeIslandMetrics.arrivalJettyTransferLocalZ
            ) ?? (x: fallbackCoast.x - 0.25, z: fallbackCoast.z + 3.00)
            let deckXZ = surface?.worldPosition(
                localX: 0,
                localZ: HomeIslandMetrics.arrivalJettyIslandLocalZ
            ) ?? (x: fallbackCoast.x, z: fallbackCoast.z - 1.08)
            return (
                SCNVector3(
                    transferXZ.x,
                    groundHeight(x: transferXZ.x, z: transferXZ.z),
                    transferXZ.z
                ),
                SCNVector3(
                    landingXZ.x,
                    groundHeight(x: landingXZ.x, z: landingXZ.z),
                    landingXZ.z
                ),
                SCNVector3(
                    deckXZ.x,
                    groundHeight(x: deckXZ.x, z: deckXZ.z),
                    deckXZ.z
                )
            )
        }

        private func makeArrivalGangplank(from start: SCNVector3, to end: SCNVector3) -> SCNNode {
            let direction = end - start
            let length = max(sqrt(
                direction.x * direction.x
                    + direction.y * direction.y
                    + direction.z * direction.z
            ), 0.1)
            let geometry = SCNBox(
                width: 0.28,
                height: 0.045,
                length: CGFloat(length),
                chamferRadius: 0.012
            )
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = UIColor(rgb: 0x796249)
            material.roughness.contents = 0.92
            geometry.materials = [material]

            let node = SCNNode(geometry: geometry)
            node.name = "home-island-arrival-gangplank"
            node.position = SCNVector3(
                (start.x + end.x) * 0.5,
                (start.y + end.y) * 0.5 - 0.025,
                (start.z + end.z) * 0.5
            )
            node.look(
                at: SCNVector3(end.x, end.y - 0.025, end.z),
                up: SCNVector3(0, 1, 0),
                localFront: SCNVector3(0, 0, 1)
            )
            node.opacity = 0
            view?.scene?.rootNode.addChildNode(node)
            return node
        }

        private func finishArrival() {
            guard !arrivalFinished else { return }
            arrivalFinished = true
            arrivalNavigatorIsWalking = false
            navigatorNode?.opacity = 1
            arrivalBoatNavigator?.opacity = 0
            startMooredBoatMotion()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.owner.onArrivalCompleted()
                self.scheduleDepartureDemoIfRequested()
                self.scheduleSeatDemoIfRequested()
            }
        }

        private func completeArrivalImmediately() {
            let destination = arrivalJettyWalkSurface == nil
                ? safestLandingPosition()
                : arrivalJettyLandingPath().landing
            navigatorNode?.position = destination
            let path = arrivalJettyLandingPath()
            let islandDirection = path.deck - path.landing
            navigatorNode?.eulerAngles.y = atan2(islandDirection.x, islandDirection.z)
            navigatorNode?.scale = SCNVector3(
                NavigatorAppearance.islandScale,
                NavigatorAppearance.islandScale,
                NavigatorAppearance.islandScale
            )
            navigatorNode?.opacity = 1
            arrivalBoat?.removeAllActions()
            arrivalBoat?.position = arrivalBoatStopPosition
            arrivalBoat?.eulerAngles.y = .pi / 2
            arrivalBoat?.opacity = 1
            arrivalBoatBob?.removeAllActions()
            arrivalBoatBob?.position = SCNVector3Zero
            arrivalBoatNavigator?.opacity = 0
            arrivalGangplank?.removeFromParentNode()
            arrivalFinished = true
            arrivalNavigatorIsWalking = false
            enterExploreCamera(focusing: destination, animated: 0)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.owner.onArrivalCompleted()
                self.scheduleDepartureDemoIfRequested()
                self.scheduleSeatDemoIfRequested()
            }
        }

        private func scheduleSeatDemoIfRequested() {
            #if DEBUG
            guard let requestedSeat = ProcessInfo.processInfo.environment["LANDFALL_SEAT_DEMO"]
            else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, let navigator = self.navigatorNode else { return }
                guard self.owner.mode == .explore else { return }
                guard self.arrivalFinished else { return }
                guard !self.seatDemoDidBegin else { return }
                let requestedSlot = requestedSeat == "stump"
                    ? self.placedSeatSlots.first(where: { $0.slotID == "stump" })
                    : self.placedSeatSlots.first
                guard let requestedSlot else { return }
                self.seatDemoDidBegin = true
                let approach = requestedSlot.approachWorldPosition
                navigator.position = SCNVector3(
                    approach.x,
                    approach.y,
                    approach.z
                )
                let target = requestedSlot.contactWorldPosition(
                    rootToSeatSurface: self.navigatorRootToSeatSurface
                )
                let dx = target.x - navigator.position.x
                let dz = target.z - navigator.position.z
                let length = sqrt(dx * dx + dz * dz)
                guard length > 0.001 else { return }
                let direction = SCNVector3(dx / length, 0, dz / length)
                if let seat = self.interactiveSeatToward(
                    navigator.position,
                    direction: direction
                ) {
                    self.beginSitting(on: seat)
                    if let exitMode = ProcessInfo.processInfo.environment[
                        "LANDFALL_SEAT_DEMO_EXIT"
                    ] {
                        // `sideways` deliberately requests a direction that does
                        // not match the bench's fixed safe approach point. This is
                        // the regression case that previously left the navigator
                        // facing away from the path it actually travelled.
                        let exitDirection = exitMode == "sideways"
                            ? SCNVector3(
                                -seat.facingDirection.z,
                                0,
                                seat.facingDirection.x
                            )
                            : seat.facingDirection
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                            self?.beginLeavingSeat(toward: exitDirection)
                        }
                    }
                }
            }
            #endif
        }

        private func scheduleDepartureDemoIfRequested() {
            #if DEBUG
            guard ProcessInfo.processInfo.environment["LANDFALL_HOME_DEPARTURE"] == "1"
            else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                guard let self, let navigator = self.navigatorNode else { return }
                let transfer = self.arrivalJettyLandingPath().transfer
                let direction = transfer - navigator.position
                let yaw = atan2(direction.x, direction.z)
                let distance = sqrt(
                    direction.x * direction.x
                        + direction.y * direction.y
                        + direction.z * direction.z
                )
                let duration = max(TimeInterval(distance / 1.75), 0.35)
                let faceBoat = SCNAction.rotateTo(
                    x: 0,
                    y: CGFloat(yaw),
                    z: 0,
                    duration: min(duration, 0.28),
                    usesShortestUnitArc: true
                )
                faceBoat.timingMode = .easeOut
                let walkToBoat = SCNAction.move(to: transfer, duration: duration)
                walkToBoat.timingMode = .easeInEaseOut
                self.arrivalNavigatorIsWalking = true
                navigator.runAction(.group([faceBoat, walkToBoat])) { [weak self] in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.arrivalNavigatorIsWalking = false
                        self.attemptBoatBoarding()
                    }
                }
            }
            #endif
        }

        private func startMooredBoatMotion() {
            guard !UIAccessibility.isReduceMotionEnabled,
                  let bob = arrivalBoatBob
            else { return }
            bob.removeAllActions()
            bob.position = SCNVector3Zero
            let rise = SCNAction.moveBy(x: 0, y: 0.016, z: 0, duration: 1.80)
            rise.timingMode = .easeInEaseOut
            bob.runAction(.repeatForever(.sequence([rise, rise.reversed()])))
        }

        private func startDeparture() {
            guard !departureStarted else { return }
            departureStarted = true
            storeCachedWalkInput(.zero)
            cancelSeatInteraction()
            guard arrivalFinished,
                  let boat = arrivalBoat,
                  let navigator = navigatorNode,
                  let boatNavigator = arrivalBoatNavigator
            else {
                finishDeparture()
                return
            }

            boat.removeAllActions()
            arrivalBoatBob?.removeAllActions()
            arrivalBoatBob?.position = SCNVector3Zero
            navigator.removeAllActions()
            arrivalNavigatorIsWalking = true

            if UIAccessibility.isReduceMotionEnabled {
                navigator.opacity = 0
                boatNavigator.opacity = 1
                arrivalNavigatorIsWalking = false
                navigatorAnimator.pose = .idle
                finishDeparture()
                return
            }

            let path = arrivalJettyLandingPath()
            let boatAnchor = boatNavigator.presentation.worldPosition
            let gangplank = makeArrivalGangplank(from: path.transfer, to: boatAnchor)
            arrivalGangplank = gangplank
            gangplank.runAction(.fadeIn(duration: 0.18))

            let approachDirection = path.transfer - navigator.position
            let approachYaw = atan2(approachDirection.x, approachDirection.z)
            let approachDistance = sqrt(
                approachDirection.x * approachDirection.x
                    + approachDirection.y * approachDirection.y
                    + approachDirection.z * approachDirection.z
            )
            let approachDuration = min(
                max(
                    TimeInterval(approachDistance / DepartureMotion.approachSpeed),
                    DepartureMotion.approachDurationRange.lowerBound
                ),
                DepartureMotion.approachDurationRange.upperBound
            )
            let approach = SCNAction.move(
                to: path.transfer,
                duration: approachDuration
            )
            approach.timingMode = .easeInEaseOut
            let faceGangplank = SCNAction.rotateTo(
                x: 0,
                y: CGFloat(approachYaw),
                z: 0,
                duration: 0.24,
                usesShortestUnitArc: true
            )
            faceGangplank.timingMode = .easeOut

            let boardDirection = boatAnchor - path.transfer
            let boardYaw = atan2(boardDirection.x, boardDirection.z)
            let transferDistance = sqrt(
                boardDirection.x * boardDirection.x
                    + boardDirection.y * boardDirection.y
                    + boardDirection.z * boardDirection.z
            )
            let transferDuration = min(
                max(
                    TimeInterval(transferDistance / DepartureMotion.transferSpeed),
                    DepartureMotion.transferDurationRange.lowerBound
                ),
                DepartureMotion.transferDurationRange.upperBound
            )
            let board = SCNAction.move(
                to: boatAnchor,
                duration: transferDuration
            )
            board.timingMode = .easeInEaseOut
            let turnAboard = SCNAction.rotateTo(
                x: 0,
                y: CGFloat(boardYaw),
                z: 0,
                duration: transferDuration,
                usesShortestUnitArc: true
            )
            turnAboard.timingMode = .easeInEaseOut
            let matchDeckScale = SCNAction.scale(
                to: 0.57,
                duration: transferDuration
            )
            matchDeckScale.timingMode = .easeInEaseOut

            boatNavigator.opacity = 0
            boatNavigator.runAction(.sequence([
                .wait(duration: approachDuration + transferDuration),
                .fadeIn(duration: 0.14),
            ]))

            animateArrivalCamera(
                target: SCNVector3(-0.08, 0.96, 8.85),
                azimuth: 0.77,
                elevation: 0.28,
                radius: 11.4,
                fieldOfView: 42,
                duration: approachDuration + transferDuration
            )

            navigator.runAction(.sequence([
                .group([approach, faceGangplank]),
                .group([board, turnAboard, matchDeckScale]),
                .fadeOut(duration: 0.14),
                .run { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.beginCastOff()
                    }
                },
            ]))
        }

        private func beginCastOff() {
            guard let boat = arrivalBoat else {
                finishDeparture()
                return
            }
            arrivalNavigatorIsWalking = false
            arrivalGangplank?.runAction(.sequence([
                .fadeOut(duration: DepartureMotion.gangplankRetractDuration),
                .removeFromParentNode(),
            ]))

            // One continuous curve avoids the visible brake/acceleration jumps
            // caused by chaining multiple move actions. The boat first reverses
            // straight clear of the piles, then turns its bow away from the dock.
            let startPosition = boat.position
            let voyage = SCNAction.customAction(
                duration: DepartureMotion.voyageDuration
            ) { node, elapsedTime in
                let rawProgress = Float(
                    elapsedTime / CGFloat(DepartureMotion.voyageDuration)
                )
                let t = min(max(rawProgress, 0), 1)
                let travelProgress = t * t * (2 - t)
                let turnProgress = min(max((t - 0.30) / 0.38, 0), 1)
                let easedTurn = turnProgress * turnProgress * (3 - 2 * turnProgress)
                node.position = SCNVector3(
                    startPosition.x - DepartureMotion.outwardDrift * easedTurn,
                    startPosition.y + sin(t * .pi * 5) * 0.012,
                    startPosition.z + DepartureMotion.voyageDistance * travelProgress
                )
                // Increasing through 3π/2 fixes the 180° turn direction: the
                // bow swings out to open water instead of choosing arbitrarily.
                node.eulerAngles.y = .pi / 2 + .pi * easedTurn
            }

            let voyageDuration = DepartureMotion.gangplankRetractDuration
                + DepartureMotion.voyageDuration
            animateArrivalCamera(
                // Keep the pier and the departing boat in the same composition.
                // A target near the island centre lets the boat leave frame too
                // early, leaving several seconds of empty ocean before dismiss.
                target: SCNVector3(-0.75, 0.88, 13.00),
                azimuth: 0.83,
                elevation: 0.30,
                radius: 24.5,
                fieldOfView: 48,
                duration: voyageDuration,
                timingFunction: CAMediaTimingFunction(
                    controlPoints: 0.22, 0.74, 0.32, 1.0
                )
            )

            boat.runAction(.sequence([
                .wait(duration: DepartureMotion.gangplankRetractDuration),
                voyage,
                .run { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.finishDeparture()
                    }
                },
            ]))
        }

        private func finishDeparture() {
            arrivalGangplank?.removeFromParentNode()
            guard departureStarted else { return }
            departureStarted = false
            // This coordinator can survive while the timer voyage replaces
            // the island branch. Never carry the boarding latch into the
            // moored Explore scene when the player returns home.
            boardingRequested = false
            touchWalkInput = .zero
            keyboardWalkInput = .zero
            gamepadWalkInput = .zero
            clearPendingTouchJump()
            storeCachedWalkInput(.zero)
            DispatchQueue.main.async { [weak self] in
                self?.owner.onDepartureCompleted()
            }
        }

        private func modeDidChange(from previousMode: HomeIslandMode, to mode: HomeIslandMode) {
            switch mode {
            case .arrival:
                touchWalkInput = .zero
                keyboardWalkInput = .zero
                gamepadWalkInput = .zero
                clearPendingTouchJump()
                storeCachedWalkInput(.zero)
                resetLocomotionState()
                break
            case .explore:
                if previousMode == .departure {
                    // A reused representable must recover just as cleanly as a
                    // newly-created Home Island scene after a timer voyage.
                    boardingRequested = false
                    departureStarted = false
                    arrivalNavigatorIsWalking = false
                    touchWalkInput = .zero
                    keyboardWalkInput = .zero
                    gamepadWalkInput = .zero
                    clearPendingTouchJump()
                    storeCachedWalkInput(.zero)
                }
                if !seatInteractionState.keepsNavigatorOnSeat {
                    ensureNavigatorIsWalkable()
                }
                navigatorNode?.opacity = 1
                resetLocomotionState()
                if previousMode == .edit || previousMode == .camera {
                    if owner.startsMooredAtIsland, owner.locksMooredOverview {
                        prepareNavigatorForEmbeddedBoarding()
                        enterIslandOverviewCamera(animated: 0.42)
                    } else {
                        enterExploreCamera(animated: 0.42)
                    }
                }
            case .edit:
                touchWalkInput = .zero
                keyboardWalkInput = .zero
                gamepadWalkInput = .zero
                clearPendingTouchJump()
                storeCachedWalkInput(.zero)
                resetLocomotionState()
                cancelSeatInteraction()
                if !seatInteractionState.keepsNavigatorOnSeat {
                    ensureNavigatorIsWalkable()
                }
                navigatorAnimator.pose = .idle
                navigatorNode?.opacity = 1
                enterBuildCamera(animated: 0.42)
            case .camera:
                touchWalkInput = .zero
                keyboardWalkInput = .zero
                gamepadWalkInput = .zero
                clearPendingTouchJump()
                storeCachedWalkInput(.zero)
                resetLocomotionState()
                navigatorAnimator.pose = .idle
                navigatorNode?.opacity = 1
                if previousMode == .edit {
                    resetCamera(animated: true)
                } else {
                    // 写真モードへ入る直前の探索構図をそのまま引き継ぐ。
                    updateCamera(animated: 0)
                }
            case .departure:
                touchWalkInput = .zero
                keyboardWalkInput = .zero
                gamepadWalkInput = .zero
                clearPendingTouchJump()
                storeCachedWalkInput(.zero)
                resetLocomotionState()
                startDeparture()
            }
        }

        private func resetLocomotionState() {
            if let navigator = navigatorNode {
                if owner.mode != .arrival,
                   !seatInteractionState.keepsNavigatorOnSeat {
                    navigator.position.y = groundSample(
                        x: navigator.position.x,
                        z: navigator.position.z
                    ).height
                }
                locomotionMotor.reset(
                    position: SIMD3<Float>(
                        navigator.position.x,
                        navigator.position.y,
                        navigator.position.z
                    ),
                    yaw: navigator.eulerAngles.y
                )
                if !seatInteractionState.keepsNavigatorOnSeat {
                    navigator.eulerAngles.x = 0
                    navigator.eulerAngles.z = 0
                }
            }
            locomotionFrame = nil
            locomotionCameraController.reset()
            cameraMotion = HomeIslandCameraMotion()
            navigatorAnimator.locomotionState = nil
            updateLocomotionWind(0)
            if owner.mode == .explore, !owner.cameraShowcaseActive {
                camera?.camera?.fieldOfView = 48
            }
        }

        private func enterExploreCamera(animated duration: TimeInterval) {
            guard let navigator = navigatorNode else { return }
            enterExploreCamera(focusing: navigator.position, animated: duration)
        }

        private func enterBuildCamera(animated duration: TimeInterval) {
            guard let navigator = navigatorNode else { return }
            elevation = HomeIslandBuildCameraTuning.elevation
            radius = HomeIslandBuildCameraTuning.radius
            cameraTarget?.position = SCNVector3(
                navigator.position.x,
                navigator.position.y + HomeIslandBuildCameraTuning.targetHeight,
                navigator.position.z
            )
            camera?.camera?.fieldOfView = HomeIslandBuildCameraTuning.fieldOfView
            updateCamera(animated: duration)
        }

        private func enterIslandOverviewCamera(animated duration: TimeInterval) {
            azimuth = nearestEquivalentAzimuth(to: 0.72)
            elevation = 0.42
            radius = 30.8
            cameraTarget?.position = SCNVector3(0, 0.34, 0)
            camera?.camera?.fieldOfView = 48
            updateCamera(animated: duration)
        }

        private func enterExploreCamera(
            focusing point: SCNVector3,
            animated duration: TimeInterval
        ) {
            azimuth = nearestEquivalentAzimuth(to: 0.82)
            elevation = 0.30
            radius = 6.8
            cameraTarget?.position = SCNVector3(point.x, point.y + 0.72, point.z)
            updateCamera(animated: duration)
        }

        private func safestLandingPosition() -> SCNVector3 {
            #if DEBUG
            if ProcessInfo.processInfo.environment["LANDFALL_EDGE_DEMO"] != nil {
                let edgeAngles = stride(from: Float(0), to: Float.pi * 2, by: Float.pi / 12)
                for angle in edgeAngles {
                    let edge = HomeIslandMetrics.sandEdgePoint(angle: angle)
                    let length = sqrt(edge.x * edge.x + edge.z * edge.z)
                    let inset = max(0, length - 0.18) / max(length, 0.001)
                    let x = edge.x * inset
                    let z = edge.z * inset
                    if isWalkable(x: x, z: z) {
                        return SCNVector3(x, groundHeight(x: x, z: z), z)
                    }
                }
            }
            #endif
            let candidates: [(Float, Float)] = [
                (0, 5.62), (-1.25, 5.48), (1.25, 5.48),
                (-2.45, 5.05), (2.45, 5.05), (0, 4.42),
                (-1.35, 4.18), (1.35, 4.18), (-2.75, 3.85),
                (2.75, 3.85), (0, 3.15), (-1.7, 3.0), (1.7, 3.0),
                (0, 1.8), (-2.8, 2.1), (2.8, 2.1), (0, 0),
            ]
            if let candidate = candidates.first(where: { isWalkable(x: $0.0, z: $0.1) }) {
                return SCNVector3(
                    candidate.0,
                    groundHeight(x: candidate.0, z: candidate.1),
                    candidate.1
                )
            }
            return SCNVector3(0, groundHeight(x: 0, z: 0), 0)
        }

        private func ensureNavigatorIsWalkable() {
            guard let navigator = navigatorNode else { return }
            recoverNavigatorFromInvalidPositionIfNeeded(navigator)
        }

        /// Placement migrations and authored collision changes must never leave
        /// the navigator inside an invalid capsule where every movement candidate
        /// is rejected. Prefer a tiny local correction; only fall back to the
        /// island landing point when no nearby escape exists.
        @discardableResult
        private func recoverNavigatorFromInvalidPositionIfNeeded(_ navigator: SCNNode) -> Bool {
            let origin = navigator.position
            guard !isWalkable(x: origin.x, z: origin.z) else { return false }

            let directionCount = 24
            let radii: [Float] = [0.05, 0.10, 0.16, 0.24, 0.34, 0.48, 0.68]
            for radius in radii {
                for index in 0..<directionCount {
                    let angle = Float(index) / Float(directionCount) * 2 * .pi
                    let x = origin.x + cos(angle) * radius
                    let z = origin.z + sin(angle) * radius
                    guard isWalkable(x: x, z: z) else { continue }
                    navigator.position = SCNVector3(x, groundHeight(x: x, z: z), z)
                    locomotionMotor.reset(
                        position: SIMD3<Float>(x, navigator.position.y, z),
                        yaw: navigator.eulerAngles.y
                    )
                    return true
                }
            }

            navigator.position = safestLandingPosition()
            locomotionMotor.reset(
                position: SIMD3<Float>(
                    navigator.position.x,
                    navigator.position.y,
                    navigator.position.z
                ),
                yaw: navigator.eulerAngles.y
            )
            return true
        }

        private func isWalkable(x: Float, z: Float) -> Bool {
            let playerRadius = NavigatorCollision.radius
            let isOnSand = HomeIslandMetrics.containsWalkableSand(
                x: x,
                z: z,
                margin: 0.18
            )
            let isOnJetty = jettyWalkSurfaces.contains {
                $0.contains(x: x, z: z, playerRadius: playerRadius)
            }
            let isOnLookout = lookoutWalkSurfaces.contains {
                $0.contains(x: x, z: z, playerRadius: playerRadius)
            }
            guard isOnSand || isOnJetty || isOnLookout else { return false }
            guard jettyWalkSurfaces.allSatisfy({
                !$0.blocksRail(x: x, z: z, playerRadius: playerRadius)
            }) else { return false }
            // The deck is reachable only through the stair mouth: everywhere
            // else its rail line and the drop below it are solid.
            guard lookoutWalkSurfaces.allSatisfy({
                !$0.blocksRail(x: x, z: z, playerRadius: playerRadius)
            }) else { return false }
            guard walkingObstacles.allSatisfy({ obstacle in
                let dx = x - obstacle.x
                let dz = z - obstacle.z
                let minimumDistance = playerRadius + obstacle.radius
                return dx * dx + dz * dz >= minimumDistance * minimumDistance
            }) else { return false }
            return ruinsWalkObstacles.allSatisfy {
                !$0.blocks(x: x, z: z, playerRadius: playerRadius)
            }
        }

        private func reportNavigatorJettyPresenceIfNeeded() {
            let isOnJetty: Bool
            if let navigator = navigatorNode,
               let arrivalJettyWalkSurface {
                isOnJetty = arrivalJettyWalkSurface.contains(
                    x: navigator.position.x,
                    z: navigator.position.z,
                    playerRadius: 0.02
                )
            } else {
                isOnJetty = false
            }
            guard renderedNavigatorOnArrivalJetty != isOnJetty else { return }
            renderedNavigatorOnArrivalJetty = isOnJetty
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.reportedNavigatorOnArrivalJetty != isOnJetty
                else { return }
                self.reportedNavigatorOnArrivalJetty = isOnJetty
                self.owner.onJettyPresenceChanged(isOnJetty)
            }
        }

        /// Roughly an arm's length past the board's own footprint, so the hint
        /// appears while walking up to it rather than only when touching it.
        private static let noticeBoardProximityRadius: Float = 2.35

        private func reportNoticeBoardProximityIfNeeded() {
            let isNear: Bool
            if let navigator = navigatorNode, fixedNoticeBoardNode?.parent != nil {
                let dx = navigator.position.x - HomeIslandMetrics.fixedNoticeBoardPosition.x
                let dz = navigator.position.z - HomeIslandMetrics.fixedNoticeBoardPosition.z
                let radius = Self.noticeBoardProximityRadius
                isNear = dx * dx + dz * dz <= radius * radius
            } else {
                isNear = false
            }
            guard renderedNavigatorNearNoticeBoard != isNear else { return }
            renderedNavigatorNearNoticeBoard = isNear
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.reportedNavigatorNearNoticeBoard != isNear
                else { return }
                self.reportedNavigatorNearNoticeBoard = isNear
                self.owner.onNoticeBoardProximityChanged(isNear)
            }
        }

        private func updateWalking(deltaTime: Float) -> Bool {
            lastLocomotionDeltaTime = min(max(deltaTime, 0), 0.05)
            guard !(owner.startsMooredAtIsland && owner.locksMooredOverview),
                  owner.mode == .explore,
                  !owner.cameraInteractionLocked,
                  !owner.cameraShowcaseActive,
                  !boardingRequested,
                  let navigator = navigatorNode,
                  deltaTime > 0
            else {
                if let navigator = navigatorNode {
                    if owner.mode == .explore,
                       locomotionFrame?.isGrounded == false,
                       !seatInteractionState.keepsNavigatorOnSeat {
                        navigator.position.y = groundSample(
                            x: navigator.position.x,
                            z: navigator.position.z
                        ).height
                    }
                    locomotionMotor.reset(
                        position: SIMD3<Float>(
                            navigator.position.x,
                            navigator.position.y,
                            navigator.position.z
                        ),
                        yaw: navigator.eulerAngles.y
                    )
                }
                locomotionFrame = nil
                navigatorAnimator.locomotionState = nil
                cameraMotion = locomotionCameraController.update(
                    frame: .idle(position: .zero, yaw: 0),
                    deltaTime: deltaTime,
                    reduceMotion: UIAccessibility.isReduceMotionEnabled
                )
                updateLocomotionWind(0)
                return false
            }

            // Never while sitting. A seat is by definition inside its own prop's
            // collider, so this rescue fired every frame of the sit animation
            // and dragged the navigator back down to walkable ground — the sit
            // played out but ended on the sand beside the bench.
            if !seatInteractionState.keepsNavigatorOnSeat {
                recoverNavigatorFromInvalidPositionIfNeeded(navigator)
            }

            let currentWalkInput = currentCachedWalkInput()
            let magnitude = currentWalkInput.magnitude
            switch seatInteractionState {
            case .seated:
                guard magnitude > 0.12 else {
                    settleLocomotion(at: navigator)
                    followNavigatorCamera()
                    return false
                }
                let direction = normalizedWalkDirection(
                    lateral: currentWalkInput.x,
                    forward: currentWalkInput.forward
                )
                beginLeavingSeat(toward: direction)
                followNavigatorCamera()
                return false
            case .approaching, .settling, .standingUp, .leaving:
                settleLocomotion(at: navigator)
                followNavigatorCamera()
                return false
            case .free:
                break
            }

            let inputDirection = normalizedWalkDirection(
                lateral: currentWalkInput.x,
                forward: currentWalkInput.forward
            )
            if magnitude > 0.035,
               CACurrentMediaTime() >= contactReentryBlockedUntil,
               let seat = interactiveSeatToward(
                   navigator.position,
                    direction: inputDirection
               ) {
                beginSitting(on: seat)
                followNavigatorCamera()
                return true
            }

            if snapFacingOnNextMovement, magnitude > 0.035 {
                let direction = normalizedWalkDirection(
                    lateral: currentWalkInput.x,
                    forward: currentWalkInput.forward
                )
                let yaw = atan2(direction.x, direction.z)
                navigator.eulerAngles.y = yaw
                locomotionMotor.reset(
                    position: SIMD3<Float>(
                        navigator.position.x,
                        navigator.position.y,
                        navigator.position.z
                    ),
                    yaw: yaw
                )
                snapFacingOnNextMovement = false
            }

            let frame = locomotionMotor.update(
                input: currentWalkInput,
                position: SIMD3<Float>(
                    navigator.position.x,
                    navigator.position.y,
                    navigator.position.z
                ),
                currentYaw: navigator.eulerAngles.y,
                cameraForward: SIMD2<Float>(-cos(azimuth), -sin(azimuth)),
                cameraRight: SIMD2<Float>(sin(azimuth), -cos(azimuth)),
                deltaTime: deltaTime,
                sampleGround: { [weak self] x, z in
                    self?.groundSample(x: x, z: z)
                        ?? HomeIslandGroundSample(height: HomeIslandMetrics.surfaceY)
                },
                canOccupy: { [weak self] x, z in
                    self?.isWalkable(x: x, z: z) ?? false
                }
            )
            locomotionFrame = frame
            navigator.position = SCNVector3(
                frame.position.x,
                frame.position.y,
                frame.position.z
            )
            applyLocomotionOrientation(frame, to: navigator, deltaTime: deltaTime)
            navigatorAnimator.locomotionState = makePhoenixLocomotionState(
                frame: frame,
                navigator: navigator
            )
            cameraMotion = locomotionCameraController.update(
                frame: frame,
                deltaTime: deltaTime,
                reduceMotion: UIAccessibility.isReduceMotionEnabled
            )
            if frame.didStep {
                addFootprintIfNeeded(frame: frame)
                locomotionAudio.playFootstep(
                    surface: frame.ground.surface,
                    intensity: 0.30 + frame.normalizedSpeed * 0.70
                )
            }
            if frame.didLand, frame.landingImpact > 0.08 {
                DispatchQueue.main.async {
                    Haptics.tap(frame.landingImpact > 0.55 ? .medium : .light)
                }
            }
            if frame.didJump {
                DispatchQueue.main.async {
                    Haptics.tap(.light)
                }
            }
            let windProgress = min(max((frame.normalizedSpeed - 0.56) / 0.44, 0), 1)
            updateLocomotionWind(windProgress * windProgress * (3 - 2 * windProgress))
            followNavigatorCamera()
            return frame.planarSpeed > 0.045
        }

        private func settleLocomotion(at navigator: SCNNode) {
            let position = SIMD3<Float>(
                navigator.position.x,
                navigator.position.y,
                navigator.position.z
            )
            locomotionMotor.reset(position: position, yaw: navigator.eulerAngles.y)
            locomotionFrame = nil
            navigatorAnimator.locomotionState = nil
            cameraMotion = locomotionCameraController.update(
                frame: .idle(position: position, yaw: navigator.eulerAngles.y),
                deltaTime: lastLocomotionDeltaTime,
                reduceMotion: UIAccessibility.isReduceMotionEnabled
            )
            updateLocomotionWind(0)
        }

        private func applyLocomotionOrientation(
            _ frame: HomeIslandLocomotionFrame,
            to navigator: SCNNode,
            deltaTime: Float
        ) {
            navigator.eulerAngles.y = frame.facingYaw
            let normal = frame.ground.normal
            let forward = SIMD2<Float>(sin(frame.facingYaw), cos(frame.facingYaw))
            let right = SIMD2<Float>(cos(frame.facingYaw), -sin(frame.facingYaw))
            let gradient = normal.y > 0.001
                ? SIMD2<Float>(-normal.x / normal.y, -normal.z / normal.y)
                : .zero
            // Timber decks and stairs support the feet independently; tilting
            // the model root makes a humanoid lean unnaturally across a tread.
            // Keep the body upright on wood while retaining terrain alignment
            // on genuinely sloped sand and stone.
            let alignsBodyToSurface = frame.isGrounded && frame.ground.surface != .wood
            let slopePitch = alignsBodyToSurface
                ? -atan(simd_dot(gradient, forward))
                : 0
            let slopeRoll = alignsBodyToSurface
                ? atan(simd_dot(gradient, right))
                : 0
            let targetPitch = min(max(slopePitch, -0.18), 0.18)
            let targetRoll = min(max(slopeRoll, -0.18), 0.18)
            let response = 1 - exp(-10 * min(max(deltaTime, 0), 0.05))
            navigator.eulerAngles.x += (targetPitch - navigator.eulerAngles.x) * response
            navigator.eulerAngles.z += (targetRoll - navigator.eulerAngles.z) * response
        }

        private func makePhoenixLocomotionState(
            frame: HomeIslandLocomotionFrame,
            navigator: SCNNode
        ) -> PhoenixLocomotionAnimationState {
            let scale = max(navigator.scale.x, 0.05)
            let forward = SIMD2<Float>(sin(frame.facingYaw), cos(frame.facingYaw))
            let right = SIMD2<Float>(cos(frame.facingYaw), -sin(frame.facingYaw))
            let stride = 0.10 + frame.normalizedSpeed * 0.20
            let swing = sin(frame.gaitPhase) * stride
            let root = SIMD2<Float>(frame.position.x, frame.position.z)
            let leftPoint = root - right * (0.088 * scale) - forward * swing
            let rightPoint = root + right * (0.088 * scale) + forward * swing
            let leftHeight = groundSample(x: leftPoint.x, z: leftPoint.y).height
            let rightHeight = groundSample(x: rightPoint.x, z: rightPoint.y).height
            let leftOffset = min(max((leftHeight - frame.ground.height) / scale, -0.10), 0.10)
            let rightOffset = min(max((rightHeight - frame.ground.height) / scale, -0.10), 0.10)
            return PhoenixLocomotionAnimationState(
                normalizedSpeed: frame.normalizedSpeed,
                gaitPhase: frame.gaitPhase,
                turnIntensity: frame.turnIntensity,
                verticalVelocity: frame.velocity.y,
                isGrounded: frame.isGrounded,
                landingImpact: frame.landingImpact,
                fatigue: frame.fatigue,
                slopePitch: navigator.eulerAngles.x,
                slopeRoll: navigator.eulerAngles.z,
                leftFootGroundOffset: leftOffset,
                rightFootGroundOffset: rightOffset,
                deckBalance: frame.ground.surface == .boat ? 1 : 0,
                groundingOffset: frame.stepOffset / scale
            )
        }

        private func updateLocomotionWind(_ intensity: Float) {
            guard abs(intensity - lastWindIntensity) > 0.025
                    || intensity == 0 && lastWindIntensity != 0
            else { return }
            lastWindIntensity = intensity
            locomotionAudio.setWindIntensity(intensity)
        }

        private func normalizedWalkDirection(lateral: Float, forward: Float) -> SCNVector3 {
            let cameraForward = SCNVector3(-cos(azimuth), 0, -sin(azimuth))
            let cameraRight = SCNVector3(sin(azimuth), 0, -cos(azimuth))
            var direction = cameraForward * forward + cameraRight * lateral
            let length = sqrt(direction.x * direction.x + direction.z * direction.z)
            guard length > 0.001 else { return SCNVector3(0, 0, 1) }
            direction.x /= length
            direction.z /= length
            return direction
        }

        private func interactiveSeatToward(
            _ position: SCNVector3,
            direction: SCNVector3
        ) -> InteractiveSeat? {
            let occupiedSeats = remotelyOccupiedSeatAddresses
            let candidates = placedSeatSlots.compactMap { slot -> (InteractiveSeat, Float)? in
                guard !occupiedSeats.contains(slot.address) else { return nil }
                let seatPosition = slot.contactWorldPosition(
                    rootToSeatSurface: navigatorRootToSeatSurface
                )
                let approachPosition = slot.approachWorldPosition
                let approachDX = approachPosition.x - position.x
                let approachDZ = approachPosition.z - position.z
                let approachDistance = sqrt(approachDX * approachDX + approachDZ * approachDZ)
                guard approachDistance <= 0.72 else { return nil }

                let toSeatX = seatPosition.x - position.x
                let toSeatZ = seatPosition.z - position.z
                let seatDistance = sqrt(toSeatX * toSeatX + toSeatZ * toSeatZ)
                guard seatDistance > 0.001 else { return nil }
                let alignment = (toSeatX * direction.x + toSeatZ * direction.z) / seatDistance
                guard alignment >= 0.72 else { return nil }

                let facingDirection = slot.contactFacingDirection
                return (
                    InteractiveSeat(
                        address: slot.address,
                        motion: slot.motion,
                        seatPosition: seatPosition,
                        approachPosition: approachPosition,
                        obstacleCenter: slot.obstacleCenter,
                        obstacleRadius: slot.obstacleRadius,
                        facingDirection: facingDirection
                    ),
                    approachDistance
                )
            }

            return candidates.min(by: { $0.1 < $1.1 })?.0
        }

        private var remotelyOccupiedSeatAddresses: Set<HomeIslandSeatAddress> {
            Set(owner.remotePlayers.compactMap { state in
                guard state.isVisible,
                      state.phoenixPose == .sit || state.phoenixPose == .lie,
                      let placement = state.seatPlacementID.flatMap(UUID.init(uuidString:)),
                      let slot = state.seatSlotID,
                      !slot.isEmpty
                else { return nil }
                return HomeIslandSeatAddress(placementID: placement, slotID: slot)
            })
        }

        /// Presence updates can race: two devices may start sitting before
        /// either sees the other's claim. Every client resolves that race with
        /// the same stable user-ID ordering. The loser is returned to a safe
        /// standing point, so a bench side or stump never keeps two sailors.
        private func resolveLocalSeatConflictIfNeeded() {
            guard let localID = owner.localPlayerID,
                  let activeSeat = seatInteractionState.seat,
                  let conflictingID = owner.remotePlayers
                    .filter({ state in
                        state.isVisible
                            && (state.phoenixPose == .sit || state.phoenixPose == .lie)
                            && state.seatPlacementID.flatMap(UUID.init(uuidString:))
                                == activeSeat.address.placementID
                            && state.seatSlotID == activeSeat.address.slotID
                    })
                    .map(\.id)
                    .min(),
                  conflictingID.localizedStandardCompare(localID) == .orderedAscending,
                  let navigator = navigatorNode
            else { return }

            navigator.removeAction(forKey: "seat-transition")
            let direction = activeSeat.facingDirection
            let exit = safestSeatExit(from: activeSeat, preferred: direction)
            let dx = exit.x - navigator.position.x
            let dz = exit.z - navigator.position.z
            let yaw = atan2(dx, dz)
            completeContactExit(navigator, at: exit, facingYaw: yaw)
            navigatorAnimator.pose = .idle
        }

        private func beginSitting(on seat: InteractiveSeat) {
            guard case .free = seatInteractionState else { return }

            seatInteractionState = .approaching(seat)
            DispatchQueue.main.async { [weak self] in
                self?.performSitting(on: seat)
            }
        }

        private func performSitting(on seat: InteractiveSeat) {
            guard case let .approaching(activeSeat) = seatInteractionState,
                  activeSeat.address == seat.address,
                  owner.mode == .explore,
                  let navigator = navigatorNode
            else { return }

            navigator.removeAction(forKey: "seat-transition")
            let targetYaw = atan2(seat.facingDirection.x, seat.facingDirection.z)
            let targetRoll = seat.motion == .lie ? NavigatorSleepMetrics.roll : 0
            let approachPosition = seat.approachPosition ?? navigator.position
            let approachDX = approachPosition.x - navigator.position.x
            let approachDZ = approachPosition.z - navigator.position.z
            let approachDistance = sqrt(
                approachDX * approachDX + approachDZ * approachDZ
            )
            let approachDuration = UIAccessibility.isReduceMotionEnabled
                ? 0
                : min(0.58, max(0.10, TimeInterval(approachDistance / 1.55)))
            let approachYaw = approachDistance > 0.001
                ? atan2(approachDX, approachDZ)
                : navigator.eulerAngles.y
            let walkToContact = SCNAction.group([
                .move(to: approachPosition, duration: approachDuration),
                .rotateTo(
                    x: 0,
                    y: CGFloat(approachYaw),
                    z: 0,
                    duration: min(approachDuration, 0.28),
                    usesShortestUnitArc: true
                ),
            ])
            walkToContact.timingMode = .easeInEaseOut
            let turnBeforeLowering = SCNAction.rotateTo(
                x: 0,
                y: CGFloat(targetYaw),
                z: 0,
                duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.24,
                usesShortestUnitArc: true
            )
            turnBeforeLowering.timingMode = .easeInEaseOut
            let lowerOntoSeat = SCNAction.group([
                .move(
                    to: seat.seatPosition,
                    duration: UIAccessibility.isReduceMotionEnabled
                        ? 0
                        : (seat.motion == .lie ? 0.62 : 0.68)
                ),
                .rotateTo(
                    x: 0,
                    y: CGFloat(targetYaw),
                    z: CGFloat(targetRoll),
                    duration: UIAccessibility.isReduceMotionEnabled
                        ? 0
                        : (seat.motion == .lie ? 0.52 : 0.30),
                    usesShortestUnitArc: true
                ),
            ])
            lowerOntoSeat.timingMode = .easeInEaseOut
            let settle = SCNAction.sequence([
                walkToContact,
                turnBeforeLowering,
                .run { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self,
                              self.seatInteractionState.seat?.address == seat.address
                        else { return }
                        self.seatInteractionState = .settling(seat)
                    }
                },
                .wait(duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.03),
                lowerOntoSeat,
                .wait(duration: seat.motion == .lie ? 0.22 : 0.18),
                .run { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self,
                              self.seatInteractionState.seat?.address == seat.address
                        else { return }
                        self.seatInteractionState = .seated(seat)
                        Haptics.tap(.light)
                    }
                },
            ])
            navigator.runAction(settle, forKey: "seat-transition")
        }

        private func beginLeavingSeat(toward direction: SCNVector3) {
            guard case let .seated(seat) = seatInteractionState else { return }

            seatInteractionState = .standingUp(seat)
            DispatchQueue.main.async { [weak self] in
                self?.performLeavingSeat(seat, toward: direction)
            }
        }

        private func performLeavingSeat(
            _ seat: InteractiveSeat,
            toward direction: SCNVector3
        ) {
            guard case let .standingUp(activeSeat) = seatInteractionState,
                  activeSeat.address == seat.address,
                  owner.mode == .explore,
                  let navigator = navigatorNode
            else { return }

            let exitPosition = safestSeatExit(from: seat, preferred: direction)
            // The validator may choose an alternate safe point when the requested
            // direction is blocked. Face the point we actually move toward instead
            // of keeping the stale joystick direction.
            let exitDX = exitPosition.x - navigator.position.x
            let exitDZ = exitPosition.z - navigator.position.z
            let exitLength = sqrt(exitDX * exitDX + exitDZ * exitDZ)
            let exitDirection = exitLength > 0.001
                ? SCNVector3(exitDX / exitLength, 0, exitDZ / exitLength)
                : direction
            let exitYaw = atan2(exitDirection.x, exitDirection.z)
            if UIAccessibility.isReduceMotionEnabled {
                completeContactExit(
                    navigator,
                    at: exitPosition,
                    facingYaw: exitYaw
                )
                return
            }

            navigator.removeAction(forKey: "seat-transition")
            let stepDown = SCNAction.group([
                .move(to: exitPosition, duration: 0.40),
                .rotateTo(
                    x: 0,
                    y: CGFloat(exitYaw),
                    z: 0,
                    duration: 0.28,
                    usesShortestUnitArc: true
                ),
            ])
            stepDown.timingMode = .easeInEaseOut
            let leave = SCNAction.sequence([
                .wait(duration: 0.34),
                .run { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self,
                              self.seatInteractionState.seat?.address == seat.address
                        else { return }
                        self.seatInteractionState = .leaving(seat)
                    }
                },
                stepDown,
                .run { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self,
                              self.seatInteractionState.seat?.address == seat.address
                        else { return }
                        self.completeContactExit(
                            navigator,
                            at: exitPosition,
                            facingYaw: exitYaw
                        )
                    }
                },
            ])
            navigator.runAction(leave, forKey: "seat-transition")
        }

        /// Finalizes every world-contact motion at one authoritative transform.
        /// Future sit/lie interactions must use this path so an animation cannot
        /// leave behind a stale yaw or immediately retrigger its contact slot.
        private func completeContactExit(
            _ navigator: SCNNode,
            at position: SCNVector3,
            facingYaw: Float
        ) {
            navigator.position = position
            navigator.eulerAngles = SCNVector3(0, facingYaw, 0)
            seatInteractionState = .free
            contactReentryBlockedUntil = CACurrentMediaTime() + 0.75
            snapFacingOnNextMovement = true
            distanceSinceFootprint = 0
        }

        private func safestSeatExit(
            from seat: InteractiveSeat,
            preferred direction: SCNVector3
        ) -> SCNVector3 {
            if let approach = seat.approachPosition,
               isWalkable(x: approach.x, z: approach.z) {
                return SCNVector3(
                    approach.x,
                    groundHeight(x: approach.x, z: approach.z),
                    approach.z
                )
            }
            let baseAngle = atan2(direction.x, direction.z)
            let angleOffsets: [Float] = [0, .pi / 6, -.pi / 6, .pi / 3, -.pi / 3,
                                           .pi / 2, -.pi / 2, .pi]
            let minimumRadius = seat.obstacleRadius + 0.32 + 0.14
            for extraRadius in stride(from: Float(0), through: 0.60, by: 0.20) {
                let radius = minimumRadius + extraRadius
                for offset in angleOffsets {
                    let angle = baseAngle + offset
                    let x = seat.obstacleCenter.x + sin(angle) * radius
                    let z = seat.obstacleCenter.z + cos(angle) * radius
                    if isWalkable(x: x, z: z) {
                        return SCNVector3(x, groundHeight(x: x, z: z), z)
                    }
                }
            }
            return safestLandingPosition()
        }

        private func cancelSeatInteraction() {

            guard seatInteractionState.keepsNavigatorOnSeat else { return }
            navigatorNode?.removeAction(forKey: "seat-transition")
            seatInteractionState = .free
            navigatorAnimator.pose = .idle
        }

        private func addFootprintIfNeeded(frame: HomeIslandLocomotionFrame) {
            guard frame.ground.surface == .sand,
                  frame.planarSpeed > 0.04
            else { return }
            let direction = SIMD2<Float>(frame.velocity.x, frame.velocity.z)
                / max(frame.planarSpeed, 0.001)
            let isLeft = frame.stepFoot == .left
            let side: Float = isLeft ? -1 : 1
            let sideOffset: Float = 0.105
            let footprintX = frame.position.x + direction.y * sideOffset * side
            let footprintZ = frame.position.z - direction.x * sideOffset * side
            let sample = groundSample(x: footprintX, z: footprintZ)
            guard sample.surface == .sand else { return }
            let footprint = HomeIslandFootprintVisual.makeNode(leftFoot: isLeft)
            footprint.position = SCNVector3(
                footprintX,
                sample.height + 0.009,
                footprintZ
            )
            let yaw = atan2(direction.x, direction.y)
            let alignToGround = simd_quatf(
                from: SIMD3<Float>(0, 1, 0),
                to: sample.normal
            )
            let faceTravel = simd_quatf(
                angle: yaw,
                axis: SIMD3<Float>(0, 1, 0)
            )
            footprint.simdOrientation = alignToGround * faceTravel
            footprint.opacity = 0
            footprintParent.addChildNode(footprint)
            footprintNodes.append(footprint)
            footprint.runAction(.fadeOpacity(to: 0.72, duration: 0.14))

            if footprintNodes.count > 8 {
                let oldest = footprintNodes.removeFirst()
                oldest.removeAllActions()
                oldest.runAction(.sequence([
                    .fadeOut(duration: 0.42),
                    .removeFromParentNode(),
                ]))
            }
            refreshFootprintDepth()
        }

        private func refreshFootprintDepth() {
            let count = max(footprintNodes.count, 1)
            for (index, footprint) in footprintNodes.enumerated() {
                guard index < count - 1 else { continue }
                let progress = Float(index + 1) / Float(count)
                let opacity = CGFloat(0.22 + progress * 0.46)
                footprint.removeAction(forKey: "footprint-age")
                footprint.runAction(
                    .fadeOpacity(to: opacity, duration: 0.20),
                    forKey: "footprint-age"
                )
            }
        }

        #if DEBUG
        private func installDebugFootprintTrailIfRequested() {
            guard ProcessInfo.processInfo.environment["LANDFALL_FOOTPRINT_DEMO"] != nil
            else { return }
            for index in 0..<8 {
                let isLeft = index.isMultiple(of: 2)
                let footprint = HomeIslandFootprintVisual.makeNode(leftFoot: isLeft)
                footprint.position = SCNVector3(
                    isLeft ? -0.105 : 0.105,
                    HomeIslandMetrics.surfaceY + 0.030,
                    5.75 + Float(index) * 0.34
                )
                footprint.opacity = CGFloat(0.24 + Float(index) * 0.065)
                footprintParent.addChildNode(footprint)
            }
        }

        #endif

        private func followNavigatorCamera() {
            guard owner.mode == .explore,
                  !owner.cameraShowcaseActive,
                  let navigator = navigatorNode,
                  let target = cameraTarget
            else { return }
            let basis = cameraGroundBasis()
            let desired = SCNVector3(
                navigator.position.x
                    + cameraMotion.lookAhead.x
                    + basis.right.x * cameraMotion.bob.x,
                navigator.position.y + 0.72 + cameraMotion.bob.y,
                navigator.position.z
                    + cameraMotion.lookAhead.y
                    + basis.right.z * cameraMotion.bob.x
            )
            let response = 1 - exp(
                -locomotionTuning.cameraFollowSharpness
                    * min(max(lastLocomotionDeltaTime, 0), 0.05)
            )
            target.position = SCNVector3(
                target.position.x + (desired.x - target.position.x) * response,
                target.position.y + (desired.y - target.position.y) * response,
                target.position.z + (desired.z - target.position.z) * response
            )
        }

        private func groundHeight(x: Float, z: Float) -> Float {
            groundSample(x: x, z: z).height
        }

        private func groundSample(x: Float, z: Float) -> HomeIslandGroundSample {
            let foundation = foundationGroundSample(x: x, z: z)
            let playerRadius = NavigatorCollision.radius
            if let jetty = jettyWalkSurfaces.first(where: {
                $0.containsGroundSurface(x: x, z: z, playerRadius: playerRadius)
            }) {
                return HomeIslandGroundSample(
                    height: jetty.height(
                        x: x,
                        z: z,
                        playerRadius: playerRadius,
                        baseHeight: foundation.height
                    ),
                    normal: jetty.normal(
                        x: x,
                        z: z,
                        playerRadius: playerRadius,
                        baseHeight: { [weak self] sampleX, sampleZ in
                            self?.foundationGroundHeight(x: sampleX, z: sampleZ)
                                ?? HomeIslandMetrics.surfaceY
                        }
                    ),
                    surface: .wood
                )
            }
            if let lookout = lookoutWalkSurfaces.first(where: {
                $0.containsGroundSurface(x: x, z: z, playerRadius: playerRadius)
            }) {
                return HomeIslandGroundSample(
                    height: lookout.height(
                        x: x,
                        z: z,
                        playerRadius: playerRadius,
                        baseHeight: foundation.height
                    ),
                    normal: SIMD3<Float>(0, 1, 0),
                    surface: .wood
                )
            }
            return HomeIslandGroundSample(
                height: foundation.height,
                normal: foundation.normal,
                surface: decorativeGroundSurface(x: x, z: z) ?? .sand
            )
        }

        private func decorativeGroundSurface(
            x: Float,
            z: Float
        ) -> HomeIslandGroundSurface? {
            for placement in owner.store.placements.reversed() {
                let surface: HomeIslandGroundSurface
                switch placement.assetID {
                case "stone_path_straight", "stone_path_curve", "stone_path_fork",
                     "compass_rose_inlay":
                    surface = .stone
                case "dune_grass_patch":
                    surface = .grass
                default:
                    continue
                }
                let dx = x - placement.transform.x
                let dz = z - placement.transform.z
                let radius = max(
                    HomeIslandAssetCatalog.footprintMargin(
                        assetID: placement.assetID,
                        scale: placement.transform.scale
                    ) * 0.82,
                    0.32
                )
                if dx * dx + dz * dz <= radius * radius { return surface }
            }
            return nil
        }

        private func foundationGroundHeight(x: Float, z: Float) -> Float {
            foundationGroundSample(x: x, z: z).height
        }

        private func foundationGroundSample(x: Float, z: Float) -> HomeIslandGroundSample {
            guard let scene = view?.scene, let foundationNode else {
                return HomeIslandGroundSample(height: HomeIslandMetrics.surfaceY)
            }
            let options: [String: Any] = [
                SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.all.rawValue,
                SCNHitTestOption.backFaceCulling.rawValue: false,
            ]
            let hits = scene.rootNode.hitTestWithSegment(
                from: SCNVector3(x, 30, z),
                to: SCNVector3(x, -10, z),
                options: options
            )
            for hit in hits where isDescendant(hit.node, of: foundationNode) {
                return HomeIslandGroundSample(
                    height: hit.worldCoordinates.y,
                    normal: SIMD3<Float>(
                        hit.worldNormal.x,
                        hit.worldNormal.y,
                        hit.worldNormal.z
                    ),
                    surface: .sand
                )
            }
            return HomeIslandGroundSample(height: HomeIslandMetrics.surfaceY)
        }

        private func isDescendant(_ node: SCNNode, of ancestor: SCNNode) -> Bool {
            var candidate: SCNNode? = node
            while let current = candidate {
                if current === ancestor { return true }
                candidate = current.parent
            }
            return false
        }

        private func updateRemotePlayers(deltaTime: Float) {
            // SceneKit invokes this while holding its internal scene lock. A
            // blocking acquisition here can deadlock against SwiftUI's main
            // thread, which may be applying a Firestore state update. Skipping
            // one interpolation frame is invisible and keeps both threads live.
            guard remotePlayersLock.try() else { return }
            defer { remotePlayersLock.unlock() }

            for visual in remotePlayerVisuals.values {
                let node = visual.node
                if !visual.isArrivalAnimating {
                    let dx = visual.targetPosition.x - node.position.x
                    let dy = visual.targetPosition.y - node.position.y
                    let dz = visual.targetPosition.z - node.position.z
                    let distanceSquared = dx * dx + dy * dy + dz * dz
                    if distanceSquared > 9 {
                        // Rejoins and host snapshot changes must not make a visitor
                        // visibly run across the entire island from a stale point.
                        node.position = visual.targetPosition
                    } else if deltaTime > 0 {
                        let amount = 1 - exp(-10 * deltaTime)
                        node.position = SCNVector3(
                            node.position.x + dx * amount,
                            node.position.y + dy * amount,
                            node.position.z + dz * amount
                        )
                    }

                    let yawDelta = atan2(
                        sin(visual.targetYaw - node.eulerAngles.y),
                        cos(visual.targetYaw - node.eulerAngles.y)
                    )
                    node.eulerAngles.y += yawDelta * (1 - exp(-12 * deltaTime))
                    let targetRoll = visual.targetPose == .lie
                        ? NavigatorSleepMetrics.roll
                        : 0
                    let rollDelta = atan2(
                        sin(targetRoll - node.eulerAngles.z),
                        cos(targetRoll - node.eulerAngles.z)
                    )
                    node.eulerAngles.z += rollDelta * (1 - exp(-10 * deltaTime))
                }

                visual.animator.pose = visual.isArrivalAnimating
                    ? visual.arrivalPose
                    : visual.targetPose
                visual.animationTime += deltaTime
                visual.animator.step(t: visual.animationTime, dt: deltaTime)
            }
        }

        private func reportLocalPlayerStateIfNeeded(at time: TimeInterval) {
            guard let rawID = owner.localPlayerID,
                  let navigator = navigatorNode
            else { return }
            let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return }

            let presented = navigator.presentation
            let seatAddress = seatInteractionState.seat?.address
            let state = HomeIslandRemotePlayerState(
                id: id,
                x: presented.position.x,
                z: presented.position.z,
                yaw: presented.eulerAngles.y,
                pose: navigatorAnimator.pose.rawValue,
                phase: localPlayerPhase,
                seatPlacementID: seatAddress?.placementID.uuidString,
                seatSlotID: seatAddress?.slotID,
                isVisible: presented.opacity > 0.01 && navigator.parent != nil
            )

            let previous = lastReportedLocalPlayerState
            let discreteStateChanged = previous == nil
                || previous?.id != state.id
                || previous?.pose != state.pose
                || previous?.phase != state.phase
                || previous?.seatPlacementID != state.seatPlacementID
                || previous?.seatSlotID != state.seatSlotID
                || previous?.isVisible != state.isVisible
            let dx = state.x - (previous?.x ?? state.x)
            let dz = state.z - (previous?.z ?? state.z)
            let yawDelta = atan2(
                sin(state.yaw - (previous?.yaw ?? state.yaw)),
                cos(state.yaw - (previous?.yaw ?? state.yaw))
            )
            let transformChanged = dx * dx + dz * dz >= 0.0004
                || abs(yawDelta) >= 0.02
            let mayReportTransform = time - lastLocalPlayerReportTime >= 0.10
            guard discreteStateChanged || (transformChanged && mayReportTransform) else {
                return
            }

            lastReportedLocalPlayerState = state
            lastLocalPlayerReportTime = time
            let callback = owner.onLocalPlayerStateChanged
            DispatchQueue.main.async {
                callback(state)
            }
        }

        private var localPlayerPhase: String {
            switch owner.mode {
            case .arrival:
                "arrival"
            case .explore:
                "explore"
            case .edit:
                "edit"
            case .camera:
                "camera"
            case .departure:
                "departure"
            }
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let reduceMotion = UIAccessibility.isReduceMotionEnabled
            if reduceMotion != oceanReduceMotionEnabled {
                oceanReduceMotionEnabled = reduceMotion
                if reduceMotion {
                    frozenOceanTime = HomeIslandOceanEffects.currentTime
                }
            }
            seaMaterial?.setValue(
                NSNumber(
                    value: reduceMotion
                        ? frozenOceanTime
                        : HomeIslandOceanEffects.currentTime
                ),
                forKey: "uTime"
            )

            // The motor substeps internally. Preserve ordinary low-frame-rate
            // time instead of turning a hitch into slow motion; only cap long
            // background gaps to avoid an unbounded catch-up burst.
            let deltaTime = Float(min(max(time - (lastFrameTime ?? time), 0), 0.25))
            lastFrameTime = time
            // The build-mode thumb pan runs here rather than on the keyboard
            // loop: that loop only ticks while a WASD key is held, so on a
            // device with no keyboard the thumb moved nothing at all.
            if owner.mode == .edit, editCameraPanInput.magnitude > 0.001 {
                panEditCamera(with: editCameraPanInput, deltaTime: deltaTime)
            }
            if owner.mode == .explore {
                applyPendingExploreOrbit()
            }
            let isWalking = updateWalking(deltaTime: deltaTime)
            if owner.mode == .explore,
               !owner.cameraShowcaseActive {
                // Commit orbit intent and the moving follow target as one pose.
                // This is the single Explore-camera write for the frame.
                updateCamera()
            }
            switch seatInteractionState {
            case .approaching, .leaving:
                navigatorAnimator.pose = .walk
            case let .settling(contact), let .seated(contact):
                navigatorAnimator.pose = contact.motion == .lie ? .lie : .sit
            case .standingUp:
                navigatorAnimator.pose = .idle
            case .free:
                navigatorAnimator.pose = (arrivalNavigatorIsWalking || isWalking) ? .walk : .idle
            }
            navigatorAnimator.renderer(renderer, updateAtTime: time)
            updateRemotePlayers(deltaTime: deltaTime)
            reportLocalPlayerStateIfNeeded(at: time)
            reportNavigatorJettyPresenceIfNeeded()
            reportNoticeBoardProximityIfNeeded()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard let view else { return true }
            let point = touch.location(in: view)
            if gestureRecognizer === movementPanRecognizer {
                // Simulator mouse drags and a real iPad trackpad arrive as an
                // indirect pointer. They should drive the same invisible
                // thumbstick instead of falling through to camera orbit.
                let supportsMovement = touch.type == .direct
                    || touch.type == .indirectPointer
                guard supportsMovement, isMovementControlPoint(point, in: view)
                else { return false }
                // 親指の領域に置かれた飾りも、そこから掴んで動かせる。
                guard owner.mode == .edit, owner.placementAssetID == nil
                else { return true }
                return grabCandidate(at: point) == nil
            }
            if gestureRecognizer === runningJumpRecognizer {
                return touch.type == .direct
                    && owner.mode == .explore
                    && !owner.cameraInteractionLocked
                    && touchWalkInput.magnitude > locomotionTuning.inputDeadZone
                    && !isMovementControlPoint(point, in: view)
                    && !hasExploreInteractiveTarget(at: point)
            }
            if gestureRecognizer === orbitPanRecognizer, owner.mode == .edit {
                // Capture the target before UIPan's movement threshold is met.
                // This keeps rocks and stumps draggable even when the finger
                // leaves their small projected mesh during the first few pixels.
                // 進行中のドラッグは二本目の指に奪わせない。
                let dragIsLive = orbitPanRecognizer.map {
                    $0.state == .began || $0.state == .changed
                } ?? false
                if !dragIsLive {
                    selectionMoveTouchPlacementID = owner.placementAssetID == nil
                        ? grabCandidate(at: point)
                        : nil
                }
                // 飾りの上から始まったドラッグは、親指の領域でもその飾りの
                // もの。何もない地面から始まったドラッグは、必ずカメラ。
                if selectionMoveTouchPlacementID != nil { return true }
                return !isMovementControlPoint(point, in: view)
            }
            if gestureRecognizer === orbitPanRecognizer, owner.mode == .explore {
                return !isMovementControlPoint(point, in: view)
            }
            if gestureRecognizer === pinchRecognizer,
               owner.mode == .explore,
               touch.type == .direct,
               isMovementControlPoint(point, in: view) {
                // A movement thumb plus a camera thumb must not be mistaken
                // for a pinch-to-zoom gesture.
                return false
            }
            if gestureRecognizer === pinchRecognizer,
               owner.mode == .edit,
               propGrabInFlight {
                return false
            }
            if gestureRecognizer === twoFingerPanRecognizer {
                return (owner.mode == .edit || owner.mode == .camera)
                    && !propGrabInFlight
            }
            if gestureRecognizer === longPressRecognizer {
                return owner.mode == .edit || owner.mode == .camera
            }
            if gestureRecognizer === doubleTapRecognizer,
               owner.mode == .explore {
                return !isMovementControlPoint(point, in: view)
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            let isMovementAndOrbit = (
                gestureRecognizer === movementPanRecognizer
                    && otherGestureRecognizer === orbitPanRecognizer
            ) || (
                gestureRecognizer === orbitPanRecognizer
                    && otherGestureRecognizer === movementPanRecognizer
            )
            if isMovementAndOrbit { return true }
            if owner.mode == .edit,
               propGrabInFlight,
               (gestureRecognizer === pinchRecognizer
                    || otherGestureRecognizer === pinchRecognizer
                    || gestureRecognizer === twoFingerPanRecognizer
                    || otherGestureRecognizer === twoFingerPanRecognizer) {
                return false
            }
            let includesRunningJump = gestureRecognizer === runningJumpRecognizer
                || otherGestureRecognizer === runningJumpRecognizer
            if includesRunningJump {
                return gestureRecognizer === movementPanRecognizer
                    || otherGestureRecognizer === movementPanRecognizer
                    || gestureRecognizer === orbitPanRecognizer
                    || otherGestureRecognizer === orbitPanRecognizer
            }
            let isPinchAndTwoFingerPan = (
                gestureRecognizer === pinchRecognizer
                    && otherGestureRecognizer === twoFingerPanRecognizer
            ) || (
                gestureRecognizer === twoFingerPanRecognizer
                    && otherGestureRecognizer === pinchRecognizer
            )
            if isPinchAndTwoFingerPan { return false }
            return gestureRecognizer is UIPinchGestureRecognizer
                || otherGestureRecognizer is UIPinchGestureRecognizer
        }
    }
}

private extension SCNVector3 {
    static func + (lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
        SCNVector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }

    static func - (lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
        SCNVector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    static func * (lhs: SCNVector3, rhs: Float) -> SCNVector3 {
        SCNVector3(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
    }
}
