import SwiftUI
import SwiftData

/// 記録済みセッションの編集。時間・ひとことの修正と削除。
struct SessionEditSheet: View {
    let session: StudySession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var minutes = 0
    @State private var note = ""
    @State private var confirmingDelete = false
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            HStack(spacing: 12) {
                if let item = session.item {
                    ItemTileArt(item: item)
                        .frame(width: 40, height: 40)
                    Text(item.name)
                        .font(LFFont.copy(17))
                        .foregroundStyle(LFColor.ink)
                }
                Spacer()
                Text(LF.dayWithWeekday(session.date))
                    .font(LFFont.label(14))
                    .foregroundStyle(LFColor.ink.opacity(0.5))
            }
            .padding(.top, 24)

            Text("Time")
                .font(LFFont.label(13))
                .foregroundStyle(LFColor.ink.opacity(0.5))
                .padding(.top, 28)

            HStack(spacing: 10) {
                ForEach([15, 30, 45, 60], id: \.self) { value in
                    minuteChip(value)
                }
            }
            .padding(.top, 10)

            Stepper(value: $minutes, in: 1...600, step: 5) {
                Text("\(minutes) min")
                    .font(LFFont.copy(17))
                    .monospacedDigit()
                    .foregroundStyle(LFColor.ink)
            }
            .padding(.top, 10)

            TextField("A note (optional)", text: $note)
                .font(LFFont.label(16))
                .foregroundStyle(LFColor.ink)
                .tint(LFColor.ink)
                .focused($noteFocused)
                .submitLabel(.done)
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(LFColor.ink.opacity(0.2), lineWidth: 1)
                )
                .padding(.top, 24)

            Spacer()

            saveButton
            deleteButton
                .padding(.top, 14)
        }
        .padding(LFMetrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LFColor.paper)
        // 余白タップでキーボードを収め、保存/削除が隠れないようにする。
        .contentShape(Rectangle())
        .onTapGesture { noteFocused = false }
        .presentationDetents([.large])
        // キーボード上の明示的な「完了」。ひとこと入力中に保存ボタンが隠れても閉じられる。
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { noteFocused = false }
            }
        }
        .onAppear {
            minutes = session.minutes
            note = session.note ?? ""
        }
        .confirmationDialog("Delete this record?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deleteSession)
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            Text("Edit record")
                .font(LFFont.copy(20))
                .foregroundStyle(LFColor.ink)
            Spacer()
            Button("Close") { dismiss() }
                .font(LFFont.label(15))
                .foregroundStyle(LFColor.ink.opacity(0.6))
        }
    }

    private func minuteChip(_ value: Int) -> some View {
        let selected = minutes == value
        return Button {
            minutes = value
        } label: {
            Text("\(value) min")
                .font(LFFont.label(15))
                .monospacedDigit()
                .foregroundStyle(selected ? LFColor.paper : LFColor.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(selected ? LFColor.ink : Color.clear)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(LFColor.ink.opacity(selected ? 0 : 0.25), lineWidth: 1)
                )
                .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var saveButton: some View {
        Button {
            noteFocused = false
            session.minutes = max(1, minutes)
            let trimmed = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
            session.note = trimmed.isEmpty ? nil : trimmed
            try? modelContext.save()
            SyncService.shared.push(session)
            WidgetBridge.refresh(context: modelContext)
            dismiss()
        } label: {
            Text("Save changes")
                .font(LFFont.copy(18))
                .foregroundStyle(LFColor.paper)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(LFColor.ink)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var deleteButton: some View {
        Button {
            confirmingDelete = true
        } label: {
            Text("Delete record")
                .font(LFFont.label(15))
                .foregroundStyle(LFColor.deepRust)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func deleteSession() {
        let date = session.date
        SyncService.shared.delete(session)
        modelContext.delete(session)
        // その日の記録が全て消えたら「学んだ日」も外す。
        StudyDayStore.unmarkDayIfEmpty(date, context: modelContext)
        try? modelContext.save()
        // 学んだ日が変わった可能性があるので、港の軌跡も更新する。
        RoomService.shared.publishCurrentMonth(context: modelContext)
        WidgetBridge.refresh(context: modelContext)
        dismiss()
    }
}
