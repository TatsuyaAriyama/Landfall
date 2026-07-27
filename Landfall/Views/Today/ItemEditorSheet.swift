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
    @State private var pccsTone: PCCSTone = .vivid
    @State private var pccsHue = 2
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

                    HStack {
                        sectionLabel("PCCS tone")
                        Spacer()
                        Text("Choose a mood")
                            .font(LFFont.label(11))
                            .foregroundStyle(LFColor.ink.opacity(0.42))
                    }
                    .padding(.top, 18)
                    pccsToneRow
                        .padding(.top, 8)

                    HStack {
                        sectionLabel("24 hues")
                        Spacer()
                        Text("Choose a hue")
                            .font(LFFont.label(11))
                            .foregroundStyle(LFColor.ink.opacity(0.42))
                    }
                    .padding(.top, 18)
                    pccsHueGrid
                        .padding(.top, 8)

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
                if let selection = PCCSSelection(token: styleToken) {
                    Text("PCCS \(selection.tone.rawValue)\(selection.hue)")
                        .font(LFFont.label(14))
                        .foregroundStyle(LFColor.ink)
                    Text(selection.tone.displayName)
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

    private var pccsToneRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PCCSTone.allCases) { tone in
                    let selection = PCCSSelection(tone: tone, hue: pccsHue)
                    Button {
                        pccsTone = tone
                        styleToken = selection.token
                        Haptics.tap(.light)
                    } label: {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(PCCSPalette.background(selection))
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tone.rawValue)
                                    .font(LFFont.label(13))
                                    .foregroundStyle(LFColor.ink)
                                Text(tone.displayName)
                                    .font(LFFont.label(10))
                                    .foregroundStyle(LFColor.ink.opacity(0.5))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 9)
                        .frame(minWidth: 96, minHeight: 48, alignment: .leading)
                        .background(LFColor.paper)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    pccsTone == tone ? LFColor.returnOrange : LFColor.ink.opacity(0.12),
                                    lineWidth: pccsTone == tone ? 2 : 1
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(tone.displayName), \(tone.rawValue)"))
                    .accessibilityAddTraits(pccsTone == tone ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var pccsHueGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
            spacing: 8
        ) {
            ForEach(1...24, id: \.self) { hue in
                let selection = PCCSSelection(tone: pccsTone, hue: hue)
                let selected = PCCSSelection(token: styleToken) == selection
                Button {
                    pccsHue = hue
                    styleToken = selection.token
                    Haptics.tap(.light)
                } label: {
                    Text("\(hue)")
                        .font(LFFont.label(10))
                        .foregroundStyle(PCCSPalette.foreground(selection))
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .background(PCCSPalette.background(selection))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(
                                    selected ? LFColor.paper : LFColor.ink.opacity(0.08),
                                    lineWidth: selected ? 2 : 1
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(selected ? LFColor.returnOrange : .clear, lineWidth: 3)
                                .padding(-3)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("PCCS \(pccsTone.rawValue)\(hue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
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
        if let selection = PCCSSelection(token: styleToken) {
            pccsTone = selection.tone
            pccsHue = selection.hue
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
