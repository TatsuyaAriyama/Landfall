import Combine
import Metal
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
            HomeIslandAssetCatalog.group(of: assetID) == .nature
        case .structures:
            HomeIslandAssetCatalog.group(of: assetID) == .structures
        case .decor:
            HomeIslandAssetCatalog.group(of: assetID) == .decor
        case .paths:
            HomeIslandAssetCatalog.group(of: assetID) == .paths
        case .furniture:
            HomeIslandAssetCatalog.group(of: assetID) == .furniture
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
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudySession.date) private var studySessions: [StudySession]
    @Query private var destinations: [Destination]
    @ObservedObject private var homeMusic = HomeBackgroundMusic.shared
    @StateObject private var store: HomeIslandStore
    @State private var placementAssetID: String?
    @State private var movingSelection = false
    @State private var placementMoveBlocked = false
    @AppStorage("homeIsland.placementAssistance") private var placementAssistanceEnabled = false
    @State private var showingSizeControls = false
    @State private var showingSelectionActions = false
    @State private var showingIslandResetConfirm = false
    @State private var lockedAssetID: String?
    @State private var cameraResetToken = 0
    @State private var cameraRequest: HomeIslandCameraRequest?
    @State private var captureRequest: HomeIslandCaptureRequest?
    /// 写真モードの明るさ増減(EV)。0 = 歩いているときのまま。
    @State private var cameraExposureOffset: Float = 0
    @State private var showingCameraExposureControl = false
    @State private var showingCameraCompositionGuide = false
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
    // Builders work in one category for a long stretch; reopening on "all"
    // every time meant scrolling past forty tiles to get back to it.
    @AppStorage("homeIsland.buildCategory") private var selectedAssetCategoryToken =
        HomeIslandAssetCategory.all.rawValue
    @StateObject private var catalogPreferences = HomeIslandCatalogPreferences()
    @State private var catalogScope = HomeIslandCatalogScope.all
    @State private var catalogQuery = ""
    @State private var showingCatalogSearch = false
    @State private var transientNotice: String?
    @State private var isDismissingAfterDeparture = false
    @State private var isNavigatorOnArrivalJetty = false
    @State private var isNavigatorNearNoticeBoard = false
    @State private var showingBoatCustomization = false
    @State private var selectedBoatSailID = BoatCustomization.selectedSailID
    @State private var selectedBoatShipID = BoatCustomization.effectiveSelectedShipID
    /// 航海士を触ったときに出す、色替えだけの小さな表示。
    @State private var showingNavigatorColors = false
    @State private var selectedNavColorID = NavigatorCustomization.selectedID
    @State private var showingVoyagePass = false
    @State private var showingIslandSlots = false
    /// Switching islands rebuilds this very view, so the choice is held until
    /// the cover has finished dismissing. Acting while it was still on screen
    /// tore the presenter down mid-transition and the switch was dropped.
    @State private var pendingIslandSwitch: Int?
    @StateObject private var islandSlots = HomeIslandSlotBook(
        baseOwnerID: AuthService.shared.homeIslandOwnerID
    )
    @StateObject private var voyagePass = VoyagePassStore.shared
    @State private var showingTodoList = false
    @StateObject private var todoStore = HomeIslandTodoStore.shared
    @State private var showingPlayerStats = false
    @State private var showingIslandBrightness = false
    /// The family whose variants are open, and the one each family is
    /// showing. Both are per-session: a drawer that reopened on "pink desk"
    /// a week later would be a surprise, but switching twice in one build
    /// session should not mean re-picking every time.
    @State private var expandedFamilyID: String?
    @State private var familySelection: [String: String] = [:]
    @State private var editingPlayerProfile = false
    /// 週グラフで選んでいる日。開くたび今日から始まる。
    @State private var selectedRecordDay: Date?
    @State private var showingMusicPicker = false
    @State private var showingSettings = false
    @State private var showingWorkRecords = false
    @State private var showingHarborPanel = false
    @State private var privateChatExpanded = false
    /// 泡ひとつまで畳んだチャット。足元のHUDはその分だけ下に戻る。
    @State private var privateChatMinimized = false
    @State private var privateChatInputFocused = false
    /// 目的地の残り時間だけを刻む時計。島の距離と期日表示をそっと進める。
    @State private var destinationClock = Date()
    @State private var showingDestinationSetup = false
    @State private var destinationNameDraft = ""
    @State private var destinationDateDraft = Date()
    @FocusState private var destinationNameFocused: Bool
    @AppStorage(PlayerProfile.nameKey) private var playerName = ""
    @AppStorage(PlayerProfile.styleKey) private var playerStyleToken = TileStyle.midnight.rawValue
    @AppStorage(PlayerProfile.symbolKey) private var playerSymbolToken = TileSymbol.phoenix.rawValue
    @AppStorage(HomeBackgroundMusic.enabledKey) private var homeMusicEnabled = false
    @AppStorage(HomeBackgroundMusic.selectedTrackKey)
    private var homeMusicTrack = HomeVoyageSound.harborMinuet.rawValue
    /// 設定で選んだ島の明るさ。歩いているときの明るさそのものを5段でずらす。
    @AppStorage(HomeIslandBrightness.storageKey)
    private var islandBrightnessToken = HomeIslandBrightness.fallback.rawValue

    private var islandBrightness: HomeIslandBrightness {
        HomeIslandBrightness.resolve(islandBrightnessToken)
    }

    /// 期日の目的地は残り一週間から少しずつ近づく。分ごとで十分に足りる。
    private let destinationMinuteClock = Timer.publish(
        every: 60,
        tolerance: 5,
        on: .main,
        in: .common
    ).autoconnect()

    private let assets = HomeIslandAssetCatalog.available()
    private let levelProgress: PlayerLevelProgress
    private let startsMooredAtIsland: Bool
    private let playsArrivalOnAppear: Bool
    private let boatTapOpensSelection: Bool
    private let externalBoatBoardingRequest: HomeIslandBoatBoardingRequest?
    private let noticeBoardRequestID: UUID?
    private let onBoatSelected: () -> Void
    private let onEmbeddedArrivalCompleted: () -> Void
    private let onEmbeddedDepartureCompleted: (() -> Void)?
    private let onEmbeddedBoardingRejected: () -> Void
    private let renderingActive: Bool
    private let multiplayerSession: HomeIslandMultiplayerSession?
    private let onPrivateIslandSelected: (PrivateIslandRoom) -> Void
    /// ホームとして見せている島だけが、沖の目的地と、その設定の入口を持つ。
    private let showsDestination: Bool
    /// 上陸の確認と着岸演出は、これまでどおりホーム側が持つ。
    private let onDestinationLandfall: ((Destination) -> Void)?

    init(
        ownerID: String,
        levelProgress: PlayerLevelProgress,
        startsMooredAtIsland: Bool = false,
        playsArrivalOnAppear: Bool = false,
        boatTapOpensSelection: Bool = false,
        boardingRequest: HomeIslandBoatBoardingRequest? = nil,
        noticeBoardRequestID: UUID? = nil,
        onBoatSelected: @escaping () -> Void = {},
        onArrivalCompleted: @escaping () -> Void = {},
        onDepartureCompleted: (() -> Void)? = nil,
        onBoardingRejected: @escaping () -> Void = {},
        renderingActive: Bool = true,
        showsDestination: Bool = false,
        onDestinationLandfall: ((Destination) -> Void)? = nil,
        multiplayerSession: HomeIslandMultiplayerSession? = nil,
        onPrivateIslandSelected: @escaping (PrivateIslandRoom) -> Void = { _ in }
    ) {
        self.levelProgress = levelProgress
        self.showsDestination = showsDestination
        self.onDestinationLandfall = onDestinationLandfall
        self.startsMooredAtIsland = startsMooredAtIsland
        self.playsArrivalOnAppear = playsArrivalOnAppear
        self.boatTapOpensSelection = boatTapOpensSelection
        externalBoatBoardingRequest = boardingRequest
        self.noticeBoardRequestID = noticeBoardRequestID
        self.onBoatSelected = onBoatSelected
        onEmbeddedArrivalCompleted = onArrivalCompleted
        onEmbeddedDepartureCompleted = onDepartureCompleted
        onEmbeddedBoardingRejected = onBoardingRejected
        self.renderingActive = renderingActive
        self.multiplayerSession = multiplayerSession
        self.onPrivateIslandSelected = onPrivateIslandSelected
        let readOnly = multiplayerSession?.isReadOnly == true
        _store = StateObject(
            wrappedValue: HomeIslandStore(
                ownerID: readOnly ? (multiplayerSession?.room.hostUid ?? ownerID) : ownerID,
                snapshot: readOnly ? multiplayerSession?.snapshot : nil,
                readOnly: readOnly,
                playerLevel: levelProgress.level
            )
        )
        _mode = State(
            initialValue: startsMooredAtIsland && !playsArrivalOnAppear
                ? .explore
                : .arrival
        )
    }

    /// One source of truth for every state that temporarily owns interaction
    /// above the island. This also keeps controller input from moving the
    /// navigator behind sheets and full-screen presentations.
    private var sceneInputLocked: Bool {
        !renderingActive
            || scenePhase != .active
            || isCapturing
            || showingHarborPanel
            || privateChatExpanded
            || privateChatInputFocused
            || showingBoatCustomization
            || showingDestinationSetup
            || showingVoyagePass
            || showingIslandSlots
            || showingLogbook
            || activeInterior != nil
            || showingPlayerStats
            || showingIslandBrightness
            || showingMusicPicker
            || showingSettings
            || showingWorkRecords
            || showingIslandShare
            || showingCaptureError
            || showingSelectionActions
            || showingIslandResetConfirm
    }

    /// Full-screen destinations do not need a live SceneKit world behind them.
    /// Partial HUDs keep a throttled live backdrop so their spatial context stays clear.
    private var sceneRenderingActive: Bool {
        renderingActive
            && scenePhase == .active
            && !showingVoyagePass
            && !showingIslandSlots
            && !showingLogbook
            && activeInterior == nil
            && !showingIslandShare
            && !showingSettings
            && !showingWorkRecords
            && !showingHarborPanel
    }

    var body: some View {
        // The presentation modifiers live here and the scene in
        // `islandStage`: as one expression this view no longer type-checks.
        islandStage
            .fullScreenCover(isPresented: $showingVoyagePass) {
                VoyagePassView()
            }
            .fullScreenCover(isPresented: $showingIslandSlots, onDismiss: commitIslandSwitch) {
                HomeIslandSlotsView(
                    book: islandSlots,
                    onSelect: { index in
                        pendingIslandSwitch = index
                        showingIslandSlots = false
                    },
                    onOpenVoyagePass: {
                        showingIslandSlots = false
                        showingVoyagePass = true
                    }
                )
                .overlay(alignment: .topTrailing) { islandSlotsCloseButton }
            }
            // 証を取った直後・切れた直後に、鍵と航海士の姿を合わせ直す。
            .onChange(of: voyagePass.isActive) { _, active in
                NavigatorCustomization.updatePassState(active)
                BoatCustomization.updatePassState(active)
                selectedNavColorID = NavigatorCustomization.selectedID
                selectedBoatShipID = BoatCustomization.effectiveSelectedShipID
            }
            .onAppear {
                NavigatorCustomization.updatePassState(voyagePass.isActive)
                BoatCustomization.updatePassState(voyagePass.isActive)
                selectedNavColorID = NavigatorCustomization.selectedID
                selectedBoatShipID = BoatCustomization.effectiveSelectedShipID
                store.updatePlayerLevel(levelProgress.level)
            }
            .onChange(of: levelProgress.level) { _, level in
                store.updatePlayerLevel(level)
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
                    let removedTitle = store.selectedPlacement.flatMap {
                        HomeIslandAssetCatalog.asset(id: $0.assetID)?.title
                    }
                    store.deleteSelected()
                    movingSelection = false
                    showingSizeControls = false
                    placementMoveBlocked = false
                    showTransientNotice(
                        removedTitle.map { LF.format("Removed %@ · Undo is available", $0) }
                            ?? LF.text("Removed · Undo is available")
                    )
                    Haptics.tap(.medium)
                }

                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Clear the island?",
                isPresented: $showingIslandResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear the island", role: .destructive) {
                    clearIsland()
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every prop you placed goes back and the island is left bare. Undo is available.")
            }
    }

    fileprivate var islandStageBase: some View {
        ZStack {
            // Keep the daylight sky outside SceneKit's HDR tone mapper. The
            // voyage home uses the same composition; rendering this color as
            // an SCNScene background made My Island noticeably darker even
            // though both cameras used the same exposure.
            HomeIslandSkyBackdrop(brightness: islandBrightness)

            HomeIslandSceneView(
                store: store,
                placementAssetID: $placementAssetID,
                playerLevel: levelProgress.level,
                cameraResetToken: cameraResetToken,
                cameraRequest: cameraRequest,
                captureRequest: captureRequest,
                boatBoardingRequest: externalBoatBoardingRequest ?? boatBoardingRequest,
                mode: mode,
                cameraExposureOffset: cameraExposureOffset,
                islandExposureOffset: islandBrightness.exposureOffset,
                placementAssistanceEnabled: placementAssistanceEnabled,
                cameraInteractionLocked: sceneInputLocked,
                // Interactive overlays keep the island legible as a 20 fps
                // backdrop; full-screen destinations suspend it completely.
                rendersThrottled: sceneInputLocked,
                renderingActive: sceneRenderingActive,
                walkInput: sceneInputLocked ? .zero : walkInput,
                onMoveBegan: {
                    movingSelection = true
                    showingSizeControls = false
                },
                onMoveCompleted: {
                    movingSelection = false
                    placementMoveBlocked = false
                },
                onMoveBlockedChanged: { blocked in
                    placementMoveBlocked = blocked
                },
                onPlacementCompleted: finishPlacement,
                onPlacementRejected: reportPlacementRejection,
                onAssetActivated: activateAsset,
                onAssetInteractionDenied: { assetID in
                    let notice = LF.text("Move closer to interact")
                    showTransientNotice(notice)
                    UIAccessibility.post(notification: .announcement, argument: notice)
                    if assetID == "home_boat", startsMooredAtIsland {
                        onEmbeddedBoardingRejected()
                    }
                },
                onArrivalCompleted: {
                    finishArrival()
                },
                onJettyPresenceChanged: { isOnJetty in
                    withAnimation(.easeOut(duration: 0.18)) {
                        isNavigatorOnArrivalJetty = isOnJetty
                    }
                },
                onNoticeBoardProximityChanged: { isNear in
                    withAnimation(.easeOut(duration: 0.18)) {
                        isNavigatorNearNoticeBoard = isNear
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
                playsArrivalOnAppear: playsArrivalOnAppear,
                locksMooredOverview: false,
                boatTapOpensSelection: boatTapOpensSelection,
                boatCustomizationActive: showingBoatCustomization,
                boatAppearanceID: "\(selectedBoatShipID)-\(selectedBoatSailID)",
                navigatorTapOpensColors: multiplayerSession?.isReadOnly != true,
                navigatorAppearanceID: effectiveNavColor.id,
                onNavigatorSelected: { toggleNavigatorColors() },
                destinationBearing: destinationBearing,
                destinationGazeActive: showingDestinationSetup,
                onBoatSelected: onBoatSelected,
                remotePlayers: multiplayerRemotePlayers,
                localPlayerID: multiplayerSession?.currentUserID,
                onLocalPlayerStateChanged: { state in
                    lastOutdoorPlayerState = state
                    multiplayerSession?.onLocalPlayerStateChanged(state)
                }
            )
            .id("home-island-scene-\(HomeIslandExpansionPolicy.scale(for: levelProgress.level))")
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

            // This guide belongs only to the SwiftUI preview. Capture reads
            // the underlying SCNView, so it can never enter the saved photo.
            if mode == .camera, showingCameraCompositionGuide {
                HomeIslandPhotoThirdsGuide()
                    .stroke(.white.opacity(0.58), lineWidth: 0.75)
                    .shadow(color: .black.opacity(0.48), radius: 1)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if showingBoatCustomization || showingDestinationSetup {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }

            if mode == .explore,
               !showingBoatCustomization,
               !showingNavigatorColors,
               !showingDestinationSetup,
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
               !showingNavigatorColors,
               !showingDestinationSetup,
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
               !showingDestinationSetup,
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
                        // 開いたチャットは色替えの段を覆う。どちらか一方だけが
                        // 足元に残るよう、開いた側が古い段を引き取って閉じる。
                        if expanded, showingNavigatorColors {
                            withAnimation(.easeOut(duration: 0.22)) {
                                showingNavigatorColors = false
                            }
                        }
                    },
                    onMinimizedChanged: { minimized in
                        privateChatMinimized = minimized
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
                    if mode != .camera, mode != .arrival {
                        Group {
                            if showingBoatCustomization {
                                boatCustomizationTopBar
                            } else {
                                topBar
                            }
                        }
                        // 目的地を決めている間だけ姿を消す。行そのものは残す
                        // ので、下の目的地の文字は押す前と同じ高さに座る。
                        .opacity(showingDestinationSetup ? 0 : 1)
                        .allowsHitTesting(!showingDestinationSetup)
                    }
                    if mode == .explore,
                       multiplayerSession?.isReadOnly != true,
                       !showingBoatCustomization,
                       showsDestination {
                        destinationShortcut
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, compactTopHUD ? 8 : 12)
                            .padding(.top, compactTopHUD ? 6 : 8)
                            .allowsHitTesting(!showingDestinationSetup)
                    }
                    if showingBoatCustomization || showingDestinationSetup {
                        EmptyView()
                    } else if mode != .camera, !store.lastSaveSucceeded {
                        saveFailureHint
                            .padding(.top, compactTopHUD ? 8 : 10)
                    } else if mode == .arrival {
                        arrivalStatus
                            .padding(.top, 12)
                    } else if mode == .edit {
                        modeHint
                            .padding(.top, compactTopHUD ? 8 : 10)
                    } else if mode != .camera, let transientNotice {
                        noticePill(symbol: "figure.walk", text: transientNotice)
                            .padding(.top, compactTopHUD ? 8 : 10)
                    } else if mode == .explore, isNavigatorOnArrivalJetty {
                        noticePill(
                            symbol: "sailboat.fill",
                            text: LF.text(boatTapOpensSelection
                                    ? "Tap the ship to choose a work item"
                                    : "Walk to the boat and tap it to return home"
                            )
                        )
                        .padding(.top, compactTopHUD ? 8 : 10)
                    } else if mode == .explore,
                              isNavigatorNearNoticeBoard,
                              multiplayerSession?.isReadOnly != true,
                              !showingBoatCustomization,
                              !showingDestinationSetup {
                        // The harbors used to sit behind a permanent HUD button.
                        // Standing beside the board is the cue now, so the hint
                        // only appears where tapping it actually works.
                        noticePill(
                            symbol: "signpost.right.and.left.fill",
                            text: LF.text("Tap the notice board to check it")
                        )
                        .padding(.top, compactTopHUD ? 8 : 10)
                    }

                    Spacer(minLength: mode == .edit || mode == .camera ? 72 : 24)

                    if mode == .explore {
                        if showingBoatCustomization {
                            boatCustomizationDock
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else if showingNavigatorColors {
                            navigatorColorDock
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else if showingDestinationSetup {
                            destinationSetupDock
                                .padding(.bottom, 8)
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

            if showingWorkRecords {
                Group {
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["LANDFALL_RECORDS_PREVIEW"] == "1" {
                        WorkRecordsPreview(onClose: { showingWorkRecords = false })
                    } else {
                        TraceView(onClose: { showingWorkRecords = false }, initialDay: selectedRecordDay)
                    }
                    #else
                    TraceView(onClose: { showingWorkRecords = false }, initialDay: selectedRecordDay)
                    #endif
                }
                .environment(\.colorScheme, .light)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .zIndex(105)
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
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["LANDFALL_RECORDS_PREVIEW"] == "1" {
                showingWorkRecords = true
            }
            #endif
        }
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
        .animation(.easeOut(duration: 0.22), value: showingNavigatorColors)
        .animation(.easeOut(duration: 0.22), value: showingDestinationSetup)
        .onChange(of: placementAssetID) { _, value in
            if value != nil {
                movingSelection = false
                showingSizeControls = false
            }
        }
        .onChange(of: movingSelection) { _, moving in
            if !moving { placementMoveBlocked = false }
        }
        .onChange(of: store.selectedID) { _, value in
            guard value != nil else {
                movingSelection = false
                placementMoveBlocked = false
                showingSizeControls = false
                return
            }
            guard placementAssetID != nil else { return }
            placementAssetID = nil
            movingSelection = false
            showingSizeControls = allowsAssetSizeCalibration
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
    }

    /// The second half of the scene's modifier chain. Three properties instead
    /// of one keeps each expression small enough for the type checker.
    fileprivate var islandStage: some View {
        islandStageBase
        .onChange(of: multiplayerSession?.room.id) { _, _ in
            replaceGuestSnapshot(multiplayerSession?.snapshot)
        }
        .onChange(of: mode) { _, value in
            if value != .explore {
                walkInput = .zero
                // The chat dock leaves the hierarchy during arrival/departure.
                // Clear its transient ownership here as well as in the dock's
                // lifecycle so a stale focus callback can never lock movement
                // after returning from a voyage.
                privateChatExpanded = false
                privateChatInputFocused = false
            }
        }
        .task(id: mode) {
            guard mode == .arrival else { return }
            // SceneKit actions pause with the app and can also be interrupted by
            // a renderer reset. Match departure's safety net so the player can
            // never be stranded on an arrival-only HUD.
            try? await Task.sleep(for: .seconds(9))
            guard !Task.isCancelled else { return }
            finishArrival()
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
        .onReceive(NotificationCenter.default.publisher(for: .homeIslandDidChange)) { note in
            guard multiplayerSession == nil,
                  note.object as? String == store.ownerKey
            else { return }
            _ = store.reloadLocalSnapshotIfNewer()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, !store.lastSaveSucceeded {
                store.save()
            }
            if phase == .active {
                destinationClock = Date()
            }
        }
        .onReceive(destinationMinuteClock) { tick in
            guard scenePhase == .active, activeDestination != nil else { return }
            destinationClock = tick
        }
        .overlay(alignment: .topTrailing) {
            homeUtilityPanel
        }
    }

    private var topBar: some View {
        HStack(spacing: compactTopHUD ? 2 : 8) {
            Button {
                walkInput = .zero
                openUtility(.player)
            } label: {
                playerCardHUD
            }
            .buttonStyle(LFPressableButtonStyle())
            .contentShape(Capsule())
            .accessibilityHint(Text("Shows your work history"))

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
                                .font(.system(size: topControlSymbolSize, weight: .semibold))
                                .foregroundStyle(homeGlassInk)
                                .frame(width: topControlWidth, height: topControlHeight)
                                .contentShape(Rectangle())
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
                            .font(.system(size: topControlSymbolSize, weight: .semibold))
                            .foregroundStyle(homeGlassInk)
                            .frame(width: topControlWidth, height: topControlHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .accessibilityLabel(Text("Camera mode"))

                    if canEditIsland {
                        Button {
                            enterEditMode()
                        } label: {
                            Image(systemName: "hammer.fill")
                                .font(.system(size: topControlSymbolSize, weight: .semibold))
                                .foregroundStyle(homeGlassInk)
                                .frame(width: topControlWidth, height: topControlHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(LFPressableButtonStyle())
                        .accessibilityLabel(Text("Edit Island"))
                    }

                    Menu {
                        Button {
                            walkInput = .zero
                            openUtility(.brightness)
                        } label: {
                            Label("Island brightness", systemImage: "sun.max")
                        }

                        Divider()

                        Button {
                            walkInput = .zero
                            openUtility(.todo)
                        } label: {
                            Label("ToDo list", systemImage: "checklist")
                        }

                        Button {
                            walkInput = .zero
                            openUtility(.music)
                        } label: {
                            Label("Music", systemImage: "music.note")
                        }
                        .accessibilityValue(musicAccessibilityValue)
                        .accessibilityHint(Text("Choose a track"))

                        Divider()

                        Button {
                            walkInput = .zero
                            showingSettings = true
                            Haptics.tap(.light)
                        } label: {
                            Label("Settings", systemImage: "gearshape.fill")
                        }
                        .accessibilityHint(Text("Change language, app icon, and account"))
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: topControlSymbolSize, weight: .bold))
                                .foregroundStyle(homeGlassInk)
                            if homeMusic.isPlaying {
                                Circle()
                                    .fill(Color(uiColor: VoyageSceneKit.returnOrange))
                                    .frame(width: 6, height: 6)
                                    .offset(x: 5, y: -5)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(width: topControlWidth, height: topControlHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .tint(homeGlassInk)
                    .menuIndicator(.hidden)
                    .menuOrder(.fixed)
                    .accessibilityLabel(Text("More actions"))
                }
                .fixedSize(horizontal: true, vertical: false)
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
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
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
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .disabled(!store.canRedo)
                    .accessibilityLabel(Text("Redo"))

                    Button {
                        showingIslandResetConfirm = true
                        Haptics.tap(.light)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(homeGlassInk.opacity(store.placements.isEmpty ? 0.30 : 1))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .disabled(store.placements.isEmpty)
                    .accessibilityLabel(Text("Clear the island"))
                    .accessibilityHint(Text("Removes every placed prop"))

                    Button {
                        enterExploreMode()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(homeGlassInk)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .accessibilityLabel(Text("Finish editing"))
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(3)
                .background(homeGlassBackground, in: Capsule())
                .overlay(Capsule().stroke(homeGlassInk.opacity(0.12), lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, compactTopHUD ? 8 : 12)
        .safeAreaPadding(.top, 8)
    }

    /// いま向かっている目的地。プレイヤーカードの真下に置き、名前と期日を
    /// 帯なしの文字だけで出す。空の色は決まっているので、名前は黒、期日は
    /// 帰還と同じ橙で読ませる。押すと、この島から沖の目的地を見つめる。
    private var destinationShortcut: some View {
        Button {
            enterDestinationSetup()
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                if let destination = activeDestination {
                    Text(verbatim: destination.name)
                        .font(LFFont.copy(compactTopHUD ? 14 : 16))
                        .foregroundStyle(homeGlassInk)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if !destinationSubtitle.isEmpty {
                        Text(verbatim: destinationSubtitle)
                            .font(LFFont.label(compactTopHUD ? 11 : 12))
                            .foregroundStyle(LFColor.returnOrange)
                            .lineLimit(1)
                    }
                } else {
                    Text("Set a destination")
                        .font(LFFont.copy(compactTopHUD ? 14 : 16))
                        .foregroundStyle(homeGlassInk.opacity(0.62))
                        .lineLimit(1)
                }
            }
            // 島の緑や桟橋が上まで入り込む画角でも読めるよう、空の色の
            // にじみだけ敷く。帯には戻さない。
            .shadow(color: Color(uiColor: UIColor(rgb: 0x8BCFDB)).opacity(0.9), radius: 4)
            .padding(.horizontal, compactTopHUD ? 4 : 6)
            .frame(minHeight: compactTopHUD ? 34 : 40, alignment: .center)
            .frame(maxWidth: destinationShortcutMaxWidth, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityLabel(Text("Destinations"))
        .accessibilityValue(
            Text(
                verbatim: activeDestination.map { "\($0.name)、\(destinationSubtitle)" }
                    ?? LF.text("Set a destination")
            )
        )
        .accessibilityHint(Text("Tap to edit the destination."))
    }

    /// 名前が長くても、島の景色を横切る帯にはしない。
    private var destinationShortcutMaxWidth: CGFloat {
        compactTopHUD ? 190 : 260
    }

    private var activeDestination: Destination? {
        destinations.first { $0.achievedAt == nil }
    }

    /// 期日を決めた目的地は「7月14日まで」。着いていれば上陸できると出す。
    private var destinationSubtitle: String {
        guard let destination = activeDestination else { return "" }
        let progress = destination.progress(sessions: studySessions, now: destinationClock)
        if progress.reached {
            return LF.text("Ready to go ashore")
        }
        if let targetDate = destination.targetDate {
            return LF.format("Due %@", LF.dayMonth(targetDate))
        }
        if let days = progress.remainingDays {
            return LF.format("%lld days left", Int64(days))
        }
        return ""
    }

    /// 目的地はこの島の主のもの。他の航海士の島を訪ねている間は沖に出さない。
    /// 設定中は、まだ保存していない期日の島も同じ沖に見せる。
    private var destinationBearing: HomeIslandDestinationBearing? {
        guard showsDestination, multiplayerSession?.isReadOnly != true else { return nil }
        if showingDestinationSetup {
            return HomeIslandDestinationBearing(
                name: destinationNameDraft,
                progressRatio: HomeIslandView.destinationRatio(
                    deadline: destinationDraftDeadline,
                    now: destinationClock
                )
            )
        }
        guard let destination = activeDestination else { return nil }
        return HomeIslandDestinationBearing(
            name: destination.name,
            progressRatio: destination.progress(
                sessions: studySessions,
                now: destinationClock
            ).ratio
        )
    }

    /// 下書きの期日の締切(その日いっぱい)。Destination.deadline と同じ解釈。
    private var destinationDraftDeadline: Date {
        let start = Calendar.current.startOfDay(for: destinationDateDraft)
        return Calendar.current.date(
            byAdding: DateComponents(day: 1, nanosecond: -1),
            to: start
        ) ?? destinationDateDraft
    }

    /// 期日目標の近さ。残り一週間から少しずつ近づく(Destination.progress と同値)。
    private static func destinationRatio(deadline: Date, now: Date) -> Double {
        let remaining = max(0, deadline.timeIntervalSince(now))
        let approachWindow: TimeInterval = 7 * 86_400
        return min(1, max(0, 1 - remaining / approachWindow))
    }

    private var destinationDraftIsValid: Bool {
        !destinationNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && destinationDraftDeadline > destinationClock
    }

    private func enterDestinationSetup() {
        walkInput = .zero
        let existing = activeDestination
        destinationNameDraft = existing?.name ?? ""
        destinationDateDraft = existing?.targetDate
            ?? Calendar.current.date(byAdding: .day, value: 30, to: Date())
            ?? Date()
        destinationClock = Date()
        withAnimation(.easeOut(duration: 0.24)) {
            showingDestinationSetup = true
        }
        Haptics.tap(.light)
    }

    private func closeDestinationSetup() {
        destinationNameFocused = false
        withAnimation(.easeOut(duration: 0.22)) {
            showingDestinationSetup = false
        }
        walkInput = .zero
    }

    /// 名前と期日だけを刻む。ステップも累計時間も持たせない。
    private func saveDestination() {
        guard destinationDraftIsValid else { return }
        let name = String(
            destinationNameDraft
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(60)
        )
        let destination: Destination
        if let existing = activeDestination {
            destination = existing
        } else {
            destination = Destination(name: name)
            modelContext.insert(destination)
        }
        destination.name = name
        destination.targetDate = destinationDateDraft
        destination.targetHasTime = false
        destination.steps = []
        destination.targetMinutes = nil
        destination.manual = false
        destination.manualDone = false
        destination.updatedAt = Date()
        try? modelContext.save()
        SyncService.shared.push(destination)
        Haptics.success()
        closeDestinationSetup()
    }

    private func deleteDestination() {
        guard let destination = activeDestination else { return }
        SyncService.shared.delete(destination)
        modelContext.delete(destination)
        try? modelContext.save()
        Haptics.tap(.medium)
        closeDestinationSetup()
    }

    /// 上陸は今までどおり、ホーム側の確認と着岸演出にそのまま渡す。
    private func requestDestinationLandfall() {
        guard let destination = activeDestination else { return }
        closeDestinationSetup()
        onDestinationLandfall?(destination)
    }

    /// 沖の目的地を見つめながら、名前と期日だけを決める面。
    private var destinationSetupDock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LFHomeFeatureStyle.ink)

                Text("Destinations")
                    .font(LFFont.copy(15))
                    .foregroundStyle(LFHomeFeatureStyle.ink)

                Spacer(minLength: 8)

                Button {
                    closeDestinationSetup()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LFHomeFeatureStyle.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(LFPressableButtonStyle())
                .accessibilityLabel(Text("Close"))
            }

            TextField(
                "e.g. TOEIC, finish the book",
                text: $destinationNameDraft
            )
            .font(LFFont.copy(16))
            .foregroundStyle(LFHomeFeatureStyle.ink)
            .tint(LFHomeFeatureStyle.ink)
            .focused($destinationNameFocused)
            .textInputAutocapitalization(.never)
            .submitLabel(.done)
            .onSubmit { destinationNameFocused = false }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(LFHomeFeatureStyle.field, in: Capsule())
            .overlay(Capsule().stroke(LFHomeFeatureStyle.outline, lineWidth: 1))
            .accessibilityLabel(Text("Island name"))

            DatePicker(
                selection: $destinationDateDraft,
                in: Date()...,
                displayedComponents: .date
            ) {
                Text("Target date")
                    .font(LFFont.copy(14))
                    .foregroundStyle(LFHomeFeatureStyle.ink)
            }
            .datePickerStyle(.compact)
            .tint(LFHomeFeatureStyle.ink)
            .foregroundStyle(LFHomeFeatureStyle.ink)

            Text("The island waits beyond the horizon until the final week. Over those last seven days, it draws closer day by day.")
                .font(LFFont.label(11))
                .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                saveDestination()
            } label: {
                Text("Save")
                    .font(LFFont.copy(15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        LFHomeFeatureStyle.primaryFill
                            .opacity(destinationDraftIsValid ? 1 : 0.36),
                        in: Capsule()
                    )
            }
            .buttonStyle(LFPressableButtonStyle())
            .disabled(!destinationDraftIsValid)

            if activeDestination != nil {
                HStack(spacing: 10) {
                    Button {
                        requestDestinationLandfall()
                    } label: {
                        Text("Go ashore")
                            .font(LFFont.copy(13))
                            .foregroundStyle(LFHomeFeatureStyle.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(LFHomeFeatureStyle.field, in: Capsule())
                            .overlay(Capsule().stroke(LFHomeFeatureStyle.outline, lineWidth: 1))
                    }
                    .buttonStyle(LFPressableButtonStyle())

                    Button(role: .destructive) {
                        deleteDestination()
                    } label: {
                        Text("Delete")
                            .font(LFFont.copy(13))
                            .foregroundStyle(LFColor.returnOrange)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(LFHomeFeatureStyle.field, in: Capsule())
                            .overlay(Capsule().stroke(LFHomeFeatureStyle.outline, lineWidth: 1))
                    }
                    .buttonStyle(LFPressableButtonStyle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: 440)
        .lfHomeFeatureCard()
        // 面の余白を叩いた指が、後ろの島まで抜けてカメラを動かさないように。
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
    }

    private func openVoyageNoticeBoard() {
        walkInput = .zero
        withAnimation(.easeOut(duration: 0.20)) {
            showingHarborPanel = true
        }
        Haptics.tap(.medium)
    }

    private var playerCardHUD: some View {
        HStack(spacing: compactTopHUD ? 7 : 9) {
            PlayerAvatarArt(
                styleToken: playerStyleToken,
                symbolToken: playerSymbolToken
            )
            .frame(width: playerAvatarSide, height: playerAvatarSide)
            .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))

            VStack(alignment: .leading, spacing: compactTopHUD ? 1 : 2) {
                Text(verbatim: playerDisplayName)
                    .font(LFFont.copy(compactTopHUD ? 13 : 14))
                    .foregroundStyle(homeGlassInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)

                Text(verbatim: "LV \(levelProgress.level)")
                    .font(LFFont.label(10))
                    .tracking(0.6)
                    .foregroundStyle(homeGlassInk.opacity(0.68))
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, compactTopHUD ? 6 : 7)
        .padding(.trailing, compactTopHUD ? 10 : 12)
        .frame(minWidth: compactTopHUD ? 100 : 150, maxWidth: playerCardWidth)
        .frame(height: playerCardHeight)
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

    /// Keep the shelf compact enough to show the whole tile—including its
    /// placement badge—without crowding the island view. iPad keeps the
    /// roomier size because the shelf spans the whole width there.
    private var assetTileSide: CGFloat {
        compactTopHUD ? 82 : 96
    }

    /// A little taller than it is wide so long names can still wrap cleanly.
    private var assetTileHeight: CGFloat {
        assetTileSide + 6
    }

    private var assetThumbnailSide: CGFloat {
        compactTopHUD ? 48 : 58
    }

    /// Keep the clock visible while chat is open. On compact layouts the chat
    /// spans the screen, so lift the clock above it; iPad keeps the clock on
    /// the left and the chat dock on the right.
    private var homeIslandClockBottomPadding: CGFloat {
        guard multiplayerSession != nil else { return 16 }
        // 畳んだチャットは右下の泡ひとつ。時計は左下へ戻してよい。
        if privateChatMinimized { return 16 }
        guard privateChatExpanded, horizontalSizeClass == .compact else { return 76 }
        if dynamicTypeSize.isAccessibilitySize { return 406 }
        if verticalSizeClass == .compact { return 266 }
        return 316
    }

    /// ToDo, music and the player card are glances, not destinations. They open
    /// as one small floating panel over the island instead of a sheet or a
    /// full-screen cover, so the island — and any walk in progress — stays
    /// visible behind them.
    private enum HomeUtility {
        case todo
        case music
        case player
        case brightness
    }

    private var activeUtility: HomeUtility? {
        if showingTodoList { return .todo }
        if showingMusicPicker { return .music }
        if showingPlayerStats { return .player }
        if showingIslandBrightness { return .brightness }
        return nil
    }

    private func openUtility(_ utility: HomeUtility) {
        let alreadyOpen = activeUtility == utility
        if utility == .player, !alreadyOpen { selectedRecordDay = nil }
        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
            showingTodoList = !alreadyOpen && utility == .todo
            showingMusicPicker = !alreadyOpen && utility == .music
            showingPlayerStats = !alreadyOpen && utility == .player
            showingIslandBrightness = !alreadyOpen && utility == .brightness
        }
        Haptics.tap(.light)
    }

    private func closeUtilityPanel() {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
            showingTodoList = false
            showingMusicPicker = false
            showingPlayerStats = false
            showingIslandBrightness = false
        }
        selectedRecordDay = nil
    }

    private func utilityPanelWidth(for utility: HomeUtility) -> CGFloat {
        guard compactTopHUD else { return 340 }
        // The music picker is a short list of names. On a phone it does not
        // need the width the ToDo list and the player card do, and the island
        // stays visible behind it.
        return utility == .music ? 262 : 300
    }

    @ViewBuilder
    private var homeUtilityPanel: some View {
        if let utility = activeUtility {
            GeometryReader { panelGeometry in
            ZStack(alignment: utility == .player ? .topLeading : .topTrailing) {
                // A transparent catcher, not a dimming scrim: tapping the world
                // closes the panel without the island ever being covered.
                //
                // The ToDo list is the one glance a player keeps open while
                // they walk, so its catcher is cut away over the invisible
                // thumbstick. Without the cut-out the catcher swallowed every
                // touch in that corner and the navigator stood still with the
                // list up.
                GeometryReader { proxy in
                    // Ignoring the safe area makes this reader the same
                    // rectangle the scene's own view occupies, so the region
                    // it computes lines up with the one the scene tests
                    // touches against.
                    let walkingThumb: CGRect = utility == .todo
                        ? HomeIslandTouchLayout.movementRegion(
                            in: CGRect(origin: .zero, size: proxy.size),
                            safeAreaTop: proxy.safeAreaInsets.top,
                            safeAreaBottom: proxy.safeAreaInsets.bottom
                        )
                        : .null
                    Color.black.opacity(0.001)
                        .contentShape(
                            HomeUtilityCatcherShape(cutOut: walkingThumb),
                            eoFill: true
                        )
                        .onTapGesture { closeUtilityPanel() }
                }
                .ignoresSafeArea()

                HomeUtilityPanelViewport(
                    scrolls: utility == .player,
                    maximumHeight: max(240, panelGeometry.size.height - panelGeometry.safeAreaInsets.top - panelGeometry.safeAreaInsets.bottom - 100)
                ) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: utilitySymbol(utility))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(utilityInk.opacity(0.62))
                            Text(utilityTitle(utility))
                                .font(LFFont.copy(13))
                                .foregroundStyle(utilityInk.opacity(0.72))
                            Spacer(minLength: 8)
                            Button {
                                closeUtilityPanel()
                                Haptics.tap(.light)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(utilityInk.opacity(0.6))
                                    .frame(width: 44, height: 44)
                                    .background(utilityInk.opacity(0.06), in: Circle())
                            }
                            .buttonStyle(LFPressableButtonStyle())
                            .accessibilityLabel(Text("Close"))
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 48)

                        Rectangle()
                            .fill(utilityInk.opacity(0.10))
                            .frame(height: 1)

                        Group {
                            switch utility {
                            case .todo:
                                HomeIslandTodoCompactList(store: todoStore, ink: utilityInk)
                            case .music:
                                HomeIslandMusicPanel(
                                    isEnabled: $homeMusicEnabled,
                                    selectedTrackID: $homeMusicTrack,
                                    music: homeMusic,
                                    compact: true
                                )
                            case .player:
                                HomeIslandPlayerStatsView(
                                    editingProfile: $editingPlayerProfile,
                                    sessions: studySessions,
                                    selectedDay: $selectedRecordDay,
                                    compact: true
                                )
                            case .brightness:
                                HomeIslandBrightnessControl(token: $islandBrightnessToken)
                            }
                        }
                        .padding(10)

                        if utility == .player, !editingPlayerProfile {
                            Rectangle()
                                .fill(LFHomeFeatureStyle.outline)
                                .frame(height: 1)
                                .padding(.horizontal, 16)
                            selectedDayRecords
                        }
                    }
                    .frame(width: utilityPanelWidth(for: utility))
                    .lfHomeFeatureCard(cornerRadius: 24)


                }
                .frame(width: utilityPanelWidth(for: utility), alignment: .leading)
                }
                .frame(width: utilityPanelWidth(for: utility), alignment: .top)
                .padding(utility == .player ? .leading : .trailing, compactTopHUD ? 8 : 12)
                .padding(.top, 62)
                .transition(.scale(scale: 0.94, anchor: utility == .player ? .topLeading : .topTrailing).combined(with: .opacity))
                .environment(\.colorScheme, .light)
            }
            }
        }
    }

    private var utilityInk: Color {
        LFHomeFeatureStyle.ink
    }

    /// A short timeline stays beside the island; the complete history opens
    /// with its selected day intact and owns scene interaction while visible.
    private var selectedDayRecords: some View {
        let day = selectedRecordDay ?? Calendar.current.startOfDay(for: Date())
        return VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: LF.dayWithWeekday(day))
                .font(LFFont.label(12))
                .foregroundStyle(LFHomeFeatureStyle.ink)
            Button {
                walkInput = .zero
                showingPlayerStats = false
                editingPlayerProfile = false
                showingWorkRecords = true
            } label: {
                Label("Open work history", systemImage: "clock.arrow.circlepath")
                    .font(LFFont.label(12))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(LFPressableButtonStyle())
            .foregroundStyle(LFHomeFeatureStyle.ink)
            WorkRecordTimelineView(sessions: studySessions, day: day, maxEntries: 3)
        }
        .padding(16)
    }

    private func utilityTitle(_ utility: HomeUtility) -> LocalizedStringKey {
        switch utility {
        case .todo: "ToDo"
        case .music: "Music"
        case .player: "Voyage record"
        case .brightness: "Island brightness"
        }
    }

    private func utilitySymbol(_ utility: HomeUtility) -> String {
        switch utility {
        case .todo: "checklist"
        case .music: "music.note"
        case .player: "person.crop.circle"
        case .brightness: "sun.max"
        }
    }

    /// The name card yields a little width on a narrow phone, while each
    /// control keeps a full 44-point target. Four actions and a 112-point
    /// name card fit together even in a 320-point viewport.
    private var playerCardWidth: CGFloat {
        compactTopHUD ? 124 : 178
    }

    private var playerCardHeight: CGFloat {
        50
    }

    private var playerAvatarSide: CGFloat {
        compactTopHUD ? 28 : 32
    }

    private var topControlWidth: CGFloat {
        44
    }

    /// Match the control capsule's six points of padding to the name card.
    private var topControlHeight: CGFloat {
        playerCardHeight - 6
    }

    private var topControlSymbolSize: CGFloat {
        16
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
                Text("Ship")
                    .font(LFFont.label(11))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.58))
                Spacer(minLength: 8)
                Text(ShipCatalog.design(id: selectedBoatShipID).title)
                    .font(LFFont.copy(13))
                    .foregroundStyle(Color(uiColor: VoyageSceneKit.sand))
            }

            HStack(spacing: 7) {
                ForEach(ShipCatalog.all) { ship in
                    boatShipButton(ship)
                }
            }

            Divider()
                .overlay(.white.opacity(0.12))

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
        .accessibilityLabel(Text("Your boat"))
    }

    private func boatShipButton(_ ship: ShipDesign) -> some View {
        let selected = selectedBoatShipID == ship.id
        let lockReason = ShipUnlockPolicy.lockReason(
            requiredLevel: ship.unlockLevel,
            requiresVoyagePass: ship.requiresVoyagePass,
            playerLevel: levelProgress.level,
            hasVoyagePass: voyagePass.isActive,
            alreadySelected: selected
        )
        let unlocked = lockReason == nil
        return Button {
            selectBoatShip(ship, lockReason: lockReason)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: unlocked ? ship.symbolName : "lock.fill")
                    .font(.system(size: unlocked ? 13 : 10, weight: .semibold))
                Text(ship.title)
                    .font(LFFont.copy(12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                if !unlocked {
                    Text(verbatim: lockReason == .voyagePass ? "PASS" : "LV\(ship.unlockLevel)")
                        .font(LFFont.label(9))
                }
            }
            .foregroundStyle(selected ? LFColor.midnight : .white.opacity(unlocked ? 0.82 : 0.48))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                selected ? Color(uiColor: VoyageSceneKit.sand) : .white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(
                        selected ? Color(uiColor: VoyageSceneKit.sand) : .white.opacity(0.13),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(LFPressableButtonStyle(scale: 0.96))
        .accessibilityLabel(Text(ship.title))
        .accessibilityHint(
            unlocked
                ? Text(ship.summary)
                : shipLockText(ship)
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
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

    /// いま着ている色。証が切れているあいだは、選んだ色を残したまま既定へ戻す。
    private var effectiveNavColor: NavigatorColorOption {
        let option = NavigatorCustomization.colors.first { $0.id == selectedNavColorID }
            ?? NavigatorCustomization.colors[0]
        guard option.requiresPass, !voyagePass.isActive else { return option }
        return NavigatorCustomization.colors[0]
    }

    /// 航海士を触ったときの小さな色替え。船のドックのように画面は奪わず、
    /// 歩きながらでも閉じられる一段だけを足元へ出す。
    private var navigatorColorDock: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Navigator color")
                    .font(LFFont.label(11))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.58))
                Spacer(minLength: 8)
                Text(effectiveNavColor.title)
                    .font(LFFont.copy(13))
                    .foregroundStyle(Color(uiColor: VoyageSceneKit.sand))
                Button {
                    closeNavigatorColors()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(LFPressableButtonStyle())
                .accessibilityLabel(Text("Close"))
            }

            HStack(spacing: 6) {
                ForEach(NavigatorCustomization.colors) { option in
                    navigatorColorButton(option)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 360)
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
        .safeAreaPadding(.bottom, navigatorColorDockBottomPadding)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Navigator color"))
    }

    /// 誰かの島にいる間は足元にチャットの段(畳んでいれば泡)が居座る。色替えは
    /// その一段上に座らせて、どちらも押せるようにする。
    private var navigatorColorDockBottomPadding: CGFloat {
        multiplayerSession == nil ? 8 : 66
    }

    /// 既定のコーラル以外は航海証で開く。鍵つきの色も並べ、押すと航海証へ渡す。
    private func navigatorColorButton(_ option: NavigatorColorOption) -> some View {
        let locked = option.requiresPass && !voyagePass.isActive
        let selected = effectiveNavColor.id == option.id
        return Button {
            selectNavigatorColor(option, locked: locked)
        } label: {
            ZStack {
                Circle()
                    .fill(option.swatch)
                    .frame(width: 32, height: 32)
                    .opacity(locked ? 0.42 : 1)
                    .shadow(
                        color: selected ? option.swatch.opacity(0.55) : .clear,
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
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(uiColor: VoyageSceneKit.sand))
                        .padding(3)
                        .background(.black.opacity(0.72), in: Circle())
                        .offset(x: 12, y: 11)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(LFPressableButtonStyle(scale: 0.94))
        .accessibilityLabel(Text(option.title))
        .accessibilityHint(locked ? Text("Opens with a Voyage Pass") : Text(""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggleNavigatorColors() {
        guard mode == .explore, !showingBoatCustomization, !showingDestinationSetup else { return }
        if showingNavigatorColors {
            closeNavigatorColors()
            return
        }
        walkInput = .zero
        selectedNavColorID = NavigatorCustomization.selectedID
        withAnimation(.easeOut(duration: 0.22)) {
            showingNavigatorColors = true
        }
        Haptics.tap(.medium)
    }

    private func closeNavigatorColors() {
        guard showingNavigatorColors else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            showingNavigatorColors = false
        }
        Haptics.tap(.light)
    }

    private func selectNavigatorColor(_ option: NavigatorColorOption, locked: Bool) {
        guard !locked else {
            walkInput = .zero
            showingVoyagePass = true
            Haptics.tap(.medium)
            return
        }
        guard selectedNavColorID != option.id else { return }
        NavigatorCustomization.select(option.id)
        selectedNavColorID = option.id
        Haptics.tap(.light)
    }

    private func enterBoatCustomization() {
        guard mode == .explore,
              !showingBoatCustomization,
              multiplayerSession?.isReadOnly != true
        else { return }
        walkInput = .zero
        showingNavigatorColors = false
        selectedBoatSailID = BoatCustomization.selectedSailID
        selectedBoatShipID = BoatCustomization.effectiveSelectedShipID
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

    private func selectBoatShip(
        _ ship: ShipDesign,
        lockReason: ShipUnlockPolicy.LockReason?
    ) {
        if lockReason == .voyagePass {
            walkInput = .zero
            showingVoyagePass = true
            Haptics.tap(.medium)
            return
        }
        guard lockReason == nil else {
            Haptics.error()
            return
        }
        guard selectedBoatShipID != ship.id else { return }
        BoatCustomization.selectShip(ship.id)
        selectedBoatShipID = BoatCustomization.effectiveSelectedShipID
        Haptics.tap(.light)
        Task { await PrivateIslandService.shared.publishProfileToJoinedIslands() }
        PublicHarborService.shared.pushProfile()
    }

    private func shipLockText(_ ship: ShipDesign) -> Text {
        if ship.requiresVoyagePass, !voyagePass.isActive {
            return Text("Opens with a Voyage Pass")
        }
        return Text(verbatim: LF.format("Unlocks at Level %lld", Int64(ship.unlockLevel)))
    }

    private var cameraExposureValueText: String {
        let value = abs(cameraExposureOffset) < 0.025 ? 0 : cameraExposureOffset
        return String(format: "%+.2f EV", value)
    }

    private var cameraCaptureControls: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Menu {
                    Button("Whole island", systemImage: "globe.asia.australia") {
                        sendCameraAction(.frameIsland)
                    }
                    Button("Main character", systemImage: "person.crop.rectangle") {
                        sendCameraAction(.frameNavigator)
                    }
                    Button("Jetty", systemImage: "water.waves") {
                        sendCameraAction(.frameJetty)
                    }
                } label: {
                    Label("Frame subject", systemImage: "viewfinder")
                        .font(LFFont.label(12))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 116, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Frame subject"))

                Rectangle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 1, height: 20)
                    .accessibilityHidden(true)

                Button {
                    showingCameraCompositionGuide.toggle()
                    Haptics.tap(.light)
                } label: {
                    Label("Thirds grid", systemImage: "grid")
                        .font(LFFont.label(12))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 116, height: 44)
                        .background(
                            .white.opacity(showingCameraCompositionGuide ? 0.16 : 0),
                            in: Capsule()
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(LFPressableButtonStyle())
                .accessibilityAddTraits(showingCameraCompositionGuide ? .isSelected : [])
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.black.opacity(0.52), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.13), lineWidth: 1))
            .disabled(isCapturing)

            if showingCameraExposureControl {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Text("Exposure")
                                .font(LFFont.label(12))
                            Text(verbatim: cameraExposureValueText)
                                .font(LFFont.copy(14))
                                .monospacedDigit()
                                .fixedSize()
                        }
                        .accessibilityElement(children: .combine)
                        Spacer(minLength: 0)
                        Button {
                            cameraExposureOffset = 0
                            Haptics.tap(.light)
                        } label: {
                            Text("Reset")
                                .font(LFFont.label(12))
                                .fontWeight(.semibold)
                                .padding(.horizontal, 10)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(LFPressableButtonStyle())
                        .accessibilityLabel(Text("Exposure") + Text(" · ") + Text("Reset"))
                        .accessibilityValue(Text(verbatim: "0 EV"))
                        .disabled(abs(cameraExposureOffset) < 0.025)
                        .opacity(abs(cameraExposureOffset) < 0.025 ? 0.4 : 1)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "sun.min")
                            .accessibilityHidden(true)
                        Slider(value: $cameraExposureOffset, in: -1.2...0.8, step: 0.05) {
                            Text("Exposure")
                        }
                        .tint(.white)
                        .accessibilityValue(Text(verbatim: cameraExposureValueText))
                        Image(systemName: "sun.max.fill")
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 15)
                .padding(.vertical, 4)
                .frame(width: 280)
                .background(.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.13), lineWidth: 1))
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
                .accessibilityAddTraits(showingCameraExposureControl ? .isSelected : [])
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
            Image(systemName: "sailboat.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(uiColor: VoyageSceneKit.sand))
            Text(verbatim: LF.format("Approaching %@…", arrivalIslandName))
                .font(LFFont.label(12))
                .foregroundStyle(.white.opacity(0.84))
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(.black.opacity(0.42), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.13), lineWidth: 1))
        .allowsHitTesting(false)
    }

    /// A guest is sailing toward the room owner's island, not the island name
    /// stored on this device. The local name remains correct for solo arrivals.
    private var arrivalIslandName: String {
        guard let multiplayerSession, multiplayerSession.isReadOnly else {
            return PlayerProfile.islandName
        }
        return multiplayerSession.room.name
    }

    private var saveFailureHint: some View {
        hintPill(
            symbol: "exclamationmark.triangle.fill",
            text: LF.text("Island changes could not be saved"),
            actionTitle: LF.text("Retry")
        ) {
            store.save()
            Haptics.tap(.medium)
        }
    }

    private func noticePill(symbol: String, text: String) -> some View {
        HStack(spacing: compactTopHUD ? 6 : 8) {
            Image(systemName: symbol)
                .font(.system(size: compactTopHUD ? 12 : 14))
                .foregroundStyle(homeGlassInk)
            Text(verbatim: text)
                .font(LFFont.label(compactTopHUD ? 11 : 12))
                .foregroundStyle(homeGlassInk)
        }
        .padding(.horizontal, compactTopHUD ? 11 : 13)
        .frame(height: compactTopHUD ? 31 : 36)
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
        showingIslandResetConfirm = false
        lockedAssetID = nil
        showingBoatCustomization = false
        store.replaceRemoteSnapshot(resolvedSnapshot)
    }

    private func beginDeparture() {
        guard mode == .explore else { return }
        privateChatExpanded = false
        privateChatInputFocused = false
        showingBoatCustomization = false
        showingNavigatorColors = false
        showingDestinationSetup = false
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

    private func finishArrival() {
        guard mode == .arrival else { return }
        withAnimation(.easeOut(duration: 0.28)) {
            mode = .explore
        }
        Haptics.tap(.medium)
        onEmbeddedArrivalCompleted()
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

    /// The palette selection survives a placement so a grove can be planted
    /// tap by tap; it steps aside only once the allowance is used up.
    private func finishPlacement(_ placementID: UUID) {
        if let placement = store.placements.first(where: { $0.id == placementID }) {
            catalogPreferences.recordPlacement(assetID: placement.assetID)
        }
        movingSelection = false
        showingSizeControls = allowsAssetSizeCalibration
        if let assetID = placementAssetID, !store.canAdd(assetID: assetID) {
            placementAssetID = nil
        }
    }

    /// Every refusal says what it actually was. They used to share one line,
    /// which read as "you may not overlap that" even where overlap is fine.
    private func reportPlacementRejection(_ reason: HomeIslandPlacementRejection) {
        let notice: String
        switch reason {
        case .reserved:
            notice = LF.text("This spot is kept clear")
        case .limitReached:
            notice = LF.text("You have placed all of these")
        case .outsideBuildArea:
            notice = LF.text("Keep the asset inside the sandy build area")
        case .coastRequired:
            notice = LF.text("Place the jetty along the island edge")
        }
        showTransientNotice(notice)
    }

    /// Tapping a prop in explore mode: the board opens the harbors, a building
    /// is entered, and the campfire opens the logbook.
    private func activateAsset(_ assetID: String) {
        // A long press in build mode arrives here as `carry:<uuid>`: the scene
        // reports it through this channel rather than a separate callback,
        // which the scene initializer no longer has room for.
        if assetID.hasPrefix("carry:"),
           let placementID = UUID(uuidString: String(assetID.dropFirst(6))) {
            beginCarrying(placementID)
            return
        }
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
    }

    /// A long press on a prop selects it. The drag that follows moves it, as
    /// does any drag that starts on a prop — there is no mode to enter.
    private func beginCarrying(_ placementID: UUID) {
        placementAssetID = nil
        store.select(placementID)
    }

    /// Shown once per visit to build mode. The camera controls are invisible
    /// by design, so they have to be said out loud at least once.
    private func announceBuildControls() {
        showTransientNotice(
            LF.text("Drag an asset to move it · drag elsewhere to turn · pinch to zoom")
        )
    }

    private func enterEditMode() {
        guard canEditIsland else { return }
        showingBoatCustomization = false
        showingDestinationSetup = false
        walkInput = .zero
        withAnimation(.easeOut(duration: 0.22)) {
            mode = .edit
        }
        announceBuildControls()
        Haptics.tap(.light)
    }

    private func enterCameraMode() {
        showingBoatCustomization = false
        showingDestinationSetup = false
        isCapturing = false
        captureRequest = nil
        cameraExposureOffset = 0
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
            capturedAt: capturedAt,
            brightness: islandBrightness
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
            let announcement = LF.text(didSave ? "Photo saved" : "Photo could not be saved")
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
    }

    private func enterExploreMode() {
        showingBoatCustomization = false
        showingDestinationSetup = false
        placementAssetID = nil
        expandedFamilyID = nil
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
                actionTitle: LF.text("OK")
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
                    : LF.text("The island has reached its object limit"),
                actionTitle: LF.text("OK")
            ) {
                self.lockedAssetID = nil
            }
        } else if let placementAssetID,
           let asset = HomeIslandAssetCatalog.asset(id: placementAssetID) {
            hintPill(
                symbol: placementAssetID == "wooden_jetty" ? "water.waves" : "hand.tap.fill",
                text: placementAssetID == "wooden_jetty"
                    ? LF.text("Tap the island edge to extend the jetty toward the sea")
                    : LF.format("Tap once on the sand to place %@", asset.title),
                actionTitle: LF.text("Cancel")
            ) {
                self.placementAssetID = nil
            }
        } else if movingSelection {
            // 指を離せばその場で決まる。取り消すものがないので、この丸には
            // ボタンを置かない。
            hintPill(
                symbol: placementMoveBlocked
                    ? "exclamationmark.triangle.fill"
                    : "arrow.up.and.down.and.arrow.left.and.right",
                text: LF.text(placementMoveBlocked
                    ? "That way is closed — slide to open ground"
                    : "Release to place it here")
            )
        } else if store.selectedPlacement != nil {
            hintPill(
                symbol: "hand.draw.fill",
                text: LF.text("Drag an asset to move it · release to place")
            )
        }
    }

    private func hintPill(
        symbol: String,
        text: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LFHomeFeatureStyle.ink)
                .accessibilityHidden(true)

            Text(verbatim: text)
                .font(LFFont.label(12))
                .foregroundStyle(LFHomeFeatureStyle.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(verbatim: actionTitle)
                        .font(LFFont.copy(12))
                        .foregroundStyle(LFHomeFeatureStyle.ink)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(LFHomeFeatureStyle.field, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(LFPressableButtonStyle())
                .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, action == nil ? 12 : 5)
        .frame(minHeight: 44)
        .lfHomeFeatureCard(cornerRadius: 22)
        .padding(.horizontal, 12)
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
                    .background(LFHomeFeatureStyle.field, in: RoundedRectangle(cornerRadius: 12))

                Text(verbatim: asset.title)
                    .font(LFFont.copy(13))
                    .foregroundStyle(LFHomeFeatureStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: 64, alignment: .leading)

                toolButton("Rotate", symbol: "rotate.right") {
                    store.rotateSelected()
                }
                .disabled(selected.assetID == "wooden_jetty")
                .opacity(selected.assetID == "wooden_jetty" ? 0.34 : 1)
                .accessibilityHint(Text("Rotates 15 degrees clockwise"))
                toolButton("Align", symbol: "align.horizontal.center", active: placementAssistanceEnabled) {
                    placementAssistanceEnabled.toggle()
                }
                .accessibilityLabel(Text("Placement assistance"))
                .accessibilityValue(Text(placementAssistanceEnabled ? "On" : "Off"))
                .accessibilityHint(Text("Gently aligns nearby props while moving"))
                if allowsAssetSizeCalibration {
                    toolButton(
                        "Size",
                        symbol: "arrow.up.left.and.arrow.down.right",
                        active: showingSizeControls
                    ) {
                        movingSelection = false
                        showingSizeControls.toggle()
                    }
                }

                Button {
                    movingSelection = false
                    showingSelectionActions = true
                    Haptics.tap(.light)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(LFHomeFeatureStyle.ink)
                        .frame(width: 44, height: 50)
                        .background(LFHomeFeatureStyle.field, in: RoundedRectangle(cornerRadius: 12))
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
                        .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
                        .frame(width: 44, height: 50)
                }
                .buttonStyle(LFPressableButtonStyle())
                .accessibilityLabel(Text("Clear selection"))
            }
            .padding(7)
            .lfHomeFeatureCard(cornerRadius: 19)
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
                    .font(LFFont.label(10))
                    .lineLimit(1)
            }
            .foregroundStyle(LFHomeFeatureStyle.ink)
            .frame(width: 44, height: 50)
            .background(
                active
                    ? LFHomeFeatureStyle.ink.opacity(0.14)
                    : LFHomeFeatureStyle.field,
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
            placementMoveBlocked = false
            Haptics.tap(.medium)
        }
        showingSizeControls = false
    }

    /// 島を更地に戻す。置いたものは減るわけではないので、取り除くだけで
    /// また好きに置き直せる。取り消しは一手で効くので、その旨も伝える。
    private func clearIsland() {
        guard !store.placements.isEmpty else { return }
        store.removeAllPlacements()
        placementAssetID = nil
        movingSelection = false
        showingSizeControls = false
        placementMoveBlocked = false
        lockedAssetID = nil
        showTransientNotice(LF.text("The island is clear · Undo is available"))
        Haptics.tap(.heavy)
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
                        .frame(width: 44, height: 44)
                        .background(LFHomeFeatureStyle.field, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(LFPressableButtonStyle())
                .disabled(selected.transform.scale <= 0.25)
                .accessibilityLabel(Text("Smaller"))

                VStack(spacing: 1) {
                    Text("Size")
                        .font(LFFont.label(10))
                        .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
                    Text(
                        verbatim: "\(calibrationScalePercent(for: selected))%"
                    )
                        .font(LFFont.copy(15))
                        .foregroundStyle(LFHomeFeatureStyle.ink)
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
                        .frame(width: 44, height: 44)
                        .background(LFHomeFeatureStyle.field, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(LFPressableButtonStyle())
                .disabled(selected.transform.scale >= 2)
                .accessibilityLabel(Text("Larger"))
            }
            .foregroundStyle(LFHomeFeatureStyle.ink)
            .padding(6)
            .lfHomeFeatureCard(cornerRadius: 17)
        }
    }

    private func commitIslandSwitch() {
        guard let index = pendingIslandSwitch else { return }
        pendingIslandSwitch = nil
        guard index != islandSlots.effectiveIndex else { return }
        // Leave build mode: the props on screen belong to the island being
        // left, and the scene is about to be rebuilt from the other one.
        placementAssetID = nil
        movingSelection = false
        lockedAssetID = nil
        store.select(nil)
        islandSlots.activate(index)
    }

    private var islandSlotsCloseButton: some View {
        Button {
            showingIslandSlots = false
            Haptics.tap(.light)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.66))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.08), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(LFPressableButtonStyle())
        .padding(.trailing, 18)
        .padding(.top, 8)
        .accessibilityLabel(Text("Close"))
    }

    /// Which island is being built on, next to the word Build. Switching saves
    /// belongs in the same place as placing props, not in Settings: this is the
    /// only screen where the difference between two islands is visible.
    private var islandSlotChip: some View {
        Button {
            islandSlots.refresh()
            showingIslandSlots = true
            Haptics.tap(.light)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text(LF.format("Island %lld", Int64(islandSlots.effectiveIndex)))
                    .font(LFFont.label(10))
            }
            .foregroundStyle(LFHomeFeatureStyle.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(LFHomeFeatureStyle.field, in: Capsule())
            .overlay(Capsule().stroke(LFHomeFeatureStyle.outline, lineWidth: 1))
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityHint(Text("Sail to this island"))
    }

    private var assetShelf: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("Build")
                    .font(LFFont.copy(13))
                    .foregroundStyle(LFHomeFeatureStyle.ink)
                islandSlotChip
                Spacer(minLength: 0)
                catalogScopeMenu
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        showingCatalogSearch.toggle()
                        if !showingCatalogSearch { catalogQuery = "" }
                    }
                    Haptics.tap(.light)
                } label: {
                    Image(systemName: showingCatalogSearch ? "xmark" : "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LFHomeFeatureStyle.ink)
                        .frame(width: 44, height: 44)
                        .background(LFHomeFeatureStyle.field, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(LFPressableButtonStyle())
                .accessibilityLabel(Text(showingCatalogSearch ? "Close search" : "Search item names"))
            }

            if showingCatalogSearch {
                HomeIslandCatalogSearchField(query: $catalogQuery)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(HomeIslandAssetCategory.allCases) { category in
                        categoryButton(category)
                    }
                }
            }

            if let family = expandedFamily {
                assetVariantRow(family)
                    .transition(
                        .move(edge: .bottom)
                            .combined(with: .opacity)
                    )
            }

            Group {
                if visibleShelfEntries.isEmpty {
                    catalogEmptyState
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        // Keep thumbnails lazy as search and shortcuts change.
                        LazyHStack(spacing: 10) {
                            ForEach(visibleShelfEntries) { entry in
                                assetButton(entry.asset, family: entry.family)
                            }
                        }
                    }
                }
            }
            // A lazy stack has no intrinsic height, so without this the shelf
            // grew to fill the screen and painted its backdrop over the island.
            .frame(height: assetTileHeight)
        }
        .padding(.horizontal, 13)
        .padding(.top, 10)
        .padding(.bottom, 7)
        .background(LFHomeFeatureStyle.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LFHomeFeatureStyle.outline)
                .frame(height: 1)
        }
        .safeAreaPadding(.bottom, 3)
        .onChange(of: catalogQuery) { _, _ in expandedFamilyID = nil }
        .onChange(of: catalogScope) { _, _ in expandedFamilyID = nil }
    }

    private var catalogScopeMenu: some View {
        Menu {
            Picker("Catalog filter", selection: $catalogScope) {
                ForEach(HomeIslandCatalogScope.allCases) { scope in
                    Label(LocalizedStringKey(scope.titleKey), systemImage: scope.symbol)
                        .tag(scope)
                }
            }
            if catalogFiltersActive {
                Button("Reset filters", action: resetCatalogFilters)
            }
        } label: {
            Label(LocalizedStringKey(catalogScope.titleKey), systemImage: catalogScope.symbol)
                .font(LFFont.label(11))
                .foregroundStyle(LFHomeFeatureStyle.ink)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(LFHomeFeatureStyle.field, in: Capsule())
                .contentShape(Capsule())
        }
        .tint(LFHomeFeatureStyle.ink)
        .menuIndicator(.hidden)
        .accessibilityLabel(Text("Catalog filter"))
        .accessibilityValue(Text(LocalizedStringKey(catalogScope.titleKey)))
    }

    private var catalogFiltersActive: Bool {
        catalogScope != .all || selectedAssetCategory != .all
            || !catalogQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var catalogEmptyState: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("No matching items")
                    .font(LFFont.copy(13))
                    .foregroundStyle(LFHomeFeatureStyle.ink)
                Text(catalogScope == .favorites && catalogPreferences.favoriteIDs.isEmpty
                     ? "Touch and hold an item to add it to favorites."
                     : catalogScope == .recent && catalogPreferences.recentIDs.isEmpty
                     ? "Items appear here after you place them."
                     : "Try another name or reset the filters.")
                    .font(LFFont.label(11))
                    .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Reset filters", action: resetCatalogFilters)
                .font(LFFont.copy(12))
                .foregroundStyle(LFHomeFeatureStyle.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(LFHomeFeatureStyle.field, in: Capsule())
                .buttonStyle(LFPressableButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func resetCatalogFilters() {
        catalogQuery = ""
        catalogScope = .all
        selectedAssetCategoryToken = HomeIslandAssetCategory.all.rawValue
        expandedFamilyID = nil
        Haptics.tap(.light)
    }

    private func assetButton(
        _ asset: HomeIslandAsset,
        family: HomeIslandAssetFamily? = nil
    ) -> some View {
        let selected = placementAssetID == asset.id
        let expanded = expandedFamilyID == family?.id
        let unlocked = HomeIslandAssetCatalog.isUnlocked(
            asset,
            playerLevel: levelProgress.level
        )
        let placedCount = store.placementCount(assetID: asset.id)
        let placementLimit = HomeIslandAssetCatalog.placementLimit(for: asset.id)
        let atLimit = placedCount >= placementLimit
        let passLocked = isPassLocked(asset)
        // Nothing but the pass stands in the way, so this tile can hand the
        // player the Voyage Pass instead of only refusing them.
        let awaitsPass = passLocked && unlocked && !atLimit && store.canAdd
        let canPlace = unlocked && !passLocked && !atLimit && store.canAdd
        return Button {
            // A prop that comes in several opens its row first. Tapping it
            // again shuts the row: a tile that only ever opened something
            // would be a trap on a shelf the player is scrolling through.
            if let family, family.variants.count > 1 {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    expandedFamilyID = expanded ? nil : family.id
                }
                Haptics.tap(.light)
                return
            }
            expandedFamilyID = nil
            selectBuildAsset(asset, canPlace: canPlace, opensVoyagePass: awaitsPass)
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .bottomTrailing) {
                    HomeIslandAssetThumbnail(
                        assetID: asset.id,
                        fallbackSymbol: asset.symbolName
                    )
                        .opacity(canPlace ? 1 : 0.38)
                        .frame(width: assetThumbnailSide, height: assetThumbnailSide)
                        .background(
                            LFHomeFeatureStyle.ink.opacity(selected ? 0.12 : 0.055),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                    assetCornerMarker(
                        unlocked: unlocked,
                        passLocked: passLocked,
                        atLimit: atLimit
                    )
                }
                Text(verbatim: family?.title ?? asset.title)
                    .font(LFFont.label(10))
                    .foregroundStyle(
                        LFHomeFeatureStyle.ink.opacity(canPlace ? (selected ? 1 : 0.76) : 0.34)
                    )
                    .multilineTextAlignment(.center)
                    // A family name is short by design, so it keeps to one
                    // line and leaves the row below for the variant.
                    .lineLimit(family == nil ? 2 : 1)
                    .minimumScaleFactor(0.78)
                if let family, family.variants.count > 1 {
                    // The dots say "this one comes in several"; the name says
                    // which one is loaded. Without the name a player who picked
                    // pink had only a ringed dot and the thumbnail to go on, and
                    // on a shelf that scrolls past that is not an answer to
                    // "what am I about to place?".
                    HStack(spacing: 4) {
                        if family.showsSwatches {
                            HStack(spacing: 3) {
                                ForEach(family.variants) { variant in
                                    let current = variant.assetID == asset.id
                                    Circle()
                                        .fill(Color(uiColor: UIColor(rgb: variant.swatch ?? 0)))
                                        .frame(width: current ? 6 : 5, height: current ? 6 : 5)
                                        .overlay {
                                            Circle()
                                                .stroke(
                                                    LFHomeFeatureStyle.ink.opacity(current ? 0.82 : 0.22),
                                                    lineWidth: 1
                                                )
                                        }
                                }
                            }
                        } else {
                            // A family of shapes has nothing to paint dots
                            // with, so the arrow carries the same promise:
                            // there is more than one of these under the tile.
                            Image(systemName: "chevron.down")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(
                                    LFHomeFeatureStyle.ink.opacity(selected ? 0.8 : 0.5)
                                )
                        }
                        if let variant = family.variants.first(where: { $0.assetID == asset.id }) {
                            Text(verbatim: variant.name)
                                .font(LFFont.label(8))
                                .foregroundStyle(
                                    LFHomeFeatureStyle.ink.opacity(
                                        canPlace ? (selected ? 0.92 : 0.58) : 0.3
                                    )
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .opacity(canPlace ? 1 : 0.4)
                }
            }
            .padding(5)
            .frame(width: assetTileSide, height: assetTileHeight)
            .background(
                selected || expanded
                    ? LFHomeFeatureStyle.ink.opacity(selected ? 0.13 : 0.08)
                    : LFHomeFeatureStyle.field.opacity(canPlace ? 1 : 0.46),
                in: RoundedRectangle(cornerRadius: 15)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(
                        selected || expanded
                            ? LFHomeFeatureStyle.ink.opacity(selected ? 0.48 : 0.30)
                            : LFHomeFeatureStyle.outline,
                        lineWidth: 1
                    )
            }
            .overlay(alignment: .topTrailing) {
                assetTagText(
                    asset,
                    unlocked: unlocked,
                    passLocked: passLocked,
                    placedCount: placedCount,
                    placementLimit: placementLimit
                )
                    .font(LFFont.label(7))
                    .monospacedDigit()
                    .foregroundStyle(
                        passLocked ? LFColor.returnOrange : Color.white.opacity(0.84)
                    )
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(LFHomeFeatureStyle.ink.opacity(0.92), in: Capsule())
                    // Keep the whole badge inside the tile. A negative top
                    // offset looked clipped by the horizontal scroll view.
                    .offset(x: -4, y: 4)
            }
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityLabel(Text(verbatim: family.map { _ in asset.title } ?? asset.title))
        .accessibilityValue(
            assetTagText(
                asset,
                unlocked: unlocked,
                passLocked: passLocked,
                placedCount: placedCount,
                placementLimit: placementLimit
            )
        )
        .accessibilityHint(
            assetHintText(
                asset,
                unlocked: unlocked,
                passLocked: passLocked,
                atLimit: atLimit
            )
        )
        .modifier(HomeIslandCatalogFavoriteModifier(assetID: asset.id, preferences: catalogPreferences))
    }

    /// 航海証で開く飾り。レベルの鍵と違って証は切れるので、これは「これから
    /// 置くとき」だけの判定。すでに島にあるものには一切かからない。
    private func isPassLocked(_ asset: HomeIslandAsset) -> Bool {
        HomeIslandAssetCatalog.isPassLocked(asset, hasVoyagePass: voyagePass.isActive)
    }

    /// 鍵つきの色と同じ渡し方。証で開く飾りは、黙って弾かずに航海証を開く。
    private func selectBuildAsset(
        _ asset: HomeIslandAsset,
        canPlace: Bool,
        opensVoyagePass: Bool
    ) {
        guard canPlace else {
            placementAssetID = nil
            movingSelection = false
            if opensVoyagePass {
                lockedAssetID = nil
                showingVoyagePass = true
            } else {
                lockedAssetID = asset.id
            }
            Haptics.tap(.medium)
            return
        }
        lockedAssetID = nil
        placementAssetID = placementAssetID == asset.id ? nil : asset.id
        store.select(nil)
        Haptics.tap(.light)
    }

    @ViewBuilder
    private func assetCornerMarker(
        unlocked: Bool,
        passLocked: Bool,
        atLimit: Bool
    ) -> some View {
        if !unlocked || passLocked {
            Image(systemName: "lock.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(passLocked ? LFColor.returnOrange : .white)
                .padding(3)
                .background(LFHomeFeatureStyle.ink.opacity(0.94), in: Circle())
                .offset(x: 3, y: 3)
        } else if atLimit {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .padding(3)
                .background(LFHomeFeatureStyle.ink, in: Circle())
                .offset(x: 3, y: 3)
        }
    }

    /// Level is the nearer gate, so a prop still below its level says so
    /// first; once that is met a pass-exclusive prop names the pass instead
    /// of a count.
    private func assetTagText(
        _ asset: HomeIslandAsset,
        unlocked: Bool,
        passLocked: Bool,
        placedCount: Int,
        placementLimit: Int
    ) -> Text {
        if !unlocked {
            return Text(verbatim: "LV\(asset.unlockLevel)")
        }
        if passLocked {
            return Text("Voyage Pass")
        }
        return Text(verbatim: "\(placedCount)/\(placementLimit)")
    }

    private func assetTagTint(unlocked: Bool, passLocked: Bool) -> Color {
        if !unlocked {
            return LFHomeFeatureStyle.secondaryInk
        }
        return passLocked ? LFColor.returnOrange : LFHomeFeatureStyle.secondaryInk
    }

    private func assetHintText(
        _ asset: HomeIslandAsset,
        unlocked: Bool,
        passLocked: Bool,
        atLimit: Bool
    ) -> Text {
        if atLimit {
            return Text("Placement limit reached")
        }
        if !unlocked {
            return Text(verbatim: LF.format("Unlocks at Level %lld", Int64(asset.unlockLevel)))
        }
        if passLocked {
            return Text("Opens with a Voyage Pass")
        }
        if asset.id == "wooden_jetty" {
            return Text("Place only at the island edge; it automatically faces the sea")
        }
        return Text("Tap the sand to place this asset")
    }

    private var selectedAssetCategory: HomeIslandAssetCategory {
        HomeIslandAssetCategory(rawValue: selectedAssetCategoryToken) ?? .all
    }

    /// どの引き出しでも並びは「いま置けるか」で三段に分かれる。
    ///
    /// 0 = 今日置けるもの。1 = 続けていれば開くもの。2 = 航海証で開くもの。
    /// 証は買わないと開かない鍵なので、レベルの鍵より後ろへ置く。棚の先頭を
    /// 占めるのは、いつでも手に取れるものだけにしたい。
    private func assetOrderTier(_ asset: HomeIslandAsset) -> Int {
        if isPassLocked(asset) { return 2 }
        return HomeIslandAssetCatalog.isUnlocked(
            asset,
            playerLevel: levelProgress.level
        ) ? 0 : 1
    }

    /// 段のなかは、カタログに書いた順(=種類ごとのまとまり)のまま。ただし
    /// 「これから開く」段だけは近いレベルから並べる。次に何が来るのかが
    /// 一覧の頭に出るほうが、まとまりよりも役に立つ。
    ///
    /// 並べ替えの最後にカタログ順を必ず見るので、同点の並びは毎回同じになる。
    private var visibleAssets: [HomeIslandAsset] {
        assets
            .filter(matchesCatalogAsset)
            .enumerated()
            .sorted { lhs, rhs in
                if catalogScope == .recent {
                    let lhsRank = catalogPreferences.recentIDs.firstIndex(of: lhs.element.id) ?? Int.max
                    let rhsRank = catalogPreferences.recentIDs.firstIndex(of: rhs.element.id) ?? Int.max
                    if lhsRank != rhsRank { return lhsRank < rhsRank }
                }
                let lhsTier = assetOrderTier(lhs.element)
                let rhsTier = assetOrderTier(rhs.element)
                if lhsTier != rhsTier { return lhsTier < rhsTier }
                if lhsTier == 1, lhs.element.unlockLevel != rhs.element.unlockLevel {
                    return lhs.element.unlockLevel < rhs.element.unlockLevel
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private func matchesCatalogAsset(_ asset: HomeIslandAsset) -> Bool {
        guard selectedAssetCategory.contains(asset.id) else { return false }
        switch catalogScope {
        case .all: break
        case .favorites:
            guard catalogPreferences.favoriteIDs.contains(asset.id) else { return false }
        case .recent:
            guard catalogPreferences.recentIDs.contains(asset.id) else { return false }
        }
        let family = HomeIslandAssetCatalog.family(containing: asset.id)
        let variant = family?.variants.first { $0.assetID == asset.id }
        return HomeIslandCatalogSearch.matches(
            query: catalogQuery,
            names: [asset.title, asset.titleKey, family?.title ?? "",
                    family?.titleKey ?? "", variant?.name ?? "", variant?.nameKey ?? ""]
        )
    }

    /// One slot on the shelf. A prop that comes in several occupies a single
    /// slot and carries its family; everything else is itself.
    private struct HomeIslandShelfEntry: Identifiable {
        let asset: HomeIslandAsset
        let family: HomeIslandAssetFamily?

        var id: String { family?.id ?? asset.id }
    }

    /// The tiles the shelf actually shows: `visibleAssets`, with each family
    /// collapsed into the one slot its best-placed variant earned.
    private var visibleShelfEntries: [HomeIslandShelfEntry] {
        var seenFamilies: Set<String> = []
        var entries: [HomeIslandShelfEntry] = []
        for asset in visibleAssets {
            guard let family = HomeIslandAssetCatalog.family(containing: asset.id) else {
                entries.append(HomeIslandShelfEntry(asset: asset, family: nil))
                continue
            }
            guard seenFamilies.insert(family.id).inserted else { continue }
            entries.append(
                HomeIslandShelfEntry(
                    asset: shelfVariant(of: family, fallback: asset),
                    family: family
                )
            )
        }
        return entries
    }

    /// Which variant a family's tile wears: the one the player last chose, or
    /// the one the sort put first — which is the cheapest to reach, since a
    /// locked or pass-only variant is sorted to the back.
    private func shelfVariant(
        of family: HomeIslandAssetFamily,
        fallback: HomeIslandAsset
    ) -> HomeIslandAsset {
        guard catalogScope != .recent,
              let chosen = familySelection[family.id],
              family.assetIDs.contains(chosen),
              let asset = HomeIslandAssetCatalog.asset(id: chosen),
              matchesCatalogAsset(asset)
        else { return fallback }
        return asset
    }

    private var expandedFamily: HomeIslandAssetFamily? {
        guard let expandedFamilyID else { return nil }
        return visibleShelfEntries.first { $0.family?.id == expandedFamilyID }?.family
    }

    /// The chooser row. It opens above the shelf rather than as a popover
    /// over the island: the player is choosing before placing, and the world
    /// they are about to place into should stay in view the whole time.
    private func assetVariantRow(_ family: HomeIslandAssetFamily) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: family.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                Text(verbatim: family.title)
                    .font(LFFont.label(10))
                    .lineLimit(1)
            }
            .foregroundStyle(LFHomeFeatureStyle.ink)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(family.variants) { variant in
                        assetVariantChip(variant, in: family)
                    }
                }
                .padding(.trailing, 2)
            }

            Button {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                    expandedFamilyID = nil
                }
                Haptics.tap(.light)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(LFHomeFeatureStyle.ink.opacity(0.72))
                    .frame(width: 24, height: 24)
                    .background(LFHomeFeatureStyle.field, in: Circle())
            }
            .buttonStyle(LFPressableButtonStyle())
            .accessibilityLabel(Text("Close"))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(LFHomeFeatureStyle.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LFHomeFeatureStyle.outline, lineWidth: 1)
        }
    }

    /// One variant. The dot is the prop's own colour — or the model itself,
    /// where colour is not what separates them — and the line under the name
    /// is the same count the tile carries, so choosing never hides how many of
    /// it the island can still take.
    @ViewBuilder
    private func assetVariantChip(
        _ variant: HomeIslandAssetVariant,
        in family: HomeIslandAssetFamily
    ) -> some View {
        if let asset = HomeIslandAssetCatalog.asset(id: variant.assetID) {
            let unlocked = HomeIslandAssetCatalog.isUnlocked(
                asset,
                playerLevel: levelProgress.level
            )
            let passLocked = isPassLocked(asset)
            let placedCount = store.placementCount(assetID: asset.id)
            let placementLimit = HomeIslandAssetCatalog.placementLimit(for: asset.id)
            let atLimit = placedCount >= placementLimit
            let awaitsPass = passLocked && unlocked && !atLimit && store.canAdd
            let canPlace = unlocked && !passLocked && !atLimit && store.canAdd
            let armed = placementAssetID == asset.id
            Button {
                familySelection[family.id] = asset.id
                if canPlace || awaitsPass {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                        expandedFamilyID = nil
                    }
                }
                selectBuildAsset(asset, canPlace: canPlace, opensVoyagePass: awaitsPass)
            } label: {
                HStack(spacing: 7) {
                    ZStack {
                        if let swatch = variant.swatch {
                            Circle()
                                .fill(Color(uiColor: UIColor(rgb: swatch)))
                                .frame(width: 20, height: 20)
                            Circle()
                                .stroke(
                                    armed
                                        ? LFHomeFeatureStyle.ink
                                        : LFHomeFeatureStyle.outline,
                                    lineWidth: armed ? 2 : 1
                                )
                                .frame(width: 20, height: 20)
                        } else {
                            // Shapes, not colours: the chip carries the model
                            // so the player picks the tree they can see.
                            HomeIslandAssetThumbnail(
                                assetID: asset.id,
                                fallbackSymbol: asset.symbolName
                            )
                                .frame(width: 24, height: 24)
                                .background(
                                    LFHomeFeatureStyle.ink.opacity(armed ? 0.14 : 0.06),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(
                                            armed
                                                ? LFHomeFeatureStyle.ink
                                                : LFHomeFeatureStyle.outline,
                                            lineWidth: armed ? 2 : 1
                                        )
                                }
                        }
                        if !unlocked || passLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(radius: 1)
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: variant.name)
                            .font(LFFont.label(10))
                            .foregroundStyle(
                                LFHomeFeatureStyle.ink.opacity(canPlace ? 0.92 : 0.42)
                            )
                        assetTagText(
                            asset,
                            unlocked: unlocked,
                            passLocked: passLocked,
                            placedCount: placedCount,
                            placementLimit: placementLimit
                        )
                        .font(LFFont.label(8))
                        .monospacedDigit()
                        .foregroundStyle(assetTagTint(unlocked: unlocked, passLocked: passLocked))
                    }
                    .lineLimit(1)
                }
                .padding(.leading, 7)
                .padding(.trailing, 11)
                .frame(height: 34)
                .background(
                    armed
                        ? LFHomeFeatureStyle.ink.opacity(0.13)
                        : LFHomeFeatureStyle.field,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            armed
                                ? LFHomeFeatureStyle.ink.opacity(0.48)
                                : LFHomeFeatureStyle.outline,
                            lineWidth: 1
                        )
                }
            }
            .buttonStyle(LFPressableButtonStyle())
            .accessibilityLabel(Text(verbatim: "\(family.title) · \(variant.name)"))
            .accessibilityValue(
                assetTagText(
                    asset,
                    unlocked: unlocked,
                    passLocked: passLocked,
                    placedCount: placedCount,
                    placementLimit: placementLimit
                )
            )
            .modifier(HomeIslandCatalogFavoriteModifier(assetID: asset.id, preferences: catalogPreferences))
        }
    }

    private func categoryButton(_ category: HomeIslandAssetCategory) -> some View {
        let selected = selectedAssetCategory == category
        return Button {
            selectedAssetCategoryToken = category.rawValue
            withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                expandedFamilyID = nil
            }
            Haptics.tap(.light)
        } label: {
            Label(category.title, systemImage: category.symbol)
                .font(LFFont.label(11))
                .foregroundStyle(
                    selected
                        ? LFHomeFeatureStyle.ink
                        : LFHomeFeatureStyle.secondaryInk
                )
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    selected
                        ? LFHomeFeatureStyle.ink.opacity(0.14)
                        : LFHomeFeatureStyle.field,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(
                            selected
                                ? LFHomeFeatureStyle.ink.opacity(0.34)
                                : LFHomeFeatureStyle.outline,
                            lineWidth: 1
                        )
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Simulator-only tuning value. It is deliberately absolute so a value
    /// approved during visual QA can be copied directly into `defaultScale`.
    private var allowsAssetSizeCalibration: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

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
    /// 島の側が持つ。文字を打っている間、島の描画枚数を落とすため。
    @Binding var editingProfile: Bool

    let sessions: [StudySession]
    /// 週グラフで選ばれている日。中身はパネルの外に出るので、選択は
    /// 島の側が持つ。nil は今日。
    @Binding var selectedDay: Date?
    /// Rendered inside a floating island panel: no navigation chrome, no
    /// full-screen background — the panel owns both.
    var compact = false

    var body: some View {
        if compact {
            compactBody
        } else {
            fullBody
        }
    }

    @ViewBuilder
    private var compactBody: some View {
        if editingProfile {
            // Editing swaps the panel's content instead of covering the island.
            ProfileEditorSheet(compact: true) {
                withAnimation(.easeOut(duration: 0.20)) {
                    editingProfile = false
                }
            }
            .transition(.opacity)
        } else {
            VStack(spacing: 16) {
                playerSummary
                Rectangle()
                    .fill(LFHomeFeatureStyle.outline)
                    .frame(height: 1)
                    .accessibilityHidden(true)
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    WorkRecordWeeklySummaryView(
                        sessions: sessions, now: max(context.date, Date()),
                        selectedDay: selectedDay,
                        onSelectDay: {
                            selectedDay = $0
                            Haptics.tap(.light)
                        },
                        compact: true
                    )
                }
            }
            .transition(.opacity)
        }
    }

    private var fullBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    playerSummary
                        .padding(12)
                        .lfHomeFeatureCard()
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        WorkRecordWeeklySummaryView(
                            sessions: sessions, now: max(context.date, Date()),
                            selectedDay: selectedDay,
                            onSelectDay: {
                                selectedDay = $0
                                Haptics.tap(.light)
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(LFHarborBackdrop())
            .navigationTitle(Text("Voyage record"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(panelInk)
                }
            }
        }
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $editingProfile) {
            ProfileEditorSheet()
        }
    }

    private var playerSummary: some View {
        HStack(alignment: .top, spacing: 12) {
            PlayerAvatarArt(styleToken: styleToken, symbolToken: symbolToken)
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(LFHomeFeatureStyle.outline, lineWidth: 1))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: displayName)
                    .font(LFFont.copy(17))
                    .foregroundStyle(panelInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !resolveText.isEmpty {
                    Text(verbatim: resolveText)
                        .font(LFFont.label(12))
                        .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
                        .lineLimit(2)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) {
                        Text("Total time")
                        Text(verbatim: LF.duration(minutes: totalMinutes))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total time")
                        Text(verbatim: LF.duration(minutes: totalMinutes))
                    }
                }
                .font(LFFont.label(11))
                .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
                .accessibilityElement(children: .combine)
            }

            Spacer(minLength: 8)

            Button {
                withAnimation(.easeOut(duration: 0.20)) {
                    editingProfile = true
                }
                Haptics.tap(.light)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(panelInk)
                    .frame(width: 44, height: 44)
                    .background(LFHomeFeatureStyle.field, in: Circle())
            }
            .buttonStyle(LFPressableButtonStyle())
            .accessibilityLabel(Text("Edit player card"))
        }
        .padding(4)
    }

    private var panelInk: Color {
        LFHomeFeatureStyle.ink
    }

    private var displayName: String {
        let normalized = PlayerProfile.normalizedName(playerName)
        return normalized.isEmpty ? LF.text("Sailor") : normalized
    }

    private var resolveText: String {
        resolve.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var totalMinutes: Int {
        sessions.reduce(0) { $0 + max(0, $1.minutes) }
    }
}

/// 週グラフで選んだ日に並べる一件ぶん。
private struct HomeIslandRecordEntry: Identifiable {
    let id: UUID
    let title: String
    let minutes: Int
    let note: String?
    let style: TileStyle
    let symbol: TileSymbol
}

private struct HomeIslandMusicPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isEnabled: Bool
    @Binding var selectedTrackID: String
    @ObservedObject var music: HomeBackgroundMusic
    @ObservedObject private var voyageMusic = HomeVoyageAudio.shared
    @AppStorage(StudyTimer.startKey, store: StudyTimer.defaults) private var timerStart: Double = 0
    @AppStorage(StudyTimer.itemKey, store: StudyTimer.defaults) private var timerItemID = ""
    @AppStorage(StudyTimer.soundKey, store: StudyTimer.defaults)
    private var timerSoundID = HomeVoyageSound.initialTimerSound.rawValue
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Rendered inside a floating island panel: no navigation chrome, no
    /// full-screen background — the panel owns both.
    var compact = false

    /// On a phone the floating panel is most of the screen, so the same layout
    /// that reads as a neat card on iPad reads as a takeover. Everything the
    /// list needs — artwork, title, state, checkmark — stays; it is drawn at
    /// phone scale.
    private var onPhone: Bool { compact && horizontalSizeClass == .compact }

    private var hasActiveTimer: Bool {
        VoyageTimerMath.isActive(startedAt: timerStart, itemID: timerItemID)
    }

    var body: some View {
        if compact {
            compactBody
        } else {
            fullBody
        }
    }

    private var compactBody: some View {
        ScrollView {
            VStack(spacing: onPhone ? 7 : 10) {
                playbackCard
                VStack(spacing: onPhone ? 1 : 3) {
                    ForEach(HomeBackgroundMusic.tracks) { track in
                        trackRow(track)
                    }
                }
            }
        }
        .frame(maxHeight: onPhone ? 248 : 340)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var fullBody: some View {
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
        HStack(spacing: onPhone ? 10 : 13) {
            ZStack {
                Circle()
                    .fill(panelInk.opacity(0.08))
                    .frame(width: onPhone ? 36 : 48, height: onPhone ? 36 : 48)
                if isCurrentContextPlaying {
                    HomeIslandEqualizer(color: panelInk)
                        .frame(width: onPhone ? 16 : 21, height: onPhone ? 16 : 21)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: onPhone ? 14 : 18, weight: .semibold))
                        .foregroundStyle(panelInk)
                }
            }

            VStack(alignment: .leading, spacing: onPhone ? 2 : 4) {
                Text(displayedTrack.title)
                    .font(LFFont.copy(onPhone ? 13 : 15))
                    .foregroundStyle(panelInk)
                    .lineLimit(2)

                Text(statusTitle)
                    .font(LFFont.label(10))
                    .foregroundStyle(panelInk.opacity(0.52))
            }

            Spacer(minLength: 8)

            Button {
                togglePlayback()
                Haptics.tap(.medium)
            } label: {
                Image(systemName: isCurrentContextPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: onPhone ? 13 : 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: onPhone ? 36 : 46, height: onPhone ? 36 : 46)
                    .background(panelInk, in: Circle())
            }
            .buttonStyle(LFPressableButtonStyle(scale: 0.94))
            .accessibilityLabel(Text(isCurrentContextPlaying ? "Stop" : "Play"))
        }
        .padding(onPhone ? 10 : 14)
        .background(Color.white.opacity(0.66), in: RoundedRectangle(cornerRadius: onPhone ? 16 : 21))
        .overlay(
            RoundedRectangle(cornerRadius: onPhone ? 16 : 21)
                .stroke(panelInk.opacity(0.11), lineWidth: 1)
        )
    }

    private func trackRow(_ track: HomeVoyageSound) -> some View {
        let selected = displayedTrack == track
        let playing = isCurrentContextPlaying && currentContextTrack == track

        return Button {
            selectedTrackID = track.rawValue
            isEnabled = true
            if hasActiveTimer {
                timerSoundID = track.rawValue
                voyageMusic.play(track.rawValue)
            } else {
                music.selectAndPlay(track)
            }
            Haptics.tap(.light)
        } label: {
            HStack(spacing: onPhone ? 9 : 12) {
                Image(systemName: "music.note")
                    .font(.system(size: onPhone ? 11 : 14, weight: .semibold))
                    .foregroundStyle(panelInk.opacity(selected ? 1 : 0.48))
                    .frame(width: onPhone ? 25 : 32, height: onPhone ? 25 : 32)
                    .background(panelInk.opacity(selected ? 0.10 : 0.045), in: Circle())

                VStack(alignment: .leading, spacing: onPhone ? 1 : 3) {
                    Text(track.title)
                        .font(LFFont.copy(onPhone ? 12 : 13))
                        .foregroundStyle(panelInk)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if playing {
                        Text("Playing")
                            .font(LFFont.label(onPhone ? 8 : 9))
                            .foregroundStyle(Color(uiColor: VoyageSceneKit.returnOrange))
                    }
                }

                Spacer(minLength: 8)

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: onPhone ? 15 : 18, weight: .semibold))
                        .foregroundStyle(panelInk)
                }
            }
            .padding(.horizontal, onPhone ? 7 : 10)
            .frame(minHeight: onPhone ? 40 : 52)
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

    /// 一曲終わるとプレイリストは次の曲へ自動で進む。パネルは選択値ではなく、
    /// いま実際に鳴っている曲を出す。止まっている間だけ、次に鳴る選択曲へ戻す。
    private var displayedTrack: HomeVoyageSound {
        guard isCurrentContextPlaying,
              HomeBackgroundMusic.tracks.contains(currentContextTrack)
        else { return selectedTrack }
        return currentContextTrack
    }

    private var statusTitle: LocalizedStringKey {
        if currentPlaybackFailed { return "Playback unavailable" }
        return isCurrentContextPlaying ? "Playing" : "Stopped"
    }

    private var isCurrentContextPlaying: Bool {
        hasActiveTimer ? voyageMusic.isPlaying : music.isPlaying
    }

    private var currentPlaybackFailed: Bool {
        hasActiveTimer ? voyageMusic.playbackFailed : music.playbackFailed
    }

    private var currentContextTrack: HomeVoyageSound {
        hasActiveTimer ? voyageMusic.currentSound : music.currentTrack
    }

    /// 島で聞こえている音を直接操作する。計測を最小化して島へ戻った場合は
    /// 航海側のプレイヤーが音源なので、そちらも同じパネルから止められる。
    private func togglePlayback() {
        if isCurrentContextPlaying {
            isEnabled = false
            if hasActiveTimer {
                timerSoundID = HomeVoyageSound.off.rawValue
                voyageMusic.stop()
            } else {
                music.stop()
            }
            return
        }

        isEnabled = true
        if hasActiveTimer {
            timerSoundID = selectedTrack.rawValue
            voyageMusic.play(selectedTrack.rawValue)
        } else {
            music.selectAndPlay(selectedTrack)
        }
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
                    VStack(spacing: 0) {
                        if selectedPublicHarbor == nil {
                            HStack(spacing: 12) {
                                Text("Harbor")
                                    .font(LFFont.copy(18))
                                    .foregroundStyle(panelInk)

                                Spacer(minLength: 0)

                                Button(action: onClose) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(panelInk)
                                        .frame(width: 44, height: 44)
                                        .background(panelInk.opacity(0.08), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("Close"))
                            }
                            .padding(.horizontal, 12)
                            .frame(height: regular ? 64 : 60)
                        }

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
                            } else {
                                HarborView(
                                    showsOceanBackground: false,
                                    onPublicHarborSelected: { harbor in
                                        withAnimation(.easeOut(duration: 0.18)) {
                                            selectedPublicHarbor = harbor
                                        }
                                    },
                                    onPrivateIslandSelected: { room in
                                        onClose()
                                        onPrivateIslandSelected(room)
                                    }
                                )
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: regular ? 30 : 24, style: .continuous))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    /// Bump when the render setup changes so stale thumbnails are re-rendered.
    private static let diskCacheVersion = 2
    private static let side: CGFloat = 96

    /// A model's own size and modification date are part of its cache key, so
    /// re-authoring an asset refreshes its tile by itself. Without this a
    /// rebuilt model kept showing the shape it had the first time it was drawn.
    private static func fingerprint(for assetID: String) -> String {
        guard let url = Bundle.main.url(forResource: assetID, withExtension: "usdz"),
              let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        else { return "none" }
        let size = values.fileSize ?? 0
        let modified = Int((values.contentModificationDate ?? .distantPast).timeIntervalSince1970)
        return "\(size)-\(modified)"
    }

    /// Building a Metal renderer costs more than the snapshot itself, so the
    /// whole catalog shares one.
    private static let renderer: SCNRenderer = {
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.autoenablesDefaultLighting = false
        return renderer
    }()

    private static var diskCacheDirectory: URL? = {
        guard let base = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let directory = base.appendingPathComponent(
            "HomeIslandAssetThumbnails/v\(diskCacheVersion)",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }()

    static func image(for assetID: String) async -> UIImage? {
        if let cached = cache[assetID] { return cached }
        if let stored = loadFromDisk(assetID: assetID) {
            cache[assetID] = stored
            return stored
        }
        // Loading the USDZ and snapshotting it are the expensive half. Yield
        // first so the palette can appear with its symbols already laid out.
        await Task.yield()
        guard let model = AssetPlacementRuntime.makeAssetNode(resourceName: assetID),
              let image = render(model: model)
        else { return nil }
        cache[assetID] = image
        storeOnDisk(image: image, assetID: assetID)
        return image
    }

    private static func diskURL(assetID: String) -> URL? {
        guard !assetID.contains("/") else { return nil }
        return diskCacheDirectory?
            .appendingPathComponent("\(assetID)-\(fingerprint(for: assetID)).png")
    }

    private static func loadFromDisk(assetID: String) -> UIImage? {
        guard let url = diskURL(assetID: assetID),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return UIImage(data: data)
    }

    private static func storeOnDisk(image: UIImage, assetID: String) {
        guard let url = diskURL(assetID: assetID), let data = image.pngData() else { return }
        try? data.write(to: url, options: .atomic)
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

        renderer.scene = scene
        renderer.pointOfView = cameraNode
        let image = renderer.snapshot(
            atTime: 0,
            with: CGSize(width: side, height: side),
            antialiasingMode: .multisampling2X
        )
        renderer.scene = nil
        return image
    }
}

/// The glance panels' full-screen tap catcher, with one rectangle punched out
/// of it. Drawn with the even-odd rule, the inner rectangle becomes a hole the
/// touch falls straight through — which is how the walking thumb keeps
/// reaching the island while a panel is open.
private struct HomeUtilityCatcherShape: Shape {
    let cutOut: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if !cutOut.isNull, !cutOut.isEmpty {
            path.addRect(cutOut)
        }
        return path
    }
}

private struct HomeIslandPhotoThirdsGuide: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for fraction in [CGFloat(1) / 3, CGFloat(2) / 3] {
            let x = rect.minX + rect.width * fraction
            let y = rect.minY + rect.height * fraction
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

/// Only records need a scrolling viewport around both their overview and day.
/// Other utility panels retain their original intrinsic height and hit area.
private struct HomeUtilityPanelViewport<Content: View>: View {
    let scrolls: Bool
    let maximumHeight: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if scrolls {
            ScrollView(.vertical, showsIndicators: false) { content() }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: maximumHeight, alignment: .top)
        } else {
            content()
        }
    }
}
