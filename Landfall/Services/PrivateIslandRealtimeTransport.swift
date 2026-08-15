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

    /// Single production selection point. EOS is attempted only on a real
    /// device with complete Portal and member-only session configuration. Any
    /// construction or runtime connection failure falls back to Firestore.
    static func live(
        room: PrivateIslandRoom,
        persistence: PrivateIslandService
    ) -> PrivateIslandRealtimeClient {
        let firestore = FirestorePrivateIslandRealtimeTransport(
            room: room,
            persistence: persistence
        )
#if EOS_SDK_AVAILABLE && !targetEnvironment(simulator)
        if let session = room.eosSessionConfiguration,
           let portal = try? EOSPrivateIslandConfiguration.load(),
           let runtime = try? EOSSDKRuntime.shared(configuration: portal),
           let eos = try? EOSPrivateIslandRealtimeTransportAdapter(
               room: room,
               session: session,
               runtime: runtime,
               persistence: persistence
           ) {
            let hybrid = EOSPresenceFirestoreFallbackTransport(
                eosPresence: eos,
                firestore: firestore,
                activateFallbackReads: {
                    persistence.enableFirestorePresenceFallback(for: room.code)
                }
            )
            return PrivateIslandRealtimeClient(
                transport: hybrid,
                moderation: firestore
            )
        }
#endif
        return PrivateIslandRealtimeClient(
            transport: firestore,
            moderation: firestore
        )
    }
}

/// Injection point shared by the hosted and visiting worlds.
typealias PrivateIslandRealtimeClientFactory = @MainActor (
    _ room: PrivateIslandRoom,
    _ persistence: PrivateIslandService
) -> PrivateIslandRealtimeClient

/// Keeps Firestore chat/moderation active while EOS owns presence. EOS failure
/// switches presence once, irreversibly, to the already-running compatibility
/// transport and enables the listener that callers initially skipped.
@MainActor
private final class EOSPresenceFirestoreFallbackTransport:
    PrivateIslandRealtimeTransport
{
    private let eosPresence: PrivateIslandRealtimeTransport
    private let firestore: PrivateIslandRealtimeTransport
    private let activateFallbackReads: () -> Void
    private let subject: CurrentValueSubject<PrivateIslandRealtimeState, Never>
    private var eosState: PrivateIslandRealtimeState
    private var firestoreState: PrivateIslandRealtimeState
    private var eosSubscription: AnyCancellable?
    private var firestoreSubscription: AnyCancellable?
    private var transitionTask: Task<Void, Never>?
    private var startupWatchdog: Task<Void, Never>?
    private var pendingPresenceFlush: Task<Void, Never>?
    private var pendingPresence: (
        value: PrivateIslandTransportPresence,
        delivery: PrivateIslandTransportDelivery
    )?
    private var isStarted = false
    private var isUsingFallback = false

    var currentState: PrivateIslandRealtimeState { subject.value }
    var statePublisher: AnyPublisher<PrivateIslandRealtimeState, Never> {
        subject.eraseToAnyPublisher()
    }
    var requiresFirestorePresenceListener: Bool { isUsingFallback }

    init(
        eosPresence: PrivateIslandRealtimeTransport,
        firestore: PrivateIslandRealtimeTransport,
        activateFallbackReads: @escaping () -> Void
    ) {
        self.eosPresence = eosPresence
        self.firestore = firestore
        self.activateFallbackReads = activateFallbackReads
        eosState = eosPresence.currentState
        firestoreState = firestore.currentState
        subject = CurrentValueSubject(.disconnected)

        eosSubscription = eosPresence.statePublisher.sink { [weak self] state in
            guard let self else { return }
            self.eosState = state
            if self.isStarted,
               !self.isUsingFallback,
               state.connectionState == .disconnected,
               state.errorDescription != nil {
                self.beginFallbackTransition()
            } else {
                self.emitCombinedState()
            }
        }
        firestoreSubscription = firestore.statePublisher.sink { [weak self] state in
            self?.firestoreState = state
            self?.emitCombinedState()
        }
        emitCombinedState()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        // Firestore stays active for canonical chat, names, reports and blocks.
        firestore.start()
        if isUsingFallback {
            emitCombinedState()
        } else {
            eosPresence.start()
            startupWatchdog?.cancel()
            startupWatchdog = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled,
                      let self,
                      self.isStarted,
                      !self.isUsingFallback,
                      self.eosState.connectionState != .connected
                else { return }
                self.beginFallbackTransition()
            }
        }
    }

    func stop() async {
        isStarted = false
        transitionTask?.cancel()
        startupWatchdog?.cancel()
        let pendingFlush = pendingPresenceFlush
        pendingFlush?.cancel()
        startupWatchdog = nil
        let pendingTransition = transitionTask
        await pendingTransition?.value
        await pendingFlush?.value
        transitionTask = nil
        pendingPresenceFlush = nil
        pendingPresence = nil
        await eosPresence.stop()
        await firestore.stop()
    }

    func publishPresence(
        _ presence: PrivateIslandTransportPresence,
        delivery: PrivateIslandTransportDelivery
    ) async throws {
        if isUsingFallback {
            try await firestore.publishPresence(presence, delivery: delivery)
            return
        }
        if eosState.connectionState == .connecting {
            pendingPresence = (presence, delivery)
            return
        }
        do {
            try await eosPresence.publishPresence(presence, delivery: delivery)
        } catch {
            if eosState.connectionState == .connecting {
                pendingPresence = (presence, delivery)
                return
            }
            await ensureFallback()
            try await firestore.publishPresence(presence, delivery: delivery)
        }
    }

    func sendChat(_ text: String) async throws {
        try await firestore.sendChat(text)
    }

    private func emitCombinedState() {
        if isUsingFallback {
            subject.send(firestoreState)
            return
        }
        if eosState.connectionState == .connected {
            startupWatchdog?.cancel()
            startupWatchdog = nil
            schedulePendingPresenceFlush()
        }
        subject.send(PrivateIslandRealtimeState(
            connectionState: eosState.connectionState,
            presences: eosState.presences,
            messages: firestoreState.messages,
            blockedParticipantIDs: firestoreState.blockedParticipantIDs,
            errorDescription: eosState.errorDescription ?? firestoreState.errorDescription
        ))
    }

    private func beginFallbackTransition() {
        guard transitionTask == nil, !isUsingFallback else { return }
        transitionTask = Task { @MainActor [weak self] in
            await self?.performFallbackTransition()
        }
    }

    private func schedulePendingPresenceFlush() {
        guard pendingPresence != nil, pendingPresenceFlush == nil else { return }
        pendingPresenceFlush = Task { @MainActor [weak self] in
            await self?.flushPendingPresence()
        }
    }

    private func flushPendingPresence() async {
        defer { pendingPresenceFlush = nil }
        guard isStarted,
              !isUsingFallback,
              eosState.connectionState == .connected,
              let pending = pendingPresence
        else { return }
        pendingPresence = nil
        do {
            try await eosPresence.publishPresence(
                pending.value,
                delivery: pending.delivery
            )
        } catch {
            pendingPresence = pending
            await ensureFallback()
        }
    }

    private func ensureFallback() async {
        beginFallbackTransition()
        await transitionTask?.value
    }

    private func performFallbackTransition() async {
        guard !isUsingFallback else {
            transitionTask = nil
            return
        }
        await eosPresence.stop()
        guard isStarted, !Task.isCancelled else {
            transitionTask = nil
            return
        }
        isUsingFallback = true
        startupWatchdog?.cancel()
        startupWatchdog = nil
        activateFallbackReads()
        if let pendingPresence {
            self.pendingPresence = nil
            try? await firestore.publishPresence(
                pendingPresence.value,
                delivery: pendingPresence.delivery
            )
        }
        emitCombinedState()
        transitionTask = nil
    }
}

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
