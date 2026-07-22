import SwiftUI
import SwiftData

/// パブリックの港の中。参加している船乗りの名前・アイコン・作業記録が見える。
/// 記録は月ごとに残り続け、消せるのは書いた本人だけ(退港=自分の共有分の削除)。
struct PublicHarborView: View {
    let harbor: PublicHarbor

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthService
    @StateObject private var service = PublicHarborService.shared
    @StateObject private var chat = HarborChatService.shared
    @State private var members: [HarborMember] = []
    @State private var loaded = false
    @State private var working = false
    @State private var leaving = false
    /// 通報の確認対象(メンバー)。
    @State private var reporting: HarborMember?
    /// ブロックの確認対象(メンバー)。
    @State private var blocking: HarborMember?

    private var isJoined: Bool { service.joined.contains(harbor.slug) }
    private var myUid: String? { auth.user?.uid }

    /// ブロックした相手は一覧から外す。
    private var visibleMembers: [HarborMember] {
        members.filter { !chat.blocked.contains($0.id) }
    }

    var body: some View {
        ZStack {
            LFColor.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    joinButton
                        .padding(.top, 28)
                    membersSection
                        .padding(.top, 32)
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
        .task { await reload() }
        .refreshable { await reload() }
        .confirmationDialog(
            "Leave this harbor?",
            isPresented: $leaving,
            titleVisibility: .visible
        ) {
            Button("Leave this harbor", role: .destructive) {
                Task {
                    await service.leave(harbor.slug)
                    Haptics.tap()
                    await reload()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your name and shared records will be removed from this harbor. You can rejoin anytime.")
        }
        .confirmationDialog(
            "Report this sailor?",
            isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }),
            titleVisibility: .visible,
            presenting: reporting
        ) { member in
            Button("Report", role: .destructive) {
                chat.report(roomId: harbor.slug, message: nil, targetUid: member.id)
                Haptics.tap()
                reporting = nil
            }
            Button("Cancel", role: .cancel) { reporting = nil }
        } message: { _ in
            Text("This sends a report to the developer for review.")
        }
        .confirmationDialog(
            "Block this sailor?",
            isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }),
            titleVisibility: .visible,
            presenting: blocking
        ) { member in
            Button("Block", role: .destructive) {
                chat.block(member.id)
                Haptics.tap()
                blocking = nil
            }
            Button("Cancel", role: .cancel) { blocking = nil }
        } message: { _ in
            Text("You won't see them anymore. They won't be told.")
        }
    }

    private func reload() async {
        await chat.loadBlocked()
        members = await service.members(of: harbor.slug)
        loaded = true
    }

    // MARK: - 見出し

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(harbor.style.background)
                TileSymbolView(symbol: harbor.symbol, fg: harbor.style.foreground, bg: harbor.style.background)
                    .frame(width: 42, height: 42)
            }
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(harbor.title)
                    .font(LFFont.copy(24))
                    .foregroundStyle(LFColor.ink)
                Text(harbor.tagline)
                    .font(LFFont.label(14))
                    .foregroundStyle(LFColor.ink.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 参加

    @ViewBuilder
    private var joinButton: some View {
        if !auth.isSignedIn {
            Text("Sign in to enter a harbor.")
                .font(LFFont.copy(15))
                .foregroundStyle(LFColor.ink.opacity(0.5))
        } else if isJoined {
            Button {
                leaving = true
            } label: {
                Text("Leave this harbor")
                    .font(LFFont.label(14))
                    .foregroundStyle(LFColor.ink.opacity(0.45))
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    guard !working else { return }
                    working = true
                    Task {
                        defer { working = false }
                        try? await service.join(harbor.slug, context: modelContext)
                        Haptics.success()
                        await reload()
                    }
                } label: {
                    Text("Join this harbor")
                        .font(LFFont.copy(17))
                        .foregroundStyle(LFColor.paper)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(LFColor.ink)
                        .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
                }
                .buttonStyle(.plain)
                Text("Joining shares your name, icon, and study records here.")
                    .font(LFFont.label(13))
                    .foregroundStyle(LFColor.ink.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 在港の船乗り

    @ViewBuilder
    private var membersSection: some View {
        Text("Sailors in harbor")
            .font(LFFont.label(13))
            .tracking(1)
            .foregroundStyle(LFColor.ink.opacity(0.5))

        if !loaded {
            ProgressView()
                .tint(LFColor.ink)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else if visibleMembers.isEmpty {
            Text("No one is in this harbor yet. Be the first to drop anchor.")
                .font(LFFont.copy(15))
                .foregroundStyle(LFColor.ink.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        } else {
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
    }

    private func memberRow(_ member: HarborMember) -> some View {
        NavigationLink(value: PublicMemberKey(slug: harbor.slug, member: member)) {
            HStack(spacing: 14) {
                // 全員同じ大きさ。序列を作らない。
                PlayerAvatarArt(styleToken: member.styleToken, symbolToken: member.symbolToken)
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(verbatim: member.displayName)
                            .font(LFFont.copy(17))
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// パブリックの港のメンバーページへの遷移キー。
struct PublicMemberKey: Hashable {
    let slug: String
    let member: HarborMember
}
