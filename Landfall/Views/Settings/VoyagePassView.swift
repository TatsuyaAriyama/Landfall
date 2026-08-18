import Foundation
import StoreKit
import SwiftUI

/// StoreKit版の航海証。復元と管理への導線を常に残し、解約を囲い込まない。
///
/// 画面は「サービス印 → 4つの恩恵 → 期間を選ぶ → ひとつの購入ボタン」の一本道。
/// 迷い先を作らないため、購入ボタンは画面下に固定して親指の届く位置に置く。
/// パレット本来の掟(グラデーション・影を使わない)はタイルや航海誌カードのもので、
/// この画面だけは店先としての奥行きを許す。ただし色そのものは既存の語彙から出さない。
struct VoyagePassView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var store = VoyagePassStore.shared
    @State private var showingManagement = false
    /// 選んでいる期間。商品が届いた時点で年額を既定にする。
    @State private var selectedProductID: String?
    @State private var appeared = false
    @State private var shimmerPhase: CGFloat = 0

    /// サービス印はアプリアイコンそのもの。角丸は一辺の22%(アイコンと同じ見え方)。
    private static let markSide: CGFloat = 132
    private static let markCorner: CGFloat = 29

    /// 背景の底の色。下端のスクリムをここに揃えて、ボタンの帯を地続きに見せる。
    private static let deepWater = Color(hex: 0x061A18)
    /// 印を1つだけ抜くとき(不死鳥の目)に使う、パネルの地に近い色。
    private static let panelVoid = Color(hex: 0x123A34)

    var body: some View {
        ZStack {
            backdrop
            content
        }
        .preferredColorScheme(.dark)
        .manageSubscriptionsSheet(isPresented: $showingManagement)
        .task {
            syncSelection()
            await store.reload()
            syncSelection()
        }
        .onChange(of: store.products.map(\.id)) { _, _ in syncSelection() }
        .onAppear { appeared = true }
    }

    // MARK: - 地

    /// 奥行きは三層で作る。地のグラデーション、印の後ろの淡い光、周縁の落とし。
    private var backdrop: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x0B2B27), LFColor.harborTeal, Self.deepWater],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [LFColor.emberGold.opacity(0.15), .clear],
                center: UnitPoint(x: 0.5, y: 0.14),
                startRadius: 6,
                endRadius: 330
            )
            RadialGradient(
                colors: [.clear, Color(hex: 0x03100F).opacity(0.5)],
                center: .center,
                startRadius: 190,
                endRadius: 640
            )
        }
        .ignoresSafeArea()
    }

    private var content: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                scrollBody
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) { purchaseBar }
        }
    }

    private var topBar: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                Haptics.tap(.light)
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LFColor.harborSand.opacity(0.78))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.07), in: Circle())
                    .overlay { Circle().stroke(.white.opacity(0.12), lineWidth: 1) }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(LFPressableButtonStyle())
            .accessibilityLabel(Text("Close"))
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var scrollBody: some View {
        VStack(spacing: 0) {
            hero
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.96, anchor: .top)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: appeared)

            VStack(spacing: 0) {
                benefits
                    .padding(.top, 36)
                planSection
                    .padding(.top, 24)
                accountActions
                    .padding(.top, 14)
                legal
                    .padding(.top, 14)
                    .padding(.bottom, 24)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(0.1), value: appeared)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 主役

    private var hero: some View {
        VStack(spacing: 18) {
            serviceMark
            Text("Voyage Pass")
                .font(LFFont.copy(28))
                .foregroundStyle(LFColor.harborSand)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 14)
    }

    /// サービス印そのものを主役に置く。輪も光の環も添えない。落ちる影だけで浮かせる。
    private var serviceMark: some View {
        Image("ServiceMark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: Self.markSide, height: Self.markSide)
            .clipShape(RoundedRectangle(cornerRadius: Self.markCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Self.markCorner, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: Color(hex: 0x03100F).opacity(0.55), radius: 26, y: 14)
            .accessibilityHidden(true)
    }

    // MARK: - 恩恵

    /// 4つだけ。説明は付けない。印はアプリ内と同じ自前のシンボルで、控えめに置く。
    private var benefits: some View {
        VStack(spacing: 0) {
            benefitRow(.attire, "Change your navigator's colour")
            benefitDivider
            benefitRow(.lighthouse, "Open the multiplayer server")
            benefitDivider
            benefitRow(.island, "Exclusive assets")
            benefitDivider
            benefitRow(.phoenix, "Ongoing updates")
        }
        .padding(.horizontal, 18)
        .background(
            Color.black.opacity(0.20),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(LFColor.harborSand.opacity(0.10), lineWidth: 1)
        }
    }

    private func benefitRow(_ symbol: TileSymbol, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 15) {
            TileSymbolView(symbol: symbol, fg: LFColor.emberGold.opacity(0.92), bg: Self.panelVoid)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
            Text(title)
                .font(LFFont.copy(15))
                .foregroundStyle(LFColor.harborSand.opacity(0.94))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 15)
    }

    private var benefitDivider: some View {
        Rectangle()
            .fill(LFColor.harborSand.opacity(0.08))
            .frame(height: 1)
    }

    // MARK: - 期間

    private var planSection: some View {
        VStack(spacing: 10) {
            planStates
            if let error = store.errorMessage, !store.products.isEmpty {
                Text(error)
                    .font(LFFont.label(12))
                    .foregroundStyle(LFColor.coral)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var planStates: some View {
        if store.isActive {
            activePass
        } else if store.isLoading && store.products.isEmpty {
            ProgressView()
                .tint(LFColor.returnOrange)
                .frame(height: 88)
        } else if store.products.isEmpty {
            Text("Voyage Pass is not available in this storefront yet.")
                .font(LFFont.copy(14))
                .foregroundStyle(LFColor.harborSand.opacity(0.58))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(
                    Color.black.opacity(0.16),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
        } else {
            VStack(spacing: 12) {
                if let annual = store.annual {
                    planCard(annual, isPrimary: true)
                }
                if let monthly = store.monthly {
                    planCard(monthly, isPrimary: false)
                }
            }
        }
    }

    /// 札は選ぶだけ。買うのは下の一本のボタンに集める。
    private func planCard(_ product: Product, isPrimary: Bool) -> some View {
        let selected = selectedProductID == product.id
        return Button {
            guard selectedProductID != product.id else { return }
            Haptics.tap(.light)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                selectedProductID = product.id
            }
        } label: {
            planCardLabel(product, isPrimary: isPrimary, selected: selected)
        }
        .buttonStyle(LFPressableButtonStyle(scale: 0.98))
        .disabled(store.isPurchasing)
        .accessibilityLabel(Text(verbatim: product.displayName))
        .accessibilityValue(Text(verbatim: product.displayPrice))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func planCardLabel(_ product: Product, isPrimary: Bool, selected: Bool) -> some View {
        HStack(spacing: 14) {
            selectionDot(selected: selected)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    periodLabel(product)
                        .font(LFFont.copy(17))
                        .foregroundStyle(LFColor.harborSand)
                    if isPrimary {
                        bestValueBadge
                    }
                }
            }
            Spacer(minLength: 8)
            Text(verbatim: product.displayPrice)
                .font(LFFont.copy(19))
                .foregroundStyle(LFColor.harborSand)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, isPrimary ? 20 : 17)
        .background { planBackground(selected: selected) }
        .accessibilityElement(children: .ignore)
    }

    private func planBackground(selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return ZStack {
            shape.fill(Color.black.opacity(selected ? 0.30 : 0.18))
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            LFColor.returnOrange.opacity(0.16),
                            LFColor.returnOrange.opacity(0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(selected ? 1 : 0)
            shape.stroke(
                selected ? LFColor.returnOrange.opacity(0.62) : LFColor.harborSand.opacity(0.14),
                lineWidth: selected ? 1.5 : 1
            )
        }
    }

    private func selectionDot(selected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(
                    selected ? LFColor.returnOrange : LFColor.harborSand.opacity(0.30),
                    lineWidth: 1.5
                )
                .frame(width: 21, height: 21)
            Circle()
                .fill(LFColor.returnOrange)
                .frame(width: 11, height: 11)
                .opacity(selected ? 1 : 0)
                .scaleEffect(selected ? 1 : 0.4)
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }

    private var bestValueBadge: some View {
        Text("Best value")
            .font(LFFont.label(10))
            .tracking(0.6)
            .foregroundStyle(LFColor.inkFixed)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(LFColor.returnOrange, in: Capsule())
    }

    /// 期間はStoreKitの購読期間から自前の文言で出す。ASCの商品名に見た目を預けない。
    private func periodLabel(_ product: Product) -> Text {
        guard let period = product.subscription?.subscriptionPeriod, period.value == 1 else {
            return Text(verbatim: product.displayName)
        }
        switch period.unit {
        case .year: return Text("Per year")
        case .month: return Text("Per month")
        default: return Text(verbatim: product.displayName)
        }
    }


    // MARK: - 有効なとき

    private var activePass: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(LFColor.returnOrange)
                Text(store.isDeveloperAccess ? "Developer access" : "Active")
                    .font(LFFont.copy(17))
                    .foregroundStyle(LFColor.harborSand)
                Spacer(minLength: 0)
            }
            if let expirationDate = store.expirationDate {
                Text("Renews \(LF.fullDate(expirationDate))")
                    .font(LFFont.label(12))
                    .foregroundStyle(LFColor.harborSand.opacity(0.52))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LFColor.returnOrange.opacity(0.16),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(LFColor.returnOrange.opacity(0.42), lineWidth: 1)
        }
    }

    // MARK: - 買う

    /// 下端に固定する一本道。買える状態のときだけ帯ごと現れる。
    @ViewBuilder
    private var purchaseBar: some View {
        if !store.isActive, let product = selectedProduct {
            purchaseButton(product)
                .padding(.horizontal, 22)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .padding(.bottom, 10)
                .background { purchaseScrim }
        }
    }

    private var purchaseScrim: some View {
        LinearGradient(
            stops: [
                .init(color: Self.deepWater.opacity(0), location: 0),
                .init(color: Self.deepWater.opacity(0.88), location: 0.42),
                .init(color: Self.deepWater, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }

    private func purchaseButton(_ product: Product) -> some View {
        Button {
            Haptics.tap(.medium)
            Task { await store.purchase(product) }
        } label: {
            ZStack {
                LFColor.returnOrange
                // 上からの光。面を平らに見せないための、ごく薄い一枚。
                LinearGradient(
                    colors: [Color.white.opacity(0.18), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                if !reduceMotion {
                    ctaShimmer
                }
                purchaseButtonLabel
            }
            .frame(height: 56)
            .clipShape(Capsule(style: .continuous))
            .shadow(color: LFColor.returnOrange.opacity(0.30), radius: 18, y: 8)
        }
        .buttonStyle(LFPressableButtonStyle(scale: 0.97))
        .disabled(store.isPurchasing)
        .accessibilityLabel(Text("Continue"))
        .accessibilityValue(Text(verbatim: product.displayPrice))
        .onAppear {
            guard !reduceMotion, shimmerPhase == 0 else { return }
            withAnimation(.linear(duration: 3.6).repeatForever(autoreverses: false)) {
                shimmerPhase = 1
            }
        }
    }

    @ViewBuilder
    private var purchaseButtonLabel: some View {
        if store.isPurchasing {
            ProgressView()
                .tint(LFColor.inkFixed)
        } else {
            Text("Continue")
                .font(LFFont.copy(17))
                .foregroundStyle(LFColor.inkFixed)
        }
    }

    /// ゆっくり一度だけ横切る光。帯の外で休ませて、瞬きの間を作る。
    private var ctaShimmer: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let band = max(72, width * 0.28)
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.30), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: band)
            .offset(x: -band + shimmerPhase * (width * 2.6 + band))
        }
        .allowsHitTesting(false)
    }

    // MARK: - 口座まわり

    private var accountActions: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            quietAction("Restore purchases") {
                Task { await store.restore() }
            }
            if store.hasStoreKitEntitlement {
                quietAction("Manage subscription") {
                    showingManagement = true
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func quietAction(
        _ title: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(LFFont.label(13))
                .foregroundStyle(LFColor.harborSand.opacity(0.68))
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(LFPressableButtonStyle(scale: 0.97))
        .disabled(store.isPurchasing)
    }

    private var legal: some View {
        VStack(spacing: 8) {
            Text("Payment is charged to your Apple Account. The subscription renews automatically unless canceled at least 24 hours before the end of the current period.")
                .font(LFFont.label(10))
                .foregroundStyle(LFColor.harborSand.opacity(0.38))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            HStack(spacing: 18) {
                if let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                    Link("Terms", destination: terms)
                }
                if let privacy = URL(string: "https://aftide.app/privacy") {
                    Link("Privacy", destination: privacy)
                }
            }
            .font(LFFont.label(11))
            .foregroundStyle(LFColor.harborSand.opacity(0.52))
            .tint(LFColor.harborSand.opacity(0.52))
        }
    }

    // MARK: - 選択の面倒

    private var selectedProduct: Product? {
        guard let selectedProductID else { return nil }
        return store.products.first { $0.id == selectedProductID }
    }

    /// 商品が入れ替わっても選択が宙に浮かないように整える。既定は年額。
    private func syncSelection() {
        guard !store.products.isEmpty else { return }
        if let selectedProductID, store.products.contains(where: { $0.id == selectedProductID }) {
            return
        }
        selectedProductID = store.annual?.id ?? store.products.first?.id
    }
}
