import SceneKit
import SwiftUI
import UIKit

/// Home-island buildings that open into a dedicated, fully enclosed world.
enum HomeIslandInteriorKind: String, Identifiable {
    case weatheredCottage = "weathered_cottage"
    case navigatorTent = "navigator_tent"

    var id: String { rawValue }

    init?(assetID: String) {
        self.init(rawValue: assetID)
    }

    var title: String {
        switch self {
        case .weatheredCottage: String(localized: "Inside the Weathered Cottage")
        case .navigatorTent: String(localized: "Inside the Navigator's Tent")
        }
    }

    var subtitle: String {
        switch self {
        case .weatheredCottage: String(localized: "A quiet room kept warm by the old hearth")
        case .navigatorTent: String(localized: "Charts, supplies, and a lantern for the next voyage")
        }
    }

    fileprivate var spawn: SCNVector3 {
        switch self {
        case .weatheredCottage: SCNVector3(0, 1.56, 2.62)
        case .navigatorTent: SCNVector3(0, 1.54, 2.55)
        }
    }

    fileprivate var walkBounds: InteriorWalkBounds {
        switch self {
        case .weatheredCottage:
            InteriorWalkBounds(minX: -4.42, maxX: 4.42, minZ: -3.30, maxZ: 3.22)
        case .navigatorTent:
            InteriorWalkBounds(minX: -3.62, maxX: 3.62, minZ: -3.30, maxZ: 3.18)
        }
    }

    fileprivate var obstacles: [InteriorObstacle] {
        switch self {
        case .weatheredCottage:
            [
                InteriorObstacle(minX: -4.02, maxX: -2.15, minZ: -0.25, maxZ: 2.10),
                InteriorObstacle(minX: -4.10, maxX: -2.05, minZ: -3.38, maxZ: -2.48),
                InteriorObstacle(minX: 0.55, maxX: 3.10, minZ: -3.38, maxZ: -1.35),
                InteriorObstacle(minX: 4.02, maxX: 4.45, minZ: -1.90, maxZ: 1.22),
            ]
        case .navigatorTent:
            [
                InteriorObstacle(minX: 0.45, maxX: 3.05, minZ: -3.22, maxZ: -1.08),
                InteriorObstacle(minX: -3.25, maxX: -1.52, minZ: -2.20, maxZ: -1.08),
                InteriorObstacle(minX: 2.38, maxX: 3.48, minZ: 0.98, maxZ: 2.12),
            ]
        }
    }
}

struct HomeIslandInteriorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var walkInput = HomeIslandWalkInput.zero
    @State private var revealed = false

    let kind: HomeIslandInteriorKind

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            HomeIslandInteriorSceneView(
                kind: kind,
                walkInput: walkInput,
                onExitRequested: exitInterior
            )
            .ignoresSafeArea()
            .opacity(revealed ? 1 : 0.01)

            LinearGradient(
                colors: [.black.opacity(0.42), .clear, .black.opacity(0.22)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button(action: exitInterior) {
                        Image(systemName: "door.left.hand.open")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.46), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .accessibilityLabel(Text("Leave interior"))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: kind.title)
                            .font(LFFont.copy(16))
                            .foregroundStyle(.white)
                        Text(verbatim: kind.subtitle)
                            .font(LFFont.label(10))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(.black.opacity(0.42), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.13), lineWidth: 1))

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .safeAreaPadding(.top, 8)

                Spacer()

                HStack(alignment: .bottom) {
                    InteriorMovementPad(input: $walkInput)

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 6) {
                        #if targetEnvironment(simulator)
                        Label("WASD / Arrow keys to walk", systemImage: "keyboard")
                        #endif
                        Label("Drag to look around", systemImage: "move.3d")
                        Label("Tap the door to leave", systemImage: "door.left.hand.open")
                    }
                    .font(LFFont.label(10))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.black.opacity(0.40), in: RoundedRectangle(cornerRadius: 13))
                    .allowsHitTesting(false)
                }
                .padding(.horizontal, 18)
                .safeAreaPadding(.bottom, 18)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.45)) {
                revealed = true
            }
        }
        .onDisappear { walkInput = .zero }
    }

    private func exitInterior() {
        walkInput = .zero
        Haptics.tap(.light)
        dismiss()
    }
}

private struct InteriorMovementPad: View {
    @Binding var input: HomeIslandWalkInput
    @State private var knobOffset = CGSize.zero

    private let diameter: CGFloat = 112
    private let travelRadius: CGFloat = 35

    var body: some View {
        ZStack {
            Circle().fill(.black.opacity(0.40))
            Circle().stroke(.white.opacity(0.17), lineWidth: 1)
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 1)
                .frame(width: 67, height: 67)
            Image(systemName: "arrow.up")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.38))
                .offset(y: -43)
            Circle()
                .fill(Color(uiColor: VoyageSceneKit.sand).opacity(0.92))
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.82))
                }
                .shadow(color: .black.opacity(0.26), radius: 8, y: 4)
                .offset(knobOffset)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    let length = max(sqrt(dx * dx + dy * dy), 0.001)
                    let scale = min(1, travelRadius / length)
                    let clampedX = dx * scale
                    let clampedY = dy * scale
                    knobOffset = CGSize(width: clampedX, height: clampedY)
                    input = HomeIslandWalkInput(
                        x: Float(clampedX / travelRadius),
                        forward: Float(-clampedY / travelRadius)
                    )
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
                        knobOffset = .zero
                    }
                    input = .zero
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Walk around inside"))
        .accessibilityHint(Text("Drag in the direction you want to walk"))
    }
}

private final class InteriorInteractiveSceneView: SCNView {
    var keyboardMovementHandler: ((HomeIslandWalkInput) -> Void)?

    private var heldMovementKeys: Set<UIKeyboardHIDUsage> = []

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { becomeFirstResponder() } else { clearKeyboardInput() }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let movementKeys = Set(presses.compactMap(\.key?.keyCode).filter(isMovementKey))
        guard !movementKeys.isEmpty else {
            super.pressesBegan(presses, with: event)
            return
        }
        heldMovementKeys.formUnion(movementKeys)
        publishKeyboardInput()
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
            true
        default:
            false
        }
    }

    private func releaseMovementKeys(from presses: Set<UIPress>) {
        for press in presses {
            if let key = press.key?.keyCode { heldMovementKeys.remove(key) }
        }
        publishKeyboardInput()
    }

    private func clearKeyboardInput() {
        heldMovementKeys.removeAll()
        keyboardMovementHandler?(.zero)
    }

    private func publishKeyboardInput() {
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
        keyboardMovementHandler?(input)
    }
}

private struct HomeIslandInteriorSceneView: UIViewRepresentable {
    let kind: HomeIslandInteriorKind
    var walkInput: HomeIslandWalkInput
    var onExitRequested: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(owner: self)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = InteriorInteractiveSceneView(frame: .zero)
        view.backgroundColor = kind == .weatheredCottage
            ? UIColor(rgb: 0x211C18)
            : UIColor(rgb: 0x172F2B)
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
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
        private var owner: HomeIslandInteriorSceneView
        private weak var view: SCNView?
        private let cameraNode = SCNNode()
        private var touchInput = HomeIslandWalkInput.zero
        private var keyboardInput = HomeIslandWalkInput.zero
        private var yaw: Float = 0
        private var pitch: Float = -0.04
        private var panStartYaw: Float = 0
        private var panStartPitch: Float = 0
        private var initialFieldOfView: CGFloat = 64
        private var lastFrameTime: TimeInterval?
        private var walkingPhase: Float = 0

        init(owner: HomeIslandInteriorSceneView) {
            self.owner = owner
            touchInput = owner.walkInput
        }

        func install(in view: SCNView) {
            self.view = view
            view.scene = InteriorSceneBuilder.makeScene(kind: owner.kind)

            let camera = SCNCamera()
            camera.fieldOfView = 64
            camera.zNear = 0.025
            camera.zFar = 120
            camera.wantsHDR = true
            camera.exposureOffset = owner.kind == .weatheredCottage ? -0.28 : -0.18
            camera.bloomIntensity = 0.28
            camera.bloomThreshold = 0.72
            camera.vignettingIntensity = 0.24
            camera.vignettingPower = 0.62
            cameraNode.name = "interior-first-person-camera"
            cameraNode.camera = camera
            cameraNode.position = owner.kind.spawn
            view.scene?.rootNode.addChildNode(cameraNode)
            view.pointOfView = cameraNode
            updateCameraOrientation()

            if let interactiveView = view as? InteriorInteractiveSceneView {
                interactiveView.keyboardMovementHandler = { [weak self] input in
                    self?.keyboardInput = input
                }
            }

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleLook(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            view.addGestureRecognizer(pan)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            view.addGestureRecognizer(pinch)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.delegate = self
            view.addGestureRecognizer(tap)

            let reset = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            reset.numberOfTapsRequired = 2
            tap.require(toFail: reset)
            view.addGestureRecognizer(reset)
        }

        func update(owner: HomeIslandInteriorSceneView) {
            self.owner = owner
            touchInput = owner.walkInput
        }

        @objc private func handleLook(_ recognizer: UIPanGestureRecognizer) {
            guard let view else { return }
            view.becomeFirstResponder()
            let translation = recognizer.translation(in: view)
            switch recognizer.state {
            case .began:
                panStartYaw = yaw
                panStartPitch = pitch
            case .changed:
                yaw = panStartYaw - Float(translation.x) * 0.0052
                pitch = min(max(panStartPitch - Float(translation.y) * 0.0043, -0.92), 0.86)
                updateCameraOrientation()
            default:
                break
            }
        }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began:
                initialFieldOfView = cameraNode.camera?.fieldOfView ?? 64
            case .changed:
                cameraNode.camera?.fieldOfView = min(
                    max(initialFieldOfView / recognizer.scale, 46),
                    78
                )
            default:
                break
            }
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view else { return }
            let hits = view.hitTest(
                recognizer.location(in: view),
                options: [.searchMode: SCNHitTestSearchMode.all.rawValue]
            )
            for hit in hits {
                var candidate: SCNNode? = hit.node
                while let node = candidate {
                    if node.name?.hasPrefix("interior-exit") == true {
                        DispatchQueue.main.async { [weak self] in self?.owner.onExitRequested() }
                        return
                    }
                    candidate = node.parent
                }
            }
        }

        @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            yaw = 0
            pitch = -0.04
            cameraNode.position = owner.kind.spawn
            cameraNode.camera?.fieldOfView = 64
            updateCameraOrientation()
            Haptics.tap(.light)
        }

        private func updateCameraOrientation() {
            cameraNode.eulerAngles = SCNVector3(pitch, yaw, 0)
        }

        private func combinedWalkInput() -> HomeIslandWalkInput {
            var input = HomeIslandWalkInput(
                x: touchInput.x + keyboardInput.x,
                forward: touchInput.forward + keyboardInput.forward
            )
            let magnitude = sqrt(input.x * input.x + input.forward * input.forward)
            if magnitude > 1 {
                input.x /= magnitude
                input.forward /= magnitude
            }
            return input
        }

        private func moveCamera(deltaTime: Float) {
            let input = combinedWalkInput()
            let magnitude = sqrt(input.x * input.x + input.forward * input.forward)
            guard magnitude > 0.025 else {
                cameraNode.position.y += (owner.kind.spawn.y - cameraNode.position.y) * min(deltaTime * 9, 1)
                return
            }

            let forward = SCNVector3(-sin(yaw), 0, -cos(yaw))
            let right = SCNVector3(cos(yaw), 0, -sin(yaw))
            var direction = forward * input.forward + right * input.x
            let directionLength = max(sqrt(direction.x * direction.x + direction.z * direction.z), 0.001)
            direction.x /= directionLength
            direction.z /= directionLength

            let distance = min(deltaTime, 0.05) * 1.78 * min(magnitude, 1)
            let current = cameraNode.position
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

            walkingPhase += distance * 7.4
            let bob = UIAccessibility.isReduceMotionEnabled ? 0 : sin(walkingPhase) * 0.018
            cameraNode.position = SCNVector3(nextX, owner.kind.spawn.y + bob, nextZ)
        }

        private func isWalkable(x: Float, z: Float) -> Bool {
            let margin: Float = 0.23
            let bounds = owner.kind.walkBounds
            guard x >= bounds.minX + margin,
                  x <= bounds.maxX - margin,
                  z >= bounds.minZ + margin,
                  z <= bounds.maxZ - margin
            else { return false }
            return owner.kind.obstacles.allSatisfy { !$0.contains(x: x, z: z, margin: margin) }
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let deltaTime = Float(min(max(time - (lastFrameTime ?? time), 0), 0.05))
            lastFrameTime = time
            moveCamera(deltaTime: deltaTime)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer is UIPinchGestureRecognizer
                || otherGestureRecognizer is UIPinchGestureRecognizer
        }
    }
}

private struct InteriorWalkBounds {
    let minX: Float
    let maxX: Float
    let minZ: Float
    let maxZ: Float
}

private struct InteriorObstacle {
    let minX: Float
    let maxX: Float
    let minZ: Float
    let maxZ: Float

    func contains(x: Float, z: Float, margin: Float) -> Bool {
        x >= minX - margin && x <= maxX + margin
            && z >= minZ - margin && z <= maxZ + margin
    }
}

private enum InteriorSceneBuilder {
    static func makeScene(kind: HomeIslandInteriorKind) -> SCNScene {
        let scene = SCNScene()
        switch kind {
        case .weatheredCottage:
            buildCottage(in: scene)
        case .navigatorTent:
            buildTent(in: scene)
        }
        return scene
    }

    private static func material(
        _ color: UInt32,
        roughness: CGFloat = 0.94,
        metalness: CGFloat = 0,
        emission: UInt32? = nil,
        emissionIntensity: CGFloat = 0
    ) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(rgb: UInt(color))
        material.roughness.contents = roughness
        material.metalness.contents = metalness
        if let emission {
            material.emission.contents = UIColor(rgb: UInt(emission))
            material.emission.intensity = emissionIntensity
        }
        return material
    }

    @discardableResult
    private static func addBox(
        to parent: SCNNode,
        name: String,
        size: SCNVector3,
        position: SCNVector3,
        material: SCNMaterial,
        chamfer: CGFloat = 0.025,
        eulerAngles: SCNVector3 = SCNVector3Zero
    ) -> SCNNode {
        let geometry = SCNBox(
            width: CGFloat(size.x),
            height: CGFloat(size.y),
            length: CGFloat(size.z),
            chamferRadius: chamfer
        )
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.name = name
        node.position = position
        node.eulerAngles = eulerAngles
        parent.addChildNode(node)
        return node
    }

    @discardableResult
    private static func addCylinder(
        to parent: SCNNode,
        name: String,
        radius: CGFloat,
        height: CGFloat,
        position: SCNVector3,
        material: SCNMaterial,
        eulerAngles: SCNVector3 = SCNVector3Zero
    ) -> SCNNode {
        let geometry = SCNCylinder(radius: radius, height: height)
        geometry.radialSegmentCount = 12
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        node.name = name
        node.position = position
        node.eulerAngles = eulerAngles
        parent.addChildNode(node)
        return node
    }

    private static func addAmbientLight(to root: SCNNode, color: UInt32, intensity: CGFloat) {
        let node = SCNNode()
        node.light = SCNLight()
        node.light?.type = .ambient
        node.light?.color = UIColor(rgb: UInt(color))
        node.light?.intensity = intensity
        root.addChildNode(node)
    }

    private static func addOmniLight(
        to root: SCNNode,
        name: String,
        color: UInt32,
        intensity: CGFloat,
        position: SCNVector3,
        radius: CGFloat
    ) -> SCNNode {
        let node = SCNNode()
        node.name = name
        node.light = SCNLight()
        node.light?.type = .omni
        node.light?.color = UIColor(rgb: UInt(color))
        node.light?.intensity = intensity
        node.light?.attenuationStartDistance = 0.4
        node.light?.attenuationEndDistance = radius
        node.light?.castsShadow = true
        node.light?.shadowRadius = 3
        node.light?.shadowColor = UIColor.black.withAlphaComponent(0.38)
        node.position = position
        root.addChildNode(node)
        return node
    }

    private static func addExitDoor(
        to root: SCNNode,
        width: Float,
        height: Float,
        z: Float,
        wood: SCNMaterial,
        trim: SCNMaterial,
        brass: SCNMaterial
    ) {
        let door = addBox(
            to: root,
            name: "interior-exit-door",
            size: SCNVector3(width, height, 0.13),
            position: SCNVector3(0, height * 0.5, z),
            material: wood,
            chamfer: 0.045
        )
        for x in [-width * 0.43, width * 0.43] {
            addBox(
                to: door,
                name: "interior-exit-trim",
                size: SCNVector3(0.11, height + 0.18, 0.09),
                position: SCNVector3(x, 0, -0.10),
                material: trim,
                chamfer: 0.018
            )
        }
        addBox(
            to: door,
            name: "interior-exit-header",
            size: SCNVector3(width + 0.18, 0.13, 0.09),
            position: SCNVector3(0, height * 0.49, -0.10),
            material: trim,
            chamfer: 0.018
        )
        let knob = SCNSphere(radius: 0.075)
        knob.segmentCount = 16
        knob.firstMaterial = brass
        let knobNode = SCNNode(geometry: knob)
        knobNode.name = "interior-exit-knob"
        knobNode.position = SCNVector3(width * 0.30, 0, -0.13)
        door.addChildNode(knobNode)
    }

    private static func buildCottage(in scene: SCNScene) {
        scene.background.contents = UIColor(rgb: 0x211C18)
        scene.fogColor = UIColor(rgb: 0x3C3027)
        scene.fogStartDistance = 12
        scene.fogEndDistance = 26
        let root = scene.rootNode

        let woodDeep = material(0x33271F)
        let wood = material(0x624A34)
        let woodWarm = material(0x876445)
        let plankA = material(0x6B5039)
        let plankB = material(0x7B5D40)
        let plaster = material(0x9C927A, roughness: 1)
        let plasterShadow = material(0x756C5D, roughness: 1)
        let stone = material(0x59605B, roughness: 1)
        let stoneLight = material(0x747A70, roughness: 1)
        let tealGlass = material(0x4E9B91, roughness: 0.24, emission: 0x5EB0A0, emissionIntensity: 0.28)
        let brass = material(0xA47A37, roughness: 0.48, metalness: 0.55)
        let ember = material(0xD96A2D, roughness: 0.35, emission: 0xFF6B24, emissionIntensity: 2.4)
        let flame = material(0xF1B24B, roughness: 0.28, emission: 0xFFB43F, emissionIntensity: 3.1)
        let fabric = material(0x516B62, roughness: 1)
        let parchment = material(0xD4BC84, roughness: 0.96)

        // Irregular plank floor and fully enclosing walls remove all sightlines to the island.
        for index in 0..<12 {
            addBox(
                to: root,
                name: "cottage-floor-plank-\(index)",
                size: SCNVector3(0.80, 0.09, 7.40),
                position: SCNVector3(-4.40 + Float(index) * 0.80, 0, 0),
                material: index.isMultiple(of: 2) ? plankA : plankB,
                chamfer: 0.018,
                eulerAngles: SCNVector3(0, Float(index % 3 - 1) * 0.004, 0)
            )
        }
        addBox(to: root, name: "cottage-back-wall", size: SCNVector3(9.60, 4.42, 0.18), position: SCNVector3(0, 2.21, -3.70), material: plaster)
        addBox(to: root, name: "cottage-front-wall", size: SCNVector3(9.60, 4.42, 0.18), position: SCNVector3(0, 2.21, 3.70), material: plasterShadow)
        addBox(to: root, name: "cottage-left-wall", size: SCNVector3(0.18, 4.42, 7.40), position: SCNVector3(-4.80, 2.21, 0), material: plasterShadow)
        addBox(to: root, name: "cottage-right-wall", size: SCNVector3(0.18, 4.42, 7.40), position: SCNVector3(4.80, 2.21, 0), material: plaster)
        addBox(to: root, name: "cottage-ceiling", size: SCNVector3(9.64, 0.16, 7.44), position: SCNVector3(0, 4.34, 0), material: woodDeep)

        for index in 0..<6 {
            addBox(
                to: root,
                name: "cottage-ceiling-beam-\(index)",
                size: SCNVector3(0.21, 0.28, 7.46),
                position: SCNVector3(-4.00 + Float(index) * 1.60, 4.15, 0),
                material: index.isMultiple(of: 2) ? wood : woodDeep,
                chamfer: 0.035
            )
        }
        for (x, z, rotation) in [(-4.62 as Float, -2.25 as Float, -0.10 as Float), (4.62, 1.70, 0.08)] {
            addBox(
                to: root,
                name: "cottage-brace",
                size: SCNVector3(0.17, 3.55, 0.16),
                position: SCNVector3(x, 1.88, z),
                material: wood,
                chamfer: 0.025,
                eulerAngles: SCNVector3(0, 0, rotation)
            )
        }

        addExitDoor(to: root, width: 1.48, height: 2.52, z: 3.61, wood: woodWarm, trim: woodDeep, brass: brass)

        // Two luminous windows act as the only suggestion of daylight; no exterior geometry is shown.
        for (x, yaw) in [(-4.69 as Float, Float.pi / 2), (4.69, -Float.pi / 2)] {
            let window = addBox(
                to: root,
                name: "cottage-window",
                size: SCNVector3(1.36, 1.34, 0.06),
                position: SCNVector3(x, 2.10, -0.35),
                material: tealGlass,
                chamfer: 0.025,
                eulerAngles: SCNVector3(0, yaw, 0)
            )
            for barX in [-0.32 as Float, 0.32] {
                addBox(to: window, name: "cottage-window-bar", size: SCNVector3(0.08, 1.16, 0.08), position: SCNVector3(barX, 0, -0.06), material: woodDeep, chamfer: 0.012)
            }
            addBox(to: window, name: "cottage-window-crossbar", size: SCNVector3(1.16, 0.08, 0.08), position: SCNVector3(0, 0, -0.06), material: woodDeep, chamfer: 0.012)
        }

        // Stone hearth and animated layered flame.
        addBox(to: root, name: "cottage-hearth-base", size: SCNVector3(1.82, 0.25, 0.82), position: SCNVector3(-3.05, 0.12, -3.28), material: stone, chamfer: 0.055)
        addBox(to: root, name: "cottage-hearth-back", size: SCNVector3(1.68, 1.86, 0.28), position: SCNVector3(-3.05, 1.04, -3.52), material: stoneLight, chamfer: 0.045)
        addBox(to: root, name: "cottage-firebox", size: SCNVector3(1.02, 0.90, 0.08), position: SCNVector3(-3.05, 0.62, -3.35), material: woodDeep, chamfer: 0.12)
        addBox(to: root, name: "cottage-mantel", size: SCNVector3(1.98, 0.18, 0.58), position: SCNVector3(-3.05, 1.90, -3.35), material: woodWarm, chamfer: 0.045)
        for index in 0..<3 {
            let geometry = SCNCone(topRadius: 0.02, bottomRadius: 0.16 - CGFloat(index) * 0.025, height: 0.48 - CGFloat(index) * 0.06)
            geometry.radialSegmentCount = 12
            geometry.firstMaterial = index == 1 ? flame : ember
            let flameNode = SCNNode(geometry: geometry)
            flameNode.name = "cottage-hearth-flame"
            flameNode.position = SCNVector3(-3.28 + Float(index) * 0.23, 0.50, -3.16)
            root.addChildNode(flameNode)
            if !UIAccessibility.isReduceMotionEnabled {
                let pulse = SCNAction.sequence([
                    .scale(to: 0.82 + CGFloat(index) * 0.04, duration: 0.22 + Double(index) * 0.05),
                    .scale(to: 1.08, duration: 0.18 + Double(index) * 0.04),
                ])
                flameNode.runAction(.repeatForever(pulse))
            }
        }
        let fireLight = addOmniLight(to: root, name: "cottage-fire-light", color: 0xFF8A42, intensity: 780, position: SCNVector3(-3.05, 0.82, -2.88), radius: 8.6)
        if !UIAccessibility.isReduceMotionEnabled {
            fireLight.runAction(.repeatForever(.customAction(duration: 1.7) { node, elapsed in
                node.light?.intensity = 650 + CGFloat(sin(elapsed * 14)) * 72
            }))
        }

        // Bed, blanket, pillow, and central woven rug.
        addBox(to: root, name: "cottage-bed-frame", size: SCNVector3(1.56, 0.34, 2.28), position: SCNVector3(-3.05, 0.28, 0.88), material: woodDeep, chamfer: 0.06)
        addBox(to: root, name: "cottage-bed-mattress", size: SCNVector3(1.43, 0.22, 2.12), position: SCNVector3(-3.05, 0.55, 0.88), material: parchment, chamfer: 0.12)
        addBox(to: root, name: "cottage-bed-blanket", size: SCNVector3(1.47, 0.08, 1.22), position: SCNVector3(-3.05, 0.69, 1.18), material: fabric, chamfer: 0.08)
        addBox(to: root, name: "cottage-bed-pillow", size: SCNVector3(0.86, 0.18, 0.46), position: SCNVector3(-3.05, 0.72, -0.03), material: parchment, chamfer: 0.14)
        addBox(to: root, name: "cottage-rug", size: SCNVector3(3.20, 0.035, 1.88), position: SCNVector3(0.05, 0.075, 0.72), material: fabric, chamfer: 0.10)
        for index in 0..<6 {
            addBox(to: root, name: "cottage-rug-stripe", size: SCNVector3(0.025, 0.012, 1.72), position: SCNVector3(-1.28 + Float(index) * 0.52, 0.10, 0.72), material: parchment, chamfer: 0.004)
        }

        // Wall shelves, provisions, and a candle make the cottage feel inhabited.
        for (index, y) in [1.12 as Float, 1.92, 2.72].enumerated() {
            addBox(to: root, name: "cottage-shelf-\(index)", size: SCNVector3(0.46, 0.10, 2.65), position: SCNVector3(4.40, y, -0.38), material: wood, chamfer: 0.028)
        }
        for index in 0..<7 {
            let colors: [UInt32] = [0x6F7D61, 0x9B6A47, 0x4E6964, 0xB09A6B]
            addBox(
                to: root,
                name: "cottage-shelf-book-\(index)",
                size: SCNVector3(0.22, 0.42 + Float(index % 3) * 0.06, 0.14),
                position: SCNVector3(4.18, 1.37, -1.28 + Float(index) * 0.34),
                material: material(colors[index % colors.count]),
                chamfer: 0.018
            )
        }
        addCylinder(to: root, name: "cottage-candle", radius: 0.055, height: 0.28, position: SCNVector3(4.18, 2.12, -0.02), material: parchment)
        let candleFlame = SCNSphere(radius: 0.055)
        candleFlame.firstMaterial = flame
        let candleNode = SCNNode(geometry: candleFlame)
        candleNode.position = SCNVector3(4.18, 2.30, -0.02)
        root.addChildNode(candleNode)

        addAmbientLight(to: root, color: 0xB8A785, intensity: 360)
        _ = addOmniLight(to: root, name: "cottage-window-light", color: 0x87C3B4, intensity: 410, position: SCNVector3(3.60, 2.45, -0.30), radius: 10.5)
        addDust(to: root, color: UIColor(rgb: 0xE7D3A2).withAlphaComponent(0.38), area: SCNVector3(8.4, 3.2, 6.5))
    }

    private static func buildTent(in scene: SCNScene) {
        scene.background.contents = UIColor(rgb: 0x172F2B)
        scene.fogColor = UIColor(rgb: 0x29433A)
        scene.fogStartDistance = 10
        scene.fogEndDistance = 22
        let root = scene.rootNode

        let earth = material(0x473E31, roughness: 1)
        let canvas = material(0xA99B7B, roughness: 1)
        let canvasShadow = material(0x746B58, roughness: 1)
        let canvasPatch = material(0x526B5A, roughness: 1)
        let wood = material(0x684A31)
        let woodDeep = material(0x33271F)
        let rope = material(0x9B835D, roughness: 1)
        let teal = material(0x4A6960, roughness: 1)
        let parchment = material(0xD2B77C, roughness: 0.96)
        let brass = material(0xA47A37, roughness: 0.50, metalness: 0.52)
        let glow = material(0xE78431, roughness: 0.28, emission: 0xFF9D3F, emissionIntensity: 3.0)

        addBox(to: root, name: "tent-earth-floor", size: SCNVector3(8.35, 0.14, 7.55), position: SCNVector3(0, -0.04, 0), material: earth, chamfer: 0.15)
        addBox(to: root, name: "tent-ground-cloth", size: SCNVector3(7.76, 0.04, 6.92), position: SCNVector3(0, 0.06, 0), material: canvasShadow, chamfer: 0.12)

        // A-frame canvas shell. Opaque panels and the closed rear/front walls fully isolate the room.
        addBox(
            to: root,
            name: "tent-canvas-left",
            size: SCNVector3(6.10, 0.10, 7.58),
            position: SCNVector3(-2.05, 2.25, 0),
            material: canvas,
            chamfer: 0.03,
            eulerAngles: SCNVector3(0, 0, 0.835)
        )
        addBox(
            to: root,
            name: "tent-canvas-right",
            size: SCNVector3(6.10, 0.10, 7.58),
            position: SCNVector3(2.05, 2.25, 0),
            material: canvasShadow,
            chamfer: 0.03,
            eulerAngles: SCNVector3(0, 0, -0.835)
        )
        addBox(to: root, name: "tent-rear-canvas", size: SCNVector3(8.10, 4.48, 0.12), position: SCNVector3(0, 2.24, -3.75), material: canvasShadow, chamfer: 0.04)
        addBox(to: root, name: "tent-front-canvas", size: SCNVector3(8.10, 4.48, 0.12), position: SCNVector3(0, 2.24, 3.75), material: canvas, chamfer: 0.04)
        addExitDoor(to: root, width: 1.58, height: 2.55, z: 3.66, wood: canvasPatch, trim: rope, brass: brass)

        // Poles, ridge beam, seam ropes, and repair patches give the interior scale.
        addCylinder(to: root, name: "tent-front-pole", radius: 0.085, height: 4.58, position: SCNVector3(0, 2.28, 3.48), material: wood)
        addCylinder(to: root, name: "tent-rear-pole", radius: 0.085, height: 4.58, position: SCNVector3(0, 2.28, -3.48), material: wood)
        addBox(to: root, name: "tent-ridge-beam", size: SCNVector3(0.15, 0.15, 7.28), position: SCNVector3(0, 4.52, 0), material: woodDeep, chamfer: 0.04)
        for x in [-3.72 as Float, 3.72] {
            addBox(to: root, name: "tent-seam-rope", size: SCNVector3(0.035, 0.035, 6.96), position: SCNVector3(x, 0.52, 0), material: rope, chamfer: 0.012)
        }
        addBox(to: root, name: "tent-canvas-patch", size: SCNVector3(0.98, 0.035, 0.72), position: SCNVector3(-3.08, 1.48, -1.18), material: canvasPatch, chamfer: 0.035, eulerAngles: SCNVector3(0, 0, 0.73))

        // Woven center rug and travel markings.
        addBox(to: root, name: "tent-center-rug", size: SCNVector3(3.32, 0.035, 2.24), position: SCNVector3(-0.18, 0.10, 0.72), material: teal, chamfer: 0.10)
        for index in 0..<5 {
            addBox(to: root, name: "tent-rug-stripe", size: SCNVector3(3.05, 0.012, 0.025), position: SCNVector3(-0.18, 0.128, 0.02 + Float(index) * 0.36), material: parchment, chamfer: 0.004)
        }

        // Rolled bedding, supply chest, and stacked charts.
        addCylinder(to: root, name: "tent-bedroll", radius: 0.32, height: 1.42, position: SCNVector3(-2.42, 0.38, -1.68), material: teal, eulerAngles: SCNVector3(0, 0, Float.pi / 2))
        for x in [-2.80 as Float, -2.04] {
            let ring = SCNTorus(ringRadius: 0.30, pipeRadius: 0.018)
            ring.ringSegmentCount = 16
            ring.pipeSegmentCount = 6
            ring.firstMaterial = rope
            let ringNode = SCNNode(geometry: ring)
            ringNode.position = SCNVector3(x, 0.38, -1.68)
            ringNode.eulerAngles.z = .pi / 2
            root.addChildNode(ringNode)
        }
        addBox(to: root, name: "tent-supply-chest", size: SCNVector3(1.02, 0.68, 0.82), position: SCNVector3(2.88, 0.40, 1.52), material: woodDeep, chamfer: 0.07)
        addBox(to: root, name: "tent-supply-lid", size: SCNVector3(1.10, 0.14, 0.88), position: SCNVector3(2.88, 0.80, 1.52), material: wood, chamfer: 0.055)
        addBox(to: root, name: "tent-chest-latch", size: SCNVector3(0.14, 0.22, 0.035), position: SCNVector3(2.88, 0.60, 1.08), material: brass, chamfer: 0.012)

        // The chart, its plotted route, and the compass work on the chest lid.
        // They used to lie on a writing desk; the desk is gone, and a chart
        // left floating at desk height would have been the only thing in the
        // tent resting on nothing.
        addBox(to: root, name: "tent-open-chart", size: SCNVector3(0.95, 0.025, 0.58), position: SCNVector3(2.86, 0.895, 1.52), material: parchment, chamfer: 0.018, eulerAngles: SCNVector3(0, 0.08, 0))
        for index in 0..<3 {
            addBox(to: root, name: "tent-chart-route", size: SCNVector3(0.32, 0.012, 0.018), position: SCNVector3(2.60 + Float(index) * 0.25, 0.925, 1.52 + Float(index % 2) * 0.12), material: teal, chamfer: 0.004, eulerAngles: SCNVector3(0, Float(index) * 0.42 - 0.35, 0))
        }
        addCylinder(to: root, name: "tent-compass", radius: 0.11, height: 0.035, position: SCNVector3(3.17, 0.945, 1.68), material: brass)

        // Hanging lantern is the dominant light source and focal point.
        addBox(to: root, name: "tent-lantern-cord", size: SCNVector3(0.025, 0.72, 0.025), position: SCNVector3(-0.72, 4.08, -0.65), material: rope, chamfer: 0.008)
        let lanternGeometry = SCNSphere(radius: 0.18)
        lanternGeometry.segmentCount = 18
        lanternGeometry.firstMaterial = glow
        let lantern = SCNNode(geometry: lanternGeometry)
        lantern.name = "tent-lantern-glow"
        lantern.position = SCNVector3(-0.72, 3.62, -0.65)
        lantern.scale = SCNVector3(0.82, 1.14, 0.82)
        root.addChildNode(lantern)
        for y in [3.40 as Float, 3.84] {
            addCylinder(to: root, name: "tent-lantern-cap", radius: 0.22, height: 0.075, position: SCNVector3(-0.72, y, -0.65), material: brass)
        }
        let lanternLight = addOmniLight(to: root, name: "tent-lantern-light", color: 0xFF9C46, intensity: 920, position: SCNVector3(-0.72, 3.54, -0.65), radius: 10.8)
        if !UIAccessibility.isReduceMotionEnabled {
            lanternLight.runAction(.repeatForever(.customAction(duration: 2.1) { node, elapsed in
                node.light?.intensity = 820 + CGFloat(sin(elapsed * 9.4)) * 58
            }))
        }

        addAmbientLight(to: root, color: 0x759488, intensity: 310)
        _ = addOmniLight(to: root, name: "tent-cool-fill", color: 0x65A99A, intensity: 270, position: SCNVector3(3.10, 2.35, 2.25), radius: 9.4)
        addDust(to: root, color: UIColor(rgb: 0xE7D3A2).withAlphaComponent(0.30), area: SCNVector3(7.2, 3.4, 6.5))
    }

    private static func addDust(to root: SCNNode, color: UIColor, area: SCNVector3) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let particles = SCNParticleSystem()
        particles.birthRate = 7
        particles.particleLifeSpan = 7
        particles.particleLifeSpanVariation = 2
        particles.particleSize = 0.012
        particles.particleSizeVariation = 0.008
        particles.particleColor = color
        particles.particleVelocity = 0.025
        particles.particleVelocityVariation = 0.018
        particles.acceleration = SCNVector3(0.012, 0.014, -0.008)
        particles.isAffectedByGravity = false
        particles.blendMode = .additive
        particles.emitterShape = SCNBox(
            width: CGFloat(area.x),
            height: CGFloat(area.y),
            length: CGFloat(area.z),
            chamferRadius: 0
        )
        let emitter = SCNNode()
        emitter.name = "interior-dust-motes"
        emitter.position = SCNVector3(0, 1.65, 0)
        emitter.addParticleSystem(particles)
        root.addChildNode(emitter)
    }
}

private extension SCNVector3 {
    static func + (lhs: SCNVector3, rhs: SCNVector3) -> SCNVector3 {
        SCNVector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }

    static func * (lhs: SCNVector3, rhs: Float) -> SCNVector3 {
        SCNVector3(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
    }
}
