import SwiftUI
import SwiftData

/// アプリアイコンの現在値取得と切り替え。setAlternateIconName は iOS のみ。
enum AppIconStore {
    static func currentOption() -> AppIconOption {
        let name = UIApplication.shared.alternateIconName
        return AppIconOption.allCases.first { $0.alternateIconName == name } ?? .harbor
    }

    static var isSupported: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    static func select(_ option: AppIconOption, completion: @escaping (Bool) -> Void) {
        guard isSupported else { completion(false); return }
        UIApplication.shared.setAlternateIconName(option.alternateIconName) { error in
            Task { @MainActor in completion(error == nil) }
        }
    }
}

/// シート内のどこまでスクロールしても見失わない、ひとつ前の画面への入口。
/// 左右を同じ幅にして、タイトルは端末の中央に固定する。
struct LFBackHeader: View {
    let title: LocalizedStringKey
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Back")
                }
                .font(LFFont.label(15))
                .foregroundStyle(LFColor.ink.opacity(0.72))
                .frame(minWidth: 78, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)
            Text(title)
                .font(LFFont.copy(20))
                .foregroundStyle(LFColor.ink)
                .lineLimit(1)
            Spacer(minLength: 8)

            Color.clear
                .frame(width: 78, height: 44)
                .accessibilityHidden(true)
        }
    }
}

/// 設定シート。作業項目とアプリ全体の設定をまとめて扱う。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthService
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue
    @AppStorage(AppTheme.storageKey) private var appTheme = AppTheme.system.rawValue
    @Query(sort: \StudyItem.sortOrder) private var items: [StudyItem]
    @Query private var sessions: [StudySession]
    @Query private var destinations: [Destination]
    @State private var current: AppIconOption = .harbor
    @State private var addingItem = false
    @State private var editingItem: StudyItem?
    /// 削除しようとしている到達済みの島(確認ダイアログ用)。
    @State private var pendingDeleteIsland: Destination?
    @State private var confirmingDeleteAccount = false
    @State private var deletingAccount = false
    @State private var showingTutorial = false
    @State private var showingVoyagePass = false
    @State private var showingAssetStudio = false
    @StateObject private var voyagePass = VoyagePassStore.shared
    @AppStorage(NotificationService.enabledKey) private var notifyEnabled = false
    @State private var notifyTime = Calendar.current.date(
        from: DateComponents(hour: NotificationService.hour, minute: NotificationService.minute)
    ) ?? Date()

    var body: some View {
        VStack(spacing: 0) {
            LFBackHeader(title: "Settings") { dismiss() }
                .padding(.horizontal, LFMetrics.cardPadding)
                .padding(.vertical, 6)

            Rectangle()
                .fill(LFColor.ink.opacity(0.08))
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("Voyage Pass")
                        .padding(.top, 24)
                        .padding(.bottom, 12)

                    voyagePassCard

                    sectionLabel("Work items")
                        .padding(.top, 36)
                        .padding(.bottom, 8)

                    Text("Manage names, colors, symbols, and order here.")
                        .font(LFFont.copy(13))
                        .foregroundStyle(LFColor.ink.opacity(0.6))
                        .padding(.bottom, 12)

                    workItemsSection

                    sectionLabel("Language")
                        .padding(.top, 36)
                        .padding(.bottom, 18)

                    HStack(spacing: 10) {
                        ForEach(AppLanguage.allCases) { language in
                            languagePill(language)
                        }
                        Spacer(minLength: 0)
                    }

                    sectionLabel("Appearance")
                        .padding(.top, 36)
                        .padding(.bottom, 18)

                    HStack(spacing: 10) {
                        ForEach(AppTheme.allCases) { theme in
                            themePill(theme)
                        }
                        Spacer(minLength: 0)
                    }

                    notificationSection
                        .padding(.top, 36)

                    sectionLabel("Guide")
                        .padding(.top, 36)
                        .padding(.bottom, 10)

                    Button {
                        showingTutorial = true
                    } label: {
                        HStack(spacing: 13) {
                            TileSymbolView(
                                symbol: .compass,
                                fg: LFColor.harborSand,
                                bg: LFColor.harborTeal
                            )
                            .frame(width: 40, height: 40)
                            .background(LFColor.harborTeal, in: RoundedRectangle(cornerRadius: 12))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tutorial")
                                    .font(LFFont.copy(16))
                                    .foregroundStyle(LFColor.ink)
                                Text("View the basics again.")
                                    .font(LFFont.label(13))
                                    .foregroundStyle(LFColor.ink.opacity(0.52))
                            }

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(LFColor.ink.opacity(0.3))
                        }
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // 代替アイコン非対応の文脈では、押しても無反応な節を出さない。
                    if AppIconStore.isSupported {
                        sectionLabel("App Icon")
                            .padding(.top, 36)
                            .padding(.bottom, 18)

                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                            alignment: .leading,
                            spacing: 22
                        ) {
                            ForEach(AppIconOption.allCases) { option in
                                iconTile(option)
                            }
                        }
                    }

                    // 到達した島。本人の記録なので、要らなくなったものは削除できる。
                    if !reachedIslands.isEmpty {
                        sectionLabel("Islands reached")
                            .padding(.top, 36)
                            .padding(.bottom, 18)

                        reachedIslandsSection
                    }

                    if AccessPolicy.canUseAssetStudio(auth.user) {
                        sectionLabel("Creative tools")
                            .padding(.top, 36)
                            .padding(.bottom, 10)

                        Button {
                            showingAssetStudio = true
                            Haptics.tap(.light)
                        } label: {
                            HStack(spacing: 13) {
                                Image(systemName: "cube.transparent.fill")
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(LFColor.harborSand)
                                    .frame(width: 40, height: 40)
                                    .background(LFColor.harborTeal, in: RoundedRectangle(cornerRadius: 12))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("3D Asset Studio")
                                        .font(LFFont.copy(16))
                                        .foregroundStyle(LFColor.ink)
                                    Text("Place and arrange USDZ models.")
                                        .font(LFFont.label(13))
                                        .foregroundStyle(LFColor.ink.opacity(0.52))
                                }

                                Spacer(minLength: 8)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(LFColor.ink.opacity(0.3))
                            }
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    sectionLabel("Account")
                        .padding(.top, 36)
                        .padding(.bottom, 18)

                    accountSection
                }
                .padding(LFMetrics.cardPadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(LFColor.paper)
        // シート自身も選択言語に追従させる(切替が即時に反映される)。
        .environment(\.locale, (AppLanguage(rawValue: appLanguage) ?? .system).locale)
        .onAppear {
            current = AppIconStore.currentOption()
            #if DEBUG
            if ProcessInfo.processInfo.environment["LANDFALL_ASSET_STUDIO"] == "1" {
                DispatchQueue.main.async { showingAssetStudio = true }
            }
            #endif
        }
        .sheet(isPresented: $addingItem) {
            ItemEditorSheet(existing: nil)
        }
        .sheet(item: $editingItem) { item in
            ItemEditorSheet(existing: item)
        }
        .sheet(isPresented: $showingVoyagePass) {
            VoyagePassView()
        }
        .fullScreenCover(isPresented: $showingTutorial) {
            OnboardingView(secondaryActionTitle: "Close") {
                showingTutorial = false
            }
        }
        .fullScreenCover(isPresented: assetStudioPresentation) {
            AssetPlacementStudioView(homeProgressRatio: homeProgressRatio)
        }
        .confirmationDialog(
            "Delete your account?",
            isPresented: $confirmingDeleteAccount,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and synced record. This cannot be undone.")
        }
        .confirmationDialog(
            "Delete this destination",
            isPresented: Binding(
                get: { pendingDeleteIsland != nil },
                set: { if !$0 { pendingDeleteIsland = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let island = pendingDeleteIsland { deleteIsland(island) }
                pendingDeleteIsland = nil
            }
        } message: {
            Text("Delete this destination? Your records stay.")
        }
    }

    /// ホームと同じ進捗率で船と島の実距離をスタジオへ渡す。
    private var homeProgressRatio: Double {
        destinations.first { $0.achievedAt == nil }?
            .progress(sessions: sessions)
            .ratio ?? 0
    }

    /// 表示ボタンとは別にプレゼンテーション自体も権限で閉じる。
    /// 認証状態が変わった場合も、未許可のスタジオを開いたままにしない。
    private var assetStudioPresentation: Binding<Bool> {
        Binding(
            get: { showingAssetStudio && AccessPolicy.canUseAssetStudio(auth.user) },
            set: { showingAssetStudio = $0 }
        )
    }

    // MARK: - 作業項目

    private var voyagePassCard: some View {
        Button {
            showingVoyagePass = true
            Haptics.tap(.light)
        } label: {
            HStack(spacing: 14) {
                TileSymbolView(
                    symbol: .compass,
                    fg: LFColor.returnOrange,
                    bg: LFColor.harborTeal
                )
                .frame(width: 48, height: 48)
                .background(LFColor.harborTeal, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(voyagePass.isActive ? "Voyage Pass aboard" : "Open Voyage Pass")
                        .font(LFFont.copy(16))
                        .foregroundStyle(LFColor.ink)
                    Text(
                        voyagePass.isActive
                            ? "Active on this Apple Account"
                            : "Seasonal waters, shared voyages, and special attire"
                    )
                    .font(LFFont.label(12))
                    .foregroundStyle(LFColor.ink.opacity(0.50))
                    .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LFColor.ink.opacity(0.28))
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [
                        LFColor.returnOrange.opacity(0.10),
                        LFColor.harborTeal.opacity(0.08),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(LFColor.returnOrange.opacity(0.22), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(LFPressableButtonStyle())
    }

    private var workItemsSection: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                Text("No work items yet.")
                    .font(LFFont.copy(15))
                    .foregroundStyle(LFColor.ink.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.persistentModelID) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(LFColor.ink.opacity(0.08))
                            .frame(height: 1)
                    }

                    HStack(spacing: 12) {
                        Button {
                            editingItem = item
                        } label: {
                            HStack(spacing: 12) {
                                ItemTileArt(item: item)
                                    .frame(width: 44, height: 44)

                                Text(verbatim: item.name)
                                    .font(LFFont.copy(16))
                                    .foregroundStyle(LFColor.ink)
                                    .lineLimit(2)

                                Spacer(minLength: 8)

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(LFColor.ink.opacity(0.32))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        VStack(spacing: 0) {
                            reorderButton(
                                systemName: "chevron.up",
                                label: "Move up",
                                disabled: index == items.startIndex
                            ) {
                                moveItem(at: index, by: -1)
                            }
                            reorderButton(
                                systemName: "chevron.down",
                                label: "Move down",
                                disabled: index == items.index(before: items.endIndex)
                            ) {
                                moveItem(at: index, by: 1)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                }
            }

            Button {
                addingItem = true
            } label: {
                Label("Add work item", systemImage: "plus")
                    .font(LFFont.copy(16))
                    .foregroundStyle(LFColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 48)
            }
            .buttonStyle(.plain)
        }
    }

    private func reorderButton(
        systemName: String,
        label: LocalizedStringKey,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LFColor.ink.opacity(disabled ? 0.16 : 0.52))
                .frame(width: 36, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(Text(label))
    }

    private func moveItem(at index: Int, by offset: Int) {
        let destination = index + offset
        guard items.indices.contains(index), items.indices.contains(destination) else { return }

        var reordered = Array(items)
        let moved = reordered.remove(at: index)
        reordered.insert(moved, at: destination)
        for (sortOrder, item) in reordered.enumerated() {
            item.sortOrder = sortOrder
        }
        try? modelContext.save()
        for item in reordered {
            SyncService.shared.push(item)
        }
        Haptics.tap(.rigid)
    }

    // MARK: - 到達した島

    /// 着岸した目的地。新しい順に並べる。
    private var reachedIslands: [Destination] {
        destinations
            .filter { $0.achievedAt != nil }
            .sorted { ($0.achievedAt ?? .distantPast) > ($1.achievedAt ?? .distantPast) }
    }

    private var reachedIslandsSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(reachedIslands.enumerated()), id: \.element.persistentModelID) { index, island in
                if index > 0 {
                    Rectangle()
                        .fill(LFColor.ink.opacity(0.08))
                        .frame(height: 1)
                }
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: island.name)
                            .font(LFFont.copy(16))
                            .foregroundStyle(LFColor.ink)
                            .lineLimit(1)
                        if let at = island.achievedAt {
                            Text(verbatim: LF.dayMonth(at))
                                .font(LFFont.label(13))
                                .foregroundStyle(LFColor.returnOrange)
                        }
                    }
                    Spacer(minLength: 8)
                    Button {
                        pendingDeleteIsland = island
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(LFColor.deepRust)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Delete"))
                }
                .padding(.vertical, 10)
            }
        }
    }

    /// 到達した島を削除する(同期先からも消す)。作業の記録そのものは残る。
    private func deleteIsland(_ island: Destination) {
        SyncService.shared.delete(island)
        modelContext.delete(island)
        try? modelContext.save()
        Haptics.tap()
    }

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: Binding(
                get: { notifyEnabled },
                set: { wants in
                    if wants {
                        Task {
                            let granted = await NotificationService.enable(
                                recordedToday: StudyDayStore.recordedToday(context: modelContext)
                            )
                            notifyEnabled = granted
                        }
                    } else {
                        notifyEnabled = false
                        Task { await NotificationService.disable() }
                    }
                }
            )) {
                Text("Notifications")
                    .font(LFFont.copy(17))
                    .foregroundStyle(LFColor.ink)
            }
            .tint(LFColor.returnOrange)

            if notifyEnabled {
                HStack {
                    Text("Time of day")
                        .font(LFFont.copy(16))
                        .foregroundStyle(LFColor.ink)
                    Spacer(minLength: 0)
                    DatePicker("", selection: $notifyTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .onChange(of: notifyTime) { _, newValue in
                            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                            UserDefaults.standard.set(comps.hour ?? 21, forKey: NotificationService.hourKey)
                            UserDefaults.standard.set(comps.minute ?? 0, forKey: NotificationService.minuteKey)
                            Task {
                                await NotificationService.reschedule(
                                    recordedToday: StudyDayStore.recordedToday(context: modelContext)
                                )
                            }
                        }
                }
                .padding(.top, 2)
            }
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if auth.isSignedIn {
                Button {
                    Task { await signOutAndClearLocalData() }
                } label: {
                    Text("Sign out")
                        .font(LFFont.copy(16))
                        .foregroundStyle(LFColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(deletingAccount)

                Button {
                    confirmingDeleteAccount = true
                } label: {
                    Text("Delete account")
                        .font(LFFont.label(15))
                        .foregroundStyle(LFColor.deepRust)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(deletingAccount)
            } else {
                Text("Records are stored only on this device.")
                    .font(LFFont.label(13))
                    .foregroundStyle(LFColor.ink.opacity(0.55))

                Button {
                    auth.stopLocalMode()
                    dismiss()
                } label: {
                    Text("Sign in to sync and use harbors")
                        .font(LFFont.copy(16))
                        .foregroundStyle(LFColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            if let message = auth.errorMessage {
                Text(message)
                    .font(LFFont.label(13))
                    .foregroundStyle(LFColor.coral)
            }

            Divider()
                .overlay(LFColor.ink.opacity(0.12))

            if let privacyURL = URL(string: "https://aftide.app/privacy") {
                Link("Privacy policy", destination: privacyURL)
                    .font(LFFont.label(14))
                    .foregroundStyle(LFColor.ink.opacity(0.72))
            }
            if let supportURL = URL(string: "mailto:ari.initx@gmail.com") {
                Link("Support", destination: supportURL)
                    .font(LFFont.label(14))
                    .foregroundStyle(LFColor.ink.opacity(0.72))
            }
        }
    }

    private func deleteAccount() async {
        deletingAccount = true
        defer { deletingAccount = false }
        do {
            try await auth.deleteAccount {
                await RoomService.shared.leaveAllRooms()
                await PublicHarborService.shared.leaveAll()
                try await SyncService.shared.deleteAllRemoteData()
                await LocalAccountData.clearAfterSignOut(context: modelContext)
            }
            dismiss()
        } catch {
            auth.errorMessage = LF.text("Deleting your account failed. Please try signing in again and retry.")
        }
    }

    private func signOutAndClearLocalData() async {
        deletingAccount = true
        await LocalAccountData.clearAfterSignOut(context: modelContext)
        auth.signOut()
        deletingAccount = false
        dismiss()
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(LFFont.label(15))
            .tracking(2)
            .foregroundStyle(LFColor.ink.opacity(0.55))
    }

    private func themePill(_ theme: AppTheme) -> some View {
        let selected = appTheme == theme.rawValue
        return Button {
            Haptics.tap()
            appTheme = theme.rawValue
        } label: {
            Text(theme.label)
                .font(LFFont.label(15))
                .foregroundStyle(selected ? LFColor.paper : LFColor.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(selected ? LFColor.ink : Color.clear)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(LFColor.ink.opacity(selected ? 0 : 0.25), lineWidth: 1)
                )
                .clipShape(Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func languagePill(_ language: AppLanguage) -> some View {
        let selected = appLanguage == language.rawValue
        return Button {
            Haptics.tap()
            appLanguage = language.rawValue
        } label: {
            Group {
                if language == .system {
                    Text("System")
                } else {
                    Text(verbatim: language.nativeName)
                }
            }
            .font(LFFont.label(15))
            .foregroundStyle(selected ? LFColor.paper : LFColor.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(selected ? LFColor.ink : Color.clear)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(LFColor.ink.opacity(selected ? 0 : 0.25), lineWidth: 1)
            )
            .clipShape(Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func iconTile(_ option: AppIconOption) -> some View {
        let selected = option == current
        return Button {
            guard option != current else { return }
            AppIconStore.select(option) { ok in
                if ok {
                    current = option
                    Haptics.tap()
                }
            }
        } label: {
            VStack(spacing: 10) {
                AppIconArt(option: option)
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(
                                selected ? LFColor.returnOrange : LFColor.ink.opacity(0.12),
                                lineWidth: selected ? 3 : 1
                            )
                    )
                Text(option.displayName)
                    .font(LFFont.label(14))
                    .foregroundStyle(selected ? LFColor.ink : LFColor.ink.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(option.displayName))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#Preview {
    SettingsView().environmentObject(AuthService.shared)
}
