import Foundation
import Testing
@testable import MarginRun

/// The funnel is only worth having if `first_job_created` really means the
/// first one and `purchase_completed` really means money. Both are enforced
/// here rather than in a dashboard query written six months from now.
@MainActor
struct AnalyticsServiceTests {

    private struct Harness {
        let service: AnalyticsService
        let backend: RecordingAnalyticsBackend
        let defaults: UserDefaults
        let suiteName: String

        func tearDown() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeHarness(
        context: AnalyticsContext = .empty,
        now: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) throws -> Harness {
        let suiteName = "AnalyticsServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let backend = RecordingAnalyticsBackend()
        let service = AnalyticsService(
            backend: backend,
            milestones: AnalyticsMilestones(defaults: defaults),
            now: { now }
        )
        service.context = context
        return Harness(
            service: service,
            backend: backend,
            defaults: defaults,
            suiteName: suiteName
        )
    }

    // MARK: - Milestones

    @Test func theFirstJobEmitsBothTheMilestoneAndTheRecurringEvent() throws {
        let harness = try makeHarness()
        defer { harness.tearDown() }

        harness.service.track(
            .jobCreated(
                source: .onboarding,
                hasCostEstimate: true,
                meetsTargetMargin: true,
                value: JobValueAnalytics(value: 18_000, currency: "USD")
            )
        )

        #expect(harness.backend.recordedNames == ["first_job_created", "job_created"])
    }

    @Test func laterJobsEmitOnlyTheRecurringEvent() throws {
        let harness = try makeHarness()
        defer { harness.tearDown() }

        let event = AnalyticsEvent.jobCreated(
            source: .history,
            hasCostEstimate: false,
            meetsTargetMargin: false,
            value: JobValueAnalytics(value: 900, currency: "BRL")
        )
        harness.service.track(event)
        harness.service.track(event)
        harness.service.track(event)

        #expect(
            harness.backend.recordedNames == [
                "first_job_created", "job_created", "job_created", "job_created",
            ]
        )
    }

    @Test func milestonesSurviveARestart() throws {
        let harness = try makeHarness()
        defer { harness.tearDown() }

        harness.service.track(.expenseAdded(
            category: .materials,
            hasReceipt: false,
            source: .jobDetailQuickExpense
        ))

        // A second service over the same storage stands in for a relaunch.
        let relaunched = AnalyticsService(
            backend: harness.backend,
            milestones: AnalyticsMilestones(defaults: harness.defaults)
        )
        relaunched.track(.expenseAdded(
            category: .labor,
            hasReceipt: true,
            source: .jobCreationFollowUp
        ))

        #expect(harness.backend.recordedNames.filter { $0 == "first_expense_added" }.count == 1)
    }

    @Test func everyFirstTimeMilestoneHasItsOwnName() throws {
        let harness = try makeHarness()
        defer { harness.tearDown() }

        harness.service.track(
            .jobCreated(
                source: .history,
                hasCostEstimate: true,
                meetsTargetMargin: true,
                value: JobValueAnalytics(value: 18_000, currency: "USD")
            )
        )
        harness.service.track(.expenseAdded(
            category: .materials,
            hasReceipt: true,
            source: .jobDetailQuickExpense
        ))
        harness.service.track(.laborAdded(source: .timer))
        harness.service.track(.receiptAttached(source: .camera))

        let milestones = harness.backend.recordedNames.filter { $0.hasPrefix("first_") }
        #expect(
            milestones == [
                "first_job_created",
                "first_expense_added",
                "first_labor_added",
                "first_receipt_attached",
            ]
        )
    }

    @Test func appFirstOpenIsSentOncePerInstall() throws {
        let harness = try makeHarness()
        defer { harness.tearDown() }

        harness.service.trackAppOpen()
        harness.service.trackAppOpen()
        harness.service.trackAppOpen()

        #expect(harness.backend.recordedNames == ["app_first_open"])
    }

    // MARK: - Properties

    @Test func everyEventCarriesTheAmbientContext() throws {
        let harness = try makeHarness(
            context: AnalyticsContext(
                isPro: true,
                activeJobCount: 4,
                totalJobCount: 7,
                completedJobCount: 3,
                onboardingCompleted: true,
                trade: .remodeling
            )
        )
        defer { harness.tearDown() }

        harness.service.track(.insightsOpened)
        let properties = try #require(harness.backend.properties(for: "insights_opened"))

        #expect(properties["is_pro"] == .bool(true))
        #expect(properties["active_job_count"] == .int(4))
        #expect(properties["job_count_bucket"] == .string("6-10"))
        #expect(properties["completed_job_count_bucket"] == .string("3-5"))
        #expect(properties["onboarding_completed"] == .bool(true))
        #expect(properties["trade"] == .string(ContractorTrade.remodeling.rawValue))
    }

    @Test func installAgeIsReportedAsABucketOnceTheInstallIsStamped() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let suiteName = "AnalyticsServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let milestones = AnalyticsMilestones(defaults: defaults)
        milestones.markFirstOpenIfNeeded(now: start)

        let backend = RecordingAnalyticsBackend()
        let service = AnalyticsService(
            backend: backend,
            milestones: milestones,
            now: { start.addingTimeInterval(5 * 24 * 60 * 60) }
        )
        service.track(.insightsOpened)

        let properties = try #require(backend.properties(for: "insights_opened"))
        #expect(properties["days_since_first_open_bucket"] == .string("4-7"))
    }

    @Test func paywallEventsCarryTheFeatureThatRaisedThem() throws {
        let harness = try makeHarness()
        defer { harness.tearDown() }

        harness.service.track(.paywallViewed(feature: .laborTimer, source: .native))
        let properties = try #require(harness.backend.properties(for: "paywall_viewed"))

        #expect(properties["paywall_context"] == .string("labor_timer"))
        #expect(properties["paywall_source"] == .string("native"))
    }

    @Test func aPaywallWithNoFeatureContextIsReportedAsSettings() throws {
        let harness = try makeHarness()
        defer { harness.tearDown() }

        harness.service.track(.paywallViewed(feature: nil, source: .revenueCat))

        #expect(
            harness.backend.properties(for: "paywall_viewed")?["paywall_context"]
                == .string("settings")
        )
    }

    @Test func purchaseEventsReportThePlanWithoutItsPrice() throws {
        let harness = try makeHarness()
        defer { harness.tearDown() }

        harness.service.track(.purchaseCompleted(
            plan: .yearly,
            feature: .insights,
            source: .revenueCat,
            kind: .introductoryTrial
        ))
        let properties = try #require(harness.backend.properties(for: "purchase_completed"))

        #expect(properties["plan"] == .string("yearly"))
        #expect(properties["paywall_context"] == .string("insights"))
        #expect(properties["paywall_source"] == .string("revenuecat"))
        #expect(properties["purchase_kind"] == .string("introductory_trial"))
    }

    /// A restore is not a sale. If these ever collapsed into one event the
    /// conversion rate would silently include every reinstall.
    @Test func restoreIsReportedApartFromPurchase() throws {
        let harness = try makeHarness()
        defer { harness.tearDown() }

        harness.service.track(.restoreStarted(source: .paywall, paywallSource: .native))
        harness.service.track(
            .restoreCompleted(
                source: .paywall,
                paywallSource: .native,
                outcome: .entitlementRestored
            )
        )

        #expect(harness.backend.recordedNames == ["restore_started", "restore_completed"])
        #expect(harness.backend.recordedNames.contains("purchase_completed") == false)
    }

    // MARK: - Privacy

    /// The guardrail behind the whole design: no property may carry free-form
    /// user text. Anything that ever could is a bug, so it is asserted for
    /// every event rather than reviewed by eye.
    @Test func noEventCarriesUserEnteredContent() throws {
        let harness = try makeHarness()
        defer { harness.tearDown() }

        let forbidden = [
            "Chen Residence", "Kitchen remodel", "Home Depot",
            "Cabinets and hardware", "18437", "$18,437.00",
        ]

        for event in AnalyticsEventCatalog.everyEvent {
            harness.service.track(event)
        }

        for payload in harness.backend.recorded {
            for (key, value) in payload.properties {
                for secret in forbidden {
                    #expect(
                        value.description.localizedCaseInsensitiveContains(secret) == false,
                        "\(payload.name).\(key) leaked \(secret)"
                    )
                }
            }
        }
    }

    @Test func everyEventNameIsSnakeCase() {
        let names = AnalyticsEventCatalog.everyEvent
            .flatMap { [$0.name, $0.firstTimeName].compactMap { $0 } }

        for name in names {
            #expect(
                name.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" },
                "\(name) is not snake_case"
            )
        }
    }

    /// Pins the wire vocabulary. A renamed or newly added event has to be a
    /// deliberate edit here, because renaming one silently orphans every
    /// historical row already sent under the old name.
    @Test func theEventVocabularyIsExactlyWhatIsExpected() {
        let emitted = Set(
            AnalyticsEventCatalog.everyEvent
                .flatMap { [$0.name, $0.firstTimeName].compactMap { $0 } }
        )

        #expect(
            emitted == [
                "app_first_open",
                "onboarding_started", "onboarding_completed", "onboarding_skipped",
                "first_job_created", "job_created",
                "quick_expense_opened",
                "first_expense_added", "expense_added",
                "first_labor_added", "labor_added",
                "first_receipt_attached", "receipt_attached",
                "receipt_ocr_started", "receipt_ocr_completed",
                "labor_timer_started", "labor_timer_completed",
                "labor_live_activity_started", "labor_live_activity_unavailable",
                "labor_live_activity_opened", "labor_live_activity_ended",
                "job_completed", "insights_opened",
                "paywall_viewed", "plan_selected",
                "purchase_started", "trial_started", "purchase_completed",
                "purchase_cancelled", "purchase_failed",
                "restore_started", "restore_completed",
                "offer_code_redemption_opened", "offer_code_redemption_succeeded",
                "offer_code_redemption_failed",
                "pro_feature_attempted",
            ]
        )
    }

    @Test func theRequiredFunnelIsFullyInstrumented() {
        let instrumented = Set(
            AnalyticsEventCatalog.everyEvent.flatMap { [$0.name, $0.firstTimeName].compactMap { $0 } }
        )

        let required = [
            "app_first_open",
            "onboarding_started", "onboarding_completed", "onboarding_skipped",
            "first_job_created", "job_created",
            "quick_expense_opened",
            "first_expense_added", "expense_added",
            "first_labor_added", "labor_added",
            "first_receipt_attached", "receipt_attached",
            "receipt_ocr_started", "receipt_ocr_completed",
            "labor_timer_started", "labor_timer_completed",
            "labor_live_activity_started", "labor_live_activity_unavailable",
            "labor_live_activity_opened", "labor_live_activity_ended",
            "job_completed", "insights_opened",
            "paywall_viewed",
            "plan_selected",
            "purchase_started", "trial_started", "purchase_completed",
            "purchase_cancelled", "purchase_failed",
            "restore_started", "restore_completed",
            "offer_code_redemption_opened", "offer_code_redemption_succeeded",
            "offer_code_redemption_failed",
            "pro_feature_attempted",
        ]

        for name in required {
            #expect(instrumented.contains(name), "\(name) is not instrumented")
        }
    }

    /// Every contextual gate must be reportable, or we cannot answer which
    /// capability actually drives purchase intent.
    @Test func everyProFeatureHasAPaywallContext() {
        let contexts = ProFeature.allCases.map(\.analyticsName)

        #expect(Set(contexts).count == ProFeature.allCases.count)
        #expect(
            Set(contexts) == [
                "unlimited_jobs", "receipt_scan", "labor_timer",
                "insights", "margin_alerts", "extra_revenue",
            ]
        )
    }
}

// MARK: - Buckets

@MainActor
struct AnalyticsBucketTests {

    @Test func jobCountsAreBanded() {
        #expect(AnalyticsBucket.jobCount(0) == "0")
        #expect(AnalyticsBucket.jobCount(1) == "1")
        #expect(AnalyticsBucket.jobCount(2) == "2")
        #expect(AnalyticsBucket.jobCount(4) == "3-5")
        #expect(AnalyticsBucket.jobCount(9) == "6-10")
        #expect(AnalyticsBucket.jobCount(400) == "11+")
    }

    @Test func installAgeIsBanded() {
        #expect(AnalyticsBucket.daysSinceFirstOpen(0) == "0")
        #expect(AnalyticsBucket.daysSinceFirstOpen(3) == "2-3")
        #expect(AnalyticsBucket.daysSinceFirstOpen(9) == "8-30")
        #expect(AnalyticsBucket.daysSinceFirstOpen(365) == "31+")
    }

    /// Bucketed rather than exact, because an exact duration next to an hourly
    /// rate reconstructs a cost.
    @Test func laborDurationIsBanded() {
        #expect(AnalyticsBucket.laborDuration(hours: Decimal(string: "0.1")!) == "under-15m")
        #expect(AnalyticsBucket.laborDuration(hours: Decimal(string: "0.5")!) == "15-60m")
        #expect(AnalyticsBucket.laborDuration(hours: 2) == "1-4h")
        #expect(AnalyticsBucket.laborDuration(hours: 6) == "4-8h")
        #expect(AnalyticsBucket.laborDuration(hours: 12) == "8h+")
    }
}

/// One value of every event, so the privacy and naming rules above are checked
/// against the whole catalogue instead of a sample.
enum AnalyticsEventCatalog {
    static let everyEvent: [AnalyticsEvent] = {
        var events: [AnalyticsEvent] = [
            .appFirstOpen,
            .onboardingStarted,
            .onboardingCompleted(
                setBusinessName: true,
                setTrade: true,
                setHourlyCost: true,
                changedTargetMargin: true
            ),
            .receiptOCRStarted,
            .receiptOCRCompleted(outcome: .extracted, fieldsExtracted: 3),
            .laborTimerCompleted(durationBucket: "1-4h"),
            .jobCompleted(
                metTargetMargin: false,
                beatExpectedProfit: false,
                value: JobValueAnalytics(value: 21_400, currency: "USD")
            ),
            .insightsOpened,
            .paywallViewed(feature: nil, source: .native),
            .quickExpenseOpened,
            .offerCodeRedemptionOpened(source: .settings),
            .offerCodeRedemptionSucceeded(source: .nativePaywall),
            .offerCodeRedemptionFailed(source: .settings, reason: .network),
        ]

        events += OnboardingStep.allCases.map { AnalyticsEvent.onboardingSkipped(step: $0) }
        events += ExpenseCategory.allCases.map {
            AnalyticsEvent.expenseAdded(
                category: $0,
                hasReceipt: true,
                source: .jobDetailQuickExpense
            )
        }
        events += [JobCreationSource.onboarding, .history, .historyEmptyState].map {
            AnalyticsEvent.jobCreated(
                source: $0,
                hasCostEstimate: true,
                meetsTargetMargin: true,
                value: JobValueAnalytics(value: 18_437, currency: "USD")
            )
        }
        events += [LaborEntrySource.manual, .timer].map { AnalyticsEvent.laborAdded(source: $0) }
        events += [ReceiptSource.camera, .library].map {
            AnalyticsEvent.receiptAttached(source: $0)
        }
        events += [LaborTimerSource.jobDetail, .timerTab].map {
            AnalyticsEvent.laborTimerStarted(source: $0)
        }
        events += [LiveActivitySource.timerStart, .reconciliation].map {
            AnalyticsEvent.laborLiveActivityStarted(source: $0)
        }
        events += [LiveActivityUnavailableReason.notEnabled, .requestFailed].map {
            AnalyticsEvent.laborLiveActivityUnavailable(reason: $0)
        }
        events += [LiveActivityOpenSource.liveActivity].map {
            AnalyticsEvent.laborLiveActivityOpened(source: $0)
        }
        events += [
            LiveActivityEndReason.timerStopped, .timerDiscarded,
            .orphanReconciled, .staleDuplicate,
        ].map { AnalyticsEvent.laborLiveActivityEnded(reason: $0) }
        events += ProFeature.allCases.map { AnalyticsEvent.proFeatureAttempted(feature: $0) }
        events += ProFeature.allCases.flatMap { feature -> [AnalyticsEvent] in
            [
                .paywallViewed(feature: feature, source: .native),
                .paywallPlanSelected(plan: .yearly, feature: feature, source: .native),
                .purchaseStarted(
                    plan: .monthly,
                    feature: feature,
                    source: .native,
                    kind: .paid
                ),
                .trialStarted(plan: .yearly, feature: feature, source: .revenueCat),
                .purchaseCompleted(
                    plan: .yearly,
                    feature: feature,
                    source: .revenueCat,
                    kind: .introductoryTrial
                ),
                .purchaseCancelled(
                    plan: .other,
                    feature: feature,
                    source: .native,
                    kind: .paid
                ),
                .purchaseFailed(
                    plan: .other,
                    feature: feature,
                    source: .native,
                    kind: .paid,
                    reason: .network
                ),
            ]
        }
        events += [RestoreSource.paywall, .proGate, .settings].flatMap { source -> [AnalyticsEvent] in
            [
                .restoreStarted(source: source, paywallSource: .native),
                .restoreCompleted(
                    source: source,
                    paywallSource: .native,
                    outcome: .entitlementRestored
                ),
                .restoreCompleted(
                    source: source,
                    paywallSource: .revenueCat,
                    outcome: .nothingToRestore
                ),
                .restoreCompleted(source: source, paywallSource: nil, outcome: .failed),
            ]
        }

        return events
    }()
}

/// The Info.plist wiring PostHog depends on.
///
/// Regression: the credentials were supplied through `INFOPLIST_KEY_POSTHOG_*`
/// build settings, which resolve correctly in `-showBuildSettings` and are then
/// dropped from the bundle — Xcode only writes Info.plist keys it has its own
/// definition for. Nothing failed: `makeBackend` simply fell back to the no-op
/// and the app shipped with analytics silently off.
@MainActor
struct PostHogConfigurationTests {

    @Test func credentialsInTheBundleProduceARealBackend() {
        let values = PostHogConfiguration.values(
            infoDictionary: [
                PostHogConfiguration.apiKeyName: "phc_example",
                PostHogConfiguration.hostName: "https://us.i.posthog.com",
            ],
            environment: [:]
        )

        #expect(values?.apiKey == "phc_example")
        #expect(values?.host.absoluteString == "https://us.i.posthog.com")
    }

    /// The exact shape of the bug: the key is absent because the build setting
    /// never reached the bundle.
    @Test func aMissingKeyLeavesNoBackend() {
        #expect(
            PostHogConfiguration.values(
                infoDictionary: [PostHogConfiguration.hostName: "https://us.i.posthog.com"],
                environment: [:]
            ) == nil
        )
    }

    /// The near miss: an explicit Info.plist entry whose `$(...)` reference did
    /// not expand would otherwise be sent to PostHog as a literal project token.
    @Test func anUnexpandedBuildSettingIsNotTreatedAsACredential() {
        #expect(
            PostHogConfiguration.values(
                infoDictionary: [
                    PostHogConfiguration.apiKeyName: "$(POSTHOG_API_KEY)",
                    PostHogConfiguration.hostName: "$(POSTHOG_HOST)",
                ],
                environment: [:]
            ) == nil
        )
    }

    @Test func aMalformedHostLeavesNoBackend() {
        for host in ["", "  ", "not a url", "ftp://us.i.posthog.com", "us.i.posthog.com"] {
            #expect(
                PostHogConfiguration.values(
                    infoDictionary: [
                        PostHogConfiguration.apiKeyName: "phc_example",
                        PostHogConfiguration.hostName: host,
                    ],
                    environment: [:]
                ) == nil,
                "\(host) should not configure a backend"
            )
        }
    }

    /// A scheme variable is the documented way to point a local run somewhere
    /// else, so it has to win over whatever shipped in the bundle.
    @Test func theEnvironmentOverridesTheBundle() {
        let values = PostHogConfiguration.values(
            infoDictionary: [
                PostHogConfiguration.apiKeyName: "phc_bundle",
                PostHogConfiguration.hostName: "https://us.i.posthog.com",
            ],
            environment: [
                PostHogConfiguration.apiKeyName: "phc_override",
                PostHogConfiguration.hostName: "https://eu.i.posthog.com",
            ]
        )

        #expect(values?.apiKey == "phc_override")
        #expect(values?.host.absoluteString == "https://eu.i.posthog.com")
    }
}
