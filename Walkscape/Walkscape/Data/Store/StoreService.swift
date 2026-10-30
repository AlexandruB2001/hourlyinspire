import Foundation
import Observation
import StoreKit
import WalkscapeDomain

/// Real-money purchases with StoreKit 2. Only verified transactions count;
/// each one is also sent to the server (verify-purchase), which checks
/// Apple's signature again and links it to the account.
@MainActor
@Observable
final class StoreService {
    enum PurchaseOutcome: Equatable {
        case purchased
        case pending
        case cancelled
        case failed(String)
    }

    /// Loaded App Store products by id (with localized prices).
    private(set) var products: [String: Product] = [:]
    /// What this Apple ID owns on this phone.
    private(set) var entitlements = Entitlements()
    private(set) var isLoadingProducts = false
    private(set) var loadError: String?

    /// Called with each verified transaction's signed JWS (sent to the server).
    @ObservationIgnored var onVerifiedTransaction: ((String) async -> Void)?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    func start() {
        guard updatesTask == nil else { return }
        // Renewals, refunds, Ask to Buy approvals and purchases on other devices.
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: StoreCatalog.allIDs)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            loadError = loaded.isEmpty ? "The store isn't available right now." : nil
        } catch {
            loadError = "Couldn't reach the App Store. Check your connection."
        }
    }

    /// The localized price, or the catalog price until the App Store answers.
    func price(of product: StoreProduct) -> String {
        products[product.id]?.displayPrice ?? product.fallbackPrice
    }

    /// Buys `product`. `accountID` (the player's account id) is attached to the
    /// transaction so the server can tie the purchase to their account.
    func purchase(_ product: StoreProduct, accountID: UUID?) async -> PurchaseOutcome {
        guard let storeProduct = products[product.id] else { return .failed("This item isn't available right now.") }
        var options: Set<Product.PurchaseOption> = []
        if let accountID { options.insert(.appAccountToken(accountID)) }
        do {
            switch try await storeProduct.purchase(options: options) {
            case .success(let result):
                guard case .verified = result else { return .failed("The App Store couldn't verify this purchase.") }
                await handle(result)
                return .purchased
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch {
            return .failed("The purchase didn't go through. You haven't been charged.")
        }
    }

    /// "Restore purchases": asks the App Store to resync this Apple ID.
    func restore() async -> String? {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            return nil
        } catch {
            return "Couldn't restore purchases. Check that you're signed in to the App Store."
        }
    }

    /// Rebuilds entitlements from the App Store's current list (verified only).
    func refreshEntitlements() async {
        var fresh = Entitlements()
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil,
                  let product = StoreCatalog.product(withID: transaction.productID) else { continue }
            switch product.kind {
            case .bundle:
                fresh.bundles.insert(product.id)
            case .subscription:
                if let expires = transaction.expirationDate {
                    fresh.plusExpires = max(fresh.plusExpires ?? expires, expires)
                }
            }
        }
        entitlements = fresh
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        await onVerifiedTransaction?(result.jwsRepresentation)
        await transaction.finish()
        await refreshEntitlements()
    }
}
