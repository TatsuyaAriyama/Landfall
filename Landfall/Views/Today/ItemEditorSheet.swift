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
        VStack(spacing: 0) {
            header
                .padding(.horizontal, LFMetrics.cardPadding)
                .padding(.top, 20)
                .padding(.bottom, 10)

            fixedPreviewBar

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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
                        .padding(.top, 22)

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

                        colorSeaHeading
                            .padding(.top, 18)
                        colorSeaChart
                            .padding(.top, 12)
                        seaLightControl
                            .padding(.top, 16)
                        harborSwatchHeading
                            .padding(.top, 18)
                        styleRow
                            .padding(.top, 10)

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
                .padding(.horizontal, LFMetrics.cardPadding)
                .padding(.bottom, LFMetrics.cardPadding)
            }
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

    private var fixedPreviewBar: some View {
        HStack(spacing: 12) {
            previewTile(size: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text("Preview")
                    .font(LFFont.label(10))
                    .foregroundStyle(LFColor.ink.opacity(0.48))
                if trimmedName.isEmpty {
                    Text("Untitled item")
                        .foregroundStyle(LFColor.ink.opacity(0.5))
                } else {
                    Text(trimmedName)
                        .foregroundStyle(LFColor.ink)
                }
            }
            .font(LFFont.copy(15))
            .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, LFMetrics.cardPadding)
        .padding(.vertical, 9)
        .background(LFColor.paper)
        .overlay(alignment: .top) {
            Rectangle().fill(LFColor.harborSand.opacity(0.2)).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(LFColor.harborSand.opacity(0.28)).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func previewTile(size: CGFloat) -> some View {
        ZStack {
            if let data = photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
            } else {
                style.background
                TileSymbolView(symbol: symbol, fg: style.foreground, bg: style.background)
                    .frame(width: size * 0.64, height: size * 0.64)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
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
                Text("Selected color")
                    .font(LFFont.copy(14))
                    .foregroundStyle(LFColor.ink)
                Text(
                    SeaColorSelection(token: styleToken) != nil
                        || PCCSSelection(token: styleToken) != nil
                        ? "Mixed on the color chart"
                        : "Chosen from the harbor swatches"
                )
                .font(LFFont.label(12))
                .foregroundStyle(LFColor.ink.opacity(0.52))
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .frame(minHeight: 58)
        .overlay(alignment: .top) {
            Rectangle().fill(LFColor.harborSand.opacity(0.25)).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(LFColor.harborSand.opacity(0.25)).frame(height: 1)
        }
    }

    private var colorSeaHeading: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Sail the skiff to choose a color")
                .font(LFFont.copy(14))
                .foregroundStyle(LFColor.ink)
            Text("Pale inshore, vivid out at sea")
                .font(LFFont.label(11))
                .foregroundStyle(LFColor.ink.opacity(0.48))
        }
        .frame(maxWidth: .infinity)
    }

    private var harborSwatchHeading: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Harbor swatches")
                .font(LFFont.copy(12))
                .foregroundStyle(LFColor.ink)
            Spacer()
            Text("Six ready-mixed colors")
                .font(LFFont.label(11))
                .foregroundStyle(LFColor.ink.opacity(0.48))
        }
    }

    private var colorSeaChart: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2
            let angle = (seaColor.hue - 90) * .pi / 180
            let markerRadius = radius * seaColor.saturation * 0.82
            ZStack {
                AngularGradient(
                    colors: [
                        Color(red: 0.79, green: 0.24, blue: 0.31),
                        Color(red: 0.85, green: 0.42, blue: 0.24),
                        Color(red: 0.85, green: 0.60, blue: 0.26),
                        Color(red: 0.42, green: 0.62, blue: 0.35),
                        Color(red: 0.24, green: 0.58, blue: 0.44),
                        Color(red: 0.30, green: 0.49, blue: 0.62),
                        Color(red: 0.35, green: 0.39, blue: 0.61),
                        Color(red: 0.48, green: 0.33, blue: 0.58),
                        Color(red: 0.63, green: 0.31, blue: 0.49),
                        Color(red: 0.79, green: 0.24, blue: 0.31),
                    ],
                    center: .center,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(270)
                )
                RadialGradient(
                    colors: [
                        Color(red: 0.96, green: 0.93, blue: 0.82),
                        Color(red: 0.96, green: 0.93, blue: 0.82).opacity(0.72),
                        .clear,
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: radius * 0.88
                )
                Circle().stroke(LFColor.deepRust.opacity(0.24), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .padding(size * 0.24)
                Circle().stroke(LFColor.deepRust.opacity(0.14), lineWidth: 1)
                    .padding(size * 0.08)
                Rectangle().fill(LFColor.deepRust.opacity(0.18)).frame(width: 1, height: size * 0.84)
                Rectangle().fill(LFColor.deepRust.opacity(0.18)).frame(width: size * 0.84, height: 1)

                ForEach([
                    ("North", Alignment.top),
                    ("East", Alignment.trailing),
                    ("South", Alignment.bottom),
                    ("West", Alignment.leading),
                ], id: \.0) { point in
                    Text(LocalizedStringKey(point.0))
                        .font(LFFont.label(9))
                        .foregroundStyle(LFColor.deepRust.opacity(0.68))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: point.1)
                        .padding(12)
                }

                HarborSkiffMarker(sailColor: SeaColorPalette.background(seaColor))
                .frame(width: 58, height: 52)
                .offset(
                    x: cos(angle) * markerRadius,
                    y: sin(angle) * markerRadius
                )
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(LFColor.harborSand.opacity(0.68), lineWidth: 2))
            .overlay(Circle().inset(by: 4).stroke(LFColor.harborTeal.opacity(0.8), lineWidth: 3))
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateSeaColor(at: value.location, size: size)
                    }
                    .onEnded { _ in Haptics.tap(.light) }
            )
            .accessibilityElement()
            .accessibilityLabel("Color chart")
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
                Text("Night")
                Spacer()
                Text("Light")
                Spacer()
                Text("Day")
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
            .accessibilityLabel("Light")
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(LFColor.harborSand.opacity(0.22)).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(LFColor.harborSand.opacity(0.22)).frame(height: 1)
        }
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

private struct HarborSkiffMarker: View {
    let sailColor: Color

    var body: some View {
        ZStack {
            Ellipse()
                .stroke(Color(red: 0.98, green: 0.94, blue: 0.82).opacity(0.78), lineWidth: 1.5)
                .frame(width: 44, height: 8)
                .offset(y: 20)

            SkiffRigShape()
                .stroke(
                    Color(red: 0.28, green: 0.18, blue: 0.12),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                )

            SkiffMainSailShape()
                .fill(sailColor)
                .overlay(
                    SkiffMainSailShape()
                        .stroke(Color(red: 0.97, green: 0.92, blue: 0.81), lineWidth: 1.6)
                )

            SkiffJibShape()
                .fill(sailColor.opacity(0.86))
                .overlay(
                    SkiffJibShape()
                        .stroke(Color(red: 0.97, green: 0.92, blue: 0.81), lineWidth: 1.6)
                )

            SkiffHullShape()
                .fill(Color(red: 0.46, green: 0.27, blue: 0.17))
                .overlay(
                    SkiffHullShape()
                        .stroke(Color(red: 0.22, green: 0.14, blue: 0.09), lineWidth: 1.7)
                )

            SkiffDeckShape()
                .stroke(
                    Color(red: 0.22, green: 0.14, blue: 0.09),
                    style: StrokeStyle(lineWidth: 1.7, lineCap: .round)
                )

            HStack(spacing: 7) {
                Circle()
                Circle()
            }
            .foregroundStyle(Color(red: 0.95, green: 0.73, blue: 0.38))
            .frame(width: 17, height: 2.6)
            .offset(x: -2, y: 15)
        }
        .shadow(color: .black.opacity(0.24), radius: 1.5, y: 2)
        .accessibilityHidden(true)
    }
}

private struct SkiffMainSailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.55, y: rect.height * 0.13))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.82, y: rect.height * 0.64),
            control1: CGPoint(x: rect.width * 0.70, y: rect.height * 0.25),
            control2: CGPoint(x: rect.width * 0.80, y: rect.height * 0.47)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.55, y: rect.height * 0.64))
        path.closeSubpath()
        return path
    }
}

private struct SkiffJibShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.44, y: rect.height * 0.20))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.19, y: rect.height * 0.64),
            control1: CGPoint(x: rect.width * 0.32, y: rect.height * 0.33),
            control2: CGPoint(x: rect.width * 0.23, y: rect.height * 0.49)
        )
        path.addLine(to: CGPoint(x: rect.width * 0.44, y: rect.height * 0.64))
        path.closeSubpath()
        return path
    }
}

private struct SkiffHullShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.12, y: rect.height * 0.66))
        path.addLine(to: CGPoint(x: rect.width * 0.88, y: rect.height * 0.66))
        path.addLine(to: CGPoint(x: rect.width * 0.76, y: rect.height * 0.88))
        path.addLine(to: CGPoint(x: rect.width * 0.31, y: rect.height * 0.88))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.12, y: rect.height * 0.66),
            control1: CGPoint(x: rect.width * 0.21, y: rect.height * 0.84),
            control2: CGPoint(x: rect.width * 0.15, y: rect.height * 0.74)
        )
        path.closeSubpath()
        return path
    }
}

private struct SkiffRigShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mastTop = CGPoint(x: rect.width * 0.50, y: rect.height * 0.06)
        let mastFoot = CGPoint(x: rect.width * 0.50, y: rect.height * 0.68)
        path.move(to: mastTop)
        path.addLine(to: mastFoot)
        path.move(to: mastTop)
        path.addLine(to: CGPoint(x: rect.width * 0.16, y: rect.height * 0.66))
        path.move(to: mastTop)
        path.addLine(to: CGPoint(x: rect.width * 0.84, y: rect.height * 0.66))
        path.move(to: CGPoint(x: rect.width * 0.49, y: rect.height * 0.64))
        path.addLine(to: CGPoint(x: rect.width * 0.85, y: rect.height * 0.64))
        path.move(to: CGPoint(x: rect.width * 0.84, y: rect.height * 0.66))
        path.addLine(to: CGPoint(x: rect.width * 0.95, y: rect.height * 0.60))
        return path
    }
}

private struct SkiffDeckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.13, y: rect.height * 0.66))
        path.addLine(to: CGPoint(x: rect.width * 0.87, y: rect.height * 0.66))
        return path
    }
}
