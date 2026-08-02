import SwiftData
import SwiftUI

/// 航海中の景色を閉じず、その上へ日付と感想欄だけを浮かべる航海誌。
/// 過去の頁は日付の左右操作で辿り、今日と昨日だけを書き換えられる。
struct LogbookView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \StudyDay.date) private var days: [StudyDay]
    @Query private var sessions: [StudySession]
    @Query private var destinations: [Destination]

    @State private var today = Date()
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var draft = ""
    @State private var savedReflection = ""
    @FocusState private var reflectionFocused: Bool

    private let calendar = Calendar.current

    private var canEdit: Bool {
        StudyDayStore.canEditComment(for: selectedDate, now: today, calendar: calendar)
    }

    private var isDirty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines) != savedReflection
    }

    /// カレンダーを置かず、感想のある日と今日・昨日だけを静かに頁送りする。
    private var pageDates: [Date] {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let reflectedDates = days.compactMap { day -> Date? in
            let note = day.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return note.isEmpty ? nil : calendar.startOfDay(for: day.date)
        }
        let landfallDates = destinations.compactMap { destination in
            destination.achievedAt.map { calendar.startOfDay(for: $0) }
        }
        return Array(Set(reflectedDates + landfallDates + [
            calendar.startOfDay(for: today),
            calendar.startOfDay(for: yesterday),
        ])).sorted(by: >)
    }

    private var selectedLandfalls: [Destination] {
        destinations
            .filter { destination in
                guard let achievedAt = destination.achievedAt else { return false }
                return calendar.isDate(achievedAt, inSameDayAs: selectedDate)
            }
            .sorted { ($0.achievedAt ?? .distantPast) > ($1.achievedAt ?? .distantPast) }
    }

    private var selectedPageIndex: Int? {
        pageDates.firstIndex { calendar.isDate($0, inSameDayAs: selectedDate) }
    }

    private var canOpenOlderPage: Bool {
        guard let selectedPageIndex else { return false }
        return selectedPageIndex + 1 < pageDates.count
    }

    private var canOpenNewerPage: Bool {
        guard let selectedPageIndex else { return false }
        return selectedPageIndex > 0
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.07)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    closeButton
                }
                .padding(.horizontal, 18)
                .safeAreaPadding(.top, 8)

                Spacer(minLength: 54)

                reflectionPane
                    .frame(maxWidth: 580)
                    .padding(.horizontal, 24)

                Spacer(minLength: 96)
            }
        }
        .background(Color.clear)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { reflectionFocused = false }
            }
        }
        .onAppear { refreshToday(selectToday: true) }
        .onChange(of: reflectionFocused) { _, focused in
            if !focused { commitReflection() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshToday(selectToday: false) }
            if phase == .inactive || phase == .background { commitReflection() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshToday(selectToday: false)
        }
    }

    private var reflectionPane: some View {
        VStack(spacing: 22) {
            HStack(spacing: 18) {
                pageButton(systemName: "chevron.left", enabled: canOpenOlderPage) {
                    movePage(by: 1)
                }

                Spacer(minLength: 0)

                Text(verbatim: LF.fullDate(selectedDate))
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(Color.white.opacity(0.94))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 0)

                pageButton(systemName: "chevron.right", enabled: canOpenNewerPage) {
                    movePage(by: -1)
                }
            }

            if !selectedLandfalls.isEmpty {
                landfallRecords
            }

            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("Write reflection")
                        .font(.system(size: 17, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $draft)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(canEdit ? 0.96 : 0.76))
                    .tint(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($reflectionFocused)
                    .disabled(!canEdit)
                    .frame(height: 196)
                    .onChange(of: draft) { _, value in
                        if value.count > 1_000 { draft = String(value.prefix(1_000)) }
                    }
            }
            .padding(.horizontal, 4)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(reflectionFocused ? 0.58 : 0.24))
                    .frame(height: 1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 26)
        .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
    }

    private var landfallRecords: some View {
        VStack(spacing: 10) {
            ForEach(selectedLandfalls) { destination in
                HStack(spacing: 12) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LFColor.returnOrange)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.09), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Landfall record")
                            .font(LFFont.label(10))
                            .tracking(1.1)
                            .foregroundStyle(LFColor.returnOrange)
                        Text(verbatim: destination.name)
                            .font(LFFont.copy(16))
                            .foregroundStyle(Color.white.opacity(0.94))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    let minutes = workMinutes(for: destination)
                    if minutes > 0 {
                        Text(verbatim: LF.duration(minutes: minutes))
                            .font(LFFont.label(12))
                            .foregroundStyle(Color.white.opacity(0.58))
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(LFColor.returnOrange.opacity(0.22), lineWidth: 1)
        }
    }

    private var closeButton: some View {
        Button {
            reflectionFocused = false
            commitReflection()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
                .frame(width: 42, height: 42)
                .background(Color.black.opacity(0.22), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(LFPressableButtonStyle(scale: 0.94))
        .accessibilityLabel(Text("Close"))
    }

    private func pageButton(
        systemName: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(enabled ? 0.86 : 0.20))
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(LFPressableButtonStyle(scale: 0.90))
        .disabled(!enabled)
        .accessibilityLabel(Text(systemName == "chevron.left" ? "Previous day" : "Next day"))
    }

    private func movePage(by delta: Int) {
        guard let selectedPageIndex else { return }
        let target = selectedPageIndex + delta
        guard pageDates.indices.contains(target) else { return }
        commitReflection()
        selectedDate = pageDates[target]
        loadReflection()
        Haptics.tap(.light)
    }

    private func workMinutes(for destination: Destination) -> Int {
        guard let achievedAt = destination.achievedAt else { return 0 }
        return sessions.reduce(0) { total, session in
            guard session.date >= destination.createdAt, session.date <= achievedAt else {
                return total
            }
            if let itemUUID = destination.itemUUID,
               session.item?.uuid.uuidString != itemUUID {
                return total
            }
            return total + session.minutes
        }
    }

    private func loadReflection() {
        let stored = StudyDayStore.comment(for: selectedDate, context: modelContext) ?? ""
        draft = stored
        savedReflection = stored
    }

    private func commitReflection() {
        guard canEdit, isDirty else { return }
        if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           StudyDayStore.comment(for: selectedDate, context: modelContext) == nil {
            StudyDayStore.markDay(selectedDate, context: modelContext)
        }
        _ = StudyDayStore.setComment(draft, for: selectedDate, context: modelContext, now: today)
        loadReflection()
    }

    private func refreshToday(selectToday: Bool) {
        let refreshed = Date()
        let crossedDay = !calendar.isDate(refreshed, inSameDayAs: today)
        today = refreshed
        if selectToday || crossedDay {
            commitReflection()
            selectedDate = calendar.startOfDay(for: refreshed)
            loadReflection()
        }
    }
}
