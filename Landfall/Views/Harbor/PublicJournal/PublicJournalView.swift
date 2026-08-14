import SwiftUI

private enum PublicJournalTodayState {
    case loading
    case loaded(PublicJournalEntry?)
    case failed
}

/// 公式港を横断して、一日一頁だけが静かに届く公開フィード。
struct PublicJournalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var auth: AuthService
    @StateObject private var journal = PublicJournalService.shared
    @StateObject private var harborService = PublicHarborService.shared
    @StateObject private var chat = HarborChatService.shared

    @State private var entries: [PublicJournalEntry] = []
    @State private var todayState: PublicJournalTodayState = .loading
    @State private var selectedHarborSlug: String?
    @State private var loading = false
    @State private var loadError: String?
    @State private var feedRequestID = UUID()
    @State private var todayRequestID = UUID()
    @State private var selectedEntry: PublicJournalEntry?
    @State private var composerEntry: PublicJournalEntry?
    @State private var showingComposer = false

    private var visibleEntries: [PublicJournalEntry] {
        entries.filter { !chat.blocked.contains($0.authorID) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HarborOceanBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        masthead
                        todayDock
                            .padding(.top, 24)
                        filterRow
                            .padding(.top, 28)
                        feed
                            .padding(.top, 18)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 56)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await reload() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Harbor", systemImage: "chevron.left")
                            .font(LFFont.label(16))
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .sheet(item: $selectedEntry, onDismiss: presentPendingComposer) { entry in
            PublicJournalDetailView(
                entry: entry,
                onEdit: { beginEditing(entry) },
                onChanged: { Task { await reload() } }
            )
        }
        .sheet(isPresented: $showingComposer, onDismiss: {
            composerEntry = nil
            Task { await reload() }
        }) {
            PublicJournalComposer(existingEntry: composerEntry) {
                Task { await reload() }
            }
        }
        .task { await reload() }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardKicker(text: "PUBLIC LOGBOOK", color: LFColor.ink)
            Text("One page per tide")
                .font(LFFont.copy(31))
                .foregroundStyle(LFColor.ink)
            Text("One photo a day, paired with the words worth carrying onward.")
                .font(LFFont.copy(16))
                .foregroundStyle(LFColor.ink.opacity(0.72))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Label("A new public-page day begins at midnight in Japan.", systemImage: "clock")
                .font(LFFont.label(13))
                .foregroundStyle(LFColor.ink.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var todayDock: some View {
        if !auth.isSignedIn {
            statusDock(
                icon: "person.crop.circle.badge.exclamationmark",
                title: "Sign in to open the public logbook",
                detail: "Public pages are shared with signed-in sailors."
            )
        } else {
            switch todayState {
            case .loading:
                todayLoadingDock
            case .failed:
                todayErrorDock
            case let .loaded(todayEntry):
                if let todayEntry {
                    publishedTodayDock(todayEntry)
                } else if harborService.joined.isEmpty {
                    statusDock(
                        icon: "sailboat",
                        title: "Choose a public harbor first",
                        detail: "Join one of the five harbors, then return to send today's page."
                    )
                } else {
                    writeTodayDock
                }
            }
        }
    }

    private func publishedTodayDock(_ todayEntry: PublicJournalEntry) -> some View {
        Button {
            selectedEntry = todayEntry
        } label: {
            HStack(spacing: 15) {
                PublicJournalPhoto(data: todayEntry.imageData)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Label("Today's page is public", systemImage: "checkmark.circle.fill")
                        .font(LFFont.copy(16))
                        .foregroundStyle(LFColor.inkFixed)
                        .lineLimit(2)
                    Text("Open, edit, or share it")
                        .font(LFFont.label(12))
                        .foregroundStyle(LFColor.inkFixed.opacity(0.68))
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(LFColor.inkFixed.opacity(0.58))
            }
            .padding(14)
            .background(Color(hex: 0xFCFAF5))
            .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous)
                    .stroke(LFColor.seaGreen.opacity(0.8), lineWidth: 1)
            }
        }
        .buttonStyle(LFPressableButtonStyle())
    }

    private var writeTodayDock: some View {
        Button {
            composerEntry = nil
            showingComposer = true
        } label: {
            HStack(spacing: 15) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(LFColor.deepRust)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Color(hex: 0xFCFAF5))
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Write today's page")
                        .font(LFFont.copy(18))
                        .foregroundStyle(LFColor.inkFixed)
                    Text("One photo and one passage")
                        .font(LFFont.label(12))
                        .foregroundStyle(LFColor.inkFixed.opacity(0.68))
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(LFColor.inkFixed.opacity(0.58))
            }
            .padding(17)
            .background(Color(hex: 0xFCFAF5))
            .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous)
                    .stroke(LFColor.returnOrange.opacity(0.8), lineWidth: 1)
            }
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityHint(Text("Opens the editor for today's only public page"))
    }

    private var todayLoadingDock: some View {
        HStack(alignment: .top, spacing: 14) {
            ProgressView()
                .tint(LFColor.deepRust)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 5) {
                Text("Checking today's page…")
                    .font(LFFont.copy(16))
                    .foregroundStyle(LFColor.inkFixed)
                Text("Confirming whether today's page is already public.")
                    .font(LFFont.label(13))
                    .foregroundStyle(LFColor.inkFixed.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(17)
        .background(Color(hex: 0xFCFAF5))
        .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
    }

    private var todayErrorDock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Today's page could not be checked.", systemImage: "exclamationmark.triangle")
                .font(LFFont.copy(16))
                .foregroundStyle(LFColor.inkFixed)
            Text("Try again before writing so an existing page stays safe.")
                .font(LFFont.label(13))
                .foregroundStyle(LFColor.inkFixed.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await reloadToday() }
            } label: {
                Text("Try again")
                    .font(LFFont.copy(15))
                    .foregroundStyle(Color(hex: 0xFCFAF5))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(minHeight: 44)
                    .background(LFColor.inkFixed)
                    .clipShape(Capsule())
            }
            .buttonStyle(LFPressableButtonStyle())
        }
        .padding(17)
        .background(Color(hex: 0xFCFAF5))
        .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
    }

    private func statusDock(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(LFColor.returnOrange)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(LFFont.copy(16))
                    .foregroundStyle(LFColor.inkFixed)
                Text(detail)
                    .font(LFFont.label(13))
                    .foregroundStyle(LFColor.inkFixed.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(17)
        .background(Color(hex: 0xFCFAF5))
        .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                filterChip(title: "Everyone", slug: nil)
                ForEach(PublicHarbor.all) { harbor in
                    filterChip(title: harbor.title, slug: harbor.slug)
                }
            }
        }
        .accessibilityLabel(Text("Filter public pages"))
    }

    private func filterChip(title: LocalizedStringKey, slug: String?) -> some View {
        let selected = selectedHarborSlug == slug
        return Button {
            guard selectedHarborSlug != slug else { return }
            Haptics.tap()
            selectedHarborSlug = slug
            entries = []
            loadError = nil
            Task { await reloadFeed(for: slug) }
        } label: {
            Text(title)
                .font(LFFont.label(13))
                .foregroundStyle(selected ? Color(hex: 0xFCFAF5) : LFColor.ink)
                .padding(.horizontal, 15)
                .frame(minHeight: 44)
                .background(selected ? LFColor.ink : LFColor.paper.opacity(0.48))
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(LFColor.ink.opacity(selected ? 0 : 0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var feed: some View {
        if !auth.isSignedIn {
            EmptyView()
        } else if loading && entries.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(LFColor.returnOrange)
                Text("Opening the latest pages…")
                    .font(LFFont.label(13))
                    .foregroundStyle(LFColor.ink.opacity(0.72))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 70)
        } else if let loadError, entries.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(LFColor.returnOrange)
                Text(verbatim: loadError)
                    .font(LFFont.copy(15))
                    .foregroundStyle(LFColor.ink.opacity(0.72))
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await reloadFeed(for: selectedHarborSlug) } }
                    .font(LFFont.copy(15))
                    .foregroundStyle(LFColor.ink)
                    .frame(minHeight: 44)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 54)
        } else if visibleEntries.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "book.closed")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(LFColor.returnOrange)
                Text("No pages have reached this tide yet")
                    .font(LFFont.copy(17))
                    .foregroundStyle(LFColor.ink)
                Text("The first page can be quiet. A photo and a few honest words are enough.")
                    .font(LFFont.label(13))
                    .foregroundStyle(LFColor.ink.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 26)
            .padding(.vertical, 58)
            .background(LFColor.paper.opacity(0.34))
            .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 16) {
                if let loadError {
                    staleFeedNotice(loadError)
                }

                HStack(alignment: .lastTextBaseline) {
                    Text("Latest pages")
                        .font(LFFont.copy(20))
                        .foregroundStyle(LFColor.ink)
                    Spacer()
                    if loading {
                        ProgressView()
                            .tint(LFColor.returnOrange)
                    }
                }

                ForEach(visibleEntries) { entry in
                    Button {
                        selectedEntry = entry
                    } label: {
                        PublicJournalPageCard(entry: entry)
                    }
                    .buttonStyle(LFPressableButtonStyle(scale: 0.985))
                    .accessibilityHint(Text("Opens sharing and page actions"))
                }
            }
        }
    }

    private func staleFeedNotice(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: message)
                .font(LFFont.copy(14))
                .foregroundStyle(LFColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Showing the last loaded pages.")
                .font(LFFont.label(13))
                .foregroundStyle(LFColor.ink.opacity(0.72))
            Button("Try again") {
                Task { await reloadFeed(for: selectedHarborSlug) }
            }
            .font(LFFont.copy(14))
            .foregroundStyle(LFColor.ink)
            .frame(minHeight: 44)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LFColor.paper.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func beginEditing(_ entry: PublicJournalEntry) {
        guard entry.dayID == PublicJournalService.dayID(Date()) else { return }
        composerEntry = entry
        selectedEntry = nil
    }

    private func presentPendingComposer() {
        guard composerEntry != nil else { return }
        showingComposer = true
    }

    private func reload() async {
        guard auth.isSignedIn else {
            feedRequestID = UUID()
            todayRequestID = UUID()
            entries = []
            todayState = .loaded(nil)
            loadError = nil
            loading = false
            return
        }
        await harborService.refresh()
        await chat.loadBlocked()
        async let today: Void = reloadToday()
        async let feed: Void = reloadFeed(for: selectedHarborSlug)
        _ = await (today, feed)
    }

    private func reloadToday() async {
        let requestID = UUID()
        todayRequestID = requestID
        todayState = .loading
        do {
            let entry = try await journal.entryForToday()
            guard todayRequestID == requestID else { return }
            todayState = .loaded(entry)
        } catch {
            guard todayRequestID == requestID else { return }
            todayState = .failed
        }
    }

    private func reloadFeed(for harborSlug: String?) async {
        guard auth.isSignedIn else { return }
        let requestID = UUID()
        feedRequestID = requestID
        loading = true
        loadError = nil
        defer {
            if feedRequestID == requestID {
                loading = false
            }
        }
        do {
            let fetched = try await journal.latestEntries(
                harborSlug: harborSlug,
                limit: 18
            )
            guard feedRequestID == requestID,
                  selectedHarborSlug == harborSlug
            else { return }
            if reduceMotion {
                entries = fetched
            } else {
                withAnimation(.easeOut(duration: 0.28)) { entries = fetched }
            }
            loadError = nil
        } catch {
            guard feedRequestID == requestID,
                  selectedHarborSlug == harborSlug
            else { return }
            loadError = LF.text("The public logbook could not be refreshed.")
        }
    }
}

private struct PublicJournalDetailView: View {
    enum PendingAction: String, Identifiable {
        case delete, report, block
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .delete: "Delete this page?"
            case .report: "Report this page?"
            case .block: "Block this sailor?"
            }
        }

        var message: LocalizedStringKey {
            switch self {
            case .delete: "The photo and text will disappear from the public logbook."
            case .report: "This sends the page to the operations crew for review."
            case .block: "Their public pages, harbor profile, and messages will disappear for you. They won't be told."
            }
        }
    }

    let entry: PublicJournalEntry
    let onEdit: () -> Void
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthService
    @StateObject private var journal = PublicJournalService.shared
    @StateObject private var chat = HarborChatService.shared
    @State private var shareImage: WrappedCardImage?
    @State private var preparingShare = true
    @State private var sharePreparationFailed = false
    @State private var pendingAction: PendingAction?
    @State private var working = false
    @State private var statusMessage: String?
    @State private var showingBlockResult = false
    @State private var blockUndoError: String?

    private var isMine: Bool { entry.authorID == auth.user?.uid }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    PublicJournalPageCard(entry: entry)

                    shareButton

                    if isMine && isToday {
                        Button {
                            onEdit()
                        } label: {
                            Label("Edit today's page", systemImage: "pencil")
                                .font(LFFont.copy(16))
                                .foregroundStyle(LFColor.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .frame(minHeight: 54)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(LFColor.ink, lineWidth: 1)
                                }
                        }
                        .buttonStyle(LFPressableButtonStyle())
                        .disabled(working)
                    } else if isMine {
                        Text("Only today's page can be edited.")
                            .font(LFFont.label(14))
                            .foregroundStyle(LFColor.ink.opacity(0.72))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(LFColor.paper.opacity(0.72))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Color(hex: 0xEEE9DE))
            .navigationTitle("Public logbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if isMine {
                            Button("Delete page", systemImage: "trash", role: .destructive) {
                                pendingAction = .delete
                            }
                        } else {
                            Button("Report page", systemImage: "exclamationmark.bubble") {
                                pendingAction = .report
                            }
                            Button("Block sailor", systemImage: "person.slash", role: .destructive) {
                                pendingAction = .block
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("Page actions"))
                    .disabled(working)
                }
            }
        }
        .preferredColorScheme(.light)
        .confirmationDialog(
            pendingAction?.title ?? "Public logbook",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingAction {
                Button(actionTitle(pendingAction), role: .destructive) {
                    perform(pendingAction)
                }
            }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        } message: {
            Text(pendingAction?.message ?? "")
        }
        .alert(
            "Public logbook",
            isPresented: Binding(
                get: { statusMessage != nil },
                set: { if !$0 { statusMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { statusMessage = nil }
        } message: {
            Text(verbatim: statusMessage ?? "")
        }
        .alert("Sailor blocked", isPresented: $showingBlockResult) {
            Button("Undo") { undoBlock() }
            Button("Close", role: .cancel) { dismiss() }
        } message: {
            Text(verbatim: blockResultMessage)
        }
        .task {
            guard shareImage == nil else { return }
            prepareShareImage()
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if let shareImage {
            ShareLink(item: shareImage, preview: SharePreview(shareImage.fileName)) {
                Label("Share this page", systemImage: "square.and.arrow.up")
                    .font(LFFont.copy(17))
                    .foregroundStyle(LFColor.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .frame(minHeight: 58)
                    .background(LFColor.ink)
                    .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
            }
            .simultaneousGesture(TapGesture().onEnded { Haptics.success() })
            .disabled(working)
        } else if sharePreparationFailed {
            Button {
                prepareShareImage()
            } label: {
                Label("Try preparing the share page again", systemImage: "arrow.clockwise")
                    .font(LFFont.copy(16))
                    .foregroundStyle(LFColor.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(minHeight: 58)
                    .overlay {
                        RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous)
                            .stroke(LFColor.ink, lineWidth: 1)
                    }
            }
            .buttonStyle(LFPressableButtonStyle())
        } else {
            HStack(spacing: 10) {
                if preparingShare {
                    ProgressView()
                        .tint(LFColor.paper)
                }
                Text("Preparing the share page…")
            }
            .font(LFFont.copy(17))
            .foregroundStyle(LFColor.paper)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(minHeight: 58)
            .background(LFColor.ink.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
        }
    }

    private var isToday: Bool {
        entry.dayID == PublicJournalService.dayID(Date())
    }

    private func prepareShareImage() {
        preparingShare = true
        sharePreparationFailed = false
        shareImage = PublicJournalShareRenderer.render(entry)
        preparingShare = false
        sharePreparationFailed = shareImage == nil
    }

    private func actionTitle(_ action: PendingAction) -> LocalizedStringKey {
        switch action {
        case .delete: "Delete page"
        case .report: "Report"
        case .block: "Block"
        }
    }

    private func perform(_ action: PendingAction) {
        pendingAction = nil
        switch action {
        case .block:
            working = true
            Task {
                do {
                    try await chat.block(entry.authorID)
                    working = false
                    blockUndoError = nil
                    Haptics.tap()
                    onChanged()
                    showingBlockResult = true
                } catch {
                    working = false
                    statusMessage = error.localizedDescription
                    Haptics.error()
                }
            }
        case .delete:
            working = true
            Task {
                do {
                    try await journal.delete(entry)
                    Haptics.success()
                    onChanged()
                    dismiss()
                } catch {
                    working = false
                    statusMessage = error.localizedDescription
                    Haptics.error()
                }
            }
        case .report:
            working = true
            Task {
                do {
                    try await journal.report(entry: entry)
                    working = false
                    statusMessage = LF.text("Report received. Thank you for helping keep the harbor safe.")
                    Haptics.success()
                } catch {
                    working = false
                    statusMessage = error.localizedDescription
                    Haptics.error()
                }
            }
        }
    }

    private var blockResultMessage: String {
        if let blockUndoError {
            return "\(blockUndoError)\n\n\(LF.text("Choose Undo to try again, or Close."))"
        }
        return LF.text("Their public pages, harbor profile, and messages are now hidden.")
    }

    private func undoBlock() {
        working = true
        Task {
            do {
                try await chat.unblock(entry.authorID)
                working = false
                blockUndoError = nil
                Haptics.success()
                onChanged()
                statusMessage = LF.text("Block undone.")
            } catch {
                working = false
                blockUndoError = error.localizedDescription
                showingBlockResult = true
                Haptics.error()
            }
        }
    }
}
