import SwiftUI
import SwiftData
import SceneKit

private enum HomeIslandAssetCategory: String, CaseIterable, Identifiable {
    case all
    case nature
    case structures
    case decor
    case paths
    case furniture

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .nature: "Nature"
        case .structures: "Structures"
        case .decor: "Decor"
        case .paths: "Paths"
        case .furniture: "Furniture"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2.fill"
        case .nature: "leaf.fill"
        case .structures: "house.fill"
        case .decor: "sparkles"
        case .paths: "point.topleft.down.to.point.bottomright.curvepath"
        case .furniture: "chair.fill"
        }
    }

    func contains(_ assetID: String) -> Bool {
        switch self {
        case .all:
            true
        case .nature:
            ["small_tree", "small_stump", "small_rock", "small_lake", "coastal_rocks",
             "dune_grass_patch"]
                .contains(assetID)
        case .structures:
            ["weathered_cottage", "small_lighthouse", "weathered_lighthouse",
             "stone_well", "cliff_lookout", "mossy_ruins",
             "navigator_tent"]
                .contains(assetID)
        case .decor:
            ["weathered_crate", "campfire_circle", "voyage_flagpole",
             "harbor_lantern_post", "weathered_anchor", "net_drying_rack",
             "voyage_signal_bell", "supply_barrels"]
                .contains(assetID)
        case .paths:
            ["stone_path_straight", "stone_path_curve", "stone_path_fork",
             "compass_rose_inlay"]
                .contains(assetID)
        case .furniture:
            ["wooden_desk", "wooden_chair", "driftwood_bench", "navigator_hammock"]
                .contains(assetID)
        }
    }
}

/// Network-neutral inputs for showing a Home Island as a private multiplayer
/// session. The parent coordinator keeps ownership of Firestore listeners and
/// supplies their latest value snapshots here, so this view never starts a
/// duplicate room, presence or chat listener.
struct HomeIslandMultiplayerSession {
    enum Role: Equatable {
        case host
        case guestReadOnly
    }

    let room: PrivateIslandRoom
    let snapshot: HomeIslandSnapshot?
    let presences: [PrivateIslandPresence]
    let currentUserID: String
    let role: Role
    let messages: [PrivateIslandChatMessage]
    let isChatConnected: Bool
    let unreadChatCount: Int
    let onLocalPlayerStateChanged: (HomeIslandRemotePlayerState) -> Void
    let onHostSnapshotChanged: ((HomeIslandSnapshot) -> Void)?
    let onSendChatMessage: (String) async throws -> Void
    let onReportChatMessage: ((PrivateIslandChatMessage) -> Void)?
    let onBlockChatMessage: ((PrivateIslandChatMessage) -> Void)?

    init(
        room: PrivateIslandRoom,
        snapshot: HomeIslandSnapshot?,
        presences: [PrivateIslandPresence],
        currentUserID: String,
        role: Role,
        messages: [PrivateIslandChatMessage] = [],
        isChatConnected: Bool = true,
        unreadChatCount: Int = 0,
        onLocalPlayerStateChanged: @escaping (HomeIslandRemotePlayerState) -> Void,
        onHostSnapshotChanged: ((HomeIslandSnapshot) -> Void)? = nil,
        onSendChatMessage: @escaping (String) async throws -> Void,
        onReportChatMessage: ((PrivateIslandChatMessage) -> Void)? = nil,
        onBlockChatMessage: ((PrivateIslandChatMessage) -> Void)? = nil
    ) {
        self.room = room
        self.snapshot = snapshot
        self.presences = presences
        self.currentUserID = currentUserID
        self.role = role
        self.messages = messages
        self.isChatConnected = isChatConnected
        self.unreadChatCount = unreadChatCount
        self.onLocalPlayerStateChanged = onLocalPlayerStateChanged
        self.onHostSnapshotChanged = onHostSnapshotChanged
        self.onSendChatMessage = onSendChatMessage
        self.onReportChatMessage = onReportChatMessage
        self.onBlockChatMessage = onBlockChatMessage
    }

    /// Treat a mismatched host claim as read-only as a final UI/model boundary.
    /// Firestore remains authoritative, but a wiring error must not expose the
    /// editor against another sailor's snapshot even for a single frame.
    var isReadOnly: Bool {
        role == .guestReadOnly || currentUserID != room.hostUid
    }

    var isHost: Bool { !isReadOnly }
}

/// Resolves the current local/Firebase owner before creating an owner-scoped store.
struct HomeIslandEntryView: View {
    @EnvironmentObject private var auth: AuthService
    @Query private var sessions: [StudySession]

    var body: some View {
        HomeIslandView(
            ownerID: auth.homeIslandOwnerID,
            levelProgress: PlayerLevelProgress(sessions: sessions)
        )
            .id(auth.homeIslandOwnerID)
    }
}

struct HomeIslandView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \StudySession.date) private var studySessions: [StudySession]
    @ObservedObject private var homeMusic = HomeBackgroundMusic.shared
    @StateObject private var store: HomeIslandStore
    @State private var placementAssetID: String?
    @State private var movingSelection = false
    @State private var showingSizeControls = false
    @State private var showingSelectionActions = false
    @State private var lockedAssetID: String?
    @State private var cameraResetToken = 0
    @State private var cameraRequest: HomeIslandCameraRequest?
    @State private var captureRequest: HomeIslandCaptureRequest?
    @State private var cameraExposureOffset: Float = 0.18
    @State private var showingCameraExposureControl = false
    @State private var boatBoardingRequest: HomeIslandBoatBoardingRequest?
    @State private var mode: HomeIslandMode = .arrival
    @State private var walkInput = HomeIslandWalkInput.zero
    @State private var showingLogbook = false
    @State private var activeInterior: HomeIslandInteriorKind?
    @State private var lastOutdoorPlayerState: HomeIslandRemotePlayerState?
    @State private var isCapturing = false
    @State private var islandShareImage: WrappedCardImage?
    @State private var islandShareCardImage: WrappedCardImage?
    @State private var photoSaveState = HomeIslandPhotoSaveState.idle
    @State private var activePhotoSaveRequestID: UUID?
    @State private var showingIslandShare = false
    @State private var showingCaptureError = false
    @State private var selectedAssetCategory = HomeIslandAssetCategory.all
    @State private var transientNotice: String?
    @State private var isDismissingAfterDeparture = false
    @State private var isNavigatorOnArrivalJetty = false
    @State private var showingBoatCustomization = false
    @State private var selectedBoatSailID = BoatCustomization.selectedSailID
    @State private var showingTodoList = false
    @State private var todoItems = HomeIslandTodoPersistence.load()
    @State private var showingPlayerStats = false
    @State private var showingMusicPicker = false
    @State private var showingSettings = false
    @State private var showingHarborPanel = false
    @State private var privateChatExpanded = false
    @State private var privateChatInputFocused = false
    @AppStorage(PlayerProfile.nameKey) private var playerName = ""
    @AppStorage(PlayerProfile.styleKey) private var playerStyleToken = TileStyle.midnight.rawValue
    @AppStorage(PlayerProfile.symbolKey) private var playerSymbolToken = TileSymbol.phoenix.rawValue
    @AppStorage(HomeBackgroundMusic.enabledKey) private var homeMusicEnabled = false
    @AppStorage(HomeBackgroundMusic.selectedTrackKey)
    private var homeMusicTrack = HomeVoyageSound.harborMinuet.rawValue

    private let assets = HomeIslandAssetCatalog.available()
    private let levelProgress: PlayerLevelProgress
    private let startsMooredAtIsland: Bool
    private let boatTapOpensSelection: Bool
    private let externalBoatBoardingRequest: HomeIslandBoatBoardingRequest?
    private let noticeBoardRequestID: UUID?
    private let onBoatSelected: () -> Void
    private let onEmbeddedDepartureCompleted: (() -> Void)?
    private let onEmbeddedBoardingRejected: () -> Void
    private let multiplayerSession: HomeIslandMultiplayerSession?
    private let onPrivateIslandSelected: (PrivateIslandRoom) -> Void

    init(
        ownerID: String,
        levelProgress: PlayerLevelProgress,
        startsMooredAtIsland: Bool = false,
        boatTapOpensSelection: Bool = false,
        boardingRequest: HomeIslandBoatBoardingRequest? = nil,
        noticeBoardRequestID: UUID? = nil,
        onBoatSelected: @escaping () -> Void = {},
        onDepartureCompleted: (() -> Void)? = nil,
        onBoardingRejected: @escaping () -> Void = {},
        multiplayerSession: HomeIslandMultiplayerSession? = nil,
        onPrivateIslandSelected: @escaping (PrivateIslandRoom) -> Void = { _ in }
    ) {
        self.levelProgress = levelProgress
        self.startsMooredAtIsland = startsMooredAtIsland
        self.boatTapOpensSelection = boatTapOpensSelection
        externalBoatBoardingRequest = boardingRequest
        self.noticeBoardRequestID = noticeBoardRequestID
        self.onBoatSelected = onBoatSelected
        onEmbeddedDepartureCompleted = onDepartureCompleted
        onEmbeddedBoardingRejected = onBoardingRejected
        self.multiplayerSession = multiplayerSession
        self.onPrivateIslandSelected = onPrivateIslandSelected
        let readOnly = multiplayerSession?.isReadOnly == true
        _store = StateObject(
            wrappedValue: HomeIslandStore(
                ownerID: readOnly ? (multiplayerSession?.room.hostUid ?? ownerID) : ownerID,
                snapshot: readOnly ? multiplayerSession?.snapshot : nil,
                readOnly: readOnly
            )
        )
        _mode = State(initialValue: startsMooredAtIsland ? .explore : .arrival)
    }

    var body: some View {
        ZStack {
            // Keep the daylight sky outside SceneKit's HDR tone mapper. The
            // voyage home uses the same composition; rendering this color as
            // an SCNScene background made My Island noticeably darker even
            // though both cameras used the same exposure.
            Color(uiColor: UIColor(rgb: 0x8BCFDB))
                .ignoresSafeArea()

            HomeIslandSceneView(
                store: store,
                placementAssetID: $placementAssetID,
                movingSelection: movingSelection,
                playerLevel: levelProgress.level,
                cameraResetToken: cameraResetToken,
                cameraRequest: cameraRequest,
                captureRequest: captureRequest,
                boatBoardingRequest: externalBoatBoardingRequest ?? boatBoardingRequest,
                mode: mode,
                cameraExposureOffset: cameraExposureOffset,
                cameraInteractionLocked: isCapturing
                    || showingHarborPanel
                    || privateChatInputFocused,
                walkInput: showingBoatCustomization
                    || showingHarborPanel
                    || privateChatInputFocused
                    ? .zero
                    : walkInput,
                onMoveCompleted: { movingSelection = false },
                onPlacementCompleted: { _ in
                    placementAssetID = nil
                    movingSelection = false
                    showingSizeControls = true
                },
                onPlacementRejected: {
                    showTransientNotice(String(localized: "That space is occupied"))
                },
                onAssetActivated: { assetID in
                    if assetID == "fixed_notice_board" {
                        openVoyageNoticeBoard()
                        return
                    }
                    if let interior = HomeIslandInteriorKind(assetID: assetID) {
                        walkInput = .zero
                        activeInterior = interior
                        Haptics.tap(.medium)
                        return
                    }
                    guard assetID == "campfire_circle" else { return }
                    showingLogbook = true
                    Haptics.tap(.medium)
                },
                onAssetInteractionDenied: { assetID in
                    let notice = String(localized: "Move closer to interact")
                    showTransientNotice(notice)
                    UIAccessibility.post(notification: .announcement, argument: notice)
                    if assetID == "home_boat", startsMooredAtIsland {
                        onEmbeddedBoardingRejected()
                    }
                },
                onArrivalCompleted: {
                    guard mode == .arrival else { return }
                    withAnimation(.easeOut(duration: 0.28)) {
                        mode = .explore
                    }
                    Haptics.tap(.medium)
                },
                onJettyPresenceChanged: { isOnJetty in
                    withAnimation(.easeOut(duration: 0.18)) {
                        isNavigatorOnArrivalJetty = isOnJetty
                    }
                },
                onBoatBoardingStarted: {
                    beginDeparture()
                },
                onDepartureCompleted: {
                    finishDeparture()
                },
                onCaptured: { requestID, image in
                    finishCapture(requestID: requestID, image: image)
                },
                startsMooredAtIsland: startsMooredAtIsland,
                locksMooredOverview: false,
                boatTapOpensSelection: boatTapOpensSelection,
                boatCustomizationActive: showingBoatCustomization,
                boatAppearanceID: selectedBoatSailID,
                onBoatSelected: onBoatSelected,
                remotePlayers: multiplayerRemotePlayers,
                localPlayerID: multiplayerSession?.currentUserID,
                onLocalPlayerStateChanged: { state in
                    lastOutdoorPlayerState = state
                    multiplayerSession?.onLocalPlayerStateChanged(state)
                }
            )
            .ignoresSafeArea()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Photo composition"))
            .accessibilityHidden(mode != .camera)
            .accessibilityActions {
                if mode == .camera {
                    Button("Move camera forward") {
                        sendCameraAction(.moveForward)
                    }
                    Button("Move camera backward") {
                        sendCameraAction(.moveBackward)
                    }
                    Button("Move camera left") {
                        sendCameraAction(.moveLeft)
                    }
                    Button("Move camera right") {
                        sendCameraAction(.moveRight)
                    }
                    Button("Zoom in") {
                        sendCameraAction(.zoomIn)
                    }
                    Button("Zoom out") {
                        sendCameraAction(.zoomOut)
                    }
                    Button("Reset view") {
                        sendCameraAction(.reset)
                    }
                }
            }

            if showingBoatCustomization {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }

            if mode == .explore,
               !showingBoatCustomization,
               !showingHarborPanel {
                HomeIslandClockHUD()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .safeAreaPadding(.leading, 16)
                    .safeAreaPadding(.bottom, homeIslandClockBottomPadding)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if mode == .explore,
               !showingBoatCustomization,
               !showingHarborPanel,
               !privateChatExpanded,
               homeMusic.isPlaying {
                HomeIslandNowPlayingBar(music: homeMusic)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .safeAreaPadding(.trailing, 16)
                    .safeAreaPadding(.bottom, multiplayerSession == nil ? 18 : 78)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if let multiplayerSession,
               mode == .explore,
               !showingBoatCustomization,
               !showingHarborPanel {
                PrivateIslandChatDock(
                    islandName: multiplayerSession.room.name,
                    messages: multiplayerSession.messages,
                    currentUserID: multiplayerSession.currentUserID,
                    isConnected: multiplayerSession.isChatConnected,
                    unreadCount: multiplayerSession.unreadChatCount,
                    onSend: multiplayerSession.onSendChatMessage,
                    onReport: multiplayerSession.onReportChatMessage,
                    onBlock: multiplayerSession.onBlockChatMessage,
                    onExpandedChanged: { expanded in
                        privateChatExpanded = expanded
                    },
                    onInputFocusChanged: { focused in
                        privateChatInputFocused = focused
                        if focused { walkInput = .zero }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .zIndex(60)
            }

            if mode != .departure, !showingHarborPanel {
                VStack(spacing: 0) {
                    if mode != .camera {
                        if showingBoatCustomization {
                            boatCustomizationTopBar
                        } else {
                            topBar
                        }
                    }
                    if mode == .explore,
                       multiplayerSession?.isReadOnly != true,
                       !showingBoatCustomization {
                        voyageNoticeBoardShortcut
                            .padding(.top, 8)
                    }
                    if showingBoatCustomization {
                        EmptyView()
                    } else if mode != .camera, !store.lastSaveSucceeded {
                        saveFailureHint
                            .padding(.top, 10)
                    } else if mode == .arrival {
                        arrivalStatus
                            .padding(.top, 12)
                    } else if mode == .edit {
                        modeHint
                            .padding(.top, 10)
                    } else if mode != .camera, let transientNotice {
                        noticePill(symbol: "figure.walk", text: transientNotice)
                            .padding(.top, 10)
                    } else if mode == .explore, isNavigatorOnArrivalJetty {
                        noticePill(
                            symbol: "sailboat.fill",
                            text: String(
                                localized: boatTapOpensSelection
                                    ? "Tap the ship to choose a work item"
                                    : "Walk to the boat and tap it to return home"
                            )
                        )
                        .padding(.top, 10)
                    }

                    Spacer(minLength: mode == .edit || mode == .camera ? 72 : 24)

                    if mode == .explore {
                        if showingBoatCustomization {
                            boatCustomizationDock
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    } else if mode == .edit {
                        if store.selectedPlacement != nil, placementAssetID == nil {
                            VStack(spacing: 8) {
                                if showingSizeControls {
                                    sizeControls
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                                selectionToolDock
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            assetShelf
                        }
                    } else if mode == .camera {
                        cameraCaptureControls
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .transition(.opacity)
            }

            // Keep Settings in the island's existing view hierarchy. Simulator's
            // Save Screen can otherwise select a stale UIKit presentation surface
            // after a sheet/full-screen cover has visually disappeared.
            if showingSettings {
                SettingsView(onClose: {
                    withAnimation(.easeOut(duration: 0.18)) {
                        showingSettings = false
                    }
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .zIndex(100)
            }

            if showingHarborPanel {
                HomeIslandHarborPanel(
                    onPrivateIslandSelected: onPrivateIslandSelected,
                    onClose: {
                        withAnimation(.easeOut(duration: 0.18)) {
                            showingHarborPanel = false
                        }
                        walkInput = .zero
                        Haptics.tap(.light)
                    }
                )
                // Never animate layout/position: Geometry and safe-area values can
                // settle on the next frame. A pure fade keeps the panel anchored.
                .transition(.opacity)
                .transaction { transaction in
                    transaction.animation = nil
                }
                .zIndex(110)
            }
        }
        .preferredColorScheme(.dark)
        // When the island is the app home, hiding the status bar briefly makes
        // SwiftUI report a zero top safe area after leaving camera mode. Keep
        // the home status region stable; standalone island photography keeps
        // the original full-screen treatment.
        .statusBarHidden(mode == .camera && !startsMooredAtIsland)
        .interactiveDismissDisabled()
        .animation(.easeOut(duration: 0.18), value: store.selectedID)
        .animation(.easeOut(duration: 0.18), value: placementAssetID)
        .animation(.easeOut(duration: 0.22), value: mode)
        .animation(.easeOut(duration: 0.22), value: showingBoatCustomization)
        .onChange(of: placementAssetID) { _, value in
            if value != nil {
                movingSelection = false
                showingSizeControls = false
            }
        }
        .onChange(of: store.selectedID) { _, value in
            guard value != nil else {
                showingSizeControls = false
                return
            }
            guard placementAssetID != nil else { return }
            placementAssetID = nil
            movingSelection = false
            showingSizeControls = true
        }
        .onChange(of: store.placements) { _, _ in
            if multiplayerSession?.isHost == true {
                multiplayerSession?.onHostSnapshotChanged?(store.snapshot)
            }
            guard let placementAssetID,
                  !store.canAdd(assetID: placementAssetID)
            else { return }
            self.placementAssetID = nil
        }
        .onChange(of: multiplayerSession?.snapshot) { _, snapshot in
            replaceGuestSnapshot(snapshot)
        }
        .onChange(of: multiplayerSession?.room.id) { _, _ in
            replaceGuestSnapshot(multiplayerSession?.snapshot)
        }
        .onChange(of: mode) { _, value in
            if value != .explore { walkInput = .zero }
        }
        .onChange(of: noticeBoardRequestID) { _, requestID in
            guard requestID != nil else { return }
            walkInput = .zero
            withAnimation(.easeOut(duration: 0.20)) {
                showingHarborPanel = true
            }
        }
        .onChange(of: selectedAssetCategory) { _, _ in
            placementAssetID = nil
            lockedAssetID = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, !store.lastSaveSucceeded {
                store.save()
            }
        }
        .fullScreenCover(isPresented: $showingLogbook) {
            LogbookView()
                .presentationBackground(.clear)
        }
        .fullScreenCover(item: $activeInterior, onDismiss: {
            walkInput = .zero
            publishInteriorPresence(scene: "island")
        }) { interior in
            HomeIslandInteriorView(kind: interior)
                .presentationBackground(.black)
                .onAppear {
                    publishInteriorPresence(scene: "interior:\(interior.rawValue)")
                }
        }
        .sheet(isPresented: adaptivePresentation($showingTodoList, onPad: false)) {
            HomeIslandTodoListView(items: $todoItems)
                .presentationDetents(homeUtilitySheetDetents)
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .fullScreenCover(isPresented: adaptivePresentation($showingTodoList, onPad: true)) {
            HomeIslandTodoListView(items: $todoItems)
        }
        .sheet(isPresented: adaptivePresentation($showingPlayerStats, onPad: false)) {
            HomeIslandPlayerStatsView(sessions: studySessions)
                .presentationDetents(homeUtilitySheetDetents)
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .fullScreenCover(isPresented: adaptivePresentation($showingPlayerStats, onPad: true)) {
            HomeIslandPlayerStatsView(sessions: studySessions)
        }
        .sheet(isPresented: adaptivePresentation($showingMusicPicker, onPad: false)) {
            HomeIslandMusicPanel(
                isEnabled: $homeMusicEnabled,
                selectedTrackID: $homeMusicTrack,
                music: homeMusic
            )
            .presentationDetents(homeUtilitySheetDetents)
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .fullScreenCover(isPresented: adaptivePresentation($showingMusicPicker, onPad: true)) {
            HomeIslandMusicPanel(
                isEnabled: $homeMusicEnabled,
                selectedTrackID: $homeMusicTrack,
                music: homeMusic
            )
        }
        .fullScreenCover(isPresented: $showingIslandShare) {
            if let islandShareImage {
                HomeIslandShareSheet(
                    photo: islandShareImage,
                    shareCard: islandShareCardImage,
                    saveState: photoSaveState,
                    onRetake: {
                        showingIslandShare = false
                        Haptics.tap(.light)
                    },
                    onClose: {
                        showingIslandShare = false
                        exitCameraMode()
                    }
                )
                .presentationBackground(.black)
            }
        }
        .alert("Could not create the photo", isPresented: $showingCaptureError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
        .confirmationDialog(
            "More actions",
            isPresented: $showingSelectionActions,
            titleVisibility: .visible
        ) {
            Button("Duplicate") {
                duplicateSelection()
            }
            .disabled(!canDuplicateSelection)

            Button("Remove", role: .destructive) {
                store.deleteSelected()
                movingSelection = false
                showingSizeControls = false
            }

            Button("Cancel", role: .cancel) {}
        }
    }

    private var topBar: some View {
        HStack(spacing: compactTopHUD ? 4 : 8) {
            Button {
                walkInput = .zero
                showingPlayerStats = true
                Haptics.tap(.light)
            } label: {
                playerCardHUD
            }
            .buttonStyle(LFPressableButtonStyle())
            .contentShape(Capsule())
            .accessibilityHint(Text("Shows your work history"))
                .layoutPriority(1)

            Spacer(minLength: compactTopHUD ? 0 : 4)

            if mode == .explore {
                HStack(spacing: topControlSpacing) {
                    if canUseBoatTopControl {
                        Button {
                            if boatTapOpensSelection {
                                enterBoatCustomization()
                            } else {
                                boatBoardingRequest = HomeIslandBoatBoardingRequest()
                            }
                        } label: {
                            Image(systemName: "sailboat.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(homeGlassInk)
                                .frame(width: topControlWidth, height: 40)
                        }
                        .buttonStyle(LFPressableButtonStyle())
                        .accessibilityLabel(
                            Text(
                                boatTapOpensSelection
                                    ? "Customize boat"
                                    : "Board boat and return home"
                            )
                        )
                        .accessibilityActions {
                            if boatTapOpensSelection {
                                Button("Choose a work item and set sail") {
                                    onBoatSelected()
                                }
                            }
                        }
                    }

                    Button {
                        enterCameraMode()
                    } label: {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(homeGlassInk)
                            .frame(width: topControlWidth, height: 40)
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .accessibilityLabel(Text("Camera mode"))

                    if canEditIsland {
                        Button {
                            enterEditMode()
                        } label: {
                            Image(systemName: "hammer.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(homeGlassInk)
                                .frame(width: topControlWidth, height: 40)
                        }
                        .buttonStyle(LFPressableButtonStyle())
                        .accessibilityLabel(Text("Edit Island"))
                    }

                    Button {
                        walkInput = .zero
                        showingTodoList = true
                        Haptics.tap(.light)
                    } label: {
                        Image(systemName: "checklist")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(homeGlassInk)
                            .frame(width: topControlWidth, height: 40)
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .accessibilityLabel(Text("ToDo list"))

                    Button {
                        walkInput = .zero
                        showingMusicPicker = true
                        Haptics.tap(.light)
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "music.note")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(homeGlassInk)
                            if homeMusic.isPlaying {
                                Circle()
                                    .fill(Color(uiColor: VoyageSceneKit.returnOrange))
                                    .frame(width: 6, height: 6)
                                    .offset(x: 5, y: -5)
                            }
                        }
                        .frame(width: topControlWidth, height: 40)
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .accessibilityLabel(Text("Music"))
                    .accessibilityValue(musicAccessibilityValue)
                    .accessibilityHint(Text("Choose a track"))

                    Button {
                        walkInput = .zero
                        showingSettings = true
                        Haptics.tap(.light)
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(homeGlassInk)
                            .frame(width: topControlWidth, height: 40)
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .accessibilityLabel(Text("Settings"))
                    .accessibilityHint(Text("Change language, app icon, and account"))
                }
                .padding(3)
                .background(homeGlassBackground, in: Capsule())
                .overlay(Capsule().stroke(homeGlassInk.opacity(0.12), lineWidth: 1))
            } else if mode == .edit {
                HStack(spacing: 2) {
                    Button {
                        store.undo()
                        movingSelection = false
                        showingSizeControls = false
                        Haptics.tap(.light)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(homeGlassInk.opacity(store.canUndo ? 1 : 0.30))
                            .frame(width: 38, height: 40)
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .disabled(!store.canUndo)
                    .accessibilityLabel(Text("Undo"))

                    Button {
                        store.redo()
                        movingSelection = false
                        showingSizeControls = false
                        Haptics.tap(.light)
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(homeGlassInk.opacity(store.canRedo ? 1 : 0.30))
                            .frame(width: 34, height: 40)
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .disabled(!store.canRedo)
                    .accessibilityLabel(Text("Redo"))

                    Button {
                        cameraResetToken &+= 1
                        Haptics.tap(.light)
                    } label: {
                        Image(systemName: "view.3d")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(homeGlassInk)
                            .frame(width: 38, height: 40)
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .accessibilityLabel(Text("Reset view"))

                    Button {
                        enterExploreMode()
                    } label: {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(homeGlassInk)
                            .frame(width: 38, height: 40)
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .accessibilityLabel(Text("Explore Island"))
                }
                .padding(3)
                .background(homeGlassBackground, in: Capsule())
                .overlay(Capsule().stroke(homeGlassInk.opacity(0.12), lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, compactTopHUD ? 8 : 12)
        .safeAreaPadding(.top, 8)
    }

    private var voyageNoticeBoardShortcut: some View {
        Button(action: openVoyageNoticeBoard) {
            HStack(spacing: 9) {
                Image(systemName: "signpost.right.and.left.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(uiColor: VoyageSceneKit.returnOrange))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Voyage Notice Board")
                        .font(LFFont.copy(12))
                    Text("Public harbors · Private islands")
                        .font(LFFont.label(8))
                        .foregroundStyle(homeGlassInk.opacity(0.58))
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(homeGlassInk.opacity(0.40))
            }
            .foregroundStyle(homeGlassInk)
            .padding(.horizontal, 13)
            .frame(minHeight: 44)
            .background(homeGlassBackground, in: Capsule())
            .overlay(Capsule().stroke(homeGlassInk.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            .contentShape(Capsule())
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityHint(Text("Open public harbors and private islands"))
    }

    private func openVoyageNoticeBoard() {
        walkInput = .zero
        withAnimation(.easeOut(duration: 0.20)) {
            showingHarborPanel = true
        }
        Haptics.tap(.medium)
    }

    private var playerCardHUD: some View {
        HStack(spacing: 9) {
            PlayerAvatarArt(
                styleToken: playerStyleToken,
                symbolToken: playerSymbolToken
            )
            .frame(width: 32, height: 32)
            .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: playerDisplayName)
                    .font(LFFont.copy(14))
                    .foregroundStyle(homeGlassInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)

                Text(verbatim: "LV \(levelProgress.level)")
                    .font(LFFont.label(9))
                    .tracking(0.6)
                    .foregroundStyle(homeGlassInk.opacity(0.58))
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 7)
        .padding(.trailing, 12)
        .frame(width: playerCardWidth, height: 46)
        .background(homeGlassBackground, in: Capsule())
        .overlay(Capsule().stroke(homeGlassInk.opacity(0.12), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(playerDisplayName), Level \(levelProgress.level)"))
    }

    private var playerDisplayName: String {
        let normalized = PlayerProfile.normalizedName(playerName)
        return normalized.isEmpty ? LF.text("Sailor") : normalized
    }

    private var canEditIsland: Bool {
        !store.isReadOnly
    }

    /// A guest may still use the standalone "board and leave" control, but the
    /// embedded-home variant of this button is exclusively boat customization.
    private var canUseBoatTopControl: Bool {
        !boatTapOpensSelection || multiplayerSession?.isReadOnly != true
    }

    private var multiplayerRemotePlayers: [HomeIslandRemotePlayerState] {
        guard let multiplayerSession else { return [] }
        return multiplayerSession.presences.compactMap { presence in
            guard presence.uid != multiplayerSession.currentUserID,
                  presence.uid == multiplayerSession.room.hostUid
                    || multiplayerSession.room.memberIds.contains(presence.uid)
            else { return nil }
            return HomeIslandRemotePlayerState(
                id: presence.uid,
                x: presence.x,
                z: presence.z,
                yaw: presence.yaw,
                pose: presence.pose,
                scene: presence.scene,
                phase: presence.phase,
                seatPlacementID: presence.seatPlacementID?.uuidString.lowercased(),
                seatSlotID: presence.seatSlotID,
                arrivalNonce: presence.arrivalNonce,
                isVisible: presence.scene == "island" && presence.phase != "departure"
            )
        }
    }

    /// Interior worlds are intentionally local for now. Publishing their
    /// scene identity hides the outdoor sailor for everyone else, avoiding a
    /// ghost avatar beside the house while the player is inside. Returning to
    /// the island republishes the latest outdoor transform immediately.
    private func publishInteriorPresence(scene: String) {
        guard let multiplayerSession,
              var state = lastOutdoorPlayerState
        else { return }
        state.scene = scene
        state.isVisible = scene == "island"
        multiplayerSession.onLocalPlayerStateChanged(state)
    }

    private var compactTopHUD: Bool {
        horizontalSizeClass == .compact
    }

    /// Keep the clock visible while chat is open. On compact layouts the chat
    /// spans the screen, so lift the clock above it; iPad keeps the clock on
    /// the left and the chat dock on the right.
    private var homeIslandClockBottomPadding: CGFloat {
        guard multiplayerSession != nil else { return 16 }
        guard privateChatExpanded, horizontalSizeClass == .compact else { return 76 }
        if dynamicTypeSize.isAccessibilitySize { return 406 }
        if verticalSizeClass == .compact { return 266 }
        return 316
    }

    /// A medium detent is useful on iPhone because the island remains visible
    /// behind the utility panel. iPad uses full-screen covers below instead of
    /// UIKit's centered form sheet, which otherwise clips the beginning/end of
    /// these longer Home utilities.
    private var homeUtilitySheetDetents: Set<PresentationDetent> {
        [.medium, .large]
    }

    private var usesFullScreenHomeUtilities: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private func adaptivePresentation(
        _ source: Binding<Bool>,
        onPad: Bool
    ) -> Binding<Bool> {
        Binding(
            get: {
                source.wrappedValue && usesFullScreenHomeUtilities == onPad
            },
            set: { isPresented in
                if !isPresented { source.wrappedValue = false }
            }
        )
    }

    private var playerCardWidth: CGFloat {
        compactTopHUD ? 136 : 178
    }

    private var topControlWidth: CGFloat {
        compactTopHUD ? 34 : 40
    }

    private var topControlSpacing: CGFloat {
        compactTopHUD ? 2 : 4
    }

    private var musicAccessibilityValue: Text {
        if homeMusic.playbackFailed {
            return Text("Playback unavailable")
        }
        if homeMusic.isPlaying {
            return Text("Playing \(Text(homeMusic.currentTrack.title))")
        }
        return Text("Stopped")
    }

    private var hudBackground: Color {
        Color(uiColor: VoyageSceneKit.nightBG).opacity(0.78)
    }

    private var homeGlassBackground: Color {
        Color.white.opacity(0.82)
    }

    private var homeGlassInk: Color {
        Color(uiColor: VoyageSceneKit.nightBG)
    }

    private var boatCustomizationTopBar: some View {
        HStack(spacing: 10) {
            Label {
                Text("Your boat")
                    .font(LFFont.copy(15))
            } icon: {
                Image(systemName: "sailboat.fill")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color(uiColor: VoyageSceneKit.sand))

            Spacer(minLength: 8)

            Button {
                exitBoatCustomization()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(LFPressableButtonStyle())
            .accessibilityLabel(Text("Close boat customization"))
        }
        .padding(.leading, 15)
        .padding(.trailing, 3)
        .frame(maxWidth: 420)
        .frame(height: 50)
        .background(hudBackground, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .safeAreaPadding(.top, 8)
    }

    private var boatCustomizationDock: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("Sail color")
                    .font(LFFont.label(11))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.58))
                Spacer(minLength: 8)
                Text(BoatCustomization.selectedSail.title)
                    .font(LFFont.copy(13))
                    .foregroundStyle(Color(uiColor: VoyageSceneKit.sand))
            }

            HStack(spacing: 6) {
                ForEach(BoatCustomization.sailColors) { option in
                    boatSailColorButton(option)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 420)
        .background(
            hudBackground,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .padding(.horizontal, 12)
        .safeAreaPadding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Sail color"))
    }

    private func boatSailColorButton(_ option: SailColorOption) -> some View {
        let selected = selectedBoatSailID == option.id
        return Button {
            selectBoatSail(option)
        } label: {
            ZStack {
                Circle()
                    .fill(option.color)
                    .frame(width: 32, height: 32)
                    .shadow(
                        color: selected ? option.color.opacity(0.55) : .clear,
                        radius: selected ? 8 : 0
                    )
                if selected {
                    Circle()
                        .stroke(Color(uiColor: VoyageSceneKit.sand), lineWidth: 2.5)
                        .frame(width: 40, height: 40)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(LFColor.midnight)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(LFPressableButtonStyle(scale: 0.94))
        .accessibilityLabel(Text(option.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func enterBoatCustomization() {
        guard mode == .explore,
              !showingBoatCustomization,
              multiplayerSession?.isReadOnly != true
        else { return }
        walkInput = .zero
        selectedBoatSailID = BoatCustomization.selectedSailID
        withAnimation(.easeOut(duration: 0.22)) {
            showingBoatCustomization = true
        }
        Haptics.tap(.medium)
    }

    private func exitBoatCustomization() {
        guard showingBoatCustomization else { return }
        walkInput = .zero
        withAnimation(.easeOut(duration: 0.22)) {
            showingBoatCustomization = false
        }
        Haptics.tap(.light)
    }

    private func selectBoatSail(_ option: SailColorOption) {
        guard selectedBoatSailID != option.id else { return }
        BoatCustomization.selectSail(option.id)
        selectedBoatSailID = option.id
        Haptics.tap(.light)
        Task { await PrivateIslandService.shared.publishProfileToJoinedIslands() }
        PublicHarborService.shared.pushProfile()
    }

    private var cameraCaptureControls: some View {
        VStack(spacing: 9) {
            if showingCameraExposureControl {
                HStack(spacing: 10) {
                    Image(systemName: "sun.min")
                    Slider(value: $cameraExposureOffset, in: -1.2...0.8, step: 0.05) {
                        Text("Exposure")
                    }
                    .tint(.white)
                    .accessibilityValue(Text(String(format: "%+.1f EV", cameraExposureOffset)))
                    Image(systemName: "sun.max.fill")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 15)
                .frame(width: 250, height: 46)
                .background(.black.opacity(0.52), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.13), lineWidth: 1))
                .disabled(isCapturing)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 12) {
                cameraDockButton(
                    symbol: "xmark",
                    accessibilityLabel: "Exit camera mode"
                ) {
                    exitCameraMode()
                }
                .disabled(isCapturing)

                Button {
                    captureIsland()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.96), lineWidth: 4)
                            .frame(width: 74, height: 74)
                        Circle()
                            .fill(.white.opacity(isCapturing ? 0.42 : 0.98))
                            .frame(width: isCapturing ? 50 : 58, height: isCapturing ? 50 : 58)
                        if isCapturing {
                            ProgressView()
                                .tint(Color(uiColor: VoyageSceneKit.seaDeep))
                        }
                    }
                    .frame(width: 82, height: 82)
                    .contentShape(Circle())
                }
                .buttonStyle(LFPressableButtonStyle())
                .disabled(isCapturing)
                .accessibilityLabel(Text(isCapturing ? "Creating photo" : "Take photo"))

                cameraDockButton(
                    symbol: "arrow.counterclockwise",
                    accessibilityLabel: "Reset view"
                ) {
                    cameraResetToken &+= 1
                    Haptics.tap(.light)
                }
                .disabled(isCapturing)

                cameraDockButton(
                    symbol: showingCameraExposureControl ? "sun.max.fill" : "sun.max",
                    accessibilityLabel: "Adjust exposure"
                ) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        showingCameraExposureControl.toggle()
                    }
                    Haptics.tap(.light)
                }
                .disabled(isCapturing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.black.opacity(0.38), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.13), lineWidth: 1))
        }
        .safeAreaPadding(.bottom, 14)
    }

    private func cameraDockButton(
        symbol: String,
        accessibilityLabel: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.black.opacity(0.46), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var arrivalStatus: some View {
        HStack(spacing: 9) {
            ProgressView()
                .tint(Color(uiColor: VoyageSceneKit.sand))
            Text(verbatim: LF.format("Approaching %@…", PlayerProfile.islandName))
                .font(LFFont.label(12))
                .foregroundStyle(.white.opacity(0.84))
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(.black.opacity(0.42), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.13), lineWidth: 1))
        .allowsHitTesting(false)
    }

    private var saveFailureHint: some View {
        hintPill(
            symbol: "exclamationmark.triangle.fill",
            text: String(localized: "Island changes could not be saved"),
            actionTitle: String(localized: "Retry")
        ) {
            store.save()
            Haptics.tap(.medium)
        }
    }

    private func noticePill(symbol: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(homeGlassInk)
            Text(verbatim: text)
                .font(LFFont.label(12))
                .foregroundStyle(homeGlassInk)
        }
        .padding(.horizontal, 13)
        .frame(height: 36)
        .background(homeGlassBackground, in: Capsule())
        .overlay(Capsule().stroke(homeGlassInk.opacity(0.12), lineWidth: 1))
        .allowsHitTesting(false)
    }

    private func showTransientNotice(_ notice: String) {
        transientNotice = notice
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            if transientNotice == notice { transientNotice = nil }
        }
    }

    private func replaceGuestSnapshot(_ snapshot: HomeIslandSnapshot?) {
        guard let multiplayerSession,
              multiplayerSession.isReadOnly,
              store.isReadOnly
        else { return }
        let resolvedSnapshot = snapshot ?? HomeIslandSnapshot(
            ownerKey: "private-island:\(multiplayerSession.room.code)",
            updatedAt: .distantPast,
            placements: []
        )
        placementAssetID = nil
        movingSelection = false
        showingSizeControls = false
        showingSelectionActions = false
        lockedAssetID = nil
        showingBoatCustomization = false
        store.replaceRemoteSnapshot(resolvedSnapshot)
    }

    private func beginDeparture() {
        guard mode == .explore else { return }
        showingBoatCustomization = false
        placementAssetID = nil
        movingSelection = false
        showingSizeControls = false
        lockedAssetID = nil
        transientNotice = nil
        store.select(nil)
        walkInput = .zero
        withAnimation(.easeOut(duration: 0.28)) {
            mode = .departure
        }
        // SceneKit actions can pause if the app backgrounds mid-voyage. Never
        // leave the player trapped on a HUD-less departure screen.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(9))
            guard mode == .departure else { return }
            finishDeparture()
        }
    }

    private func finishDeparture() {
        guard mode == .departure, !isDismissingAfterDeparture else { return }
        isDismissingAfterDeparture = true
        if let onEmbeddedDepartureCompleted {
            onEmbeddedDepartureCompleted()
        } else {
            dismiss()
        }
    }

    private func enterEditMode() {
        guard canEditIsland else { return }
        showingBoatCustomization = false
        walkInput = .zero
        withAnimation(.easeOut(duration: 0.22)) {
            mode = .edit
        }
        Haptics.tap(.light)
    }

    private func enterCameraMode() {
        showingBoatCustomization = false
        isCapturing = false
        captureRequest = nil
        cameraExposureOffset = 0.18
        showingCameraExposureControl = false
        placementAssetID = nil
        movingSelection = false
        showingSizeControls = false
        lockedAssetID = nil
        store.select(nil)
        walkInput = .zero
        transientNotice = nil
        islandShareImage = nil
        islandShareCardImage = nil
        photoSaveState = .idle
        activePhotoSaveRequestID = nil
        withAnimation(.easeOut(duration: 0.22)) {
            mode = .camera
        }
        Haptics.tap(.light)
    }

    private func exitCameraMode() {
        isCapturing = false
        captureRequest = nil
        showingCameraExposureControl = false
        withAnimation(.easeOut(duration: 0.22)) {
            mode = .explore
        }
        Haptics.tap(.light)
    }

    private func captureIsland() {
        guard mode == .camera, !isCapturing else { return }
        let request = HomeIslandCaptureRequest()
        isCapturing = true
        captureRequest = request
        Haptics.tap(.medium)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard mode == .camera,
                  isCapturing,
                  captureRequest?.id == request.id
            else { return }
            isCapturing = false
            captureRequest = nil
            showingCaptureError = true
        }
    }

    private func sendCameraAction(_ action: HomeIslandCameraAction) {
        guard mode == .camera, !isCapturing else { return }
        cameraRequest = HomeIslandCameraRequest(action: action)
        Haptics.tap(.light)
    }

    @MainActor
    private func finishCapture(requestID: UUID, image: UIImage) {
        guard mode == .camera,
              isCapturing,
              captureRequest?.id == requestID
        else { return }
        isCapturing = false
        captureRequest = nil
        let capturedAt = Date()
        guard let rendered = HomeIslandPhotoExport.render(
            sceneImage: image,
            capturedAt: capturedAt
        ) else {
            showingCaptureError = true
            return
        }
        let card = UIImage(data: rendered.data).flatMap { photo in
            WrappedShare.render(
                card: HomeIslandShareCard(sceneImage: photo, capturedAt: capturedAt),
                fileName: HomeIslandShareCard.fileName(for: capturedAt)
            )
        }
        islandShareImage = rendered
        islandShareCardImage = card
        photoSaveState = .saving
        activePhotoSaveRequestID = requestID
        showingIslandShare = true
        Haptics.success()

        Task { @MainActor in
            let didSave = await HomeIslandPhotoLibrary.save(rendered)
            guard activePhotoSaveRequestID == requestID else { return }
            photoSaveState = didSave ? .saved : .failed
            let announcement = String(localized: didSave ? "Photo saved" : "Photo could not be saved")
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
    }

    private func enterExploreMode() {
        showingBoatCustomization = false
        placementAssetID = nil
        movingSelection = false
        showingSizeControls = false
        lockedAssetID = nil
        store.select(nil)
        withAnimation(.easeOut(duration: 0.22)) {
            mode = .explore
        }
        Haptics.tap(.light)
    }

    @ViewBuilder
    private var modeHint: some View {
        if let transientNotice {
            hintPill(
                symbol: "exclamationmark.circle.fill",
                text: transientNotice,
                actionTitle: String(localized: "OK")
            ) {
                self.transientNotice = nil
            }
        } else if let lockedAssetID,
           let asset = HomeIslandAssetCatalog.asset(id: lockedAssetID) {
            let placedCount = store.placementCount(assetID: asset.id)
            let placementLimit = HomeIslandAssetCatalog.placementLimit(for: asset.id)
            let unlocked = HomeIslandAssetCatalog.isUnlocked(
                asset,
                playerLevel: levelProgress.level
            )
            hintPill(
                symbol: unlocked ? "exclamationmark.circle.fill" : "lock.fill",
                text: !unlocked
                    ? LF.format("Unlocks at Level %lld", Int64(asset.unlockLevel))
                    : placedCount >= placementLimit
                    ? LF.format("Placement limit reached · %lld/%lld", Int64(placedCount), Int64(placementLimit))
                    : String(localized: "The island has reached its object limit"),
                actionTitle: String(localized: "OK")
            ) {
                self.lockedAssetID = nil
            }
        } else if let placementAssetID,
           let asset = HomeIslandAssetCatalog.asset(id: placementAssetID) {
            hintPill(
                symbol: placementAssetID == "wooden_jetty" ? "water.waves" : "hand.tap.fill",
                text: placementAssetID == "wooden_jetty"
                    ? String(localized: "Tap the island edge to extend the jetty toward the sea")
                    : LF.format("Tap once on the sand to place %@", asset.title),
                actionTitle: String(localized: "Cancel")
            ) {
                self.placementAssetID = nil
            }
        } else if movingSelection {
            hintPill(
                symbol: "arrow.up.and.down.and.arrow.left.and.right",
                text: String(localized: "Drag the selected asset freely across the island"),
                actionTitle: String(localized: "Cancel")
            ) {
                movingSelection = false
            }
        }
    }

    private func hintPill(
        symbol: String,
        text: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(Color(uiColor: VoyageSceneKit.sand))
            Text(verbatim: text)
                .font(LFFont.label(12))
                .foregroundStyle(.white)
                .lineLimit(1)
            Button(actionTitle, action: action)
                .font(LFFont.label(12))
                .foregroundStyle(Color(uiColor: VoyageSceneKit.sand))
        }
        .padding(.horizontal, 13)
        .frame(height: 38)
        .background(.black.opacity(0.50), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
    }

    @ViewBuilder
    private var selectionToolDock: some View {
        if let selected = store.selectedPlacement,
           let asset = HomeIslandAssetCatalog.asset(id: selected.assetID) {
            HStack(spacing: 8) {
                HomeIslandAssetThumbnail(
                    assetID: asset.id,
                    fallbackSymbol: asset.symbolName
                )
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))

                Text(verbatim: asset.title)
                    .font(LFFont.copy(12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: 48, alignment: .leading)

                toolButton(
                    "Move",
                    symbol: "arrow.up.and.down.and.arrow.left.and.right",
                    active: movingSelection
                ) {
                    showingSizeControls = false
                    movingSelection = true
                }
                toolButton("Rotate", symbol: "rotate.right") {
                    store.rotateSelected()
                }
                .disabled(selected.assetID == "wooden_jetty")
                .opacity(selected.assetID == "wooden_jetty" ? 0.34 : 1)
                toolButton(
                    "Size",
                    symbol: "arrow.up.left.and.arrow.down.right",
                    active: showingSizeControls
                ) {
                    movingSelection = false
                    showingSizeControls.toggle()
                }

                Button {
                    movingSelection = false
                    showingSelectionActions = true
                    Haptics.tap(.light)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 34, height: 50)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(LFPressableButtonStyle())
                .accessibilityLabel(Text("More actions"))

                Button {
                    store.select(nil)
                    movingSelection = false
                    showingSizeControls = false
                    Haptics.tap(.light)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.62))
                        .frame(width: 32, height: 50)
                }
                .buttonStyle(LFPressableButtonStyle())
                .accessibilityLabel(Text("Clear selection"))
            }
            .padding(7)
            .background(hudBackground, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(Color(uiColor: VoyageSceneKit.sand).opacity(0.17), lineWidth: 1)
            }
        }
    }

    private func toolButton(
        _ title: LocalizedStringKey,
        symbol: String,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            Haptics.tap(.light)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(LFFont.label(8))
                    .lineLimit(1)
            }
            .foregroundStyle(active ? Color(uiColor: VoyageSceneKit.sand) : .white.opacity(0.86))
            .frame(width: 44, height: 50)
            .background(
                active
                    ? Color(uiColor: VoyageSceneKit.ember).opacity(0.24)
                    : .white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(LFPressableButtonStyle())
    }

    private var canDuplicateSelection: Bool {
        guard let selected = store.selectedPlacement,
              store.canAdd(assetID: selected.assetID),
              let asset = HomeIslandAssetCatalog.asset(id: selected.assetID)
        else { return false }
        return HomeIslandAssetCatalog.isUnlocked(asset, playerLevel: levelProgress.level)
    }

    private func duplicateSelection() {
        if store.duplicateSelected(playerLevel: levelProgress.level) == nil {
            Haptics.error()
        } else {
            Haptics.tap(.light)
        }
        showingSizeControls = false
    }

    @ViewBuilder
    private var sizeControls: some View {
        if let selected = store.selectedPlacement {
            HStack(spacing: 12) {
                Button {
                    if store.resizeSelected(by: -0.10) {
                        Haptics.tap(.light)
                    } else {
                        Haptics.error()
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 42, height: 38)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(LFPressableButtonStyle())
                .disabled(selected.transform.scale <= 0.25)
                .accessibilityLabel(Text("Smaller"))

                VStack(spacing: 1) {
                    Text("Size")
                        .font(LFFont.label(10))
                        .foregroundStyle(.white.opacity(0.55))
                    Text(
                        verbatim: "\(calibrationScalePercent(for: selected))%"
                    )
                        .font(LFFont.copy(15))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)

                Button {
                    if store.resizeSelected(by: 0.10) {
                        Haptics.tap(.light)
                    } else {
                        Haptics.error()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 42, height: 38)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(LFPressableButtonStyle())
                .disabled(selected.transform.scale >= 2)
                .accessibilityLabel(Text("Larger"))
            }
            .foregroundStyle(.white)
            .padding(6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
        }
    }

    private var assetShelf: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Build", systemImage: "hammer.fill")
                    .font(LFFont.copy(13))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text(
                    verbatim: "\(assets.filter { HomeIslandAssetCatalog.isUnlocked($0, playerLevel: levelProgress.level) }.count)/\(assets.count)"
                )
                .font(LFFont.label(9))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.38))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(HomeIslandAssetCategory.allCases) { category in
                        categoryButton(category)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(visibleAssets) { asset in
                        assetButton(asset)
                    }
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 10)
        .padding(.bottom, 7)
        .background(
            LinearGradient(
                colors: [
                    Color(uiColor: VoyageSceneKit.nightBG).opacity(0.94),
                    Color(uiColor: VoyageSceneKit.seaDeep).opacity(0.91)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.13))
                .frame(height: 1)
        }
        .safeAreaPadding(.bottom, 3)
    }

    private func assetButton(_ asset: HomeIslandAsset) -> some View {
        let selected = placementAssetID == asset.id
        let unlocked = HomeIslandAssetCatalog.isUnlocked(
            asset,
            playerLevel: levelProgress.level
        )
        let placedCount = store.placementCount(assetID: asset.id)
        let placementLimit = HomeIslandAssetCatalog.placementLimit(for: asset.id)
        let atLimit = placedCount >= placementLimit
        let canPlace = unlocked && !atLimit && store.canAdd
        return Button {
            if canPlace {
                lockedAssetID = nil
                placementAssetID = selected ? nil : asset.id
                store.select(nil)
                Haptics.tap(.light)
            } else {
                placementAssetID = nil
                movingSelection = false
                lockedAssetID = asset.id
                Haptics.tap(.medium)
            }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .bottomTrailing) {
                    HomeIslandAssetThumbnail(
                        assetID: asset.id,
                        fallbackSymbol: asset.symbolName
                    )
                        .opacity(canPlace ? 1 : 0.38)
                        .frame(width: 46, height: 46)
                        .background(.white.opacity(selected ? 0.13 : 0.055), in: RoundedRectangle(cornerRadius: 12))
                    if !unlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(uiColor: VoyageSceneKit.sand))
                            .padding(3)
                            .background(.black.opacity(0.72), in: Circle())
                            .offset(x: 3, y: 3)
                    } else if atLimit {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(uiColor: VoyageSceneKit.nightBG))
                            .padding(3)
                            .background(Color(uiColor: VoyageSceneKit.sand), in: Circle())
                            .offset(x: 3, y: 3)
                    }
                }
                Text(verbatim: asset.title)
                    .font(LFFont.label(9))
                    .foregroundStyle(.white.opacity(canPlace ? (selected ? 1 : 0.72) : 0.34))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(6)
            .frame(width: 72, height: 72)
            .background(
                selected ? Color(uiColor: VoyageSceneKit.ember).opacity(0.24) : .white.opacity(canPlace ? 0.045 : 0.018),
                in: RoundedRectangle(cornerRadius: 15)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(selected ? Color(uiColor: VoyageSceneKit.sand).opacity(0.58) : .white.opacity(0.07), lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                Text(verbatim: unlocked ? "\(placedCount)/\(placementLimit)" : "LV\(asset.unlockLevel)")
                    .font(LFFont.label(7))
                    .monospacedDigit()
                    .foregroundStyle(unlocked ? .white.opacity(0.64) : Color(uiColor: VoyageSceneKit.sand))
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(.black.opacity(0.62), in: Capsule())
                    .offset(x: 3, y: -3)
            }
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityLabel(Text(verbatim: asset.title))
        .accessibilityValue(
            Text(
                verbatim: unlocked
                    ? "\(placedCount)/\(placementLimit)"
                    : "LV\(asset.unlockLevel)"
            )
        )
        .accessibilityHint(
            atLimit
                ? Text("Placement limit reached")
                : unlocked
                ? asset.id == "wooden_jetty"
                    ? Text("Place only at the island edge; it automatically faces the sea")
                    : Text("Tap the sand to place this asset")
                : Text(verbatim: LF.format("Unlocks at Level %lld", Int64(asset.unlockLevel)))
        )
    }

    private var visibleAssets: [HomeIslandAsset] {
        assets
            .filter { selectedAssetCategory.contains($0.id) }
            .sorted { lhs, rhs in
                let lhsUnlocked = HomeIslandAssetCatalog.isUnlocked(
                    lhs,
                    playerLevel: levelProgress.level
                )
                let rhsUnlocked = HomeIslandAssetCatalog.isUnlocked(
                    rhs,
                    playerLevel: levelProgress.level
                )
                if lhsUnlocked != rhsUnlocked { return lhsUnlocked && !rhsUnlocked }
                return lhs.unlockLevel < rhs.unlockLevel
            }
    }

    private func categoryButton(_ category: HomeIslandAssetCategory) -> some View {
        let selected = selectedAssetCategory == category
        return Button {
            selectedAssetCategory = category
            Haptics.tap(.light)
        } label: {
            Label(category.title, systemImage: category.symbol)
                .font(LFFont.label(9))
                .foregroundStyle(
                    selected
                        ? Color(uiColor: VoyageSceneKit.nightBG)
                        : .white.opacity(0.68)
                )
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    selected
                        ? Color(uiColor: VoyageSceneKit.sand)
                        : .white.opacity(0.06),
                    in: Capsule()
                )
        }
        .buttonStyle(LFPressableButtonStyle())
    }

    /// Simulator-only tuning value. It is deliberately absolute so a value
    /// approved during visual QA can be copied directly into `defaultScale`.
    private func calibrationScalePercent(for placement: HomeIslandPlacement) -> Int {
        Int((placement.transform.scale * 100).rounded())
    }
}

private struct HomeIslandPlayerStatsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PlayerProfile.nameKey) private var playerName = ""
    @AppStorage(PlayerProfile.styleKey) private var styleToken = TileStyle.midnight.rawValue
    @AppStorage(PlayerProfile.symbolKey) private var symbolToken = TileSymbol.phoenix.rawValue
    @AppStorage(PlayerProfile.resolveKey) private var resolve = ""
    @State private var showingProfileEditor = false

    let sessions: [StudySession]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    playerSummary
                    metricRow
                    weeklyChart
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(panelGlass.ignoresSafeArea())
            .navigationTitle(Text("Voyage record"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(panelInk)
                }
            }
        }
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $showingProfileEditor) {
            ProfileEditorSheet()
        }
    }

    private var playerSummary: some View {
        HStack(spacing: 13) {
            PlayerAvatarArt(styleToken: styleToken, symbolToken: symbolToken)
                .frame(width: 52, height: 52)
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: displayName)
                    .font(LFFont.copy(18))
                    .foregroundStyle(panelInk)
                    .lineLimit(1)

                Text(verbatim: resolveText)
                    .font(LFFont.label(11))
                    .foregroundStyle(panelInk.opacity(resolve.isEmpty ? 0.42 : 0.66))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button {
                showingProfileEditor = true
                Haptics.tap(.light)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(panelInk)
                    .frame(width: 44, height: 44)
                    .background(panelInk.opacity(0.07), in: Circle())
            }
            .buttonStyle(LFPressableButtonStyle())
            .accessibilityLabel(Text("Edit player card"))
        }
        .padding(14)
        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(panelInk.opacity(0.11), lineWidth: 1)
        )
    }

    private var metricRow: some View {
        HStack(spacing: 10) {
            metricCard(
                title: "This week",
                value: LF.duration(minutes: weekTotalMinutes),
                symbol: "calendar"
            )
            metricCard(
                title: "Total time",
                value: LF.duration(minutes: totalMinutes),
                symbol: "hourglass"
            )
        }
    }

    private func metricCard(title: LocalizedStringKey, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(LFFont.label(10))
                .foregroundStyle(panelInk.opacity(0.50))

            Text(verbatim: value)
                .font(LFFont.number(19))
                .foregroundStyle(panelInk)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(panelInk.opacity(0.055), in: RoundedRectangle(cornerRadius: 17))
    }

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Weekly activity")
                    .font(LFFont.copy(14))
                    .foregroundStyle(panelInk)
                Spacer()
                Text(verbatim: LF.format("%lld records", Int64(weekSessionCount)))
                    .font(LFFont.label(10))
                    .foregroundStyle(panelInk.opacity(0.42))
            }

            HStack(alignment: .bottom, spacing: 7) {
                ForEach(weekDays) { day in
                    VStack(spacing: 6) {
                        Text(verbatim: day.minutes > 0 ? shortMinutes(day.minutes) : "")
                            .font(LFFont.label(8))
                            .foregroundStyle(panelInk.opacity(0.48))
                            .frame(height: 11)

                        GeometryReader { proxy in
                            VStack {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(
                                        day.isToday
                                            ? Color(uiColor: VoyageSceneKit.returnOrange)
                                            : panelInk.opacity(day.minutes > 0 ? 0.72 : 0.10)
                                    )
                                    .frame(
                                        height: max(
                                            5,
                                            proxy.size.height * CGFloat(day.minutes) / CGFloat(maxWeekdayMinutes)
                                        )
                                    )
                            }
                        }
                        .frame(height: 78)

                        Text(verbatim: day.label)
                            .font(LFFont.label(9))
                            .foregroundStyle(day.isToday ? panelInk : panelInk.opacity(0.48))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        Text(verbatim: "\(day.fullDate), \(LF.duration(minutes: day.minutes))")
                    )
                }
            }

            if weekTotalMinutes == 0 {
                Text("No work recorded this week.")
                    .font(LFFont.label(11))
                    .foregroundStyle(panelInk.opacity(0.44))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(panelInk.opacity(0.09), lineWidth: 1)
        )
    }

    private var panelGlass: Color {
        Color.white.opacity(0.86)
    }

    private var panelInk: Color {
        Color(uiColor: VoyageSceneKit.nightBG)
    }

    private var displayName: String {
        let normalized = PlayerProfile.normalizedName(playerName)
        return normalized.isEmpty ? LF.text("Sailor") : normalized
    }

    private var resolveText: String {
        let trimmed = resolve.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? LF.text("Add a short resolve") : trimmed
    }

    private var totalMinutes: Int {
        sessions.reduce(0) { $0 + max(0, $1.minutes) }
    }

    private var weekTotalMinutes: Int {
        weekDays.reduce(0) { $0 + $1.minutes }
    }

    private var weekSessionCount: Int {
        guard let interval = Self.calendar.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
        return sessions.filter { interval.contains($0.date) && $0.minutes > 0 }.count
    }

    private var maxWeekdayMinutes: Int {
        max(1, weekDays.map(\.minutes).max() ?? 0)
    }

    private var weekDays: [HomeIslandDailyMinutes] {
        let now = Date()
        guard let interval = Self.calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }

        return (0..<7).compactMap { offset in
            guard let date = Self.calendar.date(byAdding: .day, value: offset, to: interval.start),
                  let nextDate = Self.calendar.date(byAdding: .day, value: 1, to: date)
            else { return nil }

            let minutes = sessions.reduce(0) { total, session in
                guard session.date >= date, session.date < nextDate else { return total }
                return total + max(0, session.minutes)
            }
            return HomeIslandDailyMinutes(
                date: date,
                label: Self.weekdayFormatter.string(from: date),
                fullDate: LF.dayWithWeekday(date),
                minutes: minutes,
                isToday: Self.calendar.isDate(date, inSameDayAs: now)
            )
        }
    }

    private func shortMinutes(_ minutes: Int) -> String {
        if minutes >= 60 { return String(format: "%.1fh", Double(minutes) / 60) }
        return "\(minutes)m"
    }

    private static var calendar: Calendar {
        Calendar.autoupdatingCurrent
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()
}

private struct HomeIslandDailyMinutes: Identifiable {
    let date: Date
    let label: String
    let fullDate: String
    let minutes: Int
    let isToday: Bool

    var id: Date { date }
}

private struct HomeIslandMusicPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isEnabled: Bool
    @Binding var selectedTrackID: String
    @ObservedObject var music: HomeBackgroundMusic
    @AppStorage(StudyTimer.startKey, store: StudyTimer.defaults) private var timerStart: Double = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    playbackCard

                    VStack(spacing: 4) {
                        ForEach(HomeBackgroundMusic.tracks) { track in
                            trackRow(track)
                        }
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(panelInk.opacity(0.10), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 26)
            }
            .background(panelGlass.ignoresSafeArea())
            .navigationTitle(Text("Music"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(panelInk)
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var playbackCard: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(panelInk.opacity(0.08))
                    .frame(width: 48, height: 48)
                if music.isPlaying {
                    HomeIslandEqualizer(color: panelInk)
                        .frame(width: 21, height: 21)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(panelInk)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(selectedTrack.title)
                    .font(LFFont.copy(15))
                    .foregroundStyle(panelInk)
                    .lineLimit(2)

                Text(statusTitle)
                    .font(LFFont.label(10))
                    .foregroundStyle(panelInk.opacity(0.52))
            }

            Spacer(minLength: 8)

            Button {
                isEnabled.toggle()
                Haptics.tap(.medium)
            } label: {
                Image(systemName: isEnabled ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(panelInk, in: Circle())
            }
            .buttonStyle(LFPressableButtonStyle(scale: 0.94))
            .accessibilityLabel(Text(isEnabled ? "Stop" : "Play"))
        }
        .padding(14)
        .background(Color.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 21))
        .overlay(
            RoundedRectangle(cornerRadius: 21)
                .stroke(panelInk.opacity(0.11), lineWidth: 1)
        )
    }

    private func trackRow(_ track: HomeVoyageSound) -> some View {
        let selected = selectedTrackID == track.rawValue
        let playing = selected && music.isPlaying && music.currentTrack == track

        return Button {
            selectedTrackID = track.rawValue
            isEnabled = true
            Haptics.tap(.light)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(panelInk.opacity(selected ? 1 : 0.48))
                    .frame(width: 32, height: 32)
                    .background(panelInk.opacity(selected ? 0.10 : 0.045), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(LFFont.copy(13))
                        .foregroundStyle(panelInk)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if playing {
                        Text("Playing")
                            .font(LFFont.label(9))
                            .foregroundStyle(Color(uiColor: VoyageSceneKit.returnOrange))
                    }
                }

                Spacer(minLength: 8)

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(panelInk)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(LFPressableButtonStyle(scale: 0.98))
        .accessibilityLabel(track.title)
        .accessibilityValue(Text(playing ? "Playing" : selected ? "Selected" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var selectedTrack: HomeVoyageSound {
        guard let track = HomeVoyageSound(rawValue: selectedTrackID),
              HomeBackgroundMusic.tracks.contains(track)
        else { return .harborMinuet }
        return track
    }

    private var statusTitle: LocalizedStringKey {
        if music.playbackFailed { return "Playback unavailable" }
        if timerStart > 0, isEnabled { return "Plays after voyage" }
        return isEnabled ? "Playing" : "Stopped"
    }

    private var panelGlass: Color {
        Color.white.opacity(0.88)
    }

    private var panelInk: Color {
        Color(uiColor: VoyageSceneKit.nightBG)
    }
}

private struct HomeIslandNowPlayingBar: View {
    @ObservedObject var music: HomeBackgroundMusic

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            HStack(spacing: 10) {
                HomeIslandEqualizer(color: ink)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 5) {
                    Text(music.currentTrack.title)
                        .font(LFFont.copy(11))
                        .foregroundStyle(ink)
                        .lineLimit(1)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(ink.opacity(0.10))
                            Capsule()
                                .fill(ink.opacity(0.72))
                                .frame(width: proxy.size.width * music.playbackProgress)
                        }
                    }
                    .frame(height: 3)
                }
            }
            .padding(.horizontal, 12)
            .frame(width: 210, height: 44)
            .background(Color.white.opacity(0.84), in: Capsule())
            .overlay(Capsule().stroke(ink.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Now playing \(Text(music.currentTrack.title))"))
        }
    }

    private var ink: Color {
        Color(uiColor: VoyageSceneKit.nightBG)
    }
}

/// Keeps the live island world visible while presenting the existing public
/// five-harbor and private-room experience as an in-world notice-board panel.
private struct HomeIslandHarborPanel: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedPublicHarbor: PublicHarbor?
    @State private var selectedRoom: HarborRoom?
    @State private var selectedMemberTrace: MemberTraceKey?
    let onPrivateIslandSelected: (PrivateIslandRoom) -> Void
    let onClose: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let regular = horizontalSizeClass == .regular || geometry.size.width >= 700
            let horizontalMargin: CGFloat = regular ? 54 : 24
            let safeTop = max(geometry.safeAreaInsets.top, windowSafeAreaInsets.top)
            let safeBottom = max(geometry.safeAreaInsets.bottom, windowSafeAreaInsets.bottom)
            // This overlay intentionally draws edge-to-edge, so GeometryReader can
            // report zero safe-area values. Keep the notice-board panel clearly
            // below the status region on every destination screen.
            let topMargin = safeTop + (regular ? 34 : 26)
            let bottomMargin = safeBottom + (regular ? 30 : 22)
            let availableWidth = max(1, geometry.size.width - horizontalMargin * 2)
            let availableHeight = max(1, geometry.size.height - topMargin - bottomMargin)
            let panelWidth = min(regular ? 760 : availableWidth, availableWidth)
            // Keep enough vertical room for a dense sailor list. Individual
            // community headers are compact; the panel itself is the viewport.
            let preferredHeight = geometry.size.height * (regular ? 0.84 : 0.82)
            let panelHeight = min(regular ? 900 : 680, preferredHeight, availableHeight)
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture(perform: onClose)
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    ZStack(alignment: .topTrailing) {
                    Group {
                        if let selectedPublicHarbor {
                            NavigationStack {
                                PublicHarborView(
                                    harbor: selectedPublicHarbor,
                                    showsOceanBackground: false,
                                    onEmbeddedBack: {
                                        withAnimation(.easeOut(duration: 0.18)) {
                                            self.selectedPublicHarbor = nil
                                        }
                                    }
                                )
                                .navigationDestination(for: PublicMemberKey.self) { key in
                                    PublicMemberProfileView(
                                        slug: key.slug,
                                        initialMember: key.member,
                                        showsOceanBackground: false
                                    )
                                }
                            }
                        } else if let selectedRoom {
                            NavigationStack {
                                HarborChatView(
                                    room: selectedRoom,
                                    showsOceanBackground: false,
                                    onEmbeddedBack: {
                                        withAnimation(.easeOut(duration: 0.18)) {
                                            self.selectedRoom = nil
                                        }
                                    }
                                )
                            }
                        } else if let selectedMemberTrace {
                            NavigationStack {
                                MemberTraceView(
                                    roomId: selectedMemberTrace.roomId,
                                    member: selectedMemberTrace.member,
                                    showsOceanBackground: false,
                                    onEmbeddedBack: {
                                        withAnimation(.easeOut(duration: 0.18)) {
                                            self.selectedMemberTrace = nil
                                        }
                                    }
                                )
                            }
                        } else {
                            HarborView(
                                showsOceanBackground: false,
                                onPublicHarborSelected: { harbor in
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        selectedPublicHarbor = harbor
                                    }
                                },
                                onRoomSelected: { room in
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        selectedRoom = room
                                    }
                                },
                                onMemberTraceSelected: { trace in
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        selectedMemberTrace = trace
                                    }
                                },
                                onPrivateIslandSelected: { room in
                                    onClose()
                                    onPrivateIslandSelected(room)
                                }
                            )
                        }
                    }
                    .padding(.top, regular ? 10 : 8)
                    .clipShape(RoundedRectangle(cornerRadius: regular ? 30 : 24, style: .continuous))

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(panelInk)
                            .frame(width: 44, height: 44)
                            .background(panelInk.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                    .zIndex(20)
                    .accessibilityLabel(Text("Close"))
                    }
                    .frame(width: panelWidth, height: panelHeight)
                    .background {
                        RoundedRectangle(cornerRadius: regular ? 30 : 24, style: .continuous)
                            .fill(Color.white.opacity(0.28))
                            .overlay {
                                RoundedRectangle(cornerRadius: regular ? 30 : 24, style: .continuous)
                                    .fill(.ultraThinMaterial.opacity(0.22))
                            }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: regular ? 30 : 24, style: .continuous)
                            .stroke(panelInk.opacity(0.14), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 28, y: 14)
                    .accessibilityAddTraits(.isModal)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, topMargin)
                .padding(.bottom, bottomMargin)
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
        }
        .ignoresSafeArea()
    }

    private var panelInk: Color {
        Color(uiColor: VoyageSceneKit.nightBG)
    }

    private var windowSafeAreaInsets: UIEdgeInsets {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first else {
            return .zero
        }
        return window.safeAreaInsets
    }
}

private struct HomeIslandEqualizer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 0.22, paused: reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(
                            width: 3,
                            height: reduceMotion
                                ? CGFloat(8 + index * 3)
                                : CGFloat(7 + abs(sin(phase * 3.4 + Double(index) * 1.7)) * 11)
                        )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct HomeIslandClockHUD: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: LF.dayWithWeekday(context.date))
                    .font(LFFont.copy(11))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)

                Text(verbatim: Self.timeFormatter.string(from: context.date))
                    .font(LFFont.number(36))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }
            .shadow(color: .black.opacity(0.72), radius: 2, x: 0, y: 1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                Text(
                    verbatim: "\(LF.dayWithWeekday(context.date)), \(Self.timeFormatter.string(from: context.date))"
                )
            )
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct HomeIslandTodoItem: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    let createdAt: Date

    init(title: String) {
        id = UUID()
        self.title = title
        isCompleted = false
        createdAt = .now
    }
}

private enum HomeIslandTodoPersistence {
    private static let storageKey = "homeIsland.todoItems.v1"

    static func load() -> [HomeIslandTodoItem] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let items = try? JSONDecoder().decode([HomeIslandTodoItem].self, from: data)
        else { return [] }
        return items
    }

    static func save(_ items: [HomeIslandTodoItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

private struct HomeIslandTodoListView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var items: [HomeIslandTodoItem]
    @State private var draft = ""
    @FocusState private var draftFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    TextField("Add a task", text: $draft)
                        .font(LFFont.copy(14))
                        .foregroundStyle(panelInk)
                        .tint(panelInk)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .focused($draftFocused)
                        .onSubmit(addDraft)

                    Button(action: addDraft) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(panelInk, in: Circle())
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .disabled(trimmedDraft.isEmpty)
                    .opacity(trimmedDraft.isEmpty ? 0.45 : 1)
                    .accessibilityLabel(Text("Add"))
                }
                .padding(.leading, 14)
                .padding(.trailing, 10)
                .frame(minHeight: 54)
                .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 17))
                .overlay(
                    RoundedRectangle(cornerRadius: 17)
                        .stroke(panelInk.opacity(0.12), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

                if items.isEmpty {
                    ContentUnavailableView(
                        "No tasks yet",
                        systemImage: "checklist",
                        description: Text("Add a task for your next voyage.")
                    )
                    .foregroundStyle(panelInk.opacity(0.72))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach($items) { $item in
                            Button {
                                item.isCompleted.toggle()
                                Haptics.tap(.light)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(
                                            item.isCompleted
                                                ? panelInk
                                                : panelInk.opacity(0.42)
                                        )

                                    Text(verbatim: item.title)
                                        .font(LFFont.copy(14))
                                        .foregroundStyle(panelInk.opacity(item.isCompleted ? 0.42 : 0.92))
                                        .strikethrough(item.isCompleted, color: panelInk.opacity(0.36))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(minHeight: 42)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.white.opacity(0.52))
                            .listRowSeparatorTint(panelInk.opacity(0.09))
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    items.removeAll { $0.id == item.id }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .accessibilityValue(Text(item.isCompleted ? "Completed" : "Not completed"))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(panelGlass.ignoresSafeArea())
            .navigationTitle(Text("ToDo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(panelInk)
                }
            }
        }
        .preferredColorScheme(.light)
        .onChange(of: items) { _, value in
            HomeIslandTodoPersistence.save(value)
        }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var panelGlass: Color {
        Color.white.opacity(0.86)
    }

    private var panelInk: Color {
        Color(uiColor: VoyageSceneKit.nightBG)
    }

    private func addDraft() {
        let title = trimmedDraft
        guard !title.isEmpty else { return }
        items.insert(HomeIslandTodoItem(title: title), at: 0)
        draft = ""
        draftFocused = true
        Haptics.tap(.light)
    }
}

private struct HomeIslandAssetThumbnail: View {
    let assetID: String
    let fallbackSymbol: String

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(uiColor: VoyageSceneKit.sand).opacity(0.82))
            }
        }
        .task(id: assetID) {
            image = await HomeIslandAssetThumbnailRenderer.image(for: assetID)
        }
        .accessibilityHidden(true)
    }
}

@MainActor
private enum HomeIslandAssetThumbnailRenderer {
    private static var cache: [String: UIImage] = [:]

    static func image(for assetID: String) async -> UIImage? {
        if let cached = cache[assetID] { return cached }
        await Task.yield()
        guard let model = AssetPlacementRuntime.makeAssetNode(resourceName: assetID),
              let image = render(model: model)
        else { return nil }
        cache[assetID] = image
        return image
    }

    private static func render(model: SCNNode) -> UIImage? {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        model.enumerateChildNodes { node, _ in
            node.removeAllActions()
            node.animationKeys.forEach(node.removeAnimation(forKey:))
        }

        let bounds = model.boundingBox
        let width = max(bounds.max.x - bounds.min.x, 0.01)
        let height = max(bounds.max.y - bounds.min.y, 0.01)
        let depth = max(bounds.max.z - bounds.min.z, 0.01)
        let extent = max(width, height, depth)
        let center = SCNVector3(
            (bounds.min.x + bounds.max.x) * 0.5,
            (bounds.min.y + bounds.max.y) * 0.5,
            (bounds.min.z + bounds.max.z) * 0.5
        )
        model.position = SCNVector3(-center.x, -center.y, -center.z)
        scene.rootNode.addChildNode(model)

        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = Double(max(extent * 0.72, 0.42))
        camera.zNear = 0.01
        camera.zFar = Double(max(extent * 20, 100))
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(extent * 1.7, extent * 1.15, extent * 2.2)
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)

        let keyLight = SCNNode()
        let directional = SCNLight()
        directional.type = .directional
        directional.intensity = 1_350
        directional.castsShadow = false
        keyLight.light = directional
        keyLight.eulerAngles = SCNVector3(-0.82, 0.68, 0)
        scene.rootNode.addChildNode(keyLight)

        let ambientNode = SCNNode()
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 620
        ambient.color = UIColor(rgb: 0xCFE8DD)
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraNode
        renderer.autoenablesDefaultLighting = false
        return renderer.snapshot(
            atTime: 0,
            with: CGSize(width: 96, height: 96),
            antialiasingMode: .multisampling4X
        )
    }
}
