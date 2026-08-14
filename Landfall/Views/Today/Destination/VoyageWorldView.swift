import SwiftUI
import SwiftData

/// 目的地の没入エディタ。全画面の夜の海(3D)+ 下部の質問形式パネル。
/// Web版 VoyageWorld 相当。目標は2種類「期日を決める / ステップで辿る」。
struct VoyageWorldView: View {
    let existing: Destination?
    let sessions: [StudySession]
    var onLand: (Destination) -> Void
    var usesHomeWorld: Bool
    var homeWorldReady: Bool
    var homeWorldTapToken: Int
    var onRequestClose: (() -> Void)?
    var onStepsChange: ([DestinationStep]) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    enum Kind { case date, steps }

    @State private var name: String
    @State private var kind: Kind
    @State private var targetDate: Date
    @State private var hasTargetDate: Bool
    @State private var withTime: Bool
    @State private var steps: [DestinationStep]
    @State private var confirmingDelete = false
    @State private var confirmingLand = false
    @State private var working = false
    /// 入場ドリーが終わって操作可能になったか(遷移中は編集UIを隠す)。
    @State private var isIdle = false
    /// 海など「外側」をタップして世界に入り込んでいる(編集UIをフェード)。
    @State private var uiHidden = false
    /// 退場ドリーを開始する要求(true でズームアウト→dismiss)。
    @State private var closing = false
    @FocusState private var nameFocused: Bool
    @FocusState private var focusedStepID: DestinationStep.ID?

    init(
        existing: Destination?,
        sessions: [StudySession],
        usesHomeWorld: Bool = false,
        homeWorldReady: Bool = true,
        homeWorldTapToken: Int = 0,
        onRequestClose: (() -> Void)? = nil,
        onStepsChange: @escaping ([DestinationStep]) -> Void = { _ in },
        onLand: @escaping (Destination) -> Void = { _ in }
    ) {
        self.existing = existing
        self.sessions = sessions
        self.usesHomeWorld = usesHomeWorld
        self.homeWorldReady = homeWorldReady
        self.homeWorldTapToken = homeWorldTapToken
        self.onRequestClose = onRequestClose
        self.onStepsChange = onStepsChange
        self.onLand = onLand
        _name = State(initialValue: existing?.name ?? "")
        let hasSteps = !(existing?.steps.isEmpty ?? true)
        _kind = State(initialValue: hasSteps ? .steps : .date)
        let defaultDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        _targetDate = State(initialValue: existing?.targetDate ?? defaultDate)
        _hasTargetDate = State(initialValue: existing?.targetDate != nil)
        _withTime = State(initialValue: existing?.targetHasTime == true)
        _steps = State(initialValue: Array((existing?.steps ?? []).prefix(Destination.maxSteps)))
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var namedSteps: [DestinationStep] {
        validSteps(from: steps)
    }
    private var completedStepCount: Int {
        namedSteps.filter { $0.doneAt != nil }.count
    }
    private var allStepsComplete: Bool {
        !namedSteps.isEmpty && completedStepCount == namedSteps.count
    }
    private var stepProgressRatio: Double {
        guard !namedSteps.isEmpty else { return 0 }
        return Double(completedStepCount) / Double(namedSteps.count)
    }
    private var isValid: Bool {
        !trimmedName.isEmpty &&
        (kind == .date ? hasTargetDate && !deadlinePassed : !namedSteps.isEmpty)
    }
    private var draftDeadline: Date? {
        guard hasTargetDate else { return nil }
        if withTime { return targetDate }
        let start = Calendar.current.startOfDay(for: targetDate)
        return Calendar.current.date(
            byAdding: DateComponents(day: 1, nanosecond: -1),
            to: start
        )
    }
    private var deadlinePassed: Bool {
        guard kind == .date, let draftDeadline else { return false }
        return draftDeadline <= Date()
    }

    /// 空行は下書きとして扱い、進捗・3D航路・保存には数えない。
    private func validSteps(from source: [DestinationStep]) -> [DestinationStep] {
        Array(source.lazy.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.prefix(Destination.maxSteps))
    }
    /// 編集中の局所stateから、船の位置(ratio)を出す。
    private var liveRatio: Double {
        if kind == .steps {
            return stepProgressRatio
        }
        guard let end = draftDeadline else { return 0 }
        let remaining = max(0, end.timeIntervalSinceNow)
        let approachWindow: TimeInterval = 7 * 86_400
        return min(1, max(0, 1 - remaining / approachWindow))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if usesHomeWorld {
                Color.clear
                    .allowsHitTesting(false)
            } else {
                ImmersiveVoyageView(
                    ratio: liveRatio,
                    steps: kind == .steps
                        ? namedSteps.map { VoyageStep(doneAt: $0.doneAt) }
                        : [],
                    islandName: trimmedName,
                    closeRequested: closing,
                    onToggleStep: { index in toggleStep(index: index) },
                    onIdleChange: { idle in
                        withAnimation(.easeOut(duration: 0.25)) { isIdle = idle }
                    },
                    onClosed: { dismiss() },
                    onTapBoat: { SoundFX.plink(); Haptics.tap(.light) },
                    onTapWorld: {
                        withAnimation(.easeInOut(duration: 0.35)) { uiHidden.toggle() }
                        Haptics.tap(.light)
                    }
                )
                .ignoresSafeArea()
            }

            // 遷移中(enter/exit)と、世界に入り込んでいる間(uiHidden)は編集UIを隠す。
            Group {
                topBar
                panel
            }
            .opacity(editorUIVisible ? 1 : 0)
            .allowsHitTesting(editorUIVisible)
        }
        .background {
            if !usesHomeWorld {
                Color(VoyageSceneKit.seaDeep).ignoresSafeArea()
            }
        }
        .onAppear {
            onStepsChange(kind == .steps ? namedSteps : [])
            #if DEBUG
            if ProcessInfo.processInfo.environment["LANDFALL_IMMERSE"] != nil { uiHidden = true }
            #endif
        }
        .onChange(of: steps) { _, value in
            onStepsChange(kind == .steps ? validSteps(from: value) : [])
        }
        .onChange(of: kind) { _, value in
            onStepsChange(value == .steps ? namedSteps : [])
        }
        .onChange(of: homeWorldTapToken) {
            guard usesHomeWorld else { return }
            withAnimation(.easeInOut(duration: 0.35)) { uiHidden.toggle() }
            Haptics.tap(.light)
        }
        .confirmationDialog("Delete this destination", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { remove() }
        } message: {
            Text("Delete this destination? Your records stay.")
        }
        .confirmationDialog(
            "Go ashore here",
            isPresented: $confirmingLand,
            titleVisibility: .visible
        ) {
            Button("Go ashore here") { landEarly() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Did you achieve this destination? Going ashore ends this voyage and saves it in your Logbook.")
        }
    }

    private var editorUIVisible: Bool {
        (usesHomeWorld ? homeWorldReady : isIdle) && !uiHidden
    }

    /// 3D の景色に関わらず、ホームと同じ明るい編集面を保つ。
    private var editorSurface: Color { Color(hex: 0xF6EEE1) }
    private var editorInk: Color { Color(hex: 0x173F3C) }

    private var topBar: some View {
        VStack {
            HStack(spacing: 10) {
                TextField("e.g. TOEIC, finish the book", text: $name)
                    .font(LFFont.copy(16))
                    .foregroundStyle(editorInk)
                    .focused($nameFocused)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 18)
                    .frame(height: 48)
                    .background(
                        editorSurface.opacity(0.97),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule()
                            .stroke(editorInk.opacity(0.16), lineWidth: 1)
                    )
                    .accessibilityLabel(Text("Island name"))

                Button { requestClose() } label: {
                    Text("Close")
                        .font(LFFont.copy(14))
                        .foregroundStyle(LFColor.returnOrange)
                        .padding(.horizontal, 18)
                        .frame(height: 48)
                        .background(
                            editorSurface.opacity(0.97),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(editorInk.opacity(0.16), lineWidth: 1)
                        )
                }
                .buttonStyle(LFPressableButtonStyle())
            }
            .padding(.horizontal, 16)
            .safeAreaPadding(.top, 8)

            Spacer()
        }
    }

    // MARK: - パネル

    private var panel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("How will you reach this island?")
                    .font(LFFont.label(13))
                    .tracking(0.7)
                    .foregroundStyle(editorInk.opacity(0.68))

                HStack(spacing: 10) {
                    kindChip("Set a date", .date)
                    kindChip("Follow steps", .steps)
                }

                if kind == .date {
                    dateEditor
                } else {
                    Text("Break a big goal into small steps. Each one you finish moves the boat forward; finish them all to make landfall.")
                        .font(LFFont.copy(14))
                        .foregroundStyle(editorInk.opacity(0.74))
                    stepsEditor
                }

                Text("Drag to look around. Pinch to zoom in. Tap the world to see only it.")
                    .font(LFFont.label(11))
                    .foregroundStyle(editorInk.opacity(0.52))

                saveButton

                if let existing {
                    Button {
                        confirmingLand = true
                    } label: {
                        Text(existing.progress(sessions: sessions).reached
                            ? "Go ashore"
                             : "Go ashore here")
                            .font(LFFont.copy(13))
                            .foregroundStyle(LFColor.returnOrange)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(LFPressableButtonStyle())
                }

                if existing != nil {
                    Button { confirmingDelete = true } label: {
                        Text("Delete this destination")
                            .font(LFFont.copy(15))
                            .foregroundStyle(LFColor.coral)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(LFPressableButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 18)
        }
        .frame(maxHeight: 400)
        .background(
            editorSurface.opacity(0.97),
            in: RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous)
                .stroke(editorInk.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: LFColor.inkFixed.opacity(0.12), radius: 16, y: 7)
        .padding(.horizontal, 16)
        .safeAreaPadding(.bottom, 12)
    }

    private var dateEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The target date guides your voyage. When you achieve it, choose Go ashore. Without a time, the whole day counts.")
                .font(LFFont.copy(14))
                .foregroundStyle(editorInk.opacity(0.74))

            Text("Target date")
                .font(LFFont.label(13))
                .tracking(0.7)
                .foregroundStyle(editorInk.opacity(0.68))

            if hasTargetDate {
                DatePicker(
                    "",
                    selection: $targetDate,
                    in: Calendar.current.startOfDay(for: Date())...,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(LFColor.returnOrange)
                .environment(\.colorScheme, .light)
            } else {
                Button {
                    hasTargetDate = true
                } label: {
                    HStack {
                        Text("Choose a date")
                        Spacer()
                        Image(systemName: "calendar")
                    }
                    .font(LFFont.copy(15))
                    .foregroundStyle(editorInk)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(editorInk.opacity(0.20), lineWidth: 1)
                    )
                }
                .buttonStyle(LFPressableButtonStyle())
            }

            Toggle("Set a time too", isOn: $withTime)
                .font(LFFont.copy(14))
                .tint(LFColor.returnOrange)
                .foregroundStyle(editorInk.opacity(0.82))
                .disabled(!hasTargetDate)

            if withTime && hasTargetDate {
                DatePicker(
                    "Deadline time",
                    selection: $targetDate,
                    displayedComponents: .hourAndMinute
                )
                .font(LFFont.copy(14))
                .tint(LFColor.returnOrange)
                .foregroundStyle(editorInk)
                .environment(\.colorScheme, .light)

                Text(deadlinePassed
                     ? "That time has passed. Pick a later one."
                     : "This is the date you aim to achieve it.")
                    .font(LFFont.label(12))
                    .foregroundStyle(
                        deadlinePassed ? LFColor.coral : editorInk.opacity(0.62)
                    )
            } else if deadlinePassed {
                Text("That day has passed. Pick today or later.")
                    .font(LFFont.label(12))
                    .foregroundStyle(LFColor.coral)
            }
        }
    }

    private func kindChip(_ title: LocalizedStringKey, _ value: Kind) -> some View {
        let selected = kind == value
        return Button {
            selectKind(value)
        } label: {
            Text(title)
                .font(LFFont.copy(15))
                .foregroundStyle(selected ? LFColor.returnOrange : editorInk)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(
                    Capsule().fill(selected ? LFColor.returnOrange.opacity(0.14) : Color.clear)
                )
                .overlay(
                    Capsule().stroke(
                        selected ? LFColor.returnOrange.opacity(0.42) : editorInk.opacity(0.22),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private func selectKind(_ value: Kind) {
        kind = value
        guard value == .steps, steps.isEmpty else { return }
        let first = DestinationStep(name: "")
        steps = [first]
        DispatchQueue.main.async { focusedStepID = first.id }
    }

    /// 空行が既にあれば増やさず、その行の入力へ戻す。
    private func addStep() {
        if let blank = steps.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            focusedStepID = blank.id
            return
        }
        guard steps.count < Destination.maxSteps else { return }
        let step = DestinationStep(name: "")
        steps.append(step)
        DispatchQueue.main.async { focusedStepID = step.id }
    }

    private func removeStep(id: DestinationStep.ID) {
        guard steps.count > 1 else { return }
        var next = steps
        next.removeAll { $0.id == id }
        steps = next
        persistSteps(next)
    }

    private func advanceFromStep(id: DestinationStep.ID) {
        persistSteps()
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        if steps.indices.contains(index + 1) {
            focusedStepID = steps[index + 1].id
        } else if !steps[index].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addStep()
        }
    }

    private var stepsEditor: some View {
        VStack(spacing: 8) {
            VStack(spacing: 7) {
                HStack {
                    Text("\(completedStepCount) of \(namedSteps.count) completed")
                        .font(LFFont.label(12))
                        .foregroundStyle(
                            allStepsComplete
                                ? LFColor.returnOrange
                                : editorInk.opacity(0.72)
                        )
                    Spacer()
                    Text("\(steps.count) / \(Destination.maxSteps) steps")
                        .font(LFFont.label(11))
                        .foregroundStyle(editorInk.opacity(0.50))
                }

                ProgressView(value: stepProgressRatio)
                    .tint(LFColor.returnOrange)
            }
            .padding(.horizontal, 4)

            ForEach($steps) { $step in
                let stepNumber = (steps.firstIndex(where: { $0.id == step.id }) ?? 0) + 1
                let hasName = !step.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Button {
                            toggleStep(id: step.id)
                        } label: {
                            ZStack {
                                Circle()
                                    .strokeBorder(
                                        step.doneAt != nil
                                            ? LFColor.returnOrange
                                            : editorInk.opacity(0.42),
                                        lineWidth: 1.5
                                    )
                                    .background(
                                        Circle().fill(
                                            step.doneAt != nil ? LFColor.returnOrange : .clear
                                        )
                                    )
                                    .frame(width: 26, height: 26)
                                if step.doneAt != nil {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(LFColor.inkFixed)
                                } else {
                                    Text(verbatim: "\(stepNumber)")
                                        .font(LFFont.label(11))
                                        .foregroundStyle(editorInk.opacity(0.72))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasName)
                        .opacity(hasName ? 1 : 0.45)
                        .accessibilityLabel(
                            Text(step.doneAt == nil ? "Mark complete" : "Mark incomplete")
                        )

                        TextField("e.g. one pass of the vocab book", text: $step.name)
                            .font(LFFont.copy(15))
                            .foregroundStyle(editorInk)
                            .strikethrough(step.doneAt != nil, color: editorInk.opacity(0.6))
                            .focused($focusedStepID, equals: step.id)
                            .submitLabel(stepNumber < Destination.maxSteps ? .next : .done)
                            .onSubmit { advanceFromStep(id: step.id) }

                        Button {
                            toggleStepSchedule(id: step.id)
                        } label: {
                            Image(systemName: step.scheduledAt == nil ? "calendar" : "calendar.badge.checkmark")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(
                                    step.scheduledAt == nil
                                        ? editorInk.opacity(0.5)
                                        : LFColor.returnOrange
                                )
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Set schedule"))

                        if steps.count > 1 {
                            Button {
                                removeStep(id: step.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 13))
                                    .foregroundStyle(editorInk.opacity(0.5))
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Delete step"))
                        } else {
                            Color.clear
                                .frame(width: 30, height: 30)
                                .accessibilityHidden(true)
                        }
                    }

                    if step.scheduledAt != nil {
                        HStack(spacing: 8) {
                            Text("Scheduled for")
                                .font(LFFont.label(11))
                                .foregroundStyle(editorInk.opacity(0.62))
                            Spacer()
                            DatePicker(
                                "",
                                selection: stepScheduledAtBinding(id: step.id),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .font(LFFont.label(11))
                            .tint(LFColor.returnOrange)
                            .environment(\.colorScheme, .light)
                            .fixedSize()

                            Button {
                                clearStepSchedule(id: step.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(editorInk.opacity(0.42))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Clear schedule"))
                        }
                        .padding(.leading, 36)
                    }

                    if step.doneAt != nil {
                        HStack(spacing: 8) {
                            Text("Completed at")
                                .font(LFFont.label(11))
                                .foregroundStyle(LFColor.returnOrange)
                            Spacer()
                            DatePicker(
                                "",
                                selection: stepDoneAtBinding(id: step.id),
                                in: ...Date(),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .font(LFFont.label(11))
                            .tint(LFColor.returnOrange)
                            .environment(\.colorScheme, .light)
                            .fixedSize()
                        }
                        .padding(.leading, 36)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(editorInk.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if steps.count < Destination.maxSteps {
                Button {
                    addStep()
                } label: {
                    Text("+ Add a step")
                        .font(LFFont.copy(15))
                        .foregroundStyle(editorInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .strokeBorder(editorInk.opacity(0.28),
                                              style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                }
                .buttonStyle(.plain)
            }

            if allStepsComplete {
                Label("All steps complete. You can go ashore.", systemImage: "flag.checkered")
                    .font(LFFont.label(12))
                    .foregroundStyle(LFColor.returnOrange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
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
                        .fill(isValid ? LFColor.returnOrange : editorInk.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isValid || working)
    }

    // MARK: - ステップの反転(既存目的地はその場で確定=Web persistSteps)

    private func toggleStep(id: DestinationStep.ID) {
        guard let i = steps.firstIndex(where: { $0.id == id }) else { return }
        toggleStep(index: i)
    }

    /// ブイのタップ(世界)/チェックのタップ(パネル)共通。
    private func toggleStep(index i: Int) {
        guard steps.indices.contains(i) else { return }
        guard !steps[i].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            focusedStepID = steps[i].id
            return
        }
        var next = steps
        next[i].doneAt = next[i].doneAt == nil ? Date() : nil
        let completed = next[i].doneAt != nil
        steps = next
        SoundFX.plink()
        if completed {
            Haptics.success()
        } else {
            Haptics.tap(.light)
        }
        persistSteps(next)
    }

    /// 達成済みステップの日付と時刻を後から直す。変更のたびに既存目的地へ確定する。
    private func stepDoneAtBinding(id: DestinationStep.ID) -> Binding<Date> {
        Binding(
            get: {
                steps.first(where: { $0.id == id })?.doneAt ?? Date()
            },
            set: { value in
                guard let i = steps.firstIndex(where: { $0.id == id }) else { return }
                var next = steps
                next[i].doneAt = value
                steps = next
                persistSteps(next)
            }
        )
    }

    private func stepScheduledAtBinding(id: DestinationStep.ID) -> Binding<Date> {
        Binding(
            get: {
                steps.first(where: { $0.id == id })?.scheduledAt ?? Date()
            },
            set: { value in
                guard let i = steps.firstIndex(where: { $0.id == id }) else { return }
                var next = steps
                next[i].scheduledAt = value
                steps = next
                persistSteps(next)
            }
        )
    }

    private func toggleStepSchedule(id: DestinationStep.ID) {
        guard let i = steps.firstIndex(where: { $0.id == id }) else { return }
        var next = steps
        if next[i].scheduledAt == nil {
            next[i].scheduledAt = Calendar.current.date(
                byAdding: .day,
                value: 1,
                to: Date()
            ) ?? Date()
        } else {
            next[i].scheduledAt = nil
        }
        steps = next
        persistSteps(next)
        Haptics.tap(.light)
    }

    private func clearStepSchedule(id: DestinationStep.ID) {
        guard let i = steps.firstIndex(where: { $0.id == id }) else { return }
        var next = steps
        next[i].scheduledAt = nil
        steps = next
        persistSteps(next)
        Haptics.tap(.light)
    }

    /// チェックの反転は、既存の目的地ならその場で確定する(fire-and-forget)。
    /// 新規(未保存)は局所stateだけ動かし、確定は「保存」に委ねる。
    private func persistSteps(_ source: [DestinationStep]? = nil) {
        let validSteps = validSteps(from: source ?? steps)
        guard let existing, !trimmedName.isEmpty, !validSteps.isEmpty else { return }
        existing.name = trimmedName
        // 新しい配列を再代入し、SwiftData に Codable 配列の変更を確実に検知させる。
        existing.steps = validSteps.map {
            DestinationStep(
                id: $0.id,
                name: String($0.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)),
                scheduledAt: $0.scheduledAt,
                doneAt: $0.doneAt
            )
        }
        existing.targetDate = nil
        existing.targetHasTime = false
        existing.targetMinutes = nil
        existing.manual = false
        existing.manualDone = false
        existing.updatedAt = Date()
        try? modelContext.save()
        SyncService.shared.push(existing)
    }

    // MARK: - 保存/削除

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
            dest.targetHasTime = withTime
            dest.steps = []
        } else {
            // 名前を整えて上限で切る(Web saveDestination と同じ)。
            dest.steps = namedSteps.prefix(Destination.maxSteps).map {
                DestinationStep(
                    id: $0.id,
                    name: String($0.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)),
                    scheduledAt: $0.scheduledAt,
                    doneAt: $0.doneAt
                )
            }
            dest.targetDate = nil
            dest.targetHasTime = false
        }
        // 現行Webエディタで選べる目標は期日/ステップの2種類。
        dest.targetMinutes = nil
        dest.manual = false
        dest.manualDone = false
        dest.updatedAt = Date()
        try? modelContext.save()
        SyncService.shared.push(dest)
        Haptics.success()
        requestClose()
    }

    /// Web版と同じく、到達条件を満たす前でも本人の意思で航海を締められる。
    private func landEarly() {
        guard let existing, !working else { return }
        working = true
        let landedAt = Date()
        existing.achievedAt = landedAt
        existing.updatedAt = landedAt
        try? modelContext.save()
        SyncService.shared.push(existing)
        Haptics.success()
        onLand(existing)
        requestClose(persistDraft: false)
    }

    /// 退場のドリーアウトを開始する(演出後に dismiss)。
    private func requestClose(persistDraft: Bool = true) {
        // 既存のステップ目標は、保存ボタンを押さず閉じても編集内容を失わない。
        if persistDraft, kind == .steps { persistSteps() }
        if usesHomeWorld {
            nameFocused = false
            onRequestClose?()
            return
        }
        closing = true
    }

    private func remove() {
        guard let existing else { return }
        SyncService.shared.delete(existing)
        modelContext.delete(existing)
        try? modelContext.save()
        Haptics.success()
        // 削除後の下書きを保存すると目的地が復活してしまうため、そのまま閉じる。
        requestClose(persistDraft: false)
    }
}
