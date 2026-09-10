import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreManager.self) private var store

    @State private var selected = StoreManager.ProductID.lifetime
    var config: PaywallConfig = RemoteConfig.fallback.paywall

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            Text(config.title)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 22)

            Text(config.subtitle)
                .font(.system(size: 16))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(spacing: 12) {
                tierCard(id: StoreManager.ProductID.lifetime,
                         title: "Lifetime Pro",
                         caption: "One-time payment for permanent Pro access.",
                         badge: "POPULAR",
                         fallbackPrice: "£14.99")
                tierCard(id: StoreManager.ProductID.weekly,
                         title: "Weekly Pro",
                         caption: "Billed weekly.",
                         badge: nil,
                         fallbackPrice: "£1.99")
            }
            .padding(.top, 26)

            Button {
                Task { await buy() }
            } label: {
                Group {
                    if store.isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text("Continue with \(selected == StoreManager.ProductID.lifetime ? "Lifetime" : "Weekly") Pro")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .clipShape(Capsule())
            .disabled(store.isPurchasing)
            .padding(.top, 26)

            Button("Restore Purchases") {
                Task {
                    await store.restore()
                    if store.isPro { dismiss() }
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 16)

            HStack(spacing: 20) {
                Link("Terms", destination: config.termsUrl)
                Link("Privacy", destination: config.privacyUrl)
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.textSecondary.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.top, 14)

            if let error = store.lastError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background.ignoresSafeArea())
        .task {
            await store.bootstrap()
            if store.isPro { dismiss() }
        }
        .onAppear {
            if store.isPro { dismiss() }
        }
        .onChange(of: store.isPro) { _, isPro in
            if isPro { dismiss() }
        }
    }

    private func buy() async {
        guard let product = store.product(selected) else {
            // No StoreKit product (unconfigured App Store Connect, or no
            // .storekit file in the scheme). Say so instead of failing silently.
            store.reportMissingProduct(selected)
            return
        }
        if await store.purchase(product) { dismiss() }
    }

    @ViewBuilder
    private func tierCard(
        id: String, title: String, caption: String, badge: String?, fallbackPrice: String
    ) -> some View {
        let isSelected = selected == id
        // Always prefer StoreKit's localised price. A hardcoded "£14.99" shows
        // the wrong currency to every user outside the UK.
        let price = store.product(id)?.displayPrice ?? fallbackPrice

        Button { selected = id } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .overlay(Capsule().stroke(Theme.accent, lineWidth: 1))
                        }
                    }
                    Text(caption)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Text(price)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.12) : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Theme.accent : Color.white.opacity(0.08),
                            lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
