import Foundation
import RevenueCat
import Testing
@testable import MarginRun

/// A purchase that failed and a purchase the customer cancelled are different
/// events, and the reason attached to a failure has to stay a small, readable
/// vocabulary rather than a raw store message.
@MainActor
struct PurchaseFailureReasonTests {

    private func revenueCatError(_ code: ErrorCode) -> NSError {
        NSError(domain: ErrorCode.errorDomain, code: code.rawValue)
    }

    @Test func networkFailuresAreReportedAsNetwork() {
        #expect(
            SubscriptionStore.failureReason(for: revenueCatError(.networkError)) == .network
        )
        #expect(
            SubscriptionStore.failureReason(for: revenueCatError(.offlineConnectionError))
                == .network
        )
    }

    @Test func restrictionsAndBillingStatesKeepTheirOwnReasons() {
        #expect(
            SubscriptionStore.failureReason(for: revenueCatError(.purchaseNotAllowedError))
                == .notAllowed
        )
        #expect(
            SubscriptionStore.failureReason(for: revenueCatError(.productAlreadyPurchasedError))
                == .alreadyPurchased
        )
        #expect(
            SubscriptionStore.failureReason(for: revenueCatError(.paymentPendingError)) == .pending
        )
        #expect(
            SubscriptionStore.failureReason(
                for: revenueCatError(.productNotAvailableForPurchaseError)
            ) == .productUnavailable
        )
        #expect(
            SubscriptionStore.failureReason(for: revenueCatError(.configurationError))
                == .configuration
        )
    }

    /// An error from anywhere else must not leak its message into a property.
    @Test func unrecognisedErrorsCollapseToUnknown() {
        let foreign = NSError(
            domain: "SomeOtherDomain",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Chen Residence card declined"]
        )

        #expect(SubscriptionStore.failureReason(for: foreign) == .unknown)
    }

    /// Cancelling is a normal outcome. It has no failure reason at all, and
    /// mapping it to one would put user intent in the failure funnel.
    @Test func cancellationIsNotAFailureReason() {
        #expect(PurchaseFailureReason.allReasons.contains("cancelled") == false)
    }
}

private extension PurchaseFailureReason {
    static var allReasons: [String] {
        [
            PurchaseFailureReason.network, .notAllowed, .alreadyPurchased, .pending,
            .productUnavailable, .configuration, .entitlementNotActive, .unknown,
        ].map(\.rawValue)
    }
}
