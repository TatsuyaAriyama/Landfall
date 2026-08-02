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
    @StateObject private var service = RoomService.shared
    @StateObject private var voyagePass = VoyagePassStore.shared
    @Environment(\.modelContext) private var modelContext

    @State private var creating = false
    @State private var joining = false
    @State private var showingVoyagePass = false
    @State private var editingProfile = false
    @State private var membersByRoom: [String: [HarborMember]] = [:]
    /// 初回ロードが済むまでは空状態CTAを出さない(在港者に「空です」を一瞬見せないため)。
    @State private var hasLoaded = false
    /// 退港の確認対象(タップ即実行しない)。
    @State private var leavingRoom: HarborRoom?
    /// 入港証を出す対象の港。
    @State private var invitingRoom: HarborRoom?
    /// 招待リンクから受け取ったコード(参加シートに引き渡す)。
    @StateObject private var router = DeepLinkRouter.shared
    @State private var incomingCode: String?
    /// パブリックの港(公式5港)。
    @StateObject private var publicService = PublicHarborService.shared
    @State private var navPath = NavigationPath()
    @State private var now = Date()

    private let minuteClock = Timer.publish(
        every: 60,
        tolerance: 2,
        on: .main,
        in: .common
    ).autoconnect()

    private var timeOfDay: AftideHomeTimeOfDay {
        AftideHomeTimeOfDay.current(at: now)
    }

    // 自分のプレイヤーカード(ローカル先行)。編集の保存で更新される。
    @AppStorage(PlayerProfile.nameKey) private var playerName = ""
    @AppStorage(PlayerProfile.styleKey) private var playerStyle = TileStyle.midnight.rawValue
    @AppStorage(PlayerProfile.symbolKey) private var playerSymbol = TileSymbol.phoenix.rawValue
    @AppStorage(PlayerProfile.resolveKey) private var playerResolve = ""

    var body: some View {
        NavigationStack(path: $navPath) {
            ZStack {
                HarborOceanBackground(timeOfDay: timeOfDay)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                    CardKicker(text: "Harbor", color: LFColor.ink.opacity(0.55))
                        .padding(.top, 8)

                    // 自分のプレイヤーカード。サインイン不要(ローカル先行)。タップで編集。
                    Button {
                        editingProfile = true
                    } label: {
                        ownPlayerCard
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 20)

                    // ---- パブリック(公式の5港。個人は並ばず、潮だけが見える) ----
                    Text("Public")
                        .font(LFFont.label(13))
                        .tracking(1)
                        .foregroundStyle(LFColor.ink.opacity(0.5))
                        .padding(.top, 32)

                        VStack(spacing: 0) {
                            ForEach(PublicHarbor.all) { harbor in
                                if harbor.slug != PublicHarbor.all.first?.slug {
                                    Rectangle()
                                        .fill(LFColor.ink.opacity(0.08))
                                        .frame(height: 1)
                                }
                                publicRow(harbor)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(timeOfDay.palette.glassColor.opacity(0.42))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.top, 6)

                    // ---- プライベート(招待コードの小さな港・最大4人) ----
                    Text("Private")
                        .font(LFFont.label(13))
                        .tracking(1)
                        .foregroundStyle(LFColor.ink.opacity(0.5))
                        .padding(.top, 36)

                    if !auth.isSignedIn {
                        Text("Sign in to enter a harbor.")
                            .font(LFFont.copy(16))
                            .foregroundStyle(LFColor.ink.opacity(0.5))
                            .padding(.top, 28)
                    } else if !hasLoaded {
                        ProgressView()
                            .tint(LFColor.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if service.rooms.isEmpty {
                        emptyState
                    } else {
                        ForEach(service.rooms) { room in
                            roomSection(room)
                                .padding(.top, 28)
                        }
                        actionRow
                            .padding(.top, 36)
                    }
                    }
                    .padding(LFMetrics.cardPadding)
                }
                .background(Color.clear)
            }
            .navigationDestination(for: MemberTraceKey.self) { key in
                MemberTraceView(roomId: key.roomId, member: key.member)
            }
            .navigationDestination(for: PublicHarbor.self) { harbor in
                PublicHarborView(harbor: harbor)
            }
            .navigationDestination(for: PublicMemberKey.self) { key in
                PublicMemberProfileView(slug: key.slug, initialMember: key.member)
            }
            .navigationDestination(for: HarborRoom.self) { room in
                HarborChatView(room: room)
            }
        }
        .tint(timeOfDay.palette.inkColor)
        .preferredColorScheme(
            timeOfDay == .evening || timeOfDay == .night ? .dark : .light
        )
        .task { await reload() }
        .refreshable { await reload() }
        .onReceive(minuteClock) { now = $0 }
        .sheet(isPresented: $creating) {
            RoomCreateSheet { await reload() }
        }
        .sheet(isPresented: $joining) {
            RoomJoinSheet(prefilledCode: incomingCode) { await reload() }
        }
        .sheet(isPresented: $showingVoyagePass) {
            VoyagePassView()
        }
        .sheet(item: $invitingRoom) { room in
            InvitePassSheet(roomName: room.name, code: room.id)
        }
        // 入港証のリンクから開かれたら、コードを入れた状態で参加シートを出す。
        .onChange(of: router.pendingJoinCode) { _, code in
            guard let code else { return }
            incomingCode = code
            router.pendingJoinCode = nil
            joining = true
        }
        .onAppear {
            if let code = router.pendingJoinCode {
                incomingCode = code
                router.pendingJoinCode = nil
                joining = true
            }
        }
        .sheet(isPresented: $editingProfile) {
            ProfileEditorSheet { Task { await reload() } }
        }
        .confirmationDialog(
            "Leave this harbor?",
            isPresented: Binding(get: { leavingRoom != nil }, set: { if !$0 { leavingRoom = nil } }),
            titleVisibility: .visible,
            presenting: leavingRoom
        ) { room in
            Button("Leave this harbor", role: .destructive) {
                Task {
                    await service.leaveRoom(room.id)
                    Haptics.tap()
                    await reload()
                }
            }
            Button("Cancel", role: .cancel) { leavingRoom = nil }
        } message: { _ in
            Text("You'll stop sharing here and won't see this harbor's members. You can rejoin with the code.")
        }
    }

    private func reload() async {
        await service.refreshRooms()
        // Webで参加してiOSを初めて開いた場合も対象港を取りこぼさないよう、
        // 参加状態をサーバーから確定してから当月を公開する。
        await publicService.refresh()
        // Web版と同じ規則でサービス開始日を確定し、既存のカードにも補完する。
        PlayerProfile.rememberVoyageStart(
            context: modelContext,
            accountCreatedAt: auth.user?.metadata.creationDate
        )
        service.pushProfileToAllRooms()
        await publicService.syncProfile()
        for room in service.rooms {
            membersByRoom[room.id] = await service.members(of: room.id)
        }
        // 港に入っている間は、開くたびに自分の当月を公開し直す(取りこぼし防止)。
        service.publishCurrentMonth(context: modelContext)
        hasLoaded = true
    }

    // MARK: - パブリックの港ひとつぶん

    private var ownPlayerCard: some View {
        let style = TileStyle.from(playerStyle)
        let name = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(spacing: 16) {
            PlayerAvatarArt(styleToken: playerStyle, symbolToken: playerSymbol)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: name.isEmpty ? LF.text("Sailor") : name)
                    .font(LFFont.copy(20))
                    .foregroundStyle(style.foreground)
                    .lineLimit(1)
                if !playerResolve.isEmpty {
                    Text(verbatim: playerResolve)
                        .font(LFFont.copy(14))
                        .foregroundStyle(style.foreground.opacity(0.8))
                        .lineLimit(2)
                }
                if let start = PlayerProfile.sinceDayFormatter.date(from: PlayerProfile.sinceDay) {
                    Text("Sailing since \(LF.fullDate(start))")
                        .font(LFFont.label(12))
                        .foregroundStyle(style.foreground.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text("Edit")
                .font(LFFont.label(13))
                .foregroundStyle(style.foreground.opacity(0.6))
        }
        .padding(20)
        .background(style.background)
        .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
    }

    private func publicRow(_ harbor: PublicHarbor) -> some View {
        NavigationLink(value: harbor) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(harbor.style.background)
                    TileSymbolView(symbol: harbor.symbol, fg: harbor.style.foreground, bg: harbor.style.background)
                        .frame(width: 29, height: 29)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(harbor.title)
                            .font(LFFont.copy(17))
                            .foregroundStyle(LFColor.ink)
                            .lineLimit(1)
                        if publicService.joined.contains(harbor.slug) {
                            Text("In harbor")
                                .font(LFFont.label(12))
                                .foregroundStyle(LFColor.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(LFColor.seaGreen.opacity(0.3))
                                .clipShape(Capsule())
                                .fixedSize()
                        }
                    }
                    Text(harbor.tagline)
                        .font(LFFont.label(12))
                        .foregroundStyle(LFColor.ink.opacity(0.45))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(LFColor.ink.opacity(0.25))
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 空の状態

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Share your study records with friends and see theirs.")
                .font(LFFont.copy(16))
                .foregroundStyle(LFColor.ink.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            actionRow
        }
        .padding(.top, 28)
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    if voyagePass.isActive {
                        creating = true
                    } else {
                        showingVoyagePass = true
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text("Open a harbor")
                        if !voyagePass.isActive {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .font(LFFont.copy(15))
                    .foregroundStyle(LFColor.paper)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(LFColor.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    // 手で開くときは、以前リンクから受け取ったコードを持ち越さない。
                    incomingCode = nil
                    joining = true
                } label: {
                    Text("Enter with a code")
                        .font(LFFont.copy(15))
                        .foregroundStyle(LFColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(LFColor.ink, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }

            if !voyagePass.isActive {
                Text("A Voyage Pass opens a private harbor. Anyone can join free with its code.")
                    .font(LFFont.label(11))
                    .foregroundStyle(LFColor.ink.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 港ひとつぶん

    private func roomSection(_ room: HarborRoom) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                Text(verbatim: room.name)
                    .font(LFFont.copy(22))
                    .foregroundStyle(LFColor.ink)
                Spacer()
                if isOwner(room) {
                    if voyagePass.isActive {
                        // 招待コードは「港を開いた航海証所持者」にだけ見せる。
                        Button {
                            Haptics.tap()
                            invitingRoom = room
                        } label: {
                            HStack(spacing: 6) {
                                Text(verbatim: room.id)
                                    .font(LFFont.label(15))
                                    .tracking(2)
                                    .monospacedDigit()
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(LFColor.returnOrange)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Invite code \(room.id)"))
                        .accessibilityHint(Text("Share"))
                    } else {
                        Button {
                            showingVoyagePass = true
                        } label: {
                            Label("Renew to invite", systemImage: "lock.fill")
                                .font(LFFont.label(12))
                                .foregroundStyle(LFColor.returnOrange)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // 最大4人の並走ルームへ直接入る。歩ける港はiOSでは使わない。
            NavigationLink(value: room) {
                HStack(spacing: 10) {
                    Image(systemName: "sailboat")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(LFColor.ink.opacity(0.6))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sail together")
                            .font(LFFont.copy(16))
                            .foregroundStyle(LFColor.ink)
                        Text(
                            verbatim: "\(room.memberIds.count)/\(HarborRoom.maxMembers) "
                                + LF.text("sailors · shared timer and chat")
                        )
                            .font(LFFont.label(11))
                            .foregroundStyle(LFColor.ink.opacity(0.46))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(LFColor.ink.opacity(0.25))
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(spacing: 0) {
                let members = membersByRoom[room.id] ?? []
                ForEach(members) { member in
                    if member.id != members.first?.id {
                        Rectangle()
                            .fill(LFColor.ink.opacity(0.08))
                            .frame(height: 1)
                    }
                    memberRow(roomId: room.id, member: member)
                }
            }

            Button {
                leavingRoom = room
            } label: {
                Text("Leave this harbor")
                    .font(LFFont.label(14))
                    .foregroundStyle(LFColor.ink.opacity(0.45))
            }
            .buttonStyle(.plain)
        }
    }

    private func isOwner(_ room: HarborRoom) -> Bool {
        guard let uid = auth.user?.uid else { return false }
        if let ownerUid = room.ownerUid, room.memberIds.contains(ownerUid) {
            return ownerUid == uid
        }
        return room.memberIds.first == uid
    }

    private func memberRow(roomId: String, member: HarborMember) -> some View {
        NavigationLink(value: MemberTraceKey(roomId: roomId, member: member)) {
            HStack(spacing: 14) {
                // プレイヤーアイコン: 全員同じ大きさ。序列を作らない。
                PlayerAvatarArt(styleToken: member.styleToken, symbolToken: member.symbolToken)
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(verbatim: member.displayName)
                            .font(LFFont.copy(17))
                            .foregroundStyle(LFColor.ink)
                            .lineLimit(1)
                        if member.id == auth.user?.uid {
                            Text("You")
                                .font(LFFont.label(12))
                                .foregroundStyle(LFColor.ink.opacity(0.4))
                        }
                    }
                    if !member.resolve.isEmpty {
                        Text(verbatim: member.resolve)
                            .font(LFFont.label(12))
                            .foregroundStyle(LFColor.ink.opacity(0.45))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(LFColor.ink.opacity(0.25))
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

/// ナビゲーション用キー。
struct MemberTraceKey: Hashable {
    let roomId: String
    let member: HarborMember
}

// MARK: - メンバーの軌跡

/// 港のメンバーの当月の記録。自分の「軌跡」画面と同じ文法で、波形・統計・記録した日を見せる。
/// 共有されるので、項目・ひとこと・時間まで読める(読み取り専用)。
struct MemberTraceView: View {
    let roomId: String
    let member: HarborMember
    /// "rooms"(プライベート) / "publicHarbors"(パブリック)。読む場所だけが違う。
    var root: String = "rooms"

    @Environment(\.dismiss) private var dismiss
    @State private var days: Set<Int>?
    @State private var sessions: [SharedSession] = []

    private var yearMonth: (year: Int, month: Int) {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        return (comps.year ?? 2026, comps.month ?? 1)
    }

    var body: some View {
        ZStack {
            HarborOceanBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 相手のプレイヤーカード(名前・アイコン・決意)。
                    PlayerCardView(
                        name: member.displayName,
                        styleToken: member.styleToken,
                        symbolToken: member.symbolToken,
                        resolve: member.resolve,
                        sinceDay: member.sinceDay
                    )

                    CardKicker(
                        text: "Trace of \(LF.monthName(year: yearMonth.year, month: yearMonth.month))",
                        color: LFColor.ink.opacity(0.55)
                    )
                    .padding(.top, 24)

                    if let month = wrappedMonth {
                        ZStack {
                            MonthWaveform(
                                month: month,
                                lineColor: LFColor.ink,
                                gapBarColor: LFColor.coral,
                                resumeMarkerColor: LFColor.returnOrange,
                                gapLabelColor: LFColor.deepRust.opacity(0.85),
                                showDateAxis: true
                            )
                            .frame(height: 240)

                            if month.studiedCount == 0 {
                                Text("Waiting for this month's first mark.")
                                    .font(LFFont.copy(16))
                                    .foregroundStyle(LFColor.ink.opacity(0.6))
                            }
                        }
                        .padding(.top, 24)

                        statsRow(for: month)
                            .padding(.top, 28)

                        recordedDaysSection
                            .padding(.top, 40)
                    } else {
                        ProgressView()
                            .padding(.top, 60)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(LFMetrics.cardPadding)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                        Text("Harbor")
                    }
                    .font(LFFont.label(16))
                    .foregroundStyle(LFColor.ink)
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            let detail = await RoomService.shared.monthDetail(
                roomId: roomId, memberId: member.id,
                year: yearMonth.year, month: yearMonth.month, root: root
            )
            days = detail.days
            sessions = detail.sessions
        }
    }

    // MARK: - 記録した日(共有されたセッション)

    @ViewBuilder
    private var recordedDaysSection: some View {
        // 日ごとにまとめ、新しい日から並べる。
        let grouped = Dictionary(grouping: sessions, by: \.day)
        let sortedDays = grouped.keys.sorted(by: >)
        if !sortedDays.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Days logged")
                    .font(LFFont.label(13))
                    .tracking(1)
                    .foregroundStyle(LFColor.ink.opacity(0.5))

                VStack(spacing: 0) {
                    ForEach(sortedDays, id: \.self) { day in
                        if day != sortedDays.first {
                            Rectangle().fill(LFColor.ink.opacity(0.08)).frame(height: 1)
                        }
                        dayBlock(day: day, sessions: grouped[day] ?? [])
                    }
                }
            }
        }
    }

    private func dayBlock(day: Int, sessions: [SharedSession]) -> some View {
        let total = sessions.reduce(0) { $0 + $1.minutes }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(LF.dayWithWeekday(dateFor(day: day)))
                    .font(LFFont.copy(16))
                    .foregroundStyle(LFColor.ink)
                Text(LF.duration(minutes: total))
                    .font(LFFont.label(13))
                    .monospacedDigit()
                    .foregroundStyle(LFColor.ink.opacity(0.5))
            }
            ForEach(sessions) { session in
                sessionRow(session)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
    }

    private func sessionRow(_ session: SharedSession) -> some View {
        let style = TileStyle.from(session.styleToken)
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(style.background)
                TileSymbolView(symbol: TileSymbol.from(session.symbolToken), fg: style.foreground, bg: style.background)
                    .frame(width: 22, height: 22)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(verbatim: session.itemName ?? LF.text("No item"))
                        .font(LFFont.copy(15))
                        .foregroundStyle(LFColor.ink)
                        .lineLimit(1)
                    Text(LF.duration(minutes: session.minutes))
                        .font(LFFont.label(13))
                        .monospacedDigit()
                        .foregroundStyle(LFColor.ink.opacity(0.55))
                }
                if let note = session.note {
                    Text(verbatim: note)
                        .font(LFFont.label(14))
                        .foregroundStyle(LFColor.ink.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// その月の日番号から日付を作る(表示用)。
    private func dateFor(day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: yearMonth.year, month: yearMonth.month, day: day)) ?? Date()
    }

    private var wrappedMonth: WrappedMonth? {
        guard let days else { return nil }
        let (year, month) = yearMonth
        let calendar = Calendar.current
        let daysInMonth: Int = {
            guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let range = calendar.range(of: .day, in: .month, for: start) else { return 30 }
            return range.count
        }()
        return WrappedMonth(
            year: year, month: month, daysInMonth: daysInMonth,
            studiedDays: days,
            archetype: MonthStats.diagnose(year: year, month: month, studiedDays: days, calendar: calendar)
        )
    }

    private func statsRow(for month: WrappedMonth) -> some View {
        HStack(alignment: .top, spacing: 0) {
            statBlock(label: "Total", value: month.studiedCount, unit: "days", alignment: .leading)
            statBlock(label: "Returns", value: month.resumeCount, unit: "times", alignment: .center)
            statBlock(label: "Times quit", value: month.quitCount, unit: "times", alignment: .trailing)
        }
    }

    private func statBlock(label: LocalizedStringKey, value: Int, unit: LocalizedStringKey, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(label)
                .font(LFFont.label(13))
                .foregroundStyle(LFColor.ink.opacity(0.5))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(verbatim: "\(value)")
                    .font(LFFont.number(30))
                    .foregroundStyle(LFColor.ink)
                Text(unit)
                    .font(LFFont.copy(14))
                    .foregroundStyle(LFColor.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : (alignment == .trailing ? .trailing : .leading))
    }
}

// MARK: - 作成・参加シート

struct RoomCreateSheet: View {
    var onDone: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var code: String?
    @State private var working = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Open a harbor")
                .font(LFFont.copy(20))
                .foregroundStyle(LFColor.ink)

            if let code {
                // 作成完了: コードを見せる。
                VStack(alignment: .leading, spacing: 10) {
                    Text("Share this code to invite others.")
                        .font(LFFont.label(14))
                        .foregroundStyle(LFColor.ink.opacity(0.5))
                    HStack {
                        Text(verbatim: code)
                            .font(LFFont.number(34))
                            .tracking(6)
                            .foregroundStyle(LFColor.ink)
                        Spacer()
                        ShareLink(item: code) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(LFColor.returnOrange)
                        }
                    }
                }
                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .font(LFFont.copy(17))
                        .foregroundStyle(LFColor.paper)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(LFColor.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                TextField("Harbor name", text: $name)
                    .font(LFFont.label(16))
                    .foregroundStyle(LFColor.ink)
                    .tint(LFColor.ink)
                    .padding(.horizontal, 18)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(LFColor.ink.opacity(0.2), lineWidth: 1)
                    )

                if let errorText {
                    Text(verbatim: errorText)
                        .font(LFFont.label(13))
                        .foregroundStyle(LFColor.deepRust)
                }

                Button {
                    Task {
                        working = true
                        defer { working = false }
                        do {
                            code = try await RoomService.shared.createRoom(
                                named: name.trimmingCharacters(in: .whitespaces),
                                context: modelContext
                            )
                            Haptics.success()
                            await onDone()
                        } catch {
                            errorText = error.localizedDescription
                        }
                    }
                } label: {
                    Text("Open")
                        .font(LFFont.copy(17))
                        .foregroundStyle(LFColor.paper)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? LFColor.ink.opacity(0.3) : LFColor.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || working)
            }
            Spacer()
        }
        .padding(LFMetrics.cardPadding)
        .background(LFColor.paper)
        .presentationDetents([.medium])
    }
}

struct RoomJoinSheet: View {
    /// 入港証のリンクから来たときに入れておくコード。手入力の手間を省く。
    var prefilledCode: String? = nil
    var onDone: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var code = ""
    @State private var working = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Enter with a code")
                .font(LFFont.copy(20))
                .foregroundStyle(LFColor.ink)

            TextField("Code (6 letters)", text: $code)
                .font(LFFont.number(22))
                .tracking(4)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .foregroundStyle(LFColor.ink)
                .tint(LFColor.ink)
                .padding(.horizontal, 18)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(LFColor.ink.opacity(0.2), lineWidth: 1)
                )

            if let errorText {
                Text(verbatim: errorText)
                    .font(LFFont.label(13))
                    .foregroundStyle(LFColor.deepRust)
            }

            Button {
                Task {
                    working = true
                    defer { working = false }
                    do {
                        try await RoomService.shared.joinRoom(code: code, context: modelContext)
                        Haptics.success()
                        await onDone()
                        dismiss()
                    } catch {
                        errorText = error.localizedDescription
                    }
                }
            } label: {
                Text("Enter")
                    .font(LFFont.copy(17))
                    .foregroundStyle(LFColor.paper)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(code.trimmingCharacters(in: .whitespaces).isEmpty ? LFColor.ink.opacity(0.3) : LFColor.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || working)

            Spacer()
        }
        .padding(LFMetrics.cardPadding)
        .background(LFColor.paper)
        .presentationDetents([.medium])
        .onAppear {
            if let prefilledCode, code.isEmpty { code = prefilledCode }
        }
    }
}
