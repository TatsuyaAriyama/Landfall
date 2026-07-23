import SwiftUI
import SwiftData

/// 目的地の没入エディタ。全画面の夜の海(3D)+ 下部の質問形式パネル。
/// Web版 VoyageWorld 相当。目標は2種類「期日を決める / ステップで辿る」。
struct VoyageWorldView: View {
    let existing: Destination?
    let sessions: [StudySession]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    enum Kind { case date, steps }

    @State private var name: String
    @State private var kind: Kind
    @State private var targetDate: Date
    @State private var steps: [DestinationStep]
    @State private var confirmingDelete = false
    @State private var working = false
    /// 期日を「触った」印。開いた直後の既定値では自動保存しない(ただ見て閉じるのを防ぐ)。
    @State private var dateTouched = false
    /// 入場ドリーが終わって操作可能になったか(遷移中は編集UIを隠す)。
    @State private var isIdle = false
    /// 退場ドリーを開始する要求(true でズームアウト→dismiss)。
    @State private var closing = false
    @FocusState private var nameFocused: Bool

    init(existing: Destination?, sessions: [StudySession]) {
        self.existing = existing
        self.sessions = sessions
        _name = State(initialValue: existing?.name ?? "")
        let hasSteps = !(existing?.steps.isEmpty ?? true)
        _kind = State(initialValue: hasSteps ? .steps : .date)
        let defaultDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        _targetDate = State(initialValue: existing?.targetDate ?? defaultDate)
        _steps = State(initialValue: existing?.steps ?? [])
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var namedSteps: [DestinationStep] {
        steps.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    private var isValid: Bool {
        !trimmedName.isEmpty && (kind == .date || !namedSteps.isEmpty)
    }
    /// 編集中の局所stateから、船の位置(ratio)を出す。
    private var liveRatio: Double {
        if kind == .steps {
            guard !steps.isEmpty else { return 0 }
            return Double(steps.filter { $0.doneAt != nil }.count) / Double(steps.count)
        }
        let cal = Calendar.current
        let start = cal.startOfDay(for: existing?.createdAt ?? Date())
        let end = cal.startOfDay(for: targetDate)
        let today = cal.startOfDay(for: Date())
        let total = max(1, end.timeIntervalSince(start))
        return min(1, max(0, today.timeIntervalSince(start) / total))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ImmersiveVoyageView(
                ratio: liveRatio,
                steps: kind == .steps ? steps.map { $0.doneAt != nil } : [],
                islandName: trimmedName,
                closeRequested: closing,
                onToggleStep: { index in toggleStep(index: index) },
                onIdleChange: { idle in
                    withAnimation(.easeOut(duration: 0.25)) { isIdle = idle }
                },
                onClosed: { dismiss() },
                onTapBoat: { SoundFX.plink(); Haptics.tap(.light) }
            )
            .ignoresSafeArea()

            // 入場・退場の遷移中は編集UIを隠す(Web voyage-world-ui hidden)。
            Group {
                closeButton
                panel
            }
            .opacity(isIdle ? 1 : 0)
            .allowsHitTesting(isIdle)
        }
        .background(Color(VoyageSceneKit.seaDeep).ignoresSafeArea())
        .onChange(of: kind) { _, _ in
            // 目標の種類を切り替えたら、前の種類での「触った」印は捨てる。
            dateTouched = false
        }
        .confirmationDialog("Delete this destination", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { remove() }
        } message: {
            Text("Delete this destination? Your records stay.")
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button { requestClose() } label: {
                    Text("Close")
                        .font(LFFont.copy(15))
                        .foregroundStyle(LFColor.harborSand)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Color(VoyageSceneKit.seaDeep).opacity(0.6),
                                    in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - パネル

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("e.g. TOEIC, finish the book", text: $name)
                .font(LFFont.copy(20))
                .foregroundStyle(LFColor.harborSand)
                .focused($nameFocused)
                .textInputAutocapitalization(.never)

            Text("How will you reach this island?")
                .font(LFFont.label(13))
                .foregroundStyle(LFColor.harborSand.opacity(0.55))

            HStack(spacing: 10) {
                kindChip("Set a date", .date)
                kindChip("Follow steps", .steps)
            }

            if kind == .date {
                Text("The boat drifts toward the island as the day draws near.")
                    .font(LFFont.copy(14))
                    .foregroundStyle(LFColor.harborSand.opacity(0.7))
                DatePicker("", selection: $targetDate, in: Date()..., displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(LFColor.returnOrange)
                    .environment(\.colorScheme, .dark)
                    .onChange(of: targetDate) { _, _ in
                        // 期日を選び終えたら、そのまま保存してホームへ戻る(保存ボタン不要)。
                        dateTouched = true
                        autoSaveDateIfReady()
                    }
            } else {
                Text("Break a big goal into small steps. Each one you finish moves the boat forward; finish them all to make landfall.")
                    .font(LFFont.copy(14))
                    .foregroundStyle(LFColor.harborSand.opacity(0.7))
                stepsEditor
            }

            saveButton
            if existing != nil {
                Button { confirmingDelete = true } label: {
                    Text("Delete this destination")
                        .font(LFFont.copy(15))
                        .foregroundStyle(LFColor.coral)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(20)
        .background(Color(VoyageSceneKit.seaDeep).opacity(0.92),
                    in: RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func kindChip(_ title: LocalizedStringKey, _ value: Kind) -> some View {
        let selected = kind == value
        return Button {
            kind = value
        } label: {
            Text(title)
                .font(LFFont.copy(15))
                .foregroundStyle(selected ? LFColor.inkFixed : LFColor.harborSand)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(
                    Capsule().fill(selected ? LFColor.harborSand : Color.clear)
                )
                .overlay(
                    Capsule().stroke(LFColor.harborSand.opacity(selected ? 0 : 0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var stepsEditor: some View {
        VStack(spacing: 8) {
            ForEach($steps) { $step in
                HStack(spacing: 10) {
                    Button {
                        toggleStep(id: step.id)
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(LFColor.harborSand.opacity(0.5), lineWidth: 1.5)
                                .background(Circle().fill(step.doneAt != nil ? LFColor.harborSand : .clear))
                                .frame(width: 26, height: 26)
                            if step.doneAt != nil {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(LFColor.inkFixed)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    TextField("e.g. one pass of the vocab book", text: $step.name)
                        .font(LFFont.copy(15))
                        .foregroundStyle(LFColor.harborSand)
                        .strikethrough(step.doneAt != nil, color: LFColor.harborSand.opacity(0.6))

                    Button {
                        steps.removeAll { $0.id == step.id }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13))
                            .foregroundStyle(LFColor.harborSand.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(LFColor.harborSand.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if steps.count < Destination.maxSteps {
                Button {
                    steps.append(DestinationStep(name: ""))
                } label: {
                    Text("+ Add a step")
                        .font(LFFont.copy(15))
                        .foregroundStyle(LFColor.harborSand)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .strokeBorder(LFColor.harborSand.opacity(0.34),
                                              style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var saveButton: some View {
        Button(action: save) {
            Text("Save")
                .font(LFFont.copy(17))
                .foregroundStyle(LFColor.inkFixed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous)
                        .fill(isValid ? LFColor.harborSand : LFColor.harborSand.opacity(0.3))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isValid)
    }

    // MARK: - ステップの反転(既存目的地はその場で確定=Web persistSteps)

    private func toggleStep(id: DestinationStep.ID) {
        guard let i = steps.firstIndex(where: { $0.id == id }) else { return }
        toggleStep(index: i)
    }

    /// ブイのタップ(世界)/チェックのタップ(パネル)共通。
    private func toggleStep(index i: Int) {
        guard steps.indices.contains(i) else { return }
        steps[i].doneAt = steps[i].doneAt == nil ? Date() : nil
        SoundFX.plink()
        Haptics.tap(.light)
        persistSteps()
    }

    /// チェックの反転は、既存の目的地ならその場で確定する(fire-and-forget)。
    /// 新規(未保存)は局所stateだけ動かし、確定は「保存」に委ねる。
    private func persistSteps() {
        guard let existing, !trimmedName.isEmpty, !namedSteps.isEmpty else { return }
        existing.name = trimmedName
        existing.steps = namedSteps
        existing.targetDate = nil
        existing.updatedAt = Date()
        try? modelContext.save()
        SyncService.shared.push(existing)
    }

    // MARK: - 保存/削除

    /// 期日を選び終えたら、そのまま保存してホームへ戻る(保存ボタン不要)。
    /// 値を触っていなければ動かない(開いて眺めただけで閉じるのを防ぐ)。
    private func autoSaveDateIfReady() {
        guard kind == .date, dateTouched, isValid, !working else { return }
        save()
    }

    private func save() {
        guard isValid, !working else { return }
        working = true
        let dest: Destination
        if let existing {
            dest = existing
        } else {
            dest = Destination(name: trimmedName)
            modelContext.insert(dest)
        }
        dest.name = String(trimmedName.prefix(60))
        if kind == .date {
            dest.targetDate = targetDate
            dest.steps = []
        } else {
            // 名前を整えて上限で切る(Web saveDestination と同じ)。
            dest.steps = namedSteps.map {
                DestinationStep(id: $0.id, name: String($0.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)), doneAt: $0.doneAt)
            }
            dest.targetDate = nil
        }
        dest.updatedAt = Date()
        try? modelContext.save()
        SyncService.shared.push(dest)
        Haptics.success()
        requestClose()
    }

    /// 退場のドリーアウトを開始する(演出後に dismiss)。
    private func requestClose() {
        closing = true
    }

    private func remove() {
        guard let existing else { return }
        SyncService.shared.delete(existing)
        modelContext.delete(existing)
        try? modelContext.save()
        Haptics.success()
        requestClose()
    }
}
