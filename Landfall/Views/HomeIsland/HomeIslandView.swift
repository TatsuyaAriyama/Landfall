import SwiftUI
import SwiftData

/// Resolves the current local/Firebase owner before creating an owner-scoped store.
struct HomeIslandEntryView: View {
    @EnvironmentObject private var auth: AuthService
    @Query private var sessions: [StudySession]

    var body: some View {
        HomeIslandView(
            ownerID: auth.homeIslandOwnerID,
            levelProgress: PlayerLevelProgress(sessions: sessions)
        )
            .id(auth.homeIslandOwnerID)
    }
}

struct HomeIslandView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: HomeIslandStore
    @State private var placementAssetID: String?
    @State private var movingSelection = false
    @State private var showingSizeControls = false
    @State private var lockedAssetID: String?
    @State private var cameraResetToken = 0

    private let assets = HomeIslandAssetCatalog.available()
    private let levelProgress: PlayerLevelProgress

    init(ownerID: String, levelProgress: PlayerLevelProgress) {
        self.levelProgress = levelProgress
        _store = StateObject(wrappedValue: HomeIslandStore(ownerID: ownerID))
    }

    var body: some View {
        ZStack {
            HomeIslandSceneView(
                store: store,
                placementAssetID: placementAssetID,
                movingSelection: movingSelection,
                playerLevel: levelProgress.level,
                cameraResetToken: cameraResetToken,
                onMoveCompleted: { movingSelection = false }
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                modeHint
                    .padding(.top, 10)
                Spacer(minLength: 84)
                if store.selectedPlacement != nil, placementAssetID == nil {
                    VStack(spacing: 7) {
                        if showingSizeControls {
                            sizeControls
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        selectionActions
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 9)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                assetShelf
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.18), value: store.selectedID)
        .animation(.easeOut(duration: 0.18), value: placementAssetID)
        .onChange(of: placementAssetID) { _, value in
            if value != nil {
                movingSelection = false
                showingSizeControls = false
            }
        }
        .onChange(of: store.selectedID) { _, value in
            if value == nil { showingSizeControls = false }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
                Haptics.tap(.light)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.38), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(LFPressableButtonStyle())
            .accessibilityLabel(Text("Close"))

            HStack(spacing: 10) {
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(uiColor: VoyageSceneKit.sand))
                VStack(alignment: .leading, spacing: 1) {
                    Text("My Island")
                        .font(LFFont.copy(17))
                        .foregroundStyle(.white)
                    Text(
                        verbatim: LF.format(
                            "Level %lld · %lld objects",
                            Int64(levelProgress.level),
                            Int64(store.placements.count)
                        )
                    )
                        .font(LFFont.label(11))
                        .foregroundStyle(.white.opacity(0.56))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(.black.opacity(0.38), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.13), lineWidth: 1))

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                Image(systemName: store.lastSaveSucceeded ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill")
                    .foregroundStyle(store.lastSaveSucceeded ? Color(uiColor: VoyageSceneKit.sand) : .orange)
                    .accessibilityLabel(Text(store.lastSaveSucceeded ? "Saved" : "Could not save"))

                Button {
                    store.undo()
                    movingSelection = false
                    showingSizeControls = false
                    Haptics.tap(.light)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(store.canUndo ? 1 : 0.30))
                        .frame(width: 36, height: 40)
                }
                .buttonStyle(LFPressableButtonStyle())
                .disabled(!store.canUndo)
                .accessibilityLabel(Text("Undo"))

                Button {
                    cameraResetToken &+= 1
                    Haptics.tap(.light)
                } label: {
                    Image(systemName: "view.3d")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(LFPressableButtonStyle())
                .accessibilityLabel(Text("Reset view"))
            }
            .padding(.leading, 12)
            .padding(.trailing, 5)
            .frame(height: 48)
            .background(.black.opacity(0.38), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.13), lineWidth: 1))
        }
        .padding(.horizontal, 12)
        .safeAreaPadding(.top, 8)
    }

    @ViewBuilder
    private var modeHint: some View {
        if let lockedAssetID,
           let asset = HomeIslandAssetCatalog.asset(id: lockedAssetID) {
            hintPill(
                symbol: "lock.fill",
                text: LF.format("Unlocks at Level %lld", Int64(asset.unlockLevel)),
                actionTitle: String(localized: "OK")
            ) {
                self.lockedAssetID = nil
            }
        } else if let placementAssetID,
           let asset = HomeIslandAssetCatalog.asset(id: placementAssetID) {
            hintPill(
                symbol: "hand.tap.fill",
                text: LF.format("Tap the sand to place %@", asset.title),
                actionTitle: String(localized: "Done")
            ) {
                let recentlyPlacedID = store.selectedID
                self.placementAssetID = nil
                DispatchQueue.main.async {
                    store.select(recentlyPlacedID)
                }
            }
        } else if movingSelection {
            hintPill(
                symbol: "arrow.up.and.down.and.arrow.left.and.right",
                text: String(localized: "Tap the new place on the sand"),
                actionTitle: String(localized: "Cancel")
            ) {
                movingSelection = false
            }
        } else {
            Text("One finger orbits, two fingers pan, and pinch zooms.")
                .font(LFFont.label(11))
                .foregroundStyle(.white.opacity(0.70))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(.black.opacity(0.30), in: Capsule())
        }
    }

    private func hintPill(
        symbol: String,
        text: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(Color(uiColor: VoyageSceneKit.sand))
            Text(verbatim: text)
                .font(LFFont.label(12))
                .foregroundStyle(.white)
                .lineLimit(1)
            Button(actionTitle, action: action)
                .font(LFFont.label(12))
                .foregroundStyle(Color(uiColor: VoyageSceneKit.sand))
        }
        .padding(.horizontal, 13)
        .frame(height: 38)
        .background(.black.opacity(0.50), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
    }

    private var selectionActions: some View {
        HStack(spacing: 5) {
            actionButton("Move", symbol: "arrow.up.and.down.and.arrow.left.and.right") {
                movingSelection = true
                showingSizeControls = false
            }
            actionButton("Rotate", symbol: "rotate.right") {
                store.rotateSelected()
            }
            actionButton("Size", symbol: "arrow.up.left.and.arrow.down.right") {
                showingSizeControls.toggle()
            }
            actionButton(
                "Duplicate",
                symbol: "plus.square.on.square",
                disabled: !canDuplicateSelection
            ) {
                _ = store.duplicateSelected(playerLevel: levelProgress.level)
                showingSizeControls = false
            }
            actionButton("Remove", symbol: "trash.fill", destructive: true) {
                store.deleteSelected()
                movingSelection = false
                showingSizeControls = false
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private func actionButton(
        _ title: LocalizedStringKey,
        symbol: String,
        destructive: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            Haptics.tap(.light)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(LFFont.label(10))
                    .lineLimit(1)
            }
            .foregroundStyle(destructive ? Color.red.opacity(0.9) : .white.opacity(0.88))
            .opacity(disabled ? 0.34 : 1)
            .frame(maxWidth: .infinity, minHeight: 49)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(LFPressableButtonStyle())
        .disabled(disabled)
    }

    private var canDuplicateSelection: Bool {
        guard store.canAdd,
              let selected = store.selectedPlacement,
              let asset = HomeIslandAssetCatalog.asset(id: selected.assetID)
        else { return false }
        return levelProgress.unlocks(requiredLevel: asset.unlockLevel)
    }

    @ViewBuilder
    private var sizeControls: some View {
        if let selected = store.selectedPlacement {
            HStack(spacing: 12) {
                Button {
                    store.resizeSelected(by: -0.10)
                    Haptics.tap(.light)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 42, height: 38)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(LFPressableButtonStyle())
                .disabled(selected.transform.scale <= 0.25)
                .accessibilityLabel(Text("Smaller"))

                VStack(spacing: 1) {
                    Text("Size")
                        .font(LFFont.label(10))
                        .foregroundStyle(.white.opacity(0.55))
                    Text(verbatim: "\(Int((selected.transform.scale * 100).rounded()))%")
                        .font(LFFont.copy(15))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)

                Button {
                    store.resizeSelected(by: 0.10)
                    Haptics.tap(.light)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 42, height: 38)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(LFPressableButtonStyle())
                .disabled(selected.transform.scale >= 2)
                .accessibilityLabel(Text("Larger"))
            }
            .foregroundStyle(.white)
            .padding(6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
        }
    }

    private var assetShelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Place an asset")
                        .font(LFFont.copy(14))
                        .foregroundStyle(.white)
                    Text("Choose one, then tap anywhere on your island")
                        .font(LFFont.label(10))
                        .foregroundStyle(.white.opacity(0.52))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(
                        verbatim: LF.format(
                            "%@ to Level %lld",
                            LF.duration(minutes: levelProgress.minutesToNextLevel),
                            Int64(levelProgress.level + 1)
                        )
                    )
                    .font(LFFont.label(9))
                    .foregroundStyle(.white.opacity(0.58))
                    ProgressView(value: levelProgress.fractionToNextLevel)
                        .tint(Color(uiColor: VoyageSceneKit.sand))
                        .frame(width: 72)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(assets) { asset in
                        assetButton(asset)
                    }
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 11)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.13))
                .frame(height: 1)
        }
        .safeAreaPadding(.bottom, 3)
    }

    private func assetButton(_ asset: HomeIslandAsset) -> some View {
        let selected = placementAssetID == asset.id
        let unlocked = levelProgress.unlocks(requiredLevel: asset.unlockLevel)
        return Button {
            if unlocked {
                lockedAssetID = nil
                placementAssetID = selected ? nil : asset.id
                store.select(nil)
                Haptics.tap(.light)
            } else {
                placementAssetID = nil
                movingSelection = false
                lockedAssetID = asset.id
                Haptics.tap(.medium)
            }
        } label: {
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: asset.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            unlocked
                                ? (selected ? Color(uiColor: VoyageSceneKit.sand) : .white.opacity(0.78))
                                : .white.opacity(0.30)
                        )
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(selected ? 0.13 : 0.07), in: RoundedRectangle(cornerRadius: 10))
                    if !unlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(uiColor: VoyageSceneKit.sand))
                            .padding(3)
                            .background(.black.opacity(0.72), in: Circle())
                            .offset(x: 3, y: 3)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: asset.title)
                        .font(LFFont.label(11))
                        .foregroundStyle(.white.opacity(unlocked ? (selected ? 1 : 0.74) : 0.38))
                        .lineLimit(1)
                    if !unlocked {
                        Text(verbatim: LF.format("Level %lld", Int64(asset.unlockLevel)))
                            .font(LFFont.label(9))
                            .foregroundStyle(Color(uiColor: VoyageSceneKit.sand).opacity(0.72))
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 48)
            .background(
                selected ? Color(uiColor: VoyageSceneKit.ember).opacity(0.20) : .white.opacity(unlocked ? 0.055 : 0.025),
                in: RoundedRectangle(cornerRadius: 13)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(selected ? Color(uiColor: VoyageSceneKit.sand).opacity(0.42) : .white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(LFPressableButtonStyle())
        .disabled(!store.canAdd && unlocked)
        .accessibilityHint(
            unlocked
                ? Text("Tap the sand to place this asset")
                : Text(verbatim: LF.format("Unlocks at Level %lld", Int64(asset.unlockLevel)))
        )
    }
}
