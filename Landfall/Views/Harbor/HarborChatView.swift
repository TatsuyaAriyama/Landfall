import SwiftUI

/// プライベートの港のチャット。
/// 言葉と、メンバーの「着岸/帰還」の自動の行がひとつの流れに混ざる。
/// 見に行かなくても、同じ時間を航海している感じがする場所。
struct HarborChatView: View {
    let room: HarborRoom

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthService
    @StateObject private var chat = HarborChatService.shared
    @State private var members: [String: HarborMember] = [:]
    @State private var draft = ""
    @FocusState private var inputFocused: Bool
    /// 通報の確認対象。
    @State private var reporting: ChatMessage?
    /// ブロックの確認対象。
    @State private var blocking: ChatMessage?

    private var myUid: String? { auth.user?.uid }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            inputBar
        }
        .background(LFColor.paper)
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
            ToolbarItem(placement: .principal) {
                Text(verbatim: room.name)
                    .font(LFFont.copy(17))
                    .foregroundStyle(LFColor.ink)
            }
        }
        .toolbarBackground(LFColor.paper, for: .navigationBar)
        .task {
            chat.listen(roomId: room.id)
            await chat.loadBlocked()
            let list = await RoomService.shared.members(of: room.id)
            members = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        }
        .onDisappear { chat.stop() }
        .confirmationDialog(
            "Report this message?",
            isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }),
            titleVisibility: .visible,
            presenting: reporting
        ) { message in
            Button("Report", role: .destructive) {
                chat.report(roomId: room.id, message: message, targetUid: message.uid)
                Haptics.tap()
                reporting = nil
            }
            Button("Cancel", role: .cancel) { reporting = nil }
        } message: { _ in
            Text("This sends the message to the developer for review.")
        }
        .confirmationDialog(
            "Block this sailor?",
            isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }),
            titleVisibility: .visible,
            presenting: blocking
        ) { message in
            Button("Block", role: .destructive) {
                chat.block(message.uid)
                Haptics.tap()
                blocking = nil
            }
            Button("Cancel", role: .cancel) { blocking = nil }
        } message: { _ in
            Text("You won't see their messages anymore. They won't be told.")
        }
    }

    // MARK: - メッセージ一覧

    private var visibleMessages: [ChatMessage] {
        chat.messages.filter { !chat.blocked.contains($0.uid) }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if visibleMessages.isEmpty {
                        Text("Records land here on their own. Words are optional.")
                            .font(LFFont.label(14))
                            .foregroundStyle(LFColor.ink.opacity(0.45))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                    }
                    ForEach(visibleMessages) { message in
                        messageRow(message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: visibleMessages.last?.id) { _, last in
                if let last {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        switch message.kind {
        case .text: textBubble(message)
        case .landfall, .ret: logLine(message)
        }
    }

    // MARK: - 発言

    private func textBubble(_ message: ChatMessage) -> some View {
        let mine = message.uid == myUid
        return VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
            if !mine {
                Text(verbatim: displayName(of: message.uid))
                    .font(LFFont.label(11))
                    .foregroundStyle(LFColor.ink.opacity(0.45))
            }
            Text(verbatim: message.text ?? "")
                .font(LFFont.label(15))
                .foregroundStyle(mine ? LFColor.paper : LFColor.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(mine ? LFColor.ink : LFColor.ink.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contextMenu { menu(for: message) }
            reactionsRow(message)
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    // MARK: - 着岸/帰還の自動の行

    /// 記録が流れ込んだ行。発言より静かに、でも帰還はあたたかく。
    private func logLine(_ message: ChatMessage) -> some View {
        let isReturn = message.kind == .ret
        return VStack(spacing: 4) {
            HStack(spacing: 8) {
                if let style = message.itemStyle, let symbol = message.itemSymbol {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(TileStyle.from(style).background)
                        TileSymbolView(
                            symbol: TileSymbol.from(symbol),
                            fg: TileStyle.from(style).foreground,
                            bg: TileStyle.from(style).background
                        )
                        .frame(width: 14, height: 14)
                    }
                    .frame(width: 24, height: 24)
                }
                Group {
                    if isReturn, let gap = message.gapDays {
                        Text("\(displayNameText(of: message.uid)) returned — first sail in \(gap) days.")
                    } else if let name = message.itemName, let minutes = message.minutes {
                        Text("\(displayNameText(of: message.uid)) made landfall — \(name), \(LF.duration(minutes: minutes))")
                    }
                }
                .font(LFFont.label(13))
                .foregroundStyle(isReturn ? LFColor.returnOrange : LFColor.ink.opacity(0.55))
                .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .contextMenu { menu(for: message) }
            reactionsRow(message)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 2)
    }

    // MARK: - リアクション

    private func reactionsRow(_ message: ChatMessage) -> some View {
        let counts = Dictionary(grouping: message.reactions.values, by: { $0 })
            .compactMapValues(\.count)
        return HStack(spacing: 8) {
            ForEach(ChatReaction.allCases, id: \.rawValue) { reaction in
                if let count = counts[reaction.rawValue], count > 0 {
                    Button {
                        Haptics.tap(.light)
                        chat.react(roomId: room.id, message: message, reaction: reaction)
                    } label: {
                        HStack(spacing: 3) {
                            TileSymbolView(symbol: reaction.symbol, fg: LFColor.ink, bg: LFColor.paper)
                                .frame(width: 13, height: 13)
                            Text(verbatim: "\(count)")
                                .font(LFFont.label(11))
                                .monospacedDigit()
                        }
                        .foregroundStyle(LFColor.ink.opacity(
                            message.reactions[myUid ?? ""] == reaction.rawValue ? 0.9 : 0.5
                        ))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(LFColor.ink.opacity(0.15), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 長押しメニュー: リアクション3種 + 自分の発言は削除 / 他人は通報・ブロック。
    @ViewBuilder
    private func menu(for message: ChatMessage) -> some View {
        ForEach(ChatReaction.allCases, id: \.rawValue) { reaction in
            Button {
                chat.react(roomId: room.id, message: message, reaction: reaction)
            } label: {
                Label(reactionLabel(reaction), systemImage: reactionSystemImage(reaction))
            }
        }
        Divider()
        if message.uid == myUid {
            if message.kind == .text {
                Button(role: .destructive) {
                    chat.delete(roomId: room.id, messageId: message.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } else {
            Button {
                reporting = message
            } label: {
                Label("Report", systemImage: "flag")
            }
            Button(role: .destructive) {
                blocking = message
            } label: {
                Label("Block this sailor", systemImage: "hand.raised")
            }
        }
    }

    private func reactionLabel(_ reaction: ChatReaction) -> LocalizedStringKey {
        switch reaction {
        case .lighthouse: "I see you."
        case .anchor: "Rest easy."
        case .phoenix: "Welcome back."
        }
    }

    private func reactionSystemImage(_ reaction: ChatReaction) -> String {
        switch reaction {
        case .lighthouse: "light.beacon.max"
        case .anchor: "link"
        case .phoenix: "bird"
        }
    }

    // MARK: - 入力

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("A word to the harbor (optional)", text: $draft, axis: .vertical)
                .font(LFFont.label(15))
                .foregroundStyle(LFColor.ink)
                .tint(LFColor.ink)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(LFColor.ink.opacity(0.2), lineWidth: 1)
                )
            Button {
                let text = draft
                draft = ""
                chat.send(roomId: room.id, text: text)
                Haptics.tap(.light)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(LFColor.paper)
                    .frame(width: 36, height: 36)
                    .background(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? LFColor.ink.opacity(0.3) : LFColor.ink)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(Text("Send"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(LFColor.paper)
    }

    // MARK: - 名前

    private func displayName(of uid: String) -> String {
        members[uid]?.displayName ?? String(localized: "Sailor")
    }

    private func displayNameText(of uid: String) -> String {
        displayName(of: uid)
    }
}
