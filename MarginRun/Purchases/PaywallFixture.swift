import Foundation
import RevenueCat

/// A fixed offering for SwiftUI previews and UI tests.
///
/// Neither previews nor UI tests configure the RevenueCat SDK, so without this
/// the paywall could only ever render its "plans unavailable" state — and the
/// one thing most worth testing about it, that a monthly plan is visible beside
/// the yearly one before anyone can buy, would be untestable.
///
/// Built from RevenueCat's own ``TestStoreProduct``, so the paywall reads it
/// through exactly the same `Offering` API as production. Reached only when
/// ``SubscriptionStore`` was constructed with a pinned entitlement, which never
/// happens in a shipped launch.
nonisolated enum PaywallFixture {

    /// Mirrors the live App Store products so previews and screenshots show the
    /// real shape of the offer: $99.99 a year is $8.33 a month against $12.99,
    /// a 36% saving. These two strings are the **only** hardcoded prices in the
    /// app, and they are never read in a shipped launch — the paywall itself
    /// derives every figure from whatever RevenueCat serves. Update them here
    /// when App Store Connect pricing changes, so the screenshots stay honest.
    static func offering() -> Offering {
        let identifier = "fixture"

        let annual = TestStoreProduct(
            localizedTitle: "MarginRun Pro (Yearly)",
            price: Decimal(string: "99.99")!,
            currencyCode: "USD",
            localizedPriceString: "$99.99",
            productIdentifier: "marginrun.pro.yearly",
            productType: .autoRenewableSubscription,
            localizedDescription: "Everything in MarginRun Pro, billed yearly.",
            subscriptionGroupIdentifier: "marginrun.pro",
            subscriptionPeriod: SubscriptionPeriod(value: 1, unit: .year),
            locale: Locale(identifier: "en_US")
        )

        let monthly = TestStoreProduct(
            localizedTitle: "MarginRun Pro (Monthly)",
            price: Decimal(string: "12.99")!,
            currencyCode: "USD",
            localizedPriceString: "$12.99",
            productIdentifier: "marginrun.pro.monthly",
            productType: .autoRenewableSubscription,
            localizedDescription: "Everything in MarginRun Pro, billed monthly.",
            subscriptionGroupIdentifier: "marginrun.pro",
            subscriptionPeriod: SubscriptionPeriod(value: 1, unit: .month),
            locale: Locale(identifier: "en_US")
        )

        let context = PresentedOfferingContext(offeringIdentifier: identifier)

        return Offering(
            identifier: identifier,
            serverDescription: "Preview and UI-test offering",
            availablePackages: [
                Package(
                    identifier: RevenueCatConfig.PackageID.yearly,
                    packageType: .annual,
                    storeProduct: annual.toStoreProduct(),
                    presentedOfferingContext: context,
                    webCheckoutUrl: nil
                ),
                Package(
                    identifier: RevenueCatConfig.PackageID.monthly,
                    packageType: .monthly,
                    storeProduct: monthly.toStoreProduct(),
                    presentedOfferingContext: context,
                    webCheckoutUrl: nil
                ),
            ],
            webCheckoutUrl: nil
        )
    }
}
