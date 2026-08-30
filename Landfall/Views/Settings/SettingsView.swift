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

/// アプリ全体の設定をまとめて扱うシート。
struct SettingsView: View {
    private let onReplayPrologue: (() -> Void)?
    private let onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: AuthService
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue
    @AppStorage(AppTheme.storageKey) private var appTheme = AppTheme.system.rawValue
    @AppStorage(HomeIslandBrightness.storageKey)
    private var islandBrightness = HomeIslandBrightness.fallback.rawValue
    // These preferences are edited from Home's dedicated music item. Settings
    // still reads them to restore audio after replaying the opening story.
    @AppStorage(HomeBackgroundMusic.enabledKey) private var homeMusicEnabled = false
    @Query private var sessions: [StudySession]
    @Query private var destinations: [Destination]
    @State private var current: AppIconOption = .harbor
    /// 削除しようとしている到達済みの島(確認ダイアログ用)。
    @State private var pendingDeleteIsland: Destination?
    @State private var confirmingSignOut = false
    @State private var confirmingDeleteAccount = false
    @State private var deletingAccount = false
    @State private var showingPrologue = false
    @State private var prologuePresentationID = UUID()
    @State private var prologueIsLaunching = false
    @State private var showingTutorial = false
    @State private var showingHelp = false
    @State private var showingVoyagePass = false
    @State private var showingAssetStudio = false
    @State private var showingFeedback = false
    @StateObject private var voyagePass = VoyagePassStore.shared
    @AppStorage(NotificationService.enabledKey) private var notifyEnabled = false
    @State private var updatingNotifications = false
    @AppStorage(StudyTimer.startKey, store: StudyTimer.defaults) private var timerStart: Double = 0
    @AppStorage(StudyTimer.itemKey, store: StudyTimer.defaults) private var timerItemID = ""
    @AppStorage(StudyTimer.soundKey, store: StudyTimer.defaults)
    private var timerSoundMode = HomeVoyageSound.initialTimerSound.rawValue
    @AppStorage(StudyTimer.breakStartedAtKey, store: StudyTimer.defaults) private var timerBreakStartedAt: Double = 0
    @State private var notifyTime = Calendar.current.date(
        from: DateComponents(hour: NotificationService.hour, minute: NotificationService.minute)
    ) ?? Date()

    init(
        onReplayPrologue: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.onReplayPrologue = onReplayPrologue
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            LFBackHeader(title: "Settings") { closeSettings() }
                .padding(.horizontal, LFMetrics.cardPadding)
                .padding(.vertical, 6)

            Rectangle()
                .fill(LFColor.ink.opacity(0.08))
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 航海証だけは節の見出しを置かない。カード自身が紋章と名前を兼ねる。
                    voyagePassCard
                        .padding(.top, 4)

                    sectionLabel("Feedback")
                        .padding(.top, 28)
                        .padding(.bottom, 10)

                    feedbackButton

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

                    sectionLabel("Island brightness")
                        .padding(.top, 36)
                        .padding(.bottom, 18)

                    islandBrightnessSection

                    notificationSection
                        .padding(.top, 36)

                    sectionLabel("Guide")
                        .padding(.top, 36)
                        .padding(.bottom, 10)

                    Button {
                        showingHelp = true
                        Haptics.tap(.light)
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(LFColor.harborSand)
                                .frame(width: 40, height: 40)
                                .background(LFColor.harborTeal, in: RoundedRectangle(cornerRadius: 12))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Help")
                                    .font(LFFont.copy(16))
                                    .foregroundStyle(LFColor.ink)
                                Text("See how to use the main features.")
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
                    .padding(.top, 8)

                    Button {
                        presentPrologue()
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(LFColor.harborSand)
                                .frame(width: 40, height: 40)
                                .background(LFColor.harborTeal, in: RoundedRectangle(cornerRadius: 12))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Opening story")
                                    .font(LFFont.copy(16))
                                    .foregroundStyle(LFColor.ink)
                                Text("Watch the opening story again.")
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
                    .padding(.top, 8)

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
            if ProcessInfo.processInfo.environment["LANDFALL_SETTINGS_PROLOGUE"] == "1" {
                DispatchQueue.main.async { presentPrologue() }
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            guard prologueIsLaunching else { return }
            if phase == .active {
                HomeVoyageAudio.shared.play(
                    HomeVoyageSound.initialTimerSound.rawValue
                )
            } else {
                HomeVoyageAudio.shared.stop()
            }
        }
        .sheet(isPresented: $showingVoyagePass) {
            VoyagePassView()
        }
        .sheet(isPresented: $showingFeedback) {
            FeedbackView()
        }
        .sheet(isPresented: $showingHelp) {
            HelpView()
        }
        .fullScreenCover(isPresented: $showingTutorial) {
            OnboardingView(secondaryActionTitle: "Close") {
                showingTutorial = false
            }
        }
        .fullScreenCover(isPresented: $showingPrologue, onDismiss: resumeHomeAudio) {
            GeometryReader { geometry in
                ZStack {
                    Color(hex: 0x061615)
                    if prologueIsLaunching {
                        PrologueVoyageLaunchSceneView {
                            prologueIsLaunching = false
                            showingPrologue = false
                        }
                        .transition(.opacity)
                    } else {
                        ForgottenSeaPrologueView(mode: .replay) {
                            HomeVoyageAudio.shared.play(
                                HomeVoyageSound.initialTimerSound.rawValue
                            )
                            withAnimation(.easeInOut(duration: 0.48)) {
                                prologueIsLaunching = true
                            }
                        }
                        .id(prologuePresentationID)
                        .transition(.opacity)
                    }
                }
                .padding(.top, geometry.safeAreaInsets.top)
                .padding(.bottom, geometry.safeAreaInsets.bottom)
                .ignoresSafeArea()
            }
            .interactiveDismissDisabled()
        }
        .fullScreenCover(isPresented: assetStudioPresentation) {
            AssetPlacementStudioView(homeProgressRatio: homeProgressRatio)
        }
        .confirmationDialog(
            "Sign out",
            isPresented: $confirmingSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                Task { await signOutAndClearLocalData() }
            }
            Button("Cancel", role: .cancel) {}
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
            Button("Cancel", role: .cancel) {
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

    /// ホーム音響から序章の専用BGMへ静かに引き継ぐ。
    private func presentPrologue() {
        HomeBackgroundMusic.shared.stop()
        HomeWaveAmbience.shared.stop()
        HomeVoyageAudio.shared.stop()
        Haptics.tap(.light)
        if let onReplayPrologue {
            onReplayPrologue()
        } else {
            prologuePresentationID = UUID()
            prologueIsLaunching = false
            showingPrologue = true
        }
    }

    /// 序章を閉じた後、計測中でなければ利用者の音響設定を復元する。
    private func resumeHomeAudio() {
        HomeVoyageAudio.shared.stop()
        guard scenePhase == .active else { return }
        if VoyageTimerMath.isActive(startedAt: timerStart, itemID: timerItemID) {
            if timerBreakStartedAt <= 0 {
                HomeVoyageAudio.shared.play(timerSoundMode)
            }
            return
        }
        if homeMusicEnabled { HomeBackgroundMusic.shared.play() }
    }

    // MARK: - Feedback

    private var feedbackButton: some View {
        Button {
            showingFeedback = true
            Haptics.tap(.light)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LFColor.harborSand)
                    .frame(width: 40, height: 40)
                    .background(LFColor.harborTeal, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Send an improvement idea")
                        .font(LFFont.copy(16))
                        .foregroundStyle(LFColor.ink)
                    Text("Your note goes privately to the operations crew.")
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

    // MARK: - Voyage Pass

    /// アイコンの一辺。ホーム画面のアイコンと同じ、辺の22%で角を丸める。
    private static let voyagePassMarkSide: CGFloat = 50

    private var voyagePassMarkShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.voyagePassMarkSide * 0.22, style: .continuous)
    }

    private var voyagePassCardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    private var voyagePassTitle: LocalizedStringKey {
        voyagePass.isActive ? "Voyage Pass aboard" : "Voyage Pass"
    }

    private var voyagePassSupport: LocalizedStringKey {
        voyagePass.isActive ? "Active on this Apple Account" : "Colours, multiplayer, exclusive assets"
    }

    /// サービスの顔をそのまま置く。輪も座布団も敷かず、角丸だけで見せる。
    private var voyagePassMark: some View {
        Image("ServiceMark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: Self.voyagePassMarkSide, height: Self.voyagePassMarkSide)
            .clipShape(voyagePassMarkShape)
            .shadow(color: Color.black.opacity(0.16), radius: 6, y: 3)
            .accessibilityHidden(true)
    }

    private var voyagePassCopy: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(voyagePassTitle)
                    .font(LFFont.copy(17))
                    .foregroundStyle(LFColor.ink)
                // 携えているときだけの小さな封蝋。売り込みではなく、確認の印。
                if voyagePass.isActive {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(LFColor.returnOrange)
                        .accessibilityHidden(true)
                }
            }
            Text(voyagePassSupport)
                .font(LFFont.label(13))
                .foregroundStyle(LFColor.ink.opacity(0.52))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    /// 紙からほんの少しだけ持ち上げる。地は ink の薄がけにして、明所でも暗所でも同じだけ浮かせる。
    private var voyagePassSurface: some View {
        ZStack {
            voyagePassCardShape
                .fill(LFColor.paper)
                .shadow(color: Color.black.opacity(0.07), radius: 12, y: 5)
            voyagePassCardShape
                .fill(LFColor.ink.opacity(0.05))
            voyagePassCardShape
                .stroke(LFColor.ink.opacity(0.09), lineWidth: 1)
        }
    }

    private var voyagePassRow: some View {
        HStack(spacing: 14) {
            voyagePassMark
            voyagePassCopy

            Spacer(minLength: 8)

            // 未加入のときだけ、進む先を橙で指す。携えているときは他の行と同じ静かさに戻す。
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    voyagePass.isActive ? LFColor.ink.opacity(0.28) : LFColor.returnOrange.opacity(0.85)
                )
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(voyagePassSurface)
        .contentShape(voyagePassCardShape)
    }

    /// この画面でいちばん価値のある入口。設定の一行ではなく、サービスそのものの扉として置く。
    private var voyagePassCard: some View {
        Button {
            showingVoyagePass = true
            Haptics.tap(.light)
        } label: {
            voyagePassRow
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens Voyage Pass"))
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
                    Menu {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            pendingDeleteIsland = island
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(LFColor.ink.opacity(0.46))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Delete this destination"))
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
                    guard !updatingNotifications else { return }
                    updatingNotifications = true
                    notifyEnabled = wants
                    if wants {
                        Task {
                            let granted = await NotificationService.enable(
                                recordedToday: StudyDayStore.recordedToday(context: modelContext)
                            )
                            notifyEnabled = granted
                            updatingNotifications = false
                        }
                    } else {
                        Task {
                            await NotificationService.disable()
                            updatingNotifications = false
                        }
                    }
                }
            )) {
                HStack(spacing: 12) {
                    Image(systemName: notifyEnabled ? "bell.fill" : "bell")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LFColor.harborSand)
                        .frame(width: 38, height: 38)
                        .background(LFColor.harborTeal, in: RoundedRectangle(cornerRadius: 11))
                        .accessibilityHidden(true)

                    Text("Notifications")
                        .font(LFFont.copy(17))
                        .foregroundStyle(LFColor.ink)

                    if updatingNotifications {
                        ProgressView()
                            .controlSize(.small)
                            .tint(LFColor.returnOrange)
                            .accessibilityHidden(true)
                    }
                }
            }
            .tint(LFColor.returnOrange)
            .disabled(updatingNotifications)

            if notifyEnabled {
                Divider()
                    .overlay(LFColor.ink.opacity(0.10))

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
            }
        }
        .padding(14)
        .background(LFColor.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(LFColor.ink.opacity(0.08), lineWidth: 1)
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if auth.isSignedIn {
                Button {
                    confirmingSignOut = true
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
                    closeSettings()
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
                try await PublicHarborService.shared.leaveAll()
                try await SyncService.shared.deleteAllRemoteData()
                await LocalAccountData.clearAfterSignOut(context: modelContext)
            }
            closeSettings()
        } catch {
            auth.errorMessage = LF.text("Deleting your account failed. Please try signing in again and retry.")
        }
    }

    private func signOutAndClearLocalData() async {
        deletingAccount = true
        await LocalAccountData.clearAfterSignOut(context: modelContext)
        auth.signOut()
        deletingAccount = false
        closeSettings()
    }

    private func closeSettings() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(LFFont.label(15))
            .tracking(2)
            .foregroundStyle(LFColor.ink.opacity(0.55))
    }

    /// 端末や部屋の明かりで海と砂の見え方は変わる。標準を真ん中に置いた
    /// 5段で、歩いているときの明るさそのものを選べるようにする。
    private var islandBrightnessSection: some View {
        let selected = HomeIslandBrightness.resolve(islandBrightness)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(HomeIslandBrightness.allCases) { level in
                    brightnessPill(level, selected: selected)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(selected.label)
                    .font(LFFont.copy(15))
                    .foregroundStyle(LFColor.ink)
                Text("The brightness of your island while you walk it.")
                    .font(LFFont.label(13))
                    .foregroundStyle(LFColor.ink.opacity(0.52))
            }
        }
    }

    private func brightnessPill(
        _ level: HomeIslandBrightness,
        selected: HomeIslandBrightness
    ) -> some View {
        let isOn = level == selected
        return Button {
            Haptics.tap()
            islandBrightness = level.rawValue
        } label: {
            Text(verbatim: "\(level.step)")
                .font(LFFont.number(15))
                .foregroundStyle(isOn ? LFColor.paper : LFColor.ink.opacity(0.72))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(isOn ? LFColor.ink : Color.clear)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(LFColor.ink.opacity(isOn ? 0 : 0.25), lineWidth: 1)
                )
                .clipShape(Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(level.label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
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
            AppLanguage.syncToWidgets()
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
