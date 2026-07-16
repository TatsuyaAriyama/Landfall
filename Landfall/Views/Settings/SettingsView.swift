import SwiftUI

/// アプリアイコンの現在値取得と切り替え。setAlternateIconName は iOS のみ。
enum AppIconStore {
    static func currentOption() -> AppIconOption {
        let name = UIApplication.shared.alternateIconName
        return AppIconOption.allCases.first { $0.alternateIconName == name } ?? .midnight
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
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue
    @State private var current: AppIconOption = .midnight

    var body: some View {
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

            sectionLabel("App Icon")
                .padding(.top, 36)
                .padding(.bottom, 18)

            HStack(spacing: 16) {
                ForEach(AppIconOption.allCases) { option in
                    iconTile(option)
                }
                Spacer(minLength: 0)
            }

            Spacer()
        }
        .padding(LFMetrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LFColor.paper)
        // シート自身も選択言語に追従させる(切替が即時に反映される)。
        .environment(\.locale, (AppLanguage(rawValue: appLanguage) ?? .system).locale)
        .onAppear { current = AppIconStore.currentOption() }
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(LFFont.label(15))
            .tracking(2)
            .foregroundStyle(LFColor.ink.opacity(0.55))
    }

    private func languagePill(_ language: AppLanguage) -> some View {
        let selected = appLanguage == language.rawValue
        return Button {
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
            .padding(.vertical, 9)
            .background(selected ? LFColor.ink : Color.clear)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(LFColor.ink.opacity(selected ? 0 : 0.25), lineWidth: 1)
            )
            .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
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
                if ok { current = option }
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
    }
}

#Preview {
    SettingsView()
}
