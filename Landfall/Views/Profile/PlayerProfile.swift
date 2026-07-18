import SwiftUI

/// プレイヤープロフィール。名前・アイコン(配色×シンボル)・決意のひとこと。
/// ローカル先行(UserDefaults)。港に入っているときだけメンバー情報として共有される。
enum PlayerProfile {
    static let nameKey = "player.name"
    static let styleKey = "player.style"
    static let symbolKey = "player.symbol"
    static let resolveKey = "player.resolve"

    static var name: String {
        UserDefaults.standard.string(forKey: nameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static var styleToken: String {
        UserDefaults.standard.string(forKey: styleKey) ?? TileStyle.midnight.rawValue
    }

    static var symbolToken: String {
        UserDefaults.standard.string(forKey: symbolKey) ?? TileSymbol.phoenix.rawValue
    }

    static var resolve: String {
        UserDefaults.standard.string(forKey: resolveKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// 表示名。未設定なら「船乗り」。
    static var displayName: String {
        name.isEmpty ? String(localized: "Sailor") : name
    }
}

/// 丸いプレイヤーアイコン。項目タイル(角丸四角)と区別するため円にする。
struct PlayerAvatarArt: View {
    let styleToken: String
    let symbolToken: String

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let style = TileStyle.from(styleToken)
            ZStack {
                Circle().fill(style.background)
                TileSymbolView(
                    symbol: TileSymbol.from(symbolToken),
                    fg: style.foreground,
                    bg: style.background
                )
                .frame(width: s * 0.56, height: s * 0.56)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// プレイヤーカード。名前・アイコン・決意を一枚にまとめる。
/// 背景は選んだ配色。フラット塗りのみ、角丸20。
struct PlayerCardView: View {
    let name: String
    let styleToken: String
    let symbolToken: String
    let resolve: String

    var body: some View {
        let style = TileStyle.from(styleToken)
        HStack(spacing: 16) {
            PlayerAvatarArt(styleToken: styleToken, symbolToken: symbolToken)
                .frame(width: 64, height: 64)
                .overlay(
                    Circle().stroke(style.foreground.opacity(0.35), lineWidth: 1.5)
                )
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: name)
                    .font(LFFont.copy(20))
                    .foregroundStyle(style.foreground)
                    .lineLimit(1)
                if !resolve.isEmpty {
                    // 決意: 断言の一文。カードの主役コピー。
                    Text(verbatim: resolve)
                        .font(LFFont.copy(14))
                        .foregroundStyle(style.foreground.opacity(0.8))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(style.background)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// プロフィール編集シート。名前・アイコン(配色×シンボル)・決意。
/// 保存でローカルに書き、参加中の全港へも反映する。
struct ProfileEditorSheet: View {
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @AppStorage(PlayerProfile.nameKey) private var name = ""
    @AppStorage(PlayerProfile.styleKey) private var styleToken = TileStyle.midnight.rawValue
    @AppStorage(PlayerProfile.symbolKey) private var symbolToken = TileSymbol.phoenix.rawValue
    @AppStorage(PlayerProfile.resolveKey) private var resolve = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Player card")
                        .font(LFFont.copy(20))
                        .foregroundStyle(LFColor.ink)
                    Spacer()
                    Button("Close") { dismiss() }
                        .font(LFFont.label(15))
                        .foregroundStyle(LFColor.ink.opacity(0.6))
                }

                // プレビュー: 入力がそのままカードになる。
                PlayerCardView(
                    name: name.trimmingCharacters(in: .whitespaces).isEmpty
                        ? String(localized: "Sailor") : name,
                    styleToken: styleToken,
                    symbolToken: symbolToken,
                    resolve: resolve
                )
                .padding(.top, 24)

                sectionLabel("Player name")
                    .padding(.top, 32)
                TextField("Player name", text: $name)
                    .font(LFFont.label(16))
                    .foregroundStyle(LFColor.ink)
                    .tint(LFColor.ink)
                    .padding(.horizontal, 18)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(LFColor.ink.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.top, 12)

                sectionLabel("Color")
                    .padding(.top, 28)
                HStack(spacing: 14) {
                    ForEach(TileStyle.allCases) { style in
                        Button {
                            styleToken = style.rawValue
                        } label: {
                            Circle()
                                .fill(style.background)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle().stroke(
                                        styleToken == style.rawValue
                                            ? LFColor.returnOrange : LFColor.ink.opacity(0.12),
                                        lineWidth: styleToken == style.rawValue ? 3 : 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 12)

                sectionLabel("Symbol")
                    .padding(.top, 28)
                // 数が増えたので横スクロール。
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(TileSymbol.allCases) { symbol in
                            Button {
                                symbolToken = symbol.rawValue
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(LFColor.ink.opacity(0.06))
                                    TileSymbolView(symbol: symbol, fg: LFColor.ink, bg: LFColor.paper)
                                        .frame(width: 26, height: 26)
                                }
                                .frame(width: 44, height: 44)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(
                                            symbolToken == symbol.rawValue
                                                ? LFColor.returnOrange : .clear,
                                            lineWidth: 3
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)   // 選択枠が切れないように
                }
                .padding(.top, 12)

                sectionLabel("Resolve")
                    .padding(.top, 28)
                TextField("One line you sail by (optional)", text: $resolve, axis: .vertical)
                    .font(LFFont.label(16))
                    .foregroundStyle(LFColor.ink)
                    .tint(LFColor.ink)
                    .lineLimit(2)
                    .onChange(of: resolve) { _, value in
                        if value.count > 60 { resolve = String(value.prefix(60)) }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(LFColor.ink.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.top, 12)

                Button {
                    // ローカルは@AppStorageで保存済み。港にも反映して閉じる。
                    RoomService.shared.pushProfileToAllRooms()
                    Haptics.success()
                    onSaved()
                    dismiss()
                } label: {
                    Text("Save this card")
                        .font(LFFont.copy(17))
                        .foregroundStyle(LFColor.paper)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(LFColor.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 32)
            }
            .padding(LFMetrics.cardPadding)
        }
        .background(LFColor.paper)
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(LFFont.label(13))
            .tracking(1)
            .foregroundStyle(LFColor.ink.opacity(0.5))
    }
}

#Preview {
    ProfileEditorSheet()
}
