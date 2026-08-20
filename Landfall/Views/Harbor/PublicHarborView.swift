import SwiftUI
import SwiftData

/// パブリックの港の中。参加している船乗りの名前・アイコン・作業記録が見える。
/// 記録は月ごとに残り続け、消せるのは書いた本人だけ(退港=自分の共有分の削除)。
struct PublicHarborView: View {
    let harbor: PublicHarbor
    private let showsOceanBackground: Bool
    private let onEmbeddedBack: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthService
    @StateObject private var service = PublicHarborService.shared
    @StateObject private var blockList = BlockedSailors.shared
    @State private var members: [HarborMember] = []
    @State private var loaded = false
    @State private var working = false
    @State private var leaving = false
    @State private var editingProfile = false
    @State private var needsProfile = false
    @State private var joinError: String?
    @State private var leaveError: String?
    @State private var loadError: String?
    /// 通報の確認対象(メンバー)。
    @State private var reporting: HarborMember?
    /// ブロックの確認対象(メンバー)。
    @State private var blocking: HarborMember?
    /// Firestoreへの保存が完了したブロックだけをUndo対象として提示する。
    @State private var recentlyBlocked: HarborMember?
    @State private var blockError: String?
    @State private var blockingMemberID: String?
    /// 公開コンテンツ通報はCallableの完了後だけ結果を知らせる。
    @State private var reportResult: String?
    @State private var membersSubscription: PublicHarborMembersSubscription?

    private var isJoined: Bool { service.joined.contains(harbor.slug) }
    private var myUid: String? { auth.user?.uid }
    private var hasJoinError: Binding<Bool> { optionalPresentation($joinError) }
    private var hasLeaveError: Binding<Bool> { optionalPresentation($leaveError) }
    private var hasBlockError: Binding<Bool> { optionalPresentation($blockError) }
    private var hasRecentlyBlockedMember: Binding<Bool> { optionalPresentation($recentlyBlocked) }
    private var hasReportResult: Binding<Bool> { optionalPresentation($reportResult) }
    private var isReportingDialogPresented: Binding<Bool> { optionalPresentation($reporting) }
    private var isBlockingDialogPresented: Binding<Bool> {
        optionalPresentation($blocking)
    }

    init(
        harbor: PublicHarbor,
        showsOceanBackground: Bool = true,
        onEmbeddedBack: (() -> Void)? = nil
    ) {
        self.harbor = harbor
        self.showsOceanBackground = showsOceanBackground
        self.onEmbeddedBack = onEmbeddedBack
    }

    private func optionalPresentation<Value>(_ value: Binding<Value?>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue != nil },
            set: { isPresented in
                if !isPresented { value.wrappedValue = nil }
            }
        )
    }

    /// ブロックした相手は一覧から外す。
    private var visibleMembers: [HarborMember] {
        members.filter { !blockList.blocked.contains($0.id) }
    }

    var body: some View {
        confirmationDialogs
    }

    private var baseContent: some View {
        ZStack {
            if showsOceanBackground {
                HarborOceanBackground()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    joinButton
                        .padding(.top, showsOceanBackground ? 28 : 10)
                    if auth.isSignedIn {
                        membersSection
                            .padding(.top, showsOceanBackground ? 32 : 14)
                    }
                }
                .padding(showsOceanBackground ? LFMetrics.cardPadding : 14)
                .background(
                    Color.white.opacity(showsOceanBackground ? 0 : 0.78),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
                .padding(.horizontal, showsOceanBackground ? 0 : 12)
                .padding(.top, showsOceanBackground ? 0 : 10)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if let onEmbeddedBack {
                        onEmbeddedBack()
                    } else {
                        dismiss()
                    }
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
        .task { await reload() }
        .refreshable { await reload() }
        .onDisappear {
            membersSubscription?.cancel()
            membersSubscription = nil
        }
        .sheet(isPresented: $editingProfile) {
            ProfileEditorSheet {
                needsProfile = false
                Task { await reload() }
            }
        }
    }

    private var alertsContent: some View {
        baseContent
        .alert(
            "Couldn't join this harbor.",
            isPresented: hasJoinError
        ) {
            Button("OK", role: .cancel) { joinError = nil }
        } message: {
            Text(verbatim: joinError ?? "")
        }
        .alert(
            "Couldn't leave this harbor.",
            isPresented: hasLeaveError
        ) {
            Button("OK", role: .cancel) { leaveError = nil }
        } message: {
            Text(verbatim: leaveError ?? "")
        }
        .alert(
            "Couldn't update blocked sailors.",
            isPresented: hasBlockError
        ) {
            Button("OK", role: .cancel) { blockError = nil }
        } message: {
            Text(verbatim: blockError ?? "")
        }
        .alert(
            "Sailor blocked",
            isPresented: hasRecentlyBlockedMember,
            presenting: recentlyBlocked
        ) { member in
            Button("Undo") {
                recentlyBlocked = nil
                undoBlock(member)
            }
            Button("OK", role: .cancel) { recentlyBlocked = nil }
        } message: { _ in
            Text("Their public logbook pages, harbor profile, and chat messages are now hidden.")
        }
        .alert(
            "Harbor report",
            isPresented: hasReportResult
        ) {
            Button("OK", role: .cancel) { reportResult = nil }
        } message: {
            Text(verbatim: reportResult ?? "")
        }
    }

    private var confirmationDialogs: some View {
        alertsContent
        .confirmationDialog(
            "Leave this harbor?",
            isPresented: $leaving,
            titleVisibility: .visible
        ) {
            Button("Leave this harbor", role: .destructive) {
                leaveHarbor()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your name and shared records will be removed from this harbor. You can rejoin anytime.")
        }
        .confirmationDialog(
            "Report this sailor?",
            isPresented: isReportingDialogPresented,
            titleVisibility: .visible,
            presenting: reporting
        ) { member in
            Button("Report", role: .destructive) {
                reporting = nil
                Task {
                    do {
                        try await PublicJournalService.shared.reportMember(
                            member.id,
                            harborSlug: harbor.slug
                        )
                        reportResult = LF.text("Report received. Thank you for helping keep the harbor safe.")
                        Haptics.success()
                    } catch {
                        reportResult = error.localizedDescription
                        Haptics.error()
                    }
                }
            }
            Button("Cancel", role: .cancel) { reporting = nil }
        } message: { _ in
            Text("This sends a report to the developer for review.")
        }
        .confirmationDialog(
            "Block this sailor?",
            isPresented: isBlockingDialogPresented,
            titleVisibility: .visible,
            presenting: blocking
        ) { member in
            Button("Block", role: .destructive) {
                blocking = nil
                block(member)
            }
            Button("Cancel", role: .cancel) { blocking = nil }
        } message: { _ in
            Text("Their public logbook pages, harbor profile, and chat messages will be hidden. They won't be told.")
        }
    }

    private func reload() async {
        membersSubscription?.cancel()
        membersSubscription = nil
        loaded = false
        guard auth.isSignedIn else {
            members = []
            loadError = nil
            loaded = true
            return
        }
        async let blockedLoad: Void = blockList.load()
        async let membershipRefresh: Void = service.refresh()
        do {
            members = try await service.members(of: harbor.slug) { partial in
                members = partial
                loadError = nil
                loaded = true
            }
            loadError = nil
        } catch {
            loadError = LF.text("Couldn't refresh this harbor.")
        }
        loaded = true
        _ = await (blockedLoad, membershipRefresh)
        startMembersObservation()
    }

    private func startMembersObservation() {
        membersSubscription?.cancel()
        membersSubscription = service.observeMembers(of: harbor.slug) { result in
            switch result {
            case .success(let latest):
                members = latest
                loadError = nil
                loaded = true
            case .failure:
                // Preserve the last complete list. Pull to refresh exposes an explicit retry.
                if members.isEmpty {
                    loadError = LF.text("Couldn't refresh this harbor.")
                    loaded = true
                }
            }
        }
    }

    // MARK: - 見出し

    private var header: some View {
        HStack(spacing: showsOceanBackground ? 16 : 10) {
            ZStack {
                RoundedRectangle(cornerRadius: showsOceanBackground ? 20 : 12, style: .continuous)
                    .fill(harbor.style.background)
                TileSymbolView(symbol: harbor.symbol, fg: harbor.style.foreground, bg: harbor.style.background)
                    .frame(
                        width: showsOceanBackground ? 38 : 24,
                        height: showsOceanBackground ? 38 : 24
                    )
            }
            .frame(
                width: showsOceanBackground ? 64 : 42,
                height: showsOceanBackground ? 64 : 42
            )
            VStack(alignment: .leading, spacing: showsOceanBackground ? 6 : 2) {
                Text(harbor.title)
                    .font(LFFont.copy(showsOceanBackground ? 24 : 17))
                    .foregroundStyle(LFColor.ink)
                Text(harbor.tagline)
                    .font(LFFont.label(showsOceanBackground ? 14 : 11))
                    .foregroundStyle(LFColor.ink.opacity(0.6))
                    .lineLimit(showsOceanBackground ? 3 : 1)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 参加

    @ViewBuilder
    private var joinButton: some View {
        if !auth.isSignedIn {
            Text("Sign in to enter a harbor.")
                .font(LFFont.copy(showsOceanBackground ? 15 : 12))
                .foregroundStyle(LFColor.ink.opacity(0.5))
        } else if isJoined {
            Button {
                guard !working else { return }
                leaving = true
            } label: {
                Text("Leave this harbor")
                    .font(LFFont.label(14))
                    .foregroundStyle(LFColor.ink.opacity(0.45))
            }
            .buttonStyle(.plain)
            .disabled(working)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    guard !working else { return }
                    guard !PlayerProfile.name.isEmpty else {
                        needsProfile = true
                        editingProfile = true
                        return
                    }
                    working = true
                    Task {
                        defer { working = false }
                        do {
                            try await service.join(harbor.slug, context: modelContext)
                            Haptics.success()
                            await reload()
                        } catch {
                            joinError = error.localizedDescription
                        }
                    }
                } label: {
                    Text("Join this harbor")
                        .font(LFFont.copy(17))
                        .foregroundStyle(LFColor.paper)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 56)
                        .background(LFColor.ink)
                        .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
                }
                .buttonStyle(.plain)
                Text("Joining shares your name, icon, and study records here.")
                    .font(LFFont.label(13))
                    .foregroundStyle(LFColor.ink.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                if needsProfile {
                    Text("Set up your player card first.")
                        .font(LFFont.label(13))
                        .foregroundStyle(LFColor.returnOrange)
                }
            }
        }
    }

    // MARK: - 在港の船乗り

    @ViewBuilder
    private var membersSection: some View {
        HStack(spacing: 8) {
            Text("Sailors in harbor")
                .tracking(1)
            if loaded, loadError == nil {
                Text(verbatim: "\(visibleMembers.count)")
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(LFColor.ink.opacity(0.07), in: Capsule())
            }
        }
        .font(LFFont.label(showsOceanBackground ? 13 : 11))
        .foregroundStyle(LFColor.ink.opacity(0.5))

        if !loaded {
            ProgressView()
                .tint(LFColor.ink)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else if let loadError, !members.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(verbatim: loadError)
                    .font(LFFont.copy(15))
                    .foregroundStyle(LFColor.ink.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") {
                    Task { await reload() }
                }
                .font(LFFont.label(14))
                .foregroundStyle(LFColor.ink)
                .buttonStyle(.plain)
            }
            .padding(.top, 16)

            memberRows
        } else if let loadError, members.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(verbatim: loadError)
                    .font(LFFont.copy(15))
                    .foregroundStyle(LFColor.ink.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") {
                    Task { await reload() }
                }
                .font(LFFont.label(14))
                .foregroundStyle(LFColor.ink)
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
        } else if visibleMembers.isEmpty, !members.isEmpty {
            Text("All sailors in this harbor are hidden by your block list.")
                .font(LFFont.copy(15))
                .foregroundStyle(LFColor.ink.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        } else if visibleMembers.isEmpty {
            Text("No one is in this harbor yet. Be the first to drop anchor.")
                .font(LFFont.copy(15))
                .foregroundStyle(LFColor.ink.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        } else {
            memberRows
        }
    }

    private var memberRows: some View {
        VStack(spacing: 0) {
            ForEach(visibleMembers) { member in
                if member.id != visibleMembers.first?.id {
                    Rectangle()
                        .fill(LFColor.ink.opacity(0.08))
                        .frame(height: 1)
                }
                memberRow(member)
            }
        }
        .padding(.top, 6)
    }

    private func memberRow(_ member: HarborMember) -> some View {
        HStack(spacing: 8) {
            NavigationLink(value: PublicMemberKey(slug: harbor.slug, member: member)) {
                HStack(spacing: 14) {
                // 全員同じ大きさ。序列を作らない。
                    PlayerAvatarArt(styleToken: member.styleToken, symbolToken: member.symbolToken)
                        .frame(
                            width: showsOceanBackground ? 38 : 30,
                            height: showsOceanBackground ? 38 : 30
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(verbatim: member.displayName)
                                .font(LFFont.copy(showsOceanBackground ? 17 : 14))
                                .foregroundStyle(LFColor.ink)
                                .lineLimit(1)
                            if member.id == myUid {
                                Text("You")
                                    .font(LFFont.label(12))
                                    .foregroundStyle(LFColor.ink.opacity(0.4))
                            }
                        }
                        if !member.resolve.isEmpty {
                            Text(verbatim: member.resolve)
                                .font(LFFont.label(showsOceanBackground ? 12 : 10))
                                .foregroundStyle(LFColor.ink.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(LFColor.ink.opacity(0.25))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if member.id != myUid {
                Menu {
                    Button {
                        reporting = member
                    } label: {
                        Label("Report", systemImage: "flag")
                    }
                    Button(role: .destructive) {
                        blocking = member
                    } label: {
                        Label("Block this sailor", systemImage: "hand.raised")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(LFColor.ink.opacity(0.45))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(blockingMemberID != nil)
            }
        }
        .padding(.vertical, showsOceanBackground ? 9 : 4)
        .contextMenu {
            if member.id != myUid {
                Button {
                    reporting = member
                } label: {
                    Label("Report", systemImage: "flag")
                }
                Button(role: .destructive) {
                    blocking = member
                } label: {
                    Label("Block this sailor", systemImage: "hand.raised")
                }
                .disabled(blockingMemberID != nil)
            }
        }
    }

    private func leaveHarbor() {
        guard !working else { return }
        working = true
        Task {
            defer { working = false }
            do {
                try await service.leave(harbor.slug)
                Haptics.success()
                await reload()
            } catch {
                leaveError = error.localizedDescription
                Haptics.error()
            }
        }
    }

    private func block(_ member: HarborMember) {
        guard blockingMemberID == nil else { return }
        blockingMemberID = member.id
        Task {
            defer { blockingMemberID = nil }
            do {
                try await blockList.block(member.id)
                recentlyBlocked = member
                Haptics.success()
            } catch {
                blockError = error.localizedDescription
                Haptics.error()
            }
        }
    }

    private func undoBlock(_ member: HarborMember) {
        guard blockingMemberID == nil else { return }
        blockingMemberID = member.id
        Task {
            defer { blockingMemberID = nil }
            do {
                try await blockList.unblock(member.id)
                Haptics.tap(.light)
            } catch {
                blockError = error.localizedDescription
                Haptics.error()
            }
        }
    }
}

/// パブリックの港のメンバーページへの遷移キー。
struct PublicMemberKey: Hashable {
    let slug: String
    let member: HarborMember
}

// MARK: - パブリック港のプレイヤー詳細

/// Web版のメンバー詳細と同じ構成。
/// 一覧から渡されたカードは初期表示にだけ使い、画面を開いた時点でプロフィールと記録を取り直す。
/// プライベート港の既存の軌跡画面とは分離し、そちらの仕様には影響させない。
struct PublicMemberProfileView: View {
    let slug: String
    private let showsOceanBackground: Bool

    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = PublicHarborService.shared
    @State private var member: HarborMember
    @State private var year: Int
    @State private var month: Int
    @State private var days: Set<Int> = []
    @State private var sessions: [SharedSession] = []
    @State private var selectedDay: Int?
    @State private var loaded = false
    @State private var loadError: String?
    @State private var monthSubscription: PublicHarborMonthSubscription?

    init(
        slug: String,
        initialMember: HarborMember,
        showsOceanBackground: Bool = true
    ) {
        self.slug = slug
        self.showsOceanBackground = showsOceanBackground
        _member = State(initialValue: initialMember)
        let components = Calendar.current.dateComponents([.year, .month], from: Date())
        _year = State(initialValue: components.year ?? 2026)
        _month = State(initialValue: components.month ?? 1)
    }

    private var monthID: String {
        String(format: "%04d-%02d", year, month)
    }

    private var isCurrentMonth: Bool {
        let components = Calendar.current.dateComponents([.year, .month], from: Date())
        return year == components.year && month == components.month
    }

    private var selectedSessions: [SharedSession] {
        guard let selectedDay else { return [] }
        return sessions.filter { $0.day == selectedDay }
    }

    var body: some View {
        ZStack {
            if showsOceanBackground {
                HarborOceanBackground()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    memberHeader
                    monthNavigation
                        .padding(.top, 28)

                    if !loaded {
                        Text("Loading…")
                            .font(LFFont.copy(15))
                            .foregroundStyle(LFColor.ink.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if let loadError {
                        retryMessage(loadError)
                            .padding(.top, 20)
                    } else {
                        dayGrid
                            .padding(.top, 8)
                        dayDetail
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
                    .padding(.leading, 32)
                    .font(LFFont.label(16))
                    .foregroundStyle(LFColor.ink)
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: monthID) {
            await loadSelectedMonth()
        }
        .onDisappear {
            monthSubscription?.cancel()
            monthSubscription = nil
        }
        .refreshable {
            await loadSelectedMonth()
        }
    }

    private var memberHeader: some View {
        HStack(spacing: 16) {
            PlayerAvatarArt(styleToken: member.styleToken, symbolToken: member.symbolToken)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: member.displayName)
                    .font(LFFont.copy(16))
                    .foregroundStyle(LFColor.ink)
                    .lineLimit(1)
                if !member.resolve.isEmpty {
                    Text(verbatim: member.resolve)
                        .font(LFFont.label(13))
                        .foregroundStyle(LFColor.ink.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let start = PlayerProfile.sinceDayFormatter.date(from: member.sinceDay) {
                    Text("Sailing since \(LF.fullDate(start))")
                        .font(LFFont.label(12))
                        .foregroundStyle(LFColor.ink.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var monthNavigation: some View {
        HStack {
            monthArrow(systemName: "chevron.left", disabled: false) {
                shiftMonth(-1)
            }
            Spacer(minLength: 8)
            Text(verbatim: LF.monthYear(year: year, month: month))
                .font(LFFont.copy(20))
                .foregroundStyle(LFColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            monthArrow(systemName: "chevron.right", disabled: isCurrentMonth) {
                shiftMonth(1)
            }
        }
    }

    private func monthArrow(
        systemName: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LFColor.ink.opacity(disabled ? 0.2 : 0.75))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(LFPressableButtonStyle())
        .disabled(disabled)
        .accessibilityLabel(
            systemName == "chevron.left"
                ? Text("Previous month") : Text("Next month")
        )
    }

    private var dayGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: "\(days.count) \(LF.text("days"))")
                Text("·")
                Text(verbatim: "\(sessions.count) \(LF.text("records"))")
            }
            .font(LFFont.label(12))
            .foregroundStyle(LFColor.ink.opacity(0.5))

            if !days.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(days.sorted(by: >), id: \.self) { day in
                            Button {
                                selectedDay = day
                                Haptics.tap()
                            } label: {
                                Text(verbatim: LF.dayMonth(dateFor(day: day)))
                                    .font(LFFont.label(12))
                                    .monospacedDigit()
                                    .foregroundStyle(
                                        selectedDay == day ? LFColor.paper : LFColor.ink
                                    )
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 34)
                                    .background(
                                        selectedDay == day
                                            ? LFColor.ink : LFColor.seaGreen.opacity(0.20)
                                    )
                                    .clipShape(Capsule())
                                    .padding(.vertical, 5)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(dayAccessibilityLabel(day: day, studied: true))
                            .accessibilityAddTraits(selectedDay == day ? .isSelected : [])
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var dayDetail: some View {
        if days.isEmpty {
            Text("No records this day. Rest is part of the voyage.")
                .font(LFFont.copy(15))
                .foregroundStyle(LFColor.ink.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)
        } else if let selectedDay {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: LF.dayMonth(dateFor(day: selectedDay)))
                    .font(LFFont.label(13))
                    .tracking(1)
                    .foregroundStyle(LFColor.ink.opacity(0.5))
                    .padding(.top, 10)
                    .padding(.bottom, 2)

                if selectedSessions.isEmpty {
                    Text("No records this day. Rest is part of the voyage.")
                        .font(LFFont.copy(15))
                        .foregroundStyle(LFColor.ink.opacity(0.5))
                        .padding(.top, 12)
                } else {
                    ForEach(Array(selectedSessions.enumerated()), id: \.offset) { index, session in
                        if index > 0 {
                            Rectangle()
                                .fill(LFColor.ink.opacity(0.08))
                                .frame(height: 1)
                        }
                        publicSessionRow(session)
                    }
                }
            }
        } else {
            Text("Tap a day to see its records.")
                .font(LFFont.copy(15))
                .foregroundStyle(LFColor.ink.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)
        }
    }

    private func publicSessionRow(_ session: SharedSession) -> some View {
        let style = TileStyle.from(session.styleToken)
        let detail = sessionDetail(session)
        return HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(style.background)
                TileSymbolView(
                    symbol: TileSymbol.from(session.symbolToken),
                    fg: style.foreground,
                    bg: style.background
                )
                .frame(width: 20, height: 20)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: session.itemName ?? "—")
                    .font(LFFont.copy(16))
                    .foregroundStyle(LFColor.ink)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(LFFont.label(13))
                        .foregroundStyle(LFColor.ink.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(verbatim: LF.duration(minutes: session.minutes))
                .font(LFFont.label(15))
                .monospacedDigit()
                .foregroundStyle(LFColor.ink.opacity(0.7))
                .fixedSize()
        }
        .padding(.vertical, 8)
    }

    private func loadSelectedMonth() async {
        monthSubscription?.cancel()
        monthSubscription = nil
        loaded = false
        selectedDay = nil
        let requestedMonthID = monthID
        do {
            async let latestMember = service.member(of: slug, id: member.id)
            async let latestMonth = service.monthDetail(
                slug: slug,
                memberID: member.id,
                year: year,
                month: month
            )
            let (freshMember, detail) = try await (latestMember, latestMonth)
            guard !Task.isCancelled else { return }
            guard let freshMember else {
                days = []
                sessions = []
                loadError = LF.text("This sailor is no longer in this harbor.")
                loaded = true
                return
            }
            member = freshMember
            apply(detail)
            loadError = nil

            monthSubscription = service.observeMonthDetail(
                slug: slug,
                memberID: member.id,
                year: year,
                month: month
            ) { result in
                guard monthID == requestedMonthID else { return }
                switch result {
                case .success(let latest):
                    apply(latest)
                    loadError = nil
                    loaded = true
                case .failure:
                    // Keep the last complete server result visible. Pull to refresh remains
                    // available, and a later listener event can recover without a false empty UI.
                    break
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            days = []
            sessions = []
            loadError = LF.text("Couldn't refresh this sailor.")
        }
        loaded = true
    }

    private func apply(_ detail: PublicHarborMonthDetail) {
        days = detail.days
        sessions = detail.sessions
        if let selectedDay, detail.days.contains(selectedDay) {
            return
        }
        // Open on the newest recorded day so the latest complete set is visible immediately.
        selectedDay = detail.days.max()
    }

    private func retryMessage(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: message)
                .font(LFFont.copy(15))
                .foregroundStyle(LFColor.ink.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") {
                Task { await loadSelectedMonth() }
            }
            .font(LFFont.label(14))
            .foregroundStyle(LFColor.ink)
            .buttonStyle(.plain)
        }
    }

    private func shiftMonth(_ delta: Int) {
        guard let current = Calendar.current.date(
            from: DateComponents(year: year, month: month, day: 1)
        ), let shifted = Calendar.current.date(byAdding: .month, value: delta, to: current) else {
            return
        }
        let components = Calendar.current.dateComponents([.year, .month], from: shifted)
        year = components.year ?? year
        month = components.month ?? month
    }

    private func dateFor(day: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(year: year, month: month, day: day)
        ) ?? Date()
    }

    private func sessionDetail(_ session: SharedSession) -> String {
        var pieces: [String] = []
        if let date = session.date {
            pieces.append(Self.timeFormatter.string(from: date))
        }
        if let note = session.note, !note.isEmpty {
            pieces.append(note)
        }
        return pieces.joined(separator: " · ")
    }

    private func dayAccessibilityLabel(day: Int, studied: Bool) -> Text {
        let date = LF.dayWithWeekday(dateFor(day: day))
        let status = studied ? LF.text("Recorded") : LF.text("No records")
        return Text(verbatim: "\(date), \(status)")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
