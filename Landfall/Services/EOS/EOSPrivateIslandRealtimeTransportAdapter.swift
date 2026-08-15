#if EOS_SDK_AVAILABLE && !targetEnvironment(simulator)
import Combine
import EOSSDK
import FirebaseAuth
import Foundation

/// Device-only EOS adapter. Durable membership, owner authority, snapshots,
/// reports and blocks remain Firebase-owned.
@MainActor
final class EOSPrivateIslandRealtimeTransportAdapter: PrivateIslandRealtimeTransport {
    private struct VerifiedMember {
        let firebaseUID: String
        let productUserID: EOS_ProductUserId
        let productUserIDString: String
        let slot: UInt8
    }

    private var room: PrivateIslandRoom
    private let session: EOSPrivateIslandSessionConfiguration
    private let runtime: EOSSDKRuntime
    private let lobby: EOSPrivateIslandLobbySession
    private let p2p: EOSPrivateIslandP2P
    private let subject = CurrentValueSubject<PrivateIslandRealtimeState, Never>(.disconnected)
    private let linkNonce = EOSPrivateIslandRealtimeTransportAdapter
        .randomNonzeroUInt64()

    private var startTask: Task<Void, Never>?
    private var runID: UUID?
    private var user: EOSSDKRuntime.AuthenticatedUser?
    private var membersByPUID: [String: VerifiedMember] = [:]
    private var membersBySlot: [UInt8: VerifiedMember] = [:]
    private var ownerPUID: String?
    private var hostEpoch: UInt32 = 1
    private var outgoingSequences: [UInt8: UInt32] = [:]
    private var incomingSequences: [String: UInt32] = [:]
    private var presences: [String: PrivateIslandTransportPresence] = [:]
    private var messages: [PrivateIslandTransportChatMessage] = []
    private var messageIDs: Set<String> = []
    private var lastError: String?
    private var roomSubscription: AnyCancellable?
    private var membershipReconcileTask: Task<Void, Never>?
    private var healthTask: Task<Void, Never>?
    private var connectionWatchdogTask: Task<Void, Never>?
    private var establishedPUIDs: Set<String> = []

    let requiresFirestorePresenceListener = false
    var currentState: PrivateIslandRealtimeState { subject.value }
    var statePublisher: AnyPublisher<PrivateIslandRealtimeState, Never> {
        subject.eraseToAnyPublisher()
    }

    init(
        room: PrivateIslandRoom,
        session: EOSPrivateIslandSessionConfiguration,
        runtime: EOSSDKRuntime,
        persistence: PrivateIslandService
    ) throws {
        self.room = room
        self.session = session
        self.runtime = runtime
        lobby = EOSPrivateIslandLobbySession(runtime: runtime)
        p2p = try EOSPrivateIslandP2P(runtime: runtime, socketName: session.socketName)
        bindP2PCallbacks()
        roomSubscription = persistence.$currentIsland.sink { [weak self] updatedRoom in
            guard let self,
                  let updatedRoom,
                  updatedRoom.code == self.room.code
            else { return }
            self.room = updatedRoom
            if let user = self.user,
               !self.trustedUIDs.contains(user.firebaseUID) {
                Task { @MainActor [weak self] in
                    await self?.failClosed(
                        EOSPrivateIslandRuntimeError.localUserIsNotRoomMember
                    )
                }
                return
            }
            self.scheduleMembershipReconciliation()
        }
    }

    func start() {
        guard startTask == nil, currentState.connectionState == .disconnected else { return }
        let id = UUID()
        runID = id
        lastError = nil
        emit(.connecting)
        startTask = Task { [weak self] in
            await self?.start(id: id)
        }
    }

    func stop() async {
        runID = nil
        let pendingStart = startTask
        pendingStart?.cancel()
        membershipReconcileTask?.cancel()
        healthTask?.cancel()
        connectionWatchdogTask?.cancel()
        startTask = nil
        membershipReconcileTask = nil
        healthTask = nil
        connectionWatchdogTask = nil
        await pendingStart?.value
        await p2p.stop()
        if let user {
            await lobby.leave(localUserID: user.productUserID)
        }
        lobby.onMembershipChanged = nil
        user = nil
        membersByPUID.removeAll()
        membersBySlot.removeAll()
        establishedPUIDs.removeAll()
        ownerPUID = nil
        outgoingSequences.removeAll()
        incomingSequences.removeAll()
        emit(.disconnected)
    }

    func publishPresence(
        _ presence: PrivateIslandTransportPresence,
        delivery _: PrivateIslandTransportDelivery
    ) async throws {
        guard currentState.connectionState == .connected,
              let user,
              user.firebaseUID == presence.participantID,
              let local = membersByPUID[user.productUserIDString]
        else { throw EOSPrivateIslandRuntimeError.transportNotReady }

        let kind: EOSIslandPacketCodec.PacketKind = isHost ? .worldFrame : .playerSample
        let payload = try EOSPrivateIslandPayloadCodec.encodePresence(presence)
        let packet = try envelope(
            kind: kind,
            payload: payload,
            senderSlot: local.slot,
            messageID: 0
        )
        try await send(packet, stream: kind.stream, delivery: .bestEffort)
        presences[presence.participantID] = presence
        emit(.connected)
    }

    func sendChat(_ text: String) async throws {
        guard currentState.connectionState == .connected,
              let user,
              let local = membersByPUID[user.productUserIDString]
        else { throw EOSPrivateIslandRuntimeError.transportNotReady }

        let createdAt = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
        let payload = try EOSPrivateIslandPayloadCodec.encodeChat(
            text: text,
            createdAtMilliseconds: createdAt
        )
        let messageID = Self.randomNonzeroUInt64()
        let kind: EOSIslandPacketCodec.PacketKind = isHost ? .chatCommit : .chatSubmit
        let packet = try envelope(
            kind: kind,
            payload: payload,
            senderSlot: local.slot,
            messageID: messageID
        )
        try await send(packet, stream: kind.stream, delivery: .reliable)

        if isHost {
            let message = try EOSPrivateIslandPayloadCodec.decodeChat(
                payload,
                verifiedSenderID: user.firebaseUID,
                verifiedSenderName: Auth.auth().currentUser?.displayName ?? "Sailor",
                messageID: messageID
            )
            append(message)
        }
    }

    private func start(id: UUID) async {
        do {
            let user = try await runtime.authenticateWithFirebase()
            try Task.checkCancellation()
            guard runID == id, trustedUIDs.contains(user.firebaseUID) else {
                throw EOSPrivateIslandRuntimeError.localUserIsNotRoomMember
            }
            self.user = user
            lobby.onMembershipChanged = { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.membershipChanged(runID: id)
                }
            }
            let snapshot = try await lobby.start(
                sessionLocator: session.sessionLocator,
                localUserID: user.productUserID,
                createsIfMissing: user.firebaseUID == room.hostUid
            )
            try Task.checkCancellation()
            guard runID == id else { throw CancellationError() }
            try await verify(snapshot)
            try await p2p.start(localUserID: user.productUserID)
            try Task.checkCancellation()
            guard runID == id else { throw CancellationError() }
            try await acceptExpectedPeers()
            lastError = nil
            updateConnectionState(runID: id)
            startHealthChecks(runID: id)
        } catch is CancellationError {
            await cleanupStartedSession()
        } catch {
            guard runID == id else {
                await cleanupStartedSession()
                return
            }
            await failClosed(error)
        }
        if runID == id { startTask = nil }
    }

    private var trustedUIDs: Set<String> {
        Set(room.memberIds).union([room.hostUid])
    }

    private var isHost: Bool {
        guard let user, let ownerPUID else { return false }
        return user.productUserIDString == ownerPUID
    }

    /// Every lobby PUID is resolved through Connect OpenID mapping and checked
    /// against the Firebase-owned member list. Packet payload identity is never
    /// consulted.
    private func verify(_ snapshot: EOSPrivateIslandLobbySession.Snapshot) async throws {
        guard let user,
              !snapshot.memberProductUserIDs.isEmpty,
              snapshot.memberProductUserIDs.count <= PrivateIslandRoom.maxMembers
        else { throw EOSPrivateIslandRuntimeError.lobbyConfigurationInvalid }

        let previousMembers = membersByPUID
        var mapped: [(puid: String, uid: String, handle: EOS_ProductUserId)] = []
        var ownerString: String?
        for handle in snapshot.memberProductUserIDs {
            do {
                let puid = try await runtime.string(for: handle)
                if handle == snapshot.ownerProductUserID { ownerString = puid }
                let uid = try await runtime.firebaseUID(
                    for: handle,
                    localUserID: user.productUserID
                )
                guard trustedUIDs.contains(uid) else {
                    continue
                }
                mapped.append((puid, uid, handle))
            } catch {
                continue
            }
        }
        mapped.sort { $0.puid < $1.puid }

        var byPUID: [String: VerifiedMember] = [:]
        var bySlot: [UInt8: VerifiedMember] = [:]
        var usedUIDs: Set<String> = []
        for candidate in mapped where !usedUIDs.contains(candidate.uid) {
            let slot = UInt8(bySlot.count)
            let member = VerifiedMember(
                firebaseUID: candidate.uid,
                productUserID: candidate.handle,
                productUserIDString: candidate.puid,
                slot: slot
            )
            usedUIDs.insert(candidate.uid)
            byPUID[candidate.puid] = member
            bySlot[slot] = member
        }
        guard let local = byPUID[user.productUserIDString],
              local.firebaseUID == user.firebaseUID
        else { throw EOSPrivateIslandRuntimeError.localUserIsNotRoomMember }
        guard let ownerString,
              let owner = byPUID[ownerString],
              owner.firebaseUID == room.hostUid
        else {
            // Host migration is deliberately disabled until epoch/state
            // transfer exists. Never turn EOS lobby ownership into edit rights.
            throw EOSPrivateIslandRuntimeError.lobbyIdentityChanged
        }

        membersByPUID = byPUID
        membersBySlot = bySlot
        establishedPUIDs.formIntersection(byPUID.keys)
        ownerPUID = ownerString
        hostEpoch = Self.stableEpoch(lobbyID: snapshot.lobbyID, ownerPUID: ownerString)

        let removedPUIDs = Set(previousMembers.keys).subtracting(byPUID.keys)
        for puid in removedPUIDs {
            if let removed = previousMembers[puid] {
                await p2p.close(remoteUserID: removed.productUserID)
            }
        }
        let trustedRoster = Set(byPUID.values.map(\.firebaseUID))
        let priorPresenceCount = presences.count
        presences = presences.filter { trustedRoster.contains($0.key) }
        if priorPresenceCount != presences.count {
            emit(currentState.connectionState)
        }
    }

    private func membershipChanged(runID expectedRunID: UUID) async {
        guard runID == expectedRunID, let user else { return }
        do {
            let snapshot = try await lobby.refresh(localUserID: user.productUserID)
            try await verify(snapshot)
            try await acceptExpectedPeers()
            updateConnectionState(runID: expectedRunID)
        } catch {
            guard runID == expectedRunID else { return }
            await failClosed(error)
        }
    }

    private func scheduleMembershipReconciliation() {
        guard user != nil else { return }
        membershipReconcileTask?.cancel()
        membershipReconcileTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, let user = self.user else { return }
            do {
                let snapshot = try await self.lobby.refresh(
                    localUserID: user.productUserID
                )
                try await self.verify(snapshot)
                try await self.acceptExpectedPeers()
                if let runID = self.runID {
                    self.updateConnectionState(runID: runID)
                }
            } catch {
                // A Firestore/Lobby listener race is expected while a member
                // joins or leaves. Lobby notification and the next room update
                // both retry; packet authorization remains fail-closed.
            }
            self.membershipReconcileTask = nil
        }
    }

    private func startHealthChecks(runID expectedRunID: UUID) {
        healthTask?.cancel()
        healthTask = Task { @MainActor [weak self] in
            var consecutiveFailures = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled,
                      let self,
                      self.runID == expectedRunID,
                      let user = self.user
                else { return }
                do {
                    let snapshot = try await self.lobby.refresh(
                        localUserID: user.productUserID
                    )
                    try await self.verify(snapshot)
                    try await self.acceptExpectedPeers()
                    self.updateConnectionState(runID: expectedRunID)
                    consecutiveFailures = 0
                } catch {
                    consecutiveFailures += 1
                    if consecutiveFailures >= 2 {
                        await self.failClosed(error)
                        return
                    }
                }
            }
        }
    }

    private func acceptExpectedPeers() async throws {
        guard let user, let ownerPUID else {
            throw EOSPrivateIslandRuntimeError.transportNotReady
        }
        if isHost {
            for member in membersByPUID.values
                where member.productUserIDString != user.productUserIDString
            {
                try await p2p.accept(remoteUserID: member.productUserID)
                if !establishedPUIDs.contains(member.productUserIDString) {
                    try? await sendConnectionProbe(to: member)
                }
            }
        } else {
            guard let owner = membersByPUID[ownerPUID] else {
                throw EOSPrivateIslandRuntimeError.lobbyConfigurationInvalid
            }
            try await p2p.accept(remoteUserID: owner.productUserID)
            if !establishedPUIDs.contains(owner.productUserIDString) {
                try? await sendConnectionProbe(to: owner)
            }
        }
    }

    private func bindP2PCallbacks() {
        p2p.onConnectionRequest = { [weak self] handle, puid in
            Task { @MainActor [weak self] in
                await self?.handleConnectionRequest(handle: handle, puid: puid)
            }
        }
        p2p.onPacket = { [weak self] packet in
            Task { @MainActor [weak self] in await self?.handle(packet) }
        }
        p2p.onConnectionEstablished = { [weak self] handle, puid in
            Task { @MainActor [weak self] in
                await self?.connectionEstablished(handle: handle, puid: puid)
            }
        }
        p2p.onConnectionClosed = { [weak self] handle, puid in
            Task { @MainActor [weak self] in
                await self?.connectionClosed(handle: handle, puid: puid)
            }
        }
        p2p.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                await self?.failClosed(error)
            }
        }
    }

    private func handleConnectionRequest(
        handle: EOS_ProductUserId,
        puid: String
    ) async {
        guard let user else {
            await p2p.close(remoteUserID: handle)
            return
        }
        for attempt in 0..<3 {
            do {
                let snapshot = try await lobby.refresh(localUserID: user.productUserID)
                try await verify(snapshot)
                if let member = membersByPUID[puid],
                   member.productUserID == handle,
                   expectedRemote(puid) {
                    try await p2p.accept(remoteUserID: handle)
                    try? await sendConnectionProbe(to: member)
                    return
                }
            } catch {
                if attempt == 2 { publish(error) }
            }
            if attempt < 2 {
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        await p2p.close(remoteUserID: handle)
    }

    private func connectionEstablished(
        handle: EOS_ProductUserId,
        puid: String
    ) async {
        guard let expectedRunID = runID, let user else {
            await p2p.close(remoteUserID: handle)
            return
        }
        for attempt in 0..<3 {
            if let member = membersByPUID[puid],
               member.productUserID == handle,
               expectedRemote(puid) {
                establishedPUIDs.insert(puid)
                lastError = nil
                updateConnectionState(runID: expectedRunID)
                if isHost {
                    await sendCachedPresences(to: member)
                }
                return
            }
            do {
                let snapshot = try await lobby.refresh(localUserID: user.productUserID)
                try await verify(snapshot)
                try await acceptExpectedPeers()
            } catch {
                if attempt == 2 { publish(error) }
            }
            if attempt < 2 {
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        await p2p.close(remoteUserID: handle)
    }

    private func connectionClosed(
        handle: EOS_ProductUserId,
        puid: String
    ) async {
        guard let expectedRunID = runID else { return }
        establishedPUIDs.remove(puid)
        if let member = membersByPUID[puid], member.productUserID == handle {
            presences.removeValue(forKey: member.firebaseUID)
        }
        updateConnectionState(runID: expectedRunID)
        scheduleMembershipReconciliation()
    }

    private func expectedRemote(_ puid: String) -> Bool {
        guard let user, let ownerPUID else { return false }
        return isHost
            ? puid != user.productUserIDString && membersByPUID[puid] != nil
            : puid == ownerPUID
    }

    private var requiredRemotePUIDs: Set<String> {
        guard user != nil, let ownerPUID else { return [] }
        if isHost {
            // A star host remains healthy while individual guests establish or
            // reconnect; each guest independently requires the owner link.
            return []
        }
        return membersByPUID[ownerPUID] == nil ? [] : [ownerPUID]
    }

    private func updateConnectionState(runID expectedRunID: UUID) {
        guard runID == expectedRunID else { return }
        let required = requiredRemotePUIDs
        if required.isSubset(of: establishedPUIDs) {
            connectionWatchdogTask?.cancel()
            connectionWatchdogTask = nil
            lastError = nil
            emit(.connected)
            return
        }

        emit(.connecting)
        guard connectionWatchdogTask == nil else { return }
        connectionWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled,
                  let self,
                  self.runID == expectedRunID,
                  let user = self.user
            else { return }
            do {
                let snapshot = try await self.lobby.refresh(
                    localUserID: user.productUserID
                )
                try await self.verify(snapshot)
                try await self.acceptExpectedPeers()
                guard self.requiredRemotePUIDs.isSubset(of: self.establishedPUIDs) else {
                    throw EOSPrivateIslandRuntimeError.transportNotReady
                }
                self.connectionWatchdogTask = nil
                self.updateConnectionState(runID: expectedRunID)
            } catch {
                self.connectionWatchdogTask = nil
                await self.failClosed(error)
            }
        }
    }

    private func sendConnectionProbe(to member: VerifiedMember) async throws {
        let kind = EOSIslandPacketCodec.PacketKind.hello
        let header = EOSIslandPacketCodec.Header(
            kind: kind,
            hostEpoch: 0,
            sequence: nextSequence(stream: kind.stream),
            hostTickMilliseconds: 0,
            senderSlot: .max,
            linkNonce: linkNonce,
            messageID: Self.randomNonzeroUInt64()
        )
        let packet = try EOSIslandPacketCodec.encode(
            header: header,
            payload: Data(),
            outgoingChannel: kind.stream
        )
        try await p2p.send(
            packet,
            to: member.productUserID,
            channel: kind.stream,
            delivery: .reliable,
            allowDelayedDelivery: true
        )
    }

    private func sendCachedPresences(to recipient: VerifiedMember) async {
        for presence in presences.values {
            guard let origin = membersByPUID.values.first(where: {
                $0.firebaseUID == presence.participantID
            }) else { continue }
            do {
                let payload = try EOSPrivateIslandPayloadCodec.encodePresence(presence)
                let packet = try envelope(
                    kind: .worldFrame,
                    payload: payload,
                    senderSlot: origin.slot,
                    messageID: 0
                )
                try await p2p.send(
                    packet,
                    to: recipient.productUserID,
                    channel: EOSIslandPacketCodec.PacketKind.worldFrame.stream,
                    delivery: .bestEffort
                )
            } catch {
                publish(error)
                return
            }
        }
    }

    private func handle(_ received: EOSPrivateIslandP2P.ReceivedPacket) async {
        guard let remote = membersByPUID[received.remoteProductUserIDString],
              remote.productUserID == received.remoteProductUserID,
              expectedRemote(received.remoteProductUserIDString)
        else {
            await p2p.close(remoteUserID: received.remoteProductUserID)
            return
        }
        guard let packet = try? EOSIslandPacketCodec.decode(
            received.data,
            receivedChannel: received.channel
        ) else { return }
        if packet.registeredKind == .hello { return }
        guard currentState.connectionState == .connected,
              packet.header.hostEpoch == hostEpoch
        else { return }

        let origin: VerifiedMember
        if isHost {
            guard packet.header.senderSlot == remote.slot else {
                await p2p.close(remoteUserID: received.remoteProductUserID)
                return
            }
            origin = remote
        } else {
            guard received.remoteProductUserIDString == ownerPUID,
                  let member = membersBySlot[packet.header.senderSlot]
            else { return }
            origin = member
        }
        guard acceptSequence(packet.header, origin: origin) else { return }

        do {
            switch packet.registeredKind {
            case .playerSample where isHost:
                let value = try EOSPrivateIslandPayloadCodec.decodePresence(
                    packet.payload,
                    verifiedParticipantID: origin.firebaseUID
                )
                presences[origin.firebaseUID] = value
                emit(.connected)
                try await relay(
                    payload: packet.payload,
                    kind: .worldFrame,
                    slot: origin.slot,
                    messageID: 0,
                    excluding: remote.productUserIDString,
                    delivery: .bestEffort
                )
            case .worldFrame where !isHost:
                presences[origin.firebaseUID] = try EOSPrivateIslandPayloadCodec
                    .decodePresence(packet.payload, verifiedParticipantID: origin.firebaseUID)
                emit(.connected)
            case .chatSubmit where isHost:
                let message = try EOSPrivateIslandPayloadCodec.decodeChat(
                    packet.payload,
                    verifiedSenderID: origin.firebaseUID,
                    verifiedSenderName: "Sailor",
                    messageID: packet.header.messageID
                )
                append(message)
                try await relay(
                    payload: packet.payload,
                    kind: .chatCommit,
                    slot: origin.slot,
                    messageID: packet.header.messageID,
                    excluding: nil,
                    delivery: .reliable
                )
            case .chatCommit where !isHost:
                append(try EOSPrivateIslandPayloadCodec.decodeChat(
                    packet.payload,
                    verifiedSenderID: origin.firebaseUID,
                    verifiedSenderName: origin.firebaseUID == user?.firebaseUID
                        ? (Auth.auth().currentUser?.displayName ?? "Sailor")
                        : "Sailor",
                    messageID: packet.header.messageID
                ))
            default:
                break
            }
        } catch {
            publish(error)
        }
    }

    private func acceptSequence(
        _ header: EOSIslandPacketCodec.Header,
        origin: VerifiedMember
    ) -> Bool {
        let key = "\(origin.productUserIDString):\(header.stream):\(header.linkNonce)"
        if let prior = incomingSequences[key],
           !EOSIslandPacketCodec.isSerialNewer(header.sequence, than: prior) {
            return false
        }
        incomingSequences[key] = header.sequence
        return true
    }

    private func relay(
        payload: Data,
        kind: EOSIslandPacketCodec.PacketKind,
        slot: UInt8,
        messageID: UInt64,
        excluding: String?,
        delivery: PrivateIslandTransportDelivery
    ) async throws {
        let packet = try envelope(
            kind: kind,
            payload: payload,
            senderSlot: slot,
            messageID: messageID
        )
        try await send(
            packet,
            stream: kind.stream,
            delivery: delivery,
            excluding: excluding
        )
    }

    private func envelope(
        kind: EOSIslandPacketCodec.PacketKind,
        payload: Data,
        senderSlot: UInt8,
        messageID: UInt64
    ) throws -> Data {
        let header = EOSIslandPacketCodec.Header(
            kind: kind,
            hostEpoch: hostEpoch,
            sequence: nextSequence(stream: kind.stream),
            hostTickMilliseconds: UInt32(
                truncatingIfNeeded: UInt64(
                    (ProcessInfo.processInfo.systemUptime * 1_000).rounded()
                )
            ),
            senderSlot: senderSlot,
            linkNonce: linkNonce,
            messageID: messageID
        )
        return try EOSIslandPacketCodec.encode(
            header: header,
            payload: payload,
            outgoingChannel: kind.stream
        )
    }

    private func nextSequence(stream: UInt8) -> UInt32 {
        let next = outgoingSequences[stream, default: 0] &+ 1
        outgoingSequences[stream] = next
        return next
    }

    private func send(
        _ packet: Data,
        stream: UInt8,
        delivery: PrivateIslandTransportDelivery,
        excluding: String? = nil
    ) async throws {
        guard let user, let ownerPUID else {
            throw EOSPrivateIslandRuntimeError.transportNotReady
        }
        let recipients: [VerifiedMember]
        if isHost {
            recipients = membersByPUID.values.filter {
                $0.productUserIDString != user.productUserIDString
                    && $0.productUserIDString != excluding
                    && establishedPUIDs.contains($0.productUserIDString)
            }
        } else if let owner = membersByPUID[ownerPUID],
                  establishedPUIDs.contains(owner.productUserIDString) {
            recipients = [owner]
        } else {
            throw EOSPrivateIslandRuntimeError.lobbyConfigurationInvalid
        }

        var firstError: Error?
        for recipient in recipients {
            do {
                try await p2p.send(
                    packet,
                    to: recipient.productUserID,
                    channel: stream,
                    delivery: delivery
                )
            } catch {
                firstError = firstError ?? error
            }
        }
        if recipients.count == 1, let firstError { throw firstError }
    }

    private func append(_ message: PrivateIslandTransportChatMessage) {
        guard messageIDs.insert(message.id).inserted else { return }
        messages.append(message)
        let excess = messages.count - 200
        if excess > 0 {
            let removed = Array(messages.prefix(excess))
            messages.removeFirst(excess)
            removed.forEach { messageIDs.remove($0.id) }
        }
        emit(.connected)
    }

    private func publish(_ error: Error) {
        lastError = error.localizedDescription
        emit(currentState.connectionState)
    }

    private func failClosed(_ error: Error) async {
        lastError = error.localizedDescription
        runID = nil
        startTask = nil
        membershipReconcileTask?.cancel()
        membershipReconcileTask = nil
        healthTask?.cancel()
        healthTask = nil
        connectionWatchdogTask?.cancel()
        connectionWatchdogTask = nil
        await p2p.stop()
        if let user { await lobby.leave(localUserID: user.productUserID) }
        lobby.onMembershipChanged = nil
        establishedPUIDs.removeAll()
        emit(.disconnected)
    }

    private func cleanupStartedSession() async {
        connectionWatchdogTask?.cancel()
        connectionWatchdogTask = nil
        healthTask?.cancel()
        healthTask = nil
        membershipReconcileTask?.cancel()
        membershipReconcileTask = nil
        await p2p.stop()
        if let user {
            await lobby.leave(localUserID: user.productUserID)
        }
        lobby.onMembershipChanged = nil
        establishedPUIDs.removeAll()
    }

    private func emit(_ connection: PrivateIslandRealtimeConnectionState) {
        subject.send(PrivateIslandRealtimeState(
            connectionState: connection,
            presences: presences.values.sorted { $0.participantID < $1.participantID },
            messages: messages,
            blockedParticipantIDs: [],
            errorDescription: lastError
        ))
    }

    private static func randomNonzeroUInt64() -> UInt64 {
        var value: UInt64 = 0
        while value == 0 { value = UInt64.random(in: .min ... .max) }
        return value
    }

    private static func stableEpoch(lobbyID: String, ownerPUID: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in "\(lobbyID):\(ownerPUID)".utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return hash == 0 ? 1 : hash
    }
}
#endif
