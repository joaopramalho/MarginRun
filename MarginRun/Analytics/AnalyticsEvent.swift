import Foundation

// MARK: - Event dimensions
//
// Every associated value below is a closed enum or a flag. That is the whole
// privacy design: there is no `String` payload a caller could accidentally fill
// with a job name, a customer, a vendor, an address or a note, and no `Decimal`
// they could fill with a contract value. What leaves the app is behaviour.

/// Where a job was created from. Answers whether onboarding actually produces
/// first jobs or whether people find their way to History on their own.
nonisolated enum JobCreationSource: String, Sendable {
    case onboarding
    case history
    case historyEmptyState = "history_empty_state"
    case dashboardEmptyState = "dashboard_empty_state"
    case timerPickerEmptyState = "timer_picker_empty_state"
}

/// How labor reached the job.
nonisolated enum LaborEntrySource: String, Sendable {
    case manual
    case timer
}

/// Where an expense creation flow was opened.
nonisolated enum ExpenseCreationSource: String, Sendable {
    case jobDetailQuickExpense = "job_detail_quick_expense"
    case jobCreationFollowUp = "job_creation_follow_up"
}

/// Where the labor timer was started from.
nonisolated enum LaborTimerSource: String, Sendable {
    case jobDetail = "job_detail"
    case timerTab = "timer_tab"
}

/// What caused a Labor Timer Live Activity to be requested.
///
/// `reconciliation` is the app noticing on foreground that a timer is running
/// with nothing on the Lock Screen to show for it — usually because Live
/// Activities were switched on after the timer started.
nonisolated enum LiveActivitySource: String, Sendable {
    case timerStart = "timer_start"
    case reconciliation
}

/// Why no Live Activity is on screen for a running timer. Never an error the
/// customer sees: the timer runs either way, so this exists purely to say how
/// often the presentation is missing and why.
nonisolated enum LiveActivityUnavailableReason: String, Sendable {
    /// The system reports Live Activities off — disabled in Settings, or a
    /// device that does not offer them.
    case notEnabled = "not_enabled"
    /// ActivityKit accepted the call and then refused it, typically because
    /// the app was not foreground or the per-app activity budget was spent.
    case requestFailed = "request_failed"
}

/// Why a Labor Timer Live Activity was taken down.
nonisolated enum LiveActivityEndReason: String, Sendable {
    /// The customer stopped the timer. Ending here, rather than at save, is
    /// what keeps a stopped timer from counting on for the length of a review.
    case timerStopped = "timer_stopped"
    /// The timer was thrown away, running or under review.
    case timerDiscarded = "timer_discarded"
    /// Found on foreground with no timer behind it.
    case orphanReconciled = "orphan_reconciled"
    /// A second activity for a timer that already had one.
    case staleDuplicate = "stale_duplicate"
}

/// How the customer arrived back in the app. Only one route exists today, and
/// naming it keeps the property stable if another is ever added.
nonisolated enum LiveActivityOpenSource: String, Sendable {
    case liveActivity = "live_activity"
}

/// Where a receipt photo came from.
nonisolated enum ReceiptSource: String, Sendable {
    case camera
    case library
}

nonisolated enum ReceiptOCROutcome: String, Sendable {
    case extracted
    case nothingFound = "nothing_found"
    case failed
}

/// Which subscription product was in play, never its price.
nonisolated enum AnalyticsPlan: String, Sendable {
    case yearly
    case monthly
    case other
}

/// Which implementation displayed a subscription offer.
nonisolated enum PaywallSource: String, Sendable {
    case native
    case revenueCat = "revenuecat"
}

/// Whether subscribing begins with Apple's introductory free trial.
nonisolated enum AnalyticsPurchaseKind: String, Sendable {
    case paid
    case introductoryTrial = "introductory_trial"
}

/// Which control offered the restore. Restore is tracked apart from purchase
/// everywhere, so a reinstall never reads as a new subscription.
nonisolated enum RestoreSource: String, Sendable {
    case paywall
    case proGate = "pro_gate"
    case settings
}

nonisolated enum RestoreOutcome: String, Sendable {
    /// RevenueCat confirmed an active entitlement.
    case entitlementRestored = "entitlement_restored"
    /// The call succeeded but the account owns nothing.
    case nothingToRestore = "nothing_to_restore"
    case failed
}

/// Where Apple's offer-code redemption sheet was opened.
nonisolated enum OfferCodeRedemptionSource: String, Sendable {
    case settings
    case nativePaywall = "native_paywall"
}

/// Safe, low-cardinality reasons for a redemption or entitlement-sync failure.
/// The offer code and Apple Account details are never available to analytics.
nonisolated enum OfferCodeRedemptionFailureReason: String, Sendable {
    case network
    case notAllowed = "not_allowed"
    case invalidOrIneligible = "invalid_or_ineligible"
    case storeUnavailable = "store_unavailable"
    case syncFailed = "sync_failed"
    case unknown
}

/// A purchase failure, reduced to a handful of actionable causes. A user
/// cancelling the Apple sheet is *not* one of them — that is `purchase_cancelled`.
nonisolated enum PurchaseFailureReason: String, Sendable {
    case network
    case notAllowed = "not_allowed"
    case alreadyPurchased = "already_purchased"
    case pending
    case productUnavailable = "product_unavailable"
    case configuration
    /// The purchase reported success but RevenueCat still shows no entitlement.
    /// Never counted as a completed purchase.
    case entitlementNotActive = "entitlement_not_active"
    case unknown
}

/// Which onboarding screen the customer bailed out on.
nonisolated enum OnboardingStep: String, Sendable, CaseIterable {
    case value
    case business
    case defaults
}

// MARK: - Events

/// Every product milestone MarginRun reports.
///
/// Typed rather than free-form strings so a call site cannot invent an event
/// name, misspell a property, or attach something private. The funnel this
/// covers, in order: install → onboarding → first job → first recorded cost →
/// job completed → paywall → purchase.
nonisolated enum AnalyticsEvent: Equatable, Sendable {

    // Install and onboarding
    case appFirstOpen
    case onboardingStarted
    case onboardingCompleted(
        setBusinessName: Bool,
        setTrade: Bool,
        setHourlyCost: Bool,
        changedTargetMargin: Bool
    )
    case onboardingSkipped(step: OnboardingStep)

    // Activation
    case jobCreated(source: JobCreationSource, hasCostEstimate: Bool, meetsTargetMargin: Bool)
    case quickExpenseOpened
    case expenseAdded(category: ExpenseCategory, hasReceipt: Bool, source: ExpenseCreationSource)
    case laborAdded(source: LaborEntrySource)
    case receiptAttached(source: ReceiptSource)
    case receiptOCRStarted
    case receiptOCRCompleted(outcome: ReceiptOCROutcome, fieldsExtracted: Int)
    case laborTimerStarted(source: LaborTimerSource)
    case laborTimerCompleted(durationBucket: String)
    case laborLiveActivityStarted(source: LiveActivitySource)
    case laborLiveActivityUnavailable(reason: LiveActivityUnavailableReason)
    case laborLiveActivityOpened(source: LiveActivityOpenSource)
    case laborLiveActivityEnded(reason: LiveActivityEndReason)
    case jobEdited(changedContractValue: Bool, changedEstimate: Bool)
    case jobDeleted(status: JobStatus, hadCosts: Bool)
    case jobReopened
    case jobCompleted(metTargetMargin: Bool, beatExpectedProfit: Bool)
    case insightsOpened

    // Monetization
    case paywallViewed(feature: ProFeature?, source: PaywallSource)
    case paywallPlanSelected(plan: AnalyticsPlan, feature: ProFeature?, source: PaywallSource)
    case purchaseStarted(
        plan: AnalyticsPlan,
        feature: ProFeature?,
        source: PaywallSource,
        kind: AnalyticsPurchaseKind
    )
    case trialStarted(plan: AnalyticsPlan, feature: ProFeature?, source: PaywallSource)
    case purchaseCompleted(
        plan: AnalyticsPlan,
        feature: ProFeature?,
        source: PaywallSource,
        kind: AnalyticsPurchaseKind
    )
    case purchaseCancelled(
        plan: AnalyticsPlan,
        feature: ProFeature?,
        source: PaywallSource,
        kind: AnalyticsPurchaseKind
    )
    case purchaseFailed(
        plan: AnalyticsPlan,
        feature: ProFeature?,
        source: PaywallSource,
        kind: AnalyticsPurchaseKind,
        reason: PurchaseFailureReason
    )
    case restoreStarted(source: RestoreSource, paywallSource: PaywallSource?)
    case restoreCompleted(source: RestoreSource, paywallSource: PaywallSource?, outcome: RestoreOutcome)
    case offerCodeRedemptionOpened(source: OfferCodeRedemptionSource)
    case offerCodeRedemptionSucceeded(source: OfferCodeRedemptionSource)
    case offerCodeRedemptionFailed(
        source: OfferCodeRedemptionSource,
        reason: OfferCodeRedemptionFailureReason
    )
    case proFeatureAttempted(feature: ProFeature)

    /// The wire name. Snake case, stable, and never assembled at a call site.
    var name: String {
        switch self {
        case .appFirstOpen: "app_first_open"
        case .onboardingStarted: "onboarding_started"
        case .onboardingCompleted: "onboarding_completed"
        case .onboardingSkipped: "onboarding_skipped"
        case .jobCreated: "job_created"
        case .quickExpenseOpened: "quick_expense_opened"
        case .expenseAdded: "expense_added"
        case .laborAdded: "labor_added"
        case .receiptAttached: "receipt_attached"
        case .receiptOCRStarted: "receipt_ocr_started"
        case .receiptOCRCompleted: "receipt_ocr_completed"
        case .laborTimerStarted: "labor_timer_started"
        case .laborTimerCompleted: "labor_timer_completed"
        case .laborLiveActivityStarted: "labor_live_activity_started"
        case .laborLiveActivityUnavailable: "labor_live_activity_unavailable"
        case .laborLiveActivityOpened: "labor_live_activity_opened"
        case .laborLiveActivityEnded: "labor_live_activity_ended"
        case .jobEdited: "job_edited"
        case .jobDeleted: "job_deleted"
        case .jobReopened: "job_reopened"
        case .jobCompleted: "job_completed"
        case .insightsOpened: "insights_opened"
        case .paywallViewed: "paywall_viewed"
        case .paywallPlanSelected: "plan_selected"
        case .purchaseStarted: "purchase_started"
        case .trialStarted: "trial_started"
        case .purchaseCompleted: "purchase_completed"
        case .purchaseCancelled: "purchase_cancelled"
        case .purchaseFailed: "purchase_failed"
        case .restoreStarted: "restore_started"
        case .restoreCompleted: "restore_completed"
        case .offerCodeRedemptionOpened: "offer_code_redemption_opened"
        case .offerCodeRedemptionSucceeded: "offer_code_redemption_succeeded"
        case .offerCodeRedemptionFailed: "offer_code_redemption_failed"
        case .proFeatureAttempted: "pro_feature_attempted"
        }
    }

    /// The once-per-install companion this event also satisfies.
    ///
    /// `job_created` fires every time; the very first one *also* emits
    /// `first_job_created`. Declaring the pairing here means a call site logs
    /// one thing and cannot forget the milestone, and ``AnalyticsService`` owns
    /// the "has this happened before" bookkeeping.
    var firstTimeName: String? {
        switch self {
        case .jobCreated: "first_job_created"
        case .expenseAdded: "first_expense_added"
        case .laborAdded: "first_labor_added"
        case .receiptAttached: "first_receipt_attached"
        default: nil
        }
    }

    /// Properties specific to this event. Ambient ones — `is_pro`, job counts,
    /// install age — are added by ``AnalyticsService``.
    var properties: [String: AnalyticsValue] {
        switch self {
        case .appFirstOpen, .onboardingStarted, .receiptOCRStarted, .insightsOpened,
             .jobReopened, .quickExpenseOpened:
            return [:]

        case let .onboardingCompleted(setBusinessName, setTrade, setHourlyCost, changedTargetMargin):
            return [
                "set_business_name": .bool(setBusinessName),
                "set_trade": .bool(setTrade),
                "set_hourly_cost": .bool(setHourlyCost),
                "changed_target_margin": .bool(changedTargetMargin),
            ]

        case let .onboardingSkipped(step):
            return ["step": .string(step.rawValue)]

        case let .jobCreated(source, hasCostEstimate, meetsTargetMargin):
            return [
                "source": .string(source.rawValue),
                "has_cost_estimate": .bool(hasCostEstimate),
                "meets_target_margin": .bool(meetsTargetMargin),
            ]

        case let .expenseAdded(category, hasReceipt, source):
            return [
                "category": .string(category.rawValue),
                "has_receipt": .bool(hasReceipt),
                "source": .string(source.rawValue),
            ]

        case let .laborAdded(source):
            return ["source": .string(source.rawValue)]

        case let .receiptAttached(source):
            return ["source": .string(source.rawValue)]

        case let .receiptOCRCompleted(outcome, fieldsExtracted):
            return [
                "outcome": .string(outcome.rawValue),
                "fields_extracted": .int(fieldsExtracted),
            ]

        case let .laborTimerStarted(source):
            return ["source": .string(source.rawValue)]

        case let .laborTimerCompleted(durationBucket):
            return ["duration_bucket": .string(durationBucket)]

        case let .laborLiveActivityStarted(source):
            return ["source": .string(source.rawValue)]

        case let .laborLiveActivityUnavailable(reason):
            return ["availability_reason": .string(reason.rawValue)]

        case let .laborLiveActivityOpened(source):
            return ["source": .string(source.rawValue)]

        case let .laborLiveActivityEnded(reason):
            return ["availability_reason": .string(reason.rawValue)]

        case let .jobEdited(changedContractValue, changedEstimate):
            return [
                "changed_contract_value": .bool(changedContractValue),
                "changed_estimate": .bool(changedEstimate),
            ]

        case let .jobDeleted(status, hadCosts):
            return [
                "status": .string(status.rawValue),
                "had_costs": .bool(hadCosts),
            ]

        case let .jobCompleted(metTargetMargin, beatExpectedProfit):
            return [
                "met_target_margin": .bool(metTargetMargin),
                "beat_expected_profit": .bool(beatExpectedProfit),
            ]

        case let .paywallViewed(feature, source):
            return Self.paywallProperties(plan: nil, feature: feature, source: source, kind: nil)

        case let .paywallPlanSelected(plan, feature, source):
            return Self.paywallProperties(plan: plan, feature: feature, source: source, kind: nil)

        case let .purchaseStarted(plan, feature, source, kind),
             let .purchaseCompleted(plan, feature, source, kind),
             let .purchaseCancelled(plan, feature, source, kind):
            return Self.paywallProperties(plan: plan, feature: feature, source: source, kind: kind)

        case let .trialStarted(plan, feature, source):
            return Self.paywallProperties(
                plan: plan,
                feature: feature,
                source: source,
                kind: .introductoryTrial
            )

        case let .purchaseFailed(plan, feature, source, kind, reason):
            return Self.paywallProperties(plan: plan, feature: feature, source: source, kind: kind)
                .merging(["reason": .string(reason.rawValue)]) { current, _ in current }

        case let .restoreStarted(source, paywallSource):
            return Self.restoreProperties(source: source, paywallSource: paywallSource)

        case let .restoreCompleted(source, paywallSource, outcome):
            return Self.restoreProperties(source: source, paywallSource: paywallSource)
                .merging(["outcome": .string(outcome.rawValue)]) { current, _ in current }

        case let .offerCodeRedemptionOpened(source),
             let .offerCodeRedemptionSucceeded(source):
            return ["source": .string(source.rawValue)]

        case let .offerCodeRedemptionFailed(source, reason):
            return [
                "source": .string(source.rawValue),
                "reason": .string(reason.rawValue),
            ]

        case let .proFeatureAttempted(feature):
            return ["feature": .string(feature.analyticsName)]
        }
    }

    /// The `paywall_context` vocabulary. Knowing *which* capability drives
    /// purchase intent is the whole reason the paywall is contextual, so this
    /// is the one property the monetization funnel cannot lose.
    static func context(for feature: ProFeature?) -> String {
        feature?.analyticsName ?? "general"
    }

    private static func paywallProperties(
        plan: AnalyticsPlan?,
        feature: ProFeature?,
        source: PaywallSource,
        kind: AnalyticsPurchaseKind?
    ) -> [String: AnalyticsValue] {
        var properties: [String: AnalyticsValue] = [
            "paywall_context": .string(context(for: feature)),
            "paywall_source": .string(source.rawValue),
        ]
        if let plan { properties["plan"] = .string(plan.rawValue) }
        if let kind { properties["purchase_kind"] = .string(kind.rawValue) }
        return properties
    }

    private static func restoreProperties(
        source: RestoreSource,
        paywallSource: PaywallSource?
    ) -> [String: AnalyticsValue] {
        var properties: [String: AnalyticsValue] = ["source": .string(source.rawValue)]
        if let paywallSource { properties["paywall_source"] = .string(paywallSource.rawValue) }
        return properties
    }
}

extension ProFeature {
    /// Snake-cased for the wire. Separate from `rawValue` so renaming a Swift
    /// case can never silently rewrite historical event data.
    nonisolated var analyticsName: String {
        switch self {
        case .unlimitedJobs: "unlimited_jobs"
        case .receiptScan: "receipt_scan"
        case .laborTimer: "labor_timer"
        case .insights: "insights"
        case .marginAlerts: "margin_alerts"
        case .extraRevenue: "extra_revenue"
        }
    }
}
