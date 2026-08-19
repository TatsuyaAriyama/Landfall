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
            ["small_tree", "conifer_tree", "small_stump", "small_rock", "small_lake",
             "coastal_rocks", "dune_grass_patch",
             "rose_bush_white", "rose_bush_red", "rose_bush_yellow",
             "hibiscus_bush_red", "hibiscus_bush_pink", "hibiscus_bush_orange",
             "palm_tree"]
                .contains(assetID)
        case .structures:
            ["weathered_cottage", "small_lighthouse", "weathered_lighthouse",
             "stone_well", "cliff_lookout", "mossy_ruins",
             "navigator_tent"]
                .contains(assetID)
        case .decor:
            ["weathered_crate", "campfire_circle", "voyage_flagpole",
             "harbor_lantern_post", "weathered_anchor", "net_drying_rack",
             "voyage_signal_bell", "supply_barrels",
             "beach_parasol", "swim_ring", "sandcastle", "watermelon",
             "seaside_mailbox", "seaside_gramophone"]
                .contains(assetID)
        case .paths:
            ["stone_path_straight", "stone_path_curve", "stone_path_fork",
             "compass_rose_inlay"]
                .contains(assetID)
        case .furniture:
            ["council_table", "council_chair",
             "driftwood_bench", "stone_bench", "wooden_bookshelf",
             "stacked_books", "office_desk", "office_chair", "silver_laptop",
             "navigator_hammock"]
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
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudySession.date) private var studySessions: [StudySession]
    @Query private var destinations: [Destination]
    @ObservedObject private var homeMusic = HomeBackgroundMusic.shared
    @StateObject private var store: HomeIslandStore
    @State private var placementAssetID: String?
    @State private var movingSelection = false
    @State private var placementMoveBlocked = false
    @State private var showingSizeControls = false
    @State private var showingSelectionActions = false
    @State private var lockedAssetID: String?
    @State private var cameraResetToken = 0
    @State private var cameraRequest: HomeIslandCameraRequest?
    @State private var captureRequest: HomeIslandCaptureRequest?
    /// 写真モードの明るさ増減(EV)。0 = 歩いているときのまま。
    @State private var cameraExposureOffset: Float = 0
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
    // Builders work in one category for a long stretch; reopening on "all"
    // every time meant scrolling past forty tiles to get back to it.
    @AppStorage("homeIsland.buildCategory") private var selectedAssetCategoryToken =
        HomeIslandAssetCategory.all.rawValue
    @State private var transientNotice: String?
    @State private var isDismissingAfterDeparture = false
    @State private var isNavigatorOnArrivalJetty = false
    @State private var isNavigatorNearNoticeBoard = false
    @State private var showingBoatCustomization = false
    @State private var selectedBoatSailID = BoatCustomization.selectedSailID
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
    @State private var editingPlayerProfile = false
    /// 週グラフで選んでいる日。開くたび今日から始まる。
    @State private var selectedRecordDay: Date?
    @State private var showingMusicPicker = false
    @State private var showingSettings = false
    @State private var showingHarborPanel = false
    @State private var privateChatExpanded = false
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
    private let boatTapOpensSelection: Bool
    private let externalBoatBoardingRequest: HomeIslandBoatBoardingRequest?
    private let noticeBoardRequestID: UUID?
    private let onBoatSelected: () -> Void
    private let onEmbeddedDepartureCompleted: (() -> Void)?
    private let onEmbeddedBoardingRejected: () -> Void
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
        boatTapOpensSelection: Bool = false,
        boardingRequest: HomeIslandBoatBoardingRequest? = nil,
        noticeBoardRequestID: UUID? = nil,
        onBoatSelected: @escaping () -> Void = {},
        onDepartureCompleted: (() -> Void)? = nil,
        onBoardingRejected: @escaping () -> Void = {},
        showsDestination: Bool = false,
        onDestinationLandfall: ((Destination) -> Void)? = nil,
        multiplayerSession: HomeIslandMultiplayerSession? = nil,
        onPrivateIslandSelected: @escaping (PrivateIslandRoom) -> Void = { _ in }
    ) {
        self.levelProgress = levelProgress
        self.showsDestination = showsDestination
        self.onDestinationLandfall = onDestinationLandfall
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

    /// One source of truth for every state that temporarily owns interaction
    /// above the island. This also keeps controller input from moving the
    /// navigator behind sheets and full-screen presentations.
    private var sceneInputLocked: Bool {
        scenePhase != .active
            || isCapturing
            || showingHarborPanel
            || privateChatExpanded
            || privateChatInputFocused
            || showingBoatCustomization
            || showingDestinationSetup
            || showingVoyagePass
            || showingLogbook
            || activeInterior != nil
            || showingPlayerStats
            || showingMusicPicker
            || showingSettings
            || showingIslandShare
            || showingCaptureError
            || showingSelectionActions
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
                selectedNavColorID = NavigatorCustomization.selectedID
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
                            ?? String(localized: "Removed · Undo is available")
                    )
                    Haptics.tap(.medium)
                }

                Button("Cancel", role: .cancel) {}
            }
    }

    fileprivate var islandStageBase: some View {
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
                playerLevel: levelProgress.level,
                cameraResetToken: cameraResetToken,
                cameraRequest: cameraRequest,
                captureRequest: captureRequest,
                boatBoardingRequest: externalBoatBoardingRequest ?? boatBoardingRequest,
                mode: mode,
                cameraExposureOffset: cameraExposureOffset,
                cameraInteractionLocked: sceneInputLocked,
                // 文字を打っている間は島を毎秒二十枚に落とす。波は動いたまま
                // だが、鍵盤の反応に回す余力がその分だけ戻る。
                rendersThrottled: editingPlayerProfile || privateChatInputFocused,
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
                locksMooredOverview: false,
                boatTapOpensSelection: boatTapOpensSelection,
                boatCustomizationActive: showingBoatCustomization,
                boatAppearanceID: selectedBoatSailID,
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
                            text: String(
                                localized: boatTapOpensSelection
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
                            text: String(localized: "Tap the notice board to check it")
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
        HStack(spacing: compactTopHUD ? 4 : 8) {
            Button {
                walkInput = .zero
                openUtility(.player)
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
                                .font(.system(size: topControlSymbolSize, weight: .semibold))
                                .foregroundStyle(homeGlassInk)
                                .frame(width: topControlWidth, height: topControlHeight)
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
                        }
                        .buttonStyle(LFPressableButtonStyle())
                        .accessibilityLabel(Text("Edit Island"))
                    }

                    Button {
                        walkInput = .zero
                        openUtility(.todo)
                    } label: {
                        Image(systemName: "checklist")
                            .font(.system(size: topControlSymbolSize, weight: .semibold))
                            .foregroundStyle(homeGlassInk)
                            .frame(width: topControlWidth, height: topControlHeight)
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .accessibilityLabel(Text("ToDo list"))

                    Button {
                        walkInput = .zero
                        openUtility(.music)
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "music.note")
                                .font(.system(size: topControlSymbolSize, weight: .semibold))
                                .foregroundStyle(homeGlassInk)
                            if homeMusic.isPlaying {
                                Circle()
                                    .fill(Color(uiColor: VoyageSceneKit.returnOrange))
                                    .frame(width: 6, height: 6)
                                    .offset(x: 5, y: -5)
                            }
                        }
                        .frame(width: topControlWidth, height: topControlHeight)
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
                            .font(.system(size: topControlSymbolSize, weight: .semibold))
                            .foregroundStyle(homeGlassInk)
                            .frame(width: topControlWidth, height: topControlHeight)
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
                            .frame(width: 44, height: 44)
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
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .disabled(!store.canRedo)
                    .accessibilityLabel(Text("Redo"))

                    Button {
                        cameraResetToken &+= 1
                        Haptics.tap(.light)
                    } label: {
                        Image(systemName: "scope")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(homeGlassInk)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .accessibilityLabel(Text("Return view to navigator"))

                    Button {
                        enterExploreMode()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(homeGlassInk)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .accessibilityLabel(Text("Finish editing"))
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
                    .foregroundStyle(Color(uiColor: VoyageSceneKit.sand))

                Text("Destinations")
                    .font(LFFont.label(11))
                    .tracking(0.8)
                    .foregroundStyle(Color(uiColor: VoyageSceneKit.sand))

                Spacer(minLength: 8)

                Button {
                    closeDestinationSetup()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
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
            .foregroundStyle(.white)
            .tint(Color(uiColor: VoyageSceneKit.returnOrange))
            .focused($destinationNameFocused)
            .textInputAutocapitalization(.never)
            .submitLabel(.done)
            .onSubmit { destinationNameFocused = false }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(.white.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
            .accessibilityLabel(Text("Island name"))

            DatePicker(
                selection: $destinationDateDraft,
                in: Date()...,
                displayedComponents: .date
            ) {
                Text("Target date")
                    .font(LFFont.copy(14))
                    .foregroundStyle(.white.opacity(0.86))
            }
            .datePickerStyle(.compact)
            .tint(Color(uiColor: VoyageSceneKit.returnOrange))
            .foregroundStyle(.white)

            Text("The island waits beyond the horizon until the final week. Over those last seven days, it draws closer day by day.")
                .font(LFFont.label(10))
                .foregroundStyle(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                saveDestination()
            } label: {
                Text("Save")
                    .font(LFFont.copy(15))
                    .foregroundStyle(LFColor.inkFixed)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        Color(uiColor: VoyageSceneKit.returnOrange)
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
                            .foregroundStyle(Color(uiColor: VoyageSceneKit.sand))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(.white.opacity(0.10), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(LFPressableButtonStyle())

                    Button(role: .destructive) {
                        deleteDestination()
                    } label: {
                        Text("Delete")
                            .font(LFFont.copy(13))
                            .foregroundStyle(Color(uiColor: VoyageSceneKit.returnOrange))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(.white.opacity(0.10), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(LFPressableButtonStyle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: 440)
        .background(hudBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        // 面の余白を叩いた指が、後ろの島まで抜けてカメラを動かさないように。
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)

                Text(verbatim: "LV \(levelProgress.level)")
                    .font(LFFont.label(compactTopHUD ? 8 : 9))
                    .tracking(0.6)
                    .foregroundStyle(homeGlassInk.opacity(0.58))
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, compactTopHUD ? 6 : 7)
        .padding(.trailing, compactTopHUD ? 10 : 12)
        .frame(width: playerCardWidth, height: playerCardHeight)
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

    /// The catalog has grown past thirty props, several of which differ only by
    /// flower colour. Tiles are sized so the model and its full name are both
    /// legible rather than fitting the most items on screen; iPad gets the
    /// roomier size because the shelf spans the whole width there.
    private var assetTileSide: CGFloat {
        compactTopHUD ? 88 : 100
    }

    /// A little taller than it is wide: the extra room is what lets a long name
    /// like "オレンジのハイビスカス" wrap onto a second line instead of eliding.
    private var assetTileHeight: CGFloat {
        assetTileSide + 10
    }

    private var assetThumbnailSide: CGFloat {
        compactTopHUD ? 54 : 62
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

    /// ToDo, music and the player card are glances, not destinations. They open
    /// as one small floating panel over the island instead of a sheet or a
    /// full-screen cover, so the island — and any walk in progress — stays
    /// visible behind them.
    private enum HomeUtility {
        case todo
        case music
        case player
    }

    private var activeUtility: HomeUtility? {
        if showingTodoList { return .todo }
        if showingMusicPicker { return .music }
        if showingPlayerStats { return .player }
        return nil
    }

    private func openUtility(_ utility: HomeUtility) {
        let alreadyOpen = activeUtility == utility
        if utility == .player, !alreadyOpen { selectedRecordDay = nil }
        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
            showingTodoList = !alreadyOpen && utility == .todo
            showingMusicPicker = !alreadyOpen && utility == .music
            showingPlayerStats = !alreadyOpen && utility == .player
        }
        Haptics.tap(.light)
    }

    private func closeUtilityPanel() {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
            showingTodoList = false
            showingMusicPicker = false
            showingPlayerStats = false
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
            ZStack(alignment: .topTrailing) {
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

                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: utilitySymbol(utility))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(utilityInk.opacity(0.62))
                            Text(utilityTitle(utility))
                                .font(LFFont.label(10))
                                .tracking(1.1)
                                .foregroundStyle(utilityInk.opacity(0.72))
                            Spacer(minLength: 8)
                            Button {
                                closeUtilityPanel()
                                Haptics.tap(.light)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(utilityInk.opacity(0.6))
                                    .frame(width: 26, height: 26)
                                    .background(utilityInk.opacity(0.06), in: Circle())
                            }
                            .buttonStyle(LFPressableButtonStyle())
                            .accessibilityLabel(Text("Close"))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 38)

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
                            }
                        }
                        .padding(10)
                    }
                    .frame(width: utilityPanelWidth(for: utility))
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.regularMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(utilityInk.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 18, y: 8)

                    // 選んだ日の中身はカードの外、島の景色の上に置く。パネルを
                    // 縦に伸ばさずに済み、記録そのものは空の側で読める。
                    // カードを書き換えている間は下げる。編集の手元と、
                    // 別の日の記録が同時に出ていても読む相手がいない。
                    if utility == .player, !editingPlayerProfile {
                        selectedDayRecords
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: utilityPanelWidth(for: utility), alignment: .leading)
                .padding(.trailing, compactTopHUD ? 8 : 12)
                .padding(.top, 62)
                .transition(.scale(scale: 0.94, anchor: .topTrailing).combined(with: .opacity))
                .environment(\.colorScheme, .light)
            }
        }
    }

    private var utilityInk: Color {
        Color(uiColor: VoyageSceneKit.nightBG)
    }

    /// 週グラフで選んだ日の作業。帯にも枠にも入れず、島の空の上へ直に置く。
    /// 一日ぶんを覗くための短い書き出しなので、四件までにして残りは数で示す。
    @ViewBuilder
    private var selectedDayRecords: some View {
        let day = selectedRecordDay ?? Calendar.current.startOfDay(for: Date())
        let entries = recordEntries(on: day)

        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Text(verbatim: LF.dayWithWeekday(day))
                    .font(LFFont.label(11))
                    .foregroundStyle(homeGlassInk.opacity(0.86))
                Spacer(minLength: 0)
                if !entries.isEmpty {
                    Text(verbatim: LF.duration(minutes: entries.reduce(0) { $0 + $1.minutes }))
                        .font(LFFont.label(11))
                        .foregroundStyle(Color(uiColor: VoyageSceneKit.returnOrange))
                }
            }

            if entries.isEmpty {
                Text("No work recorded on this day.")
                    .font(LFFont.label(11))
                    .foregroundStyle(homeGlassInk.opacity(0.68))
            } else {
                ForEach(entries.prefix(4)) { entry in
                    recordEntryRow(entry)
                }
                if entries.count > 4 {
                    Text(verbatim: LF.format("%lld more", Int64(entries.count - 4)))
                        .font(LFFont.label(10))
                        .foregroundStyle(homeGlassInk.opacity(0.66))
                }
            }
        }
        .padding(.horizontal, 4)
        // 帯を敷かないぶん、白い暈で字を浮かせる。海の上でも砂浜の上でも、
        // 同じ濃さのまま読める。
        .shadow(color: .white.opacity(0.85), radius: 3)
        .shadow(color: .white.opacity(0.5), radius: 7)
        .accessibilityElement(children: .contain)
    }

    private func recordEntryRow(_ entry: HomeIslandRecordEntry) -> some View {
        HStack(alignment: .top, spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(entry.style.background)
                TileSymbolView(
                    symbol: entry.symbol,
                    fg: entry.style.foreground,
                    bg: entry.style.background
                )
                .frame(width: 14, height: 14)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: entry.title)
                        .font(LFFont.copy(12.5))
                        .foregroundStyle(homeGlassInk)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    Text(verbatim: LF.duration(minutes: entry.minutes))
                        .font(LFFont.label(11))
                        .foregroundStyle(homeGlassInk.opacity(0.78))
                        .monospacedDigit()
                        .layoutPriority(1)
                }

                if let note = entry.note {
                    Text(verbatim: note)
                        .font(LFFont.label(10.5))
                        .foregroundStyle(homeGlassInk.opacity(0.7))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// その日の記録を新しい順に。項目を消したあとの記録も見出しだけは残す。
    private func recordEntries(on day: Date) -> [HomeIslandRecordEntry] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        return studySessions
            .filter { $0.date >= start && $0.date < end && $0.minutes > 0 }
            .sorted(by: StudySession.newestFirst)
            .map { session in
                let note = session.note?.trimmingCharacters(in: .whitespacesAndNewlines)
                return HomeIslandRecordEntry(
                    id: session.uuid,
                    title: session.item?.name ?? LF.text("Removed item"),
                    minutes: session.minutes,
                    note: (note?.isEmpty ?? true) ? nil : note,
                    style: TileStyle.from(session.item?.styleToken ?? ""),
                    symbol: TileSymbol.from(session.item?.symbolToken ?? "")
                )
            }
    }

    private func utilityTitle(_ utility: HomeUtility) -> LocalizedStringKey {
        switch utility {
        case .todo: "ToDo"
        case .music: "Music"
        case .player: "Player"
        }
    }

    private func utilitySymbol(_ utility: HomeUtility) -> String {
        switch utility {
        case .todo: "checklist"
        case .music: "music.note"
        case .player: "person.crop.circle"
        }
    }

    /// iPhone では名札とツール列が画面幅をほとんど食い切り、島の景色に
    /// 貼りついて見えていた。コンパクト時だけ一回り小さくして、両端と
    /// 名札の隣に余白を返す。iPad は元の大きさのまま。
    private var playerCardWidth: CGFloat {
        compactTopHUD ? 124 : 178
    }

    private var playerCardHeight: CGFloat {
        compactTopHUD ? 40 : 46
    }

    private var playerAvatarSide: CGFloat {
        compactTopHUD ? 26 : 32
    }

    private var topControlWidth: CGFloat {
        compactTopHUD ? 30 : 40
    }

    /// ツール列の丸みは名札の高さに合わせる（左右の帯が段違いに見えない）。
    private var topControlHeight: CGFloat {
        playerCardHeight - 6
    }

    private var topControlSymbolSize: CGFloat {
        compactTopHUD ? 14 : 16
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
        .safeAreaPadding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Navigator color"))
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
            text: String(localized: "Island changes could not be saved"),
            actionTitle: String(localized: "Retry")
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
            notice = String(localized: "This spot is kept clear")
        case .limitReached:
            notice = String(localized: "You have placed all of these")
        case .outsideBuildArea:
            notice = String(localized: "Keep the asset inside the sandy build area")
        case .coastRequired:
            notice = String(localized: "Place the jetty along the island edge")
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
            String(localized: "Drag an asset to move it · drag elsewhere to turn · pinch to zoom")
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
        showingDestinationSetup = false
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
            // 指を離せばその場で決まる。取り消すものがないので、この丸には
            // ボタンを置かない。
            hintPill(
                symbol: placementMoveBlocked
                    ? "exclamationmark.triangle.fill"
                    : "arrow.up.and.down.and.arrow.left.and.right",
                text: String(localized: placementMoveBlocked
                    ? "That way is closed — slide to open ground"
                    : "Release to place it here")
            )
        } else if store.selectedPlacement != nil {
            hintPill(
                symbol: "hand.draw.fill",
                text: String(localized: "Drag an asset to move it · release to place")
            )
        }
    }

    private func hintPill(
        symbol: String,
        text: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(Color(uiColor: VoyageSceneKit.sand))
            Text(verbatim: text)
                .font(LFFont.label(12))
                .foregroundStyle(.white)
                .lineLimit(1)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(LFFont.label(12))
                    .foregroundStyle(Color(uiColor: VoyageSceneKit.sand))
            }
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

                toolButton("Rotate", symbol: "rotate.right") {
                    store.rotateSelected()
                }
                .disabled(selected.assetID == "wooden_jetty")
                .opacity(selected.assetID == "wooden_jetty" ? 0.34 : 1)
                .accessibilityHint(Text("Rotates 15 degrees clockwise"))
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
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 44, height: 50)
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
                        .frame(width: 44, height: 50)
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
            placementMoveBlocked = false
            Haptics.tap(.medium)
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
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.10), in: Capsule())
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityHint(Text("Sail to this island"))
    }

    private var assetShelf: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label("Build", systemImage: "hammer.fill")
                    .font(LFFont.copy(13))
                    .foregroundStyle(.white.opacity(0.9))
                islandSlotChip
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
                // Lazy: a tile's thumbnail is rendered from its USDZ the first
                // time it appears, so opening build mode only pays for the few
                // tiles on screen instead of the whole catalog.
                LazyHStack(spacing: 10) {
                    ForEach(visibleAssets) { asset in
                        assetButton(asset)
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
        let passLocked = isPassLocked(asset)
        // Nothing but the pass stands in the way, so this tile can hand the
        // player the Voyage Pass instead of only refusing them.
        let awaitsPass = passLocked && unlocked && !atLimit && store.canAdd
        let canPlace = unlocked && !passLocked && !atLimit && store.canAdd
        return Button {
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
                        .background(.white.opacity(selected ? 0.13 : 0.055), in: RoundedRectangle(cornerRadius: 14))
                    assetCornerMarker(
                        unlocked: unlocked,
                        passLocked: passLocked,
                        atLimit: atLimit
                    )
                }
                Text(verbatim: asset.title)
                    .font(LFFont.label(10))
                    .foregroundStyle(.white.opacity(canPlace ? (selected ? 1 : 0.72) : 0.34))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            .padding(6)
            .frame(width: assetTileSide, height: assetTileHeight)
            .background(
                selected ? Color(uiColor: VoyageSceneKit.ember).opacity(0.24) : .white.opacity(canPlace ? 0.045 : 0.018),
                in: RoundedRectangle(cornerRadius: 15)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(selected ? Color(uiColor: VoyageSceneKit.sand).opacity(0.58) : .white.opacity(0.07), lineWidth: 1)
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
                    .foregroundStyle(assetTagTint(unlocked: unlocked, passLocked: passLocked))
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(.black.opacity(0.62), in: Capsule())
                    .offset(x: 3, y: -3)
            }
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityLabel(Text(verbatim: asset.title))
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
                .foregroundStyle(assetTagTint(unlocked: unlocked, passLocked: passLocked))
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
            return Color(uiColor: VoyageSceneKit.sand)
        }
        return passLocked ? LFColor.returnOrange : .white.opacity(0.64)
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
            selectedAssetCategoryToken = category.rawValue
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
            ScrollView {
                VStack(spacing: 12) {
                    playerSummary
                    metricRow
                    weeklyChart
                }
            }
            .frame(maxHeight: 360)
            .scrollBounceBehavior(.basedOnSize)
            .transition(.opacity)
        }
    }

    private var fullBody: some View {
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
        .fullScreenCover(isPresented: $editingProfile) {
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
                withAnimation(.easeOut(duration: 0.20)) {
                    editingProfile = true
                }
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

            HStack(alignment: .bottom, spacing: 5) {
                ForEach(weekDays) { day in
                    let isSelected = isSelectedDay(day)
                    Button {
                        selectedDay = day.date
                        Haptics.tap(.light)
                    } label: {
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

                            // 選んだ日の印は曜日の名前だけに付ける。棒の背後を
                            // 塗ると柱が一本太って見え、今日の橙とも張り合う。
                            Text(verbatim: day.label)
                                .font(LFFont.label(9))
                                .foregroundStyle(isSelected || day.isToday ? panelInk : panelInk.opacity(0.48))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(panelInk.opacity(isSelected ? 0.11 : 0))
                                )
                        }
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        Text(verbatim: "\(day.fullDate), \(LF.duration(minutes: day.minutes))")
                    )
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityHint(Text("Shows this day's work below the card"))
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

    private func isSelectedDay(_ day: HomeIslandDailyMinutes) -> Bool {
        guard let selectedDay else { return day.isToday }
        return Self.calendar.isDate(day.date, inSameDayAs: selectedDay)
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

/// 週グラフで選んだ日に並べる一件ぶん。
private struct HomeIslandRecordEntry: Identifiable {
    let id: UUID
    let title: String
    let minutes: Int
    let note: String?
    let style: TileStyle
    let symbol: TileSymbol
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Rendered inside a floating island panel: no navigation chrome, no
    /// full-screen background — the panel owns both.
    var compact = false

    /// On a phone the floating panel is most of the screen, so the same layout
    /// that reads as a neat card on iPad reads as a takeover. Everything the
    /// list needs — artwork, title, state, checkmark — stays; it is drawn at
    /// phone scale.
    private var onPhone: Bool { compact && horizontalSizeClass == .compact }

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
                if music.isPlaying {
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
                isEnabled.toggle()
                Haptics.tap(.medium)
            } label: {
                Image(systemName: isEnabled ? "pause.fill" : "play.fill")
                    .font(.system(size: onPhone ? 13 : 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: onPhone ? 36 : 46, height: onPhone ? 36 : 46)
                    .background(panelInk, in: Circle())
            }
            .buttonStyle(LFPressableButtonStyle(scale: 0.94))
            .accessibilityLabel(Text(isEnabled ? "Stop" : "Play"))
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
        let playing = music.isPlaying && music.currentTrack == track

        return Button {
            selectedTrackID = track.rawValue
            isEnabled = true
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
        guard music.isPlaying,
              HomeBackgroundMusic.tracks.contains(music.currentTrack)
        else { return selectedTrack }
        return music.currentTrack
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
