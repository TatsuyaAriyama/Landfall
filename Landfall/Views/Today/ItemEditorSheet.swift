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
    @State private var style: TileStyle = .midnight
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
            ForEach(TileStyle.allCases) { candidate in
                Button {
                    style = candidate
                } label: {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(candidate.background)
                        .frame(width: 40, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    style == candidate ? LFColor.returnOrange : LFColor.ink.opacity(0.12),
                                    lineWidth: style == candidate ? 3 : 1
                                )
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
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
        style = TileStyle.from(existing.styleToken)
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
            existing.styleToken = style.rawValue
            existing.symbolToken = symbol.rawValue
            existing.photoData = photoData
            saved = existing
        } else {
            let item = StudyItem(
                name: trimmedName,
                styleToken: style.rawValue,
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
        if UserDefaults.standard.string(forKey: StudyTimer.itemKey) == existing.uuid.uuidString {
            UserDefaults.standard.set(0, forKey: StudyTimer.startKey)
            UserDefaults.standard.set("", forKey: StudyTimer.itemKey)
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
