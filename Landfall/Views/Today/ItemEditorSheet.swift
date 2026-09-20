import SwiftUI
import SwiftData

/// 項目の作成・編集シート。名前と配色×シンボルを設定する。
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
    @State private var confirmingDelete = false
    @State private var showingSaveError = false
    @State private var showingDeleteError = false
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

                TextField(
                    "Name (e.g. Reading, Coding)", text: $name,
                    prompt: Text("Name (e.g. Reading, Coding)")
                        .foregroundColor(LFHomeFeatureStyle.secondaryInk)
                )
                    .font(LFFont.label(16))
                    .foregroundStyle(LFHomeFeatureStyle.ink)
                    .tint(LFHomeFeatureStyle.ink)
                    .focused($nameFocused)
                    .accessibilityLabel(Text("Item name"))
                    .submitLabel(.done)
                    .onSubmit { if !saveDisabled { save() } }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .frame(minHeight: 52)
                    .background(
                        LFHomeFeatureStyle.field,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isDuplicateName ? LFColor.deepRust.opacity(0.6) : LFHomeFeatureStyle.outline, lineWidth: 1)
                    )
                    .padding(.top, 24)

                if isDuplicateName {
                    Text("An item with this name already exists.")
                        .font(LFFont.label(13))
                        .foregroundStyle(LFColor.deepRust)
                        .padding(.top, 8)
                }

                sectionLabel("Color")
                    .padding(.top, 24)
                styleRow
                    .padding(.top, 10)

                sectionLabel("Symbol")
                    .padding(.top, 20)
                symbolRow
                    .padding(.top, 10)

                if existing != nil {
                    deleteButton
                        .padding(.top, 24)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            saveButton
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .padding(.top, 12)
        }
        .lfHomeFeatureCard()
        .frame(maxWidth: 560)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { LFHarborBackdrop() }
        .tint(LFHomeFeatureStyle.ink)
        .presentationDetents([.large])
        .onAppear(perform: load)
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
        .alert("Could not save", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your item has not been saved. Please try again.")
        }
        .alert("Could not delete the item", isPresented: $showingDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
    }

    // MARK: - 部品

    private var header: some View {
        HStack {
            Text(existing == nil ? "Add item" : "Edit item")
                .font(LFFont.copy(20))
                .foregroundStyle(LFHomeFeatureStyle.ink)
            Spacer()
            Button { dismiss() } label: {
                Text("Close")
                    .font(LFFont.label(15))
                    .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
                    .padding(.horizontal, 12)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(LFHomeFeatureStyle.field, in: Capsule())
                    .contentShape(Rectangle())
            }
            .buttonStyle(LFPressableButtonStyle())
        }
    }

    private var previewTile: some View {
        let previewStyle = style
        return ZStack {
            previewStyle.background
            TileSymbolView(
                symbol: symbol,
                fg: previewStyle.foreground,
                bg: previewStyle.background
            )
            .frame(width: 60, height: 60)
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityHidden(true)
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(LFFont.label(13))
            .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
    }

    private var styleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(TileStyle.itemCases) { candidate in
                    Button {
                        style = candidate
                        Haptics.tap(.light)
                    } label: {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(candidate.background)
                            .frame(width: 42, height: 42)
                            .overlay {
                                TileSymbolView(
                                    symbol: symbol,
                                    fg: candidate.foreground,
                                    bg: candidate.background
                                )
                                .frame(width: 20, height: 20)
                                .allowsHitTesting(false)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(
                                        style == candidate
                                            ? LFColor.returnOrange
                                            : LFHomeFeatureStyle.outline,
                                        lineWidth: style == candidate ? 3 : 1
                                    )
                            )
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(candidate.accessibilityName))
                    .accessibilityAddTraits(style == candidate ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
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
                                    symbol == candidate ? LFColor.returnOrange : LFHomeFeatureStyle.outline,
                                    lineWidth: symbol == candidate ? 3 : 1
                                )
                        )
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(candidate.accessibilityName))
                    .accessibilityAddTraits(symbol == candidate ? .isSelected : [])
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
        guard !nameToSave.isEmpty else { return false }
        return items.contains { other in
            other.persistentModelID != existing?.persistentModelID
                && other.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(nameToSave) == .orderedSame
        }
    }

    private var saveDisabled: Bool { trimmedName.isEmpty || isDuplicateName }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text(existing == nil ? "Add this item" : "Save changes")
                .font(LFFont.copy(18))
                .foregroundStyle(Color.white.opacity(saveDisabled ? 0.8 : 1))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .frame(minHeight: 64)
                .background(LFHomeFeatureStyle.primaryFill.opacity(saveDisabled ? 0.36 : 1))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(LFPressableButtonStyle())
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
                .frame(minHeight: 44)
                .contentShape(Rectangle())
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
    }

    /// 保存する項目名。前後空白を除き、上限で切り詰める(肥大化した同期データを防ぐ)。
    private var nameToSave: String {
        String(trimmedName.prefix(WorkRecordPolicy.maximumItemNameCharacters))
    }

    private func save() {
        guard !saveDisabled else { return }
        let trimmedName = nameToSave
        let saved: StudyItem
        // Keep recovery scoped to this edit; rolling back the shared context
        // would also discard unrelated changes from other screens or sync.
        let previousName = existing?.name
        let previousStyle = existing?.styleToken
        let previousSymbol = existing?.symbolToken
        let previousPhoto = existing?.photoData
        if let existing {
            existing.name = trimmedName
            existing.styleToken = style.rawValue
            existing.symbolToken = symbol.rawValue
            // 旧版で設定された写真も、編集後は選択したシンボルへ統一する。
            existing.photoData = nil
            saved = existing
        } else {
            let item = StudyItem(
                name: trimmedName,
                styleToken: style.rawValue,
                symbolToken: symbol.rawValue,
                sortOrder: (items.map(\.sortOrder).max() ?? -1) + 1
            )
            modelContext.insert(item)
            saved = item
        }
        do {
            try modelContext.save()
        } catch {
            if let existing, let previousName, let previousStyle, let previousSymbol {
                existing.name = previousName
                existing.styleToken = previousStyle
                existing.symbolToken = previousSymbol
                existing.photoData = previousPhoto
            } else {
                modelContext.delete(saved)
            }
            showingSaveError = true
            return
        }
        SyncService.shared.push(saved)
        Haptics.success()
        dismiss()
    }

    private func deleteItem() {
        guard let existing else { return }
        let itemID = existing.uuid
        // Cascade deletion gets its own context so failure can be rolled back
        // without discarding unrelated pending edits in the shared context.
        let deletionContext = ModelContext(modelContext.container)
        deletionContext.autosaveEnabled = false
        do {
            let descriptor = FetchDescriptor<StudyItem>(predicate: #Predicate { $0.uuid == itemID })
            if let item = try deletionContext.fetch(descriptor).first {
                deletionContext.delete(item)
                try deletionContext.save()
            }
        } catch {
            deletionContext.rollback()
            showingDeleteError = true
            return
        }
        // Mirror the committed cascade into the UI context so its query and
        // already-loaded relationships stop displaying the removed item.
        modelContext.delete(existing)
        modelContext.processPendingChanges()
        // Only a durable local deletion may clear the timer or remove the
        // account copy. The deleted model itself is no longer safe to read.
        StudyTimer.clear(ifMatching: itemID.uuidString)
        SyncService.shared.deleteItem(id: itemID)
        dismiss()
        onDeleted?()
    }
}
