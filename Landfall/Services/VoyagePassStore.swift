import Combine
import FirebaseAuth
import FirebaseFunctions
import StoreKit

/// iOS版の航海証。StoreKit 2 の検証済みTransactionだけを有効とし、
/// 購入・復元・別端末での更新をひとつの状態へ集約する。
@MainActor
final class VoyagePassStore: ObservableObject {
    static let shared = VoyagePassStore()

    /// App Store Connect で同じSubscription Groupに作成するProduct ID。
    static let monthlyID = "com.tatsuyaariyama.keelmira.voyagepass.monthly"
    static let annualID = "com.tatsuyaariyama.keelmira.voyagepass.annual"
    static let productIDs: Set<String> = [monthlyID, annualID]

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var expirationDate: Date?
    @Published private(set) var isLoading = true
    @Published private(set) var isPurchasing = false
    @Published var errorMessage: String?

    private var updateTask: Task<Void, Never>?
    private var signedEntitlement: String?

    var isActive: Bool {
        #if DEBUG
        // 開発者アカウントでは証が常に有効なので、鍵が掛かったままの画面を
        // 確かめる手段がない。"0" を渡したときは開発者判定より先に切る。
        if let forced = ProcessInfo.processInfo.environment["LANDFALL_PASS_ACTIVE"] {
            return forced == "1"
        }
        #endif
        if AccessPolicy.isDeveloper() { return true }
        return !purchasedProductIDs.isDisjoint(with: Self.productIDs)
    }

    var isDeveloperAccess: Bool { AccessPolicy.isDeveloper() }
    var hasStoreKitEntitlement: Bool {
        !purchasedProductIDs.isDisjoint(with: Self.productIDs)
    }

    var monthly: Product? { products.first { $0.id == Self.monthlyID } }
    var annual: Product? { products.first { $0.id == Self.annualID } }

    private init() {
        updateTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                do {
                    let transaction = try Self.verified(result)
                    await transaction.finish()
                    await self.refreshEntitlements()
                } catch {
                    self.errorMessage = LF.text("We couldn't verify this purchase.")
                }
            }
        }

        Task { await reload() }
    }

    deinit { updateTask?.cancel() }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let values = try await Product.products(for: Self.productIDs)
            products = values.sorted { lhs, rhs in
                subscriptionRank(lhs) < subscriptionRank(rhs)
            }
            await refreshEntitlements()
            if values.isEmpty {
                errorMessage = LF.text("Voyage Pass is not available in this storefront yet.")
            } else {
                errorMessage = nil
            }
        } catch {
            errorMessage = LF.text("Voyage Pass could not be loaded. Please try again.")
        }
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            guard let user = Auth.auth().currentUser else {
                errorMessage = LF.text("Sign in before purchasing a Voyage Pass.")
                return
            }
            let accountToken = AccessPolicy.appAccountToken(for: user.uid)
            switch try await product.purchase(options: [.appAccountToken(accountToken)]) {
            case .success(let verification):
                let transaction = try Self.verified(verification)
                await transaction.finish()
                await refreshEntitlements()
                Haptics.success()
            case .pending:
                errorMessage = LF.text("The purchase is awaiting approval.")
            case .userCancelled:
                break
            @unknown default:
                errorMessage = LF.text("The purchase could not be completed.")
            }
        } catch {
            errorMessage = LF.text("The purchase could not be completed.")
        }
    }

    func restore() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            Haptics.success()
        } catch {
            errorMessage = LF.text("Purchases could not be restored.")
        }
    }

    /// プライベート港の作成前に、Apple署名付き取引をサーバーで再検証する。
    /// Firestoreの権限はこの検証結果だけを信頼する。
    func preparePrivateHarborCreation() async throws {
        guard Auth.auth().currentUser != nil else { throw VoyagePassAccessError.notSignedIn }
        if AccessPolicy.isDeveloper() { return }

        await refreshEntitlements()
        guard isActive, let signedEntitlement else {
            throw VoyagePassAccessError.required
        }

        do {
            let callable = Functions.functions(region: "asia-northeast1")
                .httpsCallable("syncAppStoreVoyagePass")
            _ = try await callable.call(["signedTransaction": signedEntitlement])
        } catch {
            throw VoyagePassAccessError.verificationFailed
        }
    }

    private func refreshEntitlements() async {
        var active: Set<String> = []
        var latestExpiration: Date?
        var latestSignedTransaction: String?

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? Self.verified(result),
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            active.insert(transaction.productID)
            if let expiration = transaction.expirationDate,
               latestExpiration == nil || expiration > latestExpiration! {
                latestExpiration = expiration
                latestSignedTransaction = result.jwsRepresentation
            }
        }

        purchasedProductIDs = active
        expirationDate = latestExpiration
        signedEntitlement = latestSignedTransaction
        // 航海士の色は描画スレッドからも参照されるため、確かめた結果を控えておく。
        NavigatorCustomization.updatePassState(isActive)
        BoatCustomization.updatePassState(isActive)
    }

    private static func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): value
        case .unverified:
            throw VoyagePassVerificationError.failed
        }
    }

    private func subscriptionRank(_ product: Product) -> Int {
        guard let period = product.subscription?.subscriptionPeriod else { return 99 }
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 31
        case .year: return period.value * 366
        @unknown default: return 999
        }
    }
}

private enum VoyagePassVerificationError: Error {
    case failed
}

enum VoyagePassAccessError: LocalizedError {
    case notSignedIn
    case required
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            LF.text("Sign in to enter a harbor.")
        case .required:
            LF.text("A Voyage Pass is required to open a private harbor.")
        case .verificationFailed:
            LF.text("We couldn't verify your Voyage Pass. Please try restoring purchases.")
        }
    }
}
