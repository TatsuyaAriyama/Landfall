import SwiftUI
import SwiftData

/// Wrapped画面。月末に生まれる、その月の総括4枚。
/// 縦スワイプのページングで1枚ずつめくり、各カードの下から共有できる。
struct WrappedView: View {
    @Query(sort: \StudyDay.date) private var entries: [StudyDay]
    @Query private var sessions: [StudySession]
    @Environment(\.scenePhase) private var scenePhase

    /// ユーザーが明示的に選んだ月。nilなら最新月。
    @State private var selectedMonth: YearMonth?
    /// いま表示中のページ(0〜3)。
    @State private var currentPage: Int?
    /// 共有用PNGのキャッシュ。キーは「年-月-cardN」。表示したページから順に埋める。
    @State private var imageCache: [String: WrappedCardImage] = [:]
    /// Wrapped生成可否は日付に依存する。前景復帰と日付変化で更新する。
    @State private var today = Date()

    private var availableMonths: [YearMonth] {
        MonthStats.completedWrappedMonths(entries: entries, today: today)
    }

    /// 選択が失効していたら最新月に戻す。
    private var resolvedMonth: YearMonth? {
        if let selectedMonth, availableMonths.contains(selectedMonth) {
            return selectedMonth
        }
        return availableMonths.first
    }

    var body: some View {
        ZStack {
            LFColor.paper.ignoresSafeArea()

            if let yearMonth = resolvedMonth {
                wrappedPager(for: yearMonth)
            } else {
                emptyState
            }
        }
    }

    // MARK: - 利用可能な月がないとき

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("Your first Logbook arrives at month's end.")
                .font(LFFont.copy(20))
                .foregroundStyle(LFColor.ink)
            Text("At month's end, the whole month becomes one page.")
                .font(LFFont.label(15))
                .foregroundStyle(LFColor.ink.opacity(0.6))
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, LFMetrics.cardPadding)
    }

    // MARK: - 本体

    private func wrappedPager(for yearMonth: YearMonth) -> some View {
        let wrapped = MonthStats.wrappedMonth(
            year: yearMonth.year, month: yearMonth.month, entries: entries, sessions: sessions
        )

        return VStack(spacing: 0) {
            // 月ヘッダは常設。カード2・3には月名が無いため、どの月の航海誌かを常に上部で示す。
            monthHeader(current: yearMonth)

            GeometryReader { geo in
                // 共有ボタンとその間隔ぶんを差し引いて、カードが必ず収まる縮小率を出す。
                let buttonSpace: CGFloat = 60
                let scale = min(
                    (geo.size.width - 24) / LFMetrics.cardSize.width,
                    (geo.size.height - buttonSpace - 24) / LFMetrics.cardSize.height,
                    1
                )

                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { index in
                            VStack(spacing: 18) {
                                card(index: index, month: wrapped)
                                    .scaleEffect(scale)
                                    .frame(
                                        width: LFMetrics.cardSize.width * scale,
                                        height: LFMetrics.cardSize.height * scale
                                    )
                                WrappedShareButton(
                                    image: imageCache[cacheKey(yearMonth, cardIndex: index)]
                                )
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $currentPage)
                .scrollIndicators(.hidden)
                // ページがスナップした瞬間だけ、静かな手応え(システムの触覚設定を尊重)。
                .sensoryFeedback(.selection, trigger: currentPage)
                // 4枚あることを示す縦インジケータ。縦めくりは非慣習的なので見つけやすさを補う。
                .overlay(alignment: .trailing) { pageIndicator }
            }
        }
        .onAppear {
            renderImageIfNeeded(for: currentPage ?? 0)
            #if DEBUG
            if let raw = ProcessInfo.processInfo.environment["LANDFALL_WRAPPED_PAGE"], let page = Int(raw) {
                currentPage = page
            }
            #endif
        }
        .onChange(of: currentPage) { _, newPage in
            renderImageIfNeeded(for: newPage ?? 0)
        }
        .onChange(of: selectedMonth) { _, _ in
            // 月を切り替えたら1枚目に戻し、その月の1枚目を用意する。
            currentPage = 0
            renderImageIfNeeded(for: 0)
        }
        .onChange(of: entries.map(\.date)) { _, _ in
            // 記録が変われば共有PNGは陳腐化する。全て破棄して表示中ページを作り直す。
            imageCache.removeAll()
            renderImageIfNeeded(for: currentPage ?? 0)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { today = Date() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            today = Date()
        }
    }

    // MARK: - 月選択

    @ViewBuilder
    private func monthHeader(current: YearMonth) -> some View {
        if availableMonths.count > 1 {
            // 複数月あるときは選べる。押せると分かるよう chevron.down を添える。
            Menu {
                ForEach(availableMonths) { yearMonth in
                    Button(title(of: yearMonth)) {
                        selectedMonth = yearMonth
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(title(of: current))
                        .font(LFFont.copy(17))
                        .foregroundStyle(LFColor.ink)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(LFColor.ink.opacity(0.5))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .padding(.top, 8)
            .accessibilityLabel(Text("Month"))
            .accessibilityValue(Text(verbatim: title(of: current)))
        } else {
            // 1月ぶんだけなら、そのまま月名を示す(操作なし)。
            Text(title(of: current))
                .font(LFFont.copy(17))
                .foregroundStyle(LFColor.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .padding(.top, 8)
        }
    }

    /// 縦4点のページインジケータ。現在ページだけ縦に伸ばして示す。
    private var pageIndicator: some View {
        VStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { index in
                let active = (currentPage ?? 0) == index
                Capsule(style: .continuous)
                    .fill(LFColor.ink.opacity(active ? 0.8 : 0.22))
                    .frame(width: 6, height: active ? 16 : 6)
            }
        }
        .padding(.trailing, 6)
        .animation(.easeInOut(duration: 0.2), value: currentPage)
        .accessibilityHidden(true)
        .allowsHitTesting(false)   // 装飾。右端のスワイプめくりを妨げない。
    }

    private func title(of yearMonth: YearMonth) -> String {
        LF.monthYear(year: yearMonth.year, month: yearMonth.month)
    }

    // MARK: - カード

    @ViewBuilder
    private func card(index: Int, month: WrappedMonth) -> some View {
        Group {
            switch index {
            case 0: WrappedCard1Fact(month: month)
            case 1: WrappedCard2Silence(month: month)
            case 2: WrappedCard3Archetype(month: month)
            default: WrappedCard4Trace(month: month)
            }
        }
        // 航海誌カードは固定デザインの「絵はがき」。端末のダーク設定に関わらず常にライトで描き、
        // 画面表示と共有画像の見た目を一致させる(ink/paper が反転しないようにする)。
        .environment(\.colorScheme, .light)
        // 固定寸法(390x693)の絵はがきなので、端末の文字サイズに関わらずレイアウトを一定に保つ。
        // LFFont の *Fixed は .large 相当で焼き付けるため、共有部品もこのフラグで固定側を選ぶ。
        .environment(\.lfFixedType, true)
    }

    // MARK: - 共有画像(表示したページから遅延生成)

    private func cacheKey(_ yearMonth: YearMonth, cardIndex: Int) -> String {
        "\(yearMonth.id)-card\(cardIndex + 1)"
    }

    /// 表示中のページの共有画像をまだなければ作る。
    /// 月は必ず現在の状態から引き直し、古いbodyのキャプチャに依存しない。
    @MainActor
    private func renderImageIfNeeded(for index: Int) {
        guard (0..<4).contains(index), let yearMonth = resolvedMonth else { return }
        let key = cacheKey(yearMonth, cardIndex: index)
        guard imageCache[key] == nil else { return }
        let month = MonthStats.wrappedMonth(
            year: yearMonth.year, month: yearMonth.month, entries: entries, sessions: sessions
        )
        imageCache[key] = WrappedShare.render(
            card: card(index: index, month: month),
            fileName: WrappedShare.fileName(
                year: yearMonth.year, month: yearMonth.month, cardIndex: index + 1
            )
        )
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: StudyDay.self, configurations: config)

    // 前月ぶんのダミー記録(前月は常にWrapped利用可能)。
    let calendar = Calendar.current
    if let thisMonthStart = calendar.dateInterval(of: .month, for: Date())?.start,
       let prevMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) {
        for day in [1, 2, 3, 10, 11, 14, 15, 16, 22, 23, 24, 25, 29, 30] {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: prevMonthStart) {
                container.mainContext.insert(StudyDay(date: date))
            }
        }
    }

    return WrappedView()
        .modelContainer(container)
}
