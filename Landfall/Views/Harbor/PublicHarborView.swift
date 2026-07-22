import SwiftUI

/// パブリックの港の中。個人は並ばない。見えるのは港ぜんたいの潮だけ。
/// 参加すると、自分の普段の記録が(名前を出さずに)潮位に自動で反映される。
struct PublicHarborView: View {
    let harbor: PublicHarbor

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthService
    @StateObject private var service = PublicHarborService.shared
    @State private var tide: [Int: Int] = [:]
    @State private var working = false
    @State private var leaving = false

    private var isJoined: Bool { service.joined.contains(harbor.slug) }
    private var todayCount: Int { service.todaySail[harbor.slug] ?? 0 }

    var body: some View {
        ZStack {
            LFColor.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    todayLine
                        .padding(.top, 28)
                    tideSection
                        .padding(.top, 24)
                    joinButton
                        .padding(.top, 32)
                    footnotes
                        .padding(.top, 28)
                }
                .padding(LFMetrics.cardPadding)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                        Text("Harbor")
                    }
                    .font(LFFont.label(16))
                    .foregroundStyle(LFColor.ink)
                }
            }
        }
        .toolbarBackground(LFColor.paper, for: .navigationBar)
        .task {
            tide = await service.monthTide(slug: harbor.slug)
            await service.refreshTodaySail()
        }
        .confirmationDialog(
            "Leave this harbor?",
            isPresented: $leaving,
            titleVisibility: .visible
        ) {
            Button("Leave this harbor", role: .destructive) {
                Task {
                    await service.leave(harbor.slug)
                    Haptics.tap()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your days will stop counting into this tide. You can rejoin anytime.")
        }
    }

    // MARK: - 見出し

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(harbor.style.background)
                TileSymbolView(symbol: harbor.symbol, fg: harbor.style.foreground, bg: harbor.style.background)
                    .frame(width: 42, height: 42)
            }
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(harbor.title)
                    .font(LFFont.copy(24))
                    .foregroundStyle(LFColor.ink)
                Text(harbor.tagline)
                    .font(LFFont.label(14))
                    .foregroundStyle(LFColor.ink.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var todayLine: some View {
        Group {
            if todayCount > 0 {
                Text("Today, \(todayCount) set sail here.")
            } else {
                Text("The sea is calm today.")
            }
        }
        .font(LFFont.copy(18))
        .foregroundStyle(LFColor.ink)
    }

    // MARK: - 今月の潮

    private var tideSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This month's tide")
                .font(LFFont.label(13))
                .tracking(1)
                .foregroundStyle(LFColor.ink.opacity(0.5))
            TideShape(tide: tide, daysInMonth: daysInMonth)
                .fill(harbor.style.background.opacity(0.55))
                .frame(height: 96)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(LFColor.ink.opacity(0.15))
                        .frame(height: 1)
                }
                .overlay {
                    if tide.values.allSatisfy({ $0 == 0 }) {
                        Text("The tide rises as sailors set out.")
                            .font(LFFont.label(14))
                            .foregroundStyle(LFColor.ink.opacity(0.4))
                    }
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("This month's tide"))
    }

    private var daysInMonth: Int {
        Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
    }

    // MARK: - 参加

    @ViewBuilder
    private var joinButton: some View {
        if !auth.isSignedIn {
            Text("Sign in to enter a harbor.")
                .font(LFFont.copy(15))
                .foregroundStyle(LFColor.ink.opacity(0.5))
        } else if isJoined {
            Button {
                leaving = true
            } label: {
                Text("Leave this harbor")
                    .font(LFFont.label(14))
                    .foregroundStyle(LFColor.ink.opacity(0.45))
            }
            .buttonStyle(.plain)
        } else {
            Button {
                guard !working else { return }
                working = true
                Task {
                    defer { working = false }
                    try? await service.join(harbor.slug)
                    Haptics.success()
                }
            } label: {
                Text("Join this harbor")
                    .font(LFFont.copy(17))
                    .foregroundStyle(LFColor.paper)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(LFColor.ink)
                    .clipShape(RoundedRectangle(cornerRadius: LFMetrics.cardCorner, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No names appear here — only the harbor's tide.")
            Text("On days you rest, the tide just ebbs. That's all.")
        }
        .font(LFFont.label(13))
        .foregroundStyle(LFColor.ink.opacity(0.45))
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 当月の潮位を、日ごとのステップ状の面として描く(軌跡の波形と同じ語彙)。
/// 高さはその日に海に出た人数を月内最大で正規化したもの。個人は描かない。
struct TideShape: Shape {
    let tide: [Int: Int]
    let daysInMonth: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let maxCount = max(tide.values.max() ?? 0, 1)
        let dayWidth = rect.width / CGFloat(max(daysInMonth, 1))
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for day in 1...max(daysInMonth, 1) {
            let count = tide[day] ?? 0
            let height = rect.height * 0.9 * CGFloat(count) / CGFloat(maxCount)
            let y = rect.maxY - height
            let x0 = rect.minX + CGFloat(day - 1) * dayWidth
            let x1 = x0 + dayWidth
            path.addLine(to: CGPoint(x: x0, y: y))
            path.addLine(to: CGPoint(x: x1, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
