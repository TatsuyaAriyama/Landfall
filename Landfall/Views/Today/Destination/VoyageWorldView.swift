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
            VoyageSceneView(
                ratio: liveRatio,
                steps: kind == .steps ? steps.map { $0.doneAt != nil } : [],
                allowsCameraControl: true
            )
            .ignoresSafeArea()

            closeButton
            panel
        }
        .background(Color(VoyageSceneKit.seaDeep).ignoresSafeArea())
        .confirmationDialog("Remove this destination?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { remove() }
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button { dismiss() } label: {
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
            TextField("Island name", text: $name)
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
            } else {
                Text("Break a big goal into small steps. Each one you finish moves the boat.")
                    .font(LFFont.copy(14))
                    .foregroundStyle(LFColor.harborSand.opacity(0.7))
                stepsEditor
            }

            saveButton
            if existing != nil {
                Button { confirmingDelete = true } label: {
                    Text("Remove destination")
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
                        step.doneAt = step.doneAt == nil ? Date() : nil
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

    // MARK: - 保存/削除

    private func save() {
        guard isValid else { return }
        let dest: Destination
        if let existing {
            dest = existing
        } else {
            dest = Destination(name: trimmedName)
            modelContext.insert(dest)
        }
        dest.name = trimmedName
        if kind == .date {
            dest.targetDate = targetDate
            dest.steps = []
        } else {
            dest.steps = namedSteps
            dest.targetDate = nil
        }
        dest.updatedAt = Date()
        try? modelContext.save()
        SyncService.shared.push(dest)
        Haptics.success()
        dismiss()
    }

    private func remove() {
        guard let existing else { return }
        SyncService.shared.delete(existing)
        modelContext.delete(existing)
        try? modelContext.save()
        Haptics.success()
        dismiss()
    }
}
