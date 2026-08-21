import SceneKit
import UIKit

/// ウィジェットはSceneKitを連続描画しない。代わりに本体と同じ3Dシーンを
/// オフスクリーンで一枚だけ描き、App Groupへ渡す。
@MainActor
enum WidgetVoyageStillRenderer {
    private static let renderKey = "widget.voyageStill.renderKey.v1"

    static func refreshIfNeeded(force: Bool = false) {
        guard let outputURL = KeelMiraWidgetStore.voyageImageURL else { return }
        let phaseBucket = Int(LandfallLunarPhase.current().cycle * 64)
        let appearanceKey = BoatCustomization.appearanceKey
            + ":" + PhoenixPose.selected.rawValue
            + ":moon-\(phaseBucket)"
        let previousKey = KeelMiraWidgetStore.defaults.string(forKey: renderKey)
        guard force || previousKey != appearanceKey || !FileManager.default.fileExists(atPath: outputURL.path) else {
            return
        }

        let scene = VoyageSceneKit.makeVoyagingScene(showIsland: true, timeOfDay: .night)
        let navigator = PhoenixAnimator()
        navigator.pose = PhoenixPose.selected
        navigator.animate = false
        navigator.bindIfNeeded(scene)
        navigator.step(t: 3.5, dt: 1)

        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
        renderer.autoenablesDefaultLighting = false
        let image = renderer.snapshot(
            atTime: 3.5,
            with: CGSize(width: 900, height: 520),
            antialiasingMode: .multisampling4X
        )
        guard let data = image.jpegData(compressionQuality: 0.88) else { return }
        do {
            try data.write(to: outputURL, options: .atomic)
            KeelMiraWidgetStore.defaults.set(appearanceKey, forKey: renderKey)
        } catch {
            // 背景生成に失敗してもウィジェットはコード描画の海で成立する。
        }
    }
}
