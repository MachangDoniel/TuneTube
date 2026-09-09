import Foundation
import StoreKit

/// StoreKit 2 entitlements. No third-party billing SDK.
///
/// Entitlement is "owns lifetime OR has an active weekly subscription". It is
/// mirrored into UserDefaults so a launch with no network is never a silent
/// downgrade — StoreKit is still the source of truth once it answers.
@MainActor
@Observable
final class StoreManager {
    static let shared = StoreManager()

    enum ProductID {
        static let lifetime = "com.tunetube.pro.lifetime"
        static let weekly   = "com.tunetube.pro.weekly"
        static let all      = [lifetime, weekly]
    }

    private(set) var products: [Product] = []
    private(set) var isPro: Bool
    private(set) var isPurchasing = false
    private(set) var lastError: String?

    /// Lives for the app's lifetime (this is a singleton), so it is never cancelled.
    private var updatesTask: Task<Void, Never>?
    private static let cacheKey = "tunetube.isPro"

    /// DEBUG-only entitlement override. StoreKit configuration files only apply
    /// when the app is launched from Xcode's scheme, so `simctl` runs can never
    /// buy anything; this makes the Pro paths testable from the command line.
    /// Launch with SIMCTL_CHILD_TUNETUBE_FORCE_PRO=1.
    private static var forcedPro: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["TUNETUBE_FORCE_PRO"] == "1"
        #else
        false
        #endif
    }

    private init() {
        isPro = Self.forcedPro || UserDefaults.standard.bool(forKey: Self.cacheKey)
        // Must start at launch, not at paywall presentation: this is how we hear
        // about renewals, Ask-to-Buy approvals and refunds that happen offscreen.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self.refreshEntitlement()
            }
        }
    }

    func bootstrap() async {
        await loadProducts()
        await refreshEntitlement()
    }

    func loadProducts() async {
        do {
            let fetched = try await Product.products(for: ProductID.all)
            // Lifetime first, matching the paywall layout.
            products = fetched.sorted { a, _ in a.id == ProductID.lifetime }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func product(_ id: String) -> Product? { products.first { $0.id == id } }

    func refreshEntitlement() async {
        if Self.forcedPro { setPro(true); return }
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.revocationDate != nil { continue }
            if let expiry = transaction.expirationDate, expiry < Date() { continue }
            if ProductID.all.contains(transaction.productID) { entitled = true }
        }
        setPro(entitled)
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        lastError = nil
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastError = "That purchase couldn't be verified."
                    return false
                }
                await transaction.finish()
                await refreshEntitlement()
                return true
            case .userCancelled:
                return false
            case .pending:
                // Ask-to-Buy: Transaction.updates delivers the result later.
                lastError = "Your purchase is pending approval."
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Surfaced when a product id isn't configured in App Store Connect or the
    /// local .storekit file, which otherwise looks like a dead button.
    func reportMissingProduct(_ id: String) {
        lastError = "Product \(id) isn't available. Check App Store Connect or the StoreKit configuration."
    }

    private func setPro(_ value: Bool) {
        isPro = value
        UserDefaults.standard.set(value, forKey: Self.cacheKey)
    }
}
