import SwiftUI

/// その日の記録を1枚のカードにして共有するシート。
/// 配色を選び、そのままSNSや友人へ送り出せる。
struct DayShareSheet: View {
    let log: DayLog

    @Environment(\.dismiss) private var dismiss
    @State private var theme: DayCardTheme = DayShareSheet.initialTheme

    /// 動作確認用: LANDFALL_CARD_THEME=paper/ink/harbor で初期の配色を固定できる。
    private static var initialTheme: DayCardTheme {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["LANDFALL_CARD_THEME"],
           let theme = DayCardTheme(rawValue: raw) {
            return theme
        }
        #endif
        return .paper
    }
    /// 配色ごとに書き出した画像を持っておき、選び直しても作り直さない。
    @State private var images: [DayCardTheme: WrappedCardImage] = [:]

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

            themeRow
                .padding(.horizontal, LFMetrics.cardPadding)
                .padding(.bottom, 16)

            shareButton
                .padding(.horizontal, LFMetrics.cardPadding)
                .padding(.bottom, 20)
        }
        .background(LFColor.paper)
        .presentationDetents([.large])
        .onAppear { renderIfNeeded() }
        .onChange(of: theme) { _, _ in renderIfNeeded() }
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

    private var themeRow: some View {
        HStack(spacing: 10) {
            ForEach(DayCardTheme.allCases) { candidate in
                themePill(candidate)
            }
            Spacer(minLength: 0)
        }
    }

    private func themePill(_ candidate: DayCardTheme) -> some View {
        let selected = candidate == theme
        return Button {
            Haptics.tap()
            theme = candidate
        } label: {
            Text(candidate.label)
                .font(LFFont.label(15))
                .foregroundStyle(selected ? LFColor.paper : LFColor.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(selected ? LFColor.ink : Color.clear)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(LFColor.ink.opacity(selected ? 0 : 0.25), lineWidth: 1)
                )
                .clipShape(Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var shareButton: some View {
        if let image = images[theme] {
            ShareLink(item: image, preview: SharePreview(image.fileName)) {
                shareLabel(ready: true)
            }
            .simultaneousGesture(TapGesture().onEnded { Haptics.success() })
        } else {
            shareLabel(ready: false)
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

    // MARK: - 書き出し

    @MainActor
    private func renderIfNeeded() {
        guard images[theme] == nil else { return }
        images[theme] = WrappedShare.render(
            card: DayLogCard(log: log, theme: theme),
            fileName: Self.fileName(for: log.date)
        )
    }

    /// 「Landfall-2026-07-18.png」形式。
    static func fileName(for date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "Landfall-%04d-%02d-%02d.png",
            comps.year ?? 0, comps.month ?? 0, comps.day ?? 0
        )
    }
}
