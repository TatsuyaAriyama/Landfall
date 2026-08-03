import SceneKit
import SwiftUI
import UIKit

/// iOS Simulatorのハードウェアキーボード入力を、3D編集キャンバスへ渡す。
/// 実機でも外付けキーボードを接続した場合は同じショートカットを利用できる。
private final class AssetStudioInteractiveSceneView: SCNView {
    var keyCommandHandler: ((UIKeyCommand) -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { becomeFirstResponder() }
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            keyCommand(UIKeyCommand.inputUpArrow, title: "Move camera forward"),
            keyCommand(UIKeyCommand.inputDownArrow, title: "Move camera backward"),
            keyCommand(UIKeyCommand.inputLeftArrow, title: "Move camera left"),
            keyCommand(UIKeyCommand.inputRightArrow, title: "Move camera right"),
            keyCommand("w", title: "Move camera forward"),
            keyCommand("s", title: "Move camera backward"),
            keyCommand("a", title: "Move camera left"),
            keyCommand("d", title: "Move camera right"),
            keyCommand("q", title: "Orbit camera left"),
            keyCommand("e", title: "Orbit camera right"),
            keyCommand("=", title: "Zoom in"),
            keyCommand("-", title: "Zoom out"),
            keyCommand("0", title: "Show overview"),
            keyCommand("f", title: "Focus selected"),
            keyCommand("1", title: "Select mode"),
            keyCommand("2", title: "Move mode"),
            keyCommand("3", title: "Height mode"),
            keyCommand("4", title: "Rotate mode"),
            keyCommand("5", title: "Scale mode"),
            keyCommand("6", title: "Camera mode"),
            keyCommand("7", title: "Paint mode"),
            keyCommand("8", title: "Terrain mode"),
            keyCommand("z", modifiers: .command, title: "Undo"),
            keyCommand("z", modifiers: [.command, .shift], title: "Redo"),
            keyCommand("d", modifiers: .command, title: "Duplicate selected"),
            keyCommand(UIKeyCommand.inputDelete, title: "Delete selected"),
            keyCommand(UIKeyCommand.inputEscape, title: "Clear selection"),
        ]
    }

    @objc private func handleKeyCommand(_ command: UIKeyCommand) {
        keyCommandHandler?(command)
    }

    private func keyCommand(
        _ input: String,
        modifiers: UIKeyModifierFlags = [],
        title: String
    ) -> UIKeyCommand {
        let command = UIKeyCommand(
            input: input,
            modifierFlags: modifiers,
            action: #selector(handleKeyCommand(_:))
        )
        command.discoverabilityTitle = NSLocalizedString(title, comment: "3D studio keyboard shortcut")
        command.wantsPriorityOverSystemBehavior = true
        return command
    }
}

/// SceneKit の編集キャンバス。SwiftUI側の Store とシーンノードを同期する。
struct AssetPlacementSceneView: UIViewRepresentable {
    @ObservedObject var store: AssetPlacementStore
    var homeProgressRatio: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(owner: self)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = AssetStudioInteractiveSceneView(frame: .zero)
        context.coordinator.configure(view)
        context.coordinator.synchronize()
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.owner = self
        context.coordinator.synchronize()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var owner: AssetPlacementSceneView

        private weak var sceneView: SCNView?
        private let scene = SCNScene()
        private let worldRoot = SCNNode()
        private let cameraYawNode = SCNNode()
        private let cameraPitchNode = SCNNode()
        private let cameraNode = SCNNode()
        private var placementParent = SCNNode()
        private var placementNodes: [UUID: SCNNode] = [:]
        private var paintNodes: [UUID: SCNNode] = [:]
        private var renderedPaintStrokes: [UUID: AssetPaintStroke] = [:]
        private var terrainNode: SCNNode?
        private var homeShipMarkerNode: SCNNode?
        private var brushPreviewNode: SCNNode?
        private var renderedHomeProgressRatio: Double?
        private var renderedTerrainStrokes: [AssetTerrainStroke] = []
        private var renderedContext: AssetPlacementContext?
        private var renderedActiveStudioID: UUID?
        private var renderedSelectionIDs: Set<UUID> = []
        private var selectionIndicators: [UUID: SCNNode] = [:]
        private weak var selectionMarqueeView: UIView?
        private var marqueeStart: CGPoint?
        private var activePaintStrokeID: UUID?
        private var lastPaintPoint: AssetPaintPoint?
        private var activeTerrainStrokeID: UUID?
        private var lastTerrainPoint: AssetPaintPoint?
        private var lastPaintGeometryRefresh: TimeInterval = 0
        private var lastTerrainGeometryRefresh: TimeInterval = 0

        private var cameraTarget = SCNVector3(0, 1.3, 0)
        private var cameraAzimuth: Float = 0.72
        private var cameraElevation: Float = 0.42
        private var cameraDistance: Float = 10.2
        private var processedCameraRequestID: UUID?
        private var processedSurfaceSnapRequestID: UUID?

        private var interactionID: UUID?
        private var initialTransform: AssetTransform?
        private var panEditsSelection = false
        private var pinchEditsSelection = false
        private var initialAzimuth: Float = 0
        private var initialElevation: Float = 0
        private var initialDistance: Float = 0
        private var initialCameraTarget = SCNVector3Zero
        private var pinchAnchorWorldPoint: SCNVector3?
        private var initialWorldDragPoint: SCNVector3?
        private var initialNodeWorldPosition: SCNVector3?
        private var dragPlaneY: Float = 0

        private struct CameraLimits {
            let minimumElevation: Float
            let maximumElevation: Float
            let minimumDistance: Float
            let maximumDistance: Float
            let minimumTarget: SCNVector3
            let maximumTarget: SCNVector3
        }

        init(owner: AssetPlacementSceneView) {
            self.owner = owner
            super.init()
        }

        func configure(_ view: SCNView) {
            sceneView = view
            scene.background.contents = VoyageSceneKit.nightBG
            scene.rootNode.addChildNode(worldRoot)
            configureCamera()
            configureLights()

            view.scene = scene
            view.pointOfView = cameraNode
            view.backgroundColor = VoyageSceneKit.nightBG
            view.antialiasingMode = .multisampling4X
            view.preferredFramesPerSecond = 60
            view.rendersContinuously = true
            view.autoenablesDefaultLighting = false
            view.allowsCameraControl = false
            view.isJitteringEnabled = true
            view.contentScaleFactor = UIScreen.main.scale
            if let interactiveView = view as? AssetStudioInteractiveSceneView {
                interactiveView.keyCommandHandler = { [weak self] command in
                    self?.handleKeyboardCommand(command)
                }
            }

            let marquee = UIView(frame: .zero)
            marquee.isHidden = true
            marquee.isUserInteractionEnabled = false
            marquee.backgroundColor = UIColor(rgb: 0xFFD36A).withAlphaComponent(0.13)
            marquee.layer.borderColor = UIColor(rgb: 0xFFD36A).withAlphaComponent(0.95).cgColor
            marquee.layer.borderWidth = 1.5
            marquee.layer.cornerRadius = 3
            view.addSubview(marquee)
            selectionMarqueeView = marquee

            installGestures(on: view)
        }

        func synchronize() {
            guard sceneView != nil else { return }
            var selectionGeometryChanged = false
            let activeWorldChanged = owner.store.context == .destinationIsland
                && renderedActiveStudioID != owner.store.activeStudioID
            if renderedContext != owner.store.context || activeWorldChanged {
                rebuildWorld(for: owner.store.context)
            }
            if renderedHomeProgressRatio != owner.homeProgressRatio {
                rebuildHomeShipMarker()
            }

            let visiblePlacements = owner.store.visiblePlacements
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
                    guard let loaded = AssetPlacementRuntime.makeAssetNode(resourceName: placement.assetID) else {
                        continue
                    }
                    loaded.name = "placement:\(placement.id.uuidString)"
                    placementParent.addChildNode(loaded)
                    placementNodes[placement.id] = loaded
                    node = loaded
                }
                placement.transform.apply(to: node)
            }

            let refreshTime = ProcessInfo.processInfo.systemUptime
            var paintSurfaceChanged = false

            // 先に高さフィールドを更新し、その同じ面へ素材レイヤーを再投影する。
            // この順序で山を削った後も色だけが空中へ残らない。
            let visibleTerrainStrokes = owner.store.visibleTerrainStrokes
            if renderedTerrainStrokes != visibleTerrainStrokes {
                let shouldThrottle = activeTerrainStrokeID != nil
                    && refreshTime - lastTerrainGeometryRefresh < 1.0 / 24.0
                if !shouldThrottle {
                    terrainNode?.removeFromParentNode()
                    terrainNode = AssetPlacementRuntime.makeTerrainNode(for: visibleTerrainStrokes)
                    if let terrainNode {
                        placementParent.addChildNode(terrainNode)
                    }
                    renderedTerrainStrokes = visibleTerrainStrokes
                    selectionGeometryChanged = true
                    paintSurfaceChanged = true
                    lastTerrainGeometryRefresh = refreshTime
                }
            }

            if paintSurfaceChanged {
                for node in paintNodes.values {
                    node.removeFromParentNode()
                }
                paintNodes.removeAll()
                renderedPaintStrokes.removeAll()
            }

            let visibleStrokes = owner.store.visiblePaintStrokes
            let visibleStrokeIDs = Set(visibleStrokes.map(\.id))
            for (id, node) in paintNodes where !visibleStrokeIDs.contains(id) {
                node.removeFromParentNode()
                paintNodes[id] = nil
                renderedPaintStrokes[id] = nil
                selectionGeometryChanged = true
            }
            for stroke in visibleStrokes where renderedPaintStrokes[stroke.id] != stroke {
                let isActiveStroke = stroke.id == activePaintStrokeID
                if isActiveStroke, refreshTime - lastPaintGeometryRefresh < 1.0 / 30.0 {
                    continue
                }
                paintNodes[stroke.id]?.removeFromParentNode()
                let node = AssetPlacementRuntime.makePaintNode(
                    for: stroke,
                    terrainNode: terrainNode
                )
                placementParent.addChildNode(node)
                paintNodes[stroke.id] = node
                renderedPaintStrokes[stroke.id] = stroke
                selectionGeometryChanged = true
                if isActiveStroke { lastPaintGeometryRefresh = refreshTime }
            }

            if selectionGeometryChanged {
                clearSelectionIndicators()
                renderedSelectionIDs.removeAll()
            }
            refreshSelectionIfNeeded()
            processCameraRequestIfNeeded()
            processSurfaceSnapRequestIfNeeded()
        }

        private func configureCamera() {
            let camera = SCNCamera()
            camera.fieldOfView = 46
            camera.zNear = 0.015
            camera.zFar = 1_500
            camera.wantsHDR = true
            camera.wantsExposureAdaptation = true
            camera.exposureOffset = -0.08
            camera.bloomIntensity = 0.13
            camera.bloomThreshold = 0.92
            // モデルと地表の接点、枝葉の重なりを画面空間AOで補強する。
            camera.screenSpaceAmbientOcclusionIntensity = 1.18
            camera.screenSpaceAmbientOcclusionRadius = 0.72
            camera.screenSpaceAmbientOcclusionBias = 0.018
            camera.screenSpaceAmbientOcclusionDepthThreshold = 0.38
            camera.screenSpaceAmbientOcclusionNormalThreshold = 0.30

            // 水平回転と縦回転を別ノードに分離する。カメラ自身にはロールを一切持たせない。
            // look-at姿勢の多解性や±180度境界の補間で画面が横倒しになることを構造的に防ぐ。
            cameraYawNode.name = "asset-studio-camera-yaw"
            cameraPitchNode.name = "asset-studio-camera-pitch"
            cameraNode.name = "asset-studio-camera"
            cameraNode.camera = camera
            scene.rootNode.addChildNode(cameraYawNode)
            cameraYawNode.addChildNode(cameraPitchNode)
            cameraPitchNode.addChildNode(cameraNode)
            updateCamera()
        }

        private func configureLights() {
            let ambient = SCNLight()
            ambient.type = .ambient
            ambient.color = UIColor(rgb: 0xB8D7CC)
            // 環境光を少し抑え、面の向きと接地影が読めるコントラストを残す。
            ambient.intensity = 410
            let ambientNode = SCNNode()
            ambientNode.light = ambient
            scene.rootNode.addChildNode(ambientNode)

            let key = SCNLight()
            key.type = .directional
            key.color = UIColor(rgb: 0xFFF1CB)
            key.intensity = 1_120
            key.castsShadow = true
            key.shadowMode = .deferred
            key.shadowMapSize = CGSize(width: 2_048, height: 2_048)
            key.shadowSampleCount = 32
            key.shadowRadius = 3.4
            key.shadowColor = UIColor(rgb: 0x071E1B).withAlphaComponent(0.38)
            key.automaticallyAdjustsShadowProjection = true
            key.maximumShadowDistance = 96
            key.shadowCascadeCount = 3
            key.shadowCascadeSplittingFactor = 0.18
            let keyNode = SCNNode()
            keyNode.light = key
            keyNode.eulerAngles = SCNVector3(-0.92, -0.62, -0.18)
            scene.rootNode.addChildNode(keyNode)

            // 拡張した世界の端でも色味が変わらないよう、距離減衰する点光源ではなく方向光を使う。
            let fill = SCNLight()
            fill.type = .directional
            fill.color = UIColor(rgb: 0x85C9B6)
            fill.intensity = 310
            let fillNode = SCNNode()
            fillNode.light = fill
            fillNode.eulerAngles = SCNVector3(-0.34, 2.28, 0.12)
            scene.rootNode.addChildNode(fillNode)
        }

        private func rebuildWorld(for context: AssetPlacementContext) {
            renderedContext = context
            renderedActiveStudioID = owner.store.activeStudioID
            renderedSelectionIDs.removeAll()
            clearSelectionIndicators()
            placementNodes.removeAll()
            paintNodes.removeAll()
            renderedPaintStrokes.removeAll()
            terrainNode = nil
            brushPreviewNode?.removeFromParentNode()
            brushPreviewNode = nil
            renderedTerrainStrokes.removeAll()
            homeShipMarkerNode = nil
            renderedHomeProgressRatio = nil
            worldRoot.childNodes.forEach { $0.removeFromParentNode() }

            switch context {
            case .destinationIsland:
                let water = makeGround(
                    color: VoyageSceneKit.seaBase,
                    reflective: true
                )
                water.position.y = -0.055
                worldRoot.addChildNode(water)

                let island = VoyageSceneKit.makeIsland(
                    position: SCNVector3Zero,
                    scale: SCNVector3(1, 1, 1),
                    includesCustomAssets: false
                )
                worldRoot.addChildNode(island)
                placementParent = island

            case .studio:
                let ground = makeGround(color: UIColor(rgb: 0x173F38), reflective: false)
                worldRoot.addChildNode(ground)
                worldRoot.addChildNode(makeGrid())
                let root = SCNNode()
                root.name = "studio-placement-root"
                worldRoot.addChildNode(root)
                placementParent = root
            }
            rebuildHomeShipMarker()
            resetCamera(animated: false)
        }

        private func makeGround(color: UIColor, reflective: Bool) -> SCNNode {
            let floor = SCNFloor()
            floor.reflectivity = reflective ? 0.10 : 0
            floor.reflectionFalloffEnd = 14
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = color
            material.roughness.contents = reflective ? 0.82 : 0.96
            material.metalness.contents = 0
            floor.firstMaterial = material
            let node = SCNNode(geometry: floor)
            node.name = "asset-studio-ground"
            return node
        }

        private func makeGrid() -> SCNNode {
            let root = SCNNode()
            root.name = "asset-studio-grid"
            // 大規模マップでも距離感を失わないよう、編集可能範囲全体へ広げる。
            let extent = 128

            func layer(values: [Int], opacity: CGFloat, y: Float) -> SCNNode {
                var vertices: [SCNVector3] = []
                var indices: [Int32] = []
                for value in values {
                    let offset = Float(value)
                    let start = Int32(vertices.count)
                    vertices.append(SCNVector3(-Float(extent), y, offset))
                    vertices.append(SCNVector3(Float(extent), y, offset))
                    vertices.append(SCNVector3(offset, y, -Float(extent)))
                    vertices.append(SCNVector3(offset, y, Float(extent)))
                    indices += [start, start + 1, start + 2, start + 3]
                }
                let geometry = SCNGeometry(
                    sources: [SCNGeometrySource(vertices: vertices)],
                    elements: [SCNGeometryElement(indices: indices, primitiveType: .line)]
                )
                let material = SCNMaterial()
                material.lightingModel = .constant
                material.diffuse.contents = UIColor.white.withAlphaComponent(opacity)
                material.writesToDepthBuffer = false
                geometry.firstMaterial = material
                return SCNNode(geometry: geometry)
            }

            let allValues = Array(-extent...extent)
            root.addChildNode(
                layer(
                    values: allValues.filter { $0.isMultiple(of: 2) && !$0.isMultiple(of: 10) },
                    opacity: 0.045,
                    y: 0.005
                )
            )
            root.addChildNode(
                layer(
                    values: allValues.filter { $0.isMultiple(of: 10) },
                    opacity: 0.17,
                    y: 0.007
                )
            )
            return root
        }

        /// ホーム画面の船が実際にいる位置を示す、保存対象外の編集用マーカー。
        private func rebuildHomeShipMarker() {
            homeShipMarkerNode?.removeFromParentNode()
            let marker = makeHomeShipMarker()
            marker.position = AftideHomeWorldReference.boatIslandPosition(
                progressRatio: owner.homeProgressRatio
            )
            placementParent.addChildNode(marker)
            homeShipMarkerNode = marker
            renderedHomeProgressRatio = owner.homeProgressRatio
        }

        private func makeHomeShipMarker() -> SCNNode {
            let root = SCNNode()
            root.name = "asset-studio-home-ship-marker"
            let red = UIColor(rgb: 0xFF4148)
            let redMaterial = VoyageSceneKit.unlitMaterial(red)
            redMaterial.emission.contents = red

            let ringGeometry = SCNTorus(ringRadius: 0.68, pipeRadius: 0.075)
            ringGeometry.ringSegmentCount = 48
            ringGeometry.pipeSegmentCount = 8
            ringGeometry.firstMaterial = redMaterial
            let ring = SCNNode(geometry: ringGeometry)
            ring.position.y = 0.075
            ring.renderingOrder = 180
            ring.castsShadow = false
            root.addChildNode(ring)

            let centerMaterial = VoyageSceneKit.unlitMaterial(red.withAlphaComponent(0.24))
            centerMaterial.writesToDepthBuffer = false
            let centerGeometry = SCNCylinder(radius: 0.25, height: 0.018)
            centerGeometry.radialSegmentCount = 32
            centerGeometry.firstMaterial = centerMaterial
            let center = SCNNode(geometry: centerGeometry)
            center.position.y = 0.065
            center.renderingOrder = 179
            root.addChildNode(center)

            let beaconGeometry = SCNCylinder(radius: 0.032, height: 1.58)
            beaconGeometry.radialSegmentCount = 10
            beaconGeometry.firstMaterial = redMaterial
            let beacon = SCNNode(geometry: beaconGeometry)
            beacon.position.y = 0.86
            beacon.renderingOrder = 181
            beacon.castsShadow = false
            root.addChildNode(beacon)

            let pointerGeometry = SCNCone(topRadius: 0.20, bottomRadius: 0, height: 0.38)
            pointerGeometry.radialSegmentCount = 16
            pointerGeometry.firstMaterial = redMaterial
            let pointer = SCNNode(geometry: pointerGeometry)
            pointer.position.y = 1.77
            pointer.renderingOrder = 182
            pointer.castsShadow = false
            root.addChildNode(pointer)

            // 船から島への正面方向を短い赤点で示す。
            let boatPosition = AftideHomeWorldReference.boatIslandPosition(
                progressRatio: owner.homeProgressRatio
            )
            let directionLength = max(
                sqrt(boatPosition.x * boatPosition.x + boatPosition.z * boatPosition.z),
                0.001
            )
            let directionX = -boatPosition.x / directionLength
            let directionZ = -boatPosition.z / directionLength
            let dashGeometry = SCNBox(
                width: 0.25,
                height: 0.025,
                length: 0.085,
                chamferRadius: 0.02
            )
            dashGeometry.firstMaterial = redMaterial
            let dashYaw = atan2(-directionZ, directionX)
            for index in 1...4 {
                let distance = Float(index) * 0.42 + 0.52
                let dash = SCNNode(geometry: dashGeometry)
                dash.position = SCNVector3(directionX * distance, 0.075, directionZ * distance)
                dash.eulerAngles.y = dashYaw
                dash.renderingOrder = 180
                dash.castsShadow = false
                root.addChildNode(dash)
            }

            let textGeometry = SCNText(
                string: String(localized: "HOME SHIP"),
                extrusionDepth: 0.012
            )
            textGeometry.font = .systemFont(ofSize: 8, weight: .heavy)
            textGeometry.flatness = 0.18
            textGeometry.firstMaterial = redMaterial
            let label = SCNNode(geometry: textGeometry)
            let (minimum, maximum) = label.boundingBox
            label.pivot = SCNMatrix4MakeTranslation(
                (minimum.x + maximum.x) * 0.5,
                minimum.y,
                0
            )
            label.scale = SCNVector3(0.028, 0.028, 0.028)
            label.position = SCNVector3(0, 2.08, 0)
            let billboard = SCNBillboardConstraint()
            billboard.freeAxes = .Y
            label.constraints = [billboard]
            label.renderingOrder = 183
            label.castsShadow = false
            root.addChildNode(label)

            return root
        }

        private func refreshSelectionIfNeeded() {
            // 描画中はモデルのワイヤー枠を隠し、地表と筆跡の色判定を優先する。
            let selectionIDs = owner.store.manipulationMode == .paint
                || owner.store.manipulationMode == .terrain
                || owner.store.manipulationMode == .place
                ? Set<UUID>()
                : owner.store.selectedIDs
            let paintSelectionIDs = Set(owner.store.visiblePaintStrokes.map(\.id))
            let terrainSelectionIDs = Set(owner.store.visibleTerrainStrokes.map(\.id))
            let expectedIndicatorIDs = selectionIDs.filter {
                placementNodes[$0] != nil
                    || paintSelectionIDs.contains($0)
                    || terrainSelectionIDs.contains($0)
            }
            // IDキャッシュだけでなく、実際にシーンへ残っている表示ノードも照合する。
            // 一括削除と同時にジオメトリが無効化されても、古い選択マークを必ず消す。
            guard renderedSelectionIDs != selectionIDs
                    || Set(selectionIndicators.keys) != expectedIndicatorIDs
            else { return }
            renderedSelectionIDs = selectionIDs
            clearSelectionIndicators()

            for selectionID in selectionIDs {
                let indicator: SCNNode
                if let selectedNode = placementNodes[selectionID] {
                    indicator = makeSelectionIndicator(for: selectedNode)
                    selectedNode.addChildNode(indicator)
                } else if let stroke = owner.store.visiblePaintStrokes.first(where: { $0.id == selectionID }) {
                    indicator = makeStrokeFootprintSelectionIndicator(
                        points: stroke.points,
                        radius: max(stroke.width * 0.5, 0.04)
                    )
                    placementParent.addChildNode(indicator)
                } else if let stroke = owner.store.visibleTerrainStrokes.first(where: { $0.id == selectionID }) {
                    indicator = makeTerrainSelectionIndicator(for: stroke)
                    placementParent.addChildNode(indicator)
                } else {
                    continue
                }
                selectionIndicators[selectionID] = indicator
            }
        }

        private func clearSelectionIndicators() {
            selectionIndicators.values.forEach { $0.removeFromParentNode() }
            selectionIndicators.removeAll()
        }

        private func makeSelectionIndicator(for node: SCNNode) -> SCNNode {
            var (minimum, maximum) = node.boundingBox
            let hasUsableBounds = minimum.x.isFinite && minimum.y.isFinite && minimum.z.isFinite
                && maximum.x.isFinite && maximum.y.isFinite && maximum.z.isFinite
                && (maximum.x > minimum.x || maximum.y > minimum.y || maximum.z > minimum.z)
            if !hasUsableBounds {
                minimum = SCNVector3(-0.5, 0, -0.5)
                maximum = SCNVector3(0.5, 1, 0.5)
            }

            return makeSelectionIndicator(minimum: minimum, maximum: maximum)
        }

        private func makeTerrainSelectionIndicator(for stroke: AssetTerrainStroke) -> SCNNode {
            makeStrokeFootprintSelectionIndicator(
                points: stroke.points,
                radius: max(stroke.radius, 0.08)
            )
        }

        /// ペンや地形の実際のブラシ範囲を、連続した帯と輪郭で示す。
        /// 点ごとの黄色い丸は、隣のストロークとの対応が分かりづらいため使わない。
        private func makeStrokeFootprintSelectionIndicator(
            points: [AssetPaintPoint],
            radius: Float
        ) -> SCNNode {
            let indicator = SCNNode()
            indicator.name = "asset-studio-selection"
            guard !points.isEmpty else { return indicator }

            let selectionColor = UIColor(rgb: 0xFFD36A)
            let outlineMaterial = SCNMaterial()
            outlineMaterial.lightingModel = .constant
            outlineMaterial.diffuse.contents = selectionColor
            outlineMaterial.emission.contents = UIColor(rgb: 0xE7A83E)
            outlineMaterial.readsFromDepthBuffer = false
            outlineMaterial.writesToDepthBuffer = false

            let fillMaterial = SCNMaterial()
            fillMaterial.lightingModel = .constant
            fillMaterial.diffuse.contents = selectionColor.withAlphaComponent(0.20)
            fillMaterial.emission.contents = selectionColor.withAlphaComponent(0.08)
            fillMaterial.isDoubleSided = true
            fillMaterial.readsFromDepthBuffer = false
            fillMaterial.writesToDepthBuffer = false
            fillMaterial.blendMode = .alpha

            var sampledPoints: [AssetPaintPoint] = []
            let stride = max(1, Int(ceil(Double(points.count) / 48.0)))
            for index in Swift.stride(from: 0, to: points.count, by: stride) {
                sampledPoints.append(points[index])
            }
            if let last = points.last, sampledPoints.last != last { sampledPoints.append(last) }

            guard sampledPoints.count > 1 else {
                let point = sampledPoints[0]
                let disc = SCNCylinder(radius: CGFloat(radius), height: 0.008)
                disc.radialSegmentCount = 48
                disc.firstMaterial = fillMaterial
                let discNode = SCNNode(geometry: disc)
                discNode.position = SCNVector3(point.x, point.y + 0.06, point.z)
                discNode.renderingOrder = 901
                indicator.addChildNode(discNode)

                let crossVertices = [
                    SCNVector3(point.x - radius, point.y + 0.068, point.z),
                    SCNVector3(point.x + radius, point.y + 0.068, point.z),
                    SCNVector3(point.x, point.y + 0.068, point.z - radius),
                    SCNVector3(point.x, point.y + 0.068, point.z + radius),
                ]
                let crossGeometry = SCNGeometry(
                    sources: [SCNGeometrySource(vertices: crossVertices)],
                    elements: [SCNGeometryElement(indices: [Int32(0), 1, 2, 3], primitiveType: .line)]
                )
                crossGeometry.firstMaterial = outlineMaterial
                let crossNode = SCNNode(geometry: crossGeometry)
                crossNode.renderingOrder = 903
                indicator.addChildNode(crossNode)
                return indicator
            }

            var vertices: [SCNVector3] = []
            var centerVertices: [SCNVector3] = []
            vertices.reserveCapacity(sampledPoints.count * 2)
            centerVertices.reserveCapacity(sampledPoints.count)
            for index in sampledPoints.indices {
                let point = sampledPoints[index]
                let previous = sampledPoints[max(index - 1, 0)]
                let next = sampledPoints[min(index + 1, sampledPoints.count - 1)]
                let tangentX = next.x - previous.x
                let tangentZ = next.z - previous.z
                let tangentLength = max(sqrt(tangentX * tangentX + tangentZ * tangentZ), 0.000_1)
                let normalX = -tangentZ / tangentLength
                let normalZ = tangentX / tangentLength
                let y = point.y + 0.06
                vertices.append(SCNVector3(point.x + normalX * radius, y, point.z + normalZ * radius))
                vertices.append(SCNVector3(point.x - normalX * radius, y, point.z - normalZ * radius))
                centerVertices.append(SCNVector3(point.x, y + 0.008, point.z))
            }

            let fillIndices = vertices.indices.map(Int32.init)
            let fillGeometry = SCNGeometry(
                sources: [SCNGeometrySource(vertices: vertices)],
                elements: [SCNGeometryElement(indices: fillIndices, primitiveType: .triangleStrip)]
            )
            fillGeometry.firstMaterial = fillMaterial
            let fillNode = SCNNode(geometry: fillGeometry)
            fillNode.renderingOrder = 901
            indicator.addChildNode(fillNode)

            var outlineIndices: [Int32] = []
            for index in 0..<(sampledPoints.count - 1) {
                let current = Int32(index * 2)
                let next = Int32((index + 1) * 2)
                outlineIndices.append(contentsOf: [current, next, current + 1, next + 1])
            }
            outlineIndices.append(contentsOf: [0, 1, Int32(vertices.count - 2), Int32(vertices.count - 1)])
            let outlineGeometry = SCNGeometry(
                sources: [SCNGeometrySource(vertices: vertices)],
                elements: [SCNGeometryElement(indices: outlineIndices, primitiveType: .line)]
            )
            outlineGeometry.firstMaterial = outlineMaterial
            let outlineNode = SCNNode(geometry: outlineGeometry)
            outlineNode.renderingOrder = 903
            indicator.addChildNode(outlineNode)

            var centerIndices: [Int32] = []
            for index in 0..<(centerVertices.count - 1) {
                centerIndices.append(contentsOf: [Int32(index), Int32(index + 1)])
            }
            let centerGeometry = SCNGeometry(
                sources: [SCNGeometrySource(vertices: centerVertices)],
                elements: [SCNGeometryElement(indices: centerIndices, primitiveType: .line)]
            )
            centerGeometry.firstMaterial = outlineMaterial
            let centerNode = SCNNode(geometry: centerGeometry)
            centerNode.renderingOrder = 904
            indicator.addChildNode(centerNode)
            return indicator
        }

        private func makeSelectionIndicator(minimum: SCNVector3, maximum: SCNVector3) -> SCNNode {

            let padding = max(
                max(maximum.x - minimum.x, maximum.y - minimum.y),
                maximum.z - minimum.z
            ) * 0.02
            let minX = minimum.x - padding
            let minY = minimum.y - padding
            let minZ = minimum.z - padding
            let maxX = maximum.x + padding
            let maxY = maximum.y + padding
            let maxZ = maximum.z + padding
            let vertices = [
                SCNVector3(minX, minY, minZ), SCNVector3(maxX, minY, minZ),
                SCNVector3(maxX, minY, maxZ), SCNVector3(minX, minY, maxZ),
                SCNVector3(minX, maxY, minZ), SCNVector3(maxX, maxY, minZ),
                SCNVector3(maxX, maxY, maxZ), SCNVector3(minX, maxY, maxZ),
            ]
            let edgeIndices: [Int32] = [
                0, 1, 1, 2, 2, 3, 3, 0,
                4, 5, 5, 6, 6, 7, 7, 4,
                0, 4, 1, 5, 2, 6, 3, 7,
            ]
            let geometry = SCNGeometry(
                sources: [SCNGeometrySource(vertices: vertices)],
                elements: [SCNGeometryElement(indices: edgeIndices, primitiveType: .line)]
            )
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = UIColor(rgb: 0xFFD36A)
            material.emission.contents = UIColor(rgb: 0xE7A83E)
            material.readsFromDepthBuffer = false
            material.writesToDepthBuffer = false
            geometry.firstMaterial = material

            let indicator = SCNNode()
            indicator.name = "asset-studio-selection"

            let boxNode = SCNNode(geometry: geometry)
            boxNode.renderingOrder = 900
            indicator.addChildNode(boxNode)

            return indicator
        }

        private func installGestures(on view: SCNView) {
            let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            singleTap.numberOfTapsRequired = 1

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            singleTap.require(toFail: doubleTap)

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 1
            pan.allowedScrollTypesMask = [.continuous, .discrete]
            pan.delegate = self

            let verticalPan = UIPanGestureRecognizer(target: self, action: #selector(handleVerticalPan(_:)))
            verticalPan.minimumNumberOfTouches = 2
            verticalPan.maximumNumberOfTouches = 2
            verticalPan.delegate = self

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            longPress.minimumPressDuration = 0.42
            longPress.allowableMovement = 12
            longPress.delegate = self

            let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))

            view.addGestureRecognizer(singleTap)
            view.addGestureRecognizer(doubleTap)
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(verticalPan)
            view.addGestureRecognizer(pinch)
            view.addGestureRecognizer(longPress)
            view.addGestureRecognizer(hover)
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = sceneView else { return }
            view.becomeFirstResponder()
            if owner.store.manipulationMode == .paint,
               let point = paintingPoint(at: gesture.location(in: view), in: view) {
                _ = owner.store.beginPaintStroke(at: point)
                owner.store.endInteractiveEdit()
                Haptics.tap(.light)
                return
            }
            if owner.store.manipulationMode == .terrain,
               let point = terrainPoint(at: gesture.location(in: view), in: view) {
                _ = owner.store.beginTerrainStroke(at: point)
                owner.store.endInteractiveEdit()
                Haptics.tap(.medium)
                return
            }
            if owner.store.manipulationMode == .place,
               let assetID = owner.store.placementBrushAssetID,
               let point = paintingPoint(at: gesture.location(in: view), in: view) {
                _ = owner.store.add(assetID: assetID, at: point)
                Haptics.tap(.medium)
                return
            }
            let id = owner.store.manipulationMode == .select
                ? selectableID(at: gesture.location(in: view), in: view)
                : placementID(at: gesture.location(in: view), in: view)
            owner.store.select(id)
            refreshSelectionIfNeeded()
        }

        @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = sceneView else { return }
            let id = owner.store.manipulationMode == .select
                ? selectableID(at: gesture.location(in: view), in: view)
                : placementID(at: gesture.location(in: view), in: view)
            if let id {
                owner.store.select(id)
                renderedSelectionIDs.removeAll()
                refreshSelectionIfNeeded()
                focusSelection(animated: true)
            } else if owner.store.manipulationMode == .camera || owner.store.manipulationMode == .select,
                      let worldPoint = editableWorldPoint(at: gesture.location(in: view), in: view) {
                cameraTarget = worldPoint
                cameraDistance *= 0.58
                updateCamera(animated: 0.30)
                Haptics.tap(.medium)
            } else {
                resetCamera(animated: true)
            }
        }

        @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began,
                  let view = sceneView,
                  (owner.store.manipulationMode == .camera || owner.store.manipulationMode == .select),
                  let worldPoint = editableWorldPoint(at: gesture.location(in: view), in: view)
            else { return }
            cameraTarget = worldPoint
            updateCamera(animated: 0.24)
            Haptics.tap(.medium)
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = sceneView else { return }
            view.becomeFirstResponder()
            if gesture.numberOfTouches == 0 {
                handlePointerScroll(gesture, in: view)
                return
            }
            if gesture.buttonMask.contains(.secondary) {
                handlePointerOrbit(gesture, in: view)
                return
            }
            if owner.store.manipulationMode == .paint {
                handlePaintPan(gesture, in: view)
                return
            }
            if owner.store.manipulationMode == .terrain {
                handleTerrainPan(gesture, in: view)
                return
            }
            if owner.store.manipulationMode == .select {
                handleMarqueeSelection(gesture, in: view)
                return
            }
            let translation = gesture.translation(in: view)
            let store = owner.store

            switch gesture.state {
            case .began:
                initialAzimuth = cameraAzimuth
                initialElevation = cameraElevation
                initialCameraTarget = cameraTarget
                interactionID = store.selectedID
                initialTransform = store.selectedPlacement?.transform
                let isTransformMode = store.manipulationMode == .move
                    || store.manipulationMode == .height
                    || store.manipulationMode == .rotate
                    || store.manipulationMode == .scale
                panEditsSelection = isTransformMode
                    && store.selectedID != nil
                    && !gesture.buttonMask.contains(.secondary)
                    && placementID(at: gesture.location(in: view), in: view) == store.selectedID
                initialWorldDragPoint = nil
                initialNodeWorldPosition = nil
                if panEditsSelection {
                    if store.manipulationMode == .height {
                        store.followsPlacementSurface = false
                    }
                    store.beginInteractiveEdit()
                    if store.manipulationMode == .move,
                       let id = interactionID,
                       let node = placementNodes[id] {
                        dragPlaneY = node.presentation.worldPosition.y
                        initialWorldDragPoint = worldPoint(
                            at: gesture.location(in: view),
                            onHorizontalPlaneAt: dragPlaneY,
                            in: view
                        )
                        initialNodeWorldPosition = node.presentation.worldPosition
                    }
                }

            case .changed:
                if !panEditsSelection {
                    cameraAzimuth = initialAzimuth - Float(translation.x) * 0.0064
                    // 横方向は360度回転させ、縦方向は指の移動と同じ向きで傾ける。
                    // 実際の上下限は updateCamera() 内で安全な範囲に制約される。
                    cameraElevation = initialElevation + Float(translation.y) * 0.0052
                    updateCamera()
                    return
                }
                guard let id = interactionID, let start = initialTransform else { return }
                switch store.manipulationMode {
                case .select:
                    break
                case .paint:
                    break
                case .terrain:
                    break
                case .place:
                    break
                case .move:
                    if let dragStart = initialWorldDragPoint,
                       let nodeStart = initialNodeWorldPosition,
                       let currentPoint = worldPoint(
                            at: gesture.location(in: view),
                            onHorizontalPlaneAt: dragPlaneY,
                            in: view
                       ) {
                        let movedWorldPosition = SCNVector3(
                            nodeStart.x + currentPoint.x - dragStart.x,
                            nodeStart.y,
                            nodeStart.z + currentPoint.z - dragStart.z
                        )
                        let localPosition = placementParent.convertPosition(movedWorldPosition, from: nil)
                        let restingY = placementNodes[id].flatMap {
                            restingOriginY(for: $0, atX: localPosition.x, z: localPosition.z, excluding: id)
                        }
                        let adjustedY = restingY.map {
                            store.followsPlacementSurface ? $0 : max(start.y, $0)
                        }
                        store.updatePlacement(id: id, interactively: true) { placement in
                            placement.transform.x = localPosition.x
                            placement.transform.z = localPosition.z
                            if let adjustedY { placement.transform.y = adjustedY }
                        }
                    } else {
                        let sensitivity = max(cameraDistance, 2) * 0.00135
                        let dx = Float(translation.x) * sensitivity
                        let dz = Float(translation.y) * sensitivity
                        let localAzimuth = cameraAzimuth - placementParent.eulerAngles.y
                        let targetX = start.x + dx * cos(localAzimuth) + dz * sin(localAzimuth)
                        let targetZ = start.z - dx * sin(localAzimuth) + dz * cos(localAzimuth)
                        let restingY = placementNodes[id].flatMap {
                            restingOriginY(for: $0, atX: targetX, z: targetZ, excluding: id)
                        }
                        let adjustedY = restingY.map {
                            store.followsPlacementSurface ? $0 : max(start.y, $0)
                        }
                        store.updatePlacement(id: id, interactively: true) { placement in
                            placement.transform.x = targetX
                            placement.transform.z = targetZ
                            if let adjustedY { placement.transform.y = adjustedY }
                        }
                    }
                case .height:
                    let sensitivity = max(cameraDistance, 2) * 0.00135
                    let proposedY = start.y - Float(translation.y) * sensitivity
                    let minimumY = placementNodes[id].flatMap {
                        restingOriginY(for: $0, atX: start.x, z: start.z, excluding: id)
                    }
                    store.updatePlacement(id: id, interactively: true) { placement in
                        placement.transform.y = max(proposedY, minimumY ?? proposedY)
                    }
                case .rotate:
                    store.updatePlacement(id: id, interactively: true) { placement in
                        placement.transform.yaw = start.yaw + Float(translation.x) * 0.012
                        placement.transform.pitch = min(max(start.pitch + Float(translation.y) * 0.006, -.pi / 2), .pi / 2)
                    }
                case .scale:
                    let multiplier = exp(-Float(translation.y) * 0.008)
                    store.updatePlacement(id: id, interactively: true) { placement in
                        placement.transform.scale = start.scale * multiplier
                    }
                case .camera:
                    break
                }

            case .ended, .cancelled, .failed:
                if !panEditsSelection, gesture.state == .ended {
                    let velocity = gesture.velocity(in: view)
                    cameraAzimuth -= Float(velocity.x) * 0.00010
                    cameraElevation += Float(velocity.y) * 0.000075
                    updateCamera(animated: 0.18)
                } else if panEditsSelection {
                    store.endInteractiveEdit()
                    if store.manipulationMode == .rotate || store.manipulationMode == .scale {
                        store.requestSurfaceSnap(clampOnly: !store.followsPlacementSurface)
                    }
                }
                interactionID = nil
                initialTransform = nil
                panEditsSelection = false
                initialWorldDragPoint = nil
                initialNodeWorldPosition = nil
            default:
                break
            }
        }

        /// Macのマウスホイールとトラックパッドスクロールは、
        /// どのツール中でもキャンバスをズームする。
        private func handlePointerScroll(_ gesture: UIPanGestureRecognizer, in view: SCNView) {
            let translation = gesture.translation(in: view)
            switch gesture.state {
            case .began:
                initialDistance = cameraDistance
            case .changed:
                cameraDistance = initialDistance * exp(Float(translation.y) * 0.006)
                updateCamera()
            case .ended, .cancelled, .failed:
                updateCamera(animated: 0.10)
            default:
                break
            }
        }

        /// 右ボタンドラッグは変形ツールより優先し、常にカメラ周回とする。
        private func handlePointerOrbit(_ gesture: UIPanGestureRecognizer, in view: SCNView) {
            let translation = gesture.translation(in: view)
            switch gesture.state {
            case .began:
                initialAzimuth = cameraAzimuth
                initialElevation = cameraElevation
            case .changed:
                cameraAzimuth = initialAzimuth - Float(translation.x) * 0.0064
                cameraElevation = initialElevation + Float(translation.y) * 0.0052
                updateCamera()
            case .ended, .cancelled, .failed:
                updateCamera(animated: 0.12)
            default:
                break
            }
        }

        /// マウスで筆を下ろす前に、ペンと地形ブラシの実際の範囲を見せる。
        @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
            guard let view = sceneView else { return }
            guard gesture.state != .ended, gesture.state != .cancelled else {
                hideBrushPreview()
                return
            }
            let location = gesture.location(in: view)
            switch owner.store.manipulationMode {
            case .paint:
                if let point = paintingPoint(at: location, in: view) {
                    showBrushPreview(
                        at: point,
                        radius: max(owner.store.paintWidth * 0.5, 0.04),
                        color: owner.store.paintTool.material?.color ?? UIColor(rgb: 0xFF746B)
                    )
                } else {
                    hideBrushPreview()
                }
            case .terrain:
                if let point = terrainPoint(at: location, in: view) {
                    showBrushPreview(
                        at: point,
                        radius: owner.store.terrainRadius,
                        color: terrainPreviewColor
                    )
                } else {
                    hideBrushPreview()
                }
            default:
                hideBrushPreview()
            }
        }

        private func handleKeyboardCommand(_ command: UIKeyCommand) {
            let input = command.input?.lowercased() ?? ""
            let modifiers = command.modifierFlags

            if modifiers.contains(.command), input == "z" {
                if modifiers.contains(.shift) {
                    owner.store.redo()
                } else {
                    owner.store.undo()
                }
                synchronize()
                return
            }
            if modifiers.contains(.command), input == "d" {
                owner.store.duplicateSelected()
                synchronize()
                return
            }
            if input == UIKeyCommand.inputDelete.lowercased() {
                owner.store.deleteSelected()
                synchronize()
                return
            }
            if input == UIKeyCommand.inputEscape.lowercased() {
                owner.store.select(nil)
                refreshSelectionIfNeeded()
                return
            }

            switch input {
            case "w", UIKeyCommand.inputUpArrow.lowercased():
                nudgeCamera(forward: 1, right: 0)
            case "s", UIKeyCommand.inputDownArrow.lowercased():
                nudgeCamera(forward: -1, right: 0)
            case "a", UIKeyCommand.inputLeftArrow.lowercased():
                nudgeCamera(forward: 0, right: -1)
            case "d", UIKeyCommand.inputRightArrow.lowercased():
                nudgeCamera(forward: 0, right: 1)
            case "q":
                cameraAzimuth -= 0.16
                updateCamera(animated: 0.12)
            case "e":
                cameraAzimuth += 0.16
                updateCamera(animated: 0.12)
            case "=":
                zoomCamera(by: 0.84)
            case "-":
                zoomCamera(by: 1.18)
            case "0":
                showOverview(animated: true)
            case "f":
                focusSelection(animated: true)
            case "1":
                owner.store.manipulationMode = .select
            case "2":
                owner.store.manipulationMode = .move
            case "3":
                owner.store.manipulationMode = .height
            case "4":
                owner.store.manipulationMode = .rotate
            case "5":
                owner.store.manipulationMode = .scale
            case "6":
                owner.store.manipulationMode = .camera
            case "7":
                owner.store.manipulationMode = .paint
            case "8":
                owner.store.manipulationMode = .terrain
            default:
                break
            }
        }

        private func handlePaintPan(_ gesture: UIPanGestureRecognizer, in view: SCNView) {
            let location = gesture.location(in: view)
            switch gesture.state {
            case .began:
                guard let point = paintingPoint(at: location, in: view) else { return }
                showBrushPreview(
                    at: point,
                    radius: max(owner.store.paintWidth * 0.5, 0.04),
                    color: owner.store.paintTool.material?.color ?? UIColor(rgb: 0xFF746B)
                )
                activePaintStrokeID = owner.store.beginPaintStroke(at: point)
                lastPaintPoint = point
            case .changed:
                guard let point = paintingPoint(at: location, in: view) else { return }
                showBrushPreview(
                    at: point,
                    radius: max(owner.store.paintWidth * 0.5, 0.04),
                    color: owner.store.paintTool.material?.color ?? UIColor(rgb: 0xFF746B)
                )
                appendPaintSamples(through: point)
            case .ended, .cancelled, .failed:
                if let point = paintingPoint(at: location, in: view) {
                    appendPaintSamples(through: point)
                }
                owner.store.endInteractiveEdit()
                activePaintStrokeID = nil
                lastPaintPoint = nil
                hideBrushPreview()
                lastPaintGeometryRefresh = 0
                synchronize()
                Haptics.tap(.light)
            default:
                break
            }
        }

        private func handleTerrainPan(_ gesture: UIPanGestureRecognizer, in view: SCNView) {
            let location = gesture.location(in: view)
            switch gesture.state {
            case .began:
                guard let point = terrainPoint(at: location, in: view) else { return }
                showBrushPreview(
                    at: point,
                    radius: owner.store.terrainRadius,
                    color: terrainPreviewColor
                )
                activeTerrainStrokeID = owner.store.beginTerrainStroke(at: point)
                lastTerrainPoint = point
            case .changed:
                guard let point = terrainPoint(at: location, in: view) else { return }
                showBrushPreview(
                    at: point,
                    radius: owner.store.terrainRadius,
                    color: terrainPreviewColor
                )
                appendTerrainSamples(through: point)
            case .ended, .cancelled, .failed:
                if let point = terrainPoint(at: location, in: view) {
                    appendTerrainSamples(through: point)
                }
                owner.store.endInteractiveEdit()
                activeTerrainStrokeID = nil
                lastTerrainPoint = nil
                hideBrushPreview()
                lastTerrainGeometryRefresh = 0
                synchronize()
                Haptics.tap(.medium)
            default:
                break
            }
        }

        private var terrainPreviewColor: UIColor {
            switch owner.store.terrainTool {
            case .raise: return UIColor(rgb: 0xFFD36A)
            case .lower: return UIColor(rgb: 0xFF746B)
            case .smooth: return UIColor(rgb: 0x6ED0B0)
            }
        }

        private func showBrushPreview(
            at point: AssetPaintPoint,
            radius: Float,
            color: UIColor
        ) {
            let preview: SCNNode
            if let brushPreviewNode {
                preview = brushPreviewNode
            } else {
                preview = SCNNode()
                preview.name = "asset-studio-brush-preview"

                let ringMaterial = VoyageSceneKit.unlitMaterial(color)
                ringMaterial.readsFromDepthBuffer = false
                ringMaterial.writesToDepthBuffer = false
                let ringGeometry = SCNTorus(ringRadius: 1, pipeRadius: 0.025)
                ringGeometry.ringSegmentCount = 56
                ringGeometry.pipeSegmentCount = 6
                ringGeometry.firstMaterial = ringMaterial
                let ringNode = SCNNode(geometry: ringGeometry)
                ringNode.name = "asset-studio-brush-preview-ring"
                ringNode.renderingOrder = 920
                preview.addChildNode(ringNode)

                let centerMaterial = VoyageSceneKit.unlitMaterial(color.withAlphaComponent(0.10))
                centerMaterial.readsFromDepthBuffer = false
                centerMaterial.writesToDepthBuffer = false
                let centerGeometry = SCNCylinder(radius: 1, height: 0.008)
                centerGeometry.radialSegmentCount = 40
                centerGeometry.firstMaterial = centerMaterial
                let centerNode = SCNNode(geometry: centerGeometry)
                centerNode.renderingOrder = 919
                preview.addChildNode(centerNode)

                placementParent.addChildNode(preview)
                brushPreviewNode = preview
            }
            preview.position = SCNVector3(point.x, point.y + 0.065, point.z)
            preview.scale = SCNVector3(radius, 1, radius)
            for child in preview.childNodes {
                let displayColor = child.name == "asset-studio-brush-preview-ring"
                    ? color
                    : color.withAlphaComponent(0.10)
                child.geometry?.firstMaterial?.diffuse.contents = displayColor
                child.geometry?.firstMaterial?.emission.contents = displayColor
            }
        }

        private func hideBrushPreview() {
            brushPreviewNode?.removeFromParentNode()
            brushPreviewNode = nil
        }

        private func appendTerrainSamples(through point: AssetPaintPoint) {
            guard let lastTerrainPoint else { return }
            let dx = point.x - lastTerrainPoint.x
            let dy = point.y - lastTerrainPoint.y
            let dz = point.z - lastTerrainPoint.z
            let distance = sqrt(dx * dx + dz * dz)
            let spacing = max(owner.store.terrainRadius * 0.18, 0.055)
            guard distance >= spacing else { return }
            let steps = max(Int(ceil(distance / spacing)), 1)
            guard let activeTerrainStrokeID else { return }

            for step in 1...steps {
                let progress = Float(step) / Float(steps)
                owner.store.appendTerrainPoint(
                    AssetPaintPoint(
                        x: lastTerrainPoint.x + dx * progress,
                        y: lastTerrainPoint.y + dy * progress,
                        z: lastTerrainPoint.z + dz * progress
                    ),
                    to: activeTerrainStrokeID
                )
            }
            self.lastTerrainPoint = point
        }

        private func appendPaintSamples(through point: AssetPaintPoint) {
            guard let lastPaintPoint else { return }
            let dx = point.x - lastPaintPoint.x
            let dy = point.y - lastPaintPoint.y
            let dz = point.z - lastPaintPoint.z
            let distance = sqrt(dx * dx + dz * dz)
            let spacing = max(owner.store.paintWidth * 0.16, 0.035)
            guard distance >= spacing else { return }
            let steps = max(Int(ceil(distance / spacing)), 1)

            for step in 1...steps {
                let progress = Float(step) / Float(steps)
                let sample = AssetPaintPoint(
                    x: lastPaintPoint.x + dx * progress,
                    y: lastPaintPoint.y + dy * progress,
                    z: lastPaintPoint.z + dz * progress
                )
                if owner.store.paintTool == .eraser {
                    owner.store.erasePaint(at: sample)
                } else if let activePaintStrokeID {
                    owner.store.appendPaintPoint(sample, to: activePaintStrokeID)
                }
            }
            self.lastPaintPoint = point
        }

        private func paintingPoint(at screenPoint: CGPoint, in view: SCNView) -> AssetPaintPoint? {
            let hits = view.hitTest(screenPoint, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue,
                .ignoreHiddenNodes: true,
                .boundingBoxOnly: false,
            ])
            for hit in hits {
                if nodeOrAncestor(hit.node, hasNamePrefix: "asset-studio-paint:")
                    || nodeOrAncestor(hit.node, hasNamePrefix: "asset-studio-selection")
                    || nodeOrAncestor(hit.node, hasNamePrefix: "asset-studio-brush-preview")
                    || nodeOrAncestor(hit.node, hasNamePrefix: "asset-studio-home-ship-marker") {
                    continue
                }

                let local = placementParent.convertPosition(hit.worldCoordinates, from: nil)
                if nodeOrAncestor(hit.node, hasNamePrefix: "asset-studio-terrain") {
                    return AssetPaintPoint(x: local.x, y: local.y, z: local.z)
                }
                var surfaceY = local.y
                if let placementID = placementID(for: hit.node),
                   let placement = owner.store.visiblePlacements.first(where: { $0.id == placementID }) {
                    if !Asset3DCatalog.providesPlacementSurface(for: placement.assetID) {
                        continue
                    }
                } else if hasPlacementSurfaceCategory(hit.node) {
                    surfaceY = local.y
                } else if renderedContext == .destinationIsland,
                          owner.store.activeStudioID == nil {
                    surfaceY = basePaintSurfaceY(x: local.x, z: local.z)
                } else if nodeOrAncestor(hit.node, hasNamePrefix: "asset-studio-ground") {
                    surfaceY = renderedContext == .destinationIsland ? -0.055 : 0
                } else {
                    continue
                }
                return AssetPaintPoint(x: local.x, y: surfaceY, z: local.z)
            }
            return nil
        }

        /// 山自身の表面ではなく、その下の土台をブラシの基準高にする。
        /// これにより繰り返し盛っても高さが二重加算されない。
        private func terrainPoint(at screenPoint: CGPoint, in view: SCNView) -> AssetPaintPoint? {
            let hits = view.hitTest(screenPoint, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue,
                .ignoreHiddenNodes: true,
                .boundingBoxOnly: false,
            ])
            for hit in hits {
                if nodeOrAncestor(hit.node, hasNamePrefix: "asset-studio-paint:")
                    || nodeOrAncestor(hit.node, hasNamePrefix: "asset-studio-terrain")
                    || nodeOrAncestor(hit.node, hasNamePrefix: "asset-studio-selection")
                    || nodeOrAncestor(hit.node, hasNamePrefix: "asset-studio-brush-preview")
                    || nodeOrAncestor(hit.node, hasNamePrefix: "asset-studio-home-ship-marker") {
                    continue
                }
                let local = placementParent.convertPosition(hit.worldCoordinates, from: nil)
                if hasPlacementSurfaceCategory(hit.node) {
                    return AssetPaintPoint(x: local.x, y: local.y, z: local.z)
                }
                if nodeOrAncestor(hit.node, hasNamePrefix: "asset-studio-ground") {
                    let baseY: Float = renderedContext == .destinationIsland ? -0.055 : 0
                    return AssetPaintPoint(x: local.x, y: baseY, z: local.z)
                }
                if renderedContext == .destinationIsland,
                   owner.store.activeStudioID == nil {
                    return AssetPaintPoint(
                        x: local.x,
                        y: basePaintSurfaceY(x: local.x, z: local.z),
                        z: local.z
                    )
                }
            }
            return nil
        }

        private func hasPlacementSurfaceCategory(_ node: SCNNode) -> Bool {
            var candidate: SCNNode? = node
            while let current = candidate {
                if let body = current.physicsBody,
                   body.categoryBitMask & AssetPlacementRuntime.placementSurfaceCategory != 0 {
                    return true
                }
                candidate = current.parent
            }
            return false
        }

        private func basePaintSurfaceY(x: Float, z: Float) -> Float {
            switch renderedContext ?? owner.store.context {
            case .destinationIsland:
                return VoyageSceneKit.islandSurfaceHeight(x: x, z: z)
            case .studio:
                return 0
            }
        }

        private func placementID(for node: SCNNode) -> UUID? {
            var candidate: SCNNode? = node
            while let current = candidate {
                if let name = current.name,
                   name.hasPrefix("placement:"),
                   let id = UUID(uuidString: String(name.dropFirst("placement:".count))) {
                    return id
                }
                candidate = current.parent
            }
            return nil
        }

        private func nodeOrAncestor(_ node: SCNNode, hasNamePrefix prefix: String) -> Bool {
            var candidate: SCNNode? = node
            while let current = candidate {
                if current.name?.hasPrefix(prefix) == true { return true }
                candidate = current.parent
            }
            return false
        }

        private func handleMarqueeSelection(_ gesture: UIPanGestureRecognizer, in view: SCNView) {
            let location = gesture.location(in: view)
            switch gesture.state {
            case .began:
                marqueeStart = location
                selectionMarqueeView?.frame = CGRect(origin: location, size: .zero)
                selectionMarqueeView?.isHidden = false
            case .changed:
                guard let marqueeStart else { return }
                selectionMarqueeView?.frame = selectionRect(from: marqueeStart, to: location)
            case .ended:
                guard let marqueeStart else { return }
                let rectangle = selectionRect(from: marqueeStart, to: location)
                let ids = selectableIDs(in: rectangle, in: view)
                owner.store.select(ids)
                refreshSelectionIfNeeded()
                selectionMarqueeView?.isHidden = true
                self.marqueeStart = nil
                Haptics.tap(ids.isEmpty ? .light : .medium)
            case .cancelled, .failed:
                selectionMarqueeView?.isHidden = true
                marqueeStart = nil
            default:
                break
            }
        }

        private func selectionRect(from start: CGPoint, to end: CGPoint) -> CGRect {
            CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        }

        private func selectableIDs(in rectangle: CGRect, in view: SCNView) -> Set<UUID> {
            guard rectangle.width >= 5, rectangle.height >= 5 else { return [] }
            var result: Set<UUID> = Set(placementNodes.compactMap { id, node -> UUID? in
                guard let bounds = worldBounds(of: node) else { return nil }
                let center = SCNVector3(
                    (bounds.minimum.x + bounds.maximum.x) * 0.5,
                    (bounds.minimum.y + bounds.maximum.y) * 0.5,
                    (bounds.minimum.z + bounds.maximum.z) * 0.5
                )
                let projected = view.projectPoint(center)
                guard projected.x.isFinite, projected.y.isFinite, projected.z >= 0, projected.z <= 1 else {
                    return nil
                }
                let screenPoint = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
                return rectangle.contains(screenPoint) ? id : nil
            })

            for stroke in owner.store.visiblePaintStrokes {
                if let bounds = projectedStrokeBounds(
                    points: stroke.points,
                    radius: max(stroke.width * 0.5, 0.04),
                    in: view
                ), rectangle.intersects(bounds) {
                    result.insert(stroke.id)
                }
            }
            for stroke in owner.store.visibleTerrainStrokes {
                if let bounds = projectedStrokeBounds(
                    points: stroke.points,
                    radius: max(stroke.radius, 0.08),
                    in: view
                ), rectangle.intersects(bounds) {
                    result.insert(stroke.id)
                }
            }
            return result
        }

        private func projectedStrokeBounds(
            points: [AssetPaintPoint],
            radius: Float,
            in view: SCNView
        ) -> CGRect? {
            var projectedPoints: [CGPoint] = []
            for point in points {
                let samples = [
                    SCNVector3(point.x, point.y, point.z),
                    SCNVector3(point.x - radius, point.y, point.z),
                    SCNVector3(point.x + radius, point.y, point.z),
                    SCNVector3(point.x, point.y, point.z - radius),
                    SCNVector3(point.x, point.y, point.z + radius),
                ]
                for sample in samples {
                    let world = placementParent.convertPosition(sample, to: nil)
                    let projected = view.projectPoint(world)
                    guard projected.x.isFinite,
                          projected.y.isFinite,
                          projected.z >= 0,
                          projected.z <= 1
                    else { continue }
                    projectedPoints.append(CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y)))
                }
            }
            guard let first = projectedPoints.first else { return nil }
            var minimumX = first.x
            var maximumX = first.x
            var minimumY = first.y
            var maximumY = first.y
            for point in projectedPoints.dropFirst() {
                minimumX = min(minimumX, point.x)
                maximumX = max(maximumX, point.x)
                minimumY = min(minimumY, point.y)
                maximumY = max(maximumY, point.y)
            }
            return CGRect(
                x: minimumX,
                y: minimumY,
                width: max(maximumX - minimumX, 2),
                height: max(maximumY - minimumY, 2)
            )
        }

        @objc private func handleVerticalPan(_ gesture: UIPanGestureRecognizer) {
            guard let view = sceneView else { return }
            let store = owner.store
            let editCamera = store.manipulationMode == .camera
                || store.manipulationMode == .select
                || store.manipulationMode == .paint
                || store.manipulationMode == .terrain
                || store.manipulationMode == .place
                || store.selectedPlacement == nil
            let translation = gesture.translation(in: view)

            switch gesture.state {
            case .began:
                initialCameraTarget = cameraTarget
                interactionID = store.selectedID
                initialTransform = store.selectedPlacement?.transform
                if !editCamera {
                    store.followsPlacementSurface = false
                    store.beginInteractiveEdit()
                }
            case .changed:
                if editCamera {
                    let sensitivity = max(cameraDistance, 2) * 0.00125
                    let horizontal = Float(translation.x) * sensitivity
                    let vertical = Float(translation.y) * sensitivity
                    let right = SCNVector3(cos(cameraAzimuth), 0, -sin(cameraAzimuth))
                    let up = SCNVector3(
                        -sin(cameraAzimuth) * sin(cameraElevation),
                        cos(cameraElevation),
                        -cos(cameraAzimuth) * sin(cameraElevation)
                    )
                    cameraTarget = SCNVector3(
                        initialCameraTarget.x - right.x * horizontal + up.x * vertical,
                        initialCameraTarget.y - right.y * horizontal + up.y * vertical,
                        initialCameraTarget.z - right.z * horizontal + up.z * vertical
                    )
                    updateCamera()
                } else if let id = interactionID, let start = initialTransform {
                    let sensitivity = max(cameraDistance, 2) * 0.00135
                    let proposedY = start.y - Float(translation.y) * sensitivity
                    let minimumY = placementNodes[id].flatMap {
                        restingOriginY(for: $0, atX: start.x, z: start.z, excluding: id)
                    }
                    store.updatePlacement(id: id, interactively: true) { placement in
                        placement.transform.y = max(proposedY, minimumY ?? proposedY)
                    }
                }
            case .ended, .cancelled, .failed:
                if !editCamera {
                    store.endInteractiveEdit()
                    store.requestSurfaceSnap(clampOnly: !store.followsPlacementSurface)
                }
                interactionID = nil
                initialTransform = nil
            default:
                break
            }
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            let store = owner.store
            switch gesture.state {
            case .began:
                initialDistance = cameraDistance
                initialCameraTarget = cameraTarget
                interactionID = store.selectedID
                initialTransform = store.selectedPlacement?.transform
                let location = sceneView.map { gesture.location(in: $0) }
                let isTransformMode = store.manipulationMode == .move
                    || store.manipulationMode == .height
                    || store.manipulationMode == .rotate
                    || store.manipulationMode == .scale
                let pinchHitsSelection: Bool
                if let view = sceneView, let location {
                    pinchHitsSelection = placementID(at: location, in: view) == store.selectedID
                } else {
                    pinchHitsSelection = false
                }
                pinchEditsSelection = isTransformMode
                    && store.selectedID != nil
                    && pinchHitsSelection
                if pinchEditsSelection {
                    pinchAnchorWorldPoint = nil
                    store.beginInteractiveEdit()
                } else if let view = sceneView {
                    pinchAnchorWorldPoint = editableWorldPoint(
                        at: gesture.location(in: view),
                        in: view
                    )
                } else {
                    pinchAnchorWorldPoint = nil
                }
            case .changed:
                if pinchEditsSelection, let id = interactionID, let start = initialTransform {
                    store.updatePlacement(id: id, interactively: true) { placement in
                        placement.transform.scale = start.scale * Float(gesture.scale)
                    }
                } else {
                    cameraDistance = initialDistance / pow(Float(gesture.scale), 0.86)
                    if let anchor = pinchAnchorWorldPoint {
                        let focusStrength = min(
                            max(1 - cameraDistance / max(initialDistance, 0.001), 0),
                            0.78
                        )
                        cameraTarget = SCNVector3(
                            initialCameraTarget.x + (anchor.x - initialCameraTarget.x) * focusStrength,
                            initialCameraTarget.y + (anchor.y - initialCameraTarget.y) * focusStrength,
                            initialCameraTarget.z + (anchor.z - initialCameraTarget.z) * focusStrength
                        )
                    }
                    updateCamera()
                }
            case .ended, .cancelled, .failed:
                if pinchEditsSelection {
                    store.endInteractiveEdit()
                    store.requestSurfaceSnap(clampOnly: !store.followsPlacementSurface)
                }
                interactionID = nil
                initialTransform = nil
                pinchEditsSelection = false
                pinchAnchorWorldPoint = nil
            default:
                break
            }
        }

        private func placementID(at point: CGPoint, in view: SCNView) -> UUID? {
            let hits = view.hitTest(point, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue,
                .ignoreHiddenNodes: true,
                .boundingBoxOnly: false
            ])
            for hit in hits {
                var node: SCNNode? = hit.node
                while let current = node {
                    if let name = current.name,
                       name.hasPrefix("placement:"),
                       let id = UUID(uuidString: String(name.dropFirst("placement:".count))) {
                        return id
                    }
                    node = current.parent
                }
            }
            return nil
        }

        private func editableWorldPoint(at point: CGPoint, in view: SCNView) -> SCNVector3? {
            let hits = view.hitTest(point, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue,
                .ignoreHiddenNodes: true,
                .boundingBoxOnly: false,
            ])
            for hit in hits {
                if nodeOrAncestor(hit.node, hasNamePrefix: "asset-studio-selection")
                    || nodeOrAncestor(hit.node, hasNamePrefix: "asset-studio-home-ship-marker") {
                    continue
                }
                return hit.worldCoordinates
            }
            return nil
        }

        private func selectableID(at point: CGPoint, in view: SCNView) -> UUID? {
            let hits = view.hitTest(point, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue,
                .ignoreHiddenNodes: true,
                .boundingBoxOnly: false,
            ])
            var firstSurfacePoint: SCNVector3?
            var hitTerrain = false
            for hit in hits {
                if let placementID = identifier(
                    for: hit.node,
                    namePrefix: "placement:"
                ) {
                    return placementID
                }
                if let paintID = identifier(
                    for: hit.node,
                    namePrefix: "asset-studio-paint:"
                ) {
                    return paintID
                }
                if firstSurfacePoint == nil {
                    firstSurfacePoint = placementParent.convertPosition(hit.worldCoordinates, from: nil)
                }
                if nodeOrAncestor(hit.node, hasNamePrefix: "asset-studio-terrain") {
                    hitTerrain = true
                }
            }

            guard let localPoint = firstSurfacePoint else { return nil }
            if hitTerrain,
               let terrainID = nearestTerrainStrokeID(to: localPoint) {
                return terrainID
            }
            return nearestPaintStrokeID(to: localPoint)
        }

        private func identifier(for node: SCNNode, namePrefix: String) -> UUID? {
            var candidate: SCNNode? = node
            while let current = candidate {
                if let name = current.name,
                   name.hasPrefix(namePrefix),
                   let id = UUID(uuidString: String(name.dropFirst(namePrefix.count))) {
                    return id
                }
                candidate = current.parent
            }
            return nil
        }

        private func nearestPaintStrokeID(to point: SCNVector3) -> UUID? {
            var best: (id: UUID, normalizedDistance: Float)?
            for stroke in owner.store.visiblePaintStrokes.reversed() {
                let reach = max(stroke.width * 0.65, 0.07)
                let normalized = distanceFromStroke(point, to: stroke.points) / reach
                guard normalized <= 1 else { continue }
                if best == nil || normalized < best!.normalizedDistance {
                    best = (stroke.id, normalized)
                }
            }
            return best?.id
        }

        private func nearestTerrainStrokeID(to point: SCNVector3) -> UUID? {
            var best: (id: UUID, normalizedDistance: Float)?
            for stroke in owner.store.visibleTerrainStrokes.reversed() {
                let reach = max(stroke.radius, 0.08)
                let normalized = distanceFromStroke(point, to: stroke.points) / reach
                guard normalized <= 1.08 else { continue }
                if best == nil || normalized < best!.normalizedDistance {
                    best = (stroke.id, normalized)
                }
            }
            return best?.id
        }

        private func distanceFromStroke(
            _ point: SCNVector3,
            to strokePoints: [AssetPaintPoint]
        ) -> Float {
            guard let first = strokePoints.first else { return .greatestFiniteMagnitude }
            guard strokePoints.count > 1 else {
                return sqrt(pow(first.x - point.x, 2) + pow(first.z - point.z, 2))
            }
            var minimumDistance = Float.greatestFiniteMagnitude
            for index in 0..<(strokePoints.count - 1) {
                let start = strokePoints[index]
                let end = strokePoints[index + 1]
                let segmentX = end.x - start.x
                let segmentZ = end.z - start.z
                let lengthSquared = segmentX * segmentX + segmentZ * segmentZ
                let progress: Float
                if lengthSquared <= 0.000_001 {
                    progress = 0
                } else {
                    progress = min(
                        max(
                            ((point.x - start.x) * segmentX + (point.z - start.z) * segmentZ)
                                / lengthSquared,
                            0
                        ),
                        1
                    )
                }
                let closestX = start.x + segmentX * progress
                let closestZ = start.z + segmentZ * progress
                let distance = sqrt(pow(closestX - point.x, 2) + pow(closestZ - point.z, 2))
                minimumDistance = min(minimumDistance, distance)
            }
            return minimumDistance
        }

        private func worldPoint(
            at screenPoint: CGPoint,
            onHorizontalPlaneAt y: Float,
            in view: SCNView
        ) -> SCNVector3? {
            let nearPoint = view.unprojectPoint(SCNVector3(Float(screenPoint.x), Float(screenPoint.y), 0))
            let farPoint = view.unprojectPoint(SCNVector3(Float(screenPoint.x), Float(screenPoint.y), 1))
            let verticalDelta = farPoint.y - nearPoint.y
            guard abs(verticalDelta) > 0.0001 else { return nil }
            let progress = (y - nearPoint.y) / verticalDelta
            guard progress.isFinite, progress >= 0 else { return nil }
            return SCNVector3(
                nearPoint.x + (farPoint.x - nearPoint.x) * progress,
                y,
                nearPoint.z + (farPoint.z - nearPoint.z) * progress
            )
        }

        private var cameraLimits: CameraLimits {
            switch renderedContext ?? owner.store.context {
            case .destinationIsland:
                return CameraLimits(
                    minimumElevation: 0.16,
                    // 真上に近づくと look(at:) の上方向が不安定になるため、約73度で止める。
                    maximumElevation: 1.28,
                    minimumDistance: 4.6,
                    // 進捗0%時のホーム船は島から約90m。実寸の船視点を再現できる上限にする。
                    maximumDistance: 420,
                    minimumTarget: SCNVector3(-512, 0.15, -512),
                    maximumTarget: SCNVector3(512, 96, 512)
                )
            case .studio:
                return CameraLimits(
                    minimumElevation: 0.08,
                    maximumElevation: 1.28,
                    minimumDistance: 1.4,
                    maximumDistance: 420,
                    minimumTarget: SCNVector3(-512, -12, -512),
                    maximumTarget: SCNVector3(512, 96, 512)
                )
            }
        }

        private func resetCamera(animated: Bool) {
            cameraAzimuth = nearestEquivalentAzimuth(to: 0.72)
            switch renderedContext ?? owner.store.context {
            case .destinationIsland:
                cameraTarget = SCNVector3(0, 1.9, 0)
                cameraElevation = 0.40
                cameraDistance = 14.8
            case .studio:
                cameraTarget = SCNVector3(0, 1.2, 0)
                cameraElevation = 0.38
                cameraDistance = 11.5
            }
            updateCamera(animated: animated ? 0.34 : 0)
        }

        private func showOverview(animated: Bool) {
            cameraAzimuth = nearestEquivalentAzimuth(to: 0.72)
            cameraElevation = 0.74
            if let bounds = authoredWorldBounds() {
                cameraTarget = SCNVector3(
                    (bounds.minimum.x + bounds.maximum.x) * 0.5,
                    max((bounds.minimum.y + bounds.maximum.y) * 0.5, 0.7),
                    (bounds.minimum.z + bounds.maximum.z) * 0.5
                )
                let width = bounds.maximum.x - bounds.minimum.x
                let height = bounds.maximum.y - bounds.minimum.y
                let depth = bounds.maximum.z - bounds.minimum.z
                let radius = max(sqrt(width * width + height * height + depth * depth) * 0.5, 4.5)
                let fieldOfView = Float(cameraNode.camera?.fieldOfView ?? 46) * .pi / 180
                cameraDistance = radius / max(tan(fieldOfView * 0.5), 0.1) * 1.28
            } else {
                cameraTarget = SCNVector3(0, 1.0, 0)
                cameraDistance = renderedContext == .studio ? 58 : 22
            }
            updateCamera(animated: animated ? 0.38 : 0)
        }

        private func authoredWorldBounds() -> (minimum: SCNVector3, maximum: SCNVector3)? {
            var result: (minimum: SCNVector3, maximum: SCNVector3)?

            func include(_ next: (minimum: SCNVector3, maximum: SCNVector3)) {
                guard var current = result else {
                    result = next
                    return
                }
                current.minimum.x = min(current.minimum.x, next.minimum.x)
                current.minimum.y = min(current.minimum.y, next.minimum.y)
                current.minimum.z = min(current.minimum.z, next.minimum.z)
                current.maximum.x = max(current.maximum.x, next.maximum.x)
                current.maximum.y = max(current.maximum.y, next.maximum.y)
                current.maximum.z = max(current.maximum.z, next.maximum.z)
                result = current
            }

            if renderedContext == .destinationIsland {
                include((SCNVector3(-4.2, -0.1, -3.2), SCNVector3(4.2, 4.8, 3.2)))
            }
            for node in placementNodes.values {
                if let bounds = worldBounds(of: node) { include(bounds) }
            }
            for node in paintNodes.values {
                if let bounds = worldBounds(of: node) { include(bounds) }
            }
            for stroke in owner.store.visibleTerrainStrokes {
                if let bounds = terrainStrokeWorldBounds(stroke) { include(bounds) }
            }
            return result
        }

        /// 船の正確な地点を、島へ向かう方角ごと後方から見せる。
        private func showHomeShipMarker(animated: Bool) {
            let localBoat = AftideHomeWorldReference.boatIslandPosition(
                progressRatio: owner.homeProgressRatio
            )
            let boatPosition = placementParent.convertPosition(localBoat, to: worldRoot)
            let islandPosition = placementParent.convertPosition(SCNVector3Zero, to: worldRoot)
            let directionX = islandPosition.x - boatPosition.x
            let directionZ = islandPosition.z - boatPosition.z
            let directionLength = max(sqrt(directionX * directionX + directionZ * directionZ), 0.001)
            let normalizedX = directionX / directionLength
            let normalizedZ = directionZ / directionLength

            cameraTarget = SCNVector3(boatPosition.x, boatPosition.y + 0.82, boatPosition.z)
            cameraDistance = 7.2
            cameraElevation = 0.42
            cameraAzimuth = nearestEquivalentAzimuth(to: atan2(-normalizedX, -normalizedZ))
            updateCamera(animated: animated ? 0.42 : 0)
        }

        /// ホーム画面と同じ船上カメラ位置・注視点でプレビューする。
        private func showHomeShipView(animated: Bool) {
            let localCamera = AftideHomeWorldReference.cameraIslandPosition(
                progressRatio: owner.homeProgressRatio
            )
            let localTarget = AftideHomeWorldReference.cameraTargetIslandPosition
            let cameraPosition = placementParent.convertPosition(localCamera, to: worldRoot)
            let targetPosition = placementParent.convertPosition(localTarget, to: worldRoot)
            let dx = cameraPosition.x - targetPosition.x
            let dy = cameraPosition.y - targetPosition.y
            let dz = cameraPosition.z - targetPosition.z
            let distance = max(sqrt(dx * dx + dy * dy + dz * dz), 0.001)

            cameraTarget = targetPosition
            cameraDistance = distance
            cameraElevation = asin(min(max(dy / distance, -1), 1))
            cameraAzimuth = nearestEquivalentAzimuth(to: atan2(dx, dz))
            updateCamera(animated: animated ? 0.42 : 0)
        }

        private func nudgeCamera(forward: Float, right: Float) {
            let step = min(max(cameraDistance * 0.08, 0.60), 3.0)
            let forwardVector = SCNVector3(-sin(cameraAzimuth), 0, -cos(cameraAzimuth))
            let rightVector = SCNVector3(cos(cameraAzimuth), 0, -sin(cameraAzimuth))
            cameraTarget.x += (forwardVector.x * forward + rightVector.x * right) * step
            cameraTarget.z += (forwardVector.z * forward + rightVector.z * right) * step
            updateCamera(animated: 0.18)
        }

        private func zoomCamera(by factor: Float) {
            cameraDistance *= factor
            updateCamera(animated: 0.18)
        }

        private func focusSelection(animated: Bool) {
            var selectedBounds: [(minimum: SCNVector3, maximum: SCNVector3)] = []
            for id in owner.store.selectedIDs {
                if let node = placementNodes[id] ?? paintNodes[id],
                   let nodeBounds = worldBounds(of: node) {
                    selectedBounds.append(nodeBounds)
                } else if let stroke = owner.store.visibleTerrainStrokes.first(where: { $0.id == id }),
                          let strokeBounds = terrainStrokeWorldBounds(stroke) {
                    selectedBounds.append(strokeBounds)
                }
            }
            guard var bounds = selectedBounds.first else {
                resetCamera(animated: animated)
                return
            }

            for next in selectedBounds.dropFirst() {
                bounds.minimum.x = min(bounds.minimum.x, next.minimum.x)
                bounds.minimum.y = min(bounds.minimum.y, next.minimum.y)
                bounds.minimum.z = min(bounds.minimum.z, next.minimum.z)
                bounds.maximum.x = max(bounds.maximum.x, next.maximum.x)
                bounds.maximum.y = max(bounds.maximum.y, next.maximum.y)
                bounds.maximum.z = max(bounds.maximum.z, next.maximum.z)
            }

            cameraTarget = SCNVector3(
                (bounds.minimum.x + bounds.maximum.x) * 0.5,
                (bounds.minimum.y + bounds.maximum.y) * 0.5,
                (bounds.minimum.z + bounds.maximum.z) * 0.5
            )
            let dx = bounds.maximum.x - bounds.minimum.x
            let dy = bounds.maximum.y - bounds.minimum.y
            let dz = bounds.maximum.z - bounds.minimum.z
            let squaredDiameter: Float = dx * dx + dy * dy + dz * dz
            let radius: Float = max(sqrt(squaredDiameter) * 0.5, 0.28)
            let fieldOfView = Float(cameraNode.camera?.fieldOfView ?? 46) * .pi / 180
            cameraDistance = radius / max(tan(fieldOfView * 0.5), 0.1) * 1.35
            cameraElevation = min(max(cameraElevation, 0.24), 0.92)
            updateCamera(animated: animated ? 0.32 : 0)
        }

        private func terrainStrokeWorldBounds(
            _ stroke: AssetTerrainStroke
        ) -> (minimum: SCNVector3, maximum: SCNVector3)? {
            guard let firstPoint = stroke.points.first else { return nil }
            let radius = max(stroke.radius, 0.08)
            var localMinimum = SCNVector3(firstPoint.x - radius, firstPoint.y - 0.03, firstPoint.z - radius)
            var localMaximum = SCNVector3(
                firstPoint.x + radius,
                firstPoint.y + max(abs(stroke.strength), 0.22),
                firstPoint.z + radius
            )
            for point in stroke.points.dropFirst() {
                localMinimum.x = min(localMinimum.x, point.x - radius)
                localMinimum.y = min(localMinimum.y, point.y - 0.03)
                localMinimum.z = min(localMinimum.z, point.z - radius)
                localMaximum.x = max(localMaximum.x, point.x + radius)
                localMaximum.y = max(localMaximum.y, point.y + max(abs(stroke.strength), 0.22))
                localMaximum.z = max(localMaximum.z, point.z + radius)
            }
            let corners = [
                SCNVector3(localMinimum.x, localMinimum.y, localMinimum.z),
                SCNVector3(localMinimum.x, localMinimum.y, localMaximum.z),
                SCNVector3(localMinimum.x, localMaximum.y, localMinimum.z),
                SCNVector3(localMinimum.x, localMaximum.y, localMaximum.z),
                SCNVector3(localMaximum.x, localMinimum.y, localMinimum.z),
                SCNVector3(localMaximum.x, localMinimum.y, localMaximum.z),
                SCNVector3(localMaximum.x, localMaximum.y, localMinimum.z),
                SCNVector3(localMaximum.x, localMaximum.y, localMaximum.z),
            ].map { placementParent.convertPosition($0, to: nil) }
            guard let first = corners.first else { return nil }
            var minimum = first
            var maximum = first
            for corner in corners.dropFirst() {
                minimum.x = min(minimum.x, corner.x)
                minimum.y = min(minimum.y, corner.y)
                minimum.z = min(minimum.z, corner.z)
                maximum.x = max(maximum.x, corner.x)
                maximum.y = max(maximum.y, corner.y)
                maximum.z = max(maximum.z, corner.z)
            }
            return (minimum, maximum)
        }

        private func worldBounds(of node: SCNNode) -> (minimum: SCNVector3, maximum: SCNVector3)? {
            geometryBounds(of: node, in: nil)
        }

        /// 選択枠などの編集表示を除き、実モデルのジオメトリだけから寸法を求める。
        private func geometryBounds(
            of root: SCNNode,
            in coordinateSpace: SCNNode?
        ) -> (minimum: SCNVector3, maximum: SCNVector3)? {
            var result: (minimum: SCNVector3, maximum: SCNVector3)?

            func visit(_ node: SCNNode) {
                guard node.name != "asset-studio-selection" else { return }
                if node.geometry != nil {
                    let (minimum, maximum) = node.boundingBox
                    if minimum.x.isFinite, minimum.y.isFinite, minimum.z.isFinite,
                       maximum.x.isFinite, maximum.y.isFinite, maximum.z.isFinite {
                        let corners = [
                            SCNVector3(minimum.x, minimum.y, minimum.z),
                            SCNVector3(minimum.x, minimum.y, maximum.z),
                            SCNVector3(minimum.x, maximum.y, minimum.z),
                            SCNVector3(minimum.x, maximum.y, maximum.z),
                            SCNVector3(maximum.x, minimum.y, minimum.z),
                            SCNVector3(maximum.x, minimum.y, maximum.z),
                            SCNVector3(maximum.x, maximum.y, minimum.z),
                            SCNVector3(maximum.x, maximum.y, maximum.z),
                        ].map { node.convertPosition($0, to: coordinateSpace) }

                        for corner in corners {
                            if var bounds = result {
                                bounds.minimum.x = min(bounds.minimum.x, corner.x)
                                bounds.minimum.y = min(bounds.minimum.y, corner.y)
                                bounds.minimum.z = min(bounds.minimum.z, corner.z)
                                bounds.maximum.x = max(bounds.maximum.x, corner.x)
                                bounds.maximum.y = max(bounds.maximum.y, corner.y)
                                bounds.maximum.z = max(bounds.maximum.z, corner.z)
                                result = bounds
                            } else {
                                result = (corner, corner)
                            }
                        }
                    }
                }
                node.childNodes.forEach(visit)
            }

            visit(root)
            return result
        }

        private func processSurfaceSnapRequestIfNeeded() {
            guard let requestID = owner.store.surfaceSnapRequestID,
                  requestID != processedSurfaceSnapRequestID
            else { return }
            processedSurfaceSnapRequestID = requestID

            guard let selectedID = owner.store.selectedID,
                  let node = placementNodes[selectedID]
            else {
                owner.store.endInteractiveEdit()
                return
            }
            let position = node.position
            guard let restingY = restingOriginY(
                for: node,
                atX: position.x,
                z: position.z,
                excluding: selectedID
            ) else {
                owner.store.endInteractiveEdit()
                return
            }
            let isFinishingPlacement = owner.store.manipulationMode == .place
                && owner.store.placementBrushAssetID != nil
            owner.store.updatePlacement(id: selectedID, interactively: isFinishingPlacement) { placement in
                placement.transform.y = owner.store.surfaceSnapClampsOnly
                    ? max(placement.transform.y, restingY)
                    : restingY
            }
            if isFinishingPlacement {
                // 追加と接地補正を1つの履歴にまとめ、1回のUndoで戻す。
                owner.store.endInteractiveEdit()
            }
        }

        /// 島の地形と配置土台のうち、指定XZで最も高い支持面を返す。
        private func placementSurfaceY(atX x: Float, z: Float, excluding placementID: UUID) -> Float {
            let baseSurface: Float
            switch renderedContext ?? owner.store.context {
            case .destinationIsland:
                baseSurface = owner.store.activeStudioID == nil
                    ? VoyageSceneKit.islandSurfaceHeight(x: x, z: z)
                    : -0.055
            case .studio:
                baseSurface = 0
            }

            var highestSurface = baseSurface
            placementParent.enumerateChildNodes { node, _ in
                guard node.name?.hasPrefix("asset-studio-terrain") == true else { return }
                let localSample = node.convertPosition(SCNVector3(x, 0, z), from: self.placementParent)
                guard let localHeight = AssetPlacementRuntime.terrainSurfaceHeight(
                    on: node,
                    atLocalX: localSample.x,
                    z: localSample.z
                ) else { return }
                let parentSurface = node.convertPosition(
                    SCNVector3(localSample.x, localHeight, localSample.z),
                    to: self.placementParent
                )
                highestSurface = max(highestSurface, parentSurface.y)
            }
            if let contents = AssetPlacementPersistence.activeStudioContents(),
               let activeWorld = placementParent.childNode(
                   withName: "active-studio-world",
                   recursively: false
               ) {
                for placement in contents.placements
                where Asset3DCatalog.providesPlacementSurface(for: placement.assetID) {
                    guard let component = activeWorld.childNode(
                        withName: "saved-studio-component:\(placement.id.uuidString)",
                        recursively: false
                    ),
                    let supportY = supportSurfaceY(
                        on: component,
                        assetID: placement.assetID,
                        atParentX: x,
                        z: z
                    ) else { continue }
                    highestSurface = max(highestSurface, supportY)
                }
            }
            for placement in owner.store.visiblePlacements
            where placement.id != placementID
                && Asset3DCatalog.providesPlacementSurface(for: placement.assetID) {
                guard let supportNode = placementNodes[placement.id],
                      let supportY = supportSurfaceY(
                        on: supportNode,
                        assetID: placement.assetID,
                        atParentX: x,
                        z: z
                      )
                else { continue }
                highestSurface = max(highestSurface, supportY)
            }
            return highestSurface
        }

        /// 土台ローカル座標へ変換し、基本形状の上面を判定する。物理ワールドの更新前でも確定的に動作する。
        private func supportSurfaceY(
            on node: SCNNode,
            assetID: String,
            atParentX x: Float,
            z: Float
        ) -> Float? {
            if let studioID = SavedAssetStudio.id(fromAssetID: assetID),
               let contents = AssetPlacementPersistence.contents(forStudioID: studioID) {
                var highestSurface: Float?
                for placement in contents.placements
                where Asset3DCatalog.providesPlacementSurface(for: placement.assetID) {
                    guard let componentNode = node.childNode(
                        withName: "saved-studio-component:\(placement.id.uuidString)",
                        recursively: false
                    ),
                    let componentSurface = supportSurfaceY(
                        on: componentNode,
                        assetID: placement.assetID,
                        atParentX: x,
                        z: z
                    ) else { continue }
                    highestSurface = max(highestSurface ?? componentSurface, componentSurface)
                }
                return highestSurface
            }

            let parentSample = SCNVector3(x, node.position.y, z)
            let localSample = node.convertPosition(parentSample, from: placementParent)

            let localSurfaceY: Float
            if assetID == "island_base" {
                let radius = sqrt(
                    pow(localSample.x / 1.64, 2)
                        + pow(localSample.z / 1.13, 2)
                )
                guard radius <= 1.02 else { return nil }
                switch radius {
                case ...0.46:
                    localSurfaceY = 0.385 - radius / 0.46 * 0.020
                case ...0.87:
                    localSurfaceY = 0.365 - (radius - 0.46) / 0.41 * 0.060
                default:
                    localSurfaceY = 0.305 - (radius - 0.87) / 0.15 * 0.070
                }
            } else {
                guard let bounds = geometryBounds(of: node, in: node) else { return nil }
                let centerX = (bounds.minimum.x + bounds.maximum.x) * 0.5
                let centerZ = (bounds.minimum.z + bounds.maximum.z) * 0.5
                let radiusX = max((bounds.maximum.x - bounds.minimum.x) * 0.5, 0.001)
                let radiusZ = max((bounds.maximum.z - bounds.minimum.z) * 0.5, 0.001)
                let normalizedRadius = sqrt(
                    pow((localSample.x - centerX) / radiusX, 2)
                        + pow((localSample.z - centerZ) / radiusZ, 2)
                )
                guard normalizedRadius <= 1 else { return nil }
                localSurfaceY = bounds.maximum.y
            }

            let parentSurface = node.convertPosition(
                SCNVector3(localSample.x, localSurfaceY, localSample.z),
                to: placementParent
            )
            return parentSurface.y
        }

        /// モデルの回転・拡縮後の実際の底面を支持面へ合わせるための原点Yを求める。
        private func restingOriginY(
            for node: SCNNode,
            atX x: Float,
            z: Float,
            excluding placementID: UUID
        ) -> Float? {
            guard let bounds = geometryBounds(of: node, in: placementParent) else { return nil }

            let originY = node.convertPosition(SCNVector3Zero, to: placementParent).y
            let bottomOffset = bounds.minimum.y - originY
            let surfaceY = placementSurfaceY(atX: x, z: z, excluding: placementID)
            return surfaceY - bottomOffset + 0.002
        }

        private func processCameraRequestIfNeeded() {
            guard let request = owner.store.cameraRequest,
                  request.id != processedCameraRequestID
            else { return }
            processedCameraRequestID = request.id

            switch request.action {
            case .reset:
                resetCamera(animated: true)
            case .overview:
                showOverview(animated: true)
            case .homeShipMarker:
                showHomeShipMarker(animated: true)
            case .homeShipView:
                showHomeShipView(animated: true)
            case .focusSelection:
                focusSelection(animated: true)
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
            case .top:
                cameraElevation = cameraLimits.maximumElevation
                cameraAzimuth = nearestEquivalentAzimuth(to: 0)
                updateCamera(animated: 0.32)
            case .front:
                cameraElevation = 0.30
                cameraAzimuth = nearestEquivalentAzimuth(to: 0)
                updateCamera(animated: 0.32)
            case .side:
                cameraElevation = 0.30
                cameraAzimuth = nearestEquivalentAzimuth(to: .pi * 0.5)
                updateCamera(animated: 0.32)
            }
        }

        /// 現在の周回数に最も近い同一方位を返し、プリセット移動で逆方向へ一周するのを防ぐ。
        private func nearestEquivalentAzimuth(to target: Float) -> Float {
            let fullTurn = Float.pi * 2
            let turns = round((cameraAzimuth - target) / fullTurn)
            return target + turns * fullTurn
        }

        private func constrainCamera() {
            let limits = cameraLimits
            if !cameraAzimuth.isFinite { cameraAzimuth = 0.72 }
            cameraElevation = min(max(cameraElevation, limits.minimumElevation), limits.maximumElevation)
            cameraDistance = min(max(cameraDistance, limits.minimumDistance), limits.maximumDistance)
            cameraTarget.x = min(max(cameraTarget.x, limits.minimumTarget.x), limits.maximumTarget.x)
            cameraTarget.y = min(max(cameraTarget.y, limits.minimumTarget.y), limits.maximumTarget.y)
            cameraTarget.z = min(max(cameraTarget.z, limits.minimumTarget.z), limits.maximumTarget.z)
        }

        private func updateCamera(animated duration: TimeInterval = 0) {
            constrainCamera()
            cameraNode.camera?.zNear = Double(max(0.012, cameraDistance * 0.002))
            cameraNode.camera?.zFar = Double(max(1_500, cameraDistance * 8))
            if duration > 0 {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = duration
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            }
            cameraYawNode.position = cameraTarget
            cameraYawNode.eulerAngles = SCNVector3(0, cameraAzimuth, 0)
            cameraPitchNode.eulerAngles = SCNVector3(-cameraElevation, 0, 0)
            cameraNode.position = SCNVector3(0, 0, cameraDistance)
            cameraNode.eulerAngles = SCNVector3Zero
            if duration > 0 { SCNTransaction.commit() }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            let includesPinch = gestureRecognizer is UIPinchGestureRecognizer
                || otherGestureRecognizer is UIPinchGestureRecognizer
            guard includesPinch else { return false }
            // カメラはパンしながらズームできる。モデル編集では高さと拡縮を混ぜず、誤操作を防ぐ。
            return owner.store.manipulationMode == .camera
                || owner.store.manipulationMode == .select
                || owner.store.manipulationMode == .paint
                || owner.store.manipulationMode == .terrain
                || owner.store.manipulationMode == .place
                || owner.store.selectedPlacement == nil
        }
    }
}
