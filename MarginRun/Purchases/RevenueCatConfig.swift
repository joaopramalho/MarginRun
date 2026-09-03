import Foundation

/// Every RevenueCat identifier the app depends on, in one place.
///
/// These strings have to match the RevenueCat dashboard exactly. A typo here
/// does not fail the build — it produces an empty paywall or a permanently
/// locked feature at runtime — so they are declared once and never inlined.
nonisolated enum RevenueCatConfig {

    /// The App Store key: real StoreKit products, real money, real revenue in
    /// the RevenueCat dashboard. From *Project Settings → API keys*.
    static let appStoreAPIKey = "appl_wWUYnquxjdWkgogcIpdVJKiaOJS"

    /// The Test Store key. RevenueCat simulates the entire purchase flow
    /// on-device, so the paywall, the entitlement and the Customer Center all
    /// work without App Store Connect products or a sandbox account — but no
    /// money moves and nothing syncs to a real store.
    static let testStoreAPIKey = "test_CxVXBpmKGuumJfdUyJoLuefLQHl"

    /// Public SDK key for this app, chosen by build configuration.
    ///
    /// Public SDK keys are designed to ship inside the app binary, so checking
    /// these in is expected — they are not secrets. Never put a *secret* key
    /// (`sk_…`) in the client.
    ///
    /// - Important: the direction of this split matters and must not be
    ///   inverted. A Test Store key in a shipped build simulates every
    ///   purchase, which means no customer can actually subscribe and no
    ///   revenue is recorded — and nothing about it fails loudly, because the
    ///   paywall still works perfectly.
    #if DEBUG
    static let apiKey = testStoreAPIKey
    #else
    static let apiKey = appStoreAPIKey
    #endif

    /// The entitlement that unlocks every paid feature.
    ///
    /// Gate features on this, never on a product identifier — see
    /// ``SubscriptionStore/isPro``.
    static let proEntitlementID = "marginrun_pro"

    /// Links Apple requires on any screen that sells a subscription.
    ///
    /// - Important: both URLs must resolve. A paywall linking to a dead privacy
    ///   policy is an App Review rejection, so this is worth re-checking
    ///   whenever the policy moves.
    nonisolated enum Legal {
        static let privacyPolicy = URL(
            string: "https://worried-tail-a2c.notion.site/Privacy-Policy-for-MarginRun-3d049db6866c80af86f9ee9c21048ff9"
        )!
        /// Apple's standard EULA, valid when the app ships without a custom one.
        static let termsOfUse = URL(
            string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
        )!
    }

    /// Package identifiers expected on the current offering.
    ///
    /// RevenueCat's predefined packages use `$rc_`-prefixed identifiers. The
    /// dashboard shows them as Annual / Monthly; these are the raw values the
    /// SDK reports in `Package.identifier`.
    nonisolated enum PackageID {
        static let yearly = "$rc_annual"
        static let monthly = "$rc_monthly"

        /// MarginRun does not sell a lifetime plan. Kept only so
        /// ``PlanOption/options(from:)`` can filter one out if the offering
        /// still carries it, rather than surfacing it as a nameless extra row.
        static let lifetime = "$rc_lifetime"
    }
}
