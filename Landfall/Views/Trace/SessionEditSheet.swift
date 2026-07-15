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
                Text(Self.dateFormatter.string(from: session.date))
                    .font(LFFont.label(14))
                    .foregroundStyle(LFColor.ink.opacity(0.5))
            }
            .padding(.top, 24)

            Text("時間")
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
                Text("\(minutes)分")
                    .font(LFFont.copy(17))
                    .monospacedDigit()
                    .foregroundStyle(LFColor.ink)
            }
            .padding(.top, 10)

            TextField("ひとこと(任意)", text: $note)
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
        .presentationDetents([.large])
        .onAppear {
            minutes = session.minutes
            note = session.note ?? ""
        }
        .confirmationDialog("この記録を削除する?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("削除する", role: .destructive, action: deleteSession)
            Button("やめる", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            Text("記録を編集")
                .font(LFFont.copy(20))
                .foregroundStyle(LFColor.ink)
            Spacer()
            Button("閉じる") { dismiss() }
                .font(LFFont.label(15))
                .foregroundStyle(LFColor.ink.opacity(0.6))
        }
    }

    private func minuteChip(_ value: Int) -> some View {
        let selected = minutes == value
        return Button {
            minutes = value
        } label: {
            Text("\(value)分")
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
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            session.note = trimmed.isEmpty ? nil : trimmed
            try? modelContext.save()
            dismiss()
        } label: {
            Text("変更を保存")
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
            Text("この記録を削除")
                .font(LFFont.label(15))
                .foregroundStyle(LFColor.deepRust)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func deleteSession() {
        let date = session.date
        modelContext.delete(session)
        // その日の記録が全て消えたら「学んだ日」も外す。
        StudyDayStore.unmarkDayIfEmpty(date, context: modelContext)
        try? modelContext.save()
        dismiss()
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日(E)"
        return f
    }()
}
