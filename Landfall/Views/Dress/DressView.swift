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
    @State private var controlContentHeight: CGFloat = 0
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
            GeometryReader { geometry in
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

                    VStack(spacing: 0) {
                        topControls
                        Spacer(minLength: 16)
                        controlPanel(maximumHeight: max(120, geometry.size.height * 0.48))
                    }
                }
                .background(Color(hex: 0x123830).ignoresSafeArea())
            }
        }
        .tint(LFHomeFeatureStyle.ink)
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
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                backButton
                HStack(spacing: 4) {
                    modeChip("Boat", .boat)
                    modeChip("Navigator", .navigator)
                }
                .padding(4)
                .lfHomeFeatureCard(cornerRadius: 28)
                resetCameraButton
            }

            Text("Drag to look around.")
                .font(LFFont.label(12))
                .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .lfHomeFeatureCard(cornerRadius: 16)
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
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(LFHomeFeatureStyle.ink)
                .frame(width: 44, height: 44)
                .lfHomeFeatureCard(cornerRadius: 22)
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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(LFHomeFeatureStyle.ink)
                .frame(width: 44, height: 44)
                .lfHomeFeatureCard(cornerRadius: 22)
        }
        .buttonStyle(LFPressableButtonStyle(scale: 0.92))
        .accessibilityLabel(Text("Reset view"))
    }

    private func controlPanel(maximumHeight: CGFloat) -> some View {
        ScrollView {
            controlContent
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: DressControlPanelHeightKey.self,
                            value: geometry.size.height
                        )
                    }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: 680)
        .frame(height: min(controlContentHeight > 0 ? controlContentHeight : maximumHeight, maximumHeight))
        .onPreferenceChange(DressControlPanelHeightKey.self) { height in
            if abs(controlContentHeight - height) > 0.5 {
                controlContentHeight = height
            }
        }
        .lfHomeFeatureCard(cornerRadius: 26)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 12)
        .safeAreaPadding(.bottom, 8)
    }

    private var controlContent: some View {
        Group {
            if mode == .navigator {
                navigatorControls
            } else {
                boatControls
            }
        }
    }

    private var navigatorControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pose")
                .font(LFFont.label(13))
                .foregroundStyle(LFHomeFeatureStyle.secondaryInk)

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
        .padding(.vertical, 16)
    }

    private var boatControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ship")
                .font(LFFont.label(13))
                .foregroundStyle(LFHomeFeatureStyle.secondaryInk)

            if let lockedShipTapped {
                shipLockText(lockedShipTapped)
                    .font(LFFont.label(12))
                    .foregroundStyle(LFHomeFeatureStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
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
                .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
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
        .padding(.vertical, 16)
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
                Image(systemName: selected ? "checkmark" : (unlocked ? ship.symbolName : "lock.fill"))
                    .font(.system(size: unlocked ? 14 : 11, weight: .medium))
                    .foregroundStyle(chipForeground(selected: selected, unlocked: unlocked))

                Text(ship.title)
                    .font(LFFont.copy(14))
                    .foregroundStyle(chipForeground(selected: selected, unlocked: unlocked))

                if !unlocked {
                    Text(verbatim: lockReason == .voyagePass ? "PASS" : "LV\(ship.unlockLevel)")
                        .font(LFFont.label(11))
                        .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .frame(minHeight: 46)
            .background(Capsule().fill(selected ? LFHomeFeatureStyle.primaryFill : LFHomeFeatureStyle.field))
            .overlay(
                Capsule()
                    .strokeBorder(
                        selected ? LFHomeFeatureStyle.primaryFill : LFHomeFeatureStyle.outline,
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
        if selected { return .white }
        return unlocked ? LFHomeFeatureStyle.ink : LFHomeFeatureStyle.secondaryInk
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
                .foregroundStyle(selected ? Color.white : LFHomeFeatureStyle.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(Capsule().fill(selected ? LFHomeFeatureStyle.primaryFill : Color.clear))
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
                .foregroundStyle(selected ? Color.white : LFHomeFeatureStyle.ink)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .frame(minHeight: 46)
                .background(Capsule().fill(selected ? LFHomeFeatureStyle.primaryFill : LFHomeFeatureStyle.field))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            selected ? LFHomeFeatureStyle.primaryFill : LFHomeFeatureStyle.outline,
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
                                selected ? LFHomeFeatureStyle.ink : LFHomeFeatureStyle.outline,
                                lineWidth: selected ? 2.5 : 1
                            )
                    )
                    .overlay {
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(LFHomeFeatureStyle.ink)
                                .frame(width: 20, height: 20)
                                .background(.white.opacity(0.9), in: Circle())
                        }
                    }

                Text(option.title)
                    .font(LFFont.label(11))
                    .foregroundStyle(selected ? LFHomeFeatureStyle.ink : LFHomeFeatureStyle.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 72)
            .frame(minHeight: 72)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? LFHomeFeatureStyle.ink.opacity(0.12) : LFHomeFeatureStyle.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        selected ? LFHomeFeatureStyle.ink.opacity(0.5) : LFHomeFeatureStyle.outline,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(LFPressableButtonStyle(scale: 0.96))
        .accessibilityLabel(Text(option.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct DressControlPanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
