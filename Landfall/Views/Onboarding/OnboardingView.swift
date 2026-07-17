import SwiftUI

/// 初回起動時に一度だけ見せる導入。
/// 核となる思想は「学びは途切れる前提」— 途切れを肯定し、休みも同格、評価軸は再開力。
/// ログイン壁の前に置き、価値を先に伝える。
struct OnboardingView: View {
    var onDone: () -> Void

    @State private var page = 0

    private let pages = OnboardingPage.all

    var body: some View {
        ZStack {
            LFColor.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                // スキップ(右上・控えめ)
                HStack {
                    Spacer()
                    Button("Skip") { onDone() }
                        .font(LFFont.label(15))
                        .foregroundStyle(LFColor.ink.opacity(0.4))
                }
                .padding(.horizontal, LFMetrics.cardPadding)
                .padding(.top, 12)
                .opacity(page < pages.count - 1 ? 1 : 0)

                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        pageView(pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: page)
                .onAppear {
                    #if DEBUG
                    if let raw = ProcessInfo.processInfo.environment["LANDFALL_ONBOARD_PAGE"], let p = Int(raw) {
                        page = min(max(p, 0), pages.count - 1)
                    }
                    #endif
                }

                dots
                    .padding(.top, 8)

                Button {
                    if page < pages.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        onDone()
                    }
                } label: {
                    Text(page < pages.count - 1 ? "Next" : "Begin")
                        .font(LFFont.copy(18))
                        .foregroundStyle(LFColor.paper)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(LFColor.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, LFMetrics.cardPadding)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Circle()
                    .fill(LFColor.ink.opacity(index == page ? 0.8 : 0.18))
                    .frame(width: 7, height: 7)
            }
        }
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 0) {
            Spacer()
            page.motif
                .frame(height: 150)
            Text(page.headline)
                .font(LFFont.copy(26))
                .foregroundStyle(LFColor.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 48)
            Text(page.subline)
                .font(LFFont.copy(16))
                .foregroundStyle(LFColor.ink.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, LFMetrics.cardPadding + 8)
    }
}

/// 導入1ページぶんの内容。
struct OnboardingPage {
    let headline: LocalizedStringKey
    let subline: LocalizedStringKey
    let motif: AnyView

    static let all: [OnboardingPage] = [
        OnboardingPage(
            headline: "Learning breaks off.",
            subline: "Landfall is built on that. Pausing is part of the voyage.",
            motif: AnyView(BrokenTraceMotif())
        ),
        OnboardingPage(
            headline: "Rest stands as tall as study.",
            subline: "No ranks. No streaks. Nothing to keep unbroken.",
            motif: AnyView(EqualBarsMotif())
        ),
        OnboardingPage(
            headline: "What matters is that you return.",
            subline: "Not how long you kept going. That's why times quit is always zero.",
            motif: AnyView(ReturnMotif())
        ),
        OnboardingPage(
            headline: "Set sail whenever you like.",
            subline: "And whenever you drift, the harbor is still here.",
            motif: AnyView(HarborMotif())
        ),
    ]
}

// MARK: - モチーフ(フラット塗りのみ・既存の造形を流用)

/// 途切れて、また戻る軌跡。オレンジの点が帰還。
private struct BrokenTraceMotif: View {
    var body: some View {
        HStack(spacing: 0) {
            Capsule().fill(LFColor.ink).frame(width: 66, height: 8)
            Capsule().fill(LFColor.coral).frame(width: 40, height: 8)   // 空白
            Circle().fill(LFColor.returnOrange).frame(width: 14, height: 14)   // 帰還
            Capsule().fill(LFColor.ink).frame(width: 58, height: 8)
        }
    }
}

/// 学んだ日と休んだ日を、同じ大きさで並べる。
private struct EqualBarsMotif: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LFColor.sunYellow)
                .frame(width: 52, height: 130)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LFColor.seaGreen)
                .frame(width: 52, height: 130)
        }
    }
}

/// 再開力の象徴として不死鳥。
private struct ReturnMotif: View {
    var body: some View {
        PhoenixShape()
            .fill(LFColor.returnOrange)
            .frame(width: 140, height: 140)
    }
}

/// 出航と、いつでも帰れる港。
private struct HarborMotif: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LFColor.harborTeal)
                .frame(width: 180, height: 150)
            BoatShape()
                .fill(LFColor.harborSand)
                .frame(width: 70, height: 128)
        }
    }
}

#Preview {
    OnboardingView(onDone: {})
}
