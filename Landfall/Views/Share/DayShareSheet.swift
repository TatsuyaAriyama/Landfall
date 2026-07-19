import SwiftUI
import SwiftData

/// その日の記録を1枚のカードにして共有するシート。
/// この日についてのひとことを一行だけ添えられる(記録ごとのメモとは別物)。
struct DayShareSheet: View {
    let date: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allSessions: [StudySession]

    @State private var theme: DayCardTheme = DayShareSheet.initialTheme
    /// 入力中のひとこと。プレビューには即座に効く。
    @State private var comment = ""
    /// 画像を書き出したときのひとこと。これが変わったら作り直す。
    @State private var renderedComment = ""
    @FocusState private var commentFocused: Bool
    /// 配色ごとに書き出した画像。ひとことが変わると捨てる。
    @State private var images: [DayCardTheme: WrappedCardImage] = [:]

    /// 動作確認用: LANDFALL_CARD_THEME=paper/ink/harbor で初期の配色を固定できる。
    private static var initialTheme: DayCardTheme {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["LANDFALL_CARD_THEME"],
           let theme = DayCardTheme(rawValue: raw) {
            return theme
        }
        #endif
        return .harbor
    }

    private var log: DayLog { log(with: comment) }

    private func log(with text: String) -> DayLog {
        DayLog.make(date: date, sessions: allSessions, comment: text)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { geo in
                // 幅に合わせて縮め、縦は伸びるぶんだけスクロールで見せる。
                let scale = min((geo.size.width - 48) / LFMetrics.cardSize.width, 1)
                ScrollView {
                    DayLogCard(log: log, theme: theme)
                        .scaleEffect(scale, anchor: .top)
                        .frame(width: LFMetrics.cardSize.width * scale)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
                .scrollIndicators(.hidden)
                // どの配色でも「一枚の紙」として浮くよう、下地を敷く。
                .background(LFColor.ink.opacity(0.06))
            }

            commentField
                .padding(.horizontal, LFMetrics.cardPadding)
                .padding(.top, 18)

            themeRow
                .padding(.horizontal, LFMetrics.cardPadding)
                .padding(.top, 16)
                .padding(.bottom, 16)

            shareButton
                .padding(.horizontal, LFMetrics.cardPadding)
                .padding(.bottom, 20)
        }
        .background(LFColor.paper)
        .presentationDetents([.large])
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { commentFocused = false }
            }
        }
        .onAppear {
            // @State は同じクロージャ内では反映されないので、読んだ値を明示的に渡す。
            // 状態経由にすると最初の書き出しからひとことが抜ける。
            let stored = StudyDayStore.comment(for: date, context: modelContext) ?? ""
            comment = stored
            renderedComment = stored
            renderIfNeeded(using: stored)
            #if DEBUG
            dumpAllThemesIfRequested(using: stored)
            #endif
        }
        .onChange(of: theme) { _, _ in renderIfNeeded(using: comment) }
        // 入力が終わったら保存し、画像を作り直す(打鍵のたびには作らない)。
        .onChange(of: commentFocused) { _, focused in
            if !focused { commitComment() }
        }
    }

    // MARK: - 部品

    private var header: some View {
        HStack {
            Text("Share this day")
                .font(LFFont.copy(20))
                .foregroundStyle(LFColor.ink)
            Spacer()
            Button("Close") { dismiss() }
                .font(LFFont.label(15))
                .foregroundStyle(LFColor.ink.opacity(0.6))
        }
        .padding(.horizontal, LFMetrics.cardPadding)
        .padding(.top, 24)
    }

    private var commentField: some View {
        TextField("A word about this day (optional)", text: $comment, axis: .vertical)
            .font(LFFont.label(16))
            .foregroundStyle(LFColor.ink)
            .tint(LFColor.ink)
            .lineLimit(1...3)
            .focused($commentFocused)
            .submitLabel(.done)
            .onSubmit { commentFocused = false }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous)
                    .stroke(LFColor.ink.opacity(0.2), lineWidth: 1)
            )
    }

    private var themeRow: some View {
        HStack(spacing: 16) {
            ForEach(DayCardTheme.allCases) { candidate in
                themeSwatch(candidate)
            }
            Spacer(minLength: 0)
        }
    }

    /// 配色はカードの縮図(海と砂の水平線が入った丸)で見せる。名前は読み上げ専用。
    private func themeSwatch(_ candidate: DayCardTheme) -> some View {
        let selected = candidate == theme
        return Button {
            Haptics.tap()
            commentFocused = false
            theme = candidate
        } label: {
            VStack(spacing: 0) {
                candidate.sea
                candidate.land.frame(height: 11)
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())
            // 白い海(朝)が地に溶けないよう、常に淡い輪郭を敷く。
            .overlay(Circle().stroke(LFColor.ink.opacity(0.12), lineWidth: 1))
            .padding(5)
            // 選択中は一回り外にリング。
            .overlay(Circle().stroke(selected ? LFColor.ink : .clear, lineWidth: 1.5))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(candidate.label))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var shareButton: some View {
        // 入力途中(未確定)のときは、まず確定させてから共有させる。
        if let image = images[theme], comment == renderedComment {
            ShareLink(item: image, preview: SharePreview(image.fileName)) {
                shareLabel(ready: true)
            }
            .simultaneousGesture(TapGesture().onEnded { Haptics.success() })
        } else {
            Button {
                commentFocused = false
                commitComment()
            } label: {
                shareLabel(ready: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func shareLabel(ready: Bool) -> some View {
        Text(ready ? "Share" : "Preparing…")
            .font(LFFont.copy(18))
            .foregroundStyle(LFColor.paper)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(ready ? LFColor.ink : LFColor.ink.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
    }

    // MARK: - 保存と書き出し

    /// ひとことを保存し、画像を作り直す。
    @MainActor
    private func commitComment() {
        StudyDayStore.setComment(comment, for: date, context: modelContext)
        guard comment != renderedComment else { return }
        renderedComment = comment
        images.removeAll()
        renderIfNeeded(using: comment)
    }

    @MainActor
    private func renderIfNeeded(using text: String) {
        guard images[theme] == nil else { return }
        images[theme] = WrappedShare.render(
            card: DayLogCard(log: log(with: text), theme: theme),
            fileName: Self.fileName(for: date)
        )
    }

    #if DEBUG
    /// 動作確認用: LANDFALL_CARD_DUMP=1 で全配色のPNGを Documents に書き出す。
    @MainActor
    private func dumpAllThemesIfRequested(using text: String) {
        guard ProcessInfo.processInfo.environment["LANDFALL_CARD_DUMP"] == "1" else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for candidate in DayCardTheme.allCases {
            guard let image = WrappedShare.render(
                card: DayLogCard(log: log(with: text), theme: candidate),
                fileName: Self.fileName(for: date)
            ) else { continue }
            try? image.data.write(to: dir.appendingPathComponent("card-\(candidate.rawValue).png"))
        }
    }
    #endif

    /// 「Landfall-2026-07-18.png」形式。
    static func fileName(for date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "Landfall-%04d-%02d-%02d.png",
            comps.year ?? 0, comps.month ?? 0, comps.day ?? 0
        )
    }
}
