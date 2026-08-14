import FirebaseAuth
import SwiftUI

/// Owns one live private-island visit from entry through the final presence
/// removal. A visit deliberately receives dedicated service instances so a
/// lobby refresh or a second presentation cannot tear down its listeners.
struct PrivateIslandVisitWorld: View {
    let room: PrivateIslandRoom
    let localOwnerID: String
    let levelProgress: PlayerLevelProgress
    let onClose: () -> Void
    let onPrivateIslandSelected: (PrivateIslandRoom) -> Void

    @StateObject private var islandService: PrivateIslandService
    @StateObject private var realtimeClient: PrivateIslandRealtimeClient

    @State private var hasStarted = false
    @State private var isShuttingDown = false
    @State private var coordinatorError: String?
    @State private var guestWaitIsLong = false
    @State private var guestResolutionTask: Task<Void, Never>?

    // Firestore writes are kept serial. Placement edits debounce into the
    // newest complete snapshot; player transforms use a latest-value queue and
    // rely on PrivateIslandService's trailing throttle for smooth movement.
    @State private var pendingHostSnapshot: HomeIslandSnapshot?
    @State private var snapshotPublishTask: Task<Void, Never>?
    @State private var pendingPresence: HomeIslandRemotePlayerState?
    @State private var presencePublishTask: Task<Void, Never>?
    @State private var lastPublishedPresence: PrivateIslandTransportPresence?

    private let currentUserID: String

    init(
        room: PrivateIslandRoom,
        localOwnerID: String,
        levelProgress: PlayerLevelProgress,
        onClose: @escaping () -> Void,
        onPrivateIslandSelected: @escaping (PrivateIslandRoom) -> Void,
        realtimeClientFactory: @escaping PrivateIslandRealtimeClientFactory = { room, persistence in
            PrivateIslandRealtimeClient.live(room: room, persistence: persistence)
        }
    ) {
        self.room = room
        self.localOwnerID = localOwnerID
        self.levelProgress = levelProgress
        self.onClose = onClose
        self.onPrivateIslandSelected = onPrivateIslandSelected
        currentUserID = Auth.auth().currentUser?.uid ?? ""
        let persistence = PrivateIslandService()
        _islandService = StateObject(wrappedValue: persistence)
        _realtimeClient = StateObject(
            wrappedValue: realtimeClientFactory(room, persistence)
        )
    }

    private var isHost: Bool {
        !currentUserID.isEmpty && currentUserID == room.hostUid
    }

    private var sessionIdentity: String {
        "private-island:\(room.code):\(currentUserID.isEmpty ? "signed-out" : currentUserID)"
    }

    private var multiplayerSession: HomeIslandMultiplayerSession {
        HomeIslandMultiplayerSession(
            room: islandService.currentIsland ?? room,
            snapshot: islandService.islandSnapshot,
            presences: realtimeClient.state.presences.map {
                PrivateIslandTransportCodec.legacyPresence(from: $0)
            },
            currentUserID: currentUserID,
            role: isHost ? .host : .guestReadOnly,
            messages: realtimeClient.state.messages.map {
                PrivateIslandTransportCodec.legacyChatMessage(from: $0)
            },
            // A recovered listener may retain its last diagnostic text. The
            // live room is the authoritative availability signal for sending.
            isChatConnected: realtimeClient.state.connectionState == .connected,
            onLocalPlayerStateChanged: { state in
                enqueuePresence(state)
            },
            onHostSnapshotChanged: isHost ? { snapshot in
                enqueueHostSnapshot(snapshot)
            } : nil,
            onSendChatMessage: { text in
                try await realtimeClient.sendChat(text)
            },
            onReportChatMessage: { message in
                report(message)
            },
            onBlockChatMessage: { message in
                block(message)
            }
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            HomeIslandView(
                ownerID: localOwnerID,
                levelProgress: levelProgress,
                startsMooredAtIsland: isHost,
                boatTapOpensSelection: false,
                onDepartureCompleted: {
                    shutDown(thenClose: true)
                },
                multiplayerSession: multiplayerSession,
                onPrivateIslandSelected: onPrivateIslandSelected
            )
            .id(sessionIdentity)

            statusOverlay
                .padding(.horizontal, 16)
                .safeAreaPadding(.top, 10)
        }
        .id(sessionIdentity)
        .onAppear(perform: start)
        .onChange(of: islandService.hasResolvedIslandSnapshot) { _, resolved in
            guard resolved else { return }
            guestResolutionTask?.cancel()
            guestResolutionTask = nil
            guestWaitIsLong = false
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if let errorText {
            HStack(spacing: 10) {
                Label {
                    Text(verbatim: errorText)
                        .lineLimit(2)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(LFColor.deepRust)
                }
                Button("Retry") {
                    restartVisit()
                }
                .font(LFFont.label(10))
                .buttonStyle(.bordered)
            }
            .font(LFFont.label(11))
            .foregroundStyle(Color(uiColor: VoyageSceneKit.nightBG))
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(.white.opacity(0.88), in: Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
        } else if !isHost, !islandService.hasResolvedIslandSnapshot {
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color(uiColor: VoyageSceneKit.nightBG))
                VStack(alignment: .leading, spacing: 1) {
                    Text(guestWaitIsLong ? "Waiting for the host's island" : "Charting the island…")
                        .font(LFFont.copy(12))
                    if guestWaitIsLong {
                        Text("You can still finish sailing to the jetty.")
                            .font(LFFont.label(9))
                            .opacity(0.55)
                    }
                }
            }
            .foregroundStyle(Color(uiColor: VoyageSceneKit.nightBG))
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(.white.opacity(0.84), in: Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(0.66), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 12, y: 5)
            .accessibilityElement(children: .combine)
        }
    }

    private var errorText: String? {
        coordinatorError ?? islandService.errorMessage ?? realtimeClient.state.errorDescription
    }

    private func start() {
        guard !hasStarted else { return }
        hasStarted = true
        isShuttingDown = false
        coordinatorError = nil

        guard !currentUserID.isEmpty else {
            coordinatorError = PrivateIslandError.notSignedIn.localizedDescription
            return
        }

        listenToDurableIslandState()
        realtimeClient.start()

        Task { @MainActor in
            do {
                try await islandService.publishProfile(to: room.code)
            } catch {
                coordinatorError = error.localizedDescription
            }
        }

        if isHost {
            let ownerKey = HomeIslandPersistence.ownerKey(for: localOwnerID)
            enqueueHostSnapshot(
                HomeIslandPersistence.load(ownerKey: ownerKey),
                immediately: true
            )
        } else {
            beginGuestResolutionWatchdog()
        }
    }

    /// Firestore can briefly lose its watch stream while a full-screen SceneKit
    /// world is being attached. Recover the visit once instead of leaving the
    /// guest on an empty local-looking island with an endless spinner.
    private func beginGuestResolutionWatchdog() {
        guestResolutionTask?.cancel()
        guestResolutionTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled,
                  !isShuttingDown,
                  !islandService.hasResolvedIslandSnapshot
            else { return }

            withAnimation(.easeOut(duration: 0.2)) {
                guestWaitIsLong = true
            }
            listenToDurableIslandState()
            realtimeClient.start()

            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled,
                  !isShuttingDown,
                  !islandService.hasResolvedIslandSnapshot
            else { return }
            coordinatorError = LF.text("The host's island could not be loaded. Please try again.")
        }
    }

    private func restartVisit() {
        guard !isShuttingDown else { return }
        coordinatorError = nil
        guestWaitIsLong = false
        listenToDurableIslandState()
        realtimeClient.start()
        beginGuestResolutionWatchdog()
        Haptics.tap(.medium)
    }

    private func listenToDurableIslandState() {
        islandService.listenToIsland(
            code: room.code,
            includeFirestorePresence: realtimeClient.requiresFirestorePresenceListener
        )
    }

    // MARK: - Host snapshot transport

    private func enqueueHostSnapshot(
        _ snapshot: HomeIslandSnapshot,
        immediately: Bool = false
    ) {
        guard isHost, hasStarted, !isShuttingDown else { return }
        pendingHostSnapshot = snapshot
        guard snapshotPublishTask == nil else { return }

        snapshotPublishTask = Task { @MainActor in
            if !immediately {
                try? await Task.sleep(for: .milliseconds(320))
            }
            guard !Task.isCancelled else {
                snapshotPublishTask = nil
                return
            }

            while !Task.isCancelled, !isShuttingDown,
                  let snapshot = pendingHostSnapshot {
                pendingHostSnapshot = nil
                do {
                    try await islandService.publishSnapshot(snapshot, to: room.code)
                    coordinatorError = nil
                } catch is CancellationError {
                    break
                } catch {
                    coordinatorError = error.localizedDescription
                }

                // If more edits arrived during the write, coalesce them once
                // more before publishing the newest full placement document.
                if pendingHostSnapshot != nil {
                    try? await Task.sleep(for: .milliseconds(220))
                }
            }
            snapshotPublishTask = nil
        }
    }

    // MARK: - Presence transport

    private func enqueuePresence(_ state: HomeIslandRemotePlayerState) {
        guard hasStarted, !isShuttingDown, !currentUserID.isEmpty else { return }
        pendingPresence = state
        guard presencePublishTask == nil else { return }

        presencePublishTask = Task { @MainActor in
            while !Task.isCancelled, !isShuttingDown,
                  let state = pendingPresence {
                pendingPresence = nil
                let presence = PrivateIslandTransportCodec.presence(
                    from: state,
                    participantID: currentUserID
                )
                let previous = lastPublishedPresence
                do {
                    try await realtimeClient.publishPresence(
                        presence,
                        delivery: PrivateIslandTransportCodec.delivery(
                            for: presence,
                            after: previous
                        )
                    )
                    lastPublishedPresence = presence
                    coordinatorError = nil
                } catch is CancellationError {
                    break
                } catch {
                    coordinatorError = error.localizedDescription
                }
            }
            presencePublishTask = nil
        }
    }

    // MARK: - Chat moderation

    private func report(_ message: PrivateIslandChatMessage) {
        Task { @MainActor in
            do {
                try await realtimeClient.report(
                    PrivateIslandTransportCodec.chatMessage(from: message)
                )
            } catch {
                coordinatorError = error.localizedDescription
            }
        }
    }

    private func block(_ message: PrivateIslandChatMessage) {
        Task { @MainActor in
            do {
                let isBlocked = realtimeClient.state.blockedParticipantIDs.contains(
                    message.senderID
                )
                try await realtimeClient.setBlocked(message.senderID, blocked: !isBlocked)
            } catch {
                coordinatorError = error.localizedDescription
            }
        }
    }

    // MARK: - Ordered shutdown

    private func shutDown(thenClose: Bool) {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        guestResolutionTask?.cancel()
        guestResolutionTask = nil
        pendingHostSnapshot = nil
        pendingPresence = nil

        let snapshotTask = snapshotPublishTask
        let presenceTask = presencePublishTask
        snapshotPublishTask = nil
        presencePublishTask = nil
        snapshotTask?.cancel()
        presenceTask?.cancel()

        // Leaving the 3D world is a UI transition and must never wait for a
        // Firestore acknowledgement. In particular, an offline client can
        // otherwise remain trapped on the departed scene indefinitely.
        if thenClose { onClose() }

        Task { @MainActor in
            // Waiting for any already-started Firestore operation prevents a
            // cancelled presence write from recreating the document after the
            // final deletion.
            await snapshotTask?.value
            await presenceTask?.value
            await realtimeClient.stop()
            islandService.stopIslandListeners()
        }
    }
}
