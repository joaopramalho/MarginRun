import Testing
@testable import MarginRun

struct PaywallRoutingTests {
    @Test func revenueCatMetadataUsesDashboardPaywallWhenAvailable() {
        #expect(
            PaywallMode.resolve(
                metadataValue: "revenuecat",
                revenueCatPaywallAvailable: true
            ) == .revenueCat
        )
    }

    @Test func nativeMetadataUsesNativePaywall() {
        #expect(
            PaywallMode.resolve(
                metadataValue: "native",
                revenueCatPaywallAvailable: true
            ) == .native
        )
    }

    @Test(arguments: [nil, "", "unknown", "revenue_cat"] as [String?])
    func missingOrInvalidMetadataFallsBackToNative(value: String?) {
        #expect(
            PaywallMode.resolve(
                metadataValue: value,
                revenueCatPaywallAvailable: true
            ) == .native
        )
    }

    @Test func missingRevenueCatPaywallConfigurationFallsBackToNative() {
        #expect(
            PaywallMode.resolve(
                metadataValue: "revenuecat",
                revenueCatPaywallAvailable: false
            ) == .native
        )
    }

    @Test func unavailableOfferingFallsBackToNative() {
        #expect(
            PaywallMode.resolve(
                metadataValue: "revenuecat",
                offeringAvailable: false,
                revenueCatPaywallAvailable: true
            ) == .native
        )
    }

    @Test func revenueCatConfigurationErrorFallsBackToNative() {
        #expect(
            PaywallMode.resolve(
                metadataValue: "revenuecat",
                offeringAvailable: true,
                revenueCatPaywallAvailable: false
            ) == .native
        )
    }

    @Test func metadataIsCaseAndWhitespaceTolerant() {
        #expect(
            PaywallMode.resolve(
                metadataValue: "  RevenueCat ",
                revenueCatPaywallAvailable: true
            ) == .revenueCat
        )
    }
}
