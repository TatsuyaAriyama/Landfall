import Combine
import SwiftUI
import SwiftData

/// 最新Web版の `home-ocean` と同じ、現地時刻で移ろう港の背景。
/// 港配下の画面で共用し、端末のライト/ダーク設定だけで白黒に戻らないようにする。
struct HarborOceanBackground: View {
    var timeOfDay: AftideHomeTimeOfDay = .current()

    private var palette: Palette { Palette(timeOfDay) }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: palette.skyA, location: 0),
                        .init(color: palette.skyB, location: 0.24),
                        .init(color: palette.seaA, location: 0.52),
                        .init(color: palette.seaB, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .fill(palette.glow.opacity(0.62))
                    .frame(width: 150, height: 150)
                    .blur(radius: 42)
                    .position(
                        x: geometry.size.width * palette.lightX,
                        y: max(72, geometry.size.height * 0.15)
                    )

                if palette.showsStars {
                    Group {
                        Circle().frame(width: 2, height: 2)
                            .position(x: geometry.size.width * 0.14, y: geometry.size.height * 0.08)
                        Circle().frame(width: 2.5, height: 2.5)
                            .position(x: geometry.size.width * 0.83, y: geometry.size.height * 0.24)
                        Circle().frame(width: 1.8, height: 1.8)
                            .position(x: geometry.size.width * 0.52, y: geometry.size.height * 0.13)
                    }
                    .foregroundStyle(Color(hex: 0xEEE8C9).opacity(timeOfDay == .night ? 0.6 : 0.32))
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private struct Palette {
        let skyA: Color
        let skyB: Color
        let seaA: Color
        let seaB: Color
        let glow: Color
        let lightX: CGFloat
        let showsStars: Bool

        init(_ timeOfDay: AftideHomeTimeOfDay) {
            switch timeOfDay {
            case .morning:
                (skyA, skyB, seaA, seaB, glow, lightX, showsStars) = (
                    Color(hex: 0xF7D4B5), Color(hex: 0xD9E8DD),
                    Color(hex: 0xA7D2C8), Color(hex: 0x73AAA7),
                    Color(hex: 0xFFF1C9), 0.20, false
                )
            case .day:
                (skyA, skyB, seaA, seaB, glow, lightX, showsStars) = (
                    Color(hex: 0xA9DEEB), Color(hex: 0xD7EEEA),
                    Color(hex: 0x8CC9CD), Color(hex: 0x4F969C),
                    Color(hex: 0xFFF5C8), 0.62, false
                )
            case .evening:
                (skyA, skyB, seaA, seaB, glow, lightX, showsStars) = (
                    Color(hex: 0xA85552), Color(hex: 0xDF9476),
                    Color(hex: 0x527E7B), Color(hex: 0x284F58),
                    Color(hex: 0xFFC27E), 0.78, true
                )
            case .night:
                (skyA, skyB, seaA, seaB, glow, lightX, showsStars) = (
                    Color(hex: 0x0B2927), Color(hex: 0x123A35),
                    Color(hex: 0x194B43), Color(hex: 0x0B2928),
                    Color(hex: 0xD8E0C8), 0.74, true
                )
            }
        }
    }
}

/// 「港」画面。同じ港のメンバーの軌跡(日ベースのみ)を互いに見られる。
/// 順位・ランキング・ストリークは作らない。休んだ日も学んだ日と同格に見える。
struct HarborView: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var privateIslandService = PrivateIslandService.shared
    @StateObject private var voyagePass = VoyagePassStore.shared
    @Environment(\.modelContext) private var modelContext

    @State private var isPrivateIslandLoading = true
    @State private var privateIslandLoadError: String?
    @StateObject private var router = DeepLinkRouter.shared
    @State private var joiningInviteCode: String?
    @State private var privateIslandError: String?
    @State private var privateIslandPendingClose: PrivateIslandRoom?
    /// パブリックの港(公式5港)。
    @StateObject private var publicService = PublicHarborService.shared
    @State private var navPath = NavigationPath()
    @State private var now = Date()
    @State private var showingPublicJournal = false
    @State private var showingVoyagePass = false
    @State private var publicHarborPendingLeave: PublicHarbor?
    @State private var publicHarborLeavingSlug: String?
    @State private var publicHarborLeaveError: String?
    private let showsOceanBackground: Bool
    private let onPublicHarborSelected: ((PublicHarbor) -> Void)?
    private let onPrivateIslandSelected: ((PrivateIslandRoom) -> Void)?

    init(
        showsOceanBackground: Bool = true,
        onPublicHarborSelected: ((PublicHarbor) -> Void)? = nil,
        onPrivateIslandSelected: ((PrivateIslandRoom) -> Void)? = nil
    ) {
        self.showsOceanBackground = showsOceanBackground
        self.onPublicHarborSelected = onPublicHarborSelected
        self.onPrivateIslandSelected = onPrivateIslandSelected
    }

    private let minuteClock = Timer.publish(
        every: 60,
        tolerance: 2,
        on: .main,
        in: .common
    ).autoconnect()

    private var timeOfDay: AftideHomeTimeOfDay {
        AftideHomeTimeOfDay.current(at: now)
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ZStack {
                if showsOceanBackground {
                    HarborOceanBackground(timeOfDay: timeOfDay)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        privateSection
                        publicSection
                    }
                    .padding(showsOceanBackground ? LFMetrics.cardPadding : 16)
                }
            }
            .navigationDestination(for: PublicHarbor.self) { harbor in
                PublicHarborView(
                    harbor: harbor,
                    showsOceanBackground: showsOceanBackground
                )
            }
            .navigationDestination(for: PublicMemberKey.self) { key in
                PublicMemberProfileView(
                    slug: key.slug,
                    initialMember: key.member,
                    showsOceanBackground: showsOceanBackground
                )
            }
        }
        .tint(timeOfDay.palette.inkColor)
        .preferredColorScheme(
            timeOfDay == .evening || timeOfDay == .night ? .dark : .light
        )
        .task {
            privateIslandService.listenToJoinedIslands()
            await reload()
        }
        .refreshable { await reload() }
        .onReceive(minuteClock) { now = $0 }
        .fullScreenCover(isPresented: $showingPublicJournal) {
            PublicJournalView()
        }
        .fullScreenCover(isPresented: $showingVoyagePass) {
            VoyagePassView()
        }
        // 招待リンクから開かれたら、新しいPrivate Islandへ参加してそのまま訪問する。
        .onChange(of: router.pendingJoinCode) { _, code in
            guard let code else { return }
            joinPrivateIslandInvite(code)
        }
        .onAppear {
            if let code = router.pendingJoinCode {
                joinPrivateIslandInvite(code)
            }
        }
        .onChange(of: auth.user?.uid) { _, _ in
            isPrivateIslandLoading = true
            privateIslandLoadError = nil
            privateIslandService.listenToJoinedIslands()
            Task { await reload() }
            if auth.isSignedIn, let code = router.pendingJoinCode {
                joinPrivateIslandInvite(code)
            }
        }
        .onDisappear {
            privateIslandService.stopJoinedIslandsListener()
        }
        .alert(
            "Couldn't open this private island.",
            isPresented: Binding(
                get: { privateIslandError != nil },
                set: { if !$0 { privateIslandError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { privateIslandError = nil }
        } message: {
            Text(verbatim: privateIslandError ?? "")
        }
        .alert(
            "Couldn't leave this harbor.",
            isPresented: Binding(
                get: { publicHarborLeaveError != nil },
                set: { if !$0 { publicHarborLeaveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { publicHarborLeaveError = nil }
        } message: {
            Text(verbatim: publicHarborLeaveError ?? "")
        }
        .confirmationDialog(
            "Leave this harbor?",
            isPresented: Binding(
                get: { publicHarborPendingLeave != nil },
                set: { if !$0 { publicHarborPendingLeave = nil } }
            ),
            titleVisibility: .visible,
            presenting: publicHarborPendingLeave
        ) { harbor in
            Button("Leave this harbor", role: .destructive) {
                publicHarborPendingLeave = nil
                leavePublicHarbor(harbor)
            }
            Button("Cancel", role: .cancel) { publicHarborPendingLeave = nil }
        } message: { _ in
            Text("Your name and shared records will be removed from this harbor. You can rejoin anytime.")
        }
        .confirmationDialog(
            "Close this private island?",
            isPresented: Binding(
                get: { privateIslandPendingClose != nil },
                set: { if !$0 { privateIslandPendingClose = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Close island permanently", role: .destructive) {
                guard let room = privateIslandPendingClose else { return }
                privateIslandPendingClose = nil
                Task {
                    do {
                        try await privateIslandService.closeIsland(room.code)
                        Haptics.success()
                    } catch {
                        privateIslandError = error.localizedDescription
                        Haptics.error()
                    }
                }
            }
            Button("Cancel", role: .cancel) { privateIslandPendingClose = nil }
        } message: {
            Text("The invite code, chat, members, and shared island snapshot will be deleted.")
        }
    }

    private func reload() async {
        isPrivateIslandLoading = true
        privateIslandLoadError = nil
        async let publicRefresh: Void = publicService.refresh()
        await privateIslandService.refreshIslands()
        privateIslandLoadError = privateIslandService.errorMessage
        isPrivateIslandLoading = false
        _ = await publicRefresh
        // Web版と同じ規則でサービス開始日を確定し、既存のカードにも補完する。
        PlayerProfile.rememberVoyageStart(
            context: modelContext,
            accountCreatedAt: auth.user?.metadata.creationDate
        )
        await publicService.syncProfile()
    }

    private func selectPrivateIsland(_ room: PrivateIslandRoom) {
        Haptics.tap(.medium)
        onPrivateIslandSelected?(room)
    }

    private func joinPrivateIslandInvite(_ rawCode: String) {
        guard auth.isSignedIn else { return }
        let code = PrivateIslandService.normalizedCode(rawCode)
        guard code.count == 6, joiningInviteCode != code else {
            router.pendingJoinCode = nil
            return
        }
        joiningInviteCode = code
        router.pendingJoinCode = nil

        Task {
            defer { joiningInviteCode = nil }
            do {
                let room = try await privateIslandService.joinIsland(code: code)
                Haptics.success()
                selectPrivateIsland(room)
            } catch {
                privateIslandError = error.localizedDescription
                Haptics.error()
            }
        }
    }

    // MARK: - Private island entry

    @ViewBuilder
    private var privateSection: some View {
        if horizontalSizeClass == .regular {
            Text("Private")
                .font(LFFont.label(13))
                .tracking(1)
                .foregroundStyle(LFColor.ink.opacity(0.5))
                .padding(.top, 8)
        }

        if !auth.isSignedIn {
            Text("Sign in to enter a harbor.")
                .font(LFFont.copy(16))
                .foregroundStyle(LFColor.ink.opacity(0.66))
                .padding(showsOceanBackground ? 18 : 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(showsOceanBackground ? 0 : 0.68))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.top, 10)
        } else if let privateIslandLoadError {
            Button {
                Task { await reload() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise")
                        .accessibilityHidden(true)
                    Text("Try again")
                        .font(LFFont.copy(14))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(timeOfDay.palette.inkColor)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(timeOfDay.palette.glassColor.opacity(0.86))
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(LFPressableButtonStyle())
            .accessibilityHint(Text(verbatim: privateIslandLoadError))
        } else {
            PrivateIslandLobbyView(
                rooms: privateIslandService.islands,
                currentUserID: privateIslandService.currentUserID ?? auth.user?.uid ?? "",
                isLoading: isPrivateIslandLoading,
                canHost: voyagePass.isActive,
                isHostAccessLoading: voyagePass.isLoading,
                onOpenVoyagePass: {
                    showingVoyagePass = true
                },
                onCreate: { name in
                    let ownerKey = HomeIslandPersistence.ownerKey(
                        for: auth.homeIslandOwnerID
                    )
                    let code = try await privateIslandService.createIsland(
                        name: name,
                        initialSnapshot: HomeIslandPersistence.load(ownerKey: ownerKey)
                    )
                    if let room = privateIslandService.islands.first(where: { $0.code == code }) {
                        return room
                    }
                    return try await privateIslandService.joinIsland(code: code)
                },
                onJoin: { code in
                    try await privateIslandService.joinIsland(code: code)
                },
                onVisit: { room in
                    selectPrivateIsland(room)
                },
                onLeave: { room in
                    Task {
                        do {
                            try await privateIslandService.leaveIsland(room.code)
                            Haptics.tap(.light)
                        } catch {
                            privateIslandError = error.localizedDescription
                            Haptics.error()
                        }
                    }
                },
                onCloseOwned: { room in
                    privateIslandPendingClose = room
                }
            )
            .padding(.horizontal, showsOceanBackground ? -LFMetrics.cardPadding : -16)
            .padding(.top, 6)
        }
    }

    private var publicSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Public")
                .font(LFFont.label(13))
                .tracking(1)
                .foregroundStyle(publicListInk.opacity(0.58))
                .padding(.top, horizontalSizeClass == .regular ? 36 : 18)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(PublicHarbor.all) { harbor in
                    if harbor.slug != PublicHarbor.all.first?.slug {
                        Rectangle()
                            .fill(publicListInk.opacity(0.10))
                            .frame(height: 1)
                    }
                    publicRow(harbor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                showsOceanBackground
                    ? timeOfDay.palette.glassColor.opacity(0.42)
                    : Color.white.opacity(0.74)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: - パブリックの港ひとつぶん

    private var publicJournalDoor: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LFColor.deepRust)
                Image(systemName: "book.pages")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color(hex: 0xFCFAF5))
            }
            .frame(width: 54, height: 54)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("PUBLIC LOGBOOK")
                        .font(LFFont.label(10))
                        .tracking(1.4)
                        .foregroundStyle(LFColor.deepRust)
                    Rectangle()
                        .fill(LFColor.inkFixed.opacity(0.12))
                        .frame(height: 1)
                }
                Text("Today's page")
                    .font(LFFont.copy(19))
                    .foregroundStyle(LFColor.inkFixed)
                Text("One photo a day, paired with a few words.")
                    .font(LFFont.label(12))
                    .foregroundStyle(LFColor.inkFixed.opacity(0.68))
                    .lineLimit(2)
            }

            Spacer(minLength: 2)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(LFColor.inkFixed.opacity(0.58))
        }
        .padding(18)
        .background(Color(hex: 0xFCFAF5))
        .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous)
                .stroke(LFColor.returnOrange.opacity(0.8), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens public pages and today's editor"))
    }

    @ViewBuilder
    private func publicRow(_ harbor: PublicHarbor) -> some View {
        HStack(spacing: 4) {
            if let onPublicHarborSelected {
                Button {
                    onPublicHarborSelected(harbor)
                } label: {
                    publicRowLabel(harbor)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: harbor) {
                    publicRowLabel(harbor)
                }
                .buttonStyle(.plain)
            }

            if publicService.joined.contains(harbor.slug) {
                Button {
                    guard publicHarborLeavingSlug == nil else { return }
                    publicHarborPendingLeave = harbor
                } label: {
                    if publicHarborLeavingSlug == harbor.slug {
                        ProgressView()
                            .controlSize(.small)
                            .tint(publicListInk.opacity(0.46))
                    } else {
                        Text("Leave")
                            .font(LFFont.label(10))
                            .foregroundStyle(publicListInk.opacity(0.46))
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .disabled(publicHarborLeavingSlug != nil)
                .accessibilityLabel(Text("Leave this harbor"))
            }
        }
    }

    private func publicRowLabel(_ harbor: PublicHarbor) -> some View {
            HStack(spacing: showsOceanBackground ? 14 : 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: showsOceanBackground ? 14 : 12, style: .continuous)
                        .fill(harbor.style.background)
                    TileSymbolView(symbol: harbor.symbol, fg: harbor.style.foreground, bg: harbor.style.background)
                        .frame(
                            width: showsOceanBackground ? 29 : 25,
                            height: showsOceanBackground ? 29 : 25
                        )
                }
                .frame(
                    width: showsOceanBackground ? 48 : 42,
                    height: showsOceanBackground ? 48 : 42
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(harbor.title)
                            .font(LFFont.copy(showsOceanBackground ? 17 : 16))
                            .foregroundStyle(publicListInk)
                            .lineLimit(1)
                        if publicService.joined.contains(harbor.slug) {
                            Text("In harbor")
                                .font(LFFont.label(12))
                                .foregroundStyle(publicListInk)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(LFColor.seaGreen.opacity(0.3))
                                .clipShape(Capsule())
                                .fixedSize()
                        }
                    }
                    Text(harbor.tagline)
                        .font(LFFont.label(showsOceanBackground ? 12 : 11))
                        .foregroundStyle(publicListInk.opacity(0.52))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(publicListInk.opacity(0.32))
            }
            .padding(.vertical, showsOceanBackground ? 12 : 7)
    }

    private var publicListInk: Color {
        showsOceanBackground ? timeOfDay.palette.inkColor : LFColor.harborTeal
    }

    private func leavePublicHarbor(_ harbor: PublicHarbor) {
        guard publicHarborLeavingSlug == nil else { return }
        publicHarborLeavingSlug = harbor.slug
        Task {
            defer { publicHarborLeavingSlug = nil }
            do {
                try await publicService.leave(harbor.slug)
                Haptics.tap(.light)
            } catch {
                publicHarborLeaveError = error.localizedDescription
                Haptics.error()
            }
        }
    }

}
