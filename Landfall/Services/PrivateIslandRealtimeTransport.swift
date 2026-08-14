import Combine
import Foundation

/// Replaceable boundary for latency-sensitive private-island traffic.
/// Persistent room/snapshot/profile operations intentionally stay on
/// `PrivateIslandService` and are not part of this protocol.
@MainActor
protocol PrivateIslandRealtimeTransport: AnyObject {
    var currentState: PrivateIslandRealtimeState { get }
    var statePublisher: AnyPublisher<PrivateIslandRealtimeState, Never> { get }
    /// True only for the compatibility transport. EOS keeps durable room and
    /// snapshot listeners, but must not start Firestore presence reads.
    var requiresFirestorePresenceListener: Bool { get }

    func start()
    func stop() async
    func publishPresence(
        _ presence: PrivateIslandTransportPresence,
        delivery: PrivateIslandTransportDelivery
    ) async throws
    func sendChat(_ text: String) async throws
}

/// Moderation remains a durable Firebase concern even after movement/chat
/// traffic moves to EOS, so it is composed separately from the transport.
@MainActor
protocol PrivateIslandRealtimeModerating: AnyObject {
    func report(_ message: PrivateIslandTransportChatMessage) async throws
    func setBlocked(_ participantID: String, blocked: Bool) async throws
}

/// Type-erased observable facade used by SwiftUI. A future EOS implementation
/// only needs to supply the two protocols above; no SceneKit view changes are
/// required.
@MainActor
final class PrivateIslandRealtimeClient: ObservableObject {
    @Published private(set) var state: PrivateIslandRealtimeState

    private let transport: PrivateIslandRealtimeTransport
    private let moderation: PrivateIslandRealtimeModerating?
    private var subscription: AnyCancellable?

    init(
        transport: PrivateIslandRealtimeTransport,
        moderation: PrivateIslandRealtimeModerating? = nil
    ) {
        self.transport = transport
        self.moderation = moderation
        state = transport.currentState
        subscription = transport.statePublisher
            .sink { [weak self] state in
                self?.state = state
            }
    }

    func start() {
        transport.start()
    }

    var requiresFirestorePresenceListener: Bool {
        transport.requiresFirestorePresenceListener
    }

    func stop() async {
        await transport.stop()
    }

    func publishPresence(
        _ presence: PrivateIslandTransportPresence,
        delivery: PrivateIslandTransportDelivery
    ) async throws {
        try await transport.publishPresence(presence, delivery: delivery)
    }

    func sendChat(_ text: String) async throws {
        try await transport.sendChat(text)
    }

    func report(_ message: PrivateIslandTransportChatMessage) async throws {
        guard let moderation else {
            throw PrivateIslandTransportError.moderationUnavailable
        }
        try await moderation.report(message)
    }

    func setBlocked(_ participantID: String, blocked: Bool) async throws {
        guard let moderation else {
            throw PrivateIslandTransportError.moderationUnavailable
        }
        try await moderation.setBlocked(participantID, blocked: blocked)
    }

    static func firestore(
        room: PrivateIslandRoom,
        persistence: PrivateIslandService
    ) -> PrivateIslandRealtimeClient {
        let adapter = FirestorePrivateIslandRealtimeTransport(
            room: room,
            persistence: persistence
        )
        return PrivateIslandRealtimeClient(
            transport: adapter,
            moderation: adapter
        )
    }

    /// Single production selection point. The EOS adapter will be enabled
    /// here after Portal credentials and device-only SDK validation are ready;
    /// callers retain the Firestore compatibility path automatically.
    static func live(
        room: PrivateIslandRoom,
        persistence: PrivateIslandService
    ) -> PrivateIslandRealtimeClient {
        firestore(room: room, persistence: persistence)
    }
}

/// Injection point shared by the hosted and visiting worlds.
typealias PrivateIslandRealtimeClientFactory = @MainActor (
    _ room: PrivateIslandRoom,
    _ persistence: PrivateIslandService
) -> PrivateIslandRealtimeClient

/// Compatibility adapter that preserves today's Firestore behavior until an
/// EOS SDK-backed transport is linked. It observes the same persistence service
/// instance used by the screen, avoiding duplicate room/snapshot listeners.
@MainActor
final class FirestorePrivateIslandRealtimeTransport:
    PrivateIslandRealtimeTransport,
    PrivateIslandRealtimeModerating
{
    private let room: PrivateIslandRoom
    private let persistence: PrivateIslandService
    private let chat: PrivateIslandChatService
    private let subject = CurrentValueSubject<PrivateIslandRealtimeState, Never>(.disconnected)

    private var isStarted = false
    private var liveRoom: PrivateIslandRoom?
    private var livePresences: [PrivateIslandPresence] = []
    private var liveMessages: [PrivateIslandChatMessage] = []
    private var blockedParticipantIDs: Set<String> = []
    private var persistenceError: String?
    private var chatError: String?
    private var subscriptions: Set<AnyCancellable> = []

    var currentState: PrivateIslandRealtimeState { subject.value }

    let requiresFirestorePresenceListener = true

    var statePublisher: AnyPublisher<PrivateIslandRealtimeState, Never> {
        subject.eraseToAnyPublisher()
    }

    init(
        room: PrivateIslandRoom,
        persistence: PrivateIslandService,
        chat: PrivateIslandChatService? = nil
    ) {
        self.room = room
        self.persistence = persistence
        self.chat = chat ?? PrivateIslandChatService(islandCode: room.code)
        bindSources()
    }

    func start() {
        isStarted = true
        emitState()
        chat.start()
    }

    func stop() async {
        isStarted = false
        await persistence.removePresence(from: room.code)
        chat.stop()
        emitState()
    }

    func publishPresence(
        _ presence: PrivateIslandTransportPresence,
        delivery: PrivateIslandTransportDelivery
    ) async throws {
        try PrivateIslandTransportCodec.validate(presence)
        guard persistence.currentUserID == presence.participantID else {
            throw PrivateIslandTransportError.participantIdentityMismatch
        }
        try await persistence.publishPresence(
            code: room.code,
            x: presence.x,
            z: presence.z,
            yaw: presence.yaw,
            pose: presence.pose,
            scene: presence.scene,
            phase: presence.phase,
            seat: PrivateIslandTransportCodec.seatAddress(from: presence),
            arrivalNonce: presence.arrivalNonce,
            force: delivery == .reliable
        )
    }

    func sendChat(_ text: String) async throws {
        try await chat.send(text)
    }

    func report(_ message: PrivateIslandTransportChatMessage) async throws {
        try PrivateIslandTransportCodec.validate(message)
        let legacyMessage = PrivateIslandTransportCodec.legacyChatMessage(from: message)
        try await chat.report(legacyMessage, targetUserID: message.senderID)
    }

    func setBlocked(_ participantID: String, blocked: Bool) async throws {
        if blocked {
            try await chat.block(participantID)
        } else {
            try await chat.unblock(participantID)
        }
    }

    private func bindSources() {
        persistence.$currentIsland
            .sink { [weak self] room in
                self?.liveRoom = room
                self?.emitState()
            }
            .store(in: &subscriptions)
        persistence.$presences
            .sink { [weak self] presences in
                self?.livePresences = presences
                self?.emitState()
            }
            .store(in: &subscriptions)
        persistence.$errorMessage
            .sink { [weak self] error in
                self?.persistenceError = error
                self?.emitState()
            }
            .store(in: &subscriptions)
        chat.$messages
            .sink { [weak self] messages in
                self?.liveMessages = messages
                self?.emitState()
            }
            .store(in: &subscriptions)
        chat.$blockedUserIDs
            .sink { [weak self] participantIDs in
                self?.blockedParticipantIDs = participantIDs
                self?.emitState()
            }
            .store(in: &subscriptions)
        chat.$errorMessage
            .sink { [weak self] error in
                self?.chatError = error
                self?.emitState()
            }
            .store(in: &subscriptions)
    }

    private func emitState() {
        let connectionState: PrivateIslandRealtimeConnectionState
        if !isStarted {
            connectionState = .disconnected
        } else if liveRoom?.code == room.code {
            connectionState = .connected
        } else {
            connectionState = .connecting
        }

        subject.send(
            PrivateIslandRealtimeState(
                connectionState: connectionState,
                presences: livePresences.map(PrivateIslandTransportCodec.presence(from:)),
                messages: liveMessages.map(PrivateIslandTransportCodec.chatMessage(from:)),
                blockedParticipantIDs: blockedParticipantIDs,
                errorDescription: persistenceError ?? chatError
            )
        )
    }
}
