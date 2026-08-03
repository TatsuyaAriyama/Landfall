import SceneKit
import SwiftUI
import UIKit

/// The consumer home-island canvas.  It intentionally exposes only placement,
/// selection and camera gestures; none of 3D Studio's terrain or transform tools
/// are reachable from this scene.
struct HomeIslandSceneView: UIViewRepresentable {
    @ObservedObject var store: HomeIslandStore
    var placementAssetID: String?
    var movingSelection: Bool
    var playerLevel: Int
    var cameraResetToken: Int
    var onMoveCompleted: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(owner: self)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = UIColor(rgb: 0x173F39)
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = !UIAccessibility.isReduceMotionEnabled
        view.isPlaying = !UIAccessibility.isReduceMotionEnabled
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
        private weak var camera: SCNNode?
        private weak var cameraTarget: SCNNode?
        private weak var seaMaterial: SCNMaterial?
        private var selectedOutline: SCNNode?
        private var azimuth: Float = 0.72
        private var elevation: Float = 0.42
        private var radius: Float = 30.8
        private var initialAzimuth: Float = 0
        private var initialElevation: Float = 0
        private var initialRadius: Float = 0
        private var initialCameraTarget = SCNVector3Zero
        private var pinchAnchorWorldPoint: SCNVector3?
        private var renderedResetToken = 0
        private var startTime: TimeInterval?

        init(owner: HomeIslandSceneView) {
            self.owner = owner
        }

        func install(in view: SCNView) {
            self.view = view
            let scene = makeScene()
            view.scene = scene
            view.pointOfView = camera

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.delegate = self
            view.addGestureRecognizer(tap)

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 1
            pan.allowedScrollTypesMask = [.continuous, .discrete]
            pan.delegate = self
            view.addGestureRecognizer(pan)

            let twoFingerPan = UIPanGestureRecognizer(
                target: self,
                action: #selector(handleTwoFingerPan(_:))
            )
            twoFingerPan.minimumNumberOfTouches = 2
            twoFingerPan.maximumNumberOfTouches = 2
            twoFingerPan.delegate = self
            view.addGestureRecognizer(twoFingerPan)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            view.addGestureRecognizer(pinch)

            let longPress = UILongPressGestureRecognizer(
                target: self,
                action: #selector(handleLongPress(_:))
            )
            longPress.minimumPressDuration = 0.42
            longPress.allowableMovement = 12
            longPress.delegate = self
            view.addGestureRecognizer(longPress)

            let reset = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            reset.numberOfTapsRequired = 2
            tap.require(toFail: reset)
            view.addGestureRecognizer(reset)

            syncPlacements()
            updateCamera()
        }

        func update(owner: HomeIslandSceneView) {
            self.owner = owner
            syncPlacements()
            if renderedResetToken != owner.cameraResetToken {
                renderedResetToken = owner.cameraResetToken
                resetCamera(animated: true)
            }
        }

        private func makeScene() -> SCNScene {
            let scene = SCNScene()
            scene.background.contents = UIColor(rgb: 0x173F39)
            scene.fogColor = UIColor(rgb: 0x315F55)
            scene.fogStartDistance = 46
            scene.fogEndDistance = 105

            let seaGeometry = SCNPlane(width: 180, height: 180)
            seaGeometry.widthSegmentCount = 80
            seaGeometry.heightSegmentCount = 80
            let sea = SCNMaterial()
            sea.name = "home-island-sea-material"
            sea.lightingModel = .physicallyBased
            sea.diffuse.contents = UIColor(rgb: 0x2A7165)
            sea.roughness.contents = 0.52
            sea.metalness.contents = 0.03
            sea.isDoubleSided = true
            sea.setValue(NSNumber(value: Float(0)), forKey: "uTime")
            sea.shaderModifiers = [
                .geometry: """
                #pragma arguments
                float uTime;
                #pragma body
                float2 p = _geometry.position.xy;
                float wave = sin(p.x * 0.42 + uTime * 0.48) * 0.045;
                wave += sin(p.y * 0.55 - uTime * 0.36) * 0.028;
                wave += sin((p.x + p.y) * 0.18 + uTime * 0.21) * 0.020;
                _geometry.position.z += wave;
                """,
                .surface: """
                #pragma arguments
                float uTime;
                #pragma body
                float glint = 0.5 + 0.5 * sin((_surface.position.x - _surface.position.z) * 0.31 + uTime * 0.32);
                _surface.emission.rgb += float3(0.035, 0.070, 0.058) * glint;
                """,
            ]
            seaGeometry.firstMaterial = sea
            let seaNode = SCNNode(geometry: seaGeometry)
            seaNode.name = "home-island-sea"
            seaNode.eulerAngles.x = -.pi / 2
            seaNode.position.y = -0.55
            scene.rootNode.addChildNode(seaNode)
            seaMaterial = sea

            if let foundation = AssetPlacementRuntime.makeAssetNode(
                resourceName: HomeIslandMetrics.foundationResourceName
            ) {
                foundation.name = "home-island-locked-foundation"
                scene.rootNode.addChildNode(foundation)
            }

            let foamGeometry = SCNTorus(ringRadius: 12.44, pipeRadius: 0.095)
            foamGeometry.ringSegmentCount = 128
            foamGeometry.pipeSegmentCount = 7
            let foam = SCNMaterial()
            foam.lightingModel = .constant
            foam.diffuse.contents = UIColor(rgb: 0xDCE8CF).withAlphaComponent(0.58)
            foam.blendMode = .alpha
            foam.writesToDepthBuffer = false
            foamGeometry.firstMaterial = foam
            let foamNode = SCNNode(geometry: foamGeometry)
            foamNode.name = "home-island-foam"
            foamNode.scale.z = 0.70
            foamNode.position = SCNVector3(0, -0.50, 0)
            scene.rootNode.addChildNode(foamNode)

            placementParent.name = "home-island-player-placements"
            scene.rootNode.addChildNode(placementParent)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.color = UIColor(rgb: 0x9CC0AD)
            ambient.light?.intensity = 720
            scene.rootNode.addChildNode(ambient)

            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .directional
            key.light?.color = UIColor(rgb: 0xFFE8BE)
            key.light?.intensity = 1_350
            key.light?.castsShadow = true
            key.light?.shadowMode = .deferred
            key.light?.shadowRadius = 4
            key.light?.shadowColor = UIColor.black.withAlphaComponent(0.34)
            key.light?.shadowMapSize = CGSize(width: 2_048, height: 2_048)
            key.position = SCNVector3(-7, 12, 8)
            key.look(at: SCNVector3Zero)
            scene.rootNode.addChildNode(key)

            let fill = SCNNode()
            fill.light = SCNLight()
            fill.light?.type = .directional
            fill.light?.color = UIColor(rgb: 0x7DC0AA)
            fill.light?.intensity = 430
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
            cameraComponent.wantsHDR = true
            cameraComponent.exposureOffset = -0.04
            cameraComponent.contrast = 0.08
            cameraNode.camera = cameraComponent
            scene.rootNode.addChildNode(cameraNode)
            camera = cameraNode

            return scene
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
                    placementParent.addChildNode(loaded)
                    placementNodes[placement.id] = loaded
                    node = loaded
                }
                placement.transform.apply(to: node)
            }
            updateSelectionOutline()
            view?.setNeedsDisplay()
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
                  let view
            else { return }
            let screenPoint = recognizer.location(in: view)

            if let assetID = owner.placementAssetID,
               let point = groundPoint(at: screenPoint),
               HomeIslandMetrics.contains(x: point.x, z: point.z) {
                _ = owner.store.add(
                    assetID: assetID,
                    x: point.x,
                    z: point.z,
                    playerLevel: owner.playerLevel
                )
                Haptics.tap(.light)
                return
            }

            if owner.movingSelection,
               let point = groundPoint(at: screenPoint),
               HomeIslandMetrics.contains(x: point.x, z: point.z) {
                owner.store.moveSelected(x: point.x, z: point.z)
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

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view else { return }
            view.becomeFirstResponder()
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
                azimuth = initialAzimuth - Float(translation.x) * 0.0064
                elevation = initialElevation + Float(translation.y) * 0.0052
                updateCamera()
            case .ended:
                let velocity = recognizer.velocity(in: view)
                azimuth -= Float(velocity.x) * 0.00010
                elevation += Float(velocity.y) * 0.000075
                updateCamera(animated: 0.18)
            default:
                break
            }
        }

        @objc private func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
            guard let view, let target = cameraTarget else { return }
            let translation = recognizer.translation(in: view)
            switch recognizer.state {
            case .began:
                initialCameraTarget = target.position
            case .changed:
                let sensitivity = max(radius, 2) * 0.00125
                let horizontal = Float(translation.x) * sensitivity
                let vertical = Float(translation.y) * sensitivity
                let right = SCNVector3(cos(azimuth), 0, -sin(azimuth))
                let up = SCNVector3(
                    -sin(azimuth) * sin(elevation),
                    cos(elevation),
                    -cos(azimuth) * sin(elevation)
                )
                target.position = SCNVector3(
                    initialCameraTarget.x - right.x * horizontal + up.x * vertical,
                    initialCameraTarget.y - right.y * horizontal + up.y * vertical,
                    initialCameraTarget.z - right.z * horizontal + up.z * vertical
                )
                updateCamera()
            default:
                break
            }
        }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let view, let target = cameraTarget else { return }
            switch recognizer.state {
            case .began:
                initialRadius = radius
                initialCameraTarget = target.position
                pinchAnchorWorldPoint = groundPoint(at: recognizer.location(in: view))
            case .changed:
                radius = initialRadius / pow(Float(recognizer.scale), 0.86)
                if let anchor = pinchAnchorWorldPoint {
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
            guard recognizer.state == .began,
                  let view,
                  let point = groundPoint(at: recognizer.location(in: view)),
                  let target = cameraTarget
            else { return }
            target.position = point
            updateCamera(animated: 0.24)
            Haptics.tap(.medium)
        }

        private func handlePointerScroll(_ recognizer: UIPanGestureRecognizer) {
            guard let view else { return }
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
            guard recognizer.state == .ended else { return }
            resetCamera(animated: true)
        }

        private func resetCamera(animated: Bool) {
            azimuth = nearestEquivalentAzimuth(to: 0.72)
            elevation = 0.42
            radius = 30.8
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
            view?.setNeedsDisplay()
        }

        private func constrainCamera() {
            if !azimuth.isFinite { azimuth = 0.72 }
            elevation = min(max(elevation, 0.08), 1.28)
            radius = min(max(radius, 1.4), 420)
            guard let target = cameraTarget else { return }
            target.position.x = min(max(target.position.x, -64), 64)
            target.position.y = min(max(target.position.y, -12), 96)
            target.position.z = min(max(target.position.z, -64), 64)
        }

        private func nearestEquivalentAzimuth(to target: Float) -> Float {
            let fullTurn = Float.pi * 2
            let turns = round((azimuth - target) / fullTurn)
            return target + turns * fullTurn
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            if startTime == nil { startTime = time }
            let elapsed = Float(time - (startTime ?? time))
            seaMaterial?.setValue(NSNumber(value: elapsed), forKey: "uTime")
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
