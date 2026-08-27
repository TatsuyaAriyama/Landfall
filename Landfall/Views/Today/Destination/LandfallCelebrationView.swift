import OSLog
import SceneKit
import SwiftUI

/// 着岸の一枚。島に到達したとき全画面で出す。目標の種類に関わらず「航海した時間」を添える。
/// Web版 LandfallCelebration 相当。
struct LandfallCelebrationView: View {
    let destination: Destination
    let minutes: Int
    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealRecord = false
    @State private var showingShareCard = false

    var body: some View {
        ZStack {
            Color(VoyageSceneKit.seaDeep).ignoresSafeArea()

            LandfallArrivalSceneView()
                .ignoresSafeArea()
                .accessibilityHidden(true)

            LinearGradient(
                stops: [
                    .init(color: Color(VoyageSceneKit.seaDeep).opacity(0.18), location: 0),
                    .init(color: .clear, location: 0.42),
                    .init(color: Color(VoyageSceneKit.seaDeep).opacity(0.08), location: 0.56),
                    .init(color: Color(VoyageSceneKit.seaDeep).opacity(0.48), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GeometryReader { geometry in
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: geometry.size.height * 0.55)

                    VStack(spacing: 11) {
                        if minutes > 0 {
                            Text("Work time \(LF.duration(minutes: minutes))")
                                .font(LFFont.label(12))
                                .foregroundStyle(LFColor.harborSand.opacity(0.72))
                                .tracking(1.1)
                        }
                        Text("You arrived at \(destination.name).")
                            .font(LFFont.copy(18))
                            .foregroundStyle(LFColor.returnOrange)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                        Text("This voyage stays in your Logbook.")
                            .font(LFFont.label(13))
                            .foregroundStyle(LFColor.harborSand.opacity(0.62))
                            .padding(.top, 2)

                        if let achievedAt = destination.achievedAt {
                            Text(verbatim: LF.fullDate(achievedAt))
                                .font(LFFont.label(12))
                                .foregroundStyle(LFColor.returnOrange.opacity(0.92))
                                .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 18)

                    Spacer(minLength: 24)

                    HStack(spacing: 12) {
                        Button { showingShareCard = true } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Landfall card")
                            }
                            .font(LFFont.copy(14))
                            .foregroundStyle(LFColor.inkFixed)
                            .padding(.horizontal, 18)
                            .frame(height: 42)
                            .background(LFColor.harborSand, in: Capsule())
                        }
                        .buttonStyle(LFPressableButtonStyle())

                        Button { onClose() } label: {
                            Text("Close")
                                .font(LFFont.copy(15))
                                .foregroundStyle(LFColor.harborSand)
                                .padding(.horizontal, 22)
                                .frame(height: 42)
                                .overlay(Capsule().strokeBorder(LFColor.harborSand.opacity(0.38), lineWidth: 1))
                        }
                        .buttonStyle(LFPressableButtonStyle())
                    }
                    .padding(.bottom, 26)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 24)
            .opacity(revealRecord ? 1 : 0)
            .offset(y: revealRecord ? 0 : 18)

        }
        .task {
            if reduceMotion {
                revealRecord = true
                return
            }
            try? await Task.sleep(for: .milliseconds(1_850))
            withAnimation(.easeOut(duration: 0.55)) {
                revealRecord = true
            }
        }
        .sheet(isPresented: $showingShareCard) {
            LandfallShareSheet(destination: destination, minutes: minutes)
        }
        .accessibilityElement(children: .contain)
    }
}

/// 航海中のSceneKit世界をそのまま浜へつなぐ上陸演出。
/// 船の接岸、視点のドリー、船上から浜への航海士の移動を同じシーン内で行う。
private struct LandfallArrivalSceneView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = VoyageSceneKit.makeLandfallScene(
            nativeMetalRollout: .entryExperience
        )
        view.backgroundColor = VoyageSceneKit.nightBG
        view.antialiasingMode = .multisampling4X
        view.contentScaleFactor = min(UIScreen.main.scale, 2)
        view.preferredFramesPerSecond = min(120, UIScreen.main.maximumFramesPerSecond)
        view.autoenablesDefaultLighting = false
        view.isUserInteractionEnabled = false
        view.pointOfView = view.scene?.rootNode.childNode(withName: "camera", recursively: false)
        view.delegate = context.coordinator
        context.coordinator.attach(
            to: view,
            reduceMotion: UIAccessibility.isReduceMotionEnabled
        )
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        view.delegate = nil
        view.scene?.rootNode.removeAllActions()
        view.isPlaying = false
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        private weak var view: SCNView?
        private weak var seaMaterial: SCNMaterial?
        private var framePacing = MetalOceanFramePacingMonitor()
        private var hasReducedRenderingQuality = false
        private let performanceLogger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "Landfall",
            category: "MetalOceanPerformance"
        )

        func attach(to view: SCNView, reduceMotion: Bool) {
            self.view = view
            seaMaterial = view.scene?.rootNode
                .childNode(withName: HomeIslandOceanEffects.surfaceNodeName, recursively: true)?
                .geometry?.firstMaterial
            framePacing.reset()
            guard let scene = view.scene,
                  let travel = scene.rootNode.childNode(withName: "landfallTravel", recursively: false),
                  let camera = scene.rootNode.childNode(withName: "camera", recursively: false) else { return }

            let boatNavigator = travel.childNode(withName: "landfallBoatNavigator", recursively: true)
            let shoreNavigator = scene.rootNode.childNode(
                withName: "landfallShoreNavigator",
                recursively: true
            )
            let boatBob = travel.childNode(withName: "landfallBoatBob", recursively: false)
            let finalTravelPosition = travel.position
            let finalCameraPosition = camera.position

            if reduceMotion {
                boatNavigator?.opacity = 0
                shoreNavigator?.opacity = 1
                view.rendersContinuously = false
                view.isPlaying = false
                view.setNeedsDisplay()
                return
            }

            travel.position = SCNVector3(-4.65, 0.025, 0.72)
            camera.position = SCNVector3(-9.1, 5.25, 15.4)
            boatNavigator?.opacity = 1
            shoreNavigator?.opacity = 0
            view.rendersContinuously = true
            view.isPlaying = true

            let rise = SCNAction.moveBy(x: 0, y: 0.045, z: 0, duration: 0.38)
            rise.timingMode = .easeInEaseOut
            boatBob?.runAction(.repeatForever(.sequence([rise, rise.reversed()])), forKey: "approachBob")

            let approach = SCNAction.move(to: finalTravelPosition, duration: 1.65)
            approach.timingMode = .easeInEaseOut
            let settle = SCNAction.run { _ in
                boatBob?.removeAction(forKey: "approachBob")
                boatBob?.runAction(.move(to: SCNVector3Zero, duration: 0.28))
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.52
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                boatNavigator?.opacity = 0
                shoreNavigator?.opacity = 1
                SCNTransaction.commit()
            }
            travel.runAction(.sequence([.wait(duration: 0.12), approach, settle]), forKey: "landfallApproach")

            let dolly = SCNAction.move(to: finalCameraPosition, duration: 2.25)
            dolly.timingMode = .easeInEaseOut
            camera.runAction(.sequence([.wait(duration: 0.08), dolly]), forKey: "landfallDolly")
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard seaMaterial?.program != nil, framePacing.observe(at: time) else { return }
            reduceRenderingQualityIfNeeded()
        }

        private func reduceRenderingQualityIfNeeded() {
            guard !hasReducedRenderingQuality else { return }
            hasReducedRenderingQuality = true
#if DEBUG
            print("[MetalOceanPerformance] Landfall overload detected")
#endif
            DispatchQueue.main.async { [weak self] in
                guard let self, let view = self.view else { return }
                view.antialiasingMode = .multisampling2X
                self.performanceLogger.notice(
                    "Reduced landfall ocean antialiasing after frame pacing pressure"
                )
            }
        }
    }
}
