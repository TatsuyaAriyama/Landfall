import SwiftUI
import SwiftData
import PhotosUI

/// 項目の作成・編集シート。名前+見た目(配色×シンボル、または表紙写真)。
struct ItemEditorSheet: View {
    /// nil なら新規作成。
    let existing: StudyItem?
    /// 削除されたとき呼ぶ(呼び出し元の詳細画面を閉じるなど)。
    var onDeleted: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyItem.sortOrder) private var items: [StudyItem]

    @State private var name = ""
    @State private var styleToken = TileStyle.midnight.rawValue
    @State private var seaColor = SeaColorSelection(
        hue: 258,
        saturation: 0.65,
        brightness: 0.19
    )
    @State private var symbol: TileSymbol = .compass
    @State private var photoData: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                HStack {
                    Spacer()
                    previewTile
                    Spacer()
                }
                .padding(.top, 24)

                TextField("Name (e.g. Reading, Coding)", text: $name)
                    .font(LFFont.label(16))
                    .foregroundStyle(LFColor.ink)
                    .tint(LFColor.ink)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { if !saveDisabled { save() } }
                    .padding(.horizontal, 18)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(isDuplicateName ? LFColor.deepRust.opacity(0.6) : LFColor.ink.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.top, 24)

                if isDuplicateName {
                    Text("An item with this name already exists.")
                        .font(LFFont.label(13))
                        .foregroundStyle(LFColor.deepRust)
                        .padding(.top, 8)
                }

                photoSection
                    .padding(.top, 24)

                if photoData == nil {
                    sectionLabel("Color")
                        .padding(.top, 24)
                    selectedColorSummary
                        .padding(.top, 10)
                    styleRow
                        .padding(.top, 10)

                    colorSeaHeading
                        .padding(.top, 18)
                    colorSeaChart
                        .padding(.top, 12)
                    seaLightControl
                        .padding(.top, 16)

                    sectionLabel("Symbol")
                        .padding(.top, 20)
                    symbolRow
                        .padding(.top, 10)
                }

                saveButton
                    .padding(.top, 32)

                if existing != nil {
                    deleteButton
                        .padding(.top, 16)
                }
            }
            .padding(LFMetrics.cardPadding)
        }
        .background(LFColor.paper)
        .presentationDetents([.large])
        .onAppear(perform: load)
        .onChange(of: pickerItem) { _, newValue in
            guard let newValue else { return }
            Task { @MainActor in
                if let data = try? await newValue.loadTransferable(type: Data.self) {
                    photoData = Self.downscaledJPEG(data)
                }
                pickerItem = nil
            }
        }
        .confirmationDialog(
            "Delete this item?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: deleteItem)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deleting this item removes its records. Your logged days (Trace, Logbook) stay.")
        }
    }

    // MARK: - 部品

    private var header: some View {
        HStack {
            Text(existing == nil ? "Add item" : "Edit item")
                .font(LFFont.copy(20))
                .foregroundStyle(LFColor.ink)
            Spacer()
            Button("Close") { dismiss() }
                .font(LFFont.label(15))
                .foregroundStyle(LFColor.ink.opacity(0.6))
        }
    }

    private var previewTile: some View {
        ZStack {
            if let data = photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
            } else {
                style.background
                TileSymbolView(symbol: symbol, fg: style.foreground, bg: style.background)
                    .frame(width: 60, height: 60)
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var style: ItemTileStyle {
        ItemTileStyle.from(styleToken)
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(LFFont.label(13))
            .foregroundStyle(LFColor.ink.opacity(0.5))
    }

    private var photoSection: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Text(photoData == nil ? "Choose cover photo" : "Replace photo")
                    .font(LFFont.label(15))
                    .foregroundStyle(LFColor.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(LFColor.ink.opacity(0.25), lineWidth: 1)
                    )
            }
            if photoData != nil {
                Button("Remove photo") { photoData = nil }
                    .font(LFFont.label(15))
                    .foregroundStyle(LFColor.ink.opacity(0.5))
            }
            Spacer()
        }
    }

    private var styleRow: some View {
        HStack(spacing: 12) {
            ForEach(TileStyle.itemCases) { candidate in
                Button {
                    styleToken = candidate.rawValue
                    seaColor = seaPosition(for: candidate)
                } label: {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(candidate.background)
                        .frame(width: 40, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    styleToken == candidate.rawValue
                                        ? LFColor.returnOrange : LFColor.ink.opacity(0.12),
                                    lineWidth: styleToken == candidate.rawValue ? 3 : 1
                                )
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var selectedColorSummary: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(style.background)
                .frame(width: 40, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(LFColor.ink.opacity(0.1), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                if let selection = SeaColorSelection(token: styleToken) {
                    let pccs = PCCSPalette.nearest(to: selection)
                    Text("Color sea chart")
                        .font(LFFont.label(14))
                        .foregroundStyle(LFColor.ink)
                    Text("PCCS guide \(pccs.tone.rawValue)\(pccs.hue)")
                        .font(LFFont.label(12))
                        .foregroundStyle(LFColor.ink.opacity(0.52))
                } else if let selection = PCCSSelection(token: styleToken) {
                    Text("Color sea chart")
                        .font(LFFont.label(14))
                        .foregroundStyle(LFColor.ink)
                    Text("PCCS guide \(selection.tone.rawValue)\(selection.hue)")
                        .font(LFFont.label(12))
                        .foregroundStyle(LFColor.ink.opacity(0.52))
                } else {
                    Text("Aftide preset")
                        .font(LFFont.label(14))
                        .foregroundStyle(LFColor.ink)
                    Text("Existing colors remain available")
                        .font(LFFont.label(12))
                        .foregroundStyle(LFColor.ink.opacity(0.52))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 58)
        .background(LFColor.ink.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var colorSeaHeading: some View {
        VStack(spacing: 2) {
            Text("Move the boat to find a color")
                .font(LFFont.label(14))
                .foregroundStyle(LFColor.ink)
            Text("Calm at the center, vivid at the edge")
                .font(LFFont.label(11))
                .foregroundStyle(LFColor.ink.opacity(0.48))
        }
        .frame(maxWidth: .infinity)
    }

    private var colorSeaChart: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2
            let angle = (seaColor.hue - 90) * .pi / 180
            let markerRadius = radius * seaColor.saturation * 0.86
            ZStack {
                AngularGradient(
                    colors: [
                        Color(red: 0.90, green: 0.12, blue: 0.26),
                        Color(red: 0.94, green: 0.45, blue: 0.12),
                        Color(red: 0.95, green: 0.85, blue: 0.13),
                        Color(red: 0.29, green: 0.76, blue: 0.25),
                        Color(red: 0.08, green: 0.70, blue: 0.68),
                        Color(red: 0.15, green: 0.50, blue: 0.82),
                        Color(red: 0.34, green: 0.25, blue: 0.76),
                        Color(red: 0.75, green: 0.22, blue: 0.66),
                        Color(red: 0.90, green: 0.12, blue: 0.26),
                    ],
                    center: .center,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(270)
                )
                RadialGradient(
                    colors: [.white, .white.opacity(0.76), .white.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: radius * 0.88
                )
                Circle().stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .padding(size * 0.24)
                Circle().stroke(.white.opacity(0.2), lineWidth: 1)
                    .padding(size * 0.08)
                Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: size * 0.84)
                Rectangle().fill(.white.opacity(0.25)).frame(width: size * 0.84, height: 1)

                ForEach([
                    ("N", Alignment.top),
                    ("E", Alignment.trailing),
                    ("S", Alignment.bottom),
                    ("W", Alignment.leading),
                ], id: \.0) { point in
                    Text(point.0)
                        .font(LFFont.label(9))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: point.1)
                        .padding(12)
                }

                ZStack {
                    Circle()
                        .fill(SeaColorPalette.background(seaColor))
                    Circle()
                        .strokeBorder(.white, lineWidth: 3)
                    Image(systemName: "sailboat.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(SeaColorPalette.foreground(seaColor))
                }
                .frame(width: 40, height: 40)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                .offset(
                    x: cos(angle) * markerRadius,
                    y: sin(angle) * markerRadius
                )
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(LFColor.harborSand.opacity(0.55), lineWidth: 2))
            .shadow(color: LFColor.harborTeal.opacity(0.25), radius: 18, y: 10)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateSeaColor(at: value.location, size: size)
                    }
                    .onEnded { _ in Haptics.tap(.light) }
            )
            .accessibilityElement()
            .accessibilityLabel("Color sea chart")
            .accessibilityValue(
                "\(Int(seaColor.hue.rounded())) degrees, \(Int((seaColor.saturation * 100).rounded())) percent"
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 310)
        .frame(maxWidth: .infinity)
    }

    private var seaLightControl: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Deep sea")
                Spacer()
                Text("Sea light").fontWeight(.semibold)
                Spacer()
                Text("Morning light")
            }
            .font(LFFont.label(10))
            .foregroundStyle(LFColor.ink.opacity(0.52))

            Slider(
                value: Binding(
                    get: { seaColor.brightness },
                    set: { brightness in
                        applySeaColor(
                            SeaColorSelection(
                                hue: seaColor.hue,
                                saturation: seaColor.saturation,
                                brightness: brightness
                            )
                        )
                    }
                ),
                in: 0.18...1
            )
            .tint(SeaColorPalette.background(seaColor))
            .accessibilityLabel("Sea light")
        }
        .padding(12)
        .background(LFColor.harborTeal.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func updateSeaColor(at point: CGPoint, size: CGFloat) {
        let radius = size / 2
        let x = point.x - radius
        let y = point.y - radius
        let distance = min(radius, hypot(x, y))
        let hue = (atan2(y, x) * 180 / .pi + 90 + 360)
            .truncatingRemainder(dividingBy: 360)
        applySeaColor(
            SeaColorSelection(
                hue: hue,
                saturation: Double(distance / radius),
                brightness: seaColor.brightness
            )
        )
    }

    private func applySeaColor(_ selection: SeaColorSelection) {
        seaColor = selection
        styleToken = selection.token
    }

    private func seaPosition(for style: TileStyle) -> SeaColorSelection {
        switch style {
        case .midnight: SeaColorSelection(hue: 258, saturation: 0.65, brightness: 0.19)
        case .coral: SeaColorSelection(hue: 12, saturation: 0.48, brightness: 0.94)
        case .ink: SeaColorSelection(hue: 220, saturation: 0.05, brightness: 0.16)
        case .seaGreen: SeaColorSelection(hue: 160, saturation: 0.54, brightness: 0.79)
        case .violet: SeaColorSelection(hue: 244, saturation: 0.62, brightness: 0.72)
        case .sunYellow: SeaColorSelection(hue: 48, saturation: 0.70, brightness: 1)
        default: SeaColorSelection(hue: 165, saturation: 0.54, brightness: 0.55)
        }
    }

    private var symbolRow: some View {
        // 数が増えたので横スクロール。
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(TileSymbol.allCases) { candidate in
                    Button {
                        symbol = candidate
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(style.background)
                            TileSymbolView(symbol: candidate, fg: style.foreground, bg: style.background)
                                .frame(width: 26, height: 26)
                        }
                        .frame(width: 40, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    symbol == candidate ? LFColor.returnOrange : LFColor.ink.opacity(0.12),
                                    lineWidth: symbol == candidate ? 3 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 他の項目(自分自身は除く)と大小文字・前後空白を無視して同名かどうか。
    private var isDuplicateName: Bool {
        guard !trimmedName.isEmpty else { return false }
        return items.contains { other in
            other.persistentModelID != existing?.persistentModelID
                && other.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    private var saveDisabled: Bool { trimmedName.isEmpty || isDuplicateName }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text(existing == nil ? "Add this item" : "Save changes")
                .font(LFFont.copy(18))
                .foregroundStyle(saveDisabled ? LFColor.paper.opacity(0.6) : LFColor.paper)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(saveDisabled ? LFColor.ink.opacity(0.3) : LFColor.ink)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(saveDisabled)
    }

    private var deleteButton: some View {
        Button {
            confirmingDelete = true
        } label: {
            Text("Delete item")
                .font(LFFont.label(15))
                .foregroundStyle(LFColor.deepRust)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 動作

    private func load() {
        guard let existing else {
            // 新規追加は名前入力から始まる。開いた瞬間にキーボードを出して1タップ省く。
            nameFocused = true
            return
        }
        name = existing.name
        styleToken = ItemTileStyle.from(existing.styleToken).token
        if let selection = SeaColorSelection(token: styleToken) {
            seaColor = selection
        } else if let selection = PCCSSelection(token: styleToken) {
            seaColor = SeaColorSelection(
                hue: PCCSPalette.hueDegrees[selection.hue - 1],
                saturation: selection.tone.saturation,
                brightness: selection.tone.brightness
            )
        } else {
            seaColor = seaPosition(for: TileStyle.from(styleToken))
        }
        symbol = TileSymbol.from(existing.symbolToken)
        photoData = existing.photoData
    }

    /// 保存する項目名。前後空白を除き、上限で切り詰める(肥大化した同期データを防ぐ)。
    private var nameToSave: String { String(trimmedName.prefix(60)) }

    private func save() {
        guard !saveDisabled else { return }
        let trimmedName = nameToSave
        let saved: StudyItem
        if let existing {
            existing.name = trimmedName
            existing.styleToken = styleToken
            existing.symbolToken = symbol.rawValue
            existing.photoData = photoData
            saved = existing
        } else {
            let item = StudyItem(
                name: trimmedName,
                styleToken: styleToken,
                symbolToken: symbol.rawValue,
                photoData: photoData,
                sortOrder: (items.map(\.sortOrder).max() ?? -1) + 1
            )
            modelContext.insert(item)
            saved = item
        }
        try? modelContext.save()
        SyncService.shared.push(saved)
        Haptics.success()
        dismiss()
    }

    private func deleteItem() {
        guard let existing else { return }
        // 計測中の項目を消すならタイマーも捨てる。
        StudyTimer.clear(ifMatching: existing.uuid.uuidString)
        // 軽量マイグレーション前の古い記録にも表示情報を補い、項目との関係だけを外す。
        for session in existing.sessions {
            session.itemName = session.itemName ?? existing.name
            session.itemStyle = session.itemStyle ?? existing.styleToken
            session.itemSymbol = session.itemSymbol ?? existing.symbolToken
            session.updatedAt = Date()
            SyncService.shared.push(session)
        }
        SyncService.shared.delete(existing)
        modelContext.delete(existing)
        try? modelContext.save()
        dismiss()
        onDeleted?()
    }

    /// 表紙写真は長辺512pxのJPEGへ縮小して保存する。
    static func downscaledJPEG(_ data: Data, maxSide: CGFloat = 512) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxSide / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}
