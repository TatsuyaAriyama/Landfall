import SwiftUI
import SwiftData

/// 「今日」画面。学習項目のタイルが並び、タップで時間+ひとことを刻む。
/// 催促はしない。タイルは長押しドラッグで並べ替えられる。
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \StudyDay.date, order: .reverse) private var days: [StudyDay]
    @Query(sort: \StudyItem.sortOrder) private var items: [StudyItem]
    @Query private var sessions: [StudySession]

    @State private var showingSettings = false
    @State private var creatingItem = false
    @State private var path = NavigationPath()
    /// 「今日」。日跨ぎ後の初操作をブロックしないよう、前景復帰と日付変化で更新する。
    @State private var today = Date()

    @AppStorage(StudyTimer.itemKey) private var timerItemID: String = ""

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
                        if items.isEmpty {
                            // 初回のホーム。破線の「+」だけにせず、静かに次の一歩を言葉で示す。
                            Text("Add your first thing, and set sail.")
                                .font(LFFont.copy(16))
                                .foregroundStyle(LFColor.ink.opacity(0.5))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 28)
                                .padding(.top, 44)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 22)], spacing: 26) {
                            ForEach(items) { item in
                                tileCell(item)
                            }
                            addTile
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, items.isEmpty ? 24 : 36)
                        .padding(.bottom, 24)
                    }

                    todaySummary
                        .padding(.bottom, 12)
                }

                settingsButton
            }
            .navigationDestination(for: StudyItem.self) { item in
                ItemDetailView(item: item)
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $creatingItem) { ItemEditorSheet(existing: nil) }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["LANDFALL_SETTINGS"] != nil {
                showingSettings = true
            }
            if ProcessInfo.processInfo.environment["LANDFALL_DETAIL"] != nil, let first = items.first {
                path.append(first)
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

    // MARK: - タイル

    private func tileCell(_ item: StudyItem) -> some View {
        Button {
            path.append(item)
        } label: {
            VStack(spacing: 8) {
                ItemTileArt(item: item)
                    .overlay(alignment: .topTrailing) {
                        if timerItemID == item.uuid.uuidString {
                            Circle()
                                .fill(LFColor.returnOrange)
                                .frame(width: 12, height: 12)
                                .offset(x: 4, y: -4)
                        }
                    }
                Text(item.name)
                    .font(LFFont.label(13))
                    .foregroundStyle(LFColor.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 34, alignment: .top)
            }
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(item.name))
        .accessibilityHint(Text("Open"))
        .draggable(item.uuid.uuidString)
        .dropDestination(for: String.self) { dropped, _ in
            reorder(droppedID: dropped.first, before: item)
        }
    }

    private var addTile: some View {
        Button {
            creatingItem = true
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(LFColor.ink.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    Text("+")
                        .font(LFFont.label(30))
                        .foregroundStyle(LFColor.ink.opacity(0.45))
                }
                .aspectRatio(1, contentMode: .fit)
                Text("Add")
                    .font(LFFont.label(13))
                    .foregroundStyle(LFColor.ink.opacity(0.45))
                    .frame(height: 34, alignment: .top)
            }
        }
        .buttonStyle(LFPressableButtonStyle())
        .accessibilityLabel(Text("Add item"))
    }

    /// ドラッグした項目をターゲットの位置へ差し込み、sortOrderを振り直す。
    private func reorder(droppedID: String?, before target: StudyItem) -> Bool {
        guard
            let droppedID,
            let from = items.firstIndex(where: { $0.uuid.uuidString == droppedID }),
            let to = items.firstIndex(where: { $0.uuid == target.uuid }),
            from != to
        else { return false }
        var reordered = Array(items)
        let moved = reordered.remove(at: from)
        reordered.insert(moved, at: to)
        for (index, item) in reordered.enumerated() {
            item.sortOrder = index
        }
        try? modelContext.save()
        for item in reordered {
            SyncService.shared.push(item)
        }
        Haptics.tap(.rigid)   // 並べ替え成立を軽い手応えで返す。
        return true
    }

    // MARK: - 今日の静かなサマリー

    @ViewBuilder
    private var todaySummary: some View {
        let calendar = Calendar.current
        let todays = sessions.filter { calendar.isDate($0.date, inSameDayAs: today) }
        if !todays.isEmpty {
            let total = todays.reduce(0) { $0 + $1.minutes }
            let itemCount = Set(todays.compactMap { $0.item?.uuid }).count
            Text("Today  \(LF.duration(minutes: total)) · \(itemCount) items")
                .font(LFFont.label(14))
                .monospacedDigit()
                .foregroundStyle(LFColor.ink.opacity(0.5))
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
