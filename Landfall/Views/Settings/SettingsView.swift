import SwiftUI

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

/// 設定シート。v1ではアプリアイコンの選択のみ。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthService
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue
    @AppStorage(AppTheme.storageKey) private var appTheme = AppTheme.system.rawValue
    @State private var current: AppIconOption = .harbor
    @State private var confirmingDeleteAccount = false
    @State private var deletingAccount = false
    @AppStorage(NotificationService.enabledKey) private var notifyEnabled = false
    @State private var notifyTime = Calendar.current.date(
        from: DateComponents(hour: NotificationService.hour, minute: NotificationService.minute)
    ) ?? Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                sectionLabel("Language")
                    .padding(.top, 32)
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

                sectionLabel("Notifications")
                    .padding(.top, 36)
                    .padding(.bottom, 18)

                notificationSection

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

                sectionLabel("Account")
                    .padding(.top, 36)
                    .padding(.bottom, 18)

                accountSection
            }
            .padding(LFMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(LFColor.paper)
        // シート自身も選択言語に追従させる(切替が即時に反映される)。
        .environment(\.locale, (AppLanguage(rawValue: appLanguage) ?? .system).locale)
        .onAppear { current = AppIconStore.currentOption() }
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
    }

    // そっと戻れる通知。オフ既定。オンにすると許可を求め、選んだ時刻に一度だけ静かに鳴る。
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
                Text("Gentle reminder")
                    .font(LFFont.copy(17))
                    .foregroundStyle(LFColor.ink)
            }
            .tint(LFColor.returnOrange)

            Text("A quiet nudge, never a nag. If you already showed up today, it stays silent.")
                .font(LFFont.copy(13))
                .foregroundStyle(LFColor.ink.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

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
            Button {
                auth.signOut()
                dismiss()
            } label: {
                Text("Sign out")
                    .font(LFFont.copy(16))
                    .foregroundStyle(LFColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

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

            if let message = auth.errorMessage {
                Text(message)
                    .font(LFFont.label(13))
                    .foregroundStyle(LFColor.coral)
            }
        }
    }

    private func deleteAccount() async {
        deletingAccount = true
        defer { deletingAccount = false }
        do {
            await RoomService.shared.leaveAllRooms()
            try await SyncService.shared.deleteAllRemoteData()
            try await auth.deleteAccount()
            dismiss()
        } catch {
            auth.errorMessage = String(localized: "Deleting your account failed. Please try signing in again and retry.")
        }
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

    private var header: some View {
        HStack {
            Text("Settings")
                .font(LFFont.copy(20))
                .foregroundStyle(LFColor.ink)
            Spacer()
            Button("Close") { dismiss() }
                .font(LFFont.label(15))
                .foregroundStyle(LFColor.ink.opacity(0.6))
        }
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
