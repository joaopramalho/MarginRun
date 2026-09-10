import RevenueCat
import RevenueCatUI
import SwiftUI

/// The Settings entry point for everything subscription-related.
///
/// Subscribers get the RevenueCat Customer Center, which handles cancellation,
/// refund requests, plan changes and billing issues — flows that otherwise have
/// to be built and maintained by hand. Everyone else gets the paywall and the
/// restore control Apple requires.
struct SubscriptionSettingsSection: View {
    @EnvironmentObject private var store: SubscriptionStore

    @State private var isShowingGeneralPaywall = false
    @State private var isShowingCustomerCenter = false
    @StateObject private var offerCodeRedemption = OfferCodeRedemptionPresentation()

    var body: some View {
        Section {
            if store.isPro {
                LabeledContent("Plan", value: planLabel)

                if let renewal {
                    LabeledContent(renewal.label, value: renewal.value)
                }

                Button("Manage Subscription") {
                    isShowingCustomerCenter = true
                }
            } else {
                // A row that carries the value, not a bare "Upgrade" label —
                // Settings is a low-intent surface, so it has to re-earn interest.
                Button {
                    isShowingGeneralPaywall = true
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "star.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Upgrade to MarginRun Pro")
                                .font(.headline)
                            Text("Unlimited jobs, receipt scanning, labor timer, alerts & insights.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityIdentifier("settingsUpgradeButton")

                Button("Restore Purchases") {
                    Task { await store.restorePurchases(from: .settings) }
                }
                .disabled(store.isRestoring)
                .accessibilityIdentifier("settingsRestoreButton")
            }

            Button {
                offerCodeRedemption.present(using: store, from: .settings)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Redeem Offer Code")
                    Text("Have an App Store offer code? Redeem it here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("settingsRedeemOfferCodeButton")
        } header: {
            Text("Subscription")
        } footer: {
            Text(store.isPro
                 ? "Manage billing, change plans, or request a refund."
                 : "One subscription, every device signed in to your App Store account.")
        }
        .proPaywall(isPresented: $isShowingGeneralPaywall)
        .appStoreOfferCodeRedemption(
            presentation: offerCodeRedemption,
            source: .settings
        )
        .presentCustomerCenter(
            isPresented: $isShowingCustomerCenter,
            restoreCompleted: { _ in
                // `isPro` already updates through the customer info stream, so
                // there is nothing to do here beyond leaving the hook visible for
                // analytics or a confirmation toast later.
            },
            onDismiss: { isShowingCustomerCenter = false }
        )
        .subscriptionErrorAlert()
    }

    // MARK: - Entitlement detail

    private var planLabel: String {
        guard let entitlement = store.proEntitlement else { return "Pro" }

        if entitlement.periodType == .trial { return "Pro (free trial)" }
        // A non-expiring entitlement can still arrive from a legacy purchase
        // or a promotional grant, even though no lifetime plan is sold.
        // from a subscription without inspecting product identifiers.
        return entitlement.expirationDate == nil ? "Pro (lifetime)" : "Pro"
    }

    private var renewal: (label: String, value: String)? {
        guard let entitlement = store.proEntitlement,
              let expirationDate = entitlement.expirationDate else { return nil }

        let formatted = expirationDate.formatted(date: .abbreviated, time: .omitted)

        if entitlement.billingIssueDetectedAt != nil {
            return ("Billing issue", "Update payment by \(formatted)")
        }

        return entitlement.willRenew ? ("Renews", formatted) : ("Expires", formatted)
    }
}
