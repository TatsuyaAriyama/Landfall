import SwiftData
import SwiftUI

#if DEBUG
/// 動作確認用の並べ置き。二台の端末を用意しなくても、同行の航海の札と
/// 甲板の同乗者だけを一枚の画面で見比べられる。
/// `LANDFALL_COVOYAGE=panels` で札、`=deck` で甲板。
struct CompanionVoyagePreviewView: View {
    @Query private var sessions: [StudySession]
    @State private var previewShowsPicker = false

    private let crew: [CompanionVoyageCrewMate] = [
        CompanionVoyageCrewMate(
            id: "preview-self",
            name: "あなた",
            identity: CompanionVoyageIdentity(
                level: 16,
                styleToken: TileStyle.violet.rawValue,
                symbolToken: TileSymbol.phoenix.rawValue,
                hullID: BoatCustomization.shareData["boatHull"] ?? "sand",
                sailID: BoatCustomization.selectedSailID
            ),
            stage: .muster,
            isHost: true,
            isLocal: true
        ),
        CompanionVoyageCrewMate(
            id: "preview-akari",
            name: "あかり",
            identity: CompanionVoyageIdentity(
                level: 12,
                styleToken: TileStyle.coral.rawValue,
                symbolToken: TileSymbol.compass.rawValue,
                hullID: "sand",
                sailID: "coral"
            ),
            stage: .muster,
            isHost: false,
            isLocal: false
        ),
        CompanionVoyageCrewMate(
            id: "preview-nagi",
            name: "凪",
            identity: CompanionVoyageIdentity(
                level: 8,
                styleToken: TileStyle.seaGreen.rawValue,
                symbolToken: TileSymbol.anchor.rawValue,
                hullID: "sand",
                sailID: "seaGreen"
            ),
            stage: nil,
            isHost: false,
            isLocal: false
        ),
    ]

    private var deckMode: String? {
        let raw = ProcessInfo.processInfo.environment["LANDFALL_COVOYAGE"]
        return raw == "deck" || raw == "deck-guest" ? raw : nil
    }

    private var panelMode: String {
        ProcessInfo.processInfo.environment["LANDFALL_COVOYAGE"] ?? "panels"
    }

    private var previewBoatIdentity: CompanionVoyageIdentity {
        if deckMode == "deck-guest" {
            return crew.first(where: \.isHost)?.identity ?? .fallback
        }
        return .local(level: 16)
    }

    /// `deck` はホストの画面(自分がランタンを掲げる)、`deck-guest` は同行者の
    /// 画面(ホストが甲板にいる)。
    private var deckMembers: [VoyageSceneKit.CompanionDeckMember] {
        deckMode == "deck-guest"
            ? [
                VoyageSceneKit.CompanionDeckMember(id: "preview-host", isHost: true),
                VoyageSceneKit.CompanionDeckMember(id: "preview-akari", isHost: false),
                VoyageSceneKit.CompanionDeckMember(id: "preview-nagi", isHost: false),
            ]
            : [
                VoyageSceneKit.CompanionDeckMember(id: "preview-akari", isHost: false),
                VoyageSceneKit.CompanionDeckMember(id: "preview-nagi", isHost: false),
                VoyageSceneKit.CompanionDeckMember(id: "preview-umi", isHost: false),
            ]
    }

    var body: some View {
        ZStack {
            if deckMode != nil {
                VoyagingHomeSceneView(
                    showIsland: false,
                    timeOfDay: .day,
                    resting: false,
                    elapsedSeconds: 60,
                    boatParts: previewBoatIdentity.boatParts,
                    boatAppearanceKey: previewBoatIdentity.boatAppearanceKey,
                    companions: deckMembers,
                    localSailorPose: deckMode == "deck" ? .raise : nil
                )
                .ignoresSafeArea()
            } else {
                // 確認画面だけ別の背景にすると、実際の島での見え方を
                // 誤解しやすい。普段のホームと同じ保存済みの自分の島をそのまま使う。
                HomeIslandView(
                    ownerID: AuthService.shared.homeIslandOwnerID,
                    levelProgress: PlayerLevelProgress(sessions: sessions),
                    startsMooredAtIsland: true,
                    boatTapOpensSelection: true,
                    showsDestination: true
                )
                .allowsHitTesting(false)

                Group {
                    switch panelMode {
                    case "invite":
                        CompanionVoyageInvitePanel(
                            hostName: "あかり",
                            isSailing: false,
                            onJoin: {},
                            onDismiss: {}
                        )
                    case "panels-guest":
                        CompanionVoyageMusterPanel(
                            itemName: "英単語",
                            crew: crew,
                            canSetSail: false,
                            onChangeItem: {},
                            onSetSail: {},
                            onCancel: {}
                        )
                    case "picker":
                        CompanionVoyageItemPickerHost(onSelect: { _ in }, onCancel: {})
                    default:
                        if previewShowsPicker {
                            CompanionVoyageItemPickerHost(
                                onSelect: { _ in previewShowsPicker = false },
                                onCancel: { previewShowsPicker = false }
                            )
                        } else {
                            CompanionVoyageMusterPanel(
                                itemName: "英単語",
                                crew: crew,
                                canSetSail: true,
                                onChangeItem: { previewShowsPicker = true },
                                onSetSail: {},
                                onCancel: {}
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .safeAreaPadding(.top, 62)
            }
        }
        .preferredColorScheme(.light)
    }
}
#endif

/// 同行の航海まわりの札。島の景色を覆い隠さないよう、どれも一つの
/// コンパクトな白硝子に収める。
private enum CompanionVoyagePanelStyle {
    static let cornerRadius: CGFloat = 20
    static let width: CGFloat = 300
    static var ink: Color { LFColor.harborTeal }

    static func surface() -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: 0xFAF8F0).opacity(0.97),
                        Color(hex: 0xEAF5EE).opacity(0.95),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(LFColor.harborTeal.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 18, y: 9)
    }
}

/// 参加一覧。出航前の待ち合わせに出す。航海が始まってからの同乗者は、
/// 航海の札の中の一段(`companionStrip`)で名前だけを見せる。
struct CompanionVoyageMusterPanel: View {
    let itemName: String
    let crew: [CompanionVoyageCrewMate]
    /// ホストだけが出航の合図を出せる。同行者は支度を済ませて待つ。
    let canSetSail: Bool
    let onChangeItem: () -> Void
    let onSetSail: () -> Void
    let onCancel: () -> Void

    private var aboardCount: Int { crew.filter(\.isAboard).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sailboat.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LFColor.returnOrange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sail together")
                        .font(LFFont.label(9))
                        .tracking(1.0)
                        .foregroundStyle(CompanionVoyagePanelStyle.ink.opacity(0.6))
                    Button(action: onChangeItem) {
                        HStack(spacing: 4) {
                            Text(verbatim: itemName)
                                .font(LFFont.copy(13))
                                .lineLimit(1)
                            Image(systemName: "pencil")
                                .font(.system(size: 8, weight: .semibold))
                                .opacity(0.48)
                            Text("Edit")
                                .font(LFFont.label(8))
                                .opacity(0.58)
                        }
                        .foregroundStyle(CompanionVoyagePanelStyle.ink)
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    .accessibilityLabel(Text("Change work item"))
                    .accessibilityValue(Text(verbatim: itemName))
                }
                Spacer(minLength: 4)
                Text(verbatim: "\(aboardCount)/\(crew.count)")
                    .font(LFFont.label(10))
                    .monospacedDigit()
                    .foregroundStyle(CompanionVoyagePanelStyle.ink.opacity(0.55))
            }
            .padding(.horizontal, 12)
            .padding(.top, 11)

            Rectangle()
                .fill(CompanionVoyagePanelStyle.ink.opacity(0.12))
                .frame(height: 1)
                .padding(.top, 9)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(crew) { mate in
                        CompanionVoyageCrewRow(mate: mate)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 152)

            Rectangle()
                .fill(CompanionVoyagePanelStyle.ink.opacity(0.12))
                .frame(height: 1)

            VStack(spacing: 6) {
                if canSetSail {
                    Button(action: onSetSail) {
                        Text("Set sail")
                            .font(LFFont.label(12))
                            .foregroundStyle(LFColor.harborSand)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(LFColor.harborTeal, in: Capsule())
                    }
                    .buttonStyle(LFPressableButtonStyle())
                } else {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(CompanionVoyagePanelStyle.ink)
                        Text("Waiting for the host to set sail")
                            .font(LFFont.label(10.5))
                            .foregroundStyle(CompanionVoyagePanelStyle.ink.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                }

                Button(action: onCancel) {
                    Text("Stay on the island")
                        .font(LFFont.label(11))
                        .foregroundStyle(CompanionVoyagePanelStyle.ink.opacity(0.72))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(LFPressableButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 10)
        }
        .frame(width: CompanionVoyagePanelStyle.width)
        .background(CompanionVoyagePanelStyle.surface())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Sail together"))
    }
}

private struct CompanionVoyageCrewRow: View {
    let mate: CompanionVoyageCrewMate

    private var stateLabel: LocalizedStringKey {
        switch mate.stage {
        case .sailing: "Sailing"
        case .muster: "Aboard"
        case nil: "On the island"
        }
    }

    private var dotColor: Color {
        switch mate.stage {
        case .sailing: LFColor.returnOrange
        case .muster: LFColor.harborTeal
        case nil: LFColor.harborTeal.opacity(0.24)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            PlayerAvatarArt(
                styleToken: mate.identity.styleToken,
                symbolToken: mate.identity.symbolToken
            )
            .frame(width: 25, height: 25)
            .overlay(Circle().stroke(dotColor.opacity(0.75), lineWidth: 1.25))

            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: mate.name)
                    .font(LFFont.copy(11.5))
                    .foregroundStyle(LFColor.harborTeal)
                    .lineLimit(1)
                Text(verbatim: "LV \(mate.identity.level)")
                    .font(LFFont.label(7.5))
                    .tracking(0.6)
                    .foregroundStyle(LFColor.harborTeal.opacity(0.5))
            }
            if mate.isHost {
                Text("Host")
                    .font(LFFont.label(8))
                    .tracking(0.8)
                    .foregroundStyle(LFColor.harborTeal.opacity(0.55))
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background(LFColor.harborTeal.opacity(0.08), in: Capsule())
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 5, height: 5)
                Text(stateLabel)
                    .font(LFFont.label(8.5))
                    .foregroundStyle(LFColor.harborTeal.opacity(0.55))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .accessibilityElement(children: .combine)
    }
}

/// 同行者側の呼びかけ。島を歩いている最中でも邪魔にならない一段。
struct CompanionVoyageInvitePanel: View {
    let hostName: String
    let isSailing: Bool
    let onJoin: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "sailboat.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LFColor.returnOrange)

            VStack(alignment: .leading, spacing: 1) {
                Text(
                    isSailing
                        ? LF.format("%@ is out at sea", hostName)
                        : LF.format("%@ is getting ready to sail", hostName)
                )
                .font(LFFont.copy(12))
                .foregroundStyle(LFColor.harborTeal)
                .lineLimit(1)
                Text("Choose your work and sail along.")
                    .font(LFFont.label(9))
                    .foregroundStyle(LFColor.harborTeal.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button(action: onJoin) {
                Text("Sail along")
                    .font(LFFont.label(11))
                    .foregroundStyle(LFColor.harborSand)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(LFColor.harborTeal, in: Capsule())
            }
            .buttonStyle(LFPressableButtonStyle())

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LFColor.harborTeal.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(LFColor.harborTeal.opacity(0.07), in: Circle())
            }
            .buttonStyle(LFPressableButtonStyle())
            .accessibilityLabel(Text("Dismiss"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 380)
        .background(CompanionVoyagePanelStyle.surface())
        .accessibilityElement(children: .contain)
    }
}

/// 同行者が自分の作業項目を選ぶ札。記録も経験値も、いつも通り自分のものになる。
struct CompanionVoyageItemPicker: View {
    let items: [StudyItem]
    let onSelect: (StudyItem) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("What will you work on?")
                    .font(LFFont.copy(13))
                    .foregroundStyle(CompanionVoyagePanelStyle.ink)
                Spacer(minLength: 4)
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CompanionVoyagePanelStyle.ink)
                        .frame(width: 30, height: 30)
                        .background(CompanionVoyagePanelStyle.ink.opacity(0.07), in: Circle())
                }
                .buttonStyle(LFPressableButtonStyle())
                .accessibilityLabel(Text("Close"))
            }
            .padding(.horizontal, 12)
            .padding(.top, 11)
            .padding(.bottom, 9)

            Rectangle()
                .fill(CompanionVoyagePanelStyle.ink.opacity(0.12))
                .frame(height: 1)

            if items.isEmpty {
                Text("Create a work item on your own island first.")
                    .font(LFFont.copy(11.5))
                    .foregroundStyle(CompanionVoyagePanelStyle.ink.opacity(0.65))
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 18)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            Button {
                                onSelect(item)
                            } label: {
                                HStack(spacing: 9) {
                                    ItemTileArt(item: item)
                                        .frame(width: 26, height: 26)
                                    Text(verbatim: item.name)
                                        .font(LFFont.copy(12.5))
                                        .foregroundStyle(CompanionVoyagePanelStyle.ink)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(
                                            CompanionVoyagePanelStyle.ink.opacity(0.35)
                                        )
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 42)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(LFPressableButtonStyle())
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 210)
            }
        }
        .frame(width: CompanionVoyagePanelStyle.width)
        .background(CompanionVoyagePanelStyle.surface())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("What will you work on?"))
    }
}

/// 同行者の航海画面。目的地の有無だけ自分の記録から見て、あとは通常の航海と
/// 同じ札をそのまま使う。記録も経験値も、いつも通り自分に入る。
struct CompanionVoyageTimerHost: View {
    let item: StudyItem
    let companions: [CompanionVoyageCrewMate]
    let onReturnHome: () -> Void

    @Query private var destinations: [Destination]

    var body: some View {
        let hostIdentity = companions.first(where: \.isHost)?.identity ?? .fallback
        HomeVoyageTimerView(
            item: item,
            hasDestination: destinations.contains { $0.achievedAt == nil },
            onManual: { _ in },
            onReturnHome: onReturnHome,
            companions: companions,
            boatParts: hostIdentity.boatParts,
            boatAppearanceKey: hostIdentity.boatAppearanceKey
        )
    }
}

/// 島にいるあいだに開く作業項目の一覧。自分の島の並び順のまま出す。
struct CompanionVoyageItemPickerHost: View {
    let onSelect: (StudyItem) -> Void
    let onCancel: () -> Void

    @Query(sort: \StudyItem.sortOrder) private var items: [StudyItem]

    var body: some View {
        CompanionVoyageItemPicker(
            items: items,
            onSelect: onSelect,
            onCancel: onCancel
        )
    }
}
