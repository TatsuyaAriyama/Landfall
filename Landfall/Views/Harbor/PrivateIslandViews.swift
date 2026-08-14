import SwiftUI
import UIKit

#if DEBUG
/// Stable visual-QA route for the new Private experience. It never talks to
/// Firestore and therefore remains usable before a test account has joined an
/// island on a fresh Simulator.
struct PrivateIslandPreviewView: View {
    @State private var showingVoyagePass = false

    private let room = PrivateIslandRoom(
        id: "W7D3UD",
        name: "星影の島",
        hostUid: "preview-self",
        memberIds: ["preview-self", "preview-akari", "preview-nagi"],
        createdAt: .now
    )

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x8BCFDB), Color(hex: 0x2CCFC5)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                PrivateIslandLobbyView(
                    rooms: [],
                    currentUserID: "preview-self",
                    canHost: ProcessInfo.processInfo.environment["LANDFALL_PASS_ACTIVE"] == "1",
                    isHostAccessLoading: false,
                    onOpenVoyagePass: { showingVoyagePass = true },
                    onCreate: { _ in room },
                    onJoin: { _ in room },
                    onVisit: { _ in },
                    onLeave: nil
                )
                .padding(.top, 64)
            }
            .safeAreaPadding(.horizontal, 12)
        }
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $showingVoyagePass) {
            VoyagePassView()
        }
    }
}
#endif

/// Service-independent presentation for the new private-island experience.
///
/// The view deliberately receives immutable room values and async actions. This
/// keeps Firestore listeners and visit-session ownership outside the UI, while
/// still allowing the lobby to own transient form and error state.
struct PrivateIslandLobbyView: View {
    let rooms: [PrivateIslandRoom]
    let currentUserID: String
    var isLoading = false
    var canHost: Bool
    var isHostAccessLoading: Bool
    var onOpenVoyagePass: () -> Void
    var onCreate: (String) async throws -> PrivateIslandRoom
    var onJoin: (String) async throws -> PrivateIslandRoom
    var onVisit: (PrivateIslandRoom) -> Void
    var onLeave: ((PrivateIslandRoom) -> Void)?
    var onCloseOwned: ((PrivateIslandRoom) -> Void)? = nil

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var presentedAction: PrivateIslandLobbyAction?

    private var ownedRoom: PrivateIslandRoom? {
        rooms.first(where: { $0.hostUid == currentUserID })
    }

    private var joinedRooms: [PrivateIslandRoom] {
        rooms
            .filter { $0.hostUid != currentUserID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: usesCompactCards ? 12 : 20) {
            if !usesCompactCards {
                header
            }
            entryActions
                .overlay(alignment: .topTrailing) {
                    if isLoading, rooms.isEmpty {
                        ProgressView()
                            .tint(PrivateIslandGlass.ink)
                            .frame(width: 44, height: 44)
                            .accessibilityLabel(Text("Looking for private islands…"))
                    }
                }

            if let ownedRoom {
                sectionTitle("Your private island")
                roomCard(ownedRoom, role: .host)
            }

            if !joinedRooms.isEmpty {
                sectionTitle("Islands you can visit")
                joinedRoomGrid
            }
        }
        .frame(maxWidth: 820, alignment: .leading)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, usesCompactCards ? 0 : 10)
        .padding(.bottom, usesCompactCards ? 0 : 28)
        .frame(maxWidth: .infinity)
        .sheet(item: $presentedAction) { action in
            switch action {
            case .create:
                PrivateIslandCreateSheet(onCreate: onCreate, onCreated: onVisit)
            case .join:
                PrivateIslandJoinSheet(onJoin: onJoin, onJoined: onVisit)
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.2),
            value: rooms.map(\.id)
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(PrivateIslandGlass.ink.opacity(0.08))
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(PrivateIslandGlass.ink)
            }
            .frame(width: 48, height: 48)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("PRIVATE ISLANDS")
                    .font(LFFont.label(10))
                    .tracking(1.5)
                    .foregroundStyle(PrivateIslandGlass.ink.opacity(0.5))

                Text("Visit an island together")
                    .font(LFFont.copy(21))
                    .foregroundStyle(PrivateIslandGlass.ink)

                Text("Enter an invite code, sail in, and step ashore at your friend's jetty.")
                    .font(LFFont.label(13))
                    .foregroundStyle(PrivateIslandGlass.ink.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var entryActions: some View {
        LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 12) {
            joinCodeCard
            if ownedRoom == nil, !isLoading {
                createIslandCard
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var createIslandCard: some View {
        Button {
            Haptics.tap(.light)
            if canHost {
                presentedAction = .create
            } else {
                onOpenVoyagePass()
            }
        } label: {
            entryActionLabel(
                symbol: "globe.asia.australia.fill",
                badge: canHost ? "READY" : "VOYAGE PASS",
                title: "Host your own island",
                detail: canHost
                    ? "Create an island, then share its six-character code."
                    : "A Voyage Pass is needed to host. Joining stays free.",
                isPrimary: false,
                isWorking: isHostAccessLoading
            )
        }
        .buttonStyle(LFPressableButtonStyle())
        .disabled(isHostAccessLoading)
        .accessibilityHint(
            Text(canHost ? "Opens the island creation form" : "Opens Voyage Pass")
        )
    }

    private var joinedRoomGrid: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
            ForEach(joinedRooms) { room in
                roomCard(room, role: .guest)
            }
        }
    }

    private var joinCodeCard: some View {
        Button {
            Haptics.tap(.light)
            presentedAction = .join
        } label: {
            entryActionLabel(
                symbol: "key.horizontal.fill",
                badge: "FREE",
                title: "Join with an invite code",
                detail: "Enter a friend's six-character code and sail straight to their island.",
                isPrimary: true,
                isWorking: false
            )
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityHint(Text("Adds a friend's island"))
    }

    @ViewBuilder
    private func entryActionLabel(
        symbol: String,
        badge: LocalizedStringKey,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        isPrimary: Bool,
        isWorking: Bool
    ) -> some View {
        if usesCompactCards, dynamicTypeSize < .xxxLarge {
            compactEntryActionLabel(
                symbol: symbol,
                title: title,
                isPrimary: isPrimary,
                isWorking: isWorking
            )
        } else {
            regularEntryActionLabel(
                symbol: symbol,
                badge: badge,
                title: title,
                detail: detail,
                isPrimary: isPrimary,
                isWorking: isWorking
            )
        }
    }

    private func compactEntryActionLabel(
        symbol: String,
        title: LocalizedStringKey,
        isPrimary: Bool,
        isWorking: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                ZStack {
                    Circle()
                        .fill(isPrimary ? Color.white.opacity(0.12) : PrivateIslandGlass.ink.opacity(0.07))
                    if isWorking {
                        ProgressView()
                            .tint(isPrimary ? .white : PrivateIslandGlass.ink)
                            .controlSize(.small)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

                Spacer(minLength: 4)

                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(0.56)
            }

            Text(title)
                .font(LFFont.copy(14))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(isPrimary ? "Enter code" : (canHost ? "Create island" : "View Voyage Pass"))
                .font(LFFont.label(10))
                .opacity(0.62)
        }
        .foregroundStyle(isPrimary ? Color.white : PrivateIslandGlass.ink)
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .background {
            if isPrimary {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(PrivateIslandGlass.ink)
            } else {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(Color.clear)
                    .privateIslandGlass(cornerRadius: 19)
            }
        }
    }

    private func regularEntryActionLabel(
        symbol: String,
        badge: LocalizedStringKey,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        isPrimary: Bool,
        isWorking: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(isPrimary ? Color.white.opacity(0.12) : PrivateIslandGlass.ink.opacity(0.07))
                    if isWorking {
                        ProgressView()
                            .tint(isPrimary ? .white : PrivateIslandGlass.ink)
                            .controlSize(.small)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .frame(width: 42, height: 42)

                Spacer(minLength: 6)

                Text(badge)
                    .font(LFFont.label(9))
                    .tracking(0.8)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        isPrimary ? Color.white.opacity(0.12) : PrivateIslandGlass.ink.opacity(0.06),
                        in: Capsule()
                    )
            }

            Text(title)
                .font(LFFont.copy(16))

            Text(detail)
                .font(LFFont.label(11))
                .opacity(0.66)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Text(isPrimary ? "Enter code" : (canHost ? "Create island" : "View Voyage Pass"))
                    .font(LFFont.copy(12))
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.top, 2)
        }
        .foregroundStyle(isPrimary ? Color.white : PrivateIslandGlass.ink)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background {
            if isPrimary {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(PrivateIslandGlass.ink)
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.clear)
                    .privateIslandGlass(cornerRadius: 22)
            }
        }
    }

    private func roomCard(
        _ room: PrivateIslandRoom,
        role: PrivateIslandRoomRole
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(PrivateIslandGlass.ink.opacity(0.075))
                    Image(systemName: role == .host ? "house.and.flag.fill" : "sailboat.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PrivateIslandGlass.ink)
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: room.name)
                        .font(LFFont.copy(17))
                        .foregroundStyle(PrivateIslandGlass.ink)
                        .lineLimit(1)
                    Text(role == .host ? "Hosted by you" : "Friend's island")
                        .font(LFFont.label(11))
                        .foregroundStyle(PrivateIslandGlass.ink.opacity(0.5))
                }

                Spacer(minLength: 6)

                Label {
                    Text(verbatim: "\(room.memberIds.count)")
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "person.2.fill")
                }
                .font(LFFont.label(11))
                .foregroundStyle(PrivateIslandGlass.ink.opacity(0.48))
                .accessibilityLabel(Text("\(room.memberIds.count) members"))
            }

            HStack(spacing: 8) {
                Text("Invite code")
                    .font(LFFont.label(9))
                    .foregroundStyle(PrivateIslandGlass.ink.opacity(0.44))

                Text(verbatim: room.code)
                    .font(LFFont.label(13))
                    .tracking(1.7)
                    .monospacedDigit()
                    .foregroundStyle(PrivateIslandGlass.ink)

                Spacer(minLength: 2)

                ShareLink(item: shareText(for: room)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PrivateIslandGlass.ink)
                        .frame(width: 44, height: 44)
                        .background(PrivateIslandGlass.ink.opacity(0.06), in: Circle())
                }
                .buttonStyle(LFPressableButtonStyle())
                .accessibilityLabel(Text("Share invite code \(room.code)"))
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .frame(height: 46)
            .background(
                PrivateIslandGlass.ink.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )

            HStack(spacing: 8) {
                Button {
                    Haptics.tap(.medium)
                    onVisit(room)
                } label: {
                    Label(
                        role == .host ? "Enter your island" : "Sail to this island",
                        systemImage: "arrow.right"
                    )
                    .font(LFFont.copy(13))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        PrivateIslandGlass.ink,
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                }
                .buttonStyle(LFPressableButtonStyle())

                if role == .guest, let onLeave {
                    Button {
                        Haptics.tap(.light)
                        onLeave(room)
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PrivateIslandGlass.ink.opacity(0.64))
                            .frame(width: 44, height: 44)
                            .overlay {
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .stroke(PrivateIslandGlass.ink.opacity(0.14), lineWidth: 1)
                            }
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .accessibilityLabel(Text("Remove this island"))
                } else if role == .host, let onCloseOwned {
                    Button {
                        Haptics.tap(.light)
                        onCloseOwned(room)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(LFColor.deepRust)
                            .frame(width: 44, height: 44)
                            .overlay {
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .stroke(LFColor.deepRust.opacity(0.22), lineWidth: 1)
                            }
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .accessibilityLabel(Text("Close this private island"))
                }
            }
        }
        .padding(15)
        .privateIslandGlass(cornerRadius: 23)
        .accessibilityElement(children: .contain)
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(LFFont.label(11))
            .tracking(0.9)
            .foregroundStyle(PrivateIslandGlass.ink.opacity(0.5))
            .padding(.top, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private func shareText(for room: PrivateIslandRoom) -> String {
        let link = LandfallLink.invite(code: room.code).absoluteString
        return LF.format(
            "Come visit \"%@\" on KeelMira. Invite code: %@\n%@",
            room.name,
            room.code,
            link
        )
    }

    private var gridColumns: [GridItem] {
        guard horizontalSizeClass == .regular else {
            return [GridItem(.flexible(), spacing: 12)]
        }
        return [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
    }

    private var actionColumns: [GridItem] {
        if usesCompactCards, dynamicTypeSize < .xxxLarge, ownedRoom == nil {
            return [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ]
        }
        guard horizontalSizeClass == .regular else {
            return [GridItem(.flexible(), spacing: 12)]
        }
        return [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
    }

    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 28 : 14
    }

    private var usesCompactCards: Bool {
        horizontalSizeClass != .regular
    }
}

// MARK: - Create and join

private enum PrivateIslandLobbyAction: String, Identifiable {
    case create
    case join

    var id: String { rawValue }
}

private enum PrivateIslandRoomRole {
    case host
    case guest
}

private struct PrivateIslandCreateSheet: View {
    let onCreate: (String) async throws -> PrivateIslandRoom
    let onCreated: (PrivateIslandRoom) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    @State private var name = ""
    @State private var isSubmitting = false
    @State private var errorText: String?

    private var cleanName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        PrivateIslandFormScaffold(
            symbol: "house.and.flag.fill",
            eyebrow: "YOUR PRIVATE ISLAND",
            title: "Create an island",
            message: "Friends who enter your code can arrive by boat and explore with you.",
            onClose: { dismiss() }
        ) {
            TextField("Island name", text: $name)
                .font(LFFont.copy(16))
                .foregroundStyle(PrivateIslandGlass.ink)
                .tint(PrivateIslandGlass.ink)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($nameFocused)
                .onSubmit(submit)
                .padding(.horizontal, 15)
                .frame(height: 52)
                .background(PrivateIslandGlass.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(PrivateIslandGlass.ink.opacity(0.16), lineWidth: 1)
                }
                .accessibilityHint(Text("Up to 80 characters"))

            if let errorText {
                PrivateIslandFormError(text: errorText)
            }

            Button(action: submit) {
                PrivateIslandSubmitLabel(
                    title: "Create island",
                    workingTitle: "Creating…",
                    isWorking: isSubmitting
                )
            }
            .buttonStyle(LFPressableButtonStyle())
            .disabled(cleanName.isEmpty || isSubmitting)
        }
        .onAppear { nameFocused = true }
    }

    private func submit() {
        guard !cleanName.isEmpty, !isSubmitting else { return }
        let submittedName = String(cleanName.prefix(80))
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let room = try await onCreate(submittedName)
                Haptics.success()
                dismiss()
                Task { @MainActor in
                    // Wait until the form sheet has fully left UIKit before
                    // presenting the full-screen island world.
                    try? await Task.sleep(for: .milliseconds(260))
                    onCreated(room)
                }
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
                Haptics.error()
                UIAccessibility.post(notification: .announcement, argument: error.localizedDescription)
            }
        }
    }
}

private struct PrivateIslandJoinSheet: View {
    let onJoin: (String) async throws -> PrivateIslandRoom
    let onJoined: (PrivateIslandRoom) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var codeFocused: Bool
    @State private var code = ""
    @State private var isSubmitting = false
    @State private var errorText: String?

    var body: some View {
        PrivateIslandFormScaffold(
            symbol: "key.horizontal.fill",
            eyebrow: "ISLAND INVITE",
            title: "Enter an invite code",
            message: "Your boat will take you to the host's island when you choose to visit.",
            onClose: { dismiss() }
        ) {
            TextField("Six-character code", text: $code)
                .font(LFFont.number(23))
                .tracking(4)
                .monospacedDigit()
                .foregroundStyle(PrivateIslandGlass.ink)
                .tint(PrivateIslandGlass.ink)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textContentType(.oneTimeCode)
                .submitLabel(.go)
                .focused($codeFocused)
                .onSubmit(submit)
                .onChange(of: code) { _, value in
                    let normalized = value
                        .uppercased()
                        .filter { $0.isLetter || $0.isNumber }
                    code = String(normalized.prefix(6))
                    if errorText != nil { errorText = nil }
                }
                .multilineTextAlignment(.center)
                .frame(height: 56)
                .background(PrivateIslandGlass.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(PrivateIslandGlass.ink.opacity(0.16), lineWidth: 1)
                }
                .accessibilityLabel(Text("Invite code"))
                .accessibilityValue(Text(verbatim: code))

            if let errorText {
                PrivateIslandFormError(text: errorText)
            }

            Button(action: submit) {
                PrivateIslandSubmitLabel(
                    title: "Add island",
                    workingTitle: "Joining…",
                    isWorking: isSubmitting
                )
            }
            .buttonStyle(LFPressableButtonStyle())
            .disabled(code.count != 6 || isSubmitting)
        }
        .onAppear { codeFocused = true }
    }

    private func submit() {
        guard code.count == 6, !isSubmitting else { return }
        let submittedCode = code
        isSubmitting = true
        errorText = nil
        Task { @MainActor in
            do {
                let room = try await onJoin(submittedCode)
                Haptics.success()
                dismiss()
                Task { @MainActor in
                    // Let the form sheet leave UIKit's presentation hierarchy
                    // before the parent attaches a full-screen SceneKit world.
                    try? await Task.sleep(for: .milliseconds(260))
                    onJoined(room)
                }
            } catch {
                errorText = error.localizedDescription
                isSubmitting = false
                Haptics.error()
                UIAccessibility.post(notification: .announcement, argument: error.localizedDescription)
            }
        }
    }
}

private struct PrivateIslandFormScaffold<Content: View>: View {
    let symbol: String
    let eyebrow: LocalizedStringKey
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let onClose: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(PrivateIslandGlass.ink)
                        .frame(width: 44, height: 44)
                        .background(PrivateIslandGlass.ink.opacity(0.07), in: Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(eyebrow)
                            .font(LFFont.label(9))
                            .tracking(1.3)
                            .foregroundStyle(PrivateIslandGlass.ink.opacity(0.5))
                        Text(title)
                            .font(LFFont.copy(21))
                            .foregroundStyle(PrivateIslandGlass.ink)
                    }

                    Spacer(minLength: 5)

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(PrivateIslandGlass.ink)
                            .frame(width: 44, height: 44)
                            .background(PrivateIslandGlass.ink.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(Text("Close"))
                }

                Text(message)
                    .font(LFFont.label(13))
                    .foregroundStyle(PrivateIslandGlass.ink.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)

                content
            }
            .padding(horizontalSizeClass == .regular ? 26 : 20)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.clear)
        .privateIslandGlass(cornerRadius: 28, opacity: 0.9)
        .padding(horizontalSizeClass == .regular ? 24 : 10)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.clear)
        .preferredColorScheme(.light)
    }
}

private struct PrivateIslandFormError: View {
    let text: String

    var body: some View {
        Label {
            Text(verbatim: text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
        }
        .font(LFFont.label(12))
        .foregroundStyle(LFColor.deepRust)
        .accessibilityElement(children: .combine)
    }
}

private struct PrivateIslandSubmitLabel: View {
    let title: LocalizedStringKey
    let workingTitle: LocalizedStringKey
    let isWorking: Bool

    var body: some View {
        HStack(spacing: 9) {
            if isWorking {
                ProgressView()
                    .tint(.white)
                    .controlSize(.small)
            }
            Text(isWorking ? workingTitle : title)
        }
        .font(LFFont.copy(15))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(
            PrivateIslandGlass.ink.opacity(isWorking ? 0.72 : 1),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

// MARK: - In-island chat dock

/// Compact chat designed to be installed with `safeAreaInset(edge: .bottom)`
/// over the live Home Island scene. It never owns a network listener; the visit
/// coordinator supplies messages and the send/report/block actions.
struct PrivateIslandChatDock: View {
    let islandName: String
    let messages: [PrivateIslandChatMessage]
    let currentUserID: String
    var isConnected = true
    var unreadCount = 0
    var initialExpanded = false
    var onSend: (String) async throws -> Void
    var onReport: ((PrivateIslandChatMessage) -> Void)?
    var onBlock: ((PrivateIslandChatMessage) -> Void)?
    var onExpandedChanged: (Bool) -> Void = { _ in }
    var onInputFocusChanged: (Bool) -> Void = { _ in }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isExpanded: Bool
    @State private var draft = ""
    @State private var isSending = false
    @State private var sendError: String?
    @FocusState private var inputFocused: Bool

    init(
        islandName: String,
        messages: [PrivateIslandChatMessage],
        currentUserID: String,
        isConnected: Bool = true,
        unreadCount: Int = 0,
        initialExpanded: Bool = false,
        onSend: @escaping (String) async throws -> Void,
        onReport: ((PrivateIslandChatMessage) -> Void)? = nil,
        onBlock: ((PrivateIslandChatMessage) -> Void)? = nil,
        onExpandedChanged: @escaping (Bool) -> Void = { _ in },
        onInputFocusChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.islandName = islandName
        self.messages = messages
        self.currentUserID = currentUserID
        self.isConnected = isConnected
        self.unreadCount = unreadCount
        self.initialExpanded = initialExpanded
        self.onSend = onSend
        self.onReport = onReport
        self.onBlock = onBlock
        self.onExpandedChanged = onExpandedChanged
        self.onInputFocusChanged = onInputFocusChanged
        _isExpanded = State(initialValue: initialExpanded)
    }

    private var cleanDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            dockHeader

            if isExpanded {
                Divider()
                    .overlay(PrivateIslandGlass.ink.opacity(0.08))
                    .padding(.horizontal, 12)

                messageList

                if let sendError {
                    Text(verbatim: sendError)
                        .font(LFFont.label(10))
                        .foregroundStyle(LFColor.deepRust)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.top, 5)
                }

                inputBar
            }
        }
        .frame(maxWidth: dockWidth)
        .frame(height: isExpanded ? expandedHeight : 52, alignment: .bottom)
        .privateIslandGlass(cornerRadius: isExpanded ? 22 : 18, opacity: 0.86)
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: dockAlignment)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isExpanded)
        .onChange(of: inputFocused) { _, focused in
            onInputFocusChanged(focused)
        }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded { inputFocused = false }
            onExpandedChanged(expanded)
        }
    }

    private var dockHeader: some View {
        Button {
            isExpanded.toggle()
            Haptics.tap(.light)
        } label: {
            HStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PrivateIslandGlass.ink)
                        .frame(width: 34, height: 34)
                        .background(PrivateIslandGlass.ink.opacity(0.07), in: Circle())

                    if unreadCount > 0, !isExpanded {
                        Text(verbatim: "\(min(unreadCount, 99))")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(LFColor.returnOrange, in: Capsule())
                            .offset(x: 4, y: -3)
                    }
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Island chat")
                            .font(LFFont.copy(13))
                            .foregroundStyle(PrivateIslandGlass.ink)
                        Circle()
                            .fill(isConnected ? LFColor.seaGreen : PrivateIslandGlass.ink.opacity(0.24))
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }

                    Text(verbatim: collapsedDetail)
                        .font(LFFont.label(10))
                        .foregroundStyle(PrivateIslandGlass.ink.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PrivateIslandGlass.ink.opacity(0.5))
                    .frame(width: 32, height: 32)
            }
            .padding(.horizontal, 9)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(isExpanded ? "Close chat" : "Open chat"))
        .accessibilityValue(Text(isConnected ? "Connected" : "Reconnecting"))
        .accessibilityHint(
            unreadCount > 0 && !isExpanded
                ? Text("\(unreadCount) unread messages")
                : Text(verbatim: islandName)
        )
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if messages.isEmpty {
                        Text("Say hello to everyone on the island.")
                            .font(LFFont.label(12))
                        .foregroundStyle(PrivateIslandGlass.ink.opacity(0.43))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 26)
                    } else {
                        ForEach(messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onAppear { scrollToLatest(proxy, animated: false) }
            .onChange(of: messages.last?.id) { _, _ in
                scrollToLatest(proxy, animated: true)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func messageRow(_ message: PrivateIslandChatMessage) -> some View {
        let mine = message.senderID == currentUserID
        return HStack(alignment: .bottom, spacing: 7) {
            if mine { Spacer(minLength: 46) }

            if !mine {
                Text(verbatim: senderInitial(message.senderName))
                    .font(LFFont.copy(10))
                    .foregroundStyle(PrivateIslandGlass.ink)
                    .frame(width: 26, height: 26)
                    .background(PrivateIslandGlass.ink.opacity(0.07), in: Circle())
                    .accessibilityHidden(true)
            }

            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                if !mine {
                    Text(verbatim: message.senderName)
                        .font(LFFont.label(9))
                        .foregroundStyle(PrivateIslandGlass.ink.opacity(0.48))
                        .lineLimit(1)
                }

                Text(verbatim: message.text)
                    .font(LFFont.label(14))
                    .foregroundStyle(mine ? Color.white : PrivateIslandGlass.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        mine ? PrivateIslandGlass.ink : PrivateIslandGlass.ink.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                    .textSelection(.enabled)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.text
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }

                        if !mine, let onReport {
                            Button {
                                onReport(message)
                            } label: {
                                Label("Report", systemImage: "flag")
                            }
                        }

                        if !mine, let onBlock {
                            Button(role: .destructive) {
                                onBlock(message)
                            } label: {
                                Label("Block this sailor", systemImage: "hand.raised")
                            }
                        }
                    }

                Text(message.createdAt, style: .time)
                    .font(LFFont.label(8))
                    .foregroundStyle(PrivateIslandGlass.ink.opacity(0.35))
            }

            if !mine { Spacer(minLength: 46) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text(verbatim: "\(mine ? LF.text("You") : message.senderName): \(message.text)")
        )
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $draft, axis: .vertical)
                .font(LFFont.label(14))
                .foregroundStyle(PrivateIslandGlass.ink)
                .tint(PrivateIslandGlass.ink)
                .lineLimit(1...4)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit(send)
                .onChange(of: draft) { _, value in
                    if value.count > 500 { draft = String(value.prefix(500)) }
                    if sendError != nil { sendError = nil }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(PrivateIslandGlass.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(PrivateIslandGlass.ink.opacity(0.13), lineWidth: 1)
                }
                .accessibilityLabel(Text("Chat message"))
                .accessibilityHint(Text("Up to 500 characters"))

            Button(action: send) {
                ZStack {
                    Circle()
                        .fill(
                            cleanDraft.isEmpty || isSending || !isConnected
                                ? PrivateIslandGlass.ink.opacity(0.25)
                                : PrivateIslandGlass.ink
                        )
                    if isSending {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 42, height: 42)
            }
            .buttonStyle(LFPressableButtonStyle())
            .disabled(cleanDraft.isEmpty || isSending || !isConnected)
            .accessibilityLabel(Text(isSending ? "Sending…" : "Send"))
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 10)
    }

    private func send() {
        let message = String(cleanDraft.prefix(500))
        guard !message.isEmpty, !isSending, isConnected else { return }
        isSending = true
        sendError = nil
        Task { @MainActor in
            do {
                try await onSend(message)
                draft = ""
                isSending = false
                inputFocused = true
                Haptics.tap(.light)
            } catch {
                sendError = error.localizedDescription
                isSending = false
                Haptics.error()
                UIAccessibility.post(notification: .announcement, argument: error.localizedDescription)
            }
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let id = messages.last?.id else { return }
        let action = { proxy.scrollTo(id, anchor: .bottom) }
        if animated, !reduceMotion {
            withAnimation(.easeOut(duration: 0.2), action)
        } else {
            action()
        }
    }

    private func senderInitial(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first.map(String.init) ?? "•"
    }

    private var collapsedDetail: String {
        if !isConnected { return LF.text("Reconnecting…") }
        if let latest = messages.last {
            let prefix = latest.senderID == currentUserID ? LF.text("You") : latest.senderName
            return "\(prefix): \(latest.text)"
        }
        return islandName
    }

    private var dockWidth: CGFloat {
        horizontalSizeClass == .regular ? 520 : .infinity
    }

    private var expandedHeight: CGFloat {
        if dynamicTypeSize.isAccessibilitySize { return 390 }
        if verticalSizeClass == .compact { return 250 }
        return horizontalSizeClass == .regular ? 360 : 300
    }

    private var dockAlignment: Alignment {
        horizontalSizeClass == .regular ? .bottomTrailing : .bottom
    }
}

// MARK: - Glass language

private enum PrivateIslandGlass {
    static let ink = Color(uiColor: VoyageSceneKit.nightBG)
}

private struct PrivateIslandGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(reduceTransparency ? 0 : 1)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white)
                        .opacity(reduceTransparency ? 1 : 0)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(reduceTransparency ? 0.96 : opacity))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(PrivateIslandGlass.ink.opacity(0.12), lineWidth: 1)
            }
    }
}

private extension View {
    func privateIslandGlass(
        cornerRadius: CGFloat,
        opacity: Double = 0.82
    ) -> some View {
        modifier(
            PrivateIslandGlassModifier(
                cornerRadius: cornerRadius,
                opacity: opacity
            )
        )
    }
}
