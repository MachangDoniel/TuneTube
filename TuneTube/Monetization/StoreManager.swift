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
    private(set) var hasLifetime: Bool
    private(set) var subscriptionExpiry: Date?
    private(set) var isPro: Bool
    private(set) var isPurchasing = false
    private(set) var lastError: String?

    /// Lives for the app's lifetime (this is a singleton), so it is never cancelled.
    private var updatesTask: Task<Void, Never>?
    private static let cacheKey = "tunetube.isPro"
    private static let lifetimeKey = "tunetube.hasLifetime"
    private static let expiryKey = "tunetube.subscriptionExpiry"

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
        let cachedLifetime = UserDefaults.standard.bool(forKey: Self.lifetimeKey)
        let cachedExpiryInterval = UserDefaults.standard.double(forKey: Self.expiryKey)
        let cachedExpiry = cachedExpiryInterval > 0 ? Date(timeIntervalSince1970: cachedExpiryInterval) : nil
        let hasActiveSub = cachedExpiry != nil && cachedExpiry! > Date()
        let cachedPro = UserDefaults.standard.bool(forKey: Self.cacheKey)

        self.hasLifetime = cachedLifetime
        self.subscriptionExpiry = cachedExpiry
        self.isPro = Self.forcedPro || cachedLifetime || hasActiveSub || cachedPro

        // Must start at launch, not at paywall presentation: this is how we hear
        // about renewals, Ask-to-Buy approvals and refunds that happen offscreen.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if let transaction = self.checkVerified(update) {
                    await transaction.finish()
                    await self.handleTransaction(transaction)
                }
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
        if Self.forcedPro {
            updateProState()
            return
        }

        var foundLifetime = false
        var lifetimeRevoked = false
        var latestExpiry: Date? = nil
        var foundAnyActiveTransaction = false

        for await result in Transaction.currentEntitlements {
            guard let transaction = checkVerified(result) else { continue }

            if transaction.productID == ProductID.lifetime {
                if transaction.revocationDate != nil {
                    lifetimeRevoked = true
                } else {
                    foundLifetime = true
                    foundAnyActiveTransaction = true
                }
            } else if transaction.productID == ProductID.weekly {
                if transaction.revocationDate == nil, let expiry = transaction.expirationDate {
                    if latestExpiry == nil || expiry > latestExpiry! {
                        latestExpiry = expiry
                    }
                    if expiry > Date() {
                        foundAnyActiveTransaction = true
                    }
                }
            }
        }

        // Lifetime is permanent: only clear if StoreKit explicitly confirms revocation/refund.
        // If offline or StoreKit yields no transactions, retain existing hasLifetime.
        if foundLifetime {
            setLifetime(true)
        } else if lifetimeRevoked {
            setLifetime(false)
        }

        if let latestExpiry {
            setSubscriptionExpiry(latestExpiry)
        } else if foundAnyActiveTransaction && !hasLifetime {
            // Entitlements answered actively, but weekly subscription is not present
            setSubscriptionExpiry(nil)
        }

        updateProState()
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        lastError = nil
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard let transaction = checkVerified(verification) else {
                    lastError = "That purchase couldn't be verified."
                    return false
                }
                await transaction.finish()
                await handleTransaction(transaction)
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

    // MARK: - Internal Helpers

    private func checkVerified<T>(_ result: VerificationResult<T>) -> T? {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified(let unverified, _):
            #if DEBUG
            // StoreKit testing files sign locally; allow unverified in debug builds.
            return unverified
            #else
            return nil
            #endif
        }
    }

    private func handleTransaction(_ transaction: Transaction) async {
        guard ProductID.all.contains(transaction.productID) else { return }

        if transaction.productID == ProductID.lifetime {
            if transaction.revocationDate != nil {
                setLifetime(false)
            } else {
                setLifetime(true)
            }
        } else if transaction.productID == ProductID.weekly {
            if transaction.revocationDate != nil {
                setSubscriptionExpiry(nil)
            } else if let expiry = transaction.expirationDate {
                if subscriptionExpiry == nil || expiry > subscriptionExpiry! {
                    setSubscriptionExpiry(expiry)
                }
            }
        }
        updateProState()
    }

    private func setLifetime(_ value: Bool) {
        hasLifetime = value
        UserDefaults.standard.set(value, forKey: Self.lifetimeKey)
    }

    private func setSubscriptionExpiry(_ date: Date?) {
        subscriptionExpiry = date
        if let date {
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Self.expiryKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.expiryKey)
        }
    }

    private func updateProState() {
        let hasActiveSub = (subscriptionExpiry != nil && subscriptionExpiry! > Date())
        let pro = Self.forcedPro || hasLifetime || hasActiveSub
        isPro = pro
        UserDefaults.standard.set(pro, forKey: Self.cacheKey)
    }
}
