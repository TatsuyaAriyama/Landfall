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
    @State private var persistenceError = false
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    HStack(spacing: 12) {
                        if let item = session.item {
                            ItemTileArt(item: item)
                                .frame(width: 40, height: 40)
                            Text(item.name)
                                .font(LFFont.copy(17))
                                .foregroundStyle(LFHomeFeatureStyle.ink)
                        }
                        Spacer()
                        Text(LF.dayWithWeekday(session.date))
                            .font(LFFont.label(14))
                            .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
                    }
                    .padding(.top, 24)

                    Text("Time")
                        .font(LFFont.label(13))
                        .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
                        .padding(.top, 28)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach([15, 30, 45, 60], id: \.self) { value in
                                minuteChip(value)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .padding(.top, 10)

                    Stepper(value: $minutes, in: (session.extraSeconds > 0 ? 0 : 1)...WorkRecordPolicy.maximumSessionMinutes, step: 5) {
                        Text("\(minutes) min")
                            .font(LFFont.copy(17))
                            .monospacedDigit()
                            .foregroundStyle(LFHomeFeatureStyle.ink)
                    }
                    .padding(.top, 10)

                    TextField(
                        "What you worked on (optional)", text: $note,
                        prompt: Text("What you worked on (optional)")
                            .foregroundColor(LFHomeFeatureStyle.secondaryInk)
                    )
                        .font(LFFont.label(16))
                        .foregroundStyle(LFHomeFeatureStyle.ink)
                        .tint(LFHomeFeatureStyle.ink)
                        .focused($noteFocused)
                        .submitLabel(.done)
                        .onSubmit { noteFocused = false }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .frame(minHeight: 52)
                        .background(LFHomeFeatureStyle.field, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.top, 24)
                }
                .padding(.bottom, 4)
            }
            .scrollDismissesKeyboard(.interactively)

            saveButton
            deleteButton
        }
        .padding(20)
        .lfHomeFeatureCard()
        .frame(maxWidth: 560)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { LFHarborBackdrop() }
        .tint(LFHomeFeatureStyle.ink)
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
        .alert("Could not update the record", isPresented: $persistenceError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your changes have not been saved. Please try again.")
        }
    }

    private var header: some View {
        HStack {
            Text("Edit record")
                .font(LFFont.copy(20))
                .foregroundStyle(LFHomeFeatureStyle.ink)
            Spacer()
            Button("Close") { dismiss() }
                .font(LFFont.label(15))
                .foregroundStyle(LFHomeFeatureStyle.secondaryInk)
                .frame(minWidth: 44, minHeight: 44)
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
                .foregroundStyle(selected ? Color.white : LFHomeFeatureStyle.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .frame(minHeight: 44)
                .background(selected ? LFHomeFeatureStyle.ink : Color.clear)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(LFHomeFeatureStyle.ink.opacity(selected ? 0 : 0.25), lineWidth: 1)
                )
                .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var saveButton: some View {
        Button {
            noteFocused = false
            let originalMinutes = session.minutes
            let originalNote = session.note
            let originalTiming = session.timingJSON
            let revisedMinutes = min(WorkRecordPolicy.maximumSessionMinutes, max(session.extraSeconds > 0 ? 0 : 1, minutes))
            if revisedMinutes != originalMinutes { session.timingJSON = nil }
            session.minutes = revisedMinutes
            session.note = WorkRecordPolicy.normalizedNote(note)
            do {
                try modelContext.save()
            } catch {
                session.minutes = originalMinutes
                session.note = originalNote
                session.timingJSON = originalTiming
                persistenceError = true
                return
            }
            SyncService.shared.publishPersistedSessionChanges([session], context: modelContext)
            dismiss()
        } label: {
            Text("Save changes")
                .font(LFFont.copy(18))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .frame(minHeight: 60)
                .background(LFHomeFeatureStyle.primaryFill)
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
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    private func deleteSession() {
        do {
            try StudySessionStore.delete(session, context: modelContext)
        } catch {
            persistenceError = true
            return
        }
        dismiss()
    }
}
