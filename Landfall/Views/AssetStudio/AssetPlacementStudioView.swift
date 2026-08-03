import SwiftUI
import UIKit

/// USDZをゲーム空間へ追加し、指と数値スライダーで配置するフルスクリーン編集画面。
struct AssetPlacementStudioView: View {
    var homeProgressRatio: Double = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: AuthService
    @StateObject private var store = AssetPlacementStore()
    @State private var activePanel: StudioPanel?
    @State private var panelOnLeading = false
    @State private var inspectorSection: InspectorSection = .position
    @State private var confirmingDelete = false
    @State private var confirmingClearTerrain = false
    @State private var toastMessage: String?
    @State private var modeHelpExpanded = false
    @State private var showingNewStudioPrompt = false
    @State private var showingRenameStudioPrompt = false
    @State private var studioNameDraft = ""

    private enum InspectorSection: String, CaseIterable, Identifiable {
        case position
        case rotation
        case scale

        var id: String { rawValue }
    }

    private enum StudioPanel: Equatable {
        case assets
        case inspector
    }

    var body: some View {
        Group {
            if AccessPolicy.canUseAssetStudio(auth.user) {
                studioContent
            } else {
                Color.clear
                    .ignoresSafeArea()
                    .onAppear { dismiss() }
            }
        }
    }

    private var studioContent: some View {
        ZStack {
            AssetPlacementSceneView(
                store: store,
                homeProgressRatio: homeProgressRatio
            )
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                HStack(alignment: .top, spacing: 8) {
                    modeCoach
                    Spacer(minLength: 0)
                    homeShipReferenceButton
                }
                .padding(.top, 7)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            if let activePanel {
                sidePanel(activePanel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: panelOnLeading ? .leading : .trailing)
                    .padding(.top, 68)
                    .padding(.bottom, 72)
                    .padding(.leading, panelOnLeading ? 10 : 0)
                    .padding(.trailing, panelOnLeading ? 0 : 10)
                    .transition(.scale(scale: 0.96, anchor: panelOnLeading ? .leading : .trailing).combined(with: .opacity))
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                canvasToolbar
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 7)

            if let toastMessage {
                Text(toastMessage)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 42)
                    .background(.black.opacity(0.72), in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 76)
                    .allowsHitTesting(false)
            }
        }
        .background(Color(uiColor: VoyageSceneKit.nightBG))
        .preferredColorScheme(.dark)
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelection() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteConfirmationDetail)
        }
        .confirmationDialog(
            "Clear all terrain?",
            isPresented: $confirmingClearTerrain,
            titleVisibility: .visible
        ) {
            Button("Clear terrain", role: .destructive) {
                store.clearVisibleTerrain()
                Haptics.tap(.medium)
                showToast(String(localized: "Terrain cleared"))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every terrain stroke in the current world. You can undo it afterward.")
        }
        .alert("New Studio", isPresented: $showingNewStudioPrompt) {
            TextField("Studio name", text: $studioNameDraft)
            Button("Create") {
                store.createStudio(named: studioNameDraft)
                store.manipulationMode = .move
                showToast(String(localized: "New studio created"))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Create an empty workspace and save it as a reusable asset.")
        }
        .alert("Rename Studio", isPresented: $showingRenameStudioPrompt) {
            TextField("Studio name", text: $studioNameDraft)
            Button("Save") {
                let renamed = store.renameCurrentStudio(to: studioNameDraft)
                showToast(String(localized: renamed ? "Studio name saved" : "Could not save"))
            }
            .disabled(studioNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["LANDFALL_ASSET_STUDIO_CAMERA"] == "1" {
                store.manipulationMode = .camera
            }
            if ProcessInfo.processInfo.environment["LANDFALL_ASSET_STUDIO_SELECT"] == "1" {
                store.manipulationMode = .select
            }
            if ProcessInfo.processInfo.environment["LANDFALL_ASSET_STUDIO_PAINT"] == "1" {
                store.setContext(.studio)
                store.manipulationMode = .paint
            }
            if ProcessInfo.processInfo.environment["LANDFALL_ASSET_STUDIO_PANEL"] == "assets" {
                activePanel = .assets
            } else if ProcessInfo.processInfo.environment["LANDFALL_ASSET_STUDIO_PANEL"] == "details" {
                activePanel = .inspector
            }
            if ProcessInfo.processInfo.environment["LANDFALL_ASSET_STUDIO_COLLISION"] == "1" {
                store.setContext(.studio)
                let foundationID = store.add(assetID: "island_base")
                store.updatePlacement(id: foundationID) { placement in
                    placement.transform = AssetTransform(x: 0, y: 0, z: 0, scale: 1)
                }
                let treeID = store.add(assetID: "small_tree")
                store.updatePlacement(id: treeID) { placement in
                    placement.transform = AssetTransform(x: 0, y: 0, z: 0, scale: 1)
                }
                store.select(treeID)
                store.requestSurfaceSnap()
            }
            if ProcessInfo.processInfo.environment["LANDFALL_ASSET_STUDIO_MULTISELECT"] == "1" {
                store.setContext(.studio)
                let firstID = store.add(assetID: "small_tree")
                store.updatePlacement(id: firstID) { placement in
                    placement.transform = AssetTransform(x: -1.15, y: 0, z: 0, scale: 0.72)
                }
                let secondID = store.add(assetID: "small_tree")
                store.updatePlacement(id: secondID) { placement in
                    placement.transform = AssetTransform(x: 1.05, y: 0, z: 0.15, scale: 0.82)
                }
                store.select([firstID, secondID], primary: firstID)
                store.manipulationMode = .select
            }
            #endif
        }
        .onDisappear {
            store.endInteractiveEdit()
            store.save()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            // ホームへ戻る・ロック・バックグラウンド化の全経路で編集中の点列まで確定する。
            store.endInteractiveEdit()
            store.save()
        }
    }

    private var topBar: some View {
        HStack(spacing: 7) {
            studioIconButton(symbol: "xmark", accessibilityLabel: "Close") {
                store.endInteractiveEdit()
                store.save()
                dismiss()
            }

            Menu {
                Button {
                    store.setContext(.destinationIsland)
                } label: {
                    Label("Destination island", systemImage: "mountain.2.fill")
                }

                Section("Saved Studios") {
                    ForEach(store.studios) { studio in
                        Button {
                            store.selectStudio(studio.id)
                        } label: {
                            Label(
                                studio.name,
                                systemImage: store.activeStudioID == studio.id
                                    ? "checkmark.circle.fill"
                                    : "square.3.layers.3d"
                            )
                        }
                    }
                }

                if store.context == .studio {
                    Button {
                        studioNameDraft = store.currentStudio?.name ?? ""
                        showingRenameStudioPrompt = true
                    } label: {
                        Label("Rename Studio", systemImage: "pencil")
                    }
                }

                Divider()

                Button {} label: {
                    Label(saveStatusText, systemImage: saveStatusSymbol)
                }
                .disabled(true)

                Button {
                    studioNameDraft = String(
                        format: String(localized: "Studio %lld"),
                        Int64(store.studios.count + 1)
                    )
                    showingNewStudioPrompt = true
                } label: {
                    Label("New Studio", systemImage: "plus.square.on.square")
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: store.context == .destinationIsland ? "mountain.2.fill" : "square.3.layers.3d")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(uiColor: VoyageSceneKit.ember))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("3D Studio")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        HStack(spacing: 4) {
                            Text(
                                store.context == .destinationIsland
                                    ? String(localized: "Island")
                                    : store.currentStudio?.name ?? String(localized: "Studio")
                            )
                            .lineLimit(1)
                            Image(systemName: saveStatusSymbol)
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(saveStatusColor)
                        }
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .frame(minHeight: 46)
                .background(.black.opacity(0.54), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
            }
            .accessibilityValue(saveStatusText)

            Spacer(minLength: 2)

            studioIconButton(
                symbol: "arrow.uturn.backward",
                accessibilityLabel: "Undo",
                disabled: !store.canUndo
            ) { store.undo() }
            .accessibilityHint("Undo the last edit")

            studioIconButton(
                symbol: "arrow.uturn.forward",
                accessibilityLabel: "Redo",
                disabled: !store.canRedo
            ) { store.redo() }
            .accessibilityHint("Redo the last undone edit")

            Menu {
                Button {
                    store.requestCamera(.reset)
                } label: {
                    Label("Reset view", systemImage: "rectangle.3.group")
                }
                Button {
                    store.requestCamera(.overview)
                } label: {
                    Label("World overview", systemImage: "map.fill")
                }
                Button {
                    store.requestCamera(.focusSelection)
                } label: {
                    Label("Focus selected", systemImage: "scope")
                }
                .disabled(store.selectionCount == 0)

                Button {
                    duplicateSelected()
                } label: {
                    Label("Duplicate selected", systemImage: "plus.square.on.square")
                }
                .disabled(store.selectedPlacement == nil || store.selectionCount != 1)

                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete selected", systemImage: "trash")
                }
                .disabled(store.selectionCount == 0)

                Divider()

                if store.context == .studio {
                    Button {
                        store.saveCurrentStudio()
                        showToast(String(localized: store.lastSaveSucceeded ? "Studio saved and applied to game" : "Could not save"))
                    } label: {
                        Label("Save & Apply to Game", systemImage: "checkmark.icloud.fill")
                    }

                    Button {
                        studioNameDraft = store.currentStudio?.name ?? ""
                        showingRenameStudioPrompt = true
                    } label: {
                        Label("Rename Studio", systemImage: "pencil")
                    }

                    Button {
                        useCurrentStudioInGame()
                    } label: {
                        Label("Use as Game World", systemImage: "globe.americas.fill")
                    }
                    .disabled(!store.currentStudioHasContent)

                    Divider()
                }

                Button {
                    store.save()
                    showToast(String(localized: store.lastSaveSucceeded ? "Saved" : "Could not save"))
                } label: {
                    Label("Save", systemImage: "checkmark.circle")
                }
                Button {
                    UIPasteboard.general.string = store.exportJSONString()
                    showToast(String(localized: "Placement JSON copied"))
                } label: {
                    Label("Copy placement JSON", systemImage: "doc.on.doc")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.54), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
            }
            .accessibilityLabel("More actions")
        }
    }

    private var saveStatusSymbol: String {
        if !store.lastSaveSucceeded { return "exclamationmark.triangle.fill" }
        if store.hasUnsavedChanges { return "clock.fill" }
        return "checkmark.circle.fill"
    }

    private var saveStatusColor: Color {
        if !store.lastSaveSucceeded { return Color(uiColor: VoyageSceneKit.coral) }
        if store.hasUnsavedChanges { return Color(uiColor: VoyageSceneKit.ember) }
        return Color(uiColor: UIColor(rgb: 0x8DC8A3))
    }

    private var saveStatusText: String {
        if !store.lastSaveSucceeded { return String(localized: "Save failed — retrying") }
        if store.hasUnsavedChanges { return String(localized: "Saving…") }
        guard let lastSavedAt = store.lastSavedAt else { return String(localized: "Saved") }
        return String(
            format: String(localized: "Saved at %@"),
            lastSavedAt.formatted(date: .omitted, time: .shortened)
        )
    }

    /// キャンバスから目を離さずに、現在モードと次の操作を確認する小さなガイド。
    private var modeCoach: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    modeHelpExpanded.toggle()
                }
                Haptics.tap(.light)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: store.manipulationMode.symbolName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(uiColor: VoyageSceneKit.ember))
                    Text(modeStatusTitle)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.90))
                        .lineLimit(1)
                    Image(systemName: modeHelpExpanded ? "chevron.up" : "questionmark.circle")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.46))
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 30)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            if modeHelpExpanded {
                Text(modeHelpText)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)

                modeQuickActions
                    .padding(.horizontal, 7)
                    .padding(.bottom, 7)
            }
        }
        .frame(maxWidth: modeHelpExpanded ? 246 : 190, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(.black.opacity(0.50), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: VoyageSceneKit.ember).opacity(modeHelpExpanded ? 0.30 : 0.14), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Current tool")
        .accessibilityValue(modeStatusTitle)
    }

    @ViewBuilder
    private var modeQuickActions: some View {
        if store.manipulationMode == .camera {
            HStack(spacing: 5) {
                coachAction("Overview", symbol: "map.fill") { store.requestCamera(.overview) }
                coachAction("Top", symbol: "arrow.down.to.line") { store.requestCamera(.top) }
                if store.selectionCount > 0 {
                    coachAction("Selected", symbol: "scope") { store.requestCamera(.focusSelection) }
                }
            }
        } else if store.manipulationMode == .terrain {
            HStack(spacing: 5) {
                coachTerrainShape(.hill)
                coachTerrainShape(.mountain)
                coachTerrainShape(.ridge)
            }
        } else if store.selectionCount > 0,
                  store.manipulationMode == .move || store.manipulationMode == .height {
            HStack(spacing: 5) {
                coachAction("Snap now", symbol: "arrow.down.to.line.compact") { snapSelectedToSurface() }
                coachAction("Focus selected", symbol: "scope") { store.requestCamera(.focusSelection) }
            }
        }
    }

    private func coachAction(
        _ title: LocalizedStringKey,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            Haptics.tap(.light)
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.70)
                .foregroundStyle(.white.opacity(0.76))
                .frame(maxWidth: .infinity, minHeight: 29)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func coachTerrainShape(_ shape: AssetTerrainShape) -> some View {
        Button {
            store.selectTerrainShape(shape)
            Haptics.tap(.light)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: shape.symbolName)
                Text(terrainShapeTitle(shape))
                    .lineLimit(1)
            }
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(
                store.terrainShape == shape
                    ? Color(uiColor: VoyageSceneKit.nightBG)
                    : .white.opacity(0.72)
            )
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                store.terrainShape == shape
                    ? Color(uiColor: VoyageSceneKit.ember)
                    : .white.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 9)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(terrainShapeTitle(shape))
    }

    private var homeShipReferenceButton: some View {
        Button {
            store.requestCamera(.homeShipMarker)
            Haptics.tap(.medium)
            showToast(String(localized: "Showing the home ship marker"))
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(red: 1, green: 0.24, blue: 0.28))
                    .frame(width: 8, height: 8)
                    .shadow(color: Color.red.opacity(0.75), radius: 4)
                Image(systemName: "sailboat.fill")
                Text("Ship location")
            }
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.90))
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(.black.opacity(0.56), in: Capsule())
            .overlay(Capsule().stroke(Color.red.opacity(0.42), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Find the exact home ship position in the studio")
    }

    private var canvasToolbar: some View {
        VStack(spacing: 5) {
            if store.manipulationMode == .camera {
                cameraTravelBar
            } else if store.manipulationMode == .paint {
                paintPalette
            } else if store.manipulationMode == .terrain {
                terrainPalette
            } else if store.manipulationMode == .place {
                placementPalette
            } else if store.selectionCount > 0 {
                HStack(spacing: 5) {
                    Button {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                            activePanel = activePanel == .inspector ? nil : .inspector
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selectionSymbol)
                                .foregroundStyle(Color(uiColor: VoyageSceneKit.ember))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(verbatim: selectionSummary)
                                    .lineLimit(1)
                                if store.selectionCount > 1 {
                                    Text(verbatim: selectionBreakdown)
                                        .font(.system(size: 8, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.48))
                                        .lineLimit(1)
                                }
                            }
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.84))
                        .padding(.horizontal, 11)
                        .frame(minHeight: store.selectionCount > 1 ? 34 : 28)
                        .background(.black.opacity(0.48), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(selectionSummary)
                    .accessibilityValue(selectionBreakdown)

                    if store.selectionCount == 1, store.selectedPlacement != nil {
                        Button {
                            duplicateSelected()
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(uiColor: VoyageSceneKit.ember))
                                .padding(.horizontal, 10)
                                .frame(minHeight: 28)
                                .background(.black.opacity(0.56), in: Capsule())
                                .overlay(Capsule().stroke(Color(uiColor: VoyageSceneKit.ember).opacity(0.28), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Duplicate selected")
                    }

                    Button {
                        confirmingDelete = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(uiColor: VoyageSceneKit.coral))
                            .frame(width: 30, height: 28)
                            .background(.black.opacity(0.56), in: Capsule())
                            .overlay(Capsule().stroke(Color(uiColor: VoyageSceneKit.coral).opacity(0.30), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete selected")
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if store.manipulationMode == .select {
                Label("Drag across models, paint, or terrain to box-select", systemImage: "rectangle.dashed")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.76))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 28)
                    .background(.black.opacity(0.48), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
            }

            HStack(spacing: 5) {
                canvasToolButton(
                    symbol: "square.grid.2x2.fill",
                    title: "Assets",
                    active: activePanel == .assets || store.manipulationMode == .place,
                    accented: false,
                    badge: store.availableAssetCount,
                    accessibilityHint: "Open the asset library and choose an item to place"
                ) {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                        activePanel = activePanel == .assets ? nil : .assets
                    }
                }

                ForEach(AssetManipulationMode.allCases.filter { $0 != .place }) { mode in
                    canvasToolButton(
                        symbol: mode.symbolName,
                        title: modeTitle(mode),
                        active: store.manipulationMode == mode,
                        accessibilityHint: modeAccessibilityHint(mode)
                    ) {
                        store.manipulationMode = mode
                        modeHelpExpanded = false
                        withAnimation(.easeOut(duration: 0.16)) { activePanel = nil }
                        Haptics.tap(.light)
                        if mode == .select {
                            showToast(String(localized: "Drag across models, paint, or terrain to box-select"))
                        } else if mode == .paint {
                            showToast(String(localized: "Drag on the surface to paint"))
                        } else if mode == .terrain {
                            showToast(String(localized: "Choose a shape, then tap or drag on the terrain"))
                        }
                    }
                }

                canvasToolButton(
                    symbol: "slider.horizontal.3",
                    title: "Details",
                    active: activePanel == .inspector,
                    accented: false,
                    badge: store.visiblePlacements.count,
                    accessibilityHint: "Open object details and precise controls"
                ) {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                        activePanel = activePanel == .inspector ? nil : .inspector
                    }
                }
            }
            .padding(6)
            .frame(maxWidth: 410)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.13), lineWidth: 1))
            .shadow(color: .black.opacity(0.30), radius: 18, y: 7)
        }
    }

    private var cameraTravelBar: some View {
        HStack(spacing: 5) {
            cameraTravelButton(symbol: "arrow.left", label: "Move left", action: .moveLeft)
            cameraTravelButton(symbol: "arrow.up", label: "Move forward", action: .moveForward)
            cameraZoomButton(symbol: "minus.magnifyingglass", label: "Zoom out", action: .zoomOut)
            cameraTravelButton(
                symbol: "sailboat.fill",
                label: "Home ship view",
                action: .homeShipView
            )
            Button {
                store.requestCamera(.overview)
                Haptics.tap(.medium)
            } label: {
                Label("Overview", systemImage: "map.fill")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(uiColor: VoyageSceneKit.nightBG))
                    .padding(.horizontal, 11)
                    .frame(minHeight: 31)
                    .background(Color(uiColor: VoyageSceneKit.ember), in: Capsule())
            }
            .buttonStyle(.plain)
            cameraZoomButton(symbol: "plus.magnifyingglass", label: "Zoom in", action: .zoomIn)
            cameraTravelButton(symbol: "arrow.down", label: "Move backward", action: .moveBackward)
            cameraTravelButton(symbol: "arrow.right", label: "Move right", action: .moveRight)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func cameraTravelButton(
        symbol: String,
        label: LocalizedStringKey,
        action: AssetStudioCameraAction
    ) -> some View {
        Button {
            store.requestCamera(action)
            Haptics.tap(.light)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 38, height: 31)
                .background(.black.opacity(0.52), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func cameraZoomButton(
        symbol: String,
        label: LocalizedStringKey,
        action: AssetStudioCameraAction
    ) -> some View {
        Button {
            store.requestCamera(action)
            Haptics.tap(.light)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(uiColor: VoyageSceneKit.ember))
                .frame(width: 34, height: 31)
                .background(.black.opacity(0.58), in: Capsule())
                .overlay(Capsule().stroke(Color(uiColor: VoyageSceneKit.ember).opacity(0.30), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
        .accessibilityHint("Tap repeatedly or hold to adjust zoom")
    }

    private var paintPalette: some View {
        HStack(spacing: 5) {
            ForEach(AssetPaintTool.allCases) { tool in
                Button {
                    store.paintTool = tool
                    Haptics.tap(.light)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tool.symbolName)
                        Text(paintToolTitle(tool))
                            .lineLimit(1)
                    }
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        store.paintTool == tool
                            ? Color(uiColor: VoyageSceneKit.nightBG)
                            : paintToolColor(tool)
                    )
                    .padding(.horizontal, 9)
                    .frame(minHeight: 31)
                    .background(
                        store.paintTool == tool
                            ? paintToolColor(tool)
                            : Color.black.opacity(0.52),
                        in: Capsule()
                    )
                    .overlay(Capsule().stroke(paintToolColor(tool).opacity(0.34), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(paintToolTitle(tool))
            }

            Button {
                switch store.paintWidth {
                case ..<0.38: store.paintWidth = 0.48
                case ..<0.64: store.paintWidth = 0.78
                default: store.paintWidth = 0.28
                }
                Haptics.tap(.light)
            } label: {
                VStack(spacing: 1) {
                    Image(systemName: "lineweight")
                    Text(String(format: "%.2f", store.paintWidth))
                }
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.74))
                .frame(width: 37, height: 31)
                .background(.black.opacity(0.52), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Brush width")
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var terrainPalette: some View {
        HStack(spacing: 5) {
            Menu {
                ForEach(AssetTerrainShape.allCases) { shape in
                    Button {
                        store.selectTerrainShape(shape)
                        Haptics.tap(.light)
                    } label: {
                        Label(terrainShapeTitle(shape), systemImage: shape.symbolName)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: store.terrainShape.symbolName)
                    Text(terrainShapeTitle(store.terrainShape))
                        .lineLimit(1)
                }
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color(uiColor: VoyageSceneKit.nightBG))
                .padding(.horizontal, 9)
                .frame(minHeight: 31)
                .background(Color(uiColor: VoyageSceneKit.ember), in: Capsule())
            }
            .accessibilityLabel("Terrain shape")

            ForEach(AssetTerrainTool.allCases) { tool in
                Button {
                    store.selectTerrainTool(tool)
                    Haptics.tap(.light)
                } label: {
                    Image(systemName: tool.symbolName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(
                        store.terrainTool == tool
                            ? Color(uiColor: VoyageSceneKit.nightBG)
                            : Color(uiColor: VoyageSceneKit.ember)
                    )
                    .frame(width: 31, height: 31)
                    .background(
                        store.terrainTool == tool
                            ? Color(uiColor: VoyageSceneKit.ember)
                            : Color.black.opacity(0.52),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().stroke(
                            Color(uiColor: VoyageSceneKit.ember).opacity(0.34),
                            lineWidth: 1
                        )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(terrainToolTitle(tool))
            }

            Menu {
                ForEach(AssetTerrainMaterial.allCases) { material in
                    Button {
                        store.terrainMaterial = material
                        Haptics.tap(.light)
                    } label: {
                        Label(terrainMaterialTitle(material), systemImage: material.symbolName)
                    }
                }
            } label: {
                Circle()
                    .fill(Color(uiColor: store.terrainMaterial.color))
                    .frame(width: 17, height: 17)
                    .frame(width: 31, height: 31)
                .background(.black.opacity(0.52), in: Capsule())
                .overlay(Capsule().stroke(Color(uiColor: store.terrainMaterial.color).opacity(0.64), lineWidth: 1))
            }
            .accessibilityLabel("Terrain material")
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var placementPalette: some View {
        HStack(spacing: 7) {
            Image(systemName: "hand.tap.fill")
                .foregroundStyle(Color(uiColor: VoyageSceneKit.ember))
            Text(
                store.placementBrushAssetID.map(Asset3DCatalog.displayName(for:))
                    ?? String(localized: "Asset")
            )
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.88))
            .lineLimit(1)

            Text("Tap repeatedly to place")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)

            Button {
                store.finishPlacementBrush()
                Haptics.tap(.light)
            } label: {
                Text("Done")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(uiColor: VoyageSceneKit.nightBG))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 29)
                    .background(Color(uiColor: VoyageSceneKit.ember), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(minHeight: 35)
        .background(.black.opacity(0.58), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func canvasToolButton(
        symbol: String,
        title: LocalizedStringKey,
        active: Bool,
        accented: Bool = true,
        badge: Int? = nil,
        accessibilityHint: LocalizedStringKey = "",
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 24, height: 18)
                    if let badge, badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundStyle(active && accented ? Color(uiColor: VoyageSceneKit.nightBG) : .white)
                            .padding(.horizontal, 3)
                            .frame(minWidth: 12, minHeight: 12)
                            .background(
                                active && accented ? Color.white.opacity(0.58) : Color(uiColor: VoyageSceneKit.ember),
                                in: Capsule()
                            )
                            .offset(x: 7, y: -5)
                    }
                }
                Text(title)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }
            .foregroundStyle(active && accented ? Color(uiColor: VoyageSceneKit.nightBG) : .white.opacity(active ? 0.94 : 0.70))
            .frame(maxWidth: .infinity, minHeight: 43)
            .background(
                active
                    ? (accented ? Color(uiColor: VoyageSceneKit.ember) : Color.white.opacity(0.15))
                    : Color.white.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }

    private func sidePanel(_ panel: StudioPanel) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: panel == .assets ? "square.grid.2x2.fill" : "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(uiColor: VoyageSceneKit.ember))
                Text(panelTitle(panel))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                        panelOnLeading.toggle()
                    }
                } label: {
                    Image(systemName: "arrow.left.and.right")
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("Move panel")
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { activePanel = nil }
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("Hide panel")
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(0.62))
            .padding(.horizontal, 12)
            .frame(minHeight: 48)

            Divider().overlay(.white.opacity(0.10))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    if panel == .assets {
                        sideAssetLibrary
                    } else {
                        worldContentOverview
                        placedObjects
                        if store.manipulationMode == .paint {
                            paintInspector
                        } else if store.manipulationMode == .terrain {
                            terrainInspector
                        } else if store.manipulationMode == .camera {
                            cameraInspector
                        } else if store.selectionCount > 1
                                    || !store.selectedPaintStrokes.isEmpty
                                    || !store.selectedTerrainStrokes.isEmpty {
                            multiSelectionInspector
                        } else if store.selectedPlacement != nil {
                            selectedInspector
                        } else {
                            emptySelectionHint
                        }
                    }
                }
                .padding(11)
            }
        }
        .frame(width: 252)
        .frame(maxHeight: 590)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(.black.opacity(0.40), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.36), radius: 22, y: 8)
    }

    private var sideAssetLibrary: some View {
        LazyVStack(spacing: 8) {
            if store.context == .destinationIsland,
               !store.studioAssetDescriptors.isEmpty {
                assetLibrarySectionTitle("Game Worlds", symbol: "globe.americas.fill")

                ForEach(store.studioAssetDescriptors) { asset in
                    assetLibraryRow(asset, isSavedStudio: true)
                }

                Divider()
                    .overlay(.white.opacity(0.10))
                    .padding(.vertical, 3)
            }

            assetLibrarySectionTitle("3D Assets", symbol: "cube.transparent.fill")

            if store.catalog.isEmpty {
                Text("No USDZ assets are bundled with this build.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(16)
            }

            ForEach(store.catalog) { asset in
                assetLibraryRow(asset, isSavedStudio: false)
            }
        }
    }

    private func assetLibrarySectionTitle(
        _ title: LocalizedStringKey,
        symbol: String
    ) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.46))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 3)
    }

    private func assetLibraryRow(
        _ asset: Asset3DDescriptor,
        isSavedStudio: Bool
    ) -> some View {
        Button {
            if isSavedStudio,
               let studioID = SavedAssetStudio.id(fromAssetID: asset.id) {
                store.select(nil)
                _ = store.useStudioInGame(studioID)
                store.requestCamera(.overview)
            } else {
                // モデルを選ぶたびに中央へ追加して移動する手間をなくす。
                // 選択後はシーンを何度でもタップし、その場に連続配置できる。
                store.choosePlacementBrush(assetID: asset.id)
            }
            withAnimation(.easeOut(duration: 0.18)) { activePanel = nil }
            Haptics.tap(.medium)
            showToast(
                isSavedStudio
                    ? String(format: String(localized: "%@ is now the game world"), asset.displayName)
                    : String(
                        format: String(localized: "Tap the world to place %@"),
                        asset.displayName
                    )
            )
        } label: {
            HStack(spacing: 9) {
                Image(systemName: asset.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(uiColor: VoyageSceneKit.ember))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.displayName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(isSavedStudio ? "Use everywhere in the game" : "Choose, then tap the world repeatedly")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.42))
                }
                Spacer(minLength: 0)
                Image(systemName: isSavedStudio
                    ? (store.activeStudioID == SavedAssetStudio.id(fromAssetID: asset.id)
                        ? "checkmark.circle.fill"
                        : "globe.americas.fill")
                    : "plus.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                (isSavedStudio ? Color(uiColor: VoyageSceneKit.ember).opacity(0.10) : .white.opacity(0.06)),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSavedStudio
                            ? Color(uiColor: VoyageSceneKit.ember).opacity(0.24)
                            : .white.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var paintInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Surface paint", systemImage: "paintbrush.pointed.fill")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(uiColor: VoyageSceneKit.ember))

            Text("Paint material onto the existing surface without changing its shape. Use two fingers to move the camera.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Paint strokes")
                    .foregroundStyle(.white.opacity(0.48))
                Spacer()
                Text("\(store.visiblePaintStrokes.count)")
                    .foregroundStyle(.white.opacity(0.78))
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))

            HStack {
                Text("Brush width")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
                Slider(
                    value: Binding(
                        get: { Double(store.paintWidth) },
                        set: { store.paintWidth = Float($0) }
                    ),
                    in: 0.18...1.10
                )
                .tint(Color(uiColor: VoyageSceneKit.ember))
                Text(String(format: "%.2f", store.paintWidth))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.68))
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .padding(12)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.06), lineWidth: 1))
    }

    private var terrainInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Terrain sculpt", systemImage: "mountain.2.fill")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color(uiColor: VoyageSceneKit.ember))

            Text("Choose a shape and tap once for an instant landform. Drag Ridge to draw long ranges. Carve and Smooth refine the result.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)

            Text("QUICK SHAPES")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.42))

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2),
                spacing: 6
            ) {
                ForEach(AssetTerrainShape.allCases) { shape in
                    Button {
                        store.selectTerrainShape(shape)
                        Haptics.tap(.light)
                    } label: {
                        Label(terrainShapeTitle(shape), systemImage: shape.symbolName)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                store.terrainShape == shape
                                    ? Color(uiColor: VoyageSceneKit.nightBG)
                                    : .white.opacity(0.72)
                            )
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(
                                store.terrainShape == shape
                                    ? Color(uiColor: VoyageSceneKit.ember)
                                    : .white.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("SURFACE MATERIAL")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.42))

            HStack(spacing: 7) {
                ForEach(AssetTerrainMaterial.allCases) { material in
                    Button {
                        store.terrainMaterial = material
                        Haptics.tap(.light)
                    } label: {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(Color(uiColor: material.color))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle().stroke(
                                        .white.opacity(store.terrainMaterial == material ? 0.9 : 0.12),
                                        lineWidth: store.terrainMaterial == material ? 2 : 1
                                    )
                                )
                            Text(terrainMaterialTitle(material))
                                .font(.system(size: 7, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.62))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                store.recolorVisibleTerrain(to: store.terrainMaterial)
                Haptics.tap(.medium)
                showToast(String(localized: "Applied material to all terrain"))
            } label: {
                Label("Apply to all terrain", systemImage: "paintbrush.fill")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.74))
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(store.visibleTerrainStrokes.isEmpty)

            HStack {
                Text("Terrain strokes")
                    .foregroundStyle(.white.opacity(0.48))
                Spacer()
                Text("\(store.visibleTerrainStrokes.count)")
                    .foregroundStyle(.white.opacity(0.78))
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))

            terrainSlider(
                title: "Brush radius",
                value: Binding(
                    get: { Double(store.terrainRadius) },
                    set: { store.terrainRadius = Float($0) }
                ),
                range: 0.15...3.6
            )
            terrainSlider(
                title: "Strength",
                value: Binding(
                    get: { Double(store.terrainStrength) },
                    set: { store.terrainStrength = Float($0) }
                ),
                range: terrainStrengthRange
            )

            if store.terrainTool == .lower {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Carve a little with each pass. Trace the same place repeatedly to set the exact depth.")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.52))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        ForEach([0.05, 0.10, 0.20], id: \.self) { step in
                            Button {
                                store.terrainStrength = Float(step)
                                Haptics.tap(.light)
                            } label: {
                                Text(String(format: "%.2f m", step))
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(
                                        abs(Double(store.terrainStrength) - step) < 0.005
                                            ? Color(uiColor: VoyageSceneKit.nightBG)
                                            : .white.opacity(0.70)
                                    )
                                    .frame(maxWidth: .infinity, minHeight: 30)
                                    .background(
                                        abs(Double(store.terrainStrength) - step) < 0.005
                                            ? Color(uiColor: VoyageSceneKit.ember)
                                            : .white.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 9)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Button(role: .destructive) {
                confirmingClearTerrain = true
            } label: {
                Label("Clear terrain", systemImage: "trash")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.bordered)
            .tint(Color(uiColor: VoyageSceneKit.coral))
            .disabled(store.visibleTerrainStrokes.isEmpty)
        }
        .padding(12)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.06), lineWidth: 1))
    }

    private func terrainSlider(
        title: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
            Slider(value: value, in: range)
                .tint(Color(uiColor: VoyageSceneKit.ember))
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.68))
                .frame(width: 34, alignment: .trailing)
        }
    }

    private var terrainStrengthRange: ClosedRange<Double> {
        switch store.terrainTool {
        case .lower: return 0.03...0.60
        case .smooth: return 0.05...1.0
        case .raise: return 0.20...3.5
        }
    }

    private var cameraInspector: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("VIEW PRESETS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.48))
                Spacer()
                Text("Double-tap empty space to reset")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.36))
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                spacing: 6
            ) {
                cameraPresetButton("Reset", symbol: "arrow.counterclockwise", action: .reset)
                cameraPresetButton("Overview", symbol: "map.fill", action: .overview)
                cameraPresetButton("Home ship", symbol: "sailboat.fill", action: .homeShipView)
                cameraPresetButton(
                    "Selected",
                    symbol: "scope",
                    action: .focusSelection,
                    disabled: store.selectionCount == 0
                )
                cameraPresetButton("Top", symbol: "arrow.down.to.line", action: .top)
                cameraPresetButton("Front", symbol: "viewfinder", action: .front)
                cameraPresetButton("Side", symbol: "rectangle.split.2x1", action: .side)
                cameraPresetButton("Zoom out", symbol: "minus.magnifyingglass", action: .zoomOut)
                cameraPresetButton("Zoom in", symbol: "plus.magnifyingglass", action: .zoomIn)
            }

            HStack(spacing: 7) {
                cameraGestureHint(symbol: "hand.draw", title: "Orbit", detail: "1 finger")
                cameraGestureHint(symbol: "hand.raised.fill", title: "Pan", detail: "2 fingers")
                cameraGestureHint(symbol: "arrow.up.left.and.arrow.down.right", title: "Zoom", detail: "Pinch")
            }

            #if targetEnvironment(simulator)
            Divider()
                .overlay(.white.opacity(0.08))

            Label("MAC / SIMULATOR", systemImage: "keyboard")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(Color(uiColor: VoyageSceneKit.ember))

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2),
                spacing: 6
            ) {
                macShortcut("WASD / Arrows", action: "Move view")
                macShortcut("Q / E · Right-drag", action: "Orbit view")
                macShortcut("Scroll · + / −", action: "Zoom view")
                macShortcut("⌘Z · ⇧⌘Z", action: "Undo · Redo")
                macShortcut("⌘D · Delete", action: "Duplicate · Delete")
                macShortcut("1–8", action: "Switch tools")
            }

            Text("Hover previews the active brush before clicking.")
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.42))
                .fixedSize(horizontal: false, vertical: true)
            #endif
        }
        .padding(11)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.06), lineWidth: 1))
    }

    private func cameraPresetButton(
        _ title: LocalizedStringKey,
        symbol: String,
        action: AssetStudioCameraAction,
        disabled: Bool = false
    ) -> some View {
        Button {
            store.requestCamera(action)
            Haptics.tap(.light)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(disabled ? .white.opacity(0.22) : .white.opacity(0.76))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(.white.opacity(disabled ? 0.025 : 0.065), in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(title)
    }

    private func cameraGestureHint(
        symbol: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(uiColor: VoyageSceneKit.ember))
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                Text(detail)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.38))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 35)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }

    #if targetEnvironment(simulator)
    private func macShortcut(
        _ keys: LocalizedStringKey,
        action: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(keys)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(action)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.40))
        }
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .padding(.horizontal, 8)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }
    #endif

    /// 複雑な世界でも、各編集レイヤーの量を一眼で把握できる。
    private var worldContentOverview: some View {
        HStack(spacing: 6) {
            contentCount(
                store.visiblePlacements.count,
                title: "Models",
                symbol: "cube.fill"
            )
            contentCount(
                store.visiblePaintStrokes.count,
                title: "Paint",
                symbol: "paintbrush.pointed.fill"
            )
            contentCount(
                store.visibleTerrainStrokes.count,
                title: "Terrain",
                symbol: "mountain.2.fill"
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("World contents")
        .accessibilityValue(worldContentBreakdown)
    }

    private func contentCount(
        _ count: Int,
        title: LocalizedStringKey,
        symbol: String
    ) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text("\(count)")
                    .fontWeight(.bold)
            }
            Text(title)
                .font(.system(size: 7, weight: .semibold, design: .rounded))
        }
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(count > 0 ? 0.72 : 0.28))
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(.white.opacity(count > 0 ? 0.06 : 0.025), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var placedObjects: some View {
        if !store.visiblePlacements.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(store.visiblePlacements) { placement in
                        Button {
                            store.select(placement.id)
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(store.selectedIDs.contains(placement.id) ? Color(uiColor: VoyageSceneKit.ember) : .white.opacity(0.18))
                                    .frame(width: 7, height: 7)
                                Text(placement.name)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.white.opacity(store.selectedIDs.contains(placement.id) ? 1 : 0.64))
                            .padding(.horizontal, 11)
                            .frame(minHeight: 31)
                            .background(.white.opacity(store.selectedIDs.contains(placement.id) ? 0.13 : 0.055), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(store.selectedIDs.contains(placement.id) ? 0.16 : 0.07), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var multiSelectionInspector: some View {
        VStack(spacing: 11) {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(Color(uiColor: VoyageSceneKit.ember))

            Text(selectionSummary)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(selectionBreakdown)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(uiColor: VoyageSceneKit.ember).opacity(0.86))
                .padding(.horizontal, 10)
                .frame(minHeight: 25)
                .background(Color(uiColor: VoyageSceneKit.ember).opacity(0.09), in: Capsule())

            Text("Selected models, paint strokes, and terrain can be deleted together. Drag another box to replace the selection.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.50))
                .multilineTextAlignment(.center)

            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete selected", systemImage: "trash")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(uiColor: VoyageSceneKit.coral))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(Color(uiColor: VoyageSceneKit.coral).opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)

            Button {
                store.select(nil)
            } label: {
                Text("Clear selection")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.60))
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(13)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.06), lineWidth: 1))
    }

    private var selectedInspector: some View {
        VStack(spacing: 11) {
            HStack(spacing: 8) {
                ForEach(InspectorSection.allCases) { section in
                    Button {
                        inspectorSection = section
                    } label: {
                        Text(inspectorTitle(section))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(inspectorSection == section ? .white : .white.opacity(0.46))
                            .frame(maxWidth: .infinity, minHeight: 31)
                            .background(.white.opacity(inspectorSection == section ? 0.12 : 0), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 7) {
                Button {
                    duplicateSelected()
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .foregroundStyle(.white.opacity(0.72))
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Duplicate")

                Button {
                    confirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .foregroundStyle(Color(uiColor: VoyageSceneKit.coral))
                        .background(Color(uiColor: VoyageSceneKit.coral).opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete")
            }

            switch inspectorSection {
            case .position:
                studioSlider("X", value: transformBinding(\.x), range: -32...32, format: "%.2f")
                studioSlider("Y", value: transformBinding(\.y), range: -2...24, format: "%.2f")
                studioSlider("Z", value: transformBinding(\.z), range: -32...32, format: "%.2f")

                HStack(spacing: 7) {
                    Button {
                        store.followsPlacementSurface.toggle()
                        if store.followsPlacementSurface {
                            snapSelectedToSurface()
                        } else {
                            Haptics.tap(.light)
                        }
                    } label: {
                        Label(
                            "Follow surface",
                            systemImage: store.followsPlacementSurface ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(store.followsPlacementSurface ? Color(uiColor: VoyageSceneKit.ember) : .white.opacity(0.56))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    Button {
                        snapSelectedToSurface()
                    } label: {
                        Label("Snap now", systemImage: "arrow.down.to.line.compact")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(uiColor: VoyageSceneKit.ember))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(Color(uiColor: VoyageSceneKit.ember).opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }

            case .rotation:
                studioSlider("X°", value: rotationBinding(\.pitch), range: -180...180, format: "%.0f°")
                studioSlider("Y°", value: rotationBinding(\.yaw), range: -180...180, format: "%.0f°")
                studioSlider("Z°", value: rotationBinding(\.roll), range: -180...180, format: "%.0f°")

            case .scale:
                studioSlider("S", value: transformBinding(\.scale), range: 0.01...5, format: "%.2f×")
                HStack {
                    Text("Pinch directly on the canvas for a wider 0.01–20× range.")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.42))
                    Spacer()
                    Button("Reset") {
                        store.updateSelectedTransform { $0.scale = 1 }
                        store.requestSurfaceSnap(clampOnly: !store.followsPlacementSurface)
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(uiColor: VoyageSceneKit.ember))
                }
            }
        }
        .padding(11)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.06), lineWidth: 1))
    }

    private var emptySelectionHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.tap")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(uiColor: VoyageSceneKit.ember))
            Text("Move follows surfaces. Height keeps X/Z fixed and moves only vertically. Pinch scales. Camera mode: one finger orbits, two fingers pan, and pinch zooms.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
    }

    private func studioSlider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String
    ) -> some View {
        HStack(spacing: 9) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 22, alignment: .leading)
            Slider(
                value: value,
                in: range,
                onEditingChanged: { editing in
                    if editing { store.beginInteractiveEdit() }
                    else { store.endInteractiveEdit() }
                }
            )
            .tint(Color(uiColor: VoyageSceneKit.ember))
            Text(String(format: format, value.wrappedValue))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 54, alignment: .trailing)
        }
        .frame(minHeight: 25)
    }

    private func transformBinding(_ keyPath: WritableKeyPath<AssetTransform, Float>) -> Binding<Double> {
        Binding(
            get: { Double(store.selectedPlacement?.transform[keyPath: keyPath] ?? 0) },
            set: { newValue in
                if keyPath == \AssetTransform.y {
                    store.followsPlacementSurface = false
                }
                let movesHorizontally = keyPath == \AssetTransform.x || keyPath == \AssetTransform.z
                store.updateSelectedTransform(interactively: true) { transform in
                    transform[keyPath: keyPath] = Float(newValue)
                }
                if movesHorizontally {
                    store.requestSurfaceSnap(clampOnly: !store.followsPlacementSurface)
                } else if keyPath == \AssetTransform.y {
                    store.requestSurfaceSnap(clampOnly: true)
                }
            }
        )
    }

    private func rotationBinding(_ keyPath: WritableKeyPath<AssetTransform, Float>) -> Binding<Double> {
        Binding(
            get: {
                let radians = store.selectedPlacement?.transform[keyPath: keyPath] ?? 0
                return Double(radians * 180 / .pi)
            },
            set: { degrees in
                store.updateSelectedTransform(interactively: true) { transform in
                    transform[keyPath: keyPath] = Float(degrees) * .pi / 180
                }
                store.requestSurfaceSnap(clampOnly: !store.followsPlacementSurface)
            }
        )
    }

    private func snapSelectedToSurface() {
        guard store.selectedPlacement != nil else { return }
        store.followsPlacementSurface = true
        store.requestSurfaceSnap()
        Haptics.tap(.light)
        showToast(String(localized: "Placed on surface"))
    }

    private func useCurrentStudioInGame() {
        guard let studioName = store.currentStudio?.name,
              store.useCurrentStudioInGame()
        else { return }
        store.manipulationMode = .move
        store.requestCamera(.overview)
        withAnimation(.easeOut(duration: 0.18)) { activePanel = nil }
        Haptics.tap(.medium)
        showToast(
            String(
                format: String(localized: "%@ is now the game world"),
                studioName
            )
        )
    }

    private func duplicateSelected() {
        guard store.selectionCount == 1, store.selectedPlacement != nil else { return }
        store.duplicateSelected()
        Haptics.tap(.medium)
        showToast(String(localized: "Duplicated"))
    }

    private func deleteSelection() {
        let count = store.selectionCount
        guard count > 0 else { return }
        store.deleteSelected()
        Haptics.tap(.medium)
        let message = String(
            format: String(localized: "Deleted %lld items"),
            Int64(count)
        )
        showToast(message)
    }

    private func studioIconButton(
        symbol: String,
        accessibilityLabel: LocalizedStringKey,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(disabled ? 0.25 : 0.92))
                .frame(width: 42, height: 42)
                .background(.black.opacity(0.54), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private func modeTitle(_ mode: AssetManipulationMode) -> LocalizedStringKey {
        switch mode {
        case .select: return "Select"
        case .paint: return "Paint"
        case .terrain: return "Terrain"
        case .place: return "Place"
        case .move: return "Move"
        case .height: return "Height"
        case .rotate: return "Rotate"
        case .scale: return "Scale"
        case .camera: return "Camera"
        }
    }

    private func paintToolTitle(_ tool: AssetPaintTool) -> LocalizedStringKey {
        switch tool {
        case .sand: return "Sand"
        case .grass: return "Grass"
        case .path: return "Path"
        case .rock: return "Bedrock"
        case .snow: return "Snow"
        case .eraser: return "Eraser"
        }
    }

    private func terrainToolTitle(_ tool: AssetTerrainTool) -> LocalizedStringKey {
        switch tool {
        case .raise: return "Build Up"
        case .lower: return "Carve"
        case .smooth: return "Smooth"
        }
    }

    private func terrainShapeTitle(_ shape: AssetTerrainShape) -> LocalizedStringKey {
        switch shape {
        case .hill: return "Hill"
        case .mountain: return "Mountain"
        case .plateau: return "Plateau"
        case .ridge: return "Ridge"
        }
    }

    private func terrainMaterialTitle(_ material: AssetTerrainMaterial) -> LocalizedStringKey {
        switch material {
        case .grass: return "Grass"
        case .earth: return "Earth"
        case .sand: return "Sand"
        case .rock: return "Rock"
        case .snow: return "Snow"
        }
    }

    private func paintToolColor(_ tool: AssetPaintTool) -> Color {
        if let material = tool.material {
            return Color(uiColor: material.color)
        }
        return Color(uiColor: VoyageSceneKit.coral)
    }

    private var modeStatusTitle: String {
        let mode: String
        switch store.manipulationMode {
        case .select: mode = String(localized: "Select")
        case .paint: mode = String(localized: "Paint")
        case .terrain: mode = String(localized: "Terrain")
        case .place: mode = String(localized: "Place")
        case .move: mode = String(localized: "Move")
        case .height: mode = String(localized: "Height")
        case .rotate: mode = String(localized: "Rotate")
        case .scale: mode = String(localized: "Scale")
        case .camera: mode = String(localized: "Camera")
        }

        switch store.manipulationMode {
        case .paint:
            return "\(mode) · \(localizedPaintToolName(store.paintTool))"
        case .terrain:
            return "\(mode) · \(localizedTerrainShapeName(store.terrainShape))"
        case .place:
            guard let assetID = store.placementBrushAssetID else { return mode }
            return "\(mode) · \(Asset3DCatalog.displayName(for: assetID))"
        default:
            return mode
        }
    }

    private var modeHelpText: String {
        switch store.manipulationMode {
        case .select:
            return String(localized: "Drag across models, paint, or terrain to box-select")
        case .paint:
            return String(localized: "Paint with one finger. Move the camera with two fingers.")
        case .terrain:
            return String(localized: "Tap to add the chosen landform. Drag Ridge to build a mountain range.")
        case .place:
            return String(localized: "Tap the world repeatedly to place the chosen asset.")
        case .move:
            return String(localized: "Drag the selected model across surfaces. It stays grounded automatically.")
        case .height:
            return String(localized: "Drag vertically to change height without moving sideways.")
        case .rotate:
            return String(localized: "Drag sideways to rotate the selected model.")
        case .scale:
            return String(localized: "Drag or pinch to resize the selected model.")
        case .camera:
            return String(localized: "One finger orbits, two fingers pan, and pinch zooms.")
        }
    }

    private func modeAccessibilityHint(_ mode: AssetManipulationMode) -> LocalizedStringKey {
        switch mode {
        case .select: return "Drag to select models, paint, and terrain"
        case .paint: return "Draw or erase surface materials"
        case .terrain: return "Build mountains, ridges, plateaus, and valleys"
        case .place: return "Place the chosen asset repeatedly"
        case .move: return "Move the selected model across the ground"
        case .height: return "Move the selected model only vertically"
        case .rotate: return "Rotate the selected model"
        case .scale: return "Resize the selected model"
        case .camera: return "Orbit, pan, and zoom the world view"
        }
    }

    private func localizedPaintToolName(_ tool: AssetPaintTool) -> String {
        switch tool {
        case .sand: return String(localized: "Sand")
        case .grass: return String(localized: "Grass")
        case .path: return String(localized: "Path")
        case .rock: return String(localized: "Bedrock")
        case .snow: return String(localized: "Snow")
        case .eraser: return String(localized: "Eraser")
        }
    }

    private func localizedTerrainShapeName(_ shape: AssetTerrainShape) -> String {
        switch shape {
        case .hill: return String(localized: "Hill")
        case .mountain: return String(localized: "Mountain")
        case .plateau: return String(localized: "Plateau")
        case .ridge: return String(localized: "Ridge")
        }
    }

    private var selectionBreakdown: String {
        contentBreakdown(
            models: store.selectedPlacements.count,
            paint: store.selectedPaintStrokes.count,
            terrain: store.selectedTerrainStrokes.count,
            omittingEmpty: true
        )
    }

    private var worldContentBreakdown: String {
        contentBreakdown(
            models: store.visiblePlacements.count,
            paint: store.visiblePaintStrokes.count,
            terrain: store.visibleTerrainStrokes.count,
            omittingEmpty: false
        )
    }

    private func contentBreakdown(
        models: Int,
        paint: Int,
        terrain: Int,
        omittingEmpty: Bool
    ) -> String {
        let values: [(Int, String)] = [
            (models, String(localized: "Models: %lld")),
            (paint, String(localized: "Paint: %lld")),
            (terrain, String(localized: "Terrain: %lld"))
        ]
        let parts = values.compactMap { count, format -> String? in
            guard !omittingEmpty || count > 0 else { return nil }
            return String(format: format, Int64(count))
        }
        return parts.isEmpty ? String(localized: "No selection") : parts.joined(separator: " · ")
    }

    private var selectionSummary: String {
        guard store.selectionCount > 1 else {
            if let placement = store.selectedPlacement { return placement.name }
            if !store.selectedPaintStrokes.isEmpty { return String(localized: "Paint stroke") }
            if !store.selectedTerrainStrokes.isEmpty { return String(localized: "Terrain stroke") }
            return String(localized: "Selected")
        }
        return String(
            format: String(localized: "%lld items selected"),
            Int64(store.selectionCount)
        )
    }

    private var selectionSymbol: String {
        if store.selectionCount > 1 { return "square.3.layers.3d" }
        if !store.selectedPaintStrokes.isEmpty { return "paintbrush.pointed.fill" }
        if !store.selectedTerrainStrokes.isEmpty { return "mountain.2.fill" }
        return "cube.fill"
    }

    private var deleteConfirmationTitle: String {
        guard store.selectionCount > 1 else {
            return String(localized: "Delete selected item?")
        }
        return String(
            format: String(localized: "Delete %lld selected items?"),
            Int64(store.selectionCount)
        )
    }

    private var deleteConfirmationDetail: String {
        String(
            format: String(localized: "This will delete %@. You can undo this afterward."),
            selectionBreakdown
        )
    }

    private func panelTitle(_ panel: StudioPanel) -> LocalizedStringKey {
        switch panel {
        case .assets: return "Assets"
        case .inspector: return "Details"
        }
    }

    private func inspectorTitle(_ section: InspectorSection) -> LocalizedStringKey {
        switch section {
        case .position: return "Position"
        case .rotation: return "Rotation"
        case .scale: return "Scale"
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.18)) { toastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            guard toastMessage == message else { return }
            withAnimation(.easeIn(duration: 0.18)) { toastMessage = nil }
        }
    }
}
