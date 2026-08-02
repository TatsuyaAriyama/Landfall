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

    init(
        existing: Destination?,
        sessions: [StudySession],
        usesHomeWorld: Bool = false,
        homeWorldReady: Bool = true,
        homeWorldTapToken: Int = 0,
        onRequestClose: (() -> Void)? = nil,
        onLand: @escaping (Destination) -> Void = { _ in }
    ) {
        self.existing = existing
        self.sessions = sessions
        self.usesHomeWorld = usesHomeWorld
        self.homeWorldReady = homeWorldReady
        self.homeWorldTapToken = homeWorldTapToken
        self.onRequestClose = onRequestClose
        self.onLand = onLand
        _name = State(initialValue: existing?.name ?? "")
        let hasSteps = !(existing?.steps.isEmpty ?? true)
        _kind = State(initialValue: hasSteps ? .steps : .date)
        let defaultDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        _targetDate = State(initialValue: existing?.targetDate ?? defaultDate)
        _hasTargetDate = State(initialValue: existing?.targetDate != nil)
        _withTime = State(initialValue: existing?.targetHasTime == true)
        _steps = State(initialValue: existing?.steps ?? [])
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var namedSteps: [DestinationStep] {
        steps.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
    /// 編集中の局所stateから、船の位置(ratio)を出す。
    private var liveRatio: Double {
        if kind == .steps {
            guard !steps.isEmpty else { return 0 }
            return Double(steps.filter { $0.doneAt != nil }.count) / Double(steps.count)
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
                    steps: kind == .steps ? steps.map { VoyageStep(doneAt: $0.doneAt) } : [],
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
            #if DEBUG
            if ProcessInfo.processInfo.environment["LANDFALL_IMMERSE"] != nil { uiHidden = true }
            #endif
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

    private var topBar: some View {
        VStack {
            HStack(spacing: 10) {
                TextField("e.g. TOEIC, finish the book", text: $name)
                    .font(LFFont.copy(16))
                    .foregroundStyle(LFColor.harborSand)
                    .focused($nameFocused)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 18)
                    .frame(height: 48)
                    .background(
                        Color(VoyageSceneKit.seaDeep).opacity(0.62),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule()
                            .stroke(LFColor.harborSand.opacity(0.28), lineWidth: 1)
                    )
                    .accessibilityLabel(Text("Island name"))

                Button { requestClose() } label: {
                    Text("Close")
                        .font(LFFont.copy(14))
                        .foregroundStyle(LFColor.harborSand)
                        .padding(.horizontal, 18)
                        .frame(height: 48)
                        .background(
                            Color(VoyageSceneKit.seaDeep).opacity(0.62),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(LFColor.harborSand.opacity(0.28), lineWidth: 1)
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
                    .foregroundStyle(LFColor.harborSand.opacity(0.58))

                HStack(spacing: 10) {
                    kindChip("Set a date", .date)
                    kindChip("Follow steps", .steps)
                }

                if kind == .date {
                    dateEditor
                } else {
                    Text("Break a big goal into small steps. Each one you finish moves the boat forward; finish them all to make landfall.")
                        .font(LFFont.copy(14))
                        .foregroundStyle(LFColor.harborSand.opacity(0.7))
                    stepsEditor
                }

                Text("Drag to look around. Pinch to zoom in. Tap the world to see only it.")
                    .font(LFFont.label(11))
                    .foregroundStyle(LFColor.harborSand.opacity(0.45))

                saveButton

                if let existing,
                   !existing.progress(sessions: sessions).reached {
                    Button {
                        confirmingLand = true
                    } label: {
                        Text("Go ashore here")
                            .font(LFFont.copy(13))
                            .foregroundStyle(LFColor.harborSand.opacity(0.68))
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
            Color(VoyageSceneKit.seaDeep).opacity(0.90),
            in: RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous)
        )
        .padding(.horizontal, 16)
        .safeAreaPadding(.bottom, 12)
    }

    private var dateEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The target date guides your voyage. When you achieve it, choose Go ashore. Without a time, the whole day counts.")
                .font(LFFont.copy(14))
                .foregroundStyle(LFColor.harborSand.opacity(0.7))

            Text("Target date")
                .font(LFFont.label(13))
                .tracking(0.7)
                .foregroundStyle(LFColor.harborSand.opacity(0.58))

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
                .environment(\.colorScheme, .dark)
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
                    .foregroundStyle(LFColor.harborSand)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(LFColor.harborSand.opacity(0.28), lineWidth: 1)
                    )
                }
                .buttonStyle(LFPressableButtonStyle())
            }

            Toggle("Set a time too", isOn: $withTime)
                .font(LFFont.copy(14))
                .tint(LFColor.harborSand)
                .foregroundStyle(LFColor.harborSand.opacity(0.82))
                .disabled(!hasTargetDate)

            if withTime && hasTargetDate {
                DatePicker(
                    "Deadline time",
                    selection: $targetDate,
                    displayedComponents: .hourAndMinute
                )
                .font(LFFont.copy(14))
                .tint(LFColor.returnOrange)
                .foregroundStyle(LFColor.harborSand)
                .environment(\.colorScheme, .dark)

                Text(deadlinePassed
                     ? "That time has passed. Pick a later one."
                     : "This is the date you aim to achieve it.")
                    .font(LFFont.label(12))
                    .foregroundStyle(
                        deadlinePassed ? LFColor.coral : LFColor.harborSand.opacity(0.62)
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
                VStack(alignment: .leading, spacing: 6) {
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
                            .submitLabel(.done)
                            .onSubmit { persistSteps() }

                        Button {
                            var next = steps
                            next.removeAll { $0.id == step.id }
                            steps = next
                            persistSteps(next)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13))
                                .foregroundStyle(LFColor.harborSand.opacity(0.5))
                        }
                        .buttonStyle(.plain)
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
                            .environment(\.colorScheme, .dark)
                            .fixedSize()
                        }
                        .padding(.leading, 36)
                    }
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
        var next = steps
        next[i].doneAt = next[i].doneAt == nil ? Date() : nil
        steps = next
        SoundFX.plink()
        Haptics.tap(.light)
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

    /// チェックの反転は、既存の目的地ならその場で確定する(fire-and-forget)。
    /// 新規(未保存)は局所stateだけ動かし、確定は「保存」に委ねる。
    private func persistSteps(_ source: [DestinationStep]? = nil) {
        let validSteps = (source ?? steps).filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let existing, !trimmedName.isEmpty, !validSteps.isEmpty else { return }
        existing.name = trimmedName
        // 新しい配列を再代入し、SwiftData に Codable 配列の変更を確実に検知させる。
        existing.steps = validSteps.map {
            DestinationStep(
                id: $0.id,
                name: String($0.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)),
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
            dest.steps = namedSteps.map {
                DestinationStep(id: $0.id, name: String($0.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)), doneAt: $0.doneAt)
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
