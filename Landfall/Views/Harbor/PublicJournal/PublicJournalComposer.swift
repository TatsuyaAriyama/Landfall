import PhotosUI
import SwiftUI

/// 私的な航海誌とは分離した、公開用の一頁だけを組版する画面。
struct PublicJournalComposer: View {
    let existingEntry: PublicJournalEntry?
    let intendedDayID: String
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthService
    @StateObject private var journal = PublicJournalService.shared
    @StateObject private var harborService = PublicHarborService.shared

    @State private var bodyText: String
    @State private var selectedHarborSlug: String
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var preparedPhoto: PreparedPublicJournalPhoto?
    @State private var displayPhotoData: Data?
    @State private var preparingPhoto = false
    @State private var publishing = false
    @State private var published = false
    @State private var errorMessage: String?
    @State private var isDirty = false
    @State private var showingDiscardConfirmation = false
    @FocusState private var bodyFocused: Bool
    @AccessibilityFocusState private var successFocused: Bool

    init(existingEntry: PublicJournalEntry? = nil, onSaved: @escaping () -> Void) {
        self.existingEntry = existingEntry
        self.intendedDayID = existingEntry?.dayID ?? PublicJournalService.dayID(Date())
        self.onSaved = onSaved
        _bodyText = State(initialValue: existingEntry?.body ?? "")
        _selectedHarborSlug = State(initialValue: existingEntry?.harborSlug ?? "")
        _preparedPhoto = State(initialValue: existingEntry.map {
            PreparedPublicJournalPhoto(
                data: $0.imageData,
                width: $0.imageWidth,
                height: $0.imageHeight
            )
        })
        _displayPhotoData = State(initialValue: existingEntry?.imageData)
    }

    private var joinedHarbors: [PublicHarbor] {
        PublicHarbor.all.filter { harborService.joined.contains($0.slug) }
    }

    private var canPublish: Bool {
        auth.isSignedIn &&
        !publishing &&
        !published &&
        !preparingPhoto &&
        preparedPhoto != nil &&
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        harborService.joined.contains(selectedHarborSlug)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: 0xEEE9DE).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        intro
                        journalPage
                        harborPicker
                        privacyNotice
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
                    .padding(.bottom, 124)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .allowsHitTesting(!published)
                .accessibilityHidden(published)

                if published {
                    Color.black.opacity(0.16)
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                    publishSuccess
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .navigationTitle(existingEntry == nil ? "Today's page" : "Edit today's page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { requestDismiss() }
                        .disabled(publishing || published)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !published {
                    publishBar
                }
            }
        }
        .preferredColorScheme(.light)
        .interactiveDismissDisabled(publishing || isDirty || published)
        .alert(
            "The page could not be published.",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
        .confirmationDialog(
            "Discard your changes?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Your photo and words on this screen will be lost.")
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .task {
            await harborService.refresh()
            if selectedHarborSlug.isEmpty {
                selectedHarborSlug = joinedHarbors.first?.slug ?? ""
            }
        }
        .onChange(of: published) { _, value in
            guard value else { return }
            successFocused = true
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardKicker(text: "PUBLIC LOGBOOK", color: LFColor.inkFixed)
            Text("One page per tide")
                .font(LFFont.copy(28))
                .foregroundStyle(LFColor.inkFixed)
            Text("Pair one scene from today with the words you want to keep.")
                .font(LFFont.label(15))
                .foregroundStyle(LFColor.inkFixed.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var journalPage: some View {
        VStack(spacing: 0) {
            composerMasthead
                .padding(20)

            photoStage

            VStack(alignment: .leading, spacing: 16) {
                PublicJournalTideRule()

                ZStack(alignment: .topLeading) {
                    if bodyText.isEmpty {
                        Text("What stayed with you today?")
                            .font(LFFont.copy(17))
                            .foregroundStyle(LFColor.inkFixed.opacity(0.62))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    TextEditor(text: $bodyText)
                        .font(LFFont.copy(17))
                        .foregroundStyle(LFColor.inkFixed)
                        .lineSpacing(5)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 150)
                        .focused($bodyFocused)
                        .accessibilityLabel(Text("Page text"))
                }

                HStack {
                    Text("The private logbook is never copied automatically.")
                        .font(LFFont.label(11))
                        .foregroundStyle(LFColor.inkFixed.opacity(0.68))
                    Spacer(minLength: 8)
                    Text(verbatim: "\(bodyText.count)/\(PublicJournalService.bodyLimit)")
                        .font(LFFont.number(11))
                        .foregroundStyle(LFColor.inkFixed.opacity(0.68))
                        .accessibilityLabel(Text("Page length"))
                        .accessibilityValue(
                            Text("\(bodyText.count) of \(PublicJournalService.bodyLimit) characters")
                        )
                }
            }
            .padding(20)
        }
        .background(Color(hex: 0xFCFAF5))
        .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous)
                .stroke(LFColor.inkFixed.opacity(0.12), lineWidth: 1)
        }
        .onChange(of: bodyText) { _, value in
            isDirty = true
            if value.count > PublicJournalService.bodyLimit {
                bodyText = String(value.prefix(PublicJournalService.bodyLimit))
            }
        }
    }

    private var composerMasthead: some View {
        HStack(spacing: 12) {
            PlayerAvatarArt(
                styleToken: existingEntry?.styleToken ?? PlayerProfile.styleToken,
                symbolToken: existingEntry?.symbolToken ?? PlayerProfile.symbolToken
            )
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: authorName)
                    .font(LFFont.copy(16))
                    .foregroundStyle(LFColor.inkFixed)
                    .lineLimit(1)
                Text(verbatim: PublicJournalDayDisplay.fullDate(
                    for: intendedDayID
                ))
                    .font(LFFont.label(12))
                    .foregroundStyle(LFColor.inkFixed.opacity(0.68))
            }

            Spacer()

            Image(systemName: "book.pages")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(LFColor.returnOrange)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var photoStage: some View {
        ZStack {
            Color(hex: 0xE4DED2)

            if let data = displayPhotoData {
                PublicJournalPhoto(data: data)
                    .transition(.opacity)
            } else {
                VStack(spacing: 11) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 29, weight: .regular))
                    Text("Add today's scene")
                        .font(LFFont.copy(16))
                }
                .foregroundStyle(LFColor.inkFixed.opacity(0.68))
            }

            if preparingPhoto {
                ZStack {
                    Color(hex: 0xFCFAF5).opacity(0.82)
                    VStack(spacing: 10) {
                        ProgressView()
                            .tint(LFColor.returnOrange)
                        Text("Preparing the photo…")
                            .font(LFFont.label(13))
                            .foregroundStyle(LFColor.inkFixed.opacity(0.72))
                    }
                }
            }

            if !preparingPhoto {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label(
                                displayPhotoData == nil ? "Choose a photo" : "Choose another",
                                systemImage: "photo.badge.plus"
                            )
                            .font(LFFont.copy(13))
                            .foregroundStyle(LFColor.inkFixed)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(Color(hex: 0xFCFAF5))
                            .clipShape(Capsule())
                        }
                        .accessibilityHint(Text("Opens the photo library"))
                    }
                    .padding(14)
                }
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipped()
        .animation(.easeOut(duration: 0.18), value: displayPhotoData)
    }

    @ViewBuilder
    private var harborPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Send this page from")
                .font(LFFont.label(13))
                .foregroundStyle(LFColor.inkFixed.opacity(0.68))

            if joinedHarbors.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sailboat")
                        .foregroundStyle(LFColor.returnOrange)
                    Text("Join one of the public harbors before sending a page.")
                        .font(LFFont.copy(15))
                        .foregroundStyle(LFColor.inkFixed.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(17)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0xFCFAF5))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Menu {
                    ForEach(joinedHarbors) { harbor in
                        Button {
                            guard selectedHarborSlug != harbor.slug else { return }
                            selectedHarborSlug = harbor.slug
                            isDirty = true
                        } label: {
                            if harbor.slug == selectedHarborSlug {
                                Label(harbor.title, systemImage: "checkmark")
                            } else {
                                Text(harbor.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        if let harbor = PublicHarbor.by(slug: selectedHarborSlug) {
                            TileSymbolView(
                                symbol: harbor.symbol,
                                fg: harbor.style.foreground,
                                bg: harbor.style.background
                            )
                            .frame(width: 30, height: 30)
                            Text(harbor.title)
                                .font(LFFont.copy(16))
                                .foregroundStyle(LFColor.inkFixed)
                        } else {
                            Text("Choose a harbor")
                                .font(LFFont.copy(16))
                                .foregroundStyle(LFColor.inkFixed)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(LFColor.inkFixed.opacity(0.58))
                    }
                    .padding(.horizontal, 17)
                    .frame(minHeight: 58)
                    .background(Color(hex: 0xFCFAF5))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .accessibilityLabel(Text("Public harbor"))
            }
        }
    }

    private var privacyNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "This page will be visible to signed-in people who open the public logbook.",
                systemImage: "eye"
            )
            Label(
                "A new public-page day begins at midnight in Japan.",
                systemImage: "clock"
            )
            Label(
                "Share only photos you have the right to use and that are appropriate for everyone.",
                systemImage: "checkmark.shield"
            )
        }
        .font(LFFont.label(12))
        .foregroundStyle(LFColor.inkFixed.opacity(0.68))
        .fixedSize(horizontal: false, vertical: true)
    }

    private var publishBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(LFColor.inkFixed.opacity(0.08))
                .frame(height: 1)
            Button {
                Task { await publish() }
            } label: {
                HStack(spacing: 9) {
                    if publishing {
                        ProgressView()
                            .tint(Color(hex: 0xFCFAF5))
                    } else {
                        Image(systemName: existingEntry == nil ? "paperplane" : "checkmark")
                    }
                    Text(publishing ? "Sending to the logbook…" : publishButtonTitle)
                }
                .font(LFFont.copy(17))
                .foregroundStyle(Color(hex: 0xFCFAF5))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(minHeight: 58)
                .background(canPublish ? LFColor.inkFixed : LFColor.inkFixed.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
            }
            .buttonStyle(LFPressableButtonStyle())
            .disabled(!canPublish)
            .accessibilityHint(Text("Publishes one photo and this text as today's public page"))
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Color(hex: 0xEEE9DE).opacity(0.98))
    }

    private var publishSuccess: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(LFColor.deepRust)
                .accessibilityHidden(true)
            Text("Today's page reached the harbor")
                .font(LFFont.copy(18))
                .foregroundStyle(LFColor.inkFixed)
                .multilineTextAlignment(.center)
                .accessibilityFocused($successFocused)
            Button("Done") { dismiss() }
                .font(LFFont.copy(17))
                .foregroundStyle(Color(hex: 0xFCFAF5))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(minHeight: 52)
                .background(LFColor.inkFixed)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .buttonStyle(LFPressableButtonStyle())
        }
        .padding(30)
        .background(Color(hex: 0xFCFAF5))
        .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous)
                .stroke(LFColor.inkFixed.opacity(0.12), lineWidth: 1)
        }
        .padding(34)
        .frame(maxWidth: 430)
        .accessibilityAddTraits(.isModal)
    }

    private var authorName: String {
        if let existingEntry { return existingEntry.displayName }
        let name = PlayerProfile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? LF.text("Sailor") : name
    }

    private var publishButtonTitle: LocalizedStringKey {
        existingEntry == nil ? "Send to the public logbook" : "Update today's page"
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        preparingPhoto = true
        bodyFocused = false
        defer { preparingPhoto = false }
        do {
            guard let sourceData = try await item.loadTransferable(type: Data.self) else {
                throw PublicJournalError.invalidPhoto
            }
            let photo = try await Task.detached(priority: .userInitiated) {
                try PublicJournalService.preparePhoto(from: sourceData)
            }.value
            withAnimation(.easeOut(duration: 0.18)) {
                preparedPhoto = photo
                displayPhotoData = photo.data
            }
            isDirty = true
        } catch {
            selectedPhotoItem = nil
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    private func publish() async {
        guard canPublish, let preparedPhoto else { return }
        publishing = true
        bodyFocused = false
        defer { publishing = false }
        do {
            _ = try await journal.publish(
                body: bodyText,
                photo: preparedPhoto,
                harborSlug: selectedHarborSlug,
                replaceExisting: existingEntry != nil,
                intendedDayID: intendedDayID
            )
            Haptics.success()
            isDirty = false
            onSaved()
            withAnimation(.easeOut(duration: 0.2)) { published = true }
        } catch PublicJournalError.alreadyPublished {
            onSaved()
            errorMessage = PublicJournalError.alreadyPublished.localizedDescription
            Haptics.error()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    private func requestDismiss() {
        if isDirty {
            bodyFocused = false
            showingDiscardConfirmation = true
        } else {
            dismiss()
        }
    }
}
