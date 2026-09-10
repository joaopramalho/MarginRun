import Combine
import Foundation
import RevenueCat
import StoreKit

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

    /// Test seam matching the authoritative result of RevenueCat's
    /// `syncPurchases()`. Production still receives the real `CustomerInfo`.
    struct OfferCodeSyncResult {
        let customerInfo: CustomerInfo?
        let entitlementActive: Bool
    }

    typealias PurchaseHandler = (Package) async throws -> PurchaseExecutionResult
    typealias OfferCodeSyncHandler = () async throws -> OfferCodeSyncResult

    /// What the paywall should render for the current offering.
    enum OfferingState {
        case loading
        case loaded(Offering)
        case unavailable(String)
    }

    @Published private(set) var customerInfo: CustomerInfo?
    @Published private(set) var offeringState: OfferingState = .loading
    @Published private(set) var introEligibilityByProductID: [String: IntroEligibilityStatus] = [:]
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
    private let offerCodeSyncHandler: OfferCodeSyncHandler?
    private let purchaseHandler: PurchaseHandler?

    private var customerInfoObserver: Task<Void, Never>?
    private var offerCodeEntitlementSnapshot: OfferCodeEntitlementSnapshot?

    init(
        entitlementOverride: Bool? = nil,
        analytics: AnalyticsService? = nil,
        offerCodeSyncHandler: OfferCodeSyncHandler? = nil,
        purchaseHandler: PurchaseHandler? = nil
    ) {
        self.entitlementOverride = entitlementOverride
        self.analytics = analytics
        self.offerCodeSyncHandler = offerCodeSyncHandler
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

    // MARK: - Offer codes

    /// Records the tap and snapshots the current entitlement so a plain sheet
    /// dismissal cannot be mistaken for a redeemed code.
    func offerCodeRedemptionOpened(from source: OfferCodeRedemptionSource) {
        offerCodeEntitlementSnapshot = currentOfferCodeEntitlementSnapshot
        analytics?.track(.offerCodeRedemptionOpened(source: source))
    }

    /// Handles the completion from Apple's official redemption sheet.
    ///
    /// The SwiftUI API in the project's current SDK reports whether presentation
    /// completed, while RevenueCat remains authoritative about access. A
    /// successful presentation therefore syncs StoreKit transactions into
    /// RevenueCat and only reports success after an active, changed entitlement
    /// is confirmed. Dismissing the sheet without redeeming changes nothing and
    /// stays silent.
    func offerCodeRedemptionFinished(
        _ result: Result<Void, Error>,
        from source: OfferCodeRedemptionSource
    ) async {
        switch result {
        case .failure(let error):
            offerCodeEntitlementSnapshot = nil
            guard !Self.isOfferCodeCancellation(error) else { return }
            reportOfferCodeFailure(error, from: source, occurredDuringSync: false)

        case .success:
            await syncOfferCodeRedemption(from: source)
        }
    }

    private func syncOfferCodeRedemption(from source: OfferCodeRedemptionSource) async {
        guard offerCodeSyncHandler != nil || isSDKAvailable else {
            offerCodeEntitlementSnapshot = nil
            return
        }

        let before = offerCodeEntitlementSnapshot
        defer { offerCodeEntitlementSnapshot = nil }

        do {
            let syncResult: OfferCodeSyncResult
            if let offerCodeSyncHandler {
                syncResult = try await offerCodeSyncHandler()
            } else {
                let info = try await Purchases.shared.syncPurchases()
                syncResult = OfferCodeSyncResult(
                    customerInfo: info,
                    entitlementActive: info.entitlements[RevenueCatConfig.proEntitlementID]?.isActive == true
                )
            }

            if let updatedCustomerInfo = syncResult.customerInfo {
                customerInfo = updatedCustomerInfo
            }

            let after = currentOfferCodeEntitlementSnapshot
            let entitlementChanged = before != after
                || before?.isActive != syncResult.entitlementActive
            guard syncResult.entitlementActive, entitlementChanged else {
                // The old SwiftUI completion also runs when the system sheet is
                // simply dismissed. No changed entitlement means cancellation
                // or no redemption, neither of which should show an error.
                return
            }

            analytics?.track(.offerCodeRedemptionSucceeded(source: source))
        } catch {
            reportOfferCodeFailure(error, from: source, occurredDuringSync: true)
        }
    }

    private func reportOfferCodeFailure(
        _ error: Error,
        from source: OfferCodeRedemptionSource,
        occurredDuringSync: Bool
    ) {
        let reason = Self.offerCodeFailureReason(
            for: error,
            occurredDuringSync: occurredDuringSync
        )
        errorMessage = Self.offerCodeMessage(for: reason)
        analytics?.track(.offerCodeRedemptionFailed(source: source, reason: reason))
    }

    // MARK: - Offerings

    /// Loads the current offering: the packages the dashboard is serving to this
    /// specific user, including whatever an active experiment assigns them.
    func loadOffering() async {
        _ = await loadCurrentOffering()
    }

    /// Resolves the remote paywall choice from the same Offering used by the
    /// native paywall. Called for every presentation so RevenueCat's normal
    /// cache/refresh policy can pick up metadata changes without an app release.
    func resolvePaywallRoute() async -> PaywallRoute {
        guard let offering = await loadCurrentOffering() else { return .native }
        let remoteValue: String? = offering.getMetadataValue(for: PaywallMode.metadataKey)
        let mode = PaywallMode.resolve(
            metadataValue: remoteValue,
            revenueCatPaywallAvailable: offering.hasPaywall
        )
        return mode == .revenueCat ? .revenueCat(offering) : .native
    }

    /// Fetches and publishes one current Offering for both routing and native
    /// rendering, avoiding a second Offerings request after the route resolves.
    private func loadCurrentOffering() async -> Offering? {
        guard entitlementOverride == nil, Purchases.isConfigured else {
            // Previews and UI tests pin the entitlement and never configure the
            // SDK. Serving them a fixed offering is what makes the paywall's
            // layout renderable and assertable at all — without it the screen
            // could only ever show its unavailable state. A shipped launch
            // never takes this branch, because it has no pinned entitlement.
            guard entitlementOverride != nil else {
                offeringState = .unavailable("Purchases aren't available in this build.")
                introEligibilityByProductID = [:]
                return nil
            }

            let fixture = PaywallFixture.offering()
            offeringState = .loaded(fixture)
            introEligibilityByProductID = fixture.availablePackages.reduce(into: [:]) {
                if $1.storeProduct.introductoryDiscount != nil {
                    $0[$1.storeProduct.productIdentifier] = .eligible
                }
            }
            return fixture
        }

        offeringState = .loading

        do {
            let offerings = try await Purchases.shared.offerings()

            guard let current = offerings.current else {
                offeringState = .unavailable(
                    "No current offering is configured. Set one in RevenueCat → Offerings."
                )
                introEligibilityByProductID = [:]
                return nil
            }

            guard !current.availablePackages.isEmpty else {
                offeringState = .unavailable(
                    "The current offering has no packages attached."
                )
                introEligibilityByProductID = [:]
                return nil
            }

            offeringState = .loaded(current)
            await loadIntroEligibility(for: current)
            return current
        } catch {
            offeringState = .unavailable(Self.message(for: error))
            introEligibilityByProductID = [:]
            return nil
        }
    }

    private func loadIntroEligibility(for offering: Offering) async {
        let productIDs = offering.availablePackages.compactMap { package in
            package.storeProduct.introductoryDiscount == nil
                ? nil
                : package.storeProduct.productIdentifier
        }
        guard !productIDs.isEmpty else {
            introEligibilityByProductID = [:]
            return
        }

        let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(
            productIdentifiers: productIDs
        )
        introEligibilityByProductID = eligibility.mapValues(\.status)
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
        feature: ProFeature? = nil,
        paywallSource: PaywallSource = .native,
        purchaseKind: AnalyticsPurchaseKind = .paid
    ) async -> Bool {
        // Also the duplicate-tap guard: a second call while one is in flight
        // returns without starting anything or emitting a second event.
        guard isSDKAvailable, !isPurchasing else { return false }

        isPurchasing = true
        defer { isPurchasing = false }
        analytics?.track(.purchaseStarted(
            plan: plan,
            feature: feature,
            source: paywallSource,
            kind: purchaseKind
        ))

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
                analytics?.track(.purchaseCancelled(
                    plan: plan,
                    feature: feature,
                    source: paywallSource,
                    kind: purchaseKind
                ))
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
                    .purchaseFailed(
                        plan: plan,
                        feature: feature,
                        source: paywallSource,
                        kind: purchaseKind,
                        reason: .entitlementNotActive
                    )
                )
                return false
            }

            let completedKind = Self.completedPurchaseKind(
                customerInfo: result.customerInfo,
                fallback: purchaseKind
            )
            if completedKind == .introductoryTrial {
                analytics?.track(.trialStarted(plan: plan, feature: feature, source: paywallSource))
            }
            analytics?.track(.purchaseCompleted(
                plan: plan,
                feature: feature,
                source: paywallSource,
                kind: completedKind
            ))
            return true
        } catch {
            if Self.isCancellation(error) {
                analytics?.track(.purchaseCancelled(
                    plan: plan,
                    feature: feature,
                    source: paywallSource,
                    kind: purchaseKind
                ))
                return false
            }
            errorMessage = Self.message(for: error)
            analytics?.track(
                .purchaseFailed(
                    plan: plan,
                    feature: feature,
                    source: paywallSource,
                    kind: purchaseKind,
                    reason: Self.failureReason(for: error)
                )
            )
            return false
        }
    }

    /// Restores purchases tied to the current App Store account.
    ///
    /// Apple requires a visible restore control anywhere a subscription is sold,
    /// which is why this is wired to an explicit button rather than run on launch.
    @discardableResult
    func restorePurchases(
        from source: RestoreSource = .settings,
        paywallSource: PaywallSource? = nil
    ) async -> Bool {
        guard isSDKAvailable, !isRestoring else { return false }

        isRestoring = true
        defer { isRestoring = false }
        analytics?.track(.restoreStarted(source: source, paywallSource: paywallSource))

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
                    paywallSource: paywallSource,
                    outcome: isPro ? .entitlementRestored : .nothingToRestore
                )
            )
            return isPro
        } catch {
            errorMessage = Self.message(for: error)
            analytics?.track(.restoreCompleted(
                source: source,
                paywallSource: paywallSource,
                outcome: .failed
            ))
            return false
        }
    }

    // MARK: - RevenueCatUI callbacks

    func revenueCatPaywallPurchaseStarted(package: Package, feature: ProFeature?) {
        let context = purchaseAnalyticsContext(for: package)
        analytics?.track(.purchaseStarted(
            plan: context.plan,
            feature: feature,
            source: .revenueCat,
            kind: context.kind
        ))
    }

    func revenueCatPaywallPurchaseCompleted(
        package: Package?,
        customerInfo: CustomerInfo,
        feature: ProFeature?
    ) {
        self.customerInfo = customerInfo
        let context = package.map(purchaseAnalyticsContext(for:)) ?? (.other, .paid)

        guard isPro else {
            analytics?.track(.purchaseFailed(
                plan: context.plan,
                feature: feature,
                source: .revenueCat,
                kind: context.kind,
                reason: .entitlementNotActive
            ))
            return
        }

        let completedKind = Self.completedPurchaseKind(
            customerInfo: customerInfo,
            fallback: context.kind
        )
        if completedKind == .introductoryTrial {
            analytics?.track(.trialStarted(plan: context.plan, feature: feature, source: .revenueCat))
        }
        analytics?.track(.purchaseCompleted(
            plan: context.plan,
            feature: feature,
            source: .revenueCat,
            kind: completedKind
        ))
    }

    func revenueCatPaywallPurchaseCancelled(package: Package?, feature: ProFeature?) {
        let context = package.map(purchaseAnalyticsContext(for:)) ?? (.other, .paid)
        analytics?.track(.purchaseCancelled(
            plan: context.plan,
            feature: feature,
            source: .revenueCat,
            kind: context.kind
        ))
    }

    func revenueCatPaywallPurchaseFailed(
        package: Package?,
        feature: ProFeature?,
        error: Error
    ) {
        let context = package.map(purchaseAnalyticsContext(for:)) ?? (.other, .paid)
        errorMessage = Self.message(for: error)
        analytics?.track(.purchaseFailed(
            plan: context.plan,
            feature: feature,
            source: .revenueCat,
            kind: context.kind,
            reason: Self.failureReason(for: error)
        ))
    }

    func revenueCatPaywallRestoreStarted() {
        analytics?.track(.restoreStarted(source: .paywall, paywallSource: .revenueCat))
    }

    func revenueCatPaywallRestoreCompleted(customerInfo: CustomerInfo) {
        self.customerInfo = customerInfo
        analytics?.track(.restoreCompleted(
            source: .paywall,
            paywallSource: .revenueCat,
            outcome: isPro ? .entitlementRestored : .nothingToRestore
        ))
    }

    func revenueCatPaywallRestoreFailed(error: Error) {
        errorMessage = Self.message(for: error)
        analytics?.track(.restoreCompleted(
            source: .paywall,
            paywallSource: .revenueCat,
            outcome: .failed
        ))
    }

    private func purchaseAnalyticsContext(
        for package: Package
    ) -> (plan: AnalyticsPlan, kind: AnalyticsPurchaseKind) {
        let plan: AnalyticsPlan = switch package.packageType {
        case .annual: .yearly
        case .monthly: .monthly
        default: .other
        }
        let hasEligibleTrial = PlanOption.eligibleFreeTrial(
            for: package,
            plan: plan,
            eligibility: introEligibilityByProductID[package.storeProduct.productIdentifier]
        ) != nil
        return (plan, hasEligibleTrial ? .introductoryTrial : .paid)
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

    private struct OfferCodeEntitlementSnapshot: Equatable {
        let isActive: Bool
        let productIdentifier: String?
        let latestPurchaseDate: Date?
        let expirationDate: Date?
    }

    private var currentOfferCodeEntitlementSnapshot: OfferCodeEntitlementSnapshot {
        let entitlement = proEntitlement
        return OfferCodeEntitlementSnapshot(
            isActive: isPro,
            productIdentifier: entitlement?.productIdentifier,
            latestPurchaseDate: entitlement?.latestPurchaseDate,
            expirationDate: entitlement?.expirationDate
        )
    }

    static func isOfferCodeCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == SKErrorDomain else { return false }
        return nsError.code == SKError.Code.paymentCancelled.rawValue
            || nsError.code == SKError.Code.overlayCancelled.rawValue
    }

    static func offerCodeFailureReason(
        for error: Error,
        occurredDuringSync: Bool
    ) -> OfferCodeRedemptionFailureReason {
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain {
            return .network
        }

        if nsError.domain == ErrorCode.errorDomain {
            switch failureReason(for: error) {
            case .network: return .network
            case .notAllowed: return .notAllowed
            case .productUnavailable: return .storeUnavailable
            case .configuration: return .syncFailed
            default: return occurredDuringSync ? .syncFailed : .unknown
            }
        }

        guard nsError.domain == SKErrorDomain,
              let code = SKError.Code(rawValue: nsError.code) else {
            return occurredDuringSync ? .syncFailed : .unknown
        }

        switch code {
        case .cloudServiceNetworkConnectionFailed:
            return .network
        case .clientInvalid, .paymentNotAllowed, .privacyAcknowledgementRequired:
            return .notAllowed
        case .invalidOfferIdentifier, .invalidOfferPrice, .ineligibleForOffer,
             .paymentInvalid, .missingOfferParams, .invalidSignature:
            return .invalidOrIneligible
        case .storeProductNotAvailable, .unsupportedPlatform,
             .overlayInvalidConfiguration, .overlayPresentedInBackgroundScene:
            return .storeUnavailable
        default:
            return occurredDuringSync ? .syncFailed : .unknown
        }
    }

    private static func offerCodeMessage(
        for reason: OfferCodeRedemptionFailureReason
    ) -> String {
        switch reason {
        case .network, .syncFailed:
            return "We couldn't refresh your subscription. Check your connection and try again."
        case .notAllowed:
            return "Offer code redemption isn't available for this Apple Account or device."
        case .invalidOrIneligible:
            return "The App Store couldn't redeem that offer. Check the code and its eligibility."
        case .storeUnavailable:
            return "Offer code redemption isn't available right now. Please try again later."
        case .unknown:
            return "The offer code couldn't be redeemed. Please try again."
        }
    }

    private static func completedPurchaseKind(
        customerInfo: CustomerInfo?,
        fallback: AnalyticsPurchaseKind
    ) -> AnalyticsPurchaseKind {
        guard let entitlement = customerInfo?.entitlements[RevenueCatConfig.proEntitlementID] else {
            return fallback
        }
        return entitlement.periodType == .trial ? .introductoryTrial : .paid
    }
}
