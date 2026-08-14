import Foundation

/// Validates and maps backend-neutral values at the existing model boundary.
///
/// This is deliberately not the EOS wire codec. EOS uses the explicit binary
/// protocol in `docs/EOS_MULTIPLAYER_ARCHITECTURE.md`; keeping JSON/Codable out
/// of this layer prevents an accidental, unbounded wire-format dependency.
enum PrivateIslandTransportCodec {
    static func presence(
        from state: HomeIslandRemotePlayerState,
        participantID: String,
        updatedAt: Date = Date()
    ) -> PrivateIslandTransportPresence {
        PrivateIslandTransportPresence(
            participantID: participantID,
            x: state.x,
            z: state.z,
            yaw: state.yaw,
            pose: state.pose,
            scene: state.scene,
            phase: state.phase,
            seatPlacementID: state.seatPlacementID,
            seatSlotID: state.seatSlotID,
            arrivalNonce: state.arrivalNonce,
            isVisible: state.isVisible,
            updatedAtMilliseconds: milliseconds(since1970: updatedAt)
        )
    }

    static func presence(
        from presence: PrivateIslandPresence
    ) -> PrivateIslandTransportPresence {
        PrivateIslandTransportPresence(
            participantID: presence.uid,
            x: presence.x,
            z: presence.z,
            yaw: presence.yaw,
            pose: presence.pose,
            scene: presence.scene,
            phase: presence.phase,
            seatPlacementID: presence.seatPlacementID?.uuidString.lowercased(),
            seatSlotID: presence.seatSlotID,
            arrivalNonce: presence.arrivalNonce,
            isVisible: presence.scene == "island" && presence.phase != "departure",
            updatedAtMilliseconds: milliseconds(since1970: presence.updatedAt)
        )
    }

    static func legacyPresence(
        from presence: PrivateIslandTransportPresence
    ) -> PrivateIslandPresence {
        PrivateIslandPresence(
            id: presence.participantID,
            uid: presence.participantID,
            x: presence.x,
            z: presence.z,
            yaw: presence.yaw,
            pose: presence.pose,
            scene: presence.scene,
            phase: presence.phase,
            seatPlacementID: presence.seatPlacementID.flatMap(UUID.init(uuidString:)),
            seatSlotID: presence.seatSlotID,
            arrivalNonce: presence.arrivalNonce,
            updatedAt: date(millisecondsSince1970: presence.updatedAtMilliseconds)
        )
    }

    static func chatMessage(
        from message: PrivateIslandChatMessage
    ) -> PrivateIslandTransportChatMessage {
        PrivateIslandTransportChatMessage(
            id: message.id,
            senderID: message.senderID,
            senderName: message.senderName,
            text: message.text,
            createdAtMilliseconds: milliseconds(since1970: message.createdAt)
        )
    }

    static func legacyChatMessage(
        from message: PrivateIslandTransportChatMessage
    ) -> PrivateIslandChatMessage {
        PrivateIslandChatMessage(
            id: message.id,
            senderID: message.senderID,
            senderName: message.senderName,
            text: message.text,
            createdAt: date(millisecondsSince1970: message.createdAtMilliseconds)
        )
    }

    static func delivery(
        for presence: PrivateIslandTransportPresence,
        after previous: PrivateIslandTransportPresence?
    ) -> PrivateIslandTransportDelivery {
        guard let previous else { return .reliable }
        let hasDiscreteTransition = presence.phase != previous.phase
            || presence.pose != previous.pose
            || presence.scene != previous.scene
            || presence.seatPlacementID != previous.seatPlacementID
            || presence.seatSlotID != previous.seatSlotID
            || presence.arrivalNonce != previous.arrivalNonce
            || presence.isVisible != previous.isVisible
        return hasDiscreteTransition ? .reliable : .bestEffort
    }

    static func seatAddress(
        from presence: PrivateIslandTransportPresence
    ) -> HomeIslandSeatAddress? {
        guard let placementString = presence.seatPlacementID,
              let placementID = UUID(uuidString: placementString),
              let slotID = presence.seatSlotID,
              !slotID.isEmpty
        else { return nil }
        return HomeIslandSeatAddress(placementID: placementID, slotID: slotID)
    }

    static func validate(_ presence: PrivateIslandTransportPresence) throws {
        guard isBounded(presence.participantID, maximumBytes: 128, allowingEmpty: false),
              presence.x.isFinite,
              presence.z.isFinite,
              presence.yaw.isFinite,
              abs(presence.x) <= 80,
              abs(presence.z) <= 80,
              isBounded(presence.pose, maximumBytes: 40, allowingEmpty: false),
              isBounded(presence.scene, maximumBytes: 40, allowingEmpty: false),
              isBounded(presence.phase, maximumBytes: 40, allowingEmpty: false),
              isBounded(presence.seatPlacementID, maximumBytes: 64),
              isBounded(presence.seatSlotID, maximumBytes: 40),
              isBounded(presence.arrivalNonce, maximumBytes: 64)
        else {
            throw PrivateIslandTransportError.invalidPayload
        }
    }

    static func validate(_ message: PrivateIslandTransportChatMessage) throws {
        guard isBounded(message.id, maximumBytes: 128, allowingEmpty: false),
              isBounded(message.senderID, maximumBytes: 128, allowingEmpty: false),
              isBounded(message.senderName, maximumBytes: 240, allowingEmpty: false),
              isBounded(message.text, maximumBytes: 2_000, allowingEmpty: false)
        else {
            throw PrivateIslandTransportError.invalidPayload
        }
    }

    private static func milliseconds(since1970 date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private static func date(millisecondsSince1970 value: Int64) -> Date {
        Date(timeIntervalSince1970: Double(value) / 1_000)
    }

    private static func isBounded(
        _ value: String?,
        maximumBytes: Int,
        allowingEmpty: Bool = true
    ) -> Bool {
        guard let value else { return true }
        return (allowingEmpty || !value.isEmpty) && value.utf8.count <= maximumBytes
    }
}
