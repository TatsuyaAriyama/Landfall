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
    @Query(sort: \StudyItem.sortOrder) private var items: [StudyItem]
    @Query private var sessions: [StudySession]
    @Query private var destinations: [Destination]

    @State private var now = Date()
    @State private var path = NavigationPath()
    @State private var menuOpen = false
    @State private var presentedRoute: VoyageMenuDestination?
    @State private var showingTrace = false
    @State private var showingSettings = false
    @State private var sharingToday = false
    @State private var creatingItem = false
    @State private var editingDestination = false
    @State private var destinationSceneReady = false
    @State private var destinationWorldTapToken = 0
    @State private var draggedItemID: UUID?
    @State private var lastDragTargetID: UUID?
    @State private var celebrating: Destination?
    @State private var pendingWorldLanding: Destination?
    @State private var pendingLandingDestination: Destination?
    @State private var pendingCompleteDestination: Destination?
    @State private var pendingDelete: StudySession?
    @State private var timerVoyageItem: StudyItem?
    @State private var pendingTimerSwitch: StudyItem?
    @State private var manualRequest: HomeManualRequest?

    @AppStorage(StudyTimer.startKey, store: StudyTimer.defaults) private var timerStart: Double = 0
    @AppStorage(StudyTimer.itemKey, store: StudyTimer.defaults) private var timerItemID = ""
    @StateObject private var sailAnimator = SailAnimator.shared
    @StateObject private var router = DeepLinkRouter.shared

    private let minuteClock = Timer.publish(
        every: 60,
        tolerance: 2,
        on: .main,
        in: .common
    ).autoconnect()

    private var timeOfDay: AftideHomeTimeOfDay {
        AftideHomeTimeOfDay.current(at: now)
    }

    private var palette: AftideHomePalette {
        timeOfDay.palette
    }

    private var activeDestination: Destination? {
        destinations.first { $0.achievedAt == nil }
    }

    private var destinationRatio: Double {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["LANDFALL_HOME_PROGRESS"],
           let value = Double(raw) {
            return min(1, max(0, value))
        }
        #endif
        return activeDestination?.progress(sessions: sessions, now: now).ratio ?? 0
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
                    AboardDestinationHomeSceneView(
                        ratio: destinationRatio,
                        timeOfDay: timeOfDay,
                        active: backdropActive,
                        editingDestination: editingDestination,
                        onCameraTransitionCompleted: { editing in
                            if editing {
                                withAnimation(.easeOut(duration: 0.24)) {
                                    destinationSceneReady = true
                                }
                            } else {
                                destinationSceneReady = false
                                if let landed = pendingWorldLanding {
                                    pendingWorldLanding = nil
                                    celebrating = landed
                                }
                            }
                        },
                        onTapWorld: {
                            guard editingDestination, destinationSceneReady else { return }
                            destinationWorldTapToken &+= 1
                        }
                    )
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            destinationSceneEntry(height: scenicHeight(in: geometry))
                            homeSections(availableWidth: geometry.size.width)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .accessibilityIdentifier("aftide-home-scroll")
                    .opacity(editingDestination || presentedRoute == .logbook ? 0 : 1)
                    .allowsHitTesting(!editingDestination && presentedRoute != .logbook)

                    topChrome
                        .opacity(editingDestination || presentedRoute == .logbook ? 0 : 1)
                        .allowsHitTesting(!editingDestination && presentedRoute != .logbook)

                    if menuOpen {
                        commandMenu
                            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
                    }

                    if editingDestination {
                        VoyageWorldView(
                            existing: activeDestination,
                            sessions: sessions,
                            usesHomeWorld: true,
                            homeWorldReady: destinationSceneReady,
                            homeWorldTapToken: destinationWorldTapToken,
                            onRequestClose: closeDestinationEditor,
                            onLand: { landed in
                                pendingWorldLanding = landed
                            }
                        )
                        .zIndex(30)
                    }
                }
                .background(Color(hex: palette.sky).ignoresSafeArea())
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
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $creatingItem) {
            ItemEditorSheet(existing: nil)
        }
        .fullScreenCover(isPresented: $showingTrace) {
            TraceView {
                showingTrace = false
            }
        }
        .sheet(item: $manualRequest) { request in
            HomeManualTimeSheet(
                item: request.item,
                initialMinutes: request.initialMinutes,
                onSaved: { now = Date() }
            )
        }
        .fullScreenCover(item: $timerVoyageItem) { item in
            HomeVoyageTimerView(
                item: item,
                hasDestination: activeDestination != nil,
                onMinimize: {
                    timerVoyageItem = nil
                },
                onManual: { minutes in
                    timerVoyageItem = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                        manualRequest = HomeManualRequest(
                            item: item,
                            initialMinutes: minutes
                        )
                    }
                },
                onReturnHome: {
                    timerVoyageItem = nil
                    now = Date()
                }
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
        .fullScreenCover(item: $presentedRoute) { route in
            if route == .logbook {
                VoyageRouteContainer(route: route)
                    .presentationBackground(.clear)
            } else {
                VoyageRouteContainer(route: route)
            }
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
        .overlay(alignment: .bottom) {
            if timerVoyageItem == nil, let item = currentTimerItem {
                HomeVoyageTimerChip(item: item) {
                    timerVoyageItem = item
                    Haptics.tap(.light)
                }
            }
        }
        .overlay {
            if let kind = sailAnimator.kind {
                SailingOverlay(kind: kind)
                    .transition(.opacity)
            }
        }
        .onReceive(minuteClock) { tick in
            now = tick
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            now = Date()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                now = Date()
            }
        }
        .onChange(of: router.wantsHarborTab) { _, wants in
            guard wants else { return }
            menuOpen = false
            presentedRoute = .harbor
            router.wantsHarborTab = false
        }
        .onAppear {
            clearOrphanedTimer()
            #if DEBUG
            DebugCardDump.runIfRequested()
            if ProcessInfo.processInfo.environment["LANDFALL_HOME_MENU"] == "1" {
                menuOpen = true
            }
            if ProcessInfo.processInfo.environment["LANDFALL_SETTINGS"] != nil {
                showingSettings = true
            }
            if ProcessInfo.processInfo.environment["LANDFALL_LOGBOOK"] != nil {
                presentedRoute = .logbook
            }
            if ProcessInfo.processInfo.environment["LANDFALL_EDIT_DEST"] != nil {
                editingDestination = true
            }
            #endif
        }
    }

    private var backdropActive: Bool {
        scenePhase == .active &&
        !menuOpen &&
        (presentedRoute == nil || presentedRoute == .logbook) &&
        !showingTrace &&
        !showingSettings &&
        sailAnimator.kind == nil
    }

    private func closeDestinationEditor() {
        destinationSceneReady = false
        editingDestination = false
    }

    private func scenicHeight(in geometry: GeometryProxy) -> CGFloat {
        // Webホームの約48dvh。縦長端末では作業項目が画面中央を越えすぎないよう
        // safe area分を見込んで49%に収める。
        let proposed = geometry.size.height * (geometry.size.width < 600 ? 0.49 : 0.47)
        return min(470, max(330, proposed))
    }

    /// ホームの航海映像そのものを目的地の入口にする。
    /// 独立カードは置かず、映像を押すとその構図から没入エディタへ移る。
    private func destinationSceneEntry(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Button {
                Haptics.tap(.light)
                editingDestination = true
            } label: {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Destinations"))
            .accessibilityValue(Text(destinationSceneAccessibilityValue))
            .accessibilityHint(Text("Tap to edit the destination."))

            HStack(alignment: .bottom, spacing: 12) {
                destinationSceneCaption
                    .allowsHitTesting(false)

                Spacer(minLength: 8)

                if let destination = activeDestination {
                    if !destination.manual || destination.manualDone {
                        Button {
                            pendingLandingDestination = destination
                        } label: {
                            Text("Go ashore")
                                .font(LFFont.copy(13))
                                .foregroundStyle(LFColor.inkFixed)
                                .padding(.horizontal, 18)
                                .frame(minHeight: 38)
                                .background(LFColor.harborSand, in: Capsule())
                        }
                        .buttonStyle(LFPressableButtonStyle())
                    } else {
                        Button {
                            pendingCompleteDestination = destination
                        } label: {
                            Text("Mark complete")
                                .font(LFFont.copy(13))
                                .foregroundStyle(palette.inkColor)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 38)
                                .background(
                                    palette.glassColor.opacity(0.76),
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(palette.inkColor.opacity(0.26), lineWidth: 1)
                                )
                        }
                        .buttonStyle(LFPressableButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(height: height)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var destinationSceneCaption: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Destinations")
                .font(LFFont.label(10))
                .tracking(1)
                .foregroundStyle(palette.inkColor.opacity(0.68))

            if let destination = activeDestination {
                Text(verbatim: destination.name)
                    .font(LFFont.copy(18))
                    .foregroundStyle(palette.inkColor)
                    .lineLimit(1)

                Text(destinationSceneProgress(destination))
                    .font(LFFont.label(11))
                    .foregroundStyle(palette.inkColor.opacity(0.68))
                    .lineLimit(1)
            } else {
                Text("Set a destination.")
                    .font(LFFont.copy(17))
                    .foregroundStyle(palette.inkColor)
            }
        }
        .shadow(color: Color.black.opacity(0.22), radius: 6, y: 2)
    }

    private var destinationSceneAccessibilityValue: String {
        guard let destination = activeDestination else {
            return LF.text("Set a destination.")
        }
        return "\(destination.name)、\(destinationSceneProgress(destination))"
    }

    private func destinationSceneProgress(_ destination: Destination) -> String {
        let progress = destination.progress(sessions: sessions, now: now)
        if progress.reached {
            return LF.text("Ready to go ashore")
        }
        if let next = destination.nextStepName {
            return LF.format("Next: %@", next)
        }
        if let total = progress.stepsTotal {
            return "\(progress.stepsDone ?? 0) / \(total)"
        }
        if let minutes = progress.remainingMinutes {
            if minutes < 60 {
                return LF.format("%lld minutes left", Int64(minutes))
            }
            let hours = minutes / 60
            let remainder = minutes % 60
            if remainder == 0 {
                return LF.format("%lld hours left", Int64(hours))
            }
            return LF.format(
                "%lld hours %lld minutes left",
                Int64(hours),
                Int64(remainder)
            )
        }
        if let seconds = progress.remainingSeconds {
            let minutes = max(0, Int(ceil(seconds / 60)))
            if minutes < 24 * 60 {
                return destinationRemainingMinutes(minutes)
            }
            let days = Int(ceil(seconds / 86_400))
            return LF.format("%lld days left", Int64(days))
        }
        if let days = progress.remainingDays {
            return LF.format("%lld days left", Int64(days))
        }
        return ""
    }

    private func destinationRemainingMinutes(_ minutes: Int) -> String {
        if minutes < 60 {
            return LF.format("%lld minutes left", Int64(minutes))
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return LF.format("%lld hours left", Int64(hours))
        }
        return LF.format(
            "%lld hours %lld minutes left",
            Int64(hours),
            Int64(remainder)
        )
    }

    // MARK: - 上部固定UI

    private var topChrome: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    path = NavigationPath()
                    menuOpen = false
                    Haptics.tap(.light)
                } label: {
                    KeelMiraHomeMark()
                        .frame(width: 46, height: 46)
                        .background(
                            palette.glassColor.opacity(0.92),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(LFColor.harborSand.opacity(0.38), lineWidth: 1)
                        )
                }
                .buttonStyle(LFPressableButtonStyle())
                .accessibilityLabel(Text("Home"))

                Spacer()

                Button {
                    menuOpen.toggle()
                    Haptics.tap(.light)
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(LFColor.harborTeal)
                            TileSymbolView(
                                symbol: .wheel,
                                fg: LFColor.harborSand,
                                bg: LFColor.harborTeal
                            )
                            .padding(6)
                        }
                        .frame(width: 34, height: 34)

                        Text("Home")
                            .font(LFFont.label(12))
                            .foregroundStyle(palette.inkColor)

                        Image(systemName: menuOpen ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.inkColor.opacity(0.55))
                    }
                    .padding(.leading, 5)
                    .padding(.trailing, 11)
                    .frame(height: 46)
                    .background(
                        palette.glassColor.opacity(0.92),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(LFColor.harborSand.opacity(0.38), lineWidth: 1)
                    )
                }
                .buttonStyle(LFPressableButtonStyle())
                .accessibilityLabel(Text("Main navigation"))
                .accessibilityValue(Text(menuOpen ? "Open" : "Closed"))
            }

            dateChip
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
            .frame(height: 30)
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

    private var commandMenu: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Button {
                    menuOpen = false
                } label: {
                    Color(hex: 0x184A40)
                        .opacity(0.16)
                        .ignoresSafeArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))

                VStack(spacing: 8) {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 5),
                            GridItem(.flexible(), spacing: 5)
                        ],
                        spacing: 5
                    ) {
                        ForEach(VoyageMenuDestination.allCases) { route in
                            commandButton(route)
                        }
                    }

                    Rectangle()
                        .fill(palette.inkColor.opacity(0.12))
                        .frame(height: 1)
                        .padding(.top, 2)

                    Button {
                        menuOpen = false
                        showingSettings = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 17, weight: .regular))
                                .frame(width: 27, height: 27)
                            Text("Settings")
                                .font(LFFont.label(13))
                            Spacer()
                        }
                        .foregroundStyle(palette.inkColor.opacity(0.78))
                        .padding(.horizontal, 10)
                        .frame(height: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(LFPressableButtonStyle())
                }
                .padding(12)
                .frame(width: max(0, min(320, geometry.size.width - 24)))
                .background(
                    palette.glassColor.opacity(0.97),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(LFColor.harborSand.opacity(0.34), lineWidth: 1)
                )
                .padding(.trailing, 12)
                .safeAreaPadding(.top, 66)
            }
        }
        .zIndex(20)
    }

    private func commandButton(_ route: VoyageMenuDestination) -> some View {
        Button {
            menuOpen = false
            if route != .home {
                presentedRoute = route
            }
            Haptics.tap(.light)
        } label: {
            HStack(spacing: 9) {
                route.icon
                    .frame(width: 27, height: 27)
                Text(route.title)
                    .font(LFFont.label(12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 0)
            }
            .foregroundStyle(palette.inkColor.opacity(route == .home ? 1 : 0.76))
            .padding(.horizontal, 9)
            .frame(height: 48)
            .background(
                route == .home ? LFColor.returnOrange.opacity(0.13) : Color.clear,
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityAddTraits(route == .home ? .isSelected : [])
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

    private func itemTile(_ item: StudyItem) -> some View {
        let total = totalByItem[item.uuid] ?? 0
        let timing = timerItemID == item.uuid.uuidString
        let dragging = draggedItemID == item.uuid

        return Button {
            openOrStartVoyage(for: item)
        } label: {
            VStack(spacing: 7) {
                ItemTileArt(item: item)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                timing ? LFColor.returnOrange : LFColor.harborSand.opacity(0.20),
                                lineWidth: timing ? 2 : 1
                            )
                    }
                    .shadow(color: Color(hex: 0x031818).opacity(0.12), radius: 10, y: 6)

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
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(item.name))
        .accessibilityHint(
            Text(timing ? "Return to voyage" : "Tap to start voyage. Long press to move.")
        )
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
        // iOSの標準ドラッグは長押しで始まるため、短押しの「航海開始」と競合しない。
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
                timerVoyageItem = item
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
        StudyTimer.begin(itemID: item.uuid.uuidString, itemName: item.name)
        timerVoyageItem = item
        Haptics.tap(.medium)
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
        RoomService.shared.publishCurrentMonth(context: modelContext)
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
    case harbor
    case logbook
    case style

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .harbor: "Harbor"
        case .logbook: "Logbook"
        case .style: "Style"
        }
    }

    @MainActor @ViewBuilder
    var icon: some View {
        switch self {
        case .home:
            TabSymbolIcon.image(.wheel).resizable().scaledToFit()
        case .harbor:
            TabSymbolIcon.image(.sailboat).resizable().scaledToFit()
        case .logbook:
            TabSymbolIcon.image(.book).resizable().scaledToFit()
        case .style:
            TabSymbolIcon.image(.attire).resizable().scaledToFit()
        }
    }
}

/// 既存画面は一切作り替えず、ホームから開くための閉じる口だけを外側へ足す。
private struct VoyageRouteContainer: View {
    @Environment(\.dismiss) private var dismiss
    let route: VoyageMenuDestination

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch route {
            case .harbor:
                HarborView()
            case .style:
                DressView(onClose: { dismiss() })
            case .logbook:
                LogbookView()
            case .home:
                Color.clear
            }

            if route != .logbook && route != .style {
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
