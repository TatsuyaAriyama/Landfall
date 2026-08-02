import SwiftData
import SwiftUI

/// Web版の最新「軌跡」をiOSへ移植した画面。
/// カレンダーで月と一日を辿り、索引では記録に添えた言葉を検索できる。
struct TraceView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case calendar
        case index

        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .calendar: "Calendar"
            case .index: "Index"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \StudyDay.date) private var entries: [StudyDay]
    @Query(sort: \StudySession.date) private var sessions: [StudySession]
    @Query(sort: \StudyItem.sortOrder) private var items: [StudyItem]

    private let onClose: (() -> Void)?
    private let calendar = Calendar.current

    @State private var section: Section = .calendar
    @State private var today = Date()
    @State private var monthOffset = 0
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var dayNoteDraft = ""
    @State private var searchText = ""
    @State private var selectedItemID: UUID?
    @State private var editingSession: StudySession?
    @State private var pendingDelete: StudySession?
    @FocusState private var dayNoteFocused: Bool

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    private var displayedDate: Date {
        calendar.date(byAdding: .month, value: monthOffset, to: today) ?? today
    }

    private var displayedMonthStart: Date {
        calendar.date(
            from: calendar.dateComponents([.year, .month], from: displayedDate)
        ) ?? calendar.startOfDay(for: displayedDate)
    }

    private var isCurrentMonth: Bool { monthOffset == 0 }

    private var selectedSessions: [StudySession] {
        sessions
            .filter { calendar.isDate($0.date, inSameDayAs: selectedDay) }
            .sorted { $0.date < $1.date }
    }

    private var selectedTotal: Int {
        selectedSessions.reduce(0) { $0 + $1.minutes }
    }

    private var selectedDayEntry: StudyDay? {
        entries.first { calendar.isDate($0.date, inSameDayAs: selectedDay) }
    }

    private var canEditSelectedReflection: Bool {
        StudyDayStore.canEditComment(for: selectedDay, now: today, calendar: calendar)
    }

    private var recordedDayStarts: Set<Date> {
        Set(entries.map { calendar.startOfDay(for: $0.date) })
    }

    private var serviceStartDay: Date? {
        let epochGuard = calendar.date(
            from: DateComponents(year: 2000, month: 1, day: 1)
        ) ?? .distantPast
        var candidates = entries.map(\.date) + sessions.map(\.date)
        if let stored = PlayerProfile.sinceDayFormatter.date(from: PlayerProfile.sinceDay) {
            candidates.append(stored)
        }
        return candidates
            .filter { $0 > epochGuard }
            .map { calendar.startOfDay(for: $0) }
            .min()
    }

    var body: some View {
        ZStack {
            LFColor.paper.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    sectionPicker
                        .padding(.top, 18)

                    Group {
                        switch section {
                        case .calendar:
                            calendarSection
                        case .index:
                            notesIndex
                        }
                    }
                    .padding(.top, 24)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 42)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .tint(LFColor.ink)
        .sheet(item: $editingSession) { session in
            SessionEditSheet(session: session)
        }
        .confirmationDialog(
            "Delete this record?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDelete {
                    deleteSession(pendingDelete)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        }
        .onAppear {
            today = Date()
            if monthOffset == 0 {
                selectedDay = calendar.startOfDay(for: today)
            }
            loadDayNote()
        }
        .onChange(of: selectedDayEntry?.note) { _, _ in
            if !dayNoteFocused { loadDayNote() }
        }
        .onChange(of: dayNoteFocused) { _, focused in
            if !focused { commitDayNote() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshToday()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshToday()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let onClose {
                Button {
                    commitDayNote()
                    onClose()
                    Haptics.tap(.light)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LFColor.paper)
                        .frame(width: 36, height: 36)
                        .background(LFColor.ink, in: Circle())
                }
                .buttonStyle(LFPressableButtonStyle())
                .accessibilityLabel(Text("Close"))
            }

            Text("Trace")
                .font(LFFont.copy(26))
                .foregroundStyle(LFColor.ink)

            Spacer(minLength: 0)
        }
        .padding(.top, 10)
    }

    private var sectionPicker: some View {
        HStack(spacing: 8) {
            ForEach(Section.allCases) { candidate in
                Button {
                    commitDayNote()
                    section = candidate
                    Haptics.tap(.light)
                } label: {
                    Text(candidate.title)
                        .font(LFFont.label(14))
                        .foregroundStyle(
                            section == candidate ? LFColor.paper : LFColor.ink.opacity(0.72)
                        )
                        .padding(.horizontal, 17)
                        .frame(height: 44)
                        .background(
                            section == candidate ? LFColor.ink : Color.clear,
                            in: Capsule(style: .continuous)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(
                                    section == candidate
                                        ? Color.clear : LFColor.ink.opacity(0.22),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(LFPressableButtonStyle())
                .accessibilityAddTraits(section == candidate ? .isSelected : [])
            }
        }
    }

    // MARK: - カレンダー

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            monthNavigation

            if !isCurrentMonth {
                HStack {
                    Spacer()
                    Button {
                        returnToToday()
                    } label: {
                        Text("Today")
                            .font(LFFont.label(13))
                            .foregroundStyle(LFColor.ink.opacity(0.72))
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .overlay(
                                Capsule().stroke(LFColor.ink.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(LFPressableButtonStyle())
                    Spacer()
                }
                .padding(.top, 2)
                .padding(.bottom, 12)
            }

            calendarGrid

            statistics
                .padding(.top, 25)

            selectedDaySection
                .padding(.top, 32)
        }
    }

    private var monthNavigation: some View {
        HStack {
            monthButton(
                systemName: "chevron.left",
                label: "Previous month",
                enabled: true
            ) {
                moveMonth(by: -1)
            }

            Spacer()

            Text(
                LF.monthYear(
                    year: calendar.component(.year, from: displayedMonthStart),
                    month: calendar.component(.month, from: displayedMonthStart)
                )
            )
            .font(LFFont.copy(20))
            .foregroundStyle(LFColor.ink)

            Spacer()

            monthButton(
                systemName: "chevron.right",
                label: "Next month",
                enabled: !isCurrentMonth
            ) {
                moveMonth(by: 1)
            }
        }
    }

    private func monthButton(
        systemName: String,
        label: LocalizedStringKey,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            commitDayNote()
            action()
            Haptics.tap(.light)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(LFColor.ink.opacity(enabled ? 0.72 : 0.2))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(LFPressableButtonStyle())
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
    }

    private var calendarGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let cells = monthCells
        let studiedDays = recordedDayStarts
        let startDay = serviceStartDay

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(verbatim: symbol)
                    .font(LFFont.label(11))
                    .foregroundStyle(LFColor.ink.opacity(0.44))
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
            }

            ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayCell(date, studiedDays: studiedDays, startDay: startDay)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    private func dayCell(
        _ date: Date,
        studiedDays: Set<Date>,
        startDay: Date?
    ) -> some View {
        let dayStart = calendar.startOfDay(for: date)
        let todayStart = calendar.startOfDay(for: today)
        let isFuture = dayStart > todayStart
        let isToday = calendar.isDate(dayStart, inSameDayAs: todayStart)
        let studied = studiedDays.contains(dayStart)
        let beforeStart = startDay.map { dayStart < $0 } ?? false
        let rested = !studied && !isFuture && !isToday && !beforeStart
        let selected = calendar.isDate(dayStart, inSameDayAs: selectedDay)

        return Button {
            selectDay(dayStart)
        } label: {
            Text(verbatim: "\(calendar.component(.day, from: date))")
                .font(LFFont.label(14))
                .monospacedDigit()
                .foregroundStyle(
                    studied || rested
                        ? LFColor.inkFixed
                        : LFColor.ink.opacity(isFuture || beforeStart ? 0.28 : 0.76)
                )
                .frame(width: 40, height: 40)
                .background(
                    studied
                        ? LFColor.seaGreen
                        : (rested ? LFColor.sunYellow : Color.clear),
                    in: Circle()
                )
                .overlay(
                    Circle().stroke(
                        isToday ? LFColor.returnOrange : Color.clear,
                        lineWidth: 1.5
                    )
                )
                .overlay(
                    Circle()
                        .stroke(selected ? LFColor.ink : Color.clear, lineWidth: 2)
                        .padding(-3)
                )
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(Text(LF.dayWithWeekday(date)))
        .accessibilityValue(
            Text(
                studied
                    ? LF.text("Studied")
                    : (rested ? LF.text("Rested") : "")
            )
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var statistics: some View {
        let stats = monthStatistics
        return HStack(alignment: .top, spacing: 16) {
            statistic(value: "\(stats.studied)", label: "Days studied")
            statistic(value: "\(stats.rested)", label: "Days rested")
            statistic(value: LF.duration(minutes: stats.minutes), label: "Month total", compact: true)
        }
    }

    private func statistic(
        value: String,
        label: LocalizedStringKey,
        compact: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: value)
                .font(compact ? LFFont.number(20) : LFFont.number(28))
                .monospacedDigit()
                .foregroundStyle(LFColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(LFFont.label(11))
                .foregroundStyle(LFColor.returnOrange)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var selectedDaySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(LF.dayWithWeekday(selectedDay))
                    .font(LFFont.label(13))
                    .tracking(0.5)
                    .foregroundStyle(LFColor.ink.opacity(0.58))
                if selectedTotal > 0 {
                    Text(verbatim: "· \(LF.duration(minutes: selectedTotal))")
                        .font(LFFont.label(12))
                        .foregroundStyle(LFColor.returnOrange)
                }
            }

            if selectedSessions.isEmpty {
                Text(
                    calendar.isDate(selectedDay, inSameDayAs: today)
                        ? "No records yet today. The day is still ahead."
                        : "No records this day. Rest is part of the voyage."
                )
                .font(LFFont.copy(15))
                .foregroundStyle(LFColor.ink.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            } else {
                if selectedDayEntry != nil && canEditSelectedReflection {
                    TextField("Reflections on this day", text: $dayNoteDraft)
                        .font(LFFont.copy(15))
                        .foregroundStyle(LFColor.ink)
                        .tint(LFColor.returnOrange)
                        .focused($dayNoteFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            dayNoteFocused = false
                            commitDayNote()
                        }
                        .padding(.horizontal, 15)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(LFColor.ink.opacity(0.18), lineWidth: 1)
                        )
                        .accessibilityLabel(Text("Reflections on this day"))
                } else if !dayNoteDraft.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: dayNoteDraft)
                            .font(LFFont.copy(15))
                            .foregroundStyle(LFColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Only today and yesterday can be edited.")
                            .font(LFFont.label(11))
                            .foregroundStyle(LFColor.ink.opacity(0.42))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(15)
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(LFColor.ink.opacity(0.13), lineWidth: 1)
                    }
                }

                VStack(spacing: 0) {
                    ForEach(Array(selectedSessions.enumerated()), id: \.element.persistentModelID) {
                        index,
                        session in
                        if index > 0 {
                            Rectangle()
                                .fill(LFColor.ink.opacity(0.08))
                                .frame(height: 1)
                        }
                        sessionRow(session)
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: StudySession) -> some View {
        HStack(spacing: 12) {
            Button {
                editingSession = session
            } label: {
                HStack(spacing: 12) {
                    if let item = session.item {
                        ItemTileArt(item: item)
                            .frame(width: 42, height: 42)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Group {
                                if let name = session.item?.name {
                                    Text(verbatim: name)
                                } else {
                                    Text("No item")
                                }
                            }
                            .font(LFFont.copy(15))
                            .foregroundStyle(LFColor.ink)

                            Text(LF.duration(minutes: session.minutes))
                                .font(LFFont.label(13))
                                .monospacedDigit()
                                .foregroundStyle(LFColor.returnOrange)
                        }

                        if let note = session.note, !note.isEmpty {
                            Text(verbatim: note)
                                .font(LFFont.label(13))
                                .foregroundStyle(LFColor.ink.opacity(0.6))
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                pendingDelete = session
                Haptics.tap(.light)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(LFColor.deepRust.opacity(0.72))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Delete record"))
        }
        .padding(.vertical, 11)
    }

    // MARK: - 学びの索引

    private var notesIndex: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(LFColor.ink.opacity(0.42))
                TextField("Search notes", text: $searchText)
                    .font(LFFont.copy(15))
                    .foregroundStyle(LFColor.ink)
                    .tint(LFColor.returnOrange)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 15)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(LFColor.ink.opacity(0.18), lineWidth: 1)
            )

            if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(items) { item in
                            Button {
                                selectedItemID = selectedItemID == item.uuid ? nil : item.uuid
                                Haptics.tap(.light)
                            } label: {
                                HStack(spacing: 7) {
                                    ItemTileArt(item: item)
                                        .frame(width: 24, height: 24)
                                    Text(verbatim: item.name)
                                        .font(LFFont.label(12))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(
                                    selectedItemID == item.uuid ? LFColor.paper : LFColor.ink.opacity(0.72)
                                )
                                .padding(.horizontal, 12)
                                .frame(height: 44)
                                .background(
                                    selectedItemID == item.uuid ? LFColor.ink : Color.clear,
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule().stroke(
                                        selectedItemID == item.uuid
                                            ? Color.clear : LFColor.ink.opacity(0.18),
                                        lineWidth: 1
                                    )
                                )
                            }
                            .buttonStyle(LFPressableButtonStyle())
                            .accessibilityAddTraits(
                                selectedItemID == item.uuid ? .isSelected : []
                            )
                        }
                    }
                    .padding(.vertical, 3)
                }
                .padding(.top, 13)
            }

            let notes = visibleNotes
            if notes.isEmpty {
                Text("No notes yet. Add a word to a record and it gathers here.")
                    .font(LFFont.copy(15))
                    .foregroundStyle(LFColor.ink.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 28)
            } else {
                Text(LF.format("%lld notes", Int64(notes.count)))
                .font(LFFont.label(12))
                .tracking(0.5)
                .foregroundStyle(LFColor.ink.opacity(0.5))
                .padding(.top, 28)

                VStack(spacing: 0) {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        if index > 0 {
                            Rectangle()
                                .fill(LFColor.ink.opacity(0.08))
                                .frame(height: 1)
                        }
                        noteRow(note)
                    }
                }
                .padding(.top, 5)
            }
        }
    }

    private func noteRow(_ note: NoteEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(LF.dayMonth(note.date))
                if let itemName = note.itemName {
                    Text(verbatim: "· \(itemName)")
                }
            }
            .font(LFFont.label(11))
            .foregroundStyle(LFColor.ink.opacity(0.44))

            Text(verbatim: note.text)
                .font(LFFont.copy(15))
                .foregroundStyle(LFColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
    }

    private struct NoteEntry: Identifiable {
        let id: String
        let date: Date
        let text: String
        let itemName: String?
        let itemID: UUID?
    }

    private var visibleNotes: [NoteEntry] {
        var notes: [NoteEntry] = sessions.compactMap { session in
            guard let note = session.note?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !note.isEmpty else { return nil }
            return NoteEntry(
                id: "session-\(session.uuid.uuidString)",
                date: session.date,
                text: note,
                itemName: session.item?.name,
                itemID: session.item?.uuid
            )
        }

        notes += entries.compactMap { day in
            guard let note = day.note?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !note.isEmpty else { return nil }
            return NoteEntry(
                id: "day-\(day.date.timeIntervalSince1970)",
                date: day.date,
                text: note,
                itemName: nil,
                itemID: nil
            )
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes
            .filter { note in
                (query.isEmpty || note.text.localizedCaseInsensitiveContains(query)) &&
                    (selectedItemID == nil || note.itemID == selectedItemID)
            }
            .sorted {
                if $0.date != $1.date { return $0.date > $1.date }
                return $0.id > $1.id
            }
    }

    // MARK: - 日付と統計

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.current.locale
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? []
        guard symbols.count == 7 else { return ["S", "M", "T", "W", "T", "F", "S"] }
        let startIndex = max(0, min(6, calendar.firstWeekday - 1))
        return Array(symbols[startIndex...] + symbols[..<startIndex])
    }

    private var monthCells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonthStart) else {
            return []
        }
        let weekday = calendar.component(.weekday, from: displayedMonthStart)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var cells = Array<Date?>(repeating: nil, count: leading)
        cells += range.compactMap { day in
            calendar.date(
                from: DateComponents(
                    year: calendar.component(.year, from: displayedMonthStart),
                    month: calendar.component(.month, from: displayedMonthStart),
                    day: day
                )
            )
        }
        return cells
    }

    private struct MonthSummary {
        let studied: Int
        let rested: Int
        let minutes: Int
    }

    private var monthStatistics: MonthSummary {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonthStart) else {
            return MonthSummary(studied: 0, rested: 0, minutes: 0)
        }

        let todayStart = calendar.startOfDay(for: today)
        let studiedDays = recordedDayStarts
        let startDay = serviceStartDay
        var studied = 0
        var rested = 0
        for day in range {
            guard let date = calendar.date(
                from: DateComponents(
                    year: calendar.component(.year, from: displayedMonthStart),
                    month: calendar.component(.month, from: displayedMonthStart),
                    day: day
                )
            ) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            guard dayStart <= todayStart else { continue }
            guard startDay.map({ dayStart >= $0 }) ?? true else { continue }
            if studiedDays.contains(dayStart) {
                studied += 1
            } else if dayStart < todayStart {
                rested += 1
            }
        }

        let year = calendar.component(.year, from: displayedMonthStart)
        let month = calendar.component(.month, from: displayedMonthStart)
        let minutes = sessions.reduce(0) { total, session in
            let date = calendar.startOfDay(for: session.date)
            guard date <= todayStart,
                  calendar.component(.year, from: date) == year,
                  calendar.component(.month, from: date) == month else {
                return total
            }
            return total + session.minutes
        }
        return MonthSummary(studied: studied, rested: rested, minutes: minutes)
    }

    private func moveMonth(by delta: Int) {
        monthOffset = min(0, monthOffset + delta)
        let month = displayedMonthStart
        let currentMonth = calendar.isDate(month, equalTo: today, toGranularity: .month)
        if currentMonth {
            selectDay(calendar.startOfDay(for: today))
        } else if let last = calendar.range(of: .day, in: .month, for: month)?.last,
                  let lastDay = calendar.date(
                    from: DateComponents(
                        year: calendar.component(.year, from: month),
                        month: calendar.component(.month, from: month),
                        day: last
                    )
                  ) {
            selectDay(lastDay)
        } else {
            selectDay(month)
        }
    }

    private func returnToToday() {
        commitDayNote()
        monthOffset = 0
        selectDay(calendar.startOfDay(for: today))
        Haptics.tap(.light)
    }

    private func selectDay(_ date: Date) {
        guard calendar.startOfDay(for: date) <= calendar.startOfDay(for: today) else { return }
        commitDayNote()
        selectedDay = calendar.startOfDay(for: date)
        loadDayNote()
        Haptics.tap(.light)
    }

    private func refreshToday() {
        let newToday = Date()
        let crossedDay = !calendar.isDate(newToday, inSameDayAs: today)
        today = newToday
        if crossedDay && monthOffset == 0 {
            selectedDay = calendar.startOfDay(for: newToday)
            loadDayNote()
        }
    }

    // MARK: - 保存

    private func loadDayNote() {
        dayNoteDraft = StudyDayStore.comment(for: selectedDay, context: modelContext) ?? ""
    }

    private func commitDayNote() {
        guard selectedDayEntry != nil, canEditSelectedReflection else { return }
        StudyDayStore.setComment(dayNoteDraft, for: selectedDay, context: modelContext)
    }

    private func deleteSession(_ session: StudySession) {
        let date = session.date
        SyncService.shared.delete(session)
        modelContext.delete(session)
        StudyDayStore.unmarkDayIfEmpty(date, context: modelContext)
        try? modelContext.save()
        RoomService.shared.publishCurrentMonth(context: modelContext)
        WidgetBridge.refresh(context: modelContext)
        if calendar.isDate(date, inSameDayAs: selectedDay) {
            loadDayNote()
        }
        Haptics.tap()
    }
}

#Preview("Web版の最新軌跡") {
    let container = try! ModelContainer(
        for: StudyDay.self, StudyItem.self, StudySession.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let calendar = Calendar.current
    let item = StudyItem(
        name: "開発",
        styleToken: "midnight",
        symbolToken: "phoenix",
        sortOrder: 0
    )
    container.mainContext.insert(item)
    for offset in [0, -1, -3, -6, -8] {
        if let date = calendar.date(byAdding: .day, value: offset, to: .now) {
            container.mainContext.insert(
                StudySession(date: date, minutes: 30, note: "次に試すことを残した。", item: item)
            )
            StudyDayStore.markDay(date, context: container.mainContext)
        }
    }
    return TraceView().modelContainer(container)
}
