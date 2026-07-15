import SwiftUI
import SwiftData

/// 「今日」画面。記録は最小、催促はしない。
/// 未記録なら日付・任意メモ・記録ボタン、記録済みなら静かな完了表示だけを出す。
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \StudyDay.date, order: .reverse) private var entries: [StudyDay]

    @State private var noteText = ""
    @State private var showWelcomeBack = false
    @State private var showingSettings = false
    /// 「今日」。日跨ぎ後の初操作をブロックしないよう、前景復帰と日付変化で更新する。
    @State private var today = Date()
    @FocusState private var noteFieldFocused: Bool

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日(E)"
        return formatter
    }()

    /// 今日の記録(あれば)。unique制約に加えUI側でも二重記録を防ぐ。
    private var todayEntry: StudyDay? {
        let calendar = Calendar.current
        return entries.first { calendar.isDate($0.date, inSameDayAs: today) }
    }

    var body: some View {
        ZStack {
            LFColor.paper.ignoresSafeArea()

            if let entry = todayEntry {
                recordedContent(entry: entry)
            } else {
                unrecordedContent
            }

            settingsButton

            if showWelcomeBack {
                welcomeBackOverlay
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["LANDFALL_SETTINGS"] != nil {
                showingSettings = true
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { today = Date() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            today = Date()
        }
    }

    // MARK: - 設定入口(右上・控えめ)

    private var settingsButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    noteFieldFocused = false
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(LFColor.ink.opacity(0.4))
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - 未記録状態

    private var unrecordedContent: some View {
        VStack(spacing: 0) {
            Text(Self.dateFormatter.string(from: today))
                .font(LFFont.copy(20))
                .foregroundStyle(LFColor.ink)
                .padding(.top, 32)

            Spacer()

            TextField("ひとこと(任意)", text: $noteText)
                .font(LFFont.label(17))
                .foregroundStyle(LFColor.ink)
                .tint(LFColor.ink)
                .focused($noteFieldFocused)
                .submitLabel(.done)
                .padding(.horizontal, 20)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(LFColor.ink.opacity(0.2), lineWidth: 1)
                )

            Spacer()

            Button(action: record) {
                Text("今日の分を刻む")
                    .font(LFFont.copy(18))
                    .foregroundStyle(LFColor.paper)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(LFColor.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - 記録済み状態

    private func recordedContent(entry: StudyDay) -> some View {
        VStack(spacing: 16) {
            Text("今日の分は、刻んである。")
                .font(LFFont.copy(20))
                .foregroundStyle(LFColor.ink)
            if let note = entry.note {
                Text(note)
                    .font(LFFont.label(15))
                    .foregroundStyle(LFColor.ink.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - おかえり演出(空白2日以上のときだけ)

    private var welcomeBackOverlay: some View {
        ZStack {
            LFColor.paper.opacity(0.94).ignoresSafeArea()
            Text("おかえり。")
                .font(LFFont.copy(26))
                .foregroundStyle(LFColor.ink)
        }
        .transition(.opacity)
    }

    // MARK: - 記録

    private func record() {
        noteFieldFocused = false
        guard todayEntry == nil else { return }

        let now = Date()
        // 保存の前に空白日数を測る(保存後だと最終記録日=今日になってしまう)。
        let blanks = MonthStats.blankDays(since: entries.first?.date, to: now)

        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        modelContext.insert(StudyDay(date: now, note: trimmed.isEmpty ? nil : trimmed))
        try? modelContext.save()
        noteText = ""

        if let blanks, blanks >= 2 {
            Task {
                withAnimation(.easeInOut(duration: 0.25)) { showWelcomeBack = true }
                try? await Task.sleep(nanoseconds: 1_250_000_000)
                withAnimation(.easeInOut(duration: 0.25)) { showWelcomeBack = false }
            }
        }
    }
}

// MARK: - Previews

#Preview("未記録") {
    let container = try! ModelContainer(
        for: StudyDay.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return TodayView().modelContainer(container)
}

#Preview("記録済み") {
    let container = try! ModelContainer(
        for: StudyDay.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    container.mainContext.insert(StudyDay(date: Date(), note: "英単語を30個やった。"))
    return TodayView().modelContainer(container)
}

#Preview("おかえり(3日ぶり)") {
    let container = try! ModelContainer(
        for: StudyDay.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let calendar = Calendar.current
    if let past = calendar.date(byAdding: .day, value: -4, to: Date()) {
        container.mainContext.insert(StudyDay(date: past))
    }
    return TodayView().modelContainer(container)
}
