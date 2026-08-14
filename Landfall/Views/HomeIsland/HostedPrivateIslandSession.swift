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
    @Published private var livePresences: [PrivateIslandPresence] = []
    @Published private var liveMessages: [PrivateIslandChatMessage] = []

    private var islandService: PrivateIslandService?
    private var chatService: PrivateIslandChatService?
    private var subscriptions: Set<AnyCancellable> = []
    private var pendingPresence: HomeIslandRemotePlayerState?
    private var presencePublishTask: Task<Void, Never>?
    private var lastPublishedPresence: HomeIslandRemotePlayerState?

    var multiplayerSession: HomeIslandMultiplayerSession? {
        guard let activeRoom,
              let islandService,
              let chatService,
              let uid = Auth.auth().currentUser?.uid,
              !uid.isEmpty,
              uid == activeRoom.hostUid
        else { return nil }

        return HomeIslandMultiplayerSession(
            room: liveRoom ?? activeRoom,
            snapshot: nil,
            presences: livePresences,
            currentUserID: uid,
            role: .host,
            messages: liveMessages,
            isChatConnected: liveRoom != nil,
            onLocalPlayerStateChanged: { [weak self] state in
                self?.enqueuePresence(state)
            },
            onHostSnapshotChanged: { [weak self] snapshot in
                self?.islandService?.enqueueOwnedSnapshot(snapshot)
            },
            onSendChatMessage: { [weak self] text in
                guard let self, let chatService = self.chatService else {
                    throw PrivateIslandError.islandNotFound
                }
                try await chatService.send(text)
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
        let chatService = PrivateIslandChatService(islandCode: room.code)
        self.islandService = islandService
        self.chatService = chatService

        // Mirror published values after mutation. Forwarding objectWillChange
        // fires before the nested value changes and could leave the existing
        // HomeIslandView rendering the previous chat array.
        islandService.$currentIsland
            .sink { [weak self] room in self?.liveRoom = room }
            .store(in: &subscriptions)
        islandService.$presences
            .sink { [weak self] presences in self?.livePresences = presences }
            .store(in: &subscriptions)
        chatService.$messages
            .sink { [weak self] messages in self?.liveMessages = messages }
            .store(in: &subscriptions)

        activeRoom = room
        islandService.listenToIsland(code: room.code)
        chatService.start()

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

    /// Detaches networking only. The local Home Island view remains alive.
    func deactivate() {
        guard activeRoom != nil || islandService != nil || chatService != nil else { return }
        let room = activeRoom
        let islandService = islandService
        let chatService = chatService
        let presenceTask = presencePublishTask

        activeRoom = nil
        self.islandService = nil
        self.chatService = nil
        subscriptions.removeAll()
        liveRoom = nil
        livePresences = []
        liveMessages = []
        pendingPresence = nil
        lastPublishedPresence = nil
        presencePublishTask = nil
        presenceTask?.cancel()

        Task { @MainActor in
            await presenceTask?.value
            if let room, let islandService {
                await islandService.removePresence(from: room.code)
            }
            islandService?.stopIslandListeners()
            chatService?.stop()
        }
    }

    private func enqueuePresence(_ state: HomeIslandRemotePlayerState) {
        guard let room = activeRoom,
              let islandService,
              Auth.auth().currentUser?.uid == room.hostUid
        else { return }

        pendingPresence = state
        guard presencePublishTask == nil else { return }

        presencePublishTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled,
                  self.activeRoom?.code == room.code,
                  let state = self.pendingPresence {
                self.pendingPresence = nil
                let previous = self.lastPublishedPresence
                do {
                    try await islandService.publishPresence(
                        code: room.code,
                        x: state.x,
                        z: state.z,
                        yaw: state.yaw,
                        pose: state.pose,
                        scene: state.scene,
                        phase: state.phase,
                        seat: Self.seatAddress(from: state),
                        force: Self.shouldForcePresence(state, after: previous)
                    )
                    self.lastPublishedPresence = state
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

    private static func seatAddress(
        from state: HomeIslandRemotePlayerState
    ) -> HomeIslandSeatAddress? {
        guard let placementString = state.seatPlacementID,
              let placementID = UUID(uuidString: placementString),
              let slotID = state.seatSlotID,
              !slotID.isEmpty
        else { return nil }
        return HomeIslandSeatAddress(placementID: placementID, slotID: slotID)
    }

    private static func shouldForcePresence(
        _ state: HomeIslandRemotePlayerState,
        after previous: HomeIslandRemotePlayerState?
    ) -> Bool {
        guard let previous else { return true }
        return state.phase != previous.phase
            || state.pose != previous.pose
            || state.scene != previous.scene
            || state.seatPlacementID != previous.seatPlacementID
            || state.seatSlotID != previous.seatSlotID
            || state.isVisible != previous.isVisible
    }

    private func report(_ message: PrivateIslandChatMessage) {
        Task { @MainActor [weak self] in
            guard let self, let chatService else { return }
            do {
                try await chatService.report(message, targetUserID: message.senderID)
            } catch {
                coordinatorError = error.localizedDescription
            }
        }
    }

    private func toggleBlock(_ message: PrivateIslandChatMessage) {
        Task { @MainActor [weak self] in
            guard let self, let chatService else { return }
            do {
                if chatService.blockedUserIDs.contains(message.senderID) {
                    try await chatService.unblock(message.senderID)
                } else {
                    try await chatService.block(message.senderID)
                }
            } catch {
                coordinatorError = error.localizedDescription
            }
        }
    }
}
