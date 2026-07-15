import SwiftUI
import SwiftData

/// タイマーの状態。アプリ全体で同時に1つだけ。再起動しても続くようUserDefaultsに持つ。
enum StudyTimer {
    static let startKey = "landfall.timer.start"
    static let itemKey = "landfall.timer.item"
}

/// 項目をタップして開く記録シート。タイマー計測か手入力で時間を決め、ひとことを添えて刻む。
struct RecordSessionSheet: View {
    let item: StudyItem
    /// 保存完了時に空白日数(おかえり判定用)を親へ返す。
    var onSaved: (Int?) -> Void
    /// 「編集」選択時に親へ委譲(このシートを閉じてから開き直す)。
    var onEdit: (StudyItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyDay.date, order: .reverse) private var days: [StudyDay]

    @AppStorage(StudyTimer.startKey) private var timerStart: Double = 0
    @AppStorage(StudyTimer.itemKey) private var timerItemID: String = ""

    @State private var minutes = 0
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    private var timerRunningHere: Bool {
        timerStart > 0 && timerItemID == item.uuid.uuidString
    }

    private var timerRunningElsewhere: Bool {
        timerStart > 0 && timerItemID != item.uuid.uuidString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            timerSection
                .padding(.top, 28)

            manualSection
                .padding(.top, 28)

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
                .padding(.top, 28)

            Spacer()

            saveButton
        }
        .padding(LFMetrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LFColor.paper)
        .presentationDetents([.large])
    }

    // MARK: - ヘッダー(タイル+名前+編集)

    private var header: some View {
        HStack(spacing: 14) {
            ItemTileArt(item: item)
                .frame(width: 52, height: 52)
            Text(item.name)
                .font(LFFont.copy(20))
                .foregroundStyle(LFColor.ink)
                .lineLimit(2)
            Spacer()
            Button("編集") {
                dismiss()
                onEdit(item)
            }
            .font(LFFont.label(15))
            .foregroundStyle(LFColor.ink.opacity(0.6))
        }
    }

    // MARK: - タイマー

    @ViewBuilder
    private var timerSection: some View {
        if timerRunningHere {
            VStack(alignment: .leading, spacing: 14) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(elapsedText(at: context.date))
                        .font(LFFont.number(44))
                        .foregroundStyle(LFColor.ink)
                }
                HStack(spacing: 12) {
                    Button {
                        stopTimerAndSave()
                    } label: {
                        Text("終了して刻む")
                            .font(LFFont.copy(17))
                            .foregroundStyle(LFColor.paper)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(LFColor.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Button {
                        clearTimer()
                    } label: {
                        Text("やめる")
                            .font(LFFont.label(15))
                            .foregroundStyle(LFColor.ink.opacity(0.5))
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(LFColor.ink.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if timerRunningElsewhere {
            Text("別の項目で計測中。")
                .font(LFFont.label(15))
                .foregroundStyle(LFColor.ink.opacity(0.5))
        } else {
            Button {
                timerStart = Date().timeIntervalSince1970
                timerItemID = item.uuid.uuidString
                dismiss()
            } label: {
                Text("タイマーで計測を始める")
                    .font(LFFont.copy(17))
                    .foregroundStyle(LFColor.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(LFColor.ink, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 手入力

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("または、時間を選んで刻む")
                .font(LFFont.label(13))
                .foregroundStyle(LFColor.ink.opacity(0.5))
            HStack(spacing: 10) {
                ForEach([15, 30, 45, 60], id: \.self) { value in
                    minuteChip(value)
                }
            }
            Stepper(value: $minutes, in: 0...600, step: 5) {
                Text(minutes > 0 ? "\(minutes)分" : "0分")
                    .font(LFFont.copy(17))
                    .monospacedDigit()
                    .foregroundStyle(minutes > 0 ? LFColor.ink : LFColor.ink.opacity(0.35))
            }
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

    // MARK: - 保存

    private var saveButton: some View {
        Button {
            save(minutes: minutes)
        } label: {
            Text("この分を刻む")
                .font(LFFont.copy(18))
                .foregroundStyle(minutes > 0 ? LFColor.paper : LFColor.paper.opacity(0.6))
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(minutes > 0 ? LFColor.ink : LFColor.ink.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(minutes <= 0)
    }

    private func elapsedText(at now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince1970 - timerStart))
        return String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    private func stopTimerAndSave() {
        let elapsed = Date().timeIntervalSince1970 - timerStart
        let measured = max(1, Int((elapsed / 60).rounded()))
        clearTimer()
        save(minutes: measured)
    }

    private func clearTimer() {
        timerStart = 0
        timerItemID = ""
    }

    private func save(minutes: Int) {
        guard minutes > 0 else { return }
        noteFocused = false
        let now = Date()
        // 保存の前に空白日数を測る(保存後だと最終記録日=今日になってしまう)。
        let blanks = MonthStats.blankDays(since: days.first?.date, to: now)

        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        modelContext.insert(
            StudySession(date: now, minutes: minutes, note: trimmed.isEmpty ? nil : trimmed, item: item)
        )
        StudyDayStore.markDay(now, context: modelContext)
        try? modelContext.save()
        dismiss()
        onSaved(blanks)
    }
}
