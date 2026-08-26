import SwiftData
import SwiftUI
import UIKit

/// 装い。船は船体と帆色を選び、航海士は仕草を切り替えて眺める。
struct DressView: View {
    @Environment(\.dismiss) private var dismiss
    /// 船はレベルで開く。到達段階はいつもどおり記録から導き、
    /// 別立ての残高は持たない。
    @Query private var sessions: [StudySession]
    var onClose: (() -> Void)?
    @StateObject private var voyagePass = VoyagePassStore.shared

    /// Web版と同じく、色を替えてもカメラの向きは保ったまま船だけ更新する。
    @State private var boatParts = BoatCustomization.currentParts
    @State private var mode: Mode = Self.initialMode
    @State private var cameraResetToken = 0
    /// 鍵の掛かった船を触ったときだけ、開く条件を見出しへ出す。
    @State private var lockedShipTapped: ShipDesign?
    @State private var showingVoyagePass = false
    /// 航海士のポーズ。Web版と同じローカルキーへ保存する。
    @State private var navPose: PhoenixPose = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["LANDFALL_NAV_POSE"],
           let pose = PhoenixPose(rawValue: raw) {
            return pose
        }
        #endif
        return PhoenixPose.selected
    }()

    enum Mode {
        case boat
        case navigator
    }

    private static var initialMode: Mode {
        #if DEBUG
        // 色選択を検証するためのデモ選択。
        if ProcessInfo.processInfo.environment["LANDFALL_DEMO_BOAT"] != nil {
            BoatCustomization.selectSail("coral")
        }
        // レベルを積まずに新しい船を確かめるための直行指定。
        if let ship = ProcessInfo.processInfo.environment["LANDFALL_SHIP"] {
            BoatCustomization.selectShip(ship)
        }
        if ProcessInfo.processInfo.environment["LANDFALL_DRESS_NAV"] == "1" {
            return .navigator
        }
        #endif
        return .boat
    }

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    private var levelProgress: PlayerLevelProgress {
        PlayerLevelProgress(sessions: sessions)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Web版は一つの Canvas の中で背景とカメラを使い回し、船／航海士だけを
                // 差し替える。iOSも一枚のSceneKitビューを画面全体へ敷いて同じ構造にする。
                DressStudioSceneView(
                    parts: boatParts,
                    pose: navPose,
                    showsNavigator: mode == .navigator,
                    resetToken: cameraResetToken
                )
                .ignoresSafeArea()

                // 文字の背後だけ夜色を少し深くし、3D世界そのものは隠さない。
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            Color(hex: 0x071C19).opacity(0.78),
                            Color(hex: 0x071C19).opacity(0.26),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 250)
                    Spacer()
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    topControls
                    Spacer(minLength: 16)
                    controlPanel
                }
            }
            .background(Color(hex: 0x123830).ignoresSafeArea())
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showingVoyagePass) {
            VoyagePassView()
        }
        .onChange(of: voyagePass.isActive) { _, active in
            BoatCustomization.updatePassState(active)
            boatParts = BoatCustomization.currentParts
            lockedShipTapped = nil
        }
        .onAppear {
            BoatCustomization.updatePassState(voyagePass.isActive)
            boatParts = BoatCustomization.currentParts
        }
    }

    private var topControls: some View {
        VStack(spacing: 12) {
            ZStack {
                Text(mode == .boat ? "Your boat" : "Your navigator")
                    .font(LFFont.copy(21))
                    .fontWeight(.medium)
                    .foregroundStyle(LFColor.paper)

                HStack {
                    backButton
                    Spacer()
                    resetCameraButton
                }
            }

            HStack(spacing: 4) {
                modeChip("Boat", .boat)
                modeChip("Navigator", .navigator)
            }
            .padding(4)
            .background(Color(hex: 0x071C19).opacity(0.66), in: Capsule())
            .overlay(Capsule().stroke(LFColor.harborSand.opacity(0.18), lineWidth: 1))

            Text("Drag to look around.")
                .font(LFFont.label(12))
                .foregroundStyle(LFColor.paper.opacity(0.72))
                .padding(.horizontal, 12)
                .frame(minHeight: 28)
                .background(Color(hex: 0x071C19).opacity(0.52), in: Capsule())
        }
        .padding(.horizontal, 18)
        .safeAreaPadding(.top, 10)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
    }

    private var backButton: some View {
        Button {
            Haptics.tap(.light)
            if let onClose {
                onClose()
            } else {
                dismiss()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                Text("Back")
                    .font(LFFont.label(13))
            }
            .foregroundStyle(LFColor.paper.opacity(0.92))
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Color(hex: 0x071C19).opacity(0.68), in: Capsule())
            .overlay(Capsule().stroke(LFColor.harborSand.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(LFPressableButtonStyle(scale: 0.94))
        .accessibilityLabel(Text("Back"))
    }

    private var resetCameraButton: some View {
        Button {
            cameraResetToken &+= 1
            Haptics.tap(.light)
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LFColor.paper.opacity(0.90))
                .frame(width: 42, height: 42)
                .background(Color(hex: 0x071C19).opacity(0.68), in: Circle())
                .overlay(Circle().stroke(LFColor.harborSand.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(LFPressableButtonStyle(scale: 0.92))
        .accessibilityLabel(Text("Reset view"))
    }

    private var controlPanel: some View {
        Group {
            if mode == .navigator {
                navigatorControls
            } else {
                boatControls
            }
        }
        .frame(maxWidth: 680)
        // 船は「どの船か」と「帆の色」の二段になる。航海士は一段のまま。
        .frame(height: mode == .boat ? 246 : 164)
        .background(Color(hex: 0x071C19).opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(LFColor.harborSand.opacity(0.22), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .safeAreaPadding(.bottom, 8)
    }

    private var navigatorControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pose")
                .font(LFFont.label(13))
                .tracking(1)
                .foregroundStyle(LFColor.paper.opacity(0.58))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PhoenixPose.selectableCases) { pose in
                        poseChip(pose)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollClipDisabled()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var boatControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Ship")
                    .font(LFFont.label(13))
                    .tracking(1)
                    .foregroundStyle(LFColor.paper.opacity(0.58))

                Spacer(minLength: 8)

                shipHint
                    .font(LFFont.label(12))
                    .foregroundStyle(LFColor.paper.opacity(0.52))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ShipCatalog.all) { ship in
                        shipChip(ship)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollClipDisabled()

            Text("Sail color")
                .font(LFFont.label(13))
                .tracking(1)
                .foregroundStyle(LFColor.paper.opacity(0.58))
                .padding(.top, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BoatCustomization.sailColors) { option in
                        sailColorButton(option)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollClipDisabled()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    /// 見出しの右は、いま選んでいる船の一行紹介。鍵の掛かった船を
    /// 触ったときだけ、開く条件へ差し替わる。
    private var shipHint: Text {
        if let locked = lockedShipTapped {
            return shipLockText(locked)
        }
        return Text(BoatCustomization.effectiveSelectedShip.summary)
    }

    private func shipChip(_ ship: ShipDesign) -> some View {
        let selected = boatParts.shipID == ship.id
        // 進水済みの船は鍵を外して見せる。記録を削ってレベルが下がっても
        // 取り上げない決まりなので、いま乗っている船に錠前を描くと嘘になる。
        let lockReason = ShipUnlockPolicy.lockReason(
            requiredLevel: ship.unlockLevel,
            requiresVoyagePass: ship.requiresVoyagePass,
            playerLevel: levelProgress.level,
            hasVoyagePass: voyagePass.isActive,
            alreadySelected: selected
        )
        let unlocked = lockReason == nil
        return Button {
            guard let lockReason else {
                selectShip(ship)
                return
            }
            if lockReason == .voyagePass {
                showingVoyagePass = true
                Haptics.tap(.medium)
            } else {
                withAnimation(.easeOut(duration: 0.18)) { lockedShipTapped = ship }
                Haptics.error()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: unlocked ? ship.symbolName : "lock.fill")
                    .font(.system(size: unlocked ? 14 : 11, weight: .semibold))
                    .foregroundStyle(chipForeground(selected: selected, unlocked: unlocked))

                Text(ship.title)
                    .font(LFFont.copy(14))
                    .foregroundStyle(chipForeground(selected: selected, unlocked: unlocked))

                if !unlocked {
                    Text(verbatim: lockReason == .voyagePass ? "PASS" : "LV\(ship.unlockLevel)")
                        .font(LFFont.label(11))
                        .foregroundStyle(LFColor.harborSand.opacity(0.82))
                }
            }
            .padding(.horizontal, 15)
            .frame(height: 46)
            .background(Capsule().fill(selected ? LFColor.coral : LFColor.paper.opacity(0.06)))
            .overlay(
                Capsule()
                    .strokeBorder(
                        selected ? LFColor.coral : LFColor.harborSand.opacity(0.16),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(LFPressableButtonStyle(scale: 0.96))
        .accessibilityLabel(Text(ship.title))
        .accessibilityHint(
            unlocked
                ? Text(ship.summary)
                : shipLockText(ship)
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func chipForeground(selected: Bool, unlocked: Bool) -> Color {
        if selected { return LFColor.midnight }
        return LFColor.paper.opacity(unlocked ? 0.78 : 0.44)
    }

    private func selectShip(_ ship: ShipDesign) {
        guard boatParts.shipID != ship.id else { return }
        BoatCustomization.selectShip(ship.id)
        boatParts = BoatCustomization.currentParts
        lockedShipTapped = nil
        Haptics.tap(.light)
        Task { await PrivateIslandService.shared.publishProfileToJoinedIslands() }
        PublicHarborService.shared.pushProfile()
    }

    private func shipLockText(_ ship: ShipDesign) -> Text {
        if ship.requiresVoyagePass, !voyagePass.isActive {
            return Text("Opens with a Voyage Pass")
        }
        return Text(verbatim: LF.format("Unlocks at Level %lld", Int64(ship.unlockLevel)))
    }

    private func modeChip(_ title: LocalizedStringKey, _ value: Mode) -> some View {
        let selected = mode == value
        return Button {
            guard mode != value else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                mode = value
            }
            Haptics.tap(.light)
        } label: {
            Text(title)
                .font(LFFont.copy(14))
                .foregroundStyle(selected ? LFColor.midnight : LFColor.paper.opacity(0.72))
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Capsule().fill(selected ? LFColor.coral : Color.clear))
        }
        .buttonStyle(LFPressableButtonStyle(scale: 0.97))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func poseChip(_ pose: PhoenixPose) -> some View {
        let selected = navPose == pose
        return Button {
            navPose = pose
            PhoenixPose.selected = pose
            Haptics.tap(.light)
        } label: {
            Text(pose.title)
                .font(LFFont.copy(14))
                .foregroundStyle(selected ? LFColor.midnight : LFColor.paper.opacity(0.78))
                .padding(.horizontal, 15)
                .frame(height: 46)
                .background(Capsule().fill(selected ? LFColor.coral : LFColor.paper.opacity(0.06)))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            selected ? LFColor.coral : LFColor.harborSand.opacity(0.16),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(LFPressableButtonStyle(scale: 0.96))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func sailColorButton(_ option: SailColorOption) -> some View {
        let selected = BoatCustomization.selectedSailID == option.id
        return Button {
            BoatCustomization.selectSail(option.id)
            boatParts = BoatCustomization.currentParts
            Haptics.tap(.light)
            Task { await PrivateIslandService.shared.publishProfileToJoinedIslands() }
            PublicHarborService.shared.pushProfile()
        } label: {
            VStack(spacing: 5) {
                Circle()
                    .fill(option.color)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LFColor.harborSand,
                                lineWidth: selected ? 2.5 : 0
                            )
                    )

                Text(option.title)
                    .font(LFFont.label(11))
                    .foregroundStyle(LFColor.paper.opacity(selected ? 0.94 : 0.66))
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
            .frame(width: 72)
            .frame(height: 72)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? LFColor.coral.opacity(0.14) : LFColor.paper.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        selected ? LFColor.coral : LFColor.harborSand.opacity(0.12),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(LFPressableButtonStyle(scale: 0.96))
        .accessibilityLabel(Text(option.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// CSS の flex-wrap と同じく、幅の違うピルを左から自然に折り返す。
private struct DressFlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let availableWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedX = x == 0 ? size.width : x + horizontalSpacing + size.width
            if x > 0, proposedX > availableWidth {
                y += rowHeight + verticalSpacing
                x = size.width
                rowHeight = size.height
            } else {
                x = proposedX
                rowHeight = max(rowHeight, size.height)
            }
            widest = max(widest, x)
        }

        return CGSize(
            width: proposal.width ?? widest,
            height: subviews.isEmpty ? 0 : y + rowHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX,
               x + horizontalSpacing + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            } else if x > bounds.minX {
                x += horizontalSpacing
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}
