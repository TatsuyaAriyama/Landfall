import StoreKit
import SwiftUI

/// StoreKit版の航海証。復元と管理への導線を常に残し、解約を囲い込まない。
struct VoyagePassView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = VoyagePassStore.shared
    @State private var showingManagement = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x123A35), Color(hex: 0x194B43), Color(hex: 0x0B2928)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header
                    emblem
                        .padding(.top, 18)
                    titleBlock
                        .padding(.top, 18)
                    benefits
                        .padding(.top, 28)
                    plans
                        .padding(.top, 24)
                    accountActions
                        .padding(.top, 18)
                    legal
                        .padding(.top, 24)
                        .padding(.bottom, 38)
                }
                .padding(.horizontal, 22)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .manageSubscriptionsSheet(isPresented: $showingManagement)
        .task { await store.reload() }
    }

    private var header: some View {
        HStack {
            Spacer()
            Button("Close") { dismiss() }
                .font(LFFont.label(15))
                .foregroundStyle(LFColor.harborSand.opacity(0.66))
                .frame(minWidth: 52, minHeight: 44)
        }
        .safeAreaPadding(.top, 8)
    }

    private var emblem: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.24))
                .frame(width: 104, height: 104)
            Circle()
                .stroke(LFColor.returnOrange.opacity(0.32), lineWidth: 1)
                .frame(width: 88, height: 88)
            TileSymbolView(
                symbol: .compass,
                fg: LFColor.returnOrange,
                bg: Color.clear
            )
            .frame(width: 62, height: 62)
        }
        .shadow(color: LFColor.returnOrange.opacity(0.18), radius: 24)
    }

    private var titleBlock: some View {
        Text("Voyage Pass")
            .font(LFFont.copy(24))
            .foregroundStyle(LFColor.returnOrange)
            .multilineTextAlignment(.center)
    }

    private var benefits: some View {
        VStack(spacing: 0) {
            benefit(
                symbol: "person.2.wave.2",
                title: "Open a private harbor",
                detail: "Create one harbor for up to 4 sailors. Invited sailors join free"
            )
            divider
            benefit(symbol: "sparkles", title: "Seasonal waters", detail: "Special seas that change through the year")
            divider
            benefit(symbol: "sailboat", title: "More ways to make it yours", detail: "Special attire for your navigator and boat")
            divider
            benefit(symbol: "photo.on.rectangle.angled", title: "Keepsakes from the voyage", detail: "Premium landfall cards and future additions")
        }
        .padding(.horizontal, 18)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(LFColor.harborSand.opacity(0.12), lineWidth: 1)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(LFColor.harborSand.opacity(0.10))
            .frame(height: 1)
    }

    private func benefit(symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LFColor.returnOrange)
                .frame(width: 34, height: 34)
                .background(LFColor.returnOrange.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LFFont.copy(15))
                    .foregroundStyle(LFColor.harborSand)
                Text(detail)
                    .font(LFFont.label(12))
                    .foregroundStyle(LFColor.harborSand.opacity(0.52))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var plans: some View {
        if store.isActive {
            VStack(spacing: 8) {
                HStack {
                    Label(store.isDeveloperAccess ? "Developer access" : "Active", systemImage: "checkmark.seal.fill")
                        .font(LFFont.copy(16))
                        .foregroundStyle(LFColor.harborSand)
                    Spacer()
                    if let expirationDate = store.expirationDate {
                        Text("Renews \(LF.fullDate(expirationDate))")
                            .font(LFFont.label(11))
                            .foregroundStyle(LFColor.harborSand.opacity(0.48))
                    }
                }
                .padding(18)
                .background(LFColor.returnOrange.opacity(0.18), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(LFColor.returnOrange.opacity(0.42), lineWidth: 1)
                }
            }
        } else if store.isLoading {
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
                .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            VStack(spacing: 12) {
                if let annual = store.annual {
                    planButton(annual, badge: "Best value")
                }
                if let monthly = store.monthly {
                    planButton(monthly, badge: nil)
                }
            }
        }

        if let error = store.errorMessage, !store.products.isEmpty {
            Text(error)
                .font(LFFont.label(12))
                .foregroundStyle(LFColor.coral)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
        }
    }

    private func planButton(_ product: Product, badge: LocalizedStringKey?) -> some View {
        Button {
            Task { await store.purchase(product) }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(product.displayName)
                            .font(LFFont.copy(17))
                        if let badge {
                            Text(badge)
                                .font(LFFont.label(10))
                                .foregroundStyle(LFColor.inkFixed)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(LFColor.returnOrange, in: Capsule())
                        }
                    }
                    Text(product.description)
                        .font(LFFont.label(11))
                        .foregroundStyle(LFColor.harborSand.opacity(0.50))
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(product.displayPrice)
                    .font(LFFont.copy(18))
            }
            .foregroundStyle(LFColor.harborSand)
            .padding(18)
            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(LFColor.harborSand.opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(LFPressableButtonStyle())
        .disabled(store.isPurchasing)
    }

    private var accountActions: some View {
        HStack(spacing: 18) {
            Button("Restore purchases") {
                Task { await store.restore() }
            }
            if store.hasStoreKitEntitlement {
                Button("Manage subscription") {
                    showingManagement = true
                }
            }
        }
        .font(LFFont.label(13))
        .foregroundStyle(LFColor.harborSand.opacity(0.68))
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
        }
    }
}
