import GameController
import QuartzCore
import UIKit

/// Bridges physical controllers into the same analog input used by the
/// phone's invisible thumbstick. It owns no gameplay state and clears every
/// value on disconnect/backgrounding.
final class HomeIslandGamepadInputRouter {
    var movementHandler: ((HomeIslandWalkInput, TimeInterval) -> Void)?
    var lookHandler: ((_ x: Float, _ y: Float, _ deltaTime: TimeInterval) -> Void)?

    private weak var controller: GCController?
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: .GCControllerDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let controller = notification.object as? GCController else { return }
                self?.activate(controller)
            },
            center.addObserver(
                forName: .GCControllerDidDisconnect,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let disconnected = notification.object as? GCController,
                      self?.controller === disconnected
                else { return }
                self?.activate(GCController.controllers().first { $0 !== disconnected })
            },
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.emitNeutralInput()
            },
        ]
        activate(GCController.controllers().first)
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
    }

    func stop() {
        GCController.stopWirelessControllerDiscovery()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        controller = nil
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        emitNeutralInput()
    }

    private func activate(_ nextController: GCController?) {
        controller = nextController
        nextController?.handlerQueue = .main
        guard nextController != nil else {
            displayLink?.invalidate()
            displayLink = nil
            lastTimestamp = nil
            emitNeutralInput()
            return
        }
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(update(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func update(_ link: CADisplayLink) {
        let previous = lastTimestamp ?? link.timestamp
        let deltaTime = min(max(link.timestamp - previous, 0), 0.05)
        lastTimestamp = link.timestamp
        guard let gamepad = controller?.extendedGamepad else {
            emitNeutralInput()
            return
        }
        let movement = HomeIslandGamepadMapping.movement(
            stickX: gamepad.leftThumbstick.xAxis.value,
            stickY: gamepad.leftThumbstick.yAxis.value,
            dpadX: gamepad.dpad.xAxis.value,
            dpadY: gamepad.dpad.yAxis.value,
            sprint: gamepad.rightTrigger.value > 0.35
                || gamepad.leftThumbstickButton?.isPressed == true,
            jump: gamepad.buttonA.isPressed
        )
        movementHandler?(movement, deltaTime)

        let lookX = gamepad.rightThumbstick.xAxis.value
        let lookY = gamepad.rightThumbstick.yAxis.value
        if abs(lookX) > 0.10 || abs(lookY) > 0.10 {
            lookHandler?(lookX, lookY, deltaTime)
        }
    }

    private func emitNeutralInput() {
        movementHandler?(.zero, 0)
    }

    deinit {
        stop()
    }
}
