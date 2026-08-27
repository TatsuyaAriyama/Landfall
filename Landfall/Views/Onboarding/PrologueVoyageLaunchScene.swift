import Foundation
import SceneKit
import SwiftUI
import UIKit

/// 序章の最後から、タイマーの「航海中」と同じ世界へ連続して入る3D遷移。
/// 背景画像や動画は使わず、既存の航海SceneKit世界とコード生成の航跡だけで描画する。
struct PrologueVoyageLaunchSceneView: UIViewRepresentable {
    var showIsland: Bool
    var date: Date
    var duration: TimeInterval
    var onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        showIsland: Bool = false,
        date: Date = .now,
        duration: TimeInterval = 3.65,
        onComplete: @escaping () -> Void
    ) {
        self.showIsland = showIsland
        self.date = date
        self.duration = duration
        self.onComplete = onComplete
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = PrologueVoyageLaunchSceneFactory.makeScene(
            showIsland: showIsland,
            date: date
        )
        view.pointOfView = view.scene?.rootNode.childNode(
            withName: PrologueVoyageLaunchSceneFactory.cameraName,
            recursively: false
        )
        view.backgroundColor = (view.scene?.background.contents as? UIColor)
            ?? VoyageSceneKit.nightBG
        view.isOpaque = true
        view.antialiasingMode = .multisampling2X
        view.contentScaleFactor = min(UIScreen.main.scale, 2)
        view.preferredFramesPerSecond = 30
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.isUserInteractionEnabled = false
        view.accessibilityIdentifier = "prologue-voyage-launch-transition"
        view.accessibilityElementsHidden = true
        view.delegate = context.coordinator

        context.coordinator.install(
            on: view,
            duration: duration,
            reduceMotion: reduceMotion || UIAccessibility.isReduceMotionEnabled,
            onComplete: onComplete
        )
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.update(
            duration: duration,
            reduceMotion: reduceMotion || UIAccessibility.isReduceMotionEnabled,
            onComplete: onComplete
        )
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        view.delegate = nil
        view.isPlaying = false
        view.rendersContinuously = false
        // 新しいrenderer callbackを止めたあと、Coordinatorのlockで
        // 実行中のcallbackの終了を待ってからsceneを外す。
        coordinator.stop()
        view.scene = nil
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        private enum Phase {
            case ready
            case running
            case settleRequested
            case finishing
            case completed
            case stopped
        }

        /// SceneKitノードとPhoenixAnimatorはrenderer callback中だけ書き換える。
        /// main側のReduce Motion更新と破棄はこのlock経由で受け渡し、
        /// callback実行中の参照やノード更新との競合を防ぐ。
        private let mutationLock = NSLock()
        private var phase: Phase = .ready

        private weak var view: SCNView?
        private weak var scene: SCNScene?
        private weak var travel: SCNNode?
        private weak var boatBob: SCNNode?
        private weak var wake: SCNNode?
        private weak var camera: SCNNode?
        private weak var stars: SCNNode?
        private weak var gullRoot: SCNNode?
        private weak var approachingIsland: SCNNode?

        private var gulls: [SCNNode] = []
        private var duration: TimeInterval = 3.65
        private var onComplete: () -> Void = {}
        private var startTime: TimeInterval?
        private var lastTime: TimeInterval = 0
        private var completionWorkItem: DispatchWorkItem?

        private var startTravelPosition = SCNVector3Zero
        private var finalTravelPosition = SCNVector3Zero
        private var startTravelScale = SCNVector3(0.43, 0.43, 0.43)
        private var finalTravelScale = SCNVector3(0.55, 0.55, 0.55)
        private var startTravelYaw: Float = -0.08
        private var finalTravelYaw: Float = 0.10
        private var startCameraPosition = SCNVector3Zero
        private var finalCameraPosition = SCNVector3(-5.6, 2.4, 8.6)
        private let startCameraTarget = SCNVector3(0.18, 0.96, 0)
        private let finalCameraTarget = SCNVector3(0.8, 1.15, 0)
        private var finalFieldOfView: CGFloat = 38

        private var sailor = PhoenixAnimator()
        private let flock: [(radius: Float, height: Float, omega: Float, flap: Float, phase: Float)] = [
            (4.2, 2.3, 0.085, 2.1, 0.0), (5.0, 2.8, -0.065, 1.7, 0.8),
            (4.6, 2.0, 0.11, 2.5, 1.6), (5.6, 3.2, 0.055, 1.6, 2.4),
            (3.9, 2.6, -0.1, 2.3, 3.2), (6.0, 2.2, 0.07, 1.9, 4.0),
            (5.2, 3.5, -0.05, 1.5, 4.8), (4.4, 3.0, 0.095, 2.2, 5.6),
            (6.6, 2.5, -0.045, 1.8, 6.1), (3.6, 3.3, 0.125, 2.6, 2.0),
        ]

        func install(
            on view: SCNView,
            duration: TimeInterval,
            reduceMotion: Bool,
            onComplete: @escaping () -> Void
        ) {
            mutationLock.lock()
            self.view = view
            scene = view.scene
            self.duration = max(duration, 0.01)
            self.onComplete = onComplete
            bindNodes()
            prepareEndpoints()

            if reduceMotion {
                if let scene {
                    settleAtVoyageFrame(scene: scene)
                }
                phase = .finishing
                mutationLock.unlock()
                view.isPlaying = false
                view.rendersContinuously = false
                view.setNeedsDisplay()
                scheduleCompletion(after: 0.22)
            } else {
                applyTransition(progress: 0)
                phase = .running
                mutationLock.unlock()
                view.rendersContinuously = true
                view.isPlaying = true
            }
        }

        func update(
            duration: TimeInterval,
            reduceMotion: Bool,
            onComplete: @escaping () -> Void
        ) {
            mutationLock.lock()
            self.duration = max(duration, 0.01)
            self.onComplete = onComplete
            let shouldRequestSettle = reduceMotion && phase == .running
            if shouldRequestSettle {
                // 実行中のsceneをmain threadから書き換えず、次の
                // renderer callbackに最終frameの適用を任せる。
                phase = .settleRequested
            }
            mutationLock.unlock()

            if shouldRequestSettle {
                // 次の30fps callbackが要求を必ず回収できるようにする。
                view?.rendersContinuously = true
                view?.isPlaying = true
            }
        }

        func stop() {
            completionWorkItem?.cancel()
            completionWorkItem = nil

            // dismantle側がdelegate/連続描画を先に止める。このlockは
            // 既に始まったrenderer callbackがあれば、その終了を待つ。
            mutationLock.lock()
            phase = .stopped
            sailor.animate = false
            gulls.removeAll()
            view = nil
            scene = nil
            mutationLock.unlock()
        }

        private func bindNodes() {
            guard let root = scene?.rootNode else { return }
            travel = root.childNode(withName: "travel", recursively: false)
            boatBob = root.childNode(withName: "boatBob", recursively: true)
            wake = root.childNode(
                withName: PrologueVoyageLaunchSceneFactory.wakeName,
                recursively: true
            )
            camera = root.childNode(
                withName: PrologueVoyageLaunchSceneFactory.cameraName,
                recursively: false
            )
            stars = root.childNode(
                withName: PrologueVoyageLaunchSceneFactory.starsName,
                recursively: false
            )
            gullRoot = root.childNode(withName: "gulls", recursively: false)
            gulls = gullRoot?.childNodes ?? []
            approachingIsland = root.childNode(
                withName: "approachingIsland",
                recursively: false
            )
            if let scene {
                sailor.bindIfNeeded(scene)
            }
        }

        private func prepareEndpoints() {
            guard let scene, let travel, let camera else { return }
            finalTravelPosition = travel.position
            finalTravelScale = travel.scale
            finalTravelYaw = travel.eulerAngles.y
            finalCameraPosition = camera.position
            finalFieldOfView = camera.camera?.fieldOfView ?? 38

            // camera local -Xは画面左。portraitの狭い水平画角でも船全体が
            // 確実にフレーム外へ出る距離を、現在のカメラ姿勢からworldへ変換する。
            let entryOffset = camera.convertVector(
                SCNVector3(-4.8, -0.18, -1.15),
                to: scene.rootNode
            )
            startTravelPosition = add(finalTravelPosition, entryOffset)
            startTravelScale = multiply(finalTravelScale, 0.78)
            startTravelYaw = finalTravelYaw - 0.20

            let cameraOffset = camera.convertVector(
                SCNVector3(-0.24, 0.26, 1.16),
                to: scene.rootNode
            )
            startCameraPosition = add(finalCameraPosition, cameraOffset)

            // タイマー開始直後と同じ、遠方の島の初期位置。
            approachingIsland?.position = SCNVector3(14.3, 0, -12.1)
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            var shouldComplete = false
            mutationLock.lock()
            defer {
                mutationLock.unlock()
                if shouldComplete {
                    DispatchQueue.main.async { [weak self] in
                        self?.completeOnMain()
                    }
                }
            }

            guard phase == .running || phase == .settleRequested, let scene else { return }

            if phase == .settleRequested {
                settleAtVoyageFrame(scene: scene)
                phase = .finishing
                shouldComplete = true
                return
            }

            if startTime == nil {
                startTime = time
                lastTime = time
            }
            let elapsed = max(time - (startTime ?? time), 0)
            let delta = Float(min(max(time - lastTime, 0), 0.1))
            let progress = Float(min(max(elapsed / duration, 0), 1))
            lastTime = time

            applyTransition(progress: progress)
            animateVoyageWorld(
                time: Float(elapsed),
                delta: delta,
                progress: progress,
                scene: scene
            )

            if progress >= 1 {
                // phaseのtest-and-setするため、終端settleとcompletion通知は
                // 後続frameが来ても一度しか実行されない。
                settleAtVoyageFrame(scene: scene)
                phase = .finishing
                shouldComplete = true
            }
        }

        private func applyTransition(progress: Float) {
            let boatProgress = easeOutCubic(clamp(progress / 0.78))
            let cameraProgress = smoothstep(clamp((progress - 0.08) / 0.92))
            let worldReveal = smoothstep(clamp(progress / 0.58))

            travel?.position = interpolate(startTravelPosition, finalTravelPosition, boatProgress)
            travel?.scale = interpolate(startTravelScale, finalTravelScale, boatProgress)
            travel?.eulerAngles.y = interpolate(startTravelYaw, finalTravelYaw, boatProgress)
            travel?.eulerAngles.z = -0.055 * (1 - boatProgress)

            if let camera {
                camera.position = interpolate(
                    startCameraPosition,
                    finalCameraPosition,
                    cameraProgress
                )
                camera.camera?.fieldOfView = interpolate(
                    finalFieldOfView + 5,
                    finalFieldOfView,
                    CGFloat(cameraProgress)
                )
                let target = interpolate(
                    startCameraTarget,
                    finalCameraTarget,
                    cameraProgress
                )
                camera.look(
                    at: target,
                    up: SCNVector3(0, 1, 0),
                    localFront: SCNVector3(0, 0, -1)
                )
            }

            stars?.opacity = CGFloat(0.12 + worldReveal * 0.88)
            gullRoot?.opacity = CGFloat(smoothstep(clamp((progress - 0.28) / 0.62)))
            approachingIsland?.opacity = CGFloat(0.22 + worldReveal * 0.78)

            if let scene {
                scene.fogStartDistance = interpolate(4, 12, CGFloat(worldReveal))
                scene.fogEndDistance = interpolate(18, 34, CGFloat(worldReveal))
            }
        }

        private func animateVoyageWorld(
            time: Float,
            delta: Float,
            progress: Float,
            scene: SCNScene,
            sailorPose: PhoenixPose? = nil
        ) {
            if let boatBob {
                boatBob.position.y = sin(time * 0.8) * 0.06
                boatBob.eulerAngles.z = sin(time * 0.6) * 0.03
                boatBob.eulerAngles.x = sin(time * 0.5 + 1.2) * 0.015
                boatBob.childNode(withName: "boatFlag", recursively: true)?
                    .eulerAngles.y = sin(time * 5.2) * 0.22
            }

            let wakeReveal = smoothstep(clamp((progress - 0.16) / 0.54))
            wake?.opacity = CGFloat((0.34 + sin(time * 1.4) * 0.07) * wakeReveal)

            for (index, bird) in gulls.enumerated() {
                guard flock.indices.contains(index) else { continue }
                let config = flock[index]
                let angle = config.phase + time * config.omega
                bird.position = SCNVector3(
                    cos(angle) * config.radius,
                    config.height + sin(time * 0.4 + config.phase) * 0.22,
                    sin(angle) * config.radius
                )
                let velocityX = -sin(angle) * config.omega
                let velocityZ = cos(angle) * config.omega
                bird.eulerAngles.y = atan2(-velocityX, -velocityZ)
                bird.eulerAngles.z = config.omega > 0 ? -0.18 : 0.18
                let wingBeat = -0.22 + sin(time * config.flap + config.phase) * 0.34
                bird.childNode(withName: "leftWing", recursively: false)?
                    .eulerAngles.z = wingBeat
                bird.childNode(withName: "rightWing", recursively: false)?
                    .eulerAngles.z = -wingBeat
            }

            sailor.bindIfNeeded(scene)
            if let sailorPose {
                sailor.pose = sailorPose
            } else if progress < 0.30 {
                sailor.pose = .raise
            } else if progress > 0.86 {
                // 通常VoyagingHomeAnimatorのt=0はneutralから選択poseへdampする。
                // handoff直前も同じneutralへ戻し、別SCNScene生成時の姿勢jumpを消す。
                sailor.pose = .idle
            } else {
                sailor.pose = PhoenixPose.selected
            }
            sailor.step(t: time, dt: delta)
        }

        private func settleAtVoyageFrame(scene: SCNScene) {
            applyTransition(progress: 1)

            // 減衰8stepは呼吸/視線phaseも進めるため、新規sceneのt=0と
            // わずかにずれる。通常VoyagingHomeAnimatorと同じfreshな内部状態で
            // selected poseのt=0を一度だけ適用し、全ノードを完全に揃える。
            sailor.animate = false
            sailor = PhoenixAnimator()
            animateVoyageWorld(
                time: 0,
                delta: 0,
                progress: 1,
                scene: scene,
                sailorPose: PhoenixPose.selected
            )
        }

        private func scheduleCompletion(after delay: TimeInterval) {
            mutationLock.lock()
            let shouldSchedule = phase == .finishing
            mutationLock.unlock()
            guard shouldSchedule else { return }
            completionWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.completeOnMain()
            }
            completionWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        /// completionのtest-and-setは必ずmain queueのこの一点だけで行う。
        /// renderer完了とReduce Motion切替が同じframeで競合しても一度しか通知しない。
        private func completeOnMain() {
            dispatchPrecondition(condition: .onQueue(.main))
            mutationLock.lock()
            guard phase == .finishing else {
                mutationLock.unlock()
                return
            }
            phase = .completed
            let completion = onComplete
            mutationLock.unlock()

            completionWorkItem?.cancel()
            completionWorkItem = nil
            view?.isPlaying = false
            view?.rendersContinuously = false
            completion()
        }

        private func clamp(_ value: Float) -> Float {
            min(max(value, 0), 1)
        }

        private func smoothstep(_ value: Float) -> Float {
            value * value * (3 - 2 * value)
        }

        private func easeOutCubic(_ value: Float) -> Float {
            1 - pow(1 - value, 3)
        }

        private func interpolate(_ from: Float, _ to: Float, _ amount: Float) -> Float {
            from + (to - from) * amount
        }

        private func interpolate(_ from: CGFloat, _ to: CGFloat, _ amount: CGFloat) -> CGFloat {
            from + (to - from) * amount
        }

        private func interpolate(
            _ from: SCNVector3,
            _ to: SCNVector3,
            _ amount: Float
        ) -> SCNVector3 {
            SCNVector3(
                interpolate(from.x, to.x, amount),
                interpolate(from.y, to.y, amount),
                interpolate(from.z, to.z, amount)
            )
        }

        private func add(_ lhs: SCNVector3, _ rhs: SCNVector3) -> SCNVector3 {
            SCNVector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
        }

        private func multiply(_ vector: SCNVector3, _ scalar: Float) -> SCNVector3 {
            SCNVector3(vector.x * scalar, vector.y * scalar, vector.z * scalar)
        }
    }
}

private enum PrologueVoyageLaunchSceneFactory {
    static let cameraName = "camera"
    static let starsName = "prologueVoyageStars"
    static let wakeName = "wake"

    static func makeScene(showIsland: Bool, date: Date) -> SCNScene {
        // 終端をタイマーと同一にするため、航海中の共通Sceneをそのまま土台にする。
        let scene = VoyageSceneKit.makeVoyagingScene(
            showIsland: showIsland,
            timeOfDay: .night,
            date: date,
            nativeMetalRollout: .entryExperience
        )

        if let stars = scene.rootNode.childNodes.first(where: { node in
            guard let geometry = node.geometry, geometry.elementCount > 0 else {
                return false
            }
            return geometry.element(at: 0).primitiveType == .point
        }) {
            stars.name = starsName
        }

        // 共通makeWake自体が頂点alphaのprocedural geometryなので、通常画面への
        // handoff後もnode名・形状・opacityがそのまま一致する。
        return scene
    }
}
