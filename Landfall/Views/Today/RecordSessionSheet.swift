import SwiftUI
import SwiftData
import WidgetKit

/// タイマーの状態。アプリ全体で同時に1つだけ。再起動しても続くようUserDefaultsに持つ。
enum StudyTimer {
    static let defaults = KeelMiraWidgetStore.defaults
    static let startKey = KeelMiraWidgetStore.Key.timerStart
    static let itemKey = KeelMiraWidgetStore.Key.timerItem
    /// これを超える航海は「閉じ忘れ」の可能性が高いので、着岸時に確認する。
    static let longSessionMinutes = 8 * 60
    private static let legacyMigrationKey = "landfall.timer.legacyMigration.completed.v1"

    /// 項目の削除経路が増えても、孤立したタイマーを残さないための共通処理。
    static func clear(ifMatching itemID: String? = nil) {
        if let itemID, defaults.string(forKey: itemKey) != itemID { return }
        KeelMiraWidgetStore.clearTimer()
        WidgetCenter.shared.reloadTimelines(ofKind: KeelMiraWidgetStore.widgetKind)
    }

    /// 旧版の標準UserDefaultsに航海が残っている場合だけ、App Groupへ一度移す。
    static func migrateLegacyTimerIfNeeded() {
        let legacy = UserDefaults.standard
        guard !legacy.bool(forKey: legacyMigrationKey) else { return }
        defer {
            legacy.set(true, forKey: legacyMigrationKey)
            for key in [
                startKey,
                itemKey,
                KeelMiraWidgetStore.Key.timerItemName,
                KeelMiraWidgetStore.Key.timerMode,
                KeelMiraWidgetStore.Key.pomodoroStartElapsed,
                KeelMiraWidgetStore.Key.breakSeconds,
                KeelMiraWidgetStore.Key.breakStartedAt,
                KeelMiraWidgetStore.Key.sound,
            ] {
                legacy.removeObject(forKey: key)
            }
        }

        let currentStart = defaults.double(forKey: startKey)
        let currentItem = defaults.string(forKey: itemKey) ?? ""
        guard !VoyageTimerMath.isActive(
            startedAt: currentStart,
            itemID: currentItem
        ) else { return }
        if currentStart != 0 || !currentItem.isEmpty {
            KeelMiraWidgetStore.clearTimer()
        }

        let legacyStart = legacy.double(forKey: startKey)
        let legacyItem = legacy.string(forKey: itemKey) ?? ""
        guard VoyageTimerMath.isActive(
            startedAt: legacyStart,
            itemID: legacyItem
        ) else { return }

        // Write the activation timestamp last so app and widget never observe a
        // partially migrated timer as active.
        defaults.set(legacyItem, forKey: itemKey)
        for key in [
            KeelMiraWidgetStore.Key.timerItemName,
            KeelMiraWidgetStore.Key.timerMode,
            KeelMiraWidgetStore.Key.pomodoroStartElapsed,
            KeelMiraWidgetStore.Key.breakSeconds,
            KeelMiraWidgetStore.Key.breakStartedAt,
            KeelMiraWidgetStore.Key.sound,
        ] {
            if let value = legacy.object(forKey: key) { defaults.set(value, forKey: key) }
        }
        defaults.set(legacyStart, forKey: startKey)
        defaults.synchronize()
    }

    /// Run on every launch, including after the one-time legacy migration has
    /// already completed. Partial App Group writes must not keep Home in a
    /// permanent or epoch-sized voyage state.
    static func repairInvalidStateIfNeeded() {
        let start = defaults.double(forKey: startKey)
        let itemID = defaults.string(forKey: itemKey) ?? ""
        guard start != 0 || !itemID.isEmpty else { return }
        guard !VoyageTimerMath.isActive(startedAt: start, itemID: itemID) else { return }
        KeelMiraWidgetStore.clearTimer()
        WidgetCenter.shared.reloadTimelines(ofKind: KeelMiraWidgetStore.widgetKind)
    }
}

/// 項目をタップして開く記録シート。タイマー計測か手入力で時間を決め、ひとことを添えて刻む。
struct RecordSessionSheet: View {
    let item: StudyItem
    /// 保存完了時に空白日数(おかえり判定用)を親へ返す。
    var onSaved: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudyDay.date, order: .reverse) private var days: [StudyDay]

    @AppStorage(StudyTimer.startKey, store: StudyTimer.defaults) private var timerStart: Double = 0
    @AppStorage(StudyTimer.itemKey, store: StudyTimer.defaults) private var timerItemID: String = ""

    @State private var minutes = 0
    @State private var note = ""
    /// 記録する日時。既定は今。過去日の後追い記録(バックフィル)に使う。
    @State private var recordDate = Date()
    /// 閉じ忘れ疑いの長時間航海を着岸するときの確認。
    @State private var confirmingLong = false
    @State private var pendingMinutes = 0
    @FocusState private var noteFocused: Bool

    private var timerRunningHere: Bool {
        VoyageTimerMath.isActive(startedAt: timerStart, itemID: timerItemID)
            && timerItemID == item.uuid.uuidString
    }

    private var timerRunningElsewhere: Bool {
        VoyageTimerMath.isActive(startedAt: timerStart, itemID: timerItemID)
            && timerItemID != item.uuid.uuidString
    }

    /// Arbitrary backfilled time changes level progression, so it remains an
    /// operator-only recovery tool instead of a player-facing shortcut.
    private var canEnterWorkTimeManually: Bool {
        AccessPolicy.isDeveloper()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            timerSection
                .padding(.top, 28)

            if canEnterWorkTimeManually {
                manualSection
                    .padding(.top, 28)
            }

            TextField("What you worked on (optional)", text: $note)
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

            if canEnterWorkTimeManually {
                saveButton
            }
        }
        .padding(LFMetrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LFColor.paper)
        .presentationDetents([.large])
        .alert("A long voyage", isPresented: $confirmingLong) {
            Button("Log the whole time") {
                clearTimer()
                save(minutes: pendingMinutes, date: Date())
            }
            Button("Pick the length instead") {
                clearTimer()
                minutes = 0   // 手入力モードに切り替え、長さを選び直せる。
            }
            Button("Keep sailing", role: .cancel) { }   // タイマーは残す。
        } message: {
            Text("You've been under sail for \(LF.duration(minutes: pendingMinutes)). Did you forget to make landfall? Log this whole time?")
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["LANDFALL_CONFIRM_LONG"] == "1" {
                pendingMinutes = 613   // 10時間13分
                confirmingLong = true
            }
            #endif
        }
    }

    // MARK: - ヘッダー

    private var header: some View {
        HStack(spacing: 14) {
            ItemTileArt(item: item)
                .frame(width: 52, height: 52)
            Text(item.name)
                .font(LFFont.copy(20))
                .foregroundStyle(LFColor.ink)
                .lineLimit(2)
            Spacer()
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
                        Text("Make landfall")
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
                        Text("Cancel")
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
            Text("Under sail on another item.")
                .font(LFFont.label(15))
                .foregroundStyle(LFColor.ink.opacity(0.5))
        } else {
            Button {
                KeelMiraWidgetStore.start(
                    itemID: item.uuid.uuidString,
                    itemName: item.name
                )
                timerStart = StudyTimer.defaults.double(forKey: StudyTimer.startKey)
                timerItemID = item.uuid.uuidString
                WidgetCenter.shared.reloadTimelines(ofKind: KeelMiraWidgetStore.widgetKind)
                dismiss()
                Haptics.tap(.medium)
                // 出航の瞬間: 帆船が海へ漕ぎ出す。
                SailAnimator.shared.play(.departure)
            } label: {
                Text("Set sail")
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
            // 記録する日(既定は今日)。過去日も選べる=後からつけられる。
            HStack {
                Text("Date")
                    .font(LFFont.label(13))
                    .foregroundStyle(LFColor.ink.opacity(0.5))
                Spacer()
                DatePicker(
                    "",
                    selection: $recordDate,
                    in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .tint(LFColor.ink)
            }

            Text("Or pick a voyage length")
                .font(LFFont.label(13))
                .foregroundStyle(LFColor.ink.opacity(0.5))
            HStack(spacing: 10) {
                ForEach([15, 30, 45, 60], id: \.self) { value in
                    minuteChip(value)
                }
            }
            Stepper(value: $minutes, in: 0...600, step: 5) {
                Text(minutes > 0 ? "\(minutes) min" : "0 min")
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

    // MARK: - 保存

    private var saveButton: some View {
        Button {
            save(minutes: minutes, date: recordDate)
        } label: {
            Text("Log this voyage")
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
        // 閉じ忘れ疑いの長時間は、そのまま巨大記録にせず確認する(タイマーは残したまま)。
        if measured >= StudyTimer.longSessionMinutes {
            pendingMinutes = measured
            confirmingLong = true
            return
        }
        clearTimer()
        // タイマーは「今」終えた記録なので現在時刻で刻む(バックフィルの日付は使わない)。
        save(minutes: measured, date: Date())
    }

    private func clearTimer() {
        StudyTimer.clear(ifMatching: item.uuid.uuidString)
        timerStart = 0
        timerItemID = ""
    }

    private func save(minutes: Int, date: Date) {
        guard minutes > 0 else { return }
        noteFocused = false
        let isToday = Calendar.current.isDateInToday(date)
        // 空白明け(おかえり)判定は「今日つけたとき」だけ。過去日の後追い記録では出さない。
        // 保存の前に空白日数を測る(保存後だと最終記録日=今日になってしまう)。
        let blanks = isToday ? MonthStats.blankDays(since: days.first?.date, to: date) : nil

        let session = StudySession(
            date: date,
            minutes: minutes,
            note: WorkRecordPolicy.normalizedNote(note),
            item: item
        )
        modelContext.insert(session)
        let dayMark = StudyDayStore.markDay(
            date,
            context: modelContext,
            syncsToAccount: false
        )
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(session)
            if dayMark.wasInserted { modelContext.delete(dayMark.day) }
            return
        }
        SyncService.shared.publishPersistedSessionChanges(
            [session],
            insertedDays: dayMark.wasInserted ? [dayMark.day] : [],
            context: modelContext
        )
        dismiss()
        Haptics.success()
        // 着岸アニメと「おかえり」は今日つけたときだけ。過去の後追いは静かに保存する。
        if isToday, (blanks ?? 0) < 2 {
            SailAnimator.shared.play(.arrival, minutes: minutes)
        }
        onSaved(blanks)
    }
}
