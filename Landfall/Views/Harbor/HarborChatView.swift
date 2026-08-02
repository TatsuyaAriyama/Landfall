import Combine
import CryptoKit
import SwiftData
import SwiftUI

/// 最大4人のプライベート並走ルーム。
///
/// Web版と同じ一室の中に、船団の海・全員準備式の共通タイマー・チャットを置く。
/// 旧来の「歩ける港」には遷移せず、入室すると直接この海へ入る。
struct HarborChatView: View {
    let room: HarborRoom

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthService
    @Query(sort: \StudyItem.sortOrder) private var items: [StudyItem]
    @Query(sort: \StudyDay.date, order: .reverse) private var days: [StudyDay]

    @StateObject private var chat = HarborChatService.shared
    @StateObject private var crew = CrewSessionService()

    @State private var draft = ""
    @State private var chatOpen: Bool
    @State private var selectedItemID = ""
    @State private var intention = ""
    @State private var editingPlan = false
    @State private var customDuration = 25
    @State private var recall = ""
    @State private var now = Date()
    @State private var working = false
    @State private var actionError: String?
    @State private var copied = false
    @State private var reporting: ChatMessage?
    @State private var blocking: ChatMessage?
    @State private var receivedInitialMessages = false
    @FocusState private var inputFocused: Bool

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(room: HarborRoom) {
        self.room = room
        _chatOpen = State(
            initialValue: UserDefaults.standard.object(
                forKey: "harbor.chat.open.\(room.id)"
            ) as? Bool ?? true
        )
    }

    private var activeRoom: HarborRoom { crew.room ?? room }
    private var myUID: String? { auth.user?.uid ?? crew.currentUID }
    private var captainUID: String? {
        if let ownerUID = activeRoom.ownerUid,
           activeRoom.memberIds.contains(ownerUID) {
            return ownerUID
        }
        return activeRoom.memberIds.first
    }
    private var isCaptain: Bool { captainUID == myUID }

    private var membersByID: [String: HarborMember] {
        Dictionary(uniqueKeysWithValues: crew.members.map { ($0.id, $0) })
    }

    private var activePlans: [CrewPlan] {
        crew.plans.filter { activeRoom.memberIds.contains($0.uid) }
    }

    private var myPlan: CrewPlan? {
        guard let myUID else { return nil }
        return activePlans.first(where: { $0.uid == myUID })
    }

    private var allReady: Bool {
        !activeRoom.memberIds.isEmpty
            && activeRoom.memberIds.allSatisfy { uid in activePlans.contains(where: { $0.uid == uid }) }
    }

    private var allRecorded: Bool {
        !activePlans.isEmpty
            && activePlans.allSatisfy { $0.recordedAt != nil }
    }

    private var isUnderway: Bool {
        guard let startedAt = crew.session?.startedAt,
              let finishAt = crew.session?.finishAt else { return false }
        return now >= startedAt && now < finishAt
    }

    private var visibleMessages: [ChatMessage] {
        chat.messages.filter { !chat.blocked.contains($0.uid) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    roomHeader
                    CrewVoyageScene(
                        room: activeRoom,
                        members: crew.members,
                        selfUID: myUID,
                        underway: isUnderway
                    )
                    .padding(.top, 18)

                    sharedTimerSection
                        .padding(.top, 18)

                    chatSection(proxy: proxy)
                        .padding(.top, 26)

                    Color.clear
                        .frame(height: chatOpen ? 96 : 24)
                        .id("chat-end")
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .background {
                HarborOceanBackground()
            }
            .onChange(of: visibleMessages.last?.id) { _, _ in
                guard receivedInitialMessages else {
                    receivedInitialMessages = true
                    return
                }
                guard chatOpen else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo("chat-end", anchor: .bottom)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if chatOpen { inputBar }
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
            ToolbarItem(placement: .principal) {
                Text(verbatim: activeRoom.name)
                    .font(LFFont.copy(17))
                    .foregroundStyle(LFColor.ink)
                    .lineLimit(1)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            crew.listen(room: room)
            chat.listen(roomId: room.id)
            await chat.loadBlocked()
            loadPlanIntoForm(myPlan)
        }
        .onDisappear {
            crew.stop()
            chat.stop()
        }
        .onReceive(tick) { now = $0 }
        .onChange(of: myPlan) { _, plan in
            guard !editingPlan else { return }
            loadPlanIntoForm(plan)
        }
        .onChange(of: crew.session?.id) { _, _ in
            editingPlan = false
            recall = ""
            customDuration = crew.session?.durationMinutes ?? 25
            loadPlanIntoForm(myPlan)
        }
        .onChange(of: chatOpen) { _, open in
            UserDefaults.standard.set(open, forKey: "harbor.chat.open.\(room.id)")
        }
        .alert(
            "Couldn't update this voyage.",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(verbatim: actionError ?? "")
        }
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

    // MARK: - Room header

    private var roomHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Private fleet")
                    .font(LFFont.label(11))
                    .tracking(1.3)
                    .foregroundStyle(LFColor.ink.opacity(0.48))
                Text("Up to four sailors share one sea.")
                    .font(LFFont.copy(15))
                    .foregroundStyle(LFColor.ink)
            }
            Spacer(minLength: 8)
            Button {
                UIPasteboard.general.string = activeRoom.id
                copied = true
                Haptics.tap(.light)
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(copied ? "Copied" : "Invite code")
                        .font(LFFont.label(10))
                        .foregroundStyle(LFColor.ink.opacity(0.45))
                    Text(verbatim: activeRoom.id)
                        .font(LFFont.label(14))
                        .tracking(1.8)
                        .monospacedDigit()
                        .foregroundStyle(LFColor.returnOrange)
                }
                .frame(minWidth: 92, minHeight: 44, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Invite code \(activeRoom.id)"))
            .accessibilityHint(Text("Copy"))
        }
    }

    // MARK: - Shared timer

    @ViewBuilder
    private var sharedTimerSection: some View {
        if let session = crew.session {
            if session.startedAt == nil {
                preparationCard(session)
            } else if isUnderway {
                underwayCard(session)
            } else {
                arrivalCard(session)
            }
        } else {
            openingCard
        }
    }

    private var openingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("FLEET VOYAGE")
                .font(LFFont.label(11))
                .tracking(1.5)
                .foregroundStyle(LFColor.returnOrange)
            Text("Ready to set sail?")
                .font(LFFont.copy(23))
                .foregroundStyle(LFColor.ink)
            Text("Sail together with up to four people.")
                .font(LFFont.copy(15))
                .foregroundStyle(LFColor.ink.opacity(0.56))

            if isCaptain {
                Button {
                    perform {
                        try await crew.openSession(roomID: activeRoom.id, durationMinutes: 25)
                    }
                } label: {
                    primaryLabel("Prepare to depart")
                }
                .buttonStyle(LFPressableButtonStyle())
                .disabled(working)
            } else {
                waitingLine("The captain is preparing the fleet")
            }
        }
        .crewCard()
    }

    private func preparationCard(_ session: CrewSession) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DEPARTURE")
                        .font(LFFont.label(11))
                        .tracking(1.5)
                        .foregroundStyle(LFColor.returnOrange)
                    Text("Choose what you will work on today.")
                        .font(LFFont.copy(21))
                        .foregroundStyle(LFColor.ink)
                }
                Spacer(minLength: 12)
                Text("\(activePlans.count)/\(activeRoom.memberIds.count)")
                    .font(LFFont.label(13))
                    .monospacedDigit()
                    .foregroundStyle(LFColor.ink.opacity(0.58))
            }

            readinessRow

            if let myPlan, !editingPlan {
                planSummary(myPlan)
            } else {
                planEditor(session)
            }

            timerSetup(session)
        }
        .crewCard()
    }

    private var readinessRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(activeRoom.memberIds, id: \.self) { uid in
                    let member = membersByID[uid]
                    let ready = activePlans.contains(where: { $0.uid == uid })
                    VStack(spacing: 5) {
                        ZStack(alignment: .bottomTrailing) {
                            PlayerAvatarArt(
                                styleToken: member?.styleToken ?? TileStyle.midnight.rawValue,
                                symbolToken: member?.symbolToken ?? TileSymbol.phoenix.rawValue
                            )
                            .frame(width: 34, height: 34)
                            Circle()
                                .fill(ready ? LFColor.seaGreen : LFColor.paper)
                                .frame(width: 12, height: 12)
                                .overlay {
                                    Circle()
                                        .stroke(LFColor.ink.opacity(0.28), lineWidth: 1)
                                }
                        }
                        Text(verbatim: member?.displayName ?? LF.text("Sailor"))
                            .font(LFFont.label(10))
                            .lineLimit(1)
                        if uid == captainUID {
                            Text("Captain")
                                .font(LFFont.label(9))
                                .foregroundStyle(LFColor.returnOrange)
                        }
                    }
                    .frame(width: 66)
                }
            }
        }
    }

    private func planSummary(_ plan: CrewPlan) -> some View {
        let style = TileStyle.from(plan.itemStyle)
        return HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(style.background)
                TileSymbolView(
                    symbol: TileSymbol.from(plan.itemSymbol),
                    fg: style.foreground,
                    bg: style.background
                )
                .frame(width: 24, height: 24)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text("Ready")
                    .font(LFFont.label(10))
                    .foregroundStyle(LFColor.ink.opacity(0.45))
                Text(verbatim: plan.itemName)
                    .font(LFFont.copy(16))
                    .foregroundStyle(LFColor.ink)
                Text(verbatim: plan.intention)
                    .font(LFFont.label(12))
                    .foregroundStyle(LFColor.ink.opacity(0.58))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("Edit plan") {
                loadPlanIntoForm(plan)
                editingPlan = true
            }
            .font(LFFont.label(12))
            .foregroundStyle(LFColor.ink)
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(LFColor.ink.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func planEditor(_ session: CrewSession) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Your work for this voyage")
                .font(LFFont.label(12))
                .foregroundStyle(LFColor.ink.opacity(0.52))

            if items.isEmpty {
                Text("Create a work item on Home first.")
                    .font(LFFont.copy(14))
                    .foregroundStyle(LFColor.ink.opacity(0.5))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(items) { item in
                            let selected = selectedItemID == item.uuid.uuidString
                            Button {
                                selectedItemID = item.uuid.uuidString
                                Haptics.tap(.light)
                            } label: {
                                VStack(spacing: 6) {
                                    ItemTileArt(item: item)
                                        .frame(width: 46, height: 46)
                                    Text(verbatim: item.name)
                                        .font(LFFont.label(11))
                                        .foregroundStyle(LFColor.ink)
                                        .lineLimit(1)
                                }
                                .frame(width: 70)
                                .padding(.vertical, 8)
                                .background(
                                    selected ? LFColor.seaGreen.opacity(0.2) : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(
                                            selected ? LFColor.seaGreen : LFColor.ink.opacity(0.1),
                                            lineWidth: selected ? 1.5 : 1
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                TextField(
                    "e.g. Read chapter 3 and capture three key points",
                    text: $intention
                )
                .font(LFFont.copy(15))
                .foregroundStyle(LFColor.ink)
                .textInputAutocapitalization(.sentences)
                .padding(.horizontal, 14)
                .frame(height: 50)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(LFColor.ink.opacity(0.18), lineWidth: 1)
                }

                Button {
                    guard let item = selectedItem else { return }
                    perform {
                        try await crew.prepare(
                            roomID: activeRoom.id,
                            sessionID: session.id,
                            itemID: item.uuid.uuidString,
                            itemName: item.name,
                            itemStyle: item.styleToken,
                            itemSymbol: item.symbolToken,
                            intention: intention
                        )
                        editingPlan = false
                    }
                } label: {
                    secondaryLabel("Ready")
                }
                .buttonStyle(LFPressableButtonStyle())
                .disabled(selectedItem == nil || cleanIntention.isEmpty || working)
            }
        }
    }

    private func timerSetup(_ session: CrewSession) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voyage time")
                        .font(LFFont.label(12))
                        .foregroundStyle(LFColor.ink.opacity(0.52))
                    Text("Set by the captain")
                        .font(LFFont.label(10))
                        .foregroundStyle(LFColor.ink.opacity(0.38))
                }
                Spacer()
                Text(LF.duration(minutes: session.durationMinutes))
                    .font(LFFont.copy(20))
                    .foregroundStyle(LFColor.ink)
            }

            if isCaptain {
                HStack(spacing: 8) {
                    ForEach([25, 50, 90], id: \.self) { minutes in
                        Button {
                            customDuration = minutes
                            perform {
                                try await crew.updateDuration(
                                    roomID: activeRoom.id,
                                    sessionID: session.id,
                                    durationMinutes: minutes
                                )
                            }
                        } label: {
                            Text(LF.duration(minutes: minutes))
                                .font(LFFont.label(12))
                                .foregroundStyle(LFColor.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(
                                    session.durationMinutes == minutes
                                        ? LFColor.seaGreen.opacity(0.26)
                                        : LFColor.ink.opacity(0.045)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(working)
                    }
                }

                HStack(spacing: 10) {
                    Stepper(
                        value: $customDuration,
                        in: 1...240,
                        step: 5
                    ) {
                        Text("\(customDuration) min")
                            .font(LFFont.label(13))
                            .monospacedDigit()
                    }
                    Button("Set") {
                        perform {
                            try await crew.updateDuration(
                                roomID: activeRoom.id,
                                sessionID: session.id,
                                durationMinutes: customDuration
                            )
                        }
                    }
                    .font(LFFont.label(13))
                    .foregroundStyle(LFColor.ink)
                    .buttonStyle(.bordered)
                    .disabled(working)
                }

                Button {
                    perform {
                        try await crew.start(roomID: activeRoom.id, sessionID: session.id)
                        Haptics.success()
                    }
                } label: {
                    primaryLabel("Set sail")
                }
                .buttonStyle(LFPressableButtonStyle())
                .disabled(!allReady || working)

                if !allReady {
                    Text("Departure opens when everyone is ready.")
                        .font(LFFont.label(11))
                        .foregroundStyle(LFColor.ink.opacity(0.48))
                }
            } else {
                waitingLine(
                    allReady
                        ? "The captain will set sail."
                        : "Waiting for everyone to get ready."
                )
            }
        }
        .padding(.top, 2)
    }

    private func underwayCard(_ session: CrewSession) -> some View {
        let remaining = max(0, session.finishAt?.timeIntervalSince(now) ?? 0)
        let elapsed = max(0, now.timeIntervalSince(session.startedAt ?? now))
        let total = max(1, TimeInterval(session.durationMinutes * 60))
        let progress = min(max(elapsed / total, 0), 1)

        return VStack(alignment: .leading, spacing: 15) {
            Text("FLEET VOYAGE UNDERWAY")
                .font(LFFont.label(11))
                .tracking(1.5)
                .foregroundStyle(LFColor.returnOrange)
            HStack(alignment: .lastTextBaseline) {
                Text(clockLabel(remaining))
                    .font(LFFont.copy(38))
                    .monospacedDigit()
                    .foregroundStyle(LFColor.ink)
                Spacer()
                Text("Landfall in")
                    .font(LFFont.label(12))
                    .foregroundStyle(LFColor.ink.opacity(0.48))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(LFColor.ink.opacity(0.09))
                    Capsule()
                        .fill(LFColor.seaGreen)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 7)

            if let myPlan {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: myPlan.itemName)
                        .font(LFFont.copy(16))
                        .foregroundStyle(LFColor.ink)
                    Text(verbatim: myPlan.intention)
                        .font(LFFont.label(12))
                        .foregroundStyle(LFColor.ink.opacity(0.56))
                }
            } else {
                Text("This voyage has already departed.")
                    .font(LFFont.copy(14))
                    .foregroundStyle(LFColor.ink.opacity(0.5))
            }
        }
        .crewCard()
    }

    private func arrivalCard(_ session: CrewSession) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("LANDFALL")
                .font(LFFont.label(11))
                .tracking(1.5)
                .foregroundStyle(LFColor.returnOrange)

            if let myPlan, myPlan.recordedAt == nil {
                Text(verbatim: myPlan.itemName)
                    .font(LFFont.copy(23))
                    .foregroundStyle(LFColor.ink)
                Text("Without looking, write down what you can remember.")
                    .font(LFFont.copy(15))
                    .foregroundStyle(LFColor.ink.opacity(0.56))

                TextEditor(text: $recall)
                    .font(LFFont.copy(15))
                    .foregroundStyle(LFColor.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 118)
                    .padding(10)
                    .background(LFColor.ink.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(LFColor.ink.opacity(0.16), lineWidth: 1)
                    }

                HStack {
                    Text(
                        verbatim: "\(cleanRecall.count)/20 · "
                            + LF.text("At least 20 characters")
                    )
                        .font(LFFont.label(11))
                        .foregroundStyle(
                            cleanRecall.count >= 20
                                ? LFColor.seaGreen
                                : LFColor.ink.opacity(0.45)
                        )
                    Spacer()
                }

                Button {
                    recordCrewVoyage(session: session, plan: myPlan)
                } label: {
                    primaryLabel("Finish voyage log")
                }
                .buttonStyle(LFPressableButtonStyle())
                .disabled(cleanRecall.count < 20 || working)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(LFColor.seaGreen)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            myPlan == nil
                                ? "This voyage has already departed."
                                : "Your voyage log is safely stowed"
                        )
                        .font(LFFont.copy(16))
                        .foregroundStyle(LFColor.ink)
                        if !allRecorded {
                            Text("Waiting for the crew to finish recalling")
                                .font(LFFont.label(11))
                                .foregroundStyle(LFColor.ink.opacity(0.46))
                        }
                    }
                }
            }

            if isCaptain && allRecorded {
                Button {
                    perform {
                        try await crew.openSession(
                            roomID: activeRoom.id,
                            durationMinutes: session.durationMinutes
                        )
                    }
                } label: {
                    secondaryLabel("Prepare the next voyage")
                }
                .buttonStyle(LFPressableButtonStyle())
                .disabled(working)
            }
        }
        .crewCard()
    }

    // MARK: - Chat

    private func chatSection(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("THE VOYAGE TOGETHER")
                        .font(LFFont.label(11))
                        .tracking(1.4)
                        .foregroundStyle(LFColor.ink.opacity(0.48))
                    Text("Chat")
                        .font(LFFont.copy(21))
                        .foregroundStyle(LFColor.ink)
                }
                Spacer()
                Button {
                    chatOpen.toggle()
                    Haptics.tap(.light)
                    if chatOpen {
                        DispatchQueue.main.async {
                            proxy.scrollTo("chat-end", anchor: .bottom)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: chatOpen ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                        Text(chatOpen ? "Close chat" : "Open chat")
                            .font(LFFont.label(12))
                    }
                    .foregroundStyle(LFColor.ink.opacity(0.6))
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }

            if chatOpen {
                if visibleMessages.isEmpty {
                    Text("Records land here on their own. Words are optional.")
                        .font(LFFont.label(14))
                        .foregroundStyle(LFColor.ink.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 34)
                } else {
                    ForEach(visibleMessages) { message in
                        messageRow(message)
                    }
                }
            } else {
                Text("Messages still arrive while the chat is closed.")
                    .font(LFFont.copy(14))
                    .foregroundStyle(LFColor.ink.opacity(0.46))
                    .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        switch message.kind {
        case .text:
            textBubble(message)
        case .landfall, .ret:
            logLine(message)
        }
    }

    private func textBubble(_ message: ChatMessage) -> some View {
        let mine = message.uid == myUID
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
                .contextMenu { messageMenu(message) }
            reactionsRow(message)
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

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
                        Text("\(displayName(of: message.uid)) returned — first sail in \(gap) days.")
                    } else if let name = message.itemName, let minutes = message.minutes {
                        Text(
                            "\(displayName(of: message.uid)) made landfall — \(name), \(LF.duration(minutes: minutes))"
                        )
                    }
                }
                .font(LFFont.label(13))
                .foregroundStyle(isReturn ? LFColor.returnOrange : LFColor.ink.opacity(0.55))
                .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .contextMenu { messageMenu(message) }
            reactionsRow(message)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 2)
    }

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
                            Image(systemName: reaction.systemImage)
                                .font(.system(size: 11, weight: .medium))
                            Text(verbatim: "\(count)")
                                .font(LFFont.label(11))
                                .monospacedDigit()
                        }
                        .foregroundStyle(
                            LFColor.ink.opacity(
                                message.reactions[myUID ?? ""] == reaction.rawValue ? 0.9 : 0.5
                            )
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(LFColor.ink.opacity(0.15), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func messageMenu(_ message: ChatMessage) -> some View {
        ForEach(ChatReaction.allCases, id: \.rawValue) { reaction in
            Button {
                chat.react(roomId: room.id, message: message, reaction: reaction)
            } label: {
                Label(reaction.title, systemImage: reaction.systemImage)
            }
        }
        Divider()
        if message.uid == myUID {
            if message.kind == .text,
               Date().timeIntervalSince(message.createdAt) < 3_600 {
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

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("A word to the harbor (optional)", text: $draft)
                .font(LFFont.label(15))
                .foregroundStyle(LFColor.ink)
                .tint(LFColor.ink)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(LFColor.paper)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(LFColor.ink.opacity(0.2), lineWidth: 1)
                }

            Button {
                let text = draft
                if chat.send(roomId: room.id, text: text) {
                    draft = ""
                } else {
                    actionError = LF.text("That message could not be sent. Please revise it.")
                }
                inputFocused = true
                Haptics.tap(.light)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(LFColor.paper)
                    .frame(width: 40, height: 40)
                    .background(
                        cleanDraft.isEmpty ? LFColor.ink.opacity(0.3) : LFColor.ink
                    )
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(cleanDraft.isEmpty)
            .accessibilityLabel(Text("Send"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(LFColor.paper)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LFColor.ink.opacity(0.08))
                .frame(height: 1)
        }
    }

    // MARK: - Actions and helpers

    private var selectedItem: StudyItem? {
        items.first(where: { $0.uuid.uuidString == selectedItemID })
    }

    private var cleanDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cleanIntention: String {
        intention.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cleanRecall: String {
        recall.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadPlanIntoForm(_ plan: CrewPlan?) {
        if let plan {
            selectedItemID = plan.itemID
            intention = plan.intention
            recall = plan.recall ?? ""
        } else {
            selectedItemID = items.first?.uuid.uuidString ?? ""
            intention = ""
            recall = ""
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !working else { return }
        working = true
        Task {
            defer { working = false }
            do {
                try await operation()
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func recordCrewVoyage(session: CrewSession, plan: CrewPlan) {
        guard let uid = myUID,
              let itemUUID = UUID(uuidString: plan.itemID),
              let item = items.first(where: { $0.uuid == itemUUID }) else {
            actionError = LF.text("The work item for this voyage is no longer available.")
            return
        }

        let recordID = deterministicCrewUUID(
            roomID: activeRoom.id,
            sessionID: session.id,
            uid: uid
        )
        let finishDate = session.finishAt ?? Date()
        let isToday = Calendar.current.isDateInToday(finishDate)
        let blanks = isToday ? MonthStats.blankDays(since: days.first?.date, to: finishDate) : nil

        perform {
            var descriptor = FetchDescriptor<StudySession>(
                predicate: #Predicate { $0.uuid == recordID }
            )
            descriptor.fetchLimit = 1
            let existing = (try? modelContext.fetch(descriptor))?.first

            if existing == nil {
                let local = StudySession(
                    date: finishDate,
                    minutes: session.durationMinutes,
                    note: cleanRecall,
                    item: item
                )
                local.uuid = recordID
                modelContext.insert(local)
                StudyDayStore.markDay(finishDate, context: modelContext)
                do {
                    try modelContext.save()
                } catch {
                    modelContext.delete(local)
                    throw error
                }
                SyncService.shared.push(local)
                RoomService.shared.publishCurrentMonth(context: modelContext)
                HarborChatService.shared.publishLog(
                    item: item,
                    minutes: session.durationMinutes,
                    gapDays: blanks,
                    isToday: isToday
                )
                WidgetBridge.refresh(context: modelContext)
                let recordedToday = StudyDayStore.recordedToday(context: modelContext)
                Task { await NotificationService.reschedule(recordedToday: recordedToday) }
            }

            try await crew.markRecorded(
                roomID: activeRoom.id,
                sessionID: session.id,
                recall: cleanRecall
            )
            Haptics.success()
        }
    }

    private func deterministicCrewUUID(roomID: String, sessionID: String, uid: String) -> UUID {
        let digest = SHA256.hash(data: Data("\(roomID)|\(sessionID)|\(uid)".utf8))
        let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        let part1 = String(hex.prefix(8))
        let part2 = String(hex.dropFirst(8).prefix(4))
        let part3 = String(hex.dropFirst(12).prefix(4))
        let part4 = String(hex.dropFirst(16).prefix(4))
        let part5 = String(hex.dropFirst(20).prefix(12))
        let string = "\(part1)-\(part2)-\(part3)-\(part4)-\(part5)"
        return UUID(uuidString: string) ?? UUID()
    }

    private func displayName(of uid: String) -> String {
        membersByID[uid]?.displayName ?? LF.text("Sailor")
    }

    private func clockLabel(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(ceil(seconds)))
        let hours = total / 3_600
        let minutes = (total / 60) % 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func primaryLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(LFFont.copy(16))
            .foregroundStyle(LFColor.paper)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(working ? LFColor.ink.opacity(0.34) : LFColor.ink)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private func secondaryLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(LFFont.copy(16))
            .foregroundStyle(LFColor.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(LFColor.ink.opacity(0.26), lineWidth: 1)
            }
    }

    private func waitingLine(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(LFColor.seaGreen)
                .frame(width: 8, height: 8)
            Text(title)
                .font(LFFont.copy(14))
                .foregroundStyle(LFColor.ink.opacity(0.56))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }
}

private extension View {
    func crewCard() -> some View {
        padding(18)
            .background(LFColor.paper)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(LFColor.ink.opacity(0.12), lineWidth: 1)
            }
    }
}
