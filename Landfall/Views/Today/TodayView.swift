import SwiftUI
import SwiftData

/// 「今日」画面。学習項目のタイルが並び、タップで時間+ひとことを刻む。
/// 催促はしない。項目自体の編集は設定画面にまとめる。
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \StudyDay.date, order: .reverse) private var days: [StudyDay]
    @Query(sort: \StudyItem.sortOrder) private var items: [StudyItem]
    @Query private var sessions: [StudySession]
    @Query private var destinations: [Destination]

    @State private var showingSettings = false
    @State private var sharingToday = false
    @State private var editingDestination = false
    @State private var celebrating: Destination?
    @State private var pendingWorldLanding: Destination?
    @State private var pendingLandingDestination: Destination?
    @State private var pendingCompleteDestination: Destination?
    @State private var pendingDelete: StudySession?
    @State private var path = NavigationPath()
    /// 「今日」。日跨ぎ後の初操作をブロックしないよう、前景復帰と日付変化で更新する。
    @State private var today = Date()

    @AppStorage(StudyTimer.itemKey, store: StudyTimer.defaults) private var timerItemID: String = ""

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                LFColor.paper.ignoresSafeArea()

                VStack(spacing: 0) {
                    Text(LF.dayWithWeekday(today))
                        .font(LFFont.copy(20))
                        .foregroundStyle(LFColor.ink)
                        .padding(.top, 32)

                    ScrollView {
                        DestinationCard(
                            destination: activeDestination,
                            sessions: sessions,
                            onLand: { pendingLandingDestination = $0 },
                            onMarkDone: { pendingCompleteDestination = $0 }
                        ) {
                            editingDestination = true
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                        // 作業項目(Web: section-label「作業項目」→ 4列タイル)
                        sectionLabel("Items")
                            .padding(.horizontal, 24)
                            .padding(.top, 28)

                        if items.isEmpty {
                            Text("Create your first item in Settings.")
                                .font(LFFont.copy(15))
                                .foregroundStyle(LFColor.ink.opacity(0.5))
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.top, 4)
                        }

                        // スマホは横一列に4つ。アイコンの下に名前+総作業時間を中央寄せで小さく積む。
                        LazyVGrid(columns: fourColumns, spacing: 18) {
                            ForEach(items) { item in
                                tileCell(item)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                        todayLogSection

                        Color.clear.frame(height: 28)
                    }
                }

                settingsButton
            }
            .navigationDestination(for: StudyItem.self) { item in
                ItemDetailView(item: item)
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $sharingToday) {
            DayShareSheet(date: today)
        }
        .confirmationDialog(
            "Delete this record?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let s = pendingDelete { deleteSession(s) }
                pendingDelete = nil
            }
        }
        .fullScreenCover(
            isPresented: $editingDestination,
            onDismiss: {
                if let landed = pendingWorldLanding {
                    pendingWorldLanding = nil
                    DispatchQueue.main.async { celebrating = landed }
                }
            }
        ) {
            VoyageWorldView(existing: activeDestination, sessions: sessions, onLand: {
                pendingWorldLanding = $0
            })
        }
        .fullScreenCover(item: $celebrating) { dest in
            LandfallCelebrationView(
                destination: dest,
                minutes: dest.progress(sessions: sessions).minutes
            ) { celebrating = nil }
        }
        .onAppear {
            #if DEBUG
            DebugCardDump.runIfRequested()
            if ProcessInfo.processInfo.environment["LANDFALL_SETTINGS"] != nil {
                showingSettings = true
            }
            if ProcessInfo.processInfo.environment["LANDFALL_DETAIL"] != nil, let first = items.first {
                path.append(first)
            }
            if ProcessInfo.processInfo.environment["LANDFALL_EDIT_DEST"] != nil {
                editingDestination = true
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { today = Date() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            today = Date()
        }
        .confirmationDialog(
            "Go ashore",
            isPresented: Binding(
                get: { pendingLandingDestination != nil },
                set: { if !$0 { pendingLandingDestination = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Go ashore") {
                if let destination = pendingLandingDestination {
                    land(destination)
                }
                pendingLandingDestination = nil
            }
            Button("Cancel", role: .cancel) {
                pendingLandingDestination = nil
            }
        } message: {
            Text("Did you achieve this destination? Going ashore ends this voyage and saves it in your Logbook.")
        }
        .confirmationDialog(
            "Mark complete",
            isPresented: Binding(
                get: { pendingCompleteDestination != nil },
                set: { if !$0 { pendingCompleteDestination = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Mark complete") {
                if let destination = pendingCompleteDestination {
                    destination.manualDone = true
                    destination.updatedAt = Date()
                    try? modelContext.save()
                    SyncService.shared.push(destination)
                }
                pendingCompleteDestination = nil
            }
            Button("Cancel", role: .cancel) {
                pendingCompleteDestination = nil
            }
        } message: {
            Text("Mark this destination complete?")
        }
    }

    // MARK: - 目的地

    /// 向かっている島(未着岸の1件)。着岸済みは残すが、カードには出さない。
    private var activeDestination: Destination? {
        destinations.first { $0.achievedAt == nil }
    }

    private func land(_ dest: Destination) {
        guard dest.achievedAt == nil else { return }
        let landedAt = Date()
        dest.achievedAt = landedAt
        dest.updatedAt = landedAt
        try? modelContext.save()
        SyncService.shared.push(dest)
        Haptics.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            celebrating = dest
        }
    }

    // MARK: - タイル

    /// スマホ4列のタイル。アイコンの下に名前、その下に総作業時間(帰帆色)を中央寄せで。
    private func tileCell(_ item: StudyItem) -> some View {
        let total = totalByItem[item.uuid] ?? 0
        return Button {
            path.append(item)
        } label: {
            VStack(spacing: 6) {
                ItemTileArt(item: item)
                    .overlay(alignment: .topTrailing) {
                        if timerItemID == item.uuid.uuidString {
                            Circle()
                                .fill(LFColor.returnOrange)
                                .frame(width: 12, height: 12)
                                .offset(x: 4, y: -4)
                        }
                    }
                VStack(spacing: 1) {
                    Text(item.name)
                        .font(LFFont.label(12))
                        .foregroundStyle(LFColor.ink)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                    if total > 0 {
                        Text(LF.duration(minutes: total))
                            .font(LFFont.label(11))
                            .foregroundStyle(LFColor.returnOrange)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(item.name))
        .accessibilityHint(Text("Open"))
    }

    /// 4列固定(Web mobile: grid-template-columns repeat(4,1fr))。
    private var fourColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    }

    // MARK: - 今日の記録(Web: section-label「今日の記録 · 合計」+ rows)

    /// 今日のセッション(時刻順 新→古)。項目を横断し、同期の届き順に依存させない。
    private var todaysSessions: [StudySession] {
        let calendar = Calendar.current
        return sessions
            .filter { calendar.isDate($0.date, inSameDayAs: today) }
            .sorted(by: StudySession.newestFirst)
    }

    /// 項目ごとの総作業時間(全期間・分)。タイルの小さなバッジに使う。
    private var totalByItem: [UUID: Int] {
        var map: [UUID: Int] = [:]
        for s in sessions {
            if let id = s.item?.uuid { map[id, default: 0] += s.minutes }
        }
        return map
    }

    @ViewBuilder
    private var todayLogSection: some View {
        let todays = todaysSessions
        if !todays.isEmpty {
            let total = todays.reduce(0) { $0 + $1.minutes }
            HStack(spacing: 0) {
                Text("Today's log")
                    .font(LFFont.label(13))
                    .tracking(1)
                    .foregroundStyle(LFColor.ink.opacity(0.5))
                Text(" · \(LF.duration(minutes: total))")
                    .font(LFFont.label(13))
                    .foregroundStyle(LFColor.ink.opacity(0.38))
                    .monospacedDigit()
                Spacer()
                // 今日ぶんを1枚にして持ち出す(iOSの持ち出し機能はここに残す)。
                Button {
                    Haptics.tap()
                    sharingToday = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(LFColor.ink.opacity(0.45))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Share this day"))
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, 4)

            VStack(spacing: 0) {
                ForEach(Array(todays.enumerated()), id: \.element.persistentModelID) { index, session in
                    if index > 0 {
                        Rectangle()
                            .fill(LFColor.ink.opacity(0.08))
                            .frame(height: 1)
                    }
                    logRow(session)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    /// 記録の1行(Web SessionRow): 小アイコン・項目名・時刻&ひとこと・分・削除。
    private func logRow(_ session: StudySession) -> some View {
        HStack(spacing: 14) {
            Group {
                if let item = session.item {
                    ItemTileArt(item: item)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LFColor.ink.opacity(0.1))
                }
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.item?.name ?? "—")
                    .font(LFFont.copy(16))
                    .foregroundStyle(LFColor.ink)
                    .lineLimit(1)
                Text(rowSubtitle(session))
                    .font(LFFont.label(13))
                    .foregroundStyle(LFColor.ink.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(LF.duration(minutes: session.minutes))
                .font(LFFont.label(15))
                .foregroundStyle(LFColor.ink.opacity(0.7))
                .monospacedDigit()

            Button {
                pendingDelete = session
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(LFColor.deepRust)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Delete"))
        }
        .padding(.vertical, 12)
    }

    /// 「HH:mm · ひとこと」(時刻は24時間・ゼロ埋め、Webと同じ)。
    private func rowSubtitle(_ session: StudySession) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: session.date)
        let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        if let note = session.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(time) · \(note)"
        }
        return time
    }

    private func deleteSession(_ session: StudySession) {
        let date = session.date
        SyncService.shared.delete(session)
        modelContext.delete(session)
        StudyDayStore.unmarkDayIfEmpty(date, context: modelContext)
        try? modelContext.save()
        RoomService.shared.publishCurrentMonth(context: modelContext)
        WidgetBridge.refresh(context: modelContext)
        Haptics.tap()
    }

    /// 見出しラベル(Web section-label)。
    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        HStack {
            Text(text)
                .font(LFFont.label(13))
                .tracking(1)
                .foregroundStyle(LFColor.ink.opacity(0.5))
            Spacer()
        }
    }

    // MARK: - 設定入口(右上・控えめ)

    private var settingsButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(LFColor.ink.opacity(0.4))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Settings"))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

// MARK: - Previews

#Preview("項目あり") {
    let container = try! ModelContainer(
        for: StudyDay.self, StudyItem.self, StudySession.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let samples = [
        StudyItem(name: "開発", styleToken: "midnight", symbolToken: "phoenix", sortOrder: 0),
        StudyItem(name: "読書", styleToken: "coral", symbolToken: "book", sortOrder: 1),
        StudyItem(name: "記事作成", styleToken: "ink", symbolToken: "pen", sortOrder: 2),
    ]
    for item in samples { container.mainContext.insert(item) }
    return TodayView().modelContainer(container)
}

#Preview("項目なし") {
    TodayView()
        .modelContainer(
            try! ModelContainer(
                for: StudyDay.self, StudyItem.self, StudySession.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        )
}
