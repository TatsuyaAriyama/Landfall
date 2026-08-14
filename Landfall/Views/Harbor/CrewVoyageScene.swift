import SceneKit
import SwiftUI

/// プライベートルームの「並走する海」。
///
/// 歩ける港は持ち込まず、最大4隻の船と海だけを見せる。ルームのmemberIdsを
/// リアルタイム購読しているため、後から参加したuidには水平線側から入ってくる
/// 入港アニメーションを一度だけ与える。
struct CrewVoyageScene: View {
    let room: HarborRoom
    let members: [HarborMember]
    let selfUID: String?
    let underway: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var memberByID: [String: HarborMember] {
        Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
    }

    var body: some View {
        ZStack(alignment: .top) {
            CrewVoyageSceneRepresentable(
                memberIDs: Array(room.memberIds.prefix(HarborRoom.maxMembers)),
                members: memberByID,
                underway: underway,
                reduceMotion: reduceMotion
            )
            .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Fleet sea")
                        .font(LFFont.label(11))
                        .tracking(1.4)
                        .foregroundStyle(Color.white.opacity(0.64))
                    Text(verbatim: room.name)
                        .font(LFFont.copy(18))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                Text("\(min(room.memberIds.count, HarborRoom.maxMembers))/\(HarborRoom.maxMembers)")
                    .font(LFFont.label(13))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.72))
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            VStack {
                Spacer()
                HStack(spacing: 7) {
                    ForEach(Array(room.memberIds.prefix(HarborRoom.maxMembers)), id: \.self) { uid in
                        let member = memberByID[uid]
                        HStack(spacing: 6) {
                            PlayerAvatarArt(
                                styleToken: member?.styleToken ?? TileStyle.midnight.rawValue,
                                symbolToken: member?.symbolToken ?? TileSymbol.phoenix.rawValue
                            )
                            .frame(width: 22, height: 22)
                            Text(verbatim: member?.displayName ?? LF.text("Sailor"))
                                .font(LFFont.label(11))
                                .lineLimit(1)
                            if uid == selfUID {
                                Text("You")
                                    .font(LFFont.label(9))
                                    .foregroundStyle(Color.white.opacity(0.5))
                            }
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .frame(height: 34)
                        .background(Color.black.opacity(0.28))
                        .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .frame(height: 264)
        .background(Color(uiColor: VoyageSceneKit.nightBG))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text(
                verbatim: "\(room.name), \(room.memberIds.count)/\(HarborRoom.maxMembers) "
                    + LF.text("sailors sailing together")
            )
        )
    }
}

private struct CrewVoyageSceneRepresentable: UIViewRepresentable {
    let memberIDs: [String]
    let members: [String: HarborMember]
    let underway: Bool
    let reduceMotion: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = context.coordinator.scene
        view.backgroundColor = VoyageSceneKit.nightBG
        view.isPlaying = true
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 60
        view.antialiasingMode = .multisampling4X
        view.contentScaleFactor = UIScreen.main.scale
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        context.coordinator.sync(
            memberIDs: memberIDs,
            members: members,
            underway: underway,
            reduceMotion: reduceMotion
        )
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.sync(
            memberIDs: memberIDs,
            members: members,
            underway: underway,
            reduceMotion: reduceMotion
        )
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        view.isPlaying = false
        coordinator.stop()
        view.scene = nil
    }

    final class Coordinator {
        let scene = SCNScene()

        private var boats: [String: SCNNode] = [:]
        private var visualSignatures: [String: String] = [:]
        private var hasPresentedInitialFleet = false
        private var underway = false

        init() {
            buildWorld()
        }

        func stop() {
            for node in boats.values { node.removeAllActions() }
            boats.removeAll()
        }

        func sync(
            memberIDs: [String],
            members: [String: HarborMember],
            underway: Bool,
            reduceMotion: Bool
        ) {
            let capped = Array(memberIDs.prefix(HarborRoom.maxMembers))
            let wanted = Set(capped)

            let departingUIDs = boats.keys.filter { !wanted.contains($0) }
            for uid in departingUIDs {
                guard let node = boats.removeValue(forKey: uid) else { continue }
                visualSignatures.removeValue(forKey: uid)
                if reduceMotion {
                    node.removeFromParentNode()
                } else {
                    let leave = SCNAction.group([
                        SCNAction.moveBy(x: 0, y: 0, z: -7, duration: 1.1),
                        SCNAction.fadeOut(duration: 0.8),
                    ])
                    leave.timingMode = .easeIn
                    node.runAction(.sequence([leave, .removeFromParentNode()]))
                }
            }

            for (index, uid) in capped.enumerated() {
                let target = berthPosition(index: index, count: capped.count)
                let member = members[uid]
                let signature = visualSignature(member)
                if let existing = boats[uid] {
                    if visualSignatures[uid] != signature {
                        replaceBoatModel(in: existing, member: member)
                        visualSignatures[uid] = signature
                    }
                    let move = SCNAction.move(to: target, duration: reduceMotion ? 0 : 0.7)
                    move.timingMode = .easeInEaseOut
                    existing.runAction(move, forKey: "berth")
                } else {
                    let node = makeBoatNode(member: member, phase: Double(index) * 0.7)
                    node.name = "crewBoat_\(uid)"
                    boats[uid] = node
                    visualSignatures[uid] = signature
                    scene.rootNode.addChildNode(node)

                    let arriving = hasPresentedInitialFleet && !reduceMotion
                    node.position = arriving
                        ? SCNVector3(target.x, target.y - 0.08, target.z - 13)
                        : target
                    if arriving {
                        node.opacity = 0.08
                        let arrival = SCNAction.group([
                            SCNAction.move(to: target, duration: 1.8),
                            SCNAction.fadeIn(duration: 0.9),
                        ])
                        arrival.timingMode = .easeOut
                        node.runAction(arrival, forKey: "arrival")
                    }
                }
            }

            hasPresentedInitialFleet = true
            if self.underway != underway {
                self.underway = underway
                updateUnderwayMotion(underway: underway, reduceMotion: reduceMotion)
            }
        }

        private func buildWorld() {
            scene.background.contents = VoyageSceneKit.nightBG
            scene.rootNode.addChildNode(VoyageSceneKit.makeSea(moonX: -7.5))
            scene.rootNode.addChildNode(VoyageSceneKit.makeStars(count: 520))
            VoyageSceneKit.makeLights().forEach(scene.rootNode.addChildNode)

            let island = VoyageSceneKit.makeIsland()
            island.name = "fleetIsland"
            island.position = SCNVector3(0, 0, -15.5)
            island.scale = SCNVector3(1.35, 1.35, 1.35)
            scene.rootNode.addChildNode(island)

            let moon = LandfallMoonEffects.makeNode(
                phase: .current(),
                radius: 0.62
            )
            moon.position = SCNVector3(-7.8, 7.1, -23)
            scene.rootNode.addChildNode(moon)

            let camera = SCNCamera()
            camera.fieldOfView = 48
            camera.wantsHDR = true
            camera.bloomIntensity = 0.26
            camera.bloomThreshold = 0.82
            camera.zNear = 0.1
            camera.zFar = 120
            let cameraNode = SCNNode()
            cameraNode.name = "fleetCamera"
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(0, 5.6, 11.2)
            cameraNode.look(at: SCNVector3(0, 0.85, -2.4))
            scene.rootNode.addChildNode(cameraNode)
        }

        private func makeBoatNode(member: HarborMember?, phase: Double) -> SCNNode {
            let berth = SCNNode()
            replaceBoatModel(in: berth, member: member)

            let bob = SCNAction.sequence([
                SCNAction.moveBy(x: 0, y: 0.07, z: 0, duration: 1.3 + phase * 0.08),
                SCNAction.moveBy(x: 0, y: -0.07, z: 0, duration: 1.3 + phase * 0.08),
            ])
            bob.timingMode = .easeInEaseOut
            berth.runAction(.repeatForever(bob), forKey: "bob")
            return berth
        }

        private func replaceBoatModel(in berth: SCNNode, member: HarborMember?) {
            berth.childNode(withName: "boatVisual", recursively: false)?.removeFromParentNode()
            let ids: [String: String?] = [
                "boatSail": member?.boatSail,
                "boatJib": member?.boatJib,
                "boatHull": member?.boatHull,
                "boatStripe": member?.boatStripe,
                "boatFlag": member?.boatFlag,
            ]
            let model = VoyageSceneKit.makeBoatModel(BoatCustomization.parts(fromIDs: ids))
            model.name = "boatVisual"
            model.scale = SCNVector3(0.68, 0.68, 0.68)
            model.eulerAngles.y = -.pi / 2
            berth.addChildNode(model)
        }

        private func updateUnderwayMotion(underway: Bool, reduceMotion: Bool) {
            for (index, node) in boats.values.enumerated() {
                node.removeAction(forKey: "surge")
                guard underway, !reduceMotion else { continue }
                let delay = SCNAction.wait(duration: Double(index) * 0.08)
                let forward = SCNAction.moveBy(x: 0, y: 0, z: -0.22, duration: 1.2)
                let settle = SCNAction.moveBy(x: 0, y: 0, z: 0.22, duration: 1.2)
                forward.timingMode = .easeInEaseOut
                settle.timingMode = .easeInEaseOut
                node.runAction(.repeatForever(.sequence([delay, forward, settle])), forKey: "surge")
            }
        }

        private func berthPosition(index: Int, count: Int) -> SCNVector3 {
            let spacing: Float = 2.25
            let x = (Float(index) - Float(count - 1) / 2) * spacing
            let z = Float(index % 2) * 0.45 - 0.15
            return SCNVector3(x, 0.03, z)
        }

        private func visualSignature(_ member: HarborMember?) -> String {
            [
                member?.boatSail,
                member?.boatJib,
                member?.boatHull,
                member?.boatStripe,
                member?.boatFlag,
            ]
            .map { $0 ?? "" }
            .joined(separator: "|")
        }
    }
}
