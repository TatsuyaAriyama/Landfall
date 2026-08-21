import Combine
import FirebaseAuth
import SwiftUI

/// Turns the already-visible Home Island into the host's multiplayer world.
///
/// Unlike `PrivateIslandVisitWorld`, this coordinator does not create another
/// `HomeIslandView`. It only supplies networking inputs to the existing home
/// scene, preserving the navigator, camera, editor state, and local island
/// store when a private island is created or reopened.
@MainActor
final class HostedPrivateIslandSessionCoordinator: ObservableObject {
    @Published private(set) var activeRoom: PrivateIslandRoom?
    @Published private(set) var coordinatorError: String?
    @Published private var liveRoom: PrivateIslandRoom?
    @Published private var realtimeState = PrivateIslandRealtimeState.disconnected

    private let realtimeClientFactory: PrivateIslandRealtimeClientFactory
    private var islandService: PrivateIslandService?
    private var realtimeClient: PrivateIslandRealtimeClient?
    private var subscriptions: Set<AnyCancellable> = []
    private var pendingPresence: HomeIslandRemotePlayerState?
    private var presencePublishTask: Task<Void, Never>?
    private var lastPublishedPresence: PrivateIslandTransportPresence?
    /// 島の景色がたたまれても、最後に立っていた場所は残しておく。同行の航海の
    /// あいだ presence に載せ続け、戻ったときも同じ場所から再開できる。
    private var lastIslandPlayerState: HomeIslandRemotePlayerState?

    init(
        realtimeClientFactory: @escaping PrivateIslandRealtimeClientFactory = { room, persistence in
            PrivateIslandRealtimeClient.live(room: room, persistence: persistence)
        }
    ) {
        self.realtimeClientFactory = realtimeClientFactory
    }

    var multiplayerSession: HomeIslandMultiplayerSession? {
        guard let activeRoom,
              islandService != nil,
              let realtimeClient,
              let uid = Auth.auth().currentUser?.uid,
              !uid.isEmpty,
              uid == activeRoom.hostUid
        else { return nil }

        return HomeIslandMultiplayerSession(
            room: liveRoom ?? activeRoom,
            snapshot: nil,
            presences: realtimeState.presences.map {
                PrivateIslandTransportCodec.legacyPresence(from: $0)
            },
            currentUserID: uid,
            role: .host,
            messages: realtimeState.messages.map {
                PrivateIslandTransportCodec.legacyChatMessage(from: $0)
            },
            isChatConnected: realtimeState.connectionState == .connected,
            onLocalPlayerStateChanged: { [weak self] state in
                self?.enqueuePresence(state)
            },
            onHostSnapshotChanged: { [weak self] snapshot in
                self?.islandService?.enqueueOwnedSnapshot(snapshot)
            },
            onSendChatMessage: { text in
                try await realtimeClient.sendChat(text)
            },
            onReportChatMessage: { [weak self] message in
                self?.report(message)
            },
            onBlockChatMessage: { [weak self] message in
                self?.toggleBlock(message)
            }
        )
    }

    /// Starts multiplayer transport without replacing the visible island.
    func activate(room: PrivateIslandRoom, localOwnerID: String) {
        guard let uid = Auth.auth().currentUser?.uid,
              !uid.isEmpty,
              uid == room.hostUid
        else {
            coordinatorError = PrivateIslandError.notHost.localizedDescription
            return
        }
        guard activeRoom?.code != room.code else { return }

        deactivate()
        coordinatorError = nil

        let islandService = PrivateIslandService()
        let realtimeClient = realtimeClientFactory(room, islandService)
        self.islandService = islandService
        self.realtimeClient = realtimeClient

        // Mirror published values after mutation. Forwarding objectWillChange
        // fires before the nested value changes and could leave the existing
        // HomeIslandView rendering the previous chat array.
        islandService.$currentIsland
            .sink { [weak self] room in self?.liveRoom = room }
            .store(in: &subscriptions)
        realtimeClient.$state
            .sink { [weak self] state in self?.realtimeState = state }
            .store(in: &subscriptions)

        activeRoom = room
        islandService.listenToIsland(
            code: room.code,
            includeFirestorePresence: realtimeClient.requiresFirestorePresenceListener
        )
        realtimeClient.start()

        Task { @MainActor [weak self] in
            do {
                try await islandService.publishProfile(to: room.code)
                self?.coordinatorError = nil
            } catch {
                self?.coordinatorError = error.localizedDescription
            }
        }

        let ownerKey = HomeIslandPersistence.ownerKey(for: localOwnerID)
        islandService.enqueueOwnedSnapshot(
            HomeIslandPersistence.load(ownerKey: ownerKey)
        )
    }

    /// 同行の航海の段階を島の仲間へ知らせる。`nil` は島へ戻ったこと。
    ///
    /// 航海中はホームの島ビューが外れていて、位置を送る経路が止まっている。
    /// この調整役は画面より長く生きているので、ここだけが presence を保てる。
    func publishCompanionVoyage(
        stage: CompanionVoyageStage?,
        identity: CompanionVoyageIdentity
    ) {
        guard let room = activeRoom,
              let uid = Auth.auth().currentUser?.uid,
              uid == room.hostUid
        else { return }
        let state: HomeIslandRemotePlayerState
        if let stage {
            state = CompanionVoyagePresence.state(
                stage: stage,
                continuing: lastIslandPlayerState,
                localID: uid,
                identity: identity
            )
        } else {
            state = CompanionVoyagePresence.ashoreState(
                continuing: lastIslandPlayerState,
                localID: uid
            )
        }
        enqueuePresence(state)
    }

    /// Detaches networking only. The local Home Island view remains alive.
    func deactivate() {
        guard activeRoom != nil || islandService != nil || realtimeClient != nil else { return }
        let islandService = islandService
        let realtimeClient = realtimeClient
        let presenceTask = presencePublishTask

        activeRoom = nil
        self.islandService = nil
        self.realtimeClient = nil
        subscriptions.removeAll()
        liveRoom = nil
        realtimeState = .disconnected
        pendingPresence = nil
        lastPublishedPresence = nil
        lastIslandPlayerState = nil
        presencePublishTask = nil
        presenceTask?.cancel()

        Task { @MainActor in
            await presenceTask?.value
            await realtimeClient?.stop()
            islandService?.stopIslandListeners()
        }
    }

    private func enqueuePresence(_ state: HomeIslandRemotePlayerState) {
        guard let room = activeRoom,
              let realtimeClient,
              let uid = Auth.auth().currentUser?.uid,
              uid == room.hostUid
        else { return }

        if state.scene == "island" { lastIslandPlayerState = state }
        pendingPresence = state
        guard presencePublishTask == nil else { return }

        presencePublishTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled,
                  self.activeRoom?.code == room.code,
                  let state = self.pendingPresence {
                self.pendingPresence = nil
                let presence = PrivateIslandTransportCodec.presence(
                    from: state,
                    participantID: uid
                )
                let previous = self.lastPublishedPresence
                do {
                    try await realtimeClient.publishPresence(
                        presence,
                        delivery: PrivateIslandTransportCodec.delivery(
                            for: presence,
                            after: previous
                        )
                    )
                    self.lastPublishedPresence = presence
                    self.coordinatorError = nil
                } catch is CancellationError {
                    break
                } catch {
                    self.coordinatorError = error.localizedDescription
                }
            }
            self.presencePublishTask = nil
        }
    }

    private func report(_ message: PrivateIslandChatMessage) {
        Task { @MainActor [weak self] in
            guard let self, let realtimeClient else { return }
            do {
                try await realtimeClient.report(
                    PrivateIslandTransportCodec.chatMessage(from: message)
                )
            } catch {
                coordinatorError = error.localizedDescription
            }
        }
    }

    private func toggleBlock(_ message: PrivateIslandChatMessage) {
        Task { @MainActor [weak self] in
            guard let self, let realtimeClient else { return }
            do {
                let isBlocked = realtimeState.blockedParticipantIDs.contains(message.senderID)
                try await realtimeClient.setBlocked(message.senderID, blocked: !isBlocked)
            } catch {
                coordinatorError = error.localizedDescription
            }
        }
    }
}
