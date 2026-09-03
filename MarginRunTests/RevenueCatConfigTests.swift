import Foundation
import Testing
@testable import MarginRun

/// The RevenueCat wiring that decides whether money can actually change hands.
///
/// Worth pinning because getting it wrong is silent: a Test Store key in a
/// shipped build serves the paywall, completes the purchase, unlocks the
/// entitlement and shows the Customer Center — all simulated on-device. Nothing
/// errors. The only symptom is that no one ever subscribes.
struct RevenueCatConfigTests {

    @Test func eachKeyIsTheStoreItClaimsToBe() {
        #expect(RevenueCatConfig.appStoreAPIKey.hasPrefix("appl_"))
        #expect(RevenueCatConfig.testStoreAPIKey.hasPrefix("test_"))
        #expect(RevenueCatConfig.appStoreAPIKey != RevenueCatConfig.testStoreAPIKey)
    }

    /// Neither key may be a secret key. `sk_` belongs on a server and would be
    /// a credential leak sitting in the app binary.
    @Test func noSecretKeyIsShippedInTheClient() {
        for key in [RevenueCatConfig.appStoreAPIKey, RevenueCatConfig.testStoreAPIKey] {
            #expect(key.hasPrefix("sk_") == false)
        }
    }

    /// The suite only ever runs in Debug, so this asserts the half it can see.
    /// The Release half is covered by ``eachKeyIsTheStoreItClaimsToBe``: given
    /// the prefixes hold, the `#if` in `RevenueCatConfig` can only resolve to
    /// the App Store key.
    @Test func aDebugBuildNeverTouchesTheRealStore() {
        #if DEBUG
        #expect(RevenueCatConfig.apiKey == RevenueCatConfig.testStoreAPIKey)
        #expect(RevenueCatConfig.apiKey.hasPrefix("test_"))
        #else
        #expect(RevenueCatConfig.apiKey == RevenueCatConfig.appStoreAPIKey)
        #endif
    }

    /// Gating reads the entitlement, never a product identifier — a rename in
    /// the dashboard would otherwise lock every paid feature at runtime.
    @Test func theEntitlementIdentifierIsTheOneGatingReads() {
        #expect(RevenueCatConfig.proEntitlementID == "marginrun_pro")
    }
}
