import Foundation

/// Connection state exposed by a real-time private-island transport.
///
/// Room membership and the island snapshot remain Firebase-owned persistent
/// data. This state only describes the short-lived presence/chat channel.
enum PrivateIslandRealtimeConnectionState: String, Equatable, Sendable {
    case disconnected
    case connecting
    case connected
}

/// Delivery intent for transports that support both unreliable and reliable
/// packets. Firestore maps this to its existing throttled/forced write modes.
enum PrivateIslandTransportDelivery: Equatable, Sendable {
    case bestEffort
    case reliable
}

/// Backend-neutral navigator state suitable for Firestore today and an EOS
/// lobby/P2P transport later. Timestamps use Unix milliseconds so the wire
/// representation does not depend on Firebase's `Timestamp` type.
struct PrivateIslandTransportPresence: Identifiable, Equatable, Sendable {
    let participantID: String
    let x: Float
    let z: Float
    let yaw: Float
    let pose: String
    let scene: String
    let phase: String
    let seatPlacementID: String?
    let seatSlotID: String?
    let arrivalNonce: String?
    let isVisible: Bool
    let updatedAtMilliseconds: Int64

    var id: String { participantID }
}

/// Backend-neutral private-island chat line.
struct PrivateIslandTransportChatMessage: Identifiable, Equatable, Sendable {
    let id: String
    let senderID: String
    let senderName: String
    let text: String
    let createdAtMilliseconds: Int64
}

/// A complete value snapshot emitted by a real-time transport.
struct PrivateIslandRealtimeState: Equatable, Sendable {
    var connectionState: PrivateIslandRealtimeConnectionState
    var presences: [PrivateIslandTransportPresence]
    var messages: [PrivateIslandTransportChatMessage]
    var blockedParticipantIDs: Set<String>
    var errorDescription: String?

    static let disconnected = PrivateIslandRealtimeState(
        connectionState: .disconnected,
        presences: [],
        messages: [],
        blockedParticipantIDs: [],
        errorDescription: nil
    )
}

enum PrivateIslandTransportError: LocalizedError, Equatable {
    case invalidPayload
    case participantIdentityMismatch
    case moderationUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "The private-island real-time update was invalid."
        case .participantIdentityMismatch:
            return "The private-island participant identity did not match the signed-in sailor."
        case .moderationUnavailable:
            return "Private-island moderation is not available for this session."
        }
    }
}
