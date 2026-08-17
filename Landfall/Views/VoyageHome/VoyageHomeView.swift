import Combine
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// iOS版の起点。最新Web版と同じく、目的地そのものを常設背景にし、
/// 船首甲板の上へ作業項目と今日の記録を直接重ねる。
struct VoyageHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: AuthService
    @Query(sort: \StudyItem.sortOrder) private var items: [StudyItem]
    @Query private var sessions: [StudySession]
    @Query private var destinations: [Destination]

    @State private var now = Date()
    @State private var path = NavigationPath()
    @State private var menuOpen = false
    @State private var presentedRoute: VoyageMenuDestination?
    @State private var showingTrace = false
    @State private var showingSettings = false
    @State private var showingPrologue = false
    @State private var replayPrologueAfterSettings = false
    @State private var prologuePresentationID = UUID()
    @State private var prologueIsLaunching = false
    @State private var showingHelp = false
    @State private var sharingToday = false
    @State private var creatingItem = false
    @State private var editingItem: StudyItem?
    @State private var draggedItemID: UUID?
    @State private var lastDragTargetID: UUID?
    @State private var manifestItemOrder: [UUID] = []
    @State private var manifestDraggedItemID: UUID?
    @State private var manifestDragStartOrder: [UUID] = []
    @State private var manifestItemFrames: [UUID: CGRect] = [:]
    @State private var manifestDragLocation: CGPoint?
    @State private var manifestDragGrabOffset = CGSize.zero
    @State private var manifestLastTargetID: UUID?
    @State private var manifestLastReorderLocation: CGPoint?
    @State private var manifestSuppressTapItemID: UUID?
    @State private var manifestEditing = false
    @State private var celebrating: Destination?
    @State private var pendingLandingDestination: Destination?
    @State private var pendingCompleteDestination: Destination?
    @State private var pendingDelete: StudySession?
    @State private var timerVoyageItem: StudyItem?
    @State private var timerSceneReady = false
    @State private var timerSceneReturning = false
    @State private var timerSceneNow = Date()
    @State private var timerWorldTapToken = 0
    @State private var pendingManualAfterTimerReturn: HomeManualRequest?
    @State private var pendingTimerSwitch: StudyItem?
    @State private var manualRequest: HomeManualRequest?
    @State private var quickTimerRecord: HomeQuickTimerRecord?
    @State private var showingWorkManifest = false
    @State private var showingHarborCoach = false
    @State private var homeIslandBoardingRequest: HomeIslandBoatBoardingRequest?
    @State private var noticeBoardRequestID: UUID?
    @State private var pendingIslandLaunchItem: StudyItem?
    @State private var homeIslandSceneGeneration = UUID()
    @State private var privateIslandVisit: PrivateIslandRoom?
    @State private var queuedPrivateIslandVisit: PrivateIslandRoom?
    @StateObject private var hostedPrivateIsland = HostedPrivateIslandSessionCoordinator()
    @FocusState private var workManifestKeyboardFocused: Bool
    @FocusState private var commandMenuKeyboardFocused: Bool
    @AccessibilityFocusState private var workManifestAccessibilityFocused: Bool
    @AccessibilityFocusState private var commandMenuAccessibilityFocused: Bool

    @AppStorage(StudyTimer.startKey, store: StudyTimer.defaults) private var timerStart: Double = 0
    @AppStorage(StudyTimer.itemKey, store: StudyTimer.defaults) private var timerItemID = ""
    @AppStorage(StudyTimer.modeKey, store: StudyTimer.defaults)
    private var timerMode = HomeTimerMode.free.rawValue
    @AppStorage(StudyTimer.pomodoroStartElapsedKey, store: StudyTimer.defaults)
    private var timerPomodoroStartElapsed: Double = 0
    @AppStorage(StudyTimer.breakSecondsKey, store: StudyTimer.defaults)
    private var timerBreakSeconds: Double = 0
    @AppStorage(StudyTimer.soundKey, store: StudyTimer.defaults)
    private var timerSoundMode = HomeVoyageSound.initialTimerSound.rawValue
    @AppStorage(StudyTimer.breakStartedAtKey, store: StudyTimer.defaults) private var timerBreakStartedAt: Double = 0
    @AppStorage(HomeBackgroundMusic.enabledKey) private var homeMusicEnabled = false
    @AppStorage("home.island.shipInteractionSeen") private var shipInteractionSeen = false
    @StateObject private var sailAnimator = SailAnimator.shared
    @StateObject private var router = DeepLinkRouter.shared

    private let minuteClock = Timer.publish(
        every: 60,
        tolerance: 2,
        on: .main,
        in: .common
    ).autoconnect()

    private let voyageClock = Timer.publish(
        every: 1,
        tolerance: 0.08,
        on: .main,
        in: .common
    ).autoconnect()

    private var timeOfDay: AftideHomeTimeOfDay {
        AftideHomeTimeOfDay.current(at: now)
    }

    private var palette: AftideHomePalette {
        // 3D映像は時刻に合わせて変化させる一方、操作UIは朝の高コントラスト配色へ固定する。
        // 夜でも白系パネル＋濃色文字になり、背景映像に読みやすさを左右されない。
        AftideHomeTimeOfDay.morning.palette
    }

    private var activeDestination: Destination? {
        destinations.first { $0.achievedAt == nil }
    }

    private var todaySessions: [StudySession] {
        sessions
            .filter { Calendar.current.isDate($0.date, inSameDayAs: now) }
            .sorted(by: StudySession.newestFirst)
    }

    private var todayTotal: Int {
        todaySessions.reduce(0) { $0 + $1.minutes }
    }

    private var currentTimerItem: StudyItem? {
        guard timerStart > 0 else { return nil }
        return items.first { $0.uuid.uuidString == timerItemID }
    }

    private var currentTimerSnapshot: HomeTimerSnapshot {
        HomeTimerSnapshot(
            startedAt: timerStart > 0
                ? timerStart
                : timerSceneNow.timeIntervalSince1970,
            mode: HomeTimerMode(rawValue: timerMode) ?? .free,
            pomodoroStartElapsed: timerPomodoroStartElapsed,
            breakSeconds: timerBreakSeconds,
            breakStartedAt: timerBreakStartedAt
        )
    }

    private var timerIsResting: Bool {
        currentTimerSnapshot.isResting
            || currentTimerSnapshot.phase(at: timerSceneNow)?.focusing == false
    }

    private var timerWorldActive: Bool {
        timerVoyageItem != nil || timerSceneReturning
    }

    private var totalByItem: [UUID: Int] {
        var result: [UUID: Int] = [:]
        for session in sessions {
            if let id = session.item?.uuid {
                result[id, default: 0] += session.minutes
            }
        }
        return result
    }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    if timerVoyageItem == nil {
                        VoyageHomeIslandSceneHost(
                            ownerID: auth.homeIslandOwnerID,
                            levelProgress: PlayerLevelProgress(sessions: sessions),
                            boardingRequest: homeIslandBoardingRequest,
                            noticeBoardRequestID: noticeBoardRequestID,
                            onBoatSelected: openWorkManifest,
                            multiplayerSession: hostedPrivateIsland.multiplayerSession,
                            onPrivateIslandSelected: presentPrivateIsland,
                            onDepartureCompleted: finishIslandDeparture,
                            onBoardingRejected: cancelIslandDeparture,
                            onDestinationLandfall: { destination in
                                pendingLandingDestination = destination
                            }
                        )
                        .id("\(auth.homeIslandOwnerID)-\(homeIslandSceneGeneration.uuidString)")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(
                            !showingWorkManifest && pendingIslandLaunchItem == nil
                        )
                        .accessibilityHidden(
                            showingWorkManifest || pendingIslandLaunchItem != nil
                        )
                    } else {
                        Color(hex: timeOfDay.palette.sky)
                            .ignoresSafeArea()
                    }

                    if showingHarborCoach,
                       !showingWorkManifest,
                       presentedRoute == nil,
                       !timerWorldActive {
                        harborCoach
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.top, geometry.safeAreaInsets.top + 62)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if showingWorkManifest,
                       presentedRoute == nil,
                       !timerWorldActive {
                        workManifest(
                            availableWidth: geometry.size.width,
                            availableHeight: geometry.size.height
                                - geometry.safeAreaInsets.top
                                - geometry.safeAreaInsets.bottom
                        )
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: geometry.size.width >= 760 ? .trailing : .bottom
                            )
                            .padding(.horizontal, 12)
                            .padding(.trailing, geometry.size.width >= 760 ? 10 : 0)
                            .padding(.bottom, geometry.size.width >= 760 ? 18 : geometry.safeAreaInsets.bottom + 10)
                            .transition(
                                .move(edge: geometry.size.width >= 760 ? .trailing : .bottom)
                                    .combined(with: .opacity)
                            )
                            .zIndex(12)
                    }

                    if let item = timerVoyageItem {
                        HomeVoyageTimerView(
                            item: item,
                            hasDestination: activeDestination != nil,
                            onManual: { minutes in
                                pendingManualAfterTimerReturn = HomeManualRequest(
                                    item: item,
                                    initialMinutes: minutes
                                )
                                dismissTimerVoyage()
                            },
                            onReturnHome: {
                                now = Date()
                                dismissTimerVoyage()
                            },
                            rendersScene: true,
                            externalWorldTapToken: timerWorldTapToken
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(timerSceneReady ? 1 : 0)
                        .allowsHitTesting(timerSceneReady)
                        .accessibilityHidden(!timerSceneReady)
                        .zIndex(50)
                    }
                }
                .background(Color(hex: timeOfDay.palette.sky).ignoresSafeArea())
                .animation(.easeOut(duration: 0.16), value: menuOpen)
            }
            .navigationDestination(for: StudyItem.self) { item in
                ItemDetailView(item: item)
            }
        }
        .tint(palette.inkColor)
        .preferredColorScheme(
            timeOfDay == .evening || timeOfDay == .night ? .dark : .light
        )
        .sheet(isPresented: $sharingToday) {
            DayShareSheet(date: now)
        }
        .sheet(isPresented: $showingSettings, onDismiss: presentQueuedPrologue) {
            SettingsView {
                replayPrologueAfterSettings = true
                showingSettings = false
            }
        }
        .sheet(isPresented: $showingHelp) {
            HelpView()
        }
        .sheet(isPresented: $creatingItem) {
            ItemEditorSheet(existing: nil)
        }
        .sheet(item: $editingItem) { item in
            ItemEditorSheet(existing: item)
        }
        .fullScreenCover(isPresented: $showingTrace) {
            TraceView {
                showingTrace = false
            }
        }
        .fullScreenCover(isPresented: $showingPrologue, onDismiss: resumeHomeAudioAfterPrologue) {
            GeometryReader { geometry in
                ZStack {
                    Color(hex: 0x061615)
                    if prologueIsLaunching {
                        PrologueVoyageLaunchSceneView {
                            prologueIsLaunching = false
                            showingPrologue = false
                        }
                        .transition(.opacity)
                    } else {
                        ForgottenSeaPrologueView {
                            HomeVoyageAudio.shared.play(
                                HomeVoyageSound.initialTimerSound.rawValue
                            )
                            withAnimation(.easeInOut(duration: 0.48)) {
                                prologueIsLaunching = true
                            }
                        }
                        .id(prologuePresentationID)
                        .transition(.opacity)
                    }
                }
                .padding(.top, geometry.safeAreaInsets.top)
                .padding(.bottom, geometry.safeAreaInsets.bottom)
                .ignoresSafeArea()
            }
            .interactiveDismissDisabled()
        }
        .sheet(item: $manualRequest) { request in
            HomeManualTimeSheet(
                item: request.item,
                initialMinutes: request.initialMinutes,
                onSaved: { now = Date() }
            )
        }
        .fullScreenCover(item: $celebrating) { destination in
            LandfallCelebrationView(
                destination: destination,
                minutes: destination.progress(sessions: sessions).minutes
            ) {
                celebrating = nil
            }
        }
        .fullScreenCover(item: $presentedRoute, onDismiss: {
            presentQueuedPrivateIslandIfPossible()
        }) { route in
            if route == .logbook {
                VoyageRouteContainer(
                    route: route,
                    onPrivateIslandSelected: presentPrivateIsland
                )
                    .presentationBackground(.clear)
            } else {
                VoyageRouteContainer(
                    route: route,
                    onPrivateIslandSelected: presentPrivateIsland
                )
            }
        }
        .fullScreenCover(item: $privateIslandVisit, onDismiss: {
            presentQueuedPrivateIslandIfPossible()
        }) { room in
            PrivateIslandVisitWorld(
                room: room,
                localOwnerID: auth.homeIslandOwnerID,
                levelProgress: PlayerLevelProgress(sessions: sessions),
                onClose: {
                    privateIslandVisit = nil
                },
                onPrivateIslandSelected: presentPrivateIsland
            )
            .id("private-island-\(room.code)-\(auth.user?.uid ?? "signed-out")")
        }
        .confirmationDialog(
            "Delete this record?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDelete {
                    deleteSession(pendingDelete)
                }
                pendingDelete = nil
            }
        }
        .confirmationDialog(
            "Switch to this item?",
            isPresented: Binding(
                get: { pendingTimerSwitch != nil },
                set: { if !$0 { pendingTimerSwitch = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Switch voyage", role: .destructive) {
                if let item = pendingTimerSwitch {
                    beginVoyage(for: item)
                }
                pendingTimerSwitch = nil
            }
            Button("Keep current voyage", role: .cancel) {
                pendingTimerSwitch = nil
            }
        } message: {
            Text("The current measured time will not be recorded.")
        }
        .confirmationDialog(
            "Go ashore",
            isPresented: Binding(
                get: { pendingLandingDestination != nil },
                set: { if !$0 { pendingLandingDestination = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Go ashore") {
                if let destination = pendingLandingDestination {
                    land(destination)
                }
                pendingLandingDestination = nil
            }
            Button("Cancel", role: .cancel) {
                pendingLandingDestination = nil
            }
        } message: {
            Text("Did you achieve this destination? Going ashore ends this voyage and saves it in your Logbook.")
        }
        .confirmationDialog(
            "Mark complete",
            isPresented: Binding(
                get: { pendingCompleteDestination != nil },
                set: { if !$0 { pendingCompleteDestination = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Mark complete") {
                if let destination = pendingCompleteDestination {
                    markComplete(destination)
                }
                pendingCompleteDestination = nil
            }
            Button("Cancel", role: .cancel) {
                pendingCompleteDestination = nil
            }
        } message: {
            Text("Mark this destination complete?")
        }
        .overlay(alignment: .top) {
            if let quickTimerRecord {
                Label(
                    LF.format(
                        "Recorded %@",
                        LF.duration(minutes: quickTimerRecord.minutes)
                    ),
                    systemImage: "checkmark.circle.fill"
                )
                .font(LFFont.label(13))
                .foregroundStyle(LFColor.harborSand)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(LFColor.harborTeal.opacity(0.97), in: Capsule())
                .overlay(Capsule().stroke(LFColor.harborSand.opacity(0.24), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.18), radius: 14, y: 7)
                .safeAreaPadding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .overlay {
            if let kind = sailAnimator.kind {
                SailingOverlay(kind: kind)
                    .transition(.opacity)
            }
        }
        // Above the island layer, which is hit-test disabled while a launch is
        // in flight — a skip placed inside it could never be tapped.
        .overlay(alignment: .topTrailing) {
            departureSkipButton
        }
        .onReceive(minuteClock) { tick in
            now = tick
        }
        .onReceive(voyageClock) { tick in
            guard timerVoyageItem != nil else { return }
            timerSceneNow = tick
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            now = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .homeIslandDidChange)) { note in
            guard note.object as? String
                    == HomeIslandPersistence.ownerKey(for: auth.homeIslandOwnerID)
            else { return }
            publishHomeIslandToOwnedPrivateIsland()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                now = Date()
            }
            if prologueIsLaunching {
                if phase == .active {
                    HomeVoyageAudio.shared.play(
                        HomeVoyageSound.initialTimerSound.rawValue
                    )
                } else {
                    HomeVoyageAudio.shared.stop()
                }
            }
        }
        .onChange(of: router.wantsHarborTab) { _, wants in
            openPendingHarborInviteIfNeeded(wants)
        }
        .onChange(of: showingWorkManifest) { _, visible in
            if visible {
                DispatchQueue.main.async {
                    workManifestKeyboardFocused = true
                    workManifestAccessibilityFocused = true
                }
            } else {
                workManifestKeyboardFocused = false
                workManifestAccessibilityFocused = false
            }
        }
        .onChange(of: menuOpen) { _, visible in
            if visible {
                DispatchQueue.main.async {
                    commandMenuKeyboardFocused = true
                    commandMenuAccessibilityFocused = true
                }
            } else {
                commandMenuKeyboardFocused = false
                commandMenuAccessibilityFocused = false
            }
        }
        .onChange(of: presentedRoute) { previousRoute, currentRoute in
            guard previousRoute == .island,
                  currentRoute == nil
            else { return }
            homeIslandSceneGeneration = UUID()
        }
        .onAppear {
            clearOrphanedTimer()
            openPendingHarborInviteIfNeeded(router.wantsHarborTab)
            if !shipInteractionSeen {
                withAnimation(.easeOut(duration: 0.28)) {
                    showingHarborCoach = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
                    guard !shipInteractionSeen else { return }
                    withAnimation(.easeOut(duration: 0.24)) {
                        showingHarborCoach = false
                    }
                }
            }
            #if DEBUG
            DebugCardDump.runIfRequested()
            if ProcessInfo.processInfo.environment["LANDFALL_HOME_MENU"] == "1" {
                menuOpen = true
            }
            if ProcessInfo.processInfo.environment["LANDFALL_SETTINGS"] != nil {
                showingSettings = true
            }
            if ProcessInfo.processInfo.environment["LANDFALL_HELP"] != nil {
                showingHelp = true
            }
            if ProcessInfo.processInfo.environment["LANDFALL_LOGBOOK"] != nil {
                presentedRoute = .logbook
            }
            if ProcessInfo.processInfo.environment["LANDFALL_HOME_ISLAND"] != nil {
                menuOpen = false
                presentedRoute = .island
            }
            #endif
        }
        .task(id: auth.user?.uid) {
            guard auth.user?.uid != nil else {
                hostedPrivateIsland.deactivate()
                return
            }
            guard hostedPrivateIsland.activeRoom == nil,
                  let room = try? await PrivateIslandService.shared.ownedIsland()
            else { return }
            hostedPrivateIsland.activate(
                room: room,
                localOwnerID: auth.homeIslandOwnerID
            )
        }
    }

    private func openPendingHarborInviteIfNeeded(_ requested: Bool) {
        guard requested else { return }
        menuOpen = false
        presentedRoute = .harbor
        router.wantsHarborTab = false
    }

    private func publishHomeIslandToOwnedPrivateIsland() {
        let ownerKey = HomeIslandPersistence.ownerKey(for: auth.homeIslandOwnerID)
        let snapshot = HomeIslandPersistence.load(ownerKey: ownerKey)
        PrivateIslandService.shared.enqueueOwnedSnapshot(snapshot)
    }

    private var backdropActive: Bool {
        scenePhase == .active &&
        !menuOpen &&
        (presentedRoute == nil || presentedRoute == .logbook) &&
        !showingTrace &&
        !showingSettings &&
        !showingPrologue &&
        !showingHelp &&
        sailAnimator.kind == nil
    }

    /// 設定シートが完全に閉じてから、ホーム階層で序章を全画面表示する。
    private func presentQueuedPrologue() {
        guard replayPrologueAfterSettings else { return }
        replayPrologueAfterSettings = false
        Task { @MainActor in
            await Task.yield()
            prologuePresentationID = UUID()
            prologueIsLaunching = false
            showingPrologue = true
        }
    }

    /// 序章を閉じた後、計測中でなければホーム音響を設定どおりに戻す。
    private func resumeHomeAudioAfterPrologue() {
        HomeVoyageAudio.shared.stop()
        guard scenePhase == .active else { return }
        if timerStart > 0 {
            if timerBreakStartedAt <= 0 {
                HomeVoyageAudio.shared.play(timerSoundMode)
            }
            return
        }
        if homeMusicEnabled { HomeBackgroundMusic.shared.play() }
    }

    /// A UIKit presentation must be fully dismissed before another full-screen
    /// world is attached. Queueing also keeps each room's listeners and
    /// StateObjects scoped to exactly one visit.
    private func presentPrivateIsland(_ room: PrivateIslandRoom) {
        showingWorkManifest = false
        menuOpen = false

        if privateIslandVisit?.id == room.id
            || hostedPrivateIsland.activeRoom?.id == room.id {
            return
        }
        if presentedRoute != nil || privateIslandVisit != nil {
            queuedPrivateIslandVisit = room
            if presentedRoute != nil {
                presentedRoute = nil
            } else {
                privateIslandVisit = nil
            }
            return
        }
        activatePrivateIsland(room)
    }

    /// Hosts stay in the existing Home Island scene. Only guests need a
    /// separate full-screen visit world for another sailor's local island.
    private func activatePrivateIsland(_ room: PrivateIslandRoom) {
        if room.hostUid == auth.user?.uid {
            hostedPrivateIsland.activate(
                room: room,
                localOwnerID: auth.homeIslandOwnerID
            )
        } else {
            privateIslandVisit = room
        }
    }

    private func presentQueuedPrivateIslandIfPossible() {
        guard presentedRoute == nil,
              privateIslandVisit == nil,
              let room = queuedPrivateIslandVisit
        else { return }
        queuedPrivateIslandVisit = nil
        Task { @MainActor in
            // Allow the previous presentation controller to leave the window
            // hierarchy before attaching SceneKit for the next island.
            try? await Task.sleep(for: .milliseconds(180))
            guard presentedRoute == nil, privateIslandVisit == nil else {
                queuedPrivateIslandVisit = room
                return
            }
            activatePrivateIsland(room)
        }
    }

    private func openWorkManifest() {
        guard pendingIslandLaunchItem == nil, !showingWorkManifest else { return }
        shipInteractionSeen = true
        menuOpen = false
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            showingHarborCoach = false
            showingWorkManifest = true
        }
        Haptics.tap(.light)
    }

    /// The sail-out is worth watching once and a wait every day after. Small,
    /// in the corner, and it lands exactly where the animation would have.
    @ViewBuilder
    private var departureSkipButton: some View {
        if pendingIslandLaunchItem != nil {
            Button {
                skipDeparture()
            } label: {
                HStack(spacing: 5) {
                    Text("Skip")
                        .font(LFFont.label(11))
                    Image(systemName: "forward.fill")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(LFColor.harborSand)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(LFColor.harborTeal.opacity(0.92), in: Capsule())
                .overlay(Capsule().stroke(LFColor.harborSand.opacity(0.26), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.16), radius: 10, y: 4)
            }
            .buttonStyle(LFPressableButtonStyle())
            .padding(.trailing, 16)
            .safeAreaPadding(.top, 10)
            .transition(.opacity)
            .accessibilityLabel(Text("Skip the departure"))
        }
    }

    private func skipDeparture() {
        sailAnimator.finish()
        finishIslandDeparture()
    }

    private func finishIslandDeparture() {
        guard let item = pendingIslandLaunchItem else { return }
        if timerStart > 0, timerItemID != item.uuid.uuidString {
            StudyTimer.clearAll()
        }
        StudyTimer.begin(itemID: item.uuid.uuidString, itemName: item.name)
        pendingIslandLaunchItem = nil
        homeIslandBoardingRequest = nil
        presentTimerVoyage(item)
        Haptics.tap(.medium)
    }

    private func cancelIslandDeparture() {
        guard pendingIslandLaunchItem != nil else { return }
        pendingIslandLaunchItem = nil
        homeIslandBoardingRequest = nil
        withAnimation(.easeOut(duration: 0.18)) {
            showingWorkManifest = true
        }
        Haptics.error()
    }

    private func dismissHomeOverlay() {
        guard showingWorkManifest || menuOpen else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            showingWorkManifest = false
            menuOpen = false
        }
    }

    private func activateHarborHotspot(_ hotspot: HomeHarborHotspot) {
        guard !timerWorldActive else { return }
        shipInteractionSeen = true
        withAnimation(.easeOut(duration: 0.20)) {
            showingHarborCoach = false
        }
        menuOpen = false

        switch hotspot {
        case .work:
            openWorkManifest()
        case .destination:
            // 目的地は自分の島のHUDから決める。ここでは何も開かない。
            showingWorkManifest = false
        case .logbook:
            showingWorkManifest = false
            presentedRoute = .logbook
        case .island:
            showingWorkManifest = false
            presentedRoute = .island
        case .harbor:
            showingWorkManifest = false
            presentedRoute = .harbor
        case .style:
            showingWorkManifest = false
            presentedRoute = .style
        }
    }

    private var harborCoach: some View {
        HStack(spacing: 9) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(LFColor.returnOrange)
            Text("Touch the ship to set sail.")
                .font(LFFont.label(11))
                .foregroundStyle(LFColor.harborTeal)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.white.opacity(0.78), in: Capsule())
        .overlay(Capsule().stroke(LFColor.harborTeal.opacity(0.16), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.13), radius: 10, y: 5)
        .fixedSize()
        .allowsHitTesting(false)
    }

    private func workManifest(
        availableWidth: CGFloat,
        availableHeight: CGFloat
    ) -> some View {
        let wide = availableWidth >= 760
        let panelWidth = max(0, min(wide ? 470 : 620, availableWidth - 24))
        let scrollMaxHeight = min(
            wide ? 410 : 330,
            max(80, availableHeight - 64)
        )
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
            count: 4
        )
        let manifestItems = orderedManifestItems

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer(minLength: 8)

                if todayTotal > 0 {
                    Text(LF.duration(minutes: todayTotal))
                        .font(LFFont.label(10))
                        .foregroundStyle(LFColor.returnOrange)
                        .monospacedDigit()
                }

                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        manifestEditing.toggle()
                    }
                    Haptics.tap(.light)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: manifestEditing ? "checkmark" : "pencil")
                            .font(.system(size: 10, weight: .semibold))
                        if manifestEditing {
                            Text("Done")
                        } else {
                            Text("Edit")
                        }
                    }
                    .font(LFFont.label(10))
                    .foregroundStyle(LFColor.harborTeal)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(LFColor.harborTeal.opacity(0.07), in: Capsule())
                    .overlay(Capsule().stroke(LFColor.harborTeal.opacity(0.12), lineWidth: 1))
                    // Keep the edit control visually compact while preserving a reliable tap target.
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(LFPressableButtonStyle())
                .disabled(items.isEmpty)
                .opacity(items.isEmpty ? 0.42 : 1)
                .accessibilityLabel(Text(manifestEditing ? "Done" : "Edit items"))

                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        showingWorkManifest = false
                    }
                    Haptics.tap(.light)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LFColor.harborTeal)
                        .frame(width: 44, height: 44)
                        .background(LFColor.harborTeal.opacity(0.07), in: Circle())
                }
                .buttonStyle(LFPressableButtonStyle())
                .accessibilityLabel(Text("Close"))
                .accessibilityFocused($workManifestAccessibilityFocused)
                .focused($workManifestKeyboardFocused)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            ScrollView(.vertical, showsIndicators: false) {
                if items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 25, weight: .light))
                            .foregroundStyle(LFColor.harborTeal.opacity(0.42))
                        Text("Create your first work item, then load it onto the ship.")
                            .font(LFFont.copy(13))
                            .foregroundStyle(LFColor.harborTeal.opacity(0.68))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 250)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }

                ZStack(alignment: .topLeading) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(manifestItems) { item in
                            manifestItemTile(item)
                        }
                        addItemTile
                    }

                    manifestDragOverlay(in: manifestItems)
                }
                .coordinateSpace(name: WorkManifestGridSpace.name)
                .onPreferenceChange(WorkManifestItemFramePreferenceKey.self) { frames in
                    manifestItemFrames = frames
                }
                .animation(
                    .spring(response: 0.24, dampingFraction: 0.84),
                    value: manifestItemOrder
                )
                .padding(12)
            }
            .frame(minHeight: min(180, scrollMaxHeight), maxHeight: scrollMaxHeight)
        }
        .frame(width: panelWidth)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: 0xFAF8F0).opacity(0.97),
                    Color(hex: 0xEAF5EE).opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(LFColor.harborTeal.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 20, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(Text("Work items"))
        .onAppear {
            synchronizeManifestOrder()
        }
        .onChange(of: items.map(\.uuid)) { _, _ in
            guard manifestDraggedItemID == nil else { return }
            synchronizeManifestOrder()
        }
        .onDisappear {
            resetManifestDragState()
            manifestItemFrames = [:]
            manifestEditing = false
        }
    }

    private func scenicHeight(in geometry: GeometryProxy) -> CGFloat {
        // 島と目的地表示が重ならないだけの航海映像を先に見せる。
        // 作業項目の後は「今日の記録／共有」までを初期画面の目安とし、
        // 記録行そのものは上へスクロールして初めて見える位置へ送る。
        let proposed = geometry.size.height * (geometry.size.width < 600 ? 0.58 : 0.54)
        return min(550, max(390, proposed))
    }

    // MARK: - 上部固定UI

    private var topChrome: some View {
        HStack(alignment: .top) {
            dateChip

            Spacer()

            noticeBoardShortcut

            Button {
                menuOpen.toggle()
                if menuOpen { showingWorkManifest = false }
                Haptics.tap(.light)
            } label: {
                ZStack {
                    Circle()
                        .fill(palette.glassColor.opacity(0.90))
                    TabSymbolIcon.image(.compass)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 21, height: 21)
                        .foregroundStyle(palette.inkColor)
                    if menuOpen {
                        Circle()
                            .stroke(LFColor.returnOrange.opacity(0.72), lineWidth: 1.5)
                            .padding(2)
                    }
                }
                .frame(width: 44, height: 44)
                .overlay(
                    Circle()
                        .stroke(LFColor.harborSand.opacity(0.38), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 7, y: 3)
            }
            .buttonStyle(LFPressableButtonStyle())
            .accessibilityLabel(Text("Main navigation"))
            .accessibilityValue(Text(menuOpen ? "Open" : "Closed"))
        }
        .padding(.horizontal, 12)
        .safeAreaPadding(.top, 10)
        .allowsHitTesting(true)
    }

    private var dateChip: some View {
        Button {
            menuOpen = false
            showingTrace = true
            Haptics.tap(.light)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(now, format: .dateTime.weekday(.wide))
                    .font(LFFont.label(10))
                    .foregroundStyle(LFColor.returnOrange)
                    .lineLimit(1)
                Text(now, format: .dateTime.month(.wide).day())
                    .font(LFFont.label(12))
                    .foregroundStyle(palette.inkColor)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(palette.inkColor.opacity(0.42))
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(
                palette.glassColor.opacity(0.92),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(LFColor.harborSand.opacity(0.26), lineWidth: 1)
            )
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityLabel(Text("Open Trace"))
        .accessibilityValue(Text(LF.dayWithWeekday(now)))
    }

    private var noticeBoardShortcut: some View {
        Button(action: openVoyageNoticeBoard) {
            Label("Voyage Notice Board", systemImage: "signpost.right.and.left.fill")
                .font(LFFont.label(11))
                .foregroundStyle(palette.inkColor)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(
                    palette.glassColor.opacity(0.92),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(LFColor.harborSand.opacity(0.38), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.12), radius: 7, y: 3)
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityHint(Text("Open public harbors and private islands"))
    }

    private var commandMenu: some View {
        GeometryReader { geometry in
            let maxPanelHeight = max(
                120,
                geometry.size.height
                    - geometry.safeAreaInsets.top
                    - geometry.safeAreaInsets.bottom
                    - 76
            )
            ZStack(alignment: .topTrailing) {
                Button {
                    menuOpen = false
                } label: {
                    Color.black
                        .opacity(0.34)
                        .ignoresSafeArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
                .keyboardShortcut(.cancelAction)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        Button {
                            menuOpen = false
                            activateHarborHotspot(.work)
                        } label: {
                            HStack(spacing: 11) {
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(LFColor.returnOrange)
                                .frame(width: 34, height: 34)
                                .background(palette.inkColor.opacity(0.06), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Cargo manifest")
                                    .font(LFFont.copy(13))
                                Text("Choose cargo and set sail")
                                    .font(LFFont.label(8))
                                    .foregroundStyle(palette.inkColor.opacity(0.46))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(palette.inkColor.opacity(0.34))
                            }
                            .foregroundStyle(palette.inkColor)
                            .padding(.horizontal, 11)
                            .frame(height: 52)
                            .background(
                                palette.inkColor.opacity(0.045),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(palette.inkColor.opacity(0.10), lineWidth: 1)
                            )
                        }
                        .buttonStyle(LFPressableButtonStyle())
                        .focused($commandMenuKeyboardFocused)
                        .accessibilityFocused($commandMenuAccessibilityFocused)

                        noticeBoardCommandButton

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)
                            ],
                            spacing: 8
                        ) {
                            ForEach(
                                VoyageMenuDestination.allCases.filter {
                                    $0 != .home && $0 != .harbor
                                }
                            ) { route in
                                commandDestinationButton(route)
                            }
                        }

                        helpCommandButton
                        settingsCommandButton
                    }
                    .padding(14)
                }
                .frame(width: max(0, min(354, geometry.size.width - 24)))
                .frame(maxHeight: maxPanelHeight)
                .background(
                    LinearGradient(
                        colors: [
                            palette.glassColor.opacity(0.99),
                            palette.glassColor.opacity(0.95)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(LFColor.harborSand.opacity(0.42), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    menuCornerMark
                        .padding(8)
                }
                .overlay(alignment: .bottomTrailing) {
                    menuCornerMark
                        .rotationEffect(.degrees(180))
                        .padding(8)
                }
                .shadow(color: .black.opacity(0.34), radius: 24, y: 14)
                .padding(.trailing, 12)
                .safeAreaPadding(.top, 62)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
            }
        }
        .zIndex(20)
    }

    private func commandDestinationButton(_ route: VoyageMenuDestination) -> some View {
        Button {
            menuOpen = false
            showingWorkManifest = false
            presentedRoute = route
            Haptics.tap(.light)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(palette.inkColor.opacity(0.07))
                        route.icon
                            .frame(width: 29, height: 29)
                    }
                    .frame(width: 45, height: 45)

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(LFColor.harborSand.opacity(0.56))
                }

                Text(verbatim: route.title)
                    .font(LFFont.copy(13))
                    .foregroundStyle(palette.inkColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .allowsTightening(true)

                Text(route.subtitle)
                    .font(LFFont.label(8))
                    .foregroundStyle(palette.inkColor.opacity(0.46))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(
                palette.inkColor.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(palette.inkColor.opacity(0.10), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LFPressableButtonStyle())
    }

    private var noticeBoardCommandButton: some View {
        Button(action: openVoyageNoticeBoard) {
            HStack(spacing: 12) {
                Image(systemName: "signpost.right.and.left.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Voyage Notice Board")
                        .font(LFFont.copy(14))
                    Text("Meet sailors publicly, or host and join private islands.")
                        .font(LFFont.label(9))
                        .foregroundStyle(Color.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.68))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(minHeight: 64)
            .background(
                LFColor.harborTeal,
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(LFColor.harborSand.opacity(0.28), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityHint(Text("Open public harbors and private islands"))
    }

    private var settingsCommandButton: some View {
        Button {
            menuOpen = false
            showingSettings = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(palette.inkColor.opacity(0.06), in: Circle())
                Text("Settings")
                    .font(LFFont.label(11))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.inkColor.opacity(0.34))
            }
            .foregroundStyle(palette.inkColor.opacity(0.70))
            .padding(.horizontal, 9)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(LFPressableButtonStyle())
    }

    private var helpCommandButton: some View {
        Button {
            menuOpen = false
            showingHelp = true
            Haptics.tap(.light)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 28, height: 28)
                    .background(palette.inkColor.opacity(0.06), in: Circle())
                Text("Help")
                    .font(LFFont.label(11))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.inkColor.opacity(0.34))
            }
            .foregroundStyle(palette.inkColor.opacity(0.70))
            .padding(.horizontal, 9)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(LFPressableButtonStyle())
    }

    private func openVoyageNoticeBoard() {
        menuOpen = false
        showingWorkManifest = false
        noticeBoardRequestID = UUID()
        Haptics.tap(.light)
    }

    private var menuCornerMark: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(LFColor.harborSand.opacity(0.42))
                .frame(width: 18, height: 1)
            Rectangle()
                .fill(LFColor.harborSand.opacity(0.42))
                .frame(width: 1, height: 18)
        }
        .frame(width: 18, height: 18)
        .allowsHitTesting(false)
    }

    // MARK: - スクロール領域

    private func homeSections(availableWidth: CGFloat) -> some View {
        // GeometryReader は初回評価だけ幅0を渡すことがある。負のframeを
        // SwiftUIへ渡すと実行時警告になり、端末サイズによってはレイアウトが跳ねる。
        let maxContentWidth = max(0, min(760, availableWidth - 24))
        let columnCount = maxContentWidth >= 650 ? 5 : 4
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
            count: columnCount
        )

        return VStack(alignment: .leading, spacing: 0) {
            sectionChip("Items")

            if items.isEmpty {
                Text("Tap + to create your first item.")
                    .font(LFFont.copy(14))
                    .foregroundStyle(palette.inkColor.opacity(0.62))
                    .padding(14)
                    .background(
                        palette.glassColor.opacity(0.88),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                    .padding(.top, 10)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(items) { item in
                    itemTile(item)
                }
                addItemTile
            }
            .padding(.top, 10)

            if !todaySessions.isEmpty {
                HStack(spacing: 8) {
                    sectionChip(
                        "Today's log",
                        detail: todayTotal > 0 ? LF.duration(minutes: todayTotal) : nil
                    )
                    Spacer()
                    Button {
                        sharingToday = true
                        Haptics.tap(.light)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(palette.inkColor.opacity(0.62))
                            .frame(width: 38, height: 38)
                            .background(
                                palette.glassColor.opacity(0.91),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                            )
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .accessibilityLabel(Text("Share this day"))
                }
                .padding(.top, 28)

                VStack(spacing: 0) {
                    ForEach(Array(todaySessions.enumerated()), id: \.element.persistentModelID) {
                        index,
                        session in
                        if index > 0 {
                            Rectangle()
                                .fill(palette.inkColor.opacity(0.08))
                                .frame(height: 1)
                                .padding(.leading, 58)
                        }
                        logRow(session)
                    }
                }
                .padding(.horizontal, 12)
                .background(
                    palette.glassColor.opacity(0.90),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(LFColor.harborSand.opacity(0.28), lineWidth: 1)
                )
                .padding(.top, 10)
            }
        }
        .frame(width: maxContentWidth, alignment: .leading)
        .padding(.bottom, 42)
    }

    private func sectionChip(
        _ title: LocalizedStringKey,
        detail: String? = nil
    ) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(LFFont.label(11))
                .tracking(1)
                .foregroundStyle(palette.inkColor.opacity(0.76))
            if let detail {
                Text(verbatim: " · \(detail)")
                    .font(LFFont.label(10))
                    .foregroundStyle(LFColor.returnOrange)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            palette.glassColor.opacity(0.92),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(LFColor.harborSand.opacity(0.32), lineWidth: 1)
        )
        .fixedSize()
    }

    /// 船を選んだ後の積荷画面では、カード全体を一つの出航操作にする。
    /// 名前だけが編集ボタンになる旧ホーム配置を持ち込まず、選択の迷いをなくす。
    private func manifestItemTile(_ item: StudyItem) -> some View {
        let timing = timerItemID == item.uuid.uuidString

        return ZStack(alignment: .topTrailing) {
            Button {
                if manifestEditing {
                    editingItem = item
                    return
                }
                guard manifestDraggedItemID == nil,
                      manifestSuppressTapItemID != item.uuid
                else { return }
                openOrStartVoyage(for: item)
            } label: {
                manifestItemTileArtwork(item)
                    .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(LFPressableButtonStyle())
            // Reordering belongs to the explicit edit state. Outside it the
            // card stays a plain Button, so a quick voyage tap cannot be
            // swallowed by the long-press recognizer.
            .simultaneousGesture(
                manifestReorderGesture(for: item),
                including: manifestEditing ? .all : .none
            )
            .accessibilityLabel(
                Text(
                    manifestEditing
                        ? "Edit item"
                        : (timing ? "Return to voyage" : "Start voyage")
                )
            )
            .accessibilityValue(Text(verbatim: item.name))
            .accessibilityHint(
                Text(
                    manifestEditing
                        ? "Long press and drag to rearrange"
                        : "Opens the voyage timer"
                )
            )
            .accessibilityActions {
                if manifestEditing {
                    Button("Edit item") {
                        editingItem = item
                    }
                }
                Button("Move earlier") {
                    moveItem(item.uuid, by: -1)
                }
                Button("Move later") {
                    moveItem(item.uuid, by: 1)
                }
            }

            if manifestEditing {
                Menu {
                    Button("Edit") {
                        editingItem = item
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LFColor.harborTeal)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.86), in: Circle())
                        .overlay(Circle().stroke(LFColor.harborTeal.opacity(0.12), lineWidth: 1))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Edit item"))
                .opacity(manifestDraggedItemID == item.uuid ? 0 : 1)
                .disabled(manifestDraggedItemID == item.uuid)
                .transition(.scale(scale: 0.86).combined(with: .opacity))
            }
        }
        .opacity(
            manifestDraggedItemID == item.uuid && manifestDragLocation != nil
                ? 0
                : 1
        )
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: WorkManifestItemFramePreferenceKey.self,
                    value: [
                        item.uuid: proxy.frame(in: .named(WorkManifestGridSpace.name))
                    ]
                )
            }
        }
        .shadow(
            color: LFColor.harborTeal.opacity(
                manifestDraggedItemID == item.uuid ? 0.24 : 0
            ),
            radius: manifestDraggedItemID == item.uuid ? 14 : 0,
            y: manifestDraggedItemID == item.uuid ? 8 : 0
        )
        .zIndex(manifestDraggedItemID == item.uuid ? 20 : 0)
    }

    private func manifestItemTileArtwork(_ item: StudyItem) -> some View {
        let total = totalByItem[item.uuid] ?? 0
        let timing = timerItemID == item.uuid.uuidString

        return VStack(spacing: 6) {
            ItemTileArt(item: item)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            timing ? LFColor.returnOrange : LFColor.harborTeal.opacity(0.14),
                            lineWidth: timing ? 2 : 1
                        )
                }

            Text(item.name)
                .font(LFFont.label(10.5))
                .foregroundStyle(LFColor.harborTeal)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if timing {
                Text("Return to voyage")
                    .font(LFFont.label(8))
                    .foregroundStyle(LFColor.returnOrange)
                    .lineLimit(1)
            } else if total > 0 {
                Text(LF.duration(minutes: total))
                    .font(LFFont.label(8.5))
                    .foregroundStyle(LFColor.harborTeal.opacity(0.54))
                    .monospacedDigit()
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(
            Color.white.opacity(0.66),
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
    }

    private var orderedManifestItems: [StudyItem] {
        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.uuid, $0) })
        let orderedIDs = Set(manifestItemOrder)
        var ordered = manifestItemOrder.compactMap { itemsByID[$0] }
        ordered.append(contentsOf: items.filter { !orderedIDs.contains($0.uuid) })
        return ordered
    }

    @ViewBuilder
    private func manifestDragOverlay(in manifestItems: [StudyItem]) -> some View {
        if let itemID = manifestDraggedItemID,
           let location = manifestDragLocation,
           let frame = manifestItemFrames[itemID],
           let item = manifestItems.first(where: { $0.uuid == itemID }) {
            manifestItemTileArtwork(item)
                .frame(width: frame.width, height: frame.height)
                .scaleEffect(1.055)
                .shadow(color: LFColor.harborTeal.opacity(0.28), radius: 16, y: 10)
                .position(
                    x: location.x - manifestDragGrabOffset.width + frame.width / 2,
                    y: location.y - manifestDragGrabOffset.height + frame.height / 2
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(100)
        }
    }

    private func manifestReorderGesture(
        for item: StudyItem
    ) -> some Gesture {
        LongPressGesture(minimumDuration: 0.20, maximumDistance: 20)
            .sequenced(
                before: DragGesture(
                    minimumDistance: 0,
                    coordinateSpace: .named(WorkManifestGridSpace.name)
                )
            )
            .onChanged { value in
                switch value {
                case .first(true):
                    beginManifestDrag(item.uuid)
                case .second(true, let drag?):
                    beginManifestDrag(item.uuid)
                    updateManifestDrag(item.uuid, drag: drag)
                default:
                    break
                }
            }
            .onEnded { _ in
                finishManifestDrag(item.uuid)
            }
    }

    private func synchronizeManifestOrder() {
        guard manifestDraggedItemID == nil else { return }
        manifestItemOrder = items.map(\.uuid)
    }

    private func beginManifestDrag(_ itemID: UUID) {
        guard manifestDraggedItemID == nil else { return }
        if manifestItemOrder.isEmpty {
            manifestItemOrder = items.map(\.uuid)
        }
        guard manifestItemOrder.contains(itemID) else { return }
        manifestDraggedItemID = itemID
        manifestDragStartOrder = manifestItemOrder
        manifestSuppressTapItemID = itemID
        manifestLastTargetID = nil
        manifestLastReorderLocation = nil
        Haptics.tap(.rigid)
    }

    private func updateManifestDrag(
        _ itemID: UUID,
        drag: DragGesture.Value
    ) {
        guard manifestDraggedItemID == itemID,
              let itemFrame = manifestItemFrames[itemID]
        else { return }

        if manifestDragLocation == nil {
            manifestDragGrabOffset = CGSize(
                width: drag.startLocation.x - itemFrame.minX,
                height: drag.startLocation.y - itemFrame.minY
            )
        }
        manifestDragLocation = drag.location

        let expandedFrames = manifestItemFrames.filter { $0.key != itemID }
        let candidates = expandedFrames.filter { _, frame in
            frame.insetBy(dx: -5, dy: -6).contains(drag.location)
        }
        guard let target = candidates.min(by: { lhs, rhs in
            let lhsDX = lhs.value.midX - drag.location.x
            let lhsDY = lhs.value.midY - drag.location.y
            let rhsDX = rhs.value.midX - drag.location.x
            let rhsDY = rhs.value.midY - drag.location.y
            let lhsDistance = lhsDX * lhsDX + lhsDY * lhsDY
            let rhsDistance = rhsDX * rhsDX + rhsDY * rhsDY
            return lhsDistance < rhsDistance
        }) else {
            manifestLastTargetID = nil
            manifestLastReorderLocation = nil
            return
        }

        if target.key == manifestLastTargetID { return }
        if let previousLocation = manifestLastReorderLocation {
            let distance = hypot(
                drag.location.x - previousLocation.x,
                drag.location.y - previousLocation.y
            )
            guard distance >= 10 else { return }
        }
        guard let sourceIndex = manifestItemOrder.firstIndex(of: itemID),
              let targetIndex = manifestItemOrder.firstIndex(of: target.key),
              sourceIndex != targetIndex
        else { return }

        manifestLastTargetID = target.key
        manifestLastReorderLocation = drag.location
        withAnimation(.spring(response: 0.22, dampingFraction: 0.84)) {
            let movingID = manifestItemOrder.remove(at: sourceIndex)
            manifestItemOrder.insert(movingID, at: targetIndex)
        }
        Haptics.tap(.light)
    }

    private func finishManifestDrag(_ itemID: UUID) {
        guard manifestDraggedItemID == itemID else { return }
        let finalOrder = manifestItemOrder
        let changed = finalOrder != manifestDragStartOrder

        manifestDraggedItemID = nil
        manifestDragStartOrder = []
        manifestDragLocation = nil
        manifestDragGrabOffset = .zero
        manifestLastTargetID = nil
        manifestLastReorderLocation = nil

        if changed {
            persistManifestOrder(finalOrder)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard manifestSuppressTapItemID == itemID,
                  manifestDraggedItemID == nil
            else { return }
            manifestSuppressTapItemID = nil
        }
    }

    private func resetManifestDragState() {
        manifestDraggedItemID = nil
        manifestDragStartOrder = []
        manifestDragLocation = nil
        manifestDragGrabOffset = .zero
        manifestLastTargetID = nil
        manifestLastReorderLocation = nil
        manifestSuppressTapItemID = nil
    }

    private func persistManifestOrder(_ orderedIDs: [UUID]) {
        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.uuid, $0) })
        let normalizedItems = orderedIDs.compactMap { itemsByID[$0] }
        guard normalizedItems.count == items.count else {
            synchronizeManifestOrder()
            return
        }

        let changedAt = Date()
        var changedItems: [StudyItem] = []
        for (index, item) in normalizedItems.enumerated() where item.sortOrder != index {
            item.sortOrder = index
            item.updatedAt = changedAt
            changedItems.append(item)
        }
        guard !changedItems.isEmpty else { return }

        do {
            try modelContext.save()
            for item in changedItems {
                SyncService.shared.push(item)
            }
        } catch {
            modelContext.rollback()
            synchronizeManifestOrder()
        }
    }

    private func itemTile(_ item: StudyItem) -> some View {
        let total = totalByItem[item.uuid] ?? 0
        let timing = timerItemID == item.uuid.uuidString
        let dragging = draggedItemID == item.uuid

        return VStack(spacing: 7) {
            Button {
                openOrStartVoyage(for: item)
            } label: {
                ItemTileArt(item: item)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                timing ? LFColor.returnOrange : LFColor.harborSand.opacity(0.20),
                                lineWidth: timing ? 2 : 1
                            )
                    }
                    .shadow(color: Color(hex: 0x031818).opacity(0.12), radius: 10, y: 6)
            }
            .buttonStyle(LFPressableButtonStyle())
            .accessibilityLabel(Text(timing ? "Return to voyage" : "Start voyage"))
            .accessibilityValue(Text(verbatim: item.name))

            Button {
                editingItem = item
                Haptics.tap(.light)
            } label: {
                VStack(spacing: 1) {
                    Text(item.name)
                        .font(LFFont.label(11.5))
                        .foregroundStyle(palette.inkColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    if total > 0 {
                        Text(LF.duration(minutes: total))
                            .font(LFFont.label(10))
                            .foregroundStyle(LFColor.returnOrange)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 42)
                .padding(.horizontal, 4)
                .background(
                    palette.glassColor.opacity(0.95),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(LFColor.harborSand.opacity(0.28), lineWidth: 1)
                )
            }
            .buttonStyle(LFPressableButtonStyle())
            .accessibilityLabel(Text("Edit item"))
            .accessibilityValue(Text(verbatim: item.name))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Move earlier")) {
            moveItem(item.uuid, by: -1)
        }
        .accessibilityAction(named: Text("Move later")) {
            moveItem(item.uuid, by: 1)
        }
        .scaleEffect(dragging ? 1.07 : 1)
        .opacity(dragging ? 0.78 : 1)
        .shadow(
            color: Color(hex: 0x031818).opacity(dragging ? 0.28 : 0),
            radius: dragging ? 18 : 0,
            y: dragging ? 12 : 0
        )
        .zIndex(dragging ? 20 : 0)
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: dragging)
        // 長押しはタイル全体の並べ替え、短押しはアイコン/名前ごとの操作に分ける。
        .onDrag {
            draggedItemID = item.uuid
            lastDragTargetID = nil
            Haptics.tap(.rigid)
            return NSItemProvider(object: item.uuid.uuidString as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: HomeItemDropDelegate(
                targetID: item.uuid,
                draggedItemID: $draggedItemID,
                lastTargetID: $lastDragTargetID,
                onMove: reorderItem
            )
        )
    }

    /// Webホームの末尾にある破線の「＋」タイルと同じ、作業項目の作成入口。
    /// 目的地のカメラ操作とは別のstateで管理し、目的地UIを変えても消えないようにする。
    private var addItemTile: some View {
        Button {
            creatingItem = true
            Haptics.tap(.light)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(palette.glassColor.opacity(0.54))
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        palette.inkColor.opacity(0.36),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )
                Image(systemName: "plus")
                    .font(.system(size: 27, weight: .regular))
                    .foregroundStyle(palette.inkColor.opacity(0.58))
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityLabel(Text("Add work item"))
        .accessibilityHint(Text("Create a new work item"))
    }

    private func logRow(_ session: StudySession) -> some View {
        HStack(spacing: 12) {
            Group {
                if let item = session.item {
                    ItemTileArt(item: item)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(palette.inkColor.opacity(0.10))
                }
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.item?.name ?? "—")
                    .font(LFFont.copy(15))
                    .foregroundStyle(palette.inkColor)
                    .lineLimit(1)
                Text(rowSubtitle(session))
                    .font(LFFont.label(12))
                    .foregroundStyle(palette.inkColor.opacity(0.52))
                    .lineLimit(1)
            }

            Spacer(minLength: 5)

            Text(LF.duration(minutes: session.minutes))
                .font(LFFont.label(13))
                .foregroundStyle(palette.inkColor.opacity(0.74))
                .monospacedDigit()

            Button {
                pendingDelete = session
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(LFColor.deepRust)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Delete"))
        }
        .padding(.vertical, 11)
    }

    private func rowSubtitle(_ session: StudySession) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: session.date)
        let time = String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
        guard let note = session.note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty else {
            return time
        }
        return "\(time) · \(note)"
    }

    /// ドラッグ中に別のタイルへ入った時点で並びを追従させ、その順序を同期対象として保存する。
    private func reorderItem(_ movingID: UUID, beforeOrAfter targetID: UUID) {
        guard movingID != targetID,
              let sourceIndex = items.firstIndex(where: { $0.uuid == movingID }),
              let targetIndex = items.firstIndex(where: { $0.uuid == targetID }),
              sourceIndex != targetIndex else { return }

        var reordered = Array(items)
        let moving = reordered.remove(at: sourceIndex)
        reordered.insert(moving, at: targetIndex)

        let changedAt = Date()
        var changed: [StudyItem] = []
        for (index, item) in reordered.enumerated() where item.sortOrder != index {
            item.sortOrder = index
            item.updatedAt = changedAt
            changed.append(item)
        }
        try? modelContext.save()
        for item in changed {
            SyncService.shared.push(item)
        }
        Haptics.tap(.light)
    }

    private func moveItem(_ itemID: UUID, by offset: Int) {
        guard let index = items.firstIndex(where: { $0.uuid == itemID }) else { return }
        let destination = index + offset
        guard items.indices.contains(destination) else { return }
        reorderItem(itemID, beforeOrAfter: items[destination].uuid)
    }

    // MARK: - 更新

    private func openOrStartVoyage(for item: StudyItem) {
        if timerStart > 0 {
            if timerItemID == item.uuid.uuidString {
                presentTimerVoyage(item)
                Haptics.tap(.light)
            } else {
                pendingTimerSwitch = item
                Haptics.tap(.medium)
            }
            return
        }
        beginVoyage(for: item)
    }

    private func beginVoyage(for item: StudyItem) {
        guard pendingIslandLaunchItem == nil else { return }
        menuOpen = false
        withAnimation(.easeOut(duration: 0.18)) {
            showingWorkManifest = false
        }
        pendingIslandLaunchItem = item
        homeIslandBoardingRequest = HomeIslandBoatBoardingRequest()
        Haptics.tap(.medium)
    }

    private func presentTimerVoyage(_ item: StudyItem) {
        menuOpen = false
        showingWorkManifest = false
        timerSceneReturning = false
        timerSceneReady = true
        timerSceneNow = Date()
        timerVoyageItem = item
    }

    private func dismissTimerVoyage() {
        guard timerVoyageItem != nil else { return }
        // The island leaves the hierarchy while the timer voyage is visible.
        // Give it a new identity on return so SwiftUI cannot restore the
        // pre-voyage departure state (input locked, boarding latched and the
        // boat already cast off). The rebuilt scene starts moored in Explore.
        homeIslandSceneGeneration = UUID()
        withAnimation(.easeOut(duration: 0.18)) {
            timerSceneReady = false
            timerVoyageItem = nil
        }
        timerSceneReturning = false
        homeIslandBoardingRequest = nil
        if let request = pendingManualAfterTimerReturn {
            pendingManualAfterTimerReturn = nil
            manualRequest = request
        }
    }

    private func clearOrphanedTimer() {
        guard timerStart > 0, currentTimerItem == nil else { return }
        StudyTimer.clearAll()
    }

    private func deleteSession(_ session: StudySession) {
        let date = session.date
        SyncService.shared.delete(session)
        modelContext.delete(session)
        StudyDayStore.unmarkDayIfEmpty(date, context: modelContext)
        try? modelContext.save()
        PublicHarborService.shared.publishCurrentMonth(context: modelContext)
        WidgetBridge.refresh(context: modelContext)
        Haptics.tap()
    }

    /// Web版と同じく、条件を満たしただけでは航海を締めない。
    /// カードの「上陸する」を本人が押した時点で初めて achievedAt を刻む。
    private func land(_ destination: Destination) {
        guard destination.achievedAt == nil else { return }
        let landedAt = Date()
        destination.achievedAt = landedAt
        destination.updatedAt = landedAt
        try? modelContext.save()
        SyncService.shared.push(destination)
        Haptics.success()
        // confirmationDialog の閉じアニメーションと fullScreenCover を
        // 同時に走らせると、記録だけ残って着岸演出が開かない。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            celebrating = destination
        }
    }

    private func markComplete(_ destination: Destination) {
        guard destination.manual, !destination.manualDone else { return }
        destination.manualDone = true
        destination.updatedAt = Date()
        try? modelContext.save()
        SyncService.shared.push(destination)
        Haptics.success()
    }
}

/// ホーム専用の「自分の島」。編集UIや徒歩操作は持たず、保存済みの島と
/// 係留船を見せ、船から作業項目選択と既存の出航演出へつなぐ。
private struct VoyageHomeIslandSceneHost: View {
    let ownerID: String
    let levelProgress: PlayerLevelProgress
    let boardingRequest: HomeIslandBoatBoardingRequest?
    let noticeBoardRequestID: UUID?
    let onBoatSelected: () -> Void
    let multiplayerSession: HomeIslandMultiplayerSession?
    let onPrivateIslandSelected: (PrivateIslandRoom) -> Void
    let onDepartureCompleted: () -> Void
    let onBoardingRejected: () -> Void
    let onDestinationLandfall: (Destination) -> Void

    var body: some View {
        HomeIslandView(
            ownerID: ownerID,
            levelProgress: levelProgress,
            startsMooredAtIsland: true,
            boatTapOpensSelection: true,
            boardingRequest: boardingRequest,
            noticeBoardRequestID: noticeBoardRequestID,
            onBoatSelected: onBoatSelected,
            onDepartureCompleted: onDepartureCompleted,
            onBoardingRejected: onBoardingRejected,
            showsDestination: true,
            onDestinationLandfall: onDestinationLandfall,
            multiplayerSession: multiplayerSession,
            onPrivateIslandSelected: onPrivateIslandSelected
        )
    }
}

private enum WorkManifestGridSpace {
    static let name = "workManifestGrid"
}

private struct WorkManifestItemFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(
        value: inout [UUID: CGRect],
        nextValue: () -> [UUID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

/// 長押しで持ち上げた作業項目を、指が入ったタイルの位置へライブで移す。
private struct HomeItemDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedItemID: UUID?
    @Binding var lastTargetID: UUID?
    let onMove: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let movingID = draggedItemID,
              movingID != targetID,
              lastTargetID != targetID else { return }
        lastTargetID = targetID
        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            onMove(movingID, targetID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItemID = nil
        lastTargetID = nil
        return true
    }
}

/// ログイン画面・設定画面・実アプリアイコンと同じ KeelMira のブランド記号。
/// 単独の島記号を避け、「帰る帆と望む陸地」をホームの入口にも使う。
private struct KeelMiraHomeMark: View {
    var body: some View {
        AppIconArt(option: .harbor)
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(LFColor.harborSand.opacity(0.26), lineWidth: 1)
            }
    }
}

enum VoyageMenuDestination: String, CaseIterable, Identifiable {
    case home
    case island
    case harbor
    case logbook
    case style

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: LF.text("Home")
        case .island: PlayerProfile.islandName
        case .harbor: LF.text("Harbor")
        case .logbook: LF.text("Logbook")
        case .style: LF.text("Style")
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .home: "Your voyage begins here"
        case .island: "Build and explore"
        case .harbor: "Meet the crew"
        case .logbook: "Read your voyage records"
        case .style: "Change your look"
        }
    }

    @MainActor @ViewBuilder
    var icon: some View {
        switch self {
        case .home:
            TabSymbolIcon.image(.wheel).resizable().scaledToFit()
        case .island:
            TabSymbolIcon.image(.island).resizable().scaledToFit()
        case .harbor:
            TabSymbolIcon.image(.lighthouse).resizable().scaledToFit()
        case .logbook:
            TabSymbolIcon.image(.book).resizable().scaledToFit()
        case .style:
            TabSymbolIcon.image(.sailboat).resizable().scaledToFit()
        }
    }
}

/// 既存画面は一切作り替えず、ホームから開くための閉じる口だけを外側へ足す。
private struct VoyageRouteContainer: View {
    @Environment(\.dismiss) private var dismiss
    let route: VoyageMenuDestination
    let onPrivateIslandSelected: (PrivateIslandRoom) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch route {
            case .island:
                HomeIslandEntryView()
            case .harbor:
                HarborView(onPrivateIslandSelected: onPrivateIslandSelected)
            case .style:
                DressView(onClose: { dismiss() })
            case .logbook:
                LogbookView()
            case .home:
                Color.clear
            }

            if route != .logbook && route != .style && route != .island {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LFColor.paper)
                        .frame(width: 36, height: 36)
                        .background(LFColor.ink, in: Circle())
                }
                .buttonStyle(LFPressableButtonStyle())
                .accessibilityLabel(Text("Close"))
                .padding(.leading, 12)
                .safeAreaPadding(.top, 8)
            }
        }
    }
}

#Preview {
    VoyageHomeView()
}
