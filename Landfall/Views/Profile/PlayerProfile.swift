import SwiftData
import SwiftUI

/// プレイヤープロフィール。名前・アイコン(配色×シンボル)・決意のひとこと。
/// UserDefaults はオフライン用の端末キャッシュ。サインイン中は SyncService が
/// users/{uid}/gameData/profile を正として復元・端末間同期する。
enum PlayerProfile {
    static let nameKey = "player.name"
    static let styleKey = "player.style"
    static let symbolKey = "player.symbol"
    static let resolveKey = "player.resolve"
    static let sinceDayKey = "player.sinceDay"
    static let updatedAtKey = "player.updatedAt"
    /// モバイルの島HUD・共有カード・港で省略されにくい表示名上限。
    /// SwiftのCharacter単位なので、結合文字や絵文字もプレイヤーが見る1文字として数える。
    static let nameCharacterLimit = 12

    /// 使い始めた日(yyyy-MM-dd)の書式。days の docID と同じ規約(端末ローカルの暦)。
    static let sinceDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static var name: String {
        normalizedName(UserDefaults.standard.string(forKey: nameKey) ?? "")
    }

    static func normalizedName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(nameCharacterLimit))
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

    static func save(
        name: String,
        styleToken: String,
        symbolToken: String,
        resolve: String,
        updatedAt: Date = Date()
    ) {
        let defaults = UserDefaults.standard
        defaults.set(normalizedName(name), forKey: nameKey)
        defaults.set(TileStyle.from(styleToken).rawValue, forKey: styleKey)
        defaults.set(TileSymbol.from(symbolToken).rawValue, forKey: symbolKey)
        defaults.set(
            String(resolve.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)),
            forKey: resolveKey
        )
        defaults.set(updatedAt.timeIntervalSince1970, forKey: updatedAtKey)
    }

    static var updatedAt: Date {
        let value = UserDefaults.standard.double(forKey: updatedAtKey)
        return value > 0 ? Date(timeIntervalSince1970: value) : .distantPast
    }

    /// このサービスを使い始めた日(yyyy-MM-dd)。まだ分からなければ空。
    static var sinceDay: String {
        let stored = UserDefaults.standard.string(forKey: sinceDayKey) ?? ""
        return sinceDayFormatter.date(from: stored) == nil ? "" : stored
    }

    /// 「このサービスを使い始めた日」を取り直す。Web の since.ts(serviceStartDay)と同じ決め方:
    /// 基準はアカウントを作った日(サーバ由来なので端末をまたいでも同じ)。ただし記録の方が
    /// 古いこともありうる(手入力・時計ずれ・他プラットフォームからの移行)ので、記録の最古日が
    /// それより前ならそちらを採る。記録が範囲の外に落ちないことを優先する。
    /// 記録の全量を数えるので、呼ぶのは全量が手元にある場所だけ(RoomService.monthPayload ほか)。
    static func rememberVoyageStart(context: ModelContext, accountCreatedAt: Date?) {
        // 日付が欠けた書類は 1970 に落ちる。1970年は「はじまり」ではないので無視する
        // (Web の EPOCH_GUARD と同じ考え)。
        let guardDate = DateComponents(calendar: Calendar(identifier: .gregorian),
                                       timeZone: TimeZone(secondsFromGMT: 0),
                                       year: 2000, month: 1, day: 1).date ?? .distantPast
        var candidates: [Date] = []
        if let accountCreatedAt { candidates.append(accountCreatedAt) }
        candidates += ((try? context.fetch(FetchDescriptor<StudyDay>())) ?? []).map(\.date)
        candidates += ((try? context.fetch(FetchDescriptor<StudySession>())) ?? []).map(\.date)
        guard let earliest = candidates.filter({ $0 > guardDate }).min() else { return }
        UserDefaults.standard.set(sinceDayFormatter.string(from: earliest), forKey: sinceDayKey)
    }

    /// 表示名。未設定なら「船乗り」。
    static var displayName: String {
        name.isEmpty ? LF.text("Sailor") : name
    }

    /// 島は「プレイヤー名＋の島」で統一し、未設定の旧ユーザーは「船乗りの島」と表示する。
    static var islandName: String {
        LF.format("%@'s Island", displayName)
    }

    static func reset() {
        let defaults = UserDefaults.standard
        for key in [nameKey, styleKey, symbolKey, resolveKey, sinceDayKey, updatedAtKey] {
            defaults.removeObject(forKey: key)
        }
    }

    /// 港(プライベート/パブリック共通)のメンバードキュメントに書くプロフィール一式。
    /// 長さはFirestoreルールの上限に合わせて切り詰める。
    static func harborProfileData() -> [String: Any] {
        var data: [String: Any] = [
            "displayName": String(displayName.prefix(nameCharacterLimit)),
            "styleToken": styleToken,
            "symbolToken": symbolToken,
            "resolve": String(resolve.prefix(80)),
        ]
        // 使い始めた日。分からないうちは書かない(読み手は何も出さない)。
        let since = sinceDay
        if !since.isEmpty { data["sinceDay"] = since }
        // 「みんなの海」で各自の船を出すための部位id(色ではなくid)。Web boatShareData 準拠。
        for (key, value) in BoatCustomization.shareData { data[key] = value }
        return data
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
    /// 使い始めた日(yyyy-MM-dd)。空・書式違い(古いクライアントのカード)なら出さない。
    var sinceDay: String = ""

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
                // このサービスを初めて使った日。決意より小さく、控えめに。
                if let start = PlayerProfile.sinceDayFormatter.date(from: sinceDay) {
                    Text("Sailing since \(LF.fullDate(start))")
                        .font(LFFont.label(12))
                        .foregroundStyle(style.foreground.opacity(0.65))
                        .lineLimit(1)
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
    /// Rendered inside the island's floating player panel: the form keeps its
    /// full content but drops the sheet-sized header and paper background so it
    /// fits a small card.
    var compact = false
    /// Supplied when the editor is embedded rather than presented, because an
    /// embedded view has no presentation to dismiss.
    var onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var name = PlayerProfile.name
    @State private var styleToken = PlayerProfile.styleToken
    @State private var symbolToken = PlayerProfile.symbolToken
    @State private var resolve = PlayerProfile.resolve
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            if compact {
                HStack(spacing: 8) {
                    Button(action: close) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(LFColor.ink.opacity(0.62))
                            .frame(width: 26, height: 26)
                            .background(LFColor.ink.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Back"))

                    Text("Player card")
                        .font(LFFont.label(10))
                        .tracking(1.1)
                        .foregroundStyle(LFColor.ink.opacity(0.62))
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 8)
            } else {
                LFBackHeader(title: "Player card") { close() }
                    .padding(.horizontal, LFMetrics.cardPadding)
                    .padding(.vertical, 6)

                Rectangle()
                    .fill(LFColor.ink.opacity(0.08))
                    .frame(height: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                // プレビュー: 入力がそのままカードになる。
                PlayerCardView(
                    name: previewName,
                    styleToken: styleToken,
                    symbolToken: symbolToken,
                    resolve: resolve,
                    sinceDay: PlayerProfile.sinceDay
                )
                .padding(.top, 20)

                HStack {
                    sectionLabel("Player name")
                    Spacer()
                    Text(verbatim: "\(trimmedNameCount)/\(PlayerProfile.nameCharacterLimit)")
                        .font(LFFont.label(11))
                        .foregroundStyle(
                            trimmedNameCount > PlayerProfile.nameCharacterLimit
                                ? LFColor.returnOrange : LFColor.ink.opacity(0.42)
                        )
                        .accessibilityLabel(
                            Text(
                                verbatim: LF.format(
                                    "%lld of %lld characters",
                                    Int64(trimmedNameCount),
                                    Int64(PlayerProfile.nameCharacterLimit)
                                )
                            )
                        )
                }
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
                    .autocorrectionDisabled()

                sectionLabel("Color")
                    .padding(.top, 28)
                // カードの配色は項目タイルより数が多いので、シンボルと同じく横スクロール。
                ScrollView(.horizontal, showsIndicators: false) {
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
                    .padding(.vertical, 4)   // 選択枠が切れないように
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
                // 打鍵ごとにresolveを書き戻すと、日本語入力の変換中文字(未確定文字列)が
                // 毎回リセットされ、日本語が一切打てなくなる。上限は保存時にのみ適用する。
                TextField("Write your resolve", text: $resolve, axis: .vertical)
                    .font(LFFont.label(16))
                    .foregroundStyle(LFColor.ink)
                    .tint(LFColor.ink)
                    .lineLimit(2)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(LFColor.ink.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.top, 12)

                Button {
                    guard !working else { return }
                    Task {
                        working = true
                        // 上限はここでのみ適用(打鍵中に書き戻すとIME変換が壊れるため)。
                        PlayerProfile.save(
                            name: name,
                            styleToken: styleToken,
                            symbolToken: symbolToken,
                            resolve: resolve
                        )
                        name = PlayerProfile.name
                        resolve = PlayerProfile.resolve
                        // 本人用バックアップを先に更新し、その後に港の公開カードへ反映する。
                        await SyncService.shared.pushPlayerProfile()
                        await PrivateIslandService.shared.publishProfileToJoinedIslands()
                        await PublicHarborService.shared.syncProfile()
                        Haptics.success()
                        onSaved()
                        close()
                    }
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
                .disabled(working)
                .opacity(working ? 0.45 : 1)
                .padding(.top, 32)
                }
                .padding(compact ? 0 : LFMetrics.cardPadding)
            }
            .frame(maxHeight: compact ? 380 : .infinity)
            .scrollBounceBehavior(compact ? .basedOnSize : .automatic)
        }
        .background(compact ? Color.clear : LFColor.paper)
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(LFFont.label(13))
            .tracking(1)
            .foregroundStyle(LFColor.ink.opacity(0.5))
    }

    private var trimmedNameCount: Int {
        name.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    private var previewName: String {
        let normalized = PlayerProfile.normalizedName(name)
        return normalized.isEmpty ? LF.text("Sailor") : normalized
    }
}

#Preview {
    ProfileEditorSheet()
}
