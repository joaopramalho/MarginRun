import Foundation
import RevenueCat
import Testing
@testable import MarginRun

@MainActor
struct ProductAnalyticsIntegrationTests {
    private struct Harness {
        let service: AnalyticsService
        let backend: RecordingAnalyticsBackend
        let defaults: UserDefaults
        let suiteName: String

        func tearDown() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeHarness() throws -> Harness {
        let suiteName = "ProductAnalyticsIntegrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let backend = RecordingAnalyticsBackend()
        let service = AnalyticsService(
            backend: backend,
            milestones: AnalyticsMilestones(defaults: defaults)
        )
        return Harness(
            service: service,
            backend: backend,
            defaults: defaults,
            suiteName: suiteName
        )
    }

    @Test func savedJobActionEmitsJobCreatedAndItsFirstUseMilestone() throws {
        let harness = try makeHarness()
        defer { harness.tearDown() }

        var draft = CreateJobDraft()
        draft.name = "Private job name"
        draft.contractValueText = "18400"
        draft.materialsText = "6200"
        let job = try #require(draft.makeJob())

        harness.service.trackJobCreated(source: .history, financials: job.financials)

        #expect(harness.backend.recordedNames == ["first_job_created", "job_created"])
        let properties = try #require(harness.backend.properties(for: "job_created"))
        #expect(properties["source"] == .string("history"))
        #expect(properties["has_cost_estimate"] == .bool(true))
        #expect(properties.values.contains(.string("Private job name")) == false)
    }

    @Test func savedExpenseActionEmitsExpenseAddedAndItsFirstUseMilestone() throws {
        let harness = try makeHarness()
        defer { harness.tearDown() }

        harness.service.trackExpenseAdded(category: .materials, hasReceipt: true)

        #expect(harness.backend.recordedNames == ["first_expense_added", "expense_added"])
        let properties = try #require(harness.backend.properties(for: "expense_added"))
        #expect(properties["category"] == .string(ExpenseCategory.materials.rawValue))
        #expect(properties["has_receipt"] == .bool(true))
    }

    @Test func savedLaborActionEmitsLaborAddedAndItsFirstUseMilestone() throws {
        let harness = try makeHarness()
        defer { harness.tearDown() }

        harness.service.trackLaborAdded(source: .manual)

        #expect(harness.backend.recordedNames == ["first_labor_added", "labor_added"])
        #expect(
            harness.backend.properties(for: "labor_added")?["source"] == .string("manual")
        )
    }

    @Test func completingAJobEmitsJobCompletedFromTheFrozenReport() throws {
        let harness = try makeHarness()
        defer { harness.tearDown() }
        let job = Job(
            name: "Private completed job",
            customerName: "Private customer",
            contractValue: 10_000,
            targetMargin: 30,
            estimatedMaterials: 4_000,
            estimatedLabor: 1_000,
            estimatedSubcontractors: 0,
            estimatedEquipment: 0,
            estimatedOther: 0
        )
        job.complete(at: Date(timeIntervalSince1970: 1_700_000_000))

        harness.service.trackJobCompleted(report: job.completionReport)

        #expect(harness.backend.recordedNames == ["job_completed"])
        let properties = try #require(harness.backend.properties(for: "job_completed"))
        #expect(properties["met_target_margin"] == .bool(true))
        #expect(properties["beat_expected_profit"] == .bool(true))
    }

    @Test func onePaywallPresentationEmitsOneViewWithTheTypedContext() throws {
        let harness = try makeHarness()
        defer { harness.tearDown() }
        var reporter = PaywallAnalyticsReporter()

        reporter.reportIfNeeded(feature: .receiptScan, analytics: harness.service)
        reporter.reportIfNeeded(feature: .receiptScan, analytics: harness.service)

        #expect(harness.backend.recordedNames == ["paywall_viewed"])
        #expect(
            harness.backend.properties(for: "paywall_viewed")?["paywall_context"]
                == .string("receipt_scan")
        )
    }

    @Test func missingPostHogConfigurationSelectsANoOpBackend() {
        let values = PostHogConfiguration.values(infoDictionary: [:], environment: [:])
        #expect(values == nil)
        #expect(
            PostHogConfiguration.makeBackend(infoDictionary: [:], environment: [:])
                is NoOpAnalyticsBackend
        )
    }

    @Test func postHogConfigurationRequiresBothKeyAndRegionSpecificHost() {
        let values = PostHogConfiguration.values(
            infoDictionary: [:],
            environment: [
                "POSTHOG_API_KEY": "phc_public_ingestion_key",
                "POSTHOG_HOST": "https://eu.i.posthog.com",
            ]
        )

        #expect(values?.apiKey == "phc_public_ingestion_key")
        #expect(values?.host.absoluteString == "https://eu.i.posthog.com")
    }

    @Test func revenueCatCancellationEmitsCancellationNotFailure() async throws {
        let harness = try makeHarness()
        defer { harness.tearDown() }
        let package = try #require(PaywallFixture.offering().availablePackages.first)
        let store = SubscriptionStore(analytics: harness.service) { _ in
            SubscriptionStore.PurchaseExecutionResult(
                customerInfo: nil,
                userCancelled: true,
                entitlementActive: false
            )
        }

        let purchased = await store.purchase(package, plan: .yearly, feature: .insights)

        #expect(purchased == false)
        #expect(harness.backend.recordedNames == ["purchase_started", "purchase_cancelled"])
        #expect(harness.backend.recordedNames.contains("purchase_failed") == false)
    }

    @Test func confirmedRevenueCatEntitlementEmitsPurchaseCompleted() async throws {
        let harness = try makeHarness()
        defer { harness.tearDown() }
        let package = try #require(PaywallFixture.offering().availablePackages.first)
        let store = SubscriptionStore(analytics: harness.service) { _ in
            SubscriptionStore.PurchaseExecutionResult(
                customerInfo: nil,
                userCancelled: false,
                entitlementActive: true
            )
        }

        let purchased = await store.purchase(package, plan: .yearly, feature: .insights)

        #expect(purchased)
        #expect(harness.backend.recordedNames == ["purchase_started", "purchase_completed"])
        #expect(harness.backend.recordedNames.contains("purchase_failed") == false)
    }
}
