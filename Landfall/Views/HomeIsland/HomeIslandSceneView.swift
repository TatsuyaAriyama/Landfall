import SceneKit
import SwiftUI
import UIKit

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

enum HomeIslandMode: Equatable {
    case arrival
    case explore
    case edit
    case camera
    case departure
}

struct HomeIslandWalkInput: Equatable {
    var x: Float = 0
    var forward: Float = 0

    static let zero = HomeIslandWalkInput()
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

    private var heldMovementKeys: Set<UIKeyboardHIDUsage> = []
    private var keyboardDisplayLink: CADisplayLink?
    private var lastKeyboardTimestamp: CFTimeInterval?

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            becomeFirstResponder()
        } else {
            stopKeyboardMovement()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let movementKeys = Set(presses.compactMap(\.key?.keyCode).filter(isMovementKey))
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
            $0.key.map { isMovementKey($0.keyCode) } ?? false
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
        var input = HomeIslandWalkInput(
            x: (right ? 1 : 0) - (left ? 1 : 0),
            forward: (forward ? 1 : 0) - (backward ? 1 : 0)
        )
        let magnitude = sqrt(input.x * input.x + input.forward * input.forward)
        if magnitude > 1 {
            input.x /= magnitude
            input.forward /= magnitude
        }
        keyboardMovementHandler?(input, deltaTime)
    }
}

/// The consumer home-island canvas.  It intentionally exposes only placement,
/// selection and camera gestures; none of 3D Studio's terrain or transform tools
/// are reachable from this scene.
struct HomeIslandSceneView: UIViewRepresentable {
    @ObservedObject var store: HomeIslandStore
    @Binding var placementAssetID: String?
    var movingSelection: Bool
    var playerLevel: Int
    var cameraResetToken: Int
    var cameraRequest: HomeIslandCameraRequest?
    var captureRequest: HomeIslandCaptureRequest?
    var boatBoardingRequest: HomeIslandBoatBoardingRequest?
    var mode: HomeIslandMode
    var cameraExposureOffset: Float
    var cameraInteractionLocked: Bool
    var walkInput: HomeIslandWalkInput
    var onMoveCompleted: () -> Void
    var onPlacementCompleted: (UUID) -> Void
    var onPlacementRejected: () -> Void
    var onAssetActivated: (String) -> Void
    var onAssetInteractionDenied: (String) -> Void
    var onArrivalCompleted: () -> Void
    var onJettyPresenceChanged: (Bool) -> Void
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
    var onBoatSelected: () -> Void = {}
    /// Other room members, already filtered for membership and staleness by
    /// the multiplayer service. The local ID is ignored if it is echoed back.
    var remotePlayers: [HomeIslandRemotePlayerState] = []
    var localPlayerID: String? = nil
    /// Emits a coalesced local transform while it changes. The networking layer
    /// remains responsible for write throttling and idle heartbeats.
    var onLocalPlayerStateChanged: (HomeIslandRemotePlayerState) -> Void = { _ in }

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
        private var moveDragOffset = SCNVector3Zero
        private var moveDragPosition: SCNVector3?
        private var renderedResetToken = 0
        private var processedCameraRequestID: UUID?
        private var processedCaptureRequestID: UUID?
        private var processedBoatBoardingRequestID: UUID?
        private var lastFrameTime: TimeInterval?
        private var renderedMode: HomeIslandMode = .arrival
        private var renderedBoatCustomizationActive = false
        private var renderedBoatAppearanceID = ""
        private var boatCustomizationCameraSnapshot: BoatCustomizationCameraSnapshot?
        private weak var orbitPanRecognizer: UIPanGestureRecognizer?
        /// UIKit supplies orbit intent while SceneKit owns the final Explore
        /// camera pose. The lock makes the handoff explicit across their threads.
        private let exploreOrbitLock = NSLock()
        private var pendingExploreOrbitAngles: (azimuth: Float, elevation: Float)?
        private weak var movementPanRecognizer: UIPanGestureRecognizer?
        private weak var twoFingerPanRecognizer: UIPanGestureRecognizer?
        private weak var pinchRecognizer: UIPinchGestureRecognizer?
        private weak var longPressRecognizer: UILongPressGestureRecognizer?
        private weak var doubleTapRecognizer: UITapGestureRecognizer?
        private var touchWalkInput = HomeIslandWalkInput.zero
        private var keyboardWalkInput = HomeIslandWalkInput.zero
        private var externalWalkInput = HomeIslandWalkInput.zero
        private var movementFeedbackSent = false
        private var arrivalStarted = false
        private var arrivalFinished = false
        private var arrivalNavigatorIsWalking = false
        private var renderedNavigatorOnArrivalJetty: Bool?
        private var reportedNavigatorOnArrivalJetty: Bool?
        private var boardingRequested = false
        private var departureStarted = false
        private var arrivalBoatStopPosition = SCNVector3(0, -0.35, 20.2)
        private var arrivalJettyWalkSurface: JettyWalkSurface?
        private var cachedWalkInput = HomeIslandWalkInput.zero
        private var walkingObstacles: [WalkingObstacle] = []
        private var ruinsWalkObstacles: [RuinsWalkObstacle] = []
        private var jettyWalkSurfaces: [JettyWalkSurface] = []
        private var stumpSeats: [StumpSeat] = []
        private var placedSeatSlots: [PlacedSeatSlot] = []
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
            static let deckWalkDuration: TimeInterval = 2.85
            static let jettySettleDuration: TimeInterval = 0.55
        }

        private enum NavigatorLocomotion {
            static let maximumSpeed: Float = 2.45
        }

        private enum NavigatorAppearance {
            static let islandScale: Float = 0.78
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
            /// small_stump.blend の切断面。苔や年輪の装飾上端は座面に含めない。
            static let stumpCutSurfaceLocalY: Float = 0.605
            /// 丸い切り株では衣装下端をわずかに木へ沈め、接触感を出す。
            static let stumpContactInset: Float = 0.05
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

        private struct StumpSeat {
            let id: UUID
            let transform: HomeIslandTransform
            let topY: Float
            let obstacleRadius: Float

            func seatPosition(rootToSeatSurface: Float) -> SCNVector3 {
                return SCNVector3(
                    transform.x,
                    topY
                        - rootToSeatSurface
                        + NavigatorSeatMetrics.surfaceClearance
                        - NavigatorSeatMetrics.stumpContactInset,
                    transform.z
                )
            }

            var triggerRadius: Float {
                max(0.92, obstacleRadius + 0.47)
            }

            /// 進んできた方向を向いたまま、膝下が切り株の縁から自然に下りる位置。
            func seatPosition(
                facing direction: SCNVector3,
                rootToSeatSurface: Float
            ) -> SCNVector3 {
                let edgeOffset = max(0.12, obstacleRadius - 0.26)
                let base = seatPosition(rootToSeatSurface: rootToSeatSurface)
                return SCNVector3(
                    base.x + direction.x * edgeOffset,
                    base.y,
                    base.z + direction.z * edgeOffset
                )
            }

            var address: HomeIslandSeatAddress {
                HomeIslandSeatAddress(placementID: id, slotID: "stump")
            }
        }

        /// Runtime-resolved sockets for assets with more than one seat. The
        /// stable ID is suitable for a future multiplayer occupancy record.
        private struct PlacedSeatSlot {
            let placementID: UUID
            let slotID: String
            let motion: HomeIslandContactMotion
            let seatNode: SCNNode
            let approachNode: SCNNode
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
                return SCNVector3(
                    outwardX / outwardLength,
                    0,
                    outwardZ / outwardLength
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
                return SCNVector3(
                    surface.x + outwardX / max(outwardLength, 0.001)
                        * NavigatorSeatMetrics.backrestClearance,
                    surface.y
                        - rootToSeatSurface
                        + NavigatorSeatMetrics.surfaceClearance,
                    surface.z + outwardZ / max(outwardLength, 0.001)
                        * NavigatorSeatMetrics.backrestClearance
                )
            }

            var approachWorldPosition: SCNVector3 {
                approachNode.presentation.worldPosition
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
                let connectorNearX = 0.52 * scale
                let connectorFarX = 1.54 * scale
                let connectorHalfLength = 0.52 * scale
                let isOnConnector = local.x >= connectorNearX
                    && local.x <= connectorFarX
                    && abs(local.z - floatCenterZ) <= connectorHalfLength
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
                let isBoardingGate = local.x > 0
                    && local.z >= HomeIslandMetrics.jettyBoardingGateSeawardLocalZ * scale
                    && local.z <= HomeIslandMetrics.jettyBoardingGateLandwardLocalZ * scale
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

            func height(x: Float, z: Float, baseHeight: Float) -> Float {
                let local = localPosition(x: x, z: z)
                let localZ = local.z
                let scale = max(transform.scale, 0.05)
                let flatDeck = HomeIslandMetrics.surfaceY + 0.445 * scale
                let floatCenterX = HomeIslandMetrics.boardingFloatCenterLocalX * scale
                let floatCenterZ = HomeIslandMetrics.boardingFloatCenterLocalZ * scale
                let isOnFloat = abs(local.x - floatCenterX)
                        <= HomeIslandMetrics.boardingFloatHalfWidth * scale
                    && abs(local.z - floatCenterZ)
                        <= HomeIslandMetrics.boardingFloatHalfLength * scale
                let lowDeck = HomeIslandMetrics.surfaceY - 0.215 * scale
                if isOnFloat { return lowDeck }
                let connectorNearX = 0.58 * scale
                let connectorFarX = 1.54 * scale
                if local.x > connectorNearX,
                   local.x < connectorFarX,
                   abs(local.z - floatCenterZ) <= 0.56 * scale {
                    let progress = min(
                        max((local.x - connectorNearX) / (connectorFarX - connectorNearX), 0),
                        1
                    )
                    return flatDeck + (lowDeck - flatDeck) * progress
                }
                let rampStart = 1.70 * scale
                let shoreEnd = 2.30 * scale
                guard localZ > rampStart else { return max(baseHeight, flatDeck) }
                let progress = min(max((localZ - rampStart) / max(shoreEnd - rampStart, 0.001), 0), 1)
                let shoreHeight = max(baseHeight, HomeIslandMetrics.surfaceY + 0.055 * scale)
                return flatDeck + (shoreHeight - flatDeck) * progress
            }
        }

        init(owner: HomeIslandSceneView) {
            self.owner = owner
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
            } else {
                updateCamera()
                startArrivalIfNeeded()
            }
        }

        func update(owner: HomeIslandSceneView) {
            self.owner = owner
            if renderedLocalPlayerID != owner.localPlayerID {
                renderedLocalPlayerID = owner.localPlayerID
                lastReportedLocalPlayerState = nil
                lastLocalPlayerReportTime = -.infinity
            }
            externalWalkInput = owner.walkInput
            refreshWalkInput()
            updateExposure()
            syncPlacements()
            syncRemotePlayers()
            syncBoatAppearanceIfNeeded()
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
            let target = CGFloat(owner.mode == .camera ? owner.cameraExposureOffset : 0.82)
            guard let sceneCamera = camera?.camera,
                  abs(sceneCamera.exposureOffset - target) > 0.001
            else { return }
            sceneCamera.exposureOffset = target
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
                let berthFocus = arrivalJettyLandingPath().transfer
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
            cameraComponent.exposureOffset = 0.82
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

            addAsset(
                "harbor_gathering_deck",
                name: "home-island-locked-gathering-deck",
                position: HomeIslandMetrics.gatheringDeckPosition,
                scale: HomeIslandMetrics.gatheringDeckScale
            )

            if addAsset(
                "harbor_sail_canopy",
                name: "home-island-locked-sail-canopy",
                position: HomeIslandMetrics.sailCanopyPosition,
                yaw: HomeIslandMetrics.sailCanopyYaw,
                scale: HomeIslandMetrics.sailCanopyScale
            ) != nil {
                let center = HomeIslandMetrics.sailCanopyPosition
                let yaw = HomeIslandMetrics.sailCanopyYaw
                let scale = HomeIslandMetrics.sailCanopyScale
                let postOffsets: [(Float, Float)] = [
                    (-1.65, 1.18),
                    (1.65, 1.18),
                    (-1.65, -1.18),
                    (1.65, -1.18),
                ]
                for (localX, localZ) in postOffsets {
                    let cosine = cos(yaw)
                    let sine = sin(yaw)
                    fixedHarborWalkingObstacles.append(WalkingObstacle(
                        x: center.x + localX * scale * cosine + localZ * scale * sine,
                        z: center.z - localX * scale * sine + localZ * scale * cosine,
                        radius: 0.18
                    ))
                }
            }

            if let table = addAsset(
                "harbor_council_table",
                name: "home-island-locked-council-table",
                position: HomeIslandMetrics.councilTablePosition,
                scale: HomeIslandMetrics.councilTableScale
            ) {
                let position = HomeIslandMetrics.councilTablePosition
                fixedHarborSeatAssets.append(FixedHarborSeatAsset(
                    id: HomeIslandMetrics.councilTableSeatID,
                    assetID: "harbor_council_table",
                    node: table,
                    obstacleCenter: SCNVector3(position.x, HomeIslandMetrics.surfaceY, position.z),
                    obstacleRadius: 0.62
                ))
                fixedHarborWalkingObstacles.append(WalkingObstacle(
                    x: position.x,
                    z: position.z,
                    radius: 0.62
                ))
            }

            if let bench = addAsset(
                "harbor_arc_bench",
                name: "home-island-locked-arc-bench",
                position: HomeIslandMetrics.arcBenchPosition,
                yaw: HomeIslandMetrics.arcBenchYaw,
                scale: HomeIslandMetrics.arcBenchScale
            ) {
                let position = HomeIslandMetrics.arcBenchPosition
                fixedHarborSeatAssets.append(FixedHarborSeatAsset(
                    id: HomeIslandMetrics.arcBenchSeatID,
                    assetID: "harbor_arc_bench",
                    node: bench,
                    obstacleCenter: SCNVector3(position.x, HomeIslandMetrics.surfaceY, position.z),
                    obstacleRadius: 1.08
                ))
                fixedHarborWalkingObstacles.append(WalkingObstacle(
                    x: position.x,
                    z: position.z,
                    radius: 1.08
                ))
            }

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
            let visibleIDs = Set(owner.store.placements.map(\.id))
            for (id, node) in placementNodes where !visibleIDs.contains(id) {
                node.removeFromParentNode()
                placementNodes[id] = nil
            }

            for placement in owner.store.placements {
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
            walkingObstacles = owner.store.placements.compactMap { placement in
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
            ruinsWalkObstacles = owner.store.placements.compactMap { placement in
                guard placement.assetID == "mossy_ruins" else { return nil }
                return RuinsWalkObstacle(transform: placement.transform)
            }
            stumpSeats = owner.store.placements.compactMap { placement in
                guard placement.assetID == "small_stump",
                      let node = placementNodes[placement.id]
                else { return nil }
                let scale = max(placement.transform.scale, 0.05)
                let obstacleRadius = max(
                    0.25,
                    HomeIslandAssetCatalog.footprintMargin(
                        assetID: placement.assetID,
                        scale: scale
                    ) * 0.72
                )
                return StumpSeat(
                    id: placement.id,
                    transform: placement.transform,
                    topY: node.position.y
                        + NavigatorSeatMetrics.stumpCutSurfaceLocalY * scale,
                    obstacleRadius: obstacleRadius
                )
            }
            placedSeatSlots = owner.store.placements.flatMap { placement -> [PlacedSeatSlot] in
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
                        obstacleCenter: asset.obstacleCenter,
                        obstacleRadius: asset.obstacleRadius
                    )
                }
            }
            if let activeAddress = seatInteractionState.seat?.address {
                let seatStillExists = stumpSeats.contains(where: { $0.address == activeAddress })
                    || placedSeatSlots.contains(where: { $0.address == activeAddress })
                if !seatStillExists {
                    cancelStumpInteraction()
                    if owner.mode == .explore { ensureNavigatorIsWalkable() }
                }
            }
            let playerJettySurfaces: [JettyWalkSurface] = owner.store.placements.compactMap {
                placement -> JettyWalkSurface? in
                guard placement.assetID == "wooden_jetty" else { return nil }
                return JettyWalkSurface(transform: placement.transform)
            }
            jettyWalkSurfaces = (arrivalJettyWalkSurface.map { [$0] } ?? [])
                + playerJettySurfaces
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

                let navigator = PhoenixNavigator.makeNavigatorNode()
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
                if let stump = stumpSeats.first(where: { $0.address == address }) {
                    let seat = stump.seatPosition(
                        rootToSeatSurface: navigatorRootToSeatSurface
                    )
                    return SCNVector3(state.x, seat.y, state.z)
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
            let sailor = PhoenixNavigator.makeNavigatorNode()
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
            navigator.scale = SCNVector3(0.57, 0.57, 0.57)
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
                navigator.position = path.deck
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
            let growOnTransfer = SCNAction.scale(
                to: 0.68,
                duration: ArrivalMotion.transferDuration
            )
            growOnTransfer.timingMode = .easeInEaseOut
            let crossJetty = SCNAction.move(
                to: path.deck,
                duration: ArrivalMotion.deckWalkDuration
            )
            crossJetty.timingMode = .easeInEaseOut
            let growToIslandScale = SCNAction.scale(
                to: CGFloat(NavigatorAppearance.islandScale),
                duration: 0.62
            )
            growToIslandScale.timingMode = .easeOut

            navigator.runAction(.sequence([
                .group([fadeIn, transfer, growOnTransfer]),
                .run { _ in
                    gangplank.runAction(.sequence([
                        .fadeOut(duration: 0.24),
                        .removeFromParentNode(),
                    ]))
                },
                .group([crossJetty, growToIslandScale]),
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

            let bounds = node.boundingBox
            let width = max(0.24, CGFloat(bounds.max.x - bounds.min.x) + 0.22)
            let height = max(0.24, CGFloat(bounds.max.y - bounds.min.y) + 0.22)
            let length = max(0.24, CGFloat(bounds.max.z - bounds.min.z) + 0.22)
            let box = SCNBox(width: width, height: height, length: length, chamferRadius: 0.04)
            box.widthSegmentCount = 1
            box.heightSegmentCount = 1
            box.lengthSegmentCount = 1
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = UIColor(rgb: 0xF3D58B)
            material.emission.contents = UIColor(rgb: 0x8CCDB5).withAlphaComponent(0.28)
            material.fillMode = .lines
            material.readsFromDepthBuffer = false
            material.writesToDepthBuffer = false
            box.materials = [material]
            let outline = SCNNode(geometry: box)
            outline.name = "home-island-selection-outline"
            outline.renderingOrder = 500
            outline.position = SCNVector3(
                (bounds.min.x + bounds.max.x) * 0.5,
                (bounds.min.y + bounds.max.y) * 0.5,
                (bounds.min.z + bounds.max.z) * 0.5
            )
            node.addChildNode(outline)
            selectedOutline = outline
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
                guard let placementID = hitPlacement(at: screenPoint),
                      let placement = owner.store.placements.first(where: { $0.id == placementID })
                else { return }
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
                guard assetID == "wooden_jetty" || HomeIslandMetrics.contains(x: point.x, z: point.z),
                      let placementID = owner.store.add(
                    assetID: assetID,
                    x: point.x,
                    z: point.z,
                    playerLevel: owner.playerLevel
                ) else {
                    owner.onPlacementRejected()
                    Haptics.error()
                    return
                }
                owner.placementAssetID = nil
                let onPlacementCompleted = owner.onPlacementCompleted
                DispatchQueue.main.async {
                    onPlacementCompleted(placementID)
                }
                Haptics.tap(.light)
                return
            }

            if owner.movingSelection,
               let point = groundPoint(at: screenPoint),
               (owner.store.selectedPlacement?.assetID == "wooden_jetty"
                    || HomeIslandMetrics.contains(x: point.x, z: point.z)) {
                guard owner.store.moveSelected(x: point.x, z: point.z) else {
                    owner.onPlacementRejected()
                    Haptics.error()
                    return
                }
                owner.onMoveCompleted()
                Haptics.tap(.medium)
                return
            }

            if let placementID = hitPlacement(at: screenPoint) {
                owner.store.select(placementID)
                Haptics.tap(.light)
            } else {
                owner.store.select(nil)
            }
        }

        private func focusCamera(at screenPoint: CGPoint) {
            guard let view, let target = cameraTarget else { return }
            let hits = view.hitTest(
                screenPoint,
                options: [.searchMode: SCNHitTestSearchMode.all.rawValue]
            )
            let focusPoint = hits.first(where: { !isOceanNode($0.node) })?.worldCoordinates
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
            let boardingPoint = arrivalJettyLandingPath().transfer
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
            cachedWalkInput = .zero
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

        private func groundPoint(at point: CGPoint) -> SCNVector3? {
            guard let view else { return nil }
            let near = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 0))
            let far = view.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 1))
            let direction = far - near
            guard abs(direction.y) > 0.0001 else { return nil }
            let distance = (HomeIslandMetrics.surfaceY - near.y) / direction.y
            guard distance >= 0 else { return nil }
            return near + direction * distance
        }

        /// A large thumb-reachable region instead of a fixed joystick. The
        /// right and upper portions remain available for direct camera orbit,
        /// and UIKit can track one finger in each region simultaneously.
        private func isMovementControlPoint(_ point: CGPoint, in view: UIView) -> Bool {
            guard owner.mode == .explore,
                  !owner.boatCustomizationActive,
                  !boardingRequested
            else { return false }
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
            guard owner.mode == .explore,
                  !owner.boatCustomizationActive,
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
                refreshWalkInput()
            case .ended, .cancelled, .failed:
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
                  !owner.boatCustomizationActive,
                  !boardingRequested
            else {
                cachedWalkInput = .zero
                return
            }
            var input = HomeIslandWalkInput(
                x: externalWalkInput.x + touchWalkInput.x + keyboardWalkInput.x,
                forward: externalWalkInput.forward
                    + touchWalkInput.forward
                    + keyboardWalkInput.forward
            )
            let magnitude = sqrt(input.x * input.x + input.forward * input.forward)
            if magnitude > 1 {
                input.x /= magnitude
                input.forward /= magnitude
            }
            cachedWalkInput = input
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard owner.mode != .arrival,
                  owner.mode != .departure,
                  !(owner.mode == .camera && owner.cameraInteractionLocked),
                  let view
            else { return }
            view.becomeFirstResponder()
            if recognizer.numberOfTouches == 0 {
                handlePointerScroll(recognizer)
                return
            }
            if owner.mode == .edit, owner.movingSelection {
                handleSelectionMove(recognizer, in: view)
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

        private func handleSelectionMove(
            _ recognizer: UIPanGestureRecognizer,
            in view: SCNView
        ) {
            guard let selected = owner.store.selectedPlacement,
                  let node = placementNodes[selected.id]
            else {
                clearSelectionMoveDrag()
                return
            }

            let screenPoint = recognizer.location(in: view)
            switch recognizer.state {
            case .began:
                guard let point = groundPoint(at: screenPoint) else { return }
                moveDragPlacementID = selected.id
                moveDragOffset = SCNVector3(
                    selected.transform.x - point.x,
                    0,
                    selected.transform.z - point.z
                )
                moveDragPosition = SCNVector3(
                    selected.transform.x,
                    HomeIslandMetrics.surfaceY,
                    selected.transform.z
                )
            case .changed:
                guard moveDragPlacementID == selected.id,
                      let point = groundPoint(at: screenPoint)
                else { return }
                let targetX = point.x + moveDragOffset.x
                let targetZ = point.z + moveDragOffset.z
                guard let transform = owner.store.validTransform(
                    assetID: selected.assetID,
                    x: targetX,
                    z: targetZ,
                    yaw: selected.transform.yaw,
                    scale: selected.transform.scale,
                    excluding: selected.id,
                    requireValidCoastPoint: selected.assetID == "wooden_jetty"
                ) else { return }
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
                guard moveDragPlacementID == selected.id,
                      let position = moveDragPosition
                else {
                    clearSelectionMoveDrag()
                    return
                }
                guard owner.store.moveSelected(x: position.x, z: position.z) else {
                    selected.transform.apply(to: node)
                    clearSelectionMoveDrag()
                    owner.onPlacementRejected()
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

        private func clearSelectionMoveDrag() {
            moveDragPlacementID = nil
            moveDragOffset = SCNVector3Zero
            moveDragPosition = nil
        }

        @objc private func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
            guard owner.mode == .edit || owner.mode == .camera,
                  !(owner.mode == .camera && owner.cameraInteractionLocked),
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
                  !(owner.mode == .camera && owner.cameraInteractionLocked),
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
                  !(owner.mode == .camera && owner.cameraInteractionLocked),
                  !owner.movingSelection,
                  recognizer.state == .began,
                  let view
            else { return }
            if owner.mode == .camera {
                focusCamera(at: recognizer.location(in: view))
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
                  !(owner.mode == .camera && owner.cameraInteractionLocked),
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
                  !(owner.mode == .camera && owner.cameraInteractionLocked),
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
                  !(owner.mode == .camera && owner.cameraInteractionLocked),
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
                cachedWalkInput = .zero
                return
            }
            if owner.startsMooredAtIsland,
               owner.locksMooredOverview,
               owner.mode == .explore {
                keyboardWalkInput = .zero
                cachedWalkInput = .zero
                return
            }
            switch owner.mode {
            case .arrival, .departure:
                keyboardWalkInput = .zero
                cachedWalkInput = .zero
            case .explore:
                keyboardWalkInput = input
                refreshWalkInput()
            case .edit, .camera:
                keyboardWalkInput = .zero
                cachedWalkInput = .zero
                guard !(owner.mode == .camera && owner.cameraInteractionLocked)
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

        private func zoomCamera(by factor: Float) {
            radius *= factor
            updateCamera(animated: 0.18)
        }

        private func updateCamera(animated duration: TimeInterval = 0) {
            constrainCamera()
            guard let camera, let target = cameraTarget?.position else { return }
            camera.camera?.zNear = Double(max(0.012, radius * 0.002))
            camera.camera?.zFar = Double(max(1_500, radius * 8))
            if duration > 0 {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = UIAccessibility.isReduceMotionEnabled ? 0 : duration
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            }
            let horizontal = cos(elevation) * radius
            camera.position = SCNVector3(
                target.x + cos(azimuth) * horizontal,
                target.y + sin(elevation) * radius,
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
            elevation = min(max(elevation, 0.08), 1.28)
            switch owner.mode {
            case .explore:
                radius = owner.startsMooredAtIsland && owner.locksMooredOverview
                    ? min(max(radius, 11.5), 48)
                    : min(max(radius, 3.2), 11.5)
            case .camera:
                radius = min(max(radius, 3.2), 48)
            case .arrival, .edit, .departure:
                radius = min(max(radius, 1.4), 420)
            }
            guard let target = cameraTarget else { return }
            let horizontalLimit: Float = owner.mode == .camera ? 18 : 64
            let minimumHeight: Float = owner.mode == .camera ? -1 : -12
            let maximumHeight: Float = owner.mode == .camera ? 18 : 96
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
            cachedWalkInput = .zero

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
        /// an embedded home does not emit arrival callbacks or DEBUG demo events.
        private func prepareMooredHome() {
            guard !arrivalStarted else { return }
            arrivalStarted = true
            arrivalFinished = true
            renderedMode = owner.mode
            boardingRequested = false
            departureStarted = false
            cachedWalkInput = .zero
            arrivalNavigatorIsWalking = false
            cancelStumpInteraction()

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
            cancelStumpInteraction()
            let transfer = arrivalJettyLandingPath().transfer
            navigator.removeAllActions()
            navigator.position = transfer
            navigator.scale = SCNVector3(
                NavigatorAppearance.islandScale,
                NavigatorAppearance.islandScale,
                NavigatorAppearance.islandScale
            )
            navigator.opacity = 1
            if let boatNavigator = arrivalBoatNavigator {
                let direction = boatNavigator.presentation.worldPosition - transfer
                navigator.eulerAngles.y = atan2(direction.x, direction.z)
            } else {
                navigator.eulerAngles.y = .pi
            }
            navigatorAnimator.pose = .idle
            arrivalNavigatorIsWalking = false
            cachedWalkInput = .zero
        }

        private func beginLanding() {
            guard !arrivalFinished, let navigator = navigatorNode else { return }
            let path = arrivalJettyLandingPath()
            let fallbackStart = SCNVector3(
                arrivalBoatStopPosition.x + 0.17,
                0.28,
                arrivalBoatStopPosition.z - 0.68
            )
            let transferStart = arrivalBoatNavigator?.presentation.worldPosition
                ?? fallbackStart
            let transferEnd = path.transfer
            let transferDirection = transferEnd - transferStart

            navigator.position = transferStart
            navigator.eulerAngles.y = atan2(transferDirection.x, transferDirection.z)
            navigator.scale = SCNVector3(0.57, 0.57, 0.57)
            navigator.opacity = 0
            arrivalNavigatorIsWalking = true

            let gangplank = makeArrivalGangplank(from: transferStart, to: transferEnd)
            arrivalGangplank = gangplank
            gangplank.runAction(.fadeIn(duration: 0.18))

            let fadeSailor = SCNAction.sequence([
                .wait(duration: 0.04),
                .fadeOut(duration: 0.18),
            ])
            arrivalBoatNavigator?.runAction(fadeSailor)

            let fadeNavigator = SCNAction.sequence([
                .wait(duration: 0.10),
                .fadeIn(duration: 0.18),
            ])
            let transfer = SCNAction.move(
                to: transferEnd,
                duration: ArrivalMotion.transferDuration
            )
            transfer.timingMode = .easeInEaseOut
            let growOnTransfer = SCNAction.scale(to: 0.68, duration: ArrivalMotion.transferDuration)
            growOnTransfer.timingMode = .easeInEaseOut

            let crossDeck = SCNAction.move(
                to: path.deck,
                duration: ArrivalMotion.deckWalkDuration
            )
            crossDeck.timingMode = .easeInEaseOut
            let growToIslandScale = SCNAction.scale(
                to: CGFloat(NavigatorAppearance.islandScale),
                duration: 0.62
            )
            growToIslandScale.timingMode = .easeOut

            animateArrivalCamera(
                target: SCNVector3(-0.65, 0.96, 9.7),
                azimuth: 0.77,
                elevation: 0.28,
                radius: 11.8,
                fieldOfView: 42,
                duration: ArrivalMotion.transferDuration + ArrivalMotion.deckWalkDuration
            )

            navigator.runAction(.sequence([
                .group([fadeNavigator, transfer, growOnTransfer]),
                .run { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.arrivalGangplank?.runAction(.sequence([
                            .fadeOut(duration: 0.24),
                            .removeFromParentNode(),
                        ]))
                    }
                },
                .group([crossDeck, growToIslandScale]),
                .run { [weak self] _ in
                    guard let self else { return }
                    DispatchQueue.main.async {
                        self.animateArrivalCamera(
                            target: SCNVector3(
                                path.deck.x,
                                path.deck.y + 0.72,
                                path.deck.z
                            ),
                            azimuth: self.nearestEquivalentAzimuth(to: 0.82),
                            elevation: 0.30,
                            radius: 6.8,
                            fieldOfView: 48,
                            duration: ArrivalMotion.jettySettleDuration
                        )
                    }
                },
                .wait(duration: ArrivalMotion.jettySettleDuration),
                .run { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.finishArrival()
                    }
                },
            ]))
        }

        private func arrivalJettyLandingPath() -> (
            transfer: SCNVector3,
            deck: SCNVector3
        ) {
            let fallbackCoast = HomeIslandMetrics.arrivalJettyPosition
            let surface = arrivalJettyWalkSurface
            let transferXZ = surface?.worldPosition(
                localX: HomeIslandMetrics.arrivalJettyTransferLocalX,
                localZ: HomeIslandMetrics.arrivalJettyTransferLocalZ
            ) ?? (x: fallbackCoast.x - 1.94, z: fallbackCoast.z + 3.00)
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
                : arrivalJettyLandingPath().deck
            navigatorNode?.position = destination
            navigatorNode?.eulerAngles.y = .pi
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
                let approach: SCNVector3
                if requestedSeat == "stump", let stump = self.stumpSeats.first {
                    approach = SCNVector3(
                        stump.transform.x,
                        self.groundHeight(x: stump.transform.x, z: stump.transform.z + stump.triggerRadius * 0.82),
                        stump.transform.z + stump.triggerRadius * 0.82
                    )
                } else if let slot = self.placedSeatSlots.first {
                    approach = slot.approachWorldPosition
                } else {
                    return
                }
                navigator.position = SCNVector3(
                    approach.x,
                    approach.y,
                    approach.z
                )
                let target: SCNVector3
                if requestedSeat == "stump", let stump = self.stumpSeats.first {
                    target = stump.seatPosition(
                        rootToSeatSurface: self.navigatorRootToSeatSurface
                    )
                } else if let slot = self.placedSeatSlots.first {
                    target = slot.contactWorldPosition(
                        rootToSeatSurface: self.navigatorRootToSeatSurface
                    )
                } else {
                    return
                }
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
            cachedWalkInput = .zero
            cancelStumpInteraction()
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
            DispatchQueue.main.async { [weak self] in
                self?.owner.onDepartureCompleted()
            }
        }

        private func modeDidChange(from previousMode: HomeIslandMode, to mode: HomeIslandMode) {
            switch mode {
            case .arrival:
                touchWalkInput = .zero
                keyboardWalkInput = .zero
                cachedWalkInput = .zero
                break
            case .explore:
                if !seatInteractionState.keepsNavigatorOnSeat {
                    ensureNavigatorIsWalkable()
                }
                navigatorNode?.opacity = 1
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
                cachedWalkInput = .zero
                cancelStumpInteraction()
                navigatorAnimator.pose = .idle
                navigatorNode?.opacity = 0
                resetCamera(animated: true)
            case .camera:
                touchWalkInput = .zero
                keyboardWalkInput = .zero
                cachedWalkInput = .zero
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
                cachedWalkInput = .zero
                startDeparture()
            }
        }

        private func enterExploreCamera(animated duration: TimeInterval) {
            guard let navigator = navigatorNode else { return }
            enterExploreCamera(focusing: navigator.position, animated: duration)
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
            guard let navigator = navigatorNode,
                  !isWalkable(x: navigator.position.x, z: navigator.position.z)
            else { return }
            navigator.position = safestLandingPosition()
        }

        private func isWalkable(x: Float, z: Float) -> Bool {
            let playerRadius: Float = 0.32
            let isOnSand = HomeIslandMetrics.containsWalkableSand(
                x: x,
                z: z,
                margin: 0.18
            )
            let isOnJetty = jettyWalkSurfaces.contains {
                $0.contains(x: x, z: z, playerRadius: playerRadius)
            }
            guard isOnSand || isOnJetty else { return false }
            guard jettyWalkSurfaces.allSatisfy({
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

        private func updateWalking(deltaTime: Float) -> Bool {
            guard !(owner.startsMooredAtIsland && owner.locksMooredOverview),
                  owner.mode == .explore,
                  !owner.cameraInteractionLocked,
                  !owner.boatCustomizationActive,
                  !boardingRequested,
                  let navigator = navigatorNode,
                  deltaTime > 0
            else { return false }

            let currentWalkInput = cachedWalkInput
            var lateral = currentWalkInput.x
            var forwardAmount = currentWalkInput.forward
            let magnitude = sqrt(lateral * lateral + forwardAmount * forwardAmount)
            switch seatInteractionState {
            case .seated:
                guard magnitude > 0.12 else {
                    followNavigatorCamera()
                    return false
                }
                let direction = normalizedWalkDirection(
                    lateral: lateral,
                    forward: forwardAmount
                )
                beginLeavingSeat(toward: direction)
                followNavigatorCamera()
                return false
            case .approaching, .settling, .standingUp, .leaving:
                followNavigatorCamera()
                return false
            case .free:
                break
            }
            guard magnitude > 0.035 else {
                followNavigatorCamera()
                return false
            }
            if magnitude > 1 {
                lateral /= magnitude
                forwardAmount /= magnitude
            }

            let cameraForward = SCNVector3(-cos(azimuth), 0, -sin(azimuth))
            let cameraRight = SCNVector3(sin(azimuth), 0, -cos(azimuth))
            var direction = cameraForward * forwardAmount + cameraRight * lateral
            let directionLength = sqrt(
                direction.x * direction.x + direction.z * direction.z
            )
            guard directionLength > 0.001 else { return false }
            direction.x /= directionLength
            direction.z /= directionLength

            if CACurrentMediaTime() >= contactReentryBlockedUntil,
               let seat = interactiveSeatToward(
                   navigator.position,
                   direction: direction
               ) {
                beginSitting(on: seat)
                followNavigatorCamera()
                return true
            }

            let distance = min(deltaTime, 0.05)
                * NavigatorLocomotion.maximumSpeed
                * min(magnitude, 1)
            let current = navigator.position
            let candidateX = current.x + direction.x * distance
            let candidateZ = current.z + direction.z * distance
            var nextX = current.x
            var nextZ = current.z

            if isWalkable(x: candidateX, z: candidateZ) {
                nextX = candidateX
                nextZ = candidateZ
            } else if isWalkable(x: candidateX, z: current.z) {
                nextX = candidateX
            } else if isWalkable(x: current.x, z: candidateZ) {
                nextZ = candidateZ
            }

            let moved = abs(nextX - current.x) + abs(nextZ - current.z) > 0.0001
            if moved {
                navigator.position = SCNVector3(
                    nextX,
                    groundHeight(x: nextX, z: nextZ),
                    nextZ
                )
                let movedX = nextX - current.x
                let movedZ = nextZ - current.z
                let movedLength = sqrt(movedX * movedX + movedZ * movedZ)
                let actualDirection = SCNVector3(
                    movedX / max(movedLength, 0.0001),
                    0,
                    movedZ / max(movedLength, 0.0001)
                )
                addFootprintIfNeeded(
                    at: navigator.position,
                    distance: movedLength,
                    direction: actualDirection
                )
                let desiredYaw = atan2(actualDirection.x, actualDirection.z)
                if snapFacingOnNextMovement {
                    navigator.eulerAngles.y = desiredYaw
                    snapFacingOnNextMovement = false
                } else {
                    let yawDelta = atan2(
                        sin(desiredYaw - navigator.eulerAngles.y),
                        cos(desiredYaw - navigator.eulerAngles.y)
                    )
                    navigator.eulerAngles.y += yawDelta * min(deltaTime * 12, 1)
                }
            }
            followNavigatorCamera()
            return moved
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
            var candidates = stumpSeats.compactMap { stump -> (InteractiveSeat, Float)? in
                guard !occupiedSeats.contains(stump.address) else { return nil }
                let dx = stump.transform.x - position.x
                let dz = stump.transform.z - position.z
                let distance = sqrt(dx * dx + dz * dz)
                guard distance > 0.001, distance <= stump.triggerRadius else { return nil }
                let alignment = (dx * direction.x + dz * direction.z) / distance
                guard alignment >= 0.78 else { return nil }
                return (
                    InteractiveSeat(
                        address: stump.address,
                        motion: .sit,
                        seatPosition: stump.seatPosition(
                            facing: direction,
                            rootToSeatSurface: navigatorRootToSeatSurface
                        ),
                        approachPosition: nil,
                        obstacleCenter: SCNVector3(
                            stump.transform.x,
                            HomeIslandMetrics.surfaceY,
                            stump.transform.z
                        ),
                        obstacleRadius: stump.obstacleRadius,
                        facingDirection: direction
                    ),
                    distance
                )
            }

            candidates += placedSeatSlots.compactMap { slot -> (InteractiveSeat, Float)? in
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
            let approach = SCNAction.group([
                .move(to: seat.seatPosition, duration: 0.42),
                .rotateTo(
                    x: 0,
                    y: CGFloat(targetYaw),
                    z: CGFloat(targetRoll),
                    duration: seat.motion == .lie ? 0.52 : 0.30,
                    usesShortestUnitArc: true
                ),
            ])
            approach.timingMode = .easeInEaseOut
            let settle = SCNAction.sequence([
                approach,
                .run { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self,
                              self.seatInteractionState.seat?.address == seat.address
                        else { return }
                        self.seatInteractionState = .settling(seat)
                    }
                },
                .wait(duration: seat.motion == .lie ? 0.62 : 0.52),
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

        private func cancelStumpInteraction() {
            guard seatInteractionState.keepsNavigatorOnSeat else { return }
            navigatorNode?.removeAction(forKey: "seat-transition")
            seatInteractionState = .free
            navigatorAnimator.pose = .idle
        }

        private func addFootprintIfNeeded(
            at position: SCNVector3,
            distance: Float,
            direction: SCNVector3
        ) {
            distanceSinceFootprint += distance
            let spacing: Float = 0.36
            guard distanceSinceFootprint >= spacing else { return }
            distanceSinceFootprint.formTruncatingRemainder(dividingBy: spacing)

            let isLeft = nextFootprintIsLeft
            nextFootprintIsLeft.toggle()
            let side: Float = isLeft ? -1 : 1
            let sideOffset: Float = 0.105
            let footprint = HomeIslandFootprintVisual.makeNode(leftFoot: isLeft)
            footprint.position = SCNVector3(
                position.x + direction.z * sideOffset * side,
                groundHeight(x: position.x, z: position.z) + 0.009,
                position.z - direction.x * sideOffset * side
            )
            footprint.eulerAngles.y = atan2(direction.x, direction.z)
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
                  !owner.boatCustomizationActive,
                  let navigator = navigatorNode,
                  let target = cameraTarget
            else { return }
            target.position = SCNVector3(
                navigator.position.x,
                navigator.position.y + 0.72,
                navigator.position.z
            )
        }

        private func groundHeight(x: Float, z: Float) -> Float {
            let foundationHeight = foundationGroundHeight(x: x, z: z)
            if let jetty = jettyWalkSurfaces.first(where: {
                $0.contains(x: x, z: z, playerRadius: 0.02)
            }) {
                return jetty.height(x: x, z: z, baseHeight: foundationHeight)
            }
            if HomeIslandMetrics.containsGatheringDeck(x: x, z: z) {
                return max(
                    foundationHeight,
                    HomeIslandMetrics.surfaceY
                        + HomeIslandMetrics.gatheringDeckLocalTopY
                        * HomeIslandMetrics.gatheringDeckScale
                )
            }
            return foundationHeight
        }

        private func foundationGroundHeight(x: Float, z: Float) -> Float {
            guard let scene = view?.scene, let foundationNode else {
                return HomeIslandMetrics.surfaceY
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
                return hit.worldCoordinates.y
            }
            return HomeIslandMetrics.surfaceY
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

            let deltaTime = Float(min(max(time - (lastFrameTime ?? time), 0), 0.05))
            lastFrameTime = time
            if owner.mode == .explore {
                applyPendingExploreOrbit()
            }
            let isWalking = updateWalking(deltaTime: deltaTime)
            if owner.mode == .explore,
               !owner.boatCustomizationActive {
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
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard let view else { return true }
            let point = touch.location(in: view)
            if gestureRecognizer === movementPanRecognizer {
                return touch.type == .direct && isMovementControlPoint(point, in: view)
            }
            if gestureRecognizer === orbitPanRecognizer,
               owner.mode == .explore,
               touch.type == .direct {
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
            if gestureRecognizer === twoFingerPanRecognizer {
                return owner.mode == .edit || owner.mode == .camera
            }
            if gestureRecognizer === longPressRecognizer {
                return owner.mode == .edit || owner.mode == .camera
            }
            if gestureRecognizer === doubleTapRecognizer,
               owner.mode == .explore,
               touch.type == .direct {
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
