import SwiftUI
import SwiftData

/// 「港」画面。同じ港のメンバーの軌跡(日ベースのみ)を互いに見られる。
/// 順位・ランキング・ストリークは作らない。休んだ日も学んだ日と同格に見える。
struct HarborView: View {
    @EnvironmentObject private var auth: AuthService
    @StateObject private var service = RoomService.shared
    @Environment(\.modelContext) private var modelContext

    @State private var creating = false
    @State private var joining = false
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

    // 自分のプレイヤーカード(ローカル先行)。編集の保存で更新される。
    @AppStorage(PlayerProfile.nameKey) private var playerName = ""
    @AppStorage(PlayerProfile.styleKey) private var playerStyle = TileStyle.midnight.rawValue
    @AppStorage(PlayerProfile.symbolKey) private var playerSymbol = TileSymbol.phoenix.rawValue
    @AppStorage(PlayerProfile.resolveKey) private var playerResolve = ""

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CardKicker(text: "Harbor", color: LFColor.ink.opacity(0.55))
                        .padding(.top, 8)

                    // 自分のプレイヤーカード。サインイン不要(ローカル先行)。タップで編集。
                    Button {
                        editingProfile = true
                    } label: {
                        PlayerCardView(
                            name: playerName.trimmingCharacters(in: .whitespaces).isEmpty
                                ? String(localized: "Sailor") : playerName,
                            styleToken: playerStyle,
                            symbolToken: playerSymbol,
                            resolve: playerResolve
                        )
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(TileStyle.from(playerStyle).foreground.opacity(0.6))
                                .padding(12)
                        }
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
            .background(LFColor.paper)
            .navigationDestination(for: MemberTraceKey.self) { key in
                MemberTraceView(roomId: key.roomId, member: key.member)
            }
            .navigationDestination(for: PublicHarbor.self) { harbor in
                PublicHarborView(harbor: harbor)
            }
            .navigationDestination(for: HarborRoom.self) { room in
                HarborChatView(room: room)
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $creating) {
            RoomCreateSheet { await reload() }
        }
        .sheet(isPresented: $joining) {
            RoomJoinSheet(prefilledCode: incomingCode) { await reload() }
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
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["LANDFALL_PROFILE"] == "1" {
                editingProfile = true
            }
            // 動作確認用: LANDFALL_PUBLIC=<slug> でパブリックの港の中を直接開く。
            if let slug = ProcessInfo.processInfo.environment["LANDFALL_PUBLIC"],
               let harbor = PublicHarbor.by(slug: slug) {
                navPath.append(harbor)
            }
            #endif
        }
    }

    private func reload() async {
        await service.refreshRooms()
        for room in service.rooms {
            membersByRoom[room.id] = await service.members(of: room.id)
        }
        // 港に入っている間は、開くたびに自分の当月を公開し直す(取りこぼし防止)。
        service.publishCurrentMonth(context: modelContext)
        await publicService.refresh()
        hasLoaded = true
    }

    // MARK: - パブリックの港ひとつぶん

    private func publicRow(_ harbor: PublicHarbor) -> some View {
        NavigationLink(value: harbor) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(harbor.style.background)
                    TileSymbolView(symbol: harbor.symbol, fg: harbor.style.foreground, bg: harbor.style.background)
                        .frame(width: 22, height: 22)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(harbor.title)
                            .font(LFFont.copy(17))
                            .foregroundStyle(LFColor.ink)
                        if publicService.joined.contains(harbor.slug) {
                            Text("In harbor")
                                .font(LFFont.label(11))
                                .foregroundStyle(LFColor.returnOrange)
                        }
                    }
                    Text(harbor.tagline)
                        .font(LFFont.label(12))
                        .foregroundStyle(LFColor.ink.opacity(0.45))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let n = publicService.todaySail[harbor.slug], n > 0 {
                    Text("\(n)")
                        .font(LFFont.number(15))
                        .foregroundStyle(LFColor.ink.opacity(0.5))
                }
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
        HStack(spacing: 12) {
            Button {
                creating = true
            } label: {
                Text("Open a harbor")
                    .font(LFFont.copy(16))
                    .foregroundStyle(LFColor.paper)
                    .padding(.horizontal, 20)
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
                    .font(LFFont.copy(16))
                    .foregroundStyle(LFColor.ink)
                    .padding(.horizontal, 20)
                    .frame(height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(LFColor.ink, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
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
                // 招待コード。タップで入港証(コード+QRの一枚)を開いて渡せる。
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
            }

            // みんなの航海(チャット)。言葉と、着岸/帰還の自動の行がひとつの流れになる。
            NavigationLink(value: room) {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(LFColor.ink.opacity(0.6))
                    Text("The voyage together")
                        .font(LFFont.copy(16))
                        .foregroundStyle(LFColor.ink)
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

    @Environment(\.dismiss) private var dismiss
    @State private var days: Set<Int>?
    @State private var sessions: [SharedSession] = []

    private var yearMonth: (year: Int, month: Int) {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        return (comps.year ?? 2026, comps.month ?? 1)
    }

    var body: some View {
        ZStack {
            LFColor.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 相手のプレイヤーカード(名前・アイコン・決意)。
                    PlayerCardView(
                        name: member.displayName,
                        styleToken: member.styleToken,
                        symbolToken: member.symbolToken,
                        resolve: member.resolve
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
        .toolbarBackground(LFColor.paper, for: .navigationBar)
        .task {
            let detail = await RoomService.shared.monthDetail(
                roomId: roomId, memberId: member.id,
                year: yearMonth.year, month: yearMonth.month
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
                    Text(verbatim: session.itemName ?? String(localized: "No item"))
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
