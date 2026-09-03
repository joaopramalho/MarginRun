import Combine
import Foundation
import RevenueCat

/// Observable façade over the RevenueCat SDK.
///
/// Views never touch `Purchases` directly: they read ``isPro`` to gate features
/// and call ``purchase(_:)`` or ``restorePurchases()`` for the two write paths.
/// Keeping entitlement logic here means changing *what* Pro unlocks, or *how* it
/// is sold, never has to touch feature code.
@MainActor
final class SubscriptionStore: ObservableObject {

    /// Small test seam around the authoritative RevenueCat result. Production
    /// builds still call `Purchases.shared.purchase`; tests can supply the same
    /// three facts without opening StoreKit or making a network request.
    struct PurchaseExecutionResult {
        let customerInfo: CustomerInfo?
        let userCancelled: Bool
        let entitlementActive: Bool
    }

    typealias PurchaseHandler = (Package) async throws -> PurchaseExecutionResult

    /// What the paywall should render for the current offering.
    enum OfferingState {
        case loading
        case loaded(Offering)
        case unavailable(String)
    }

    @Published private(set) var customerInfo: CustomerInfo?
    @Published private(set) var offeringState: OfferingState = .loading
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false

    /// Set when a purchase or restore fails; views bind an alert to it.
    @Published var errorMessage: String?

    /// Alert binding for ``errorMessage``.
    ///
    /// Derived rather than stored so there is only ever one source of truth for
    /// "is there an error"; dismissing the alert clears the message.
    var isShowingError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    /// Pins ``isPro`` to a fixed value for SwiftUI previews and UI tests, where
    /// the SDK is deliberately left unconfigured. `nil` in the real app.
    private let entitlementOverride: Bool?

    /// Reports purchase and restore outcomes. Optional so previews, tests and
    /// the gating unit tests can construct a store with no reporting at all.
    private let analytics: AnalyticsService?
    private let purchaseHandler: PurchaseHandler?

    private var customerInfoObserver: Task<Void, Never>?

    init(
        entitlementOverride: Bool? = nil,
        analytics: AnalyticsService? = nil,
        purchaseHandler: PurchaseHandler? = nil
    ) {
        self.entitlementOverride = entitlementOverride
        self.analytics = analytics
        self.purchaseHandler = purchaseHandler

        guard entitlementOverride == nil, Purchases.isConfigured else { return }

        // The SDK restores the last known CustomerInfo from disk during
        // `configure`, so the very first frame already knows the entitlement
        // state. Without this the app flashes its locked UI on every cold launch
        // while the network request is in flight.
        customerInfo = Purchases.shared.cachedCustomerInfo
        observeCustomerInfo()
    }

    deinit {
        customerInfoObserver?.cancel()
    }

    // MARK: - SDK configuration

    /// Configures RevenueCat. Call once, before anything else touches the SDK.
    ///
    /// No `appUserID` is passed, so RevenueCat generates and persists an
    /// anonymous ID. That is the right default for an app without accounts; if
    /// MarginRun ever adds sign-in, call `Purchases.shared.logIn(_:)` at that
    /// point so entitlements follow the user across devices.
    static func configureSDK() {
        guard !Purchases.isConfigured else { return }

        #if DEBUG
        // Debug logs spell out which offering was served and why an entitlement
        // is or isn't active — much the fastest way to diagnose an empty paywall.
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif

        Purchases.configure(
            with: Configuration.Builder(withAPIKey: RevenueCatConfig.apiKey)
                .build()
        )
    }

    /// Reports that a locked capability was reached for.
    ///
    /// Called only from the gating helpers in `PaywallPresentation`, which every
    /// locked feature passes through — so `pro_feature_attempted` cannot go
    /// missing when a new gate is added.
    func trackProFeatureAttempt(_ feature: ProFeature) {
        analytics?.track(.proFeatureAttempted(feature: feature))
    }

    // MARK: - Entitlement

    /// Whether `marginrun_pro` is currently active.
    ///
    /// Gate on the entitlement, never on a product identifier: entitlements
    /// survive product renames, price changes, plan switches between monthly and
    /// yearly, and purchases originally made on another platform.
    var isPro: Bool {
        if let entitlementOverride { return entitlementOverride }
        return customerInfo?.entitlements[RevenueCatConfig.proEntitlementID]?.isActive == true
    }

    /// The `marginrun_pro` entitlement, for rendering renewal and billing detail.
    var proEntitlement: EntitlementInfo? {
        customerInfo?.entitlements[RevenueCatConfig.proEntitlementID]
    }

    // MARK: - Customer info

    /// Mirrors entitlement changes into ``customerInfo`` for the app's lifetime.
    ///
    /// `customerInfoStream` replays the current value and then emits on renewal,
    /// expiry, restore, billing issues, and purchases made outside the app —
    /// which is why nothing else in the app needs to poll for entitlement state.
    private func observeCustomerInfo() {
        customerInfoObserver?.cancel()
        customerInfoObserver = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.customerInfo = info
            }
        }
    }

    /// Forces a refresh from the network.
    ///
    /// The stream covers normal operation; this exists for explicit
    /// pull-to-refresh style affordances.
    func refreshCustomerInfo() async {
        guard isSDKAvailable else { return }

        do {
            customerInfo = try await Purchases.shared.customerInfo()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    // MARK: - Offerings

    /// Loads the current offering: the packages the dashboard is serving to this
    /// specific user, including whatever an active experiment assigns them.
    func loadOffering() async {
        guard isSDKAvailable else {
            // Previews and UI tests pin the entitlement and never configure the
            // SDK. Serving them a fixed offering is what makes the paywall's
            // layout renderable and assertable at all — without it the screen
            // could only ever show its unavailable state. A shipped launch
            // never takes this branch, because it has no pinned entitlement.
            offeringState = entitlementOverride == nil
                ? .unavailable("Purchases aren't available in this build.")
                : .loaded(PaywallFixture.offering())
            return
        }

        offeringState = .loading

        do {
            let offerings = try await Purchases.shared.offerings()

            guard let current = offerings.current else {
                offeringState = .unavailable(
                    "No current offering is configured. Set one in RevenueCat → Offerings."
                )
                return
            }

            guard !current.availablePackages.isEmpty else {
                offeringState = .unavailable(
                    "The current offering has no packages attached."
                )
                return
            }

            offeringState = .loaded(current)
        } catch {
            offeringState = .unavailable(Self.message(for: error))
        }
    }

    // MARK: - Purchasing

    /// Buys `package` and reports whether Pro is unlocked afterwards.
    ///
    /// Also the single place purchase analytics are emitted, so the funnel can
    /// never disagree with what RevenueCat actually did: `purchase_completed`
    /// is sent only once the entitlement is confirmed active, cancelling is
    /// reported as its own outcome rather than as a failure, and restores are
    /// counted separately in ``restorePurchases()``.
    ///
    /// - Parameters:
    ///   - plan: which product this is, for the `plan` property. No price is
    ///     ever reported.
    ///   - feature: what the customer had reached for, for `paywall_context`.
    /// - Returns: `true` once the entitlement is active; `false` if the user
    ///   cancelled or the purchase failed.
    @discardableResult
    func purchase(
        _ package: Package,
        plan: AnalyticsPlan = .other,
        feature: ProFeature? = nil
    ) async -> Bool {
        // Also the duplicate-tap guard: a second call while one is in flight
        // returns without starting anything or emitting a second event.
        guard isSDKAvailable, !isPurchasing else { return false }

        isPurchasing = true
        defer { isPurchasing = false }
        analytics?.track(.purchaseStarted(plan: plan, feature: feature))

        do {
            let result: PurchaseExecutionResult
            if let purchaseHandler {
                result = try await purchaseHandler(package)
            } else {
                let revenueCatResult = try await Purchases.shared.purchase(package: package)
                result = PurchaseExecutionResult(
                    customerInfo: revenueCatResult.customerInfo,
                    userCancelled: revenueCatResult.userCancelled,
                    entitlementActive: revenueCatResult.customerInfo
                        .entitlements[RevenueCatConfig.proEntitlementID]?.isActive == true
                )
            }

            // Cancelling is a normal outcome, not an error. Alerting on it is the
            // classic way to annoy someone who just deliberately tapped "Cancel".
            guard !result.userCancelled else {
                analytics?.track(.purchaseCancelled(plan: plan, feature: feature))
                return false
            }

            if let updatedCustomerInfo = result.customerInfo {
                customerInfo = updatedCustomerInfo
            }

            guard result.entitlementActive else {
                // StoreKit reported a purchase but RevenueCat still shows no
                // entitlement. Counting this as a conversion would inflate the
                // funnel against revenue that does not exist.
                analytics?.track(
                    .purchaseFailed(plan: plan, feature: feature, reason: .entitlementNotActive)
                )
                return false
            }

            analytics?.track(.purchaseCompleted(plan: plan, feature: feature))
            return true
        } catch {
            if Self.isCancellation(error) {
                analytics?.track(.purchaseCancelled(plan: plan, feature: feature))
                return false
            }
            errorMessage = Self.message(for: error)
            analytics?.track(
                .purchaseFailed(plan: plan, feature: feature, reason: Self.failureReason(for: error))
            )
            return false
        }
    }

    /// Restores purchases tied to the current App Store account.
    ///
    /// Apple requires a visible restore control anywhere a subscription is sold,
    /// which is why this is wired to an explicit button rather than run on launch.
    @discardableResult
    func restorePurchases(from source: RestoreSource = .settings) async -> Bool {
        guard isSDKAvailable, !isRestoring else { return false }

        isRestoring = true
        defer { isRestoring = false }
        analytics?.track(.restoreStarted(source: source))

        do {
            customerInfo = try await Purchases.shared.restorePurchases()

            if !isPro {
                errorMessage = "We didn't find an active MarginRun Pro purchase on this account."
            }
            // Reported apart from `purchase_completed` throughout: a reinstall
            // recovering an old subscription is not a new sale.
            analytics?.track(
                .restoreCompleted(
                    source: source,
                    outcome: isPro ? .entitlementRestored : .nothingToRestore
                )
            )
            return isPro
        } catch {
            errorMessage = Self.message(for: error)
            analytics?.track(.restoreCompleted(source: source, outcome: .failed))
            return false
        }
    }

    // MARK: - Errors

    /// `false` in previews and UI tests, where `Purchases.shared` would trap.
    private var isSDKAvailable: Bool {
        purchaseHandler != nil || (entitlementOverride == nil && Purchases.isConfigured)
    }

    /// Turns a RevenueCat error into something worth showing a customer.
    ///
    /// The SDK surfaces failures as `NSError` in `ErrorCode.errorDomain` rather
    /// than as `ErrorCode` values, so the code is read back off the domain.
    /// Anything not special-cased falls through to the SDK's own message, which
    /// already carries StoreKit's wording.
    private static func message(for error: Error) -> String {
        let nsError = error as NSError

        guard nsError.domain == ErrorCode.errorDomain,
              let code = ErrorCode(rawValue: nsError.code) else {
            return error.localizedDescription
        }

        switch code {
        case .networkError, .offlineConnectionError:
            return "Couldn't reach the App Store. Check your connection and try again."
        case .purchaseNotAllowedError:
            return "This device isn't allowed to make purchases. Check Screen Time restrictions."
        case .productAlreadyPurchasedError:
            return "You already own this. Tap Restore Purchases to unlock it."
        case .paymentPendingError:
            return "Your purchase is pending approval. Pro unlocks as soon as it clears."
        case .productNotAvailableForPurchaseError:
            return "That plan isn't available right now. Please try again later."
        case .configurationError, .invalidCredentialsError:
            return "Subscriptions are misconfigured in this build. Please contact support."
        default:
            return error.localizedDescription
        }
    }

    /// Collapses a RevenueCat error into the small, low-cardinality vocabulary
    /// the funnel reports. Never the raw message, which can carry store or
    /// account detail.
    static func failureReason(for error: Error) -> PurchaseFailureReason {
        let nsError = error as NSError

        guard nsError.domain == ErrorCode.errorDomain,
              let code = ErrorCode(rawValue: nsError.code) else {
            return .unknown
        }

        switch code {
        case .networkError, .offlineConnectionError: return .network
        case .purchaseNotAllowedError: return .notAllowed
        case .productAlreadyPurchasedError: return .alreadyPurchased
        case .paymentPendingError: return .pending
        case .productNotAvailableForPurchaseError: return .productUnavailable
        case .configurationError, .invalidCredentialsError: return .configuration
        default: return .unknown
        }
    }

    /// RevenueCat normally reports cancellation on the purchase result, but
    /// StoreKit paths can also surface its stable cancellation error code.
    /// Both must land in `purchase_cancelled`, never `purchase_failed`.
    static func isCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == ErrorCode.errorDomain
            && ErrorCode(rawValue: nsError.code) == .purchaseCancelledError
    }
}
