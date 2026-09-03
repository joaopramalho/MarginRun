import Foundation
import SwiftUI
import Testing
@testable import MarginRun

/// Covers the routing contract every gate depends on: locked features raise the
/// paywall with the right context, unlocked ones proceed silently.
@MainActor
struct ProGatingTests {

    /// Mirrors how a view holds `@State private var paywallFeature: ProFeature?`.
    private func paywallSlot() -> (Binding<ProFeature?>, () -> ProFeature?) {
        final class Box { var value: ProFeature? }
        let box = Box()
        let binding = Binding<ProFeature?>(
            get: { box.value },
            set: { box.value = $0 }
        )
        return (binding, { box.value })
    }

    @Test func freeUserIsRoutedToThePaywallWithTheTriggeringFeature() {
        let store = SubscriptionStore(entitlementOverride: false)
        let (binding, presented) = paywallSlot()

        let allowed = store.requirePro(.insights, presenting: binding)

        #expect(allowed == false)
        #expect(presented() == .insights)
    }

    @Test func everyGatedFeatureCarriesItsOwnContext() {
        let store = SubscriptionStore(entitlementOverride: false)

        for feature in ProFeature.allCases {
            let (binding, presented) = paywallSlot()
            #expect(store.requirePro(feature, presenting: binding) == false)
            #expect(presented() == feature)
        }
    }

    @Test func proUserProceedsWithoutSeeingAPaywall() {
        let store = SubscriptionStore(entitlementOverride: true)

        for feature in ProFeature.allCases {
            let (binding, presented) = paywallSlot()
            #expect(store.requirePro(feature, presenting: binding) == true)
            #expect(presented() == nil)
        }
    }

    @Test func thirdActiveJobRaisesTheUnlimitedJobsPaywall() {
        let store = SubscriptionStore(entitlementOverride: false)
        let (binding, presented) = paywallSlot()

        let allowed = store.requireActiveJobSlot(activeJobCount: 2, presenting: binding)

        #expect(allowed == false)
        #expect(presented() == .unlimitedJobs)
    }

    @Test func secondActiveJobIsAllowedOnFree() {
        let store = SubscriptionStore(entitlementOverride: false)
        let (binding, presented) = paywallSlot()

        #expect(store.requireActiveJobSlot(activeJobCount: 1, presenting: binding))
        #expect(presented() == nil)
    }

    @Test func proUserCanAlwaysCreateAnotherActiveJob() {
        let store = SubscriptionStore(entitlementOverride: true)
        let (binding, presented) = paywallSlot()

        #expect(store.requireActiveJobSlot(activeJobCount: 99, presenting: binding))
        #expect(presented() == nil)
    }

    @Test func isUnlockedFollowsTheEntitlement() {
        let free = SubscriptionStore(entitlementOverride: false)
        let pro = SubscriptionStore(entitlementOverride: true)

        for feature in ProFeature.allCases {
            #expect(free.isUnlocked(feature) == false)
            #expect(pro.isUnlocked(feature))
        }
    }
}
