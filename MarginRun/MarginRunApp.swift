//
//  MarginRunApp.swift
//  MarginRun
//
//  Created by João Pedro da Silva Ramalho on 31/08/26.
//

import SwiftUI
import SwiftData

@main
struct MarginRunApp: App {
    let modelContainer: ModelContainer

    /// Pins the entitlement during UI tests so runs never depend on the network
    /// or on a store account. `nil` in a normal launch.
    private let entitlementOverride: Bool?

    /// Analytics is created once, at the top, so every screen shares one
    /// service and one set of once-per-install milestones.
    private let analytics: AnalyticsService

    /// The one ActivityKit seam in the process. A UI-test run gets the no-op:
    /// an activity requested by a test would outlive the run and sit on the
    /// host simulator's Lock Screen afterwards.
    private let liveActivity: LaborLiveActivityManaging

    init() {
        let schema = Schema([Job.self, Expense.self, LaborEntry.self, ExtraRevenue.self])
        let launch = LaunchConfiguration(arguments: ProcessInfo.processInfo.arguments)

        if launch.isUITesting {
            AppPreferences().resetForUITesting()
            OnboardingState().resetForUITesting()
            AnalyticsMilestones().resetForUITesting()
            LaborTimerStore.resetForUITesting()
            entitlementOverride = launch.entitlementOverride
            // No event may leave the app during a UI test run, and no assertion
            // may depend on one having been delivered.
            analytics = AnalyticsService(backend: NoOpAnalyticsBackend())
        } else {
            entitlementOverride = nil
            // A unit-test host lands here — it is launched with no arguments —
            // so the backend is chosen by the launch, not by this branch.
            analytics = AnalyticsService(
                backend: launch.sendsAnalytics
                    ? PostHogConfiguration.makeBackend()
                    : NoOpAnalyticsBackend()
            )
            // Configure before any view can read an entitlement, so the first
            // frame renders the cached Pro state instead of the locked one.
            SubscriptionStore.configureSDK()
        }

        // Gated on the launch rather than on the branch above: a *unit* test
        // host is launched with no arguments at all, so it lands in the else
        // branch while still being a test run that must not touch ActivityKit.
        liveActivity = launch.usesLiveActivities
            ? LaborLiveActivityManager(analytics: analytics)
            : NoOpLaborLiveActivityManager()

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: launch.usesInMemoryStore
        )
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            if launch.seedsDemoData {
                try MockData.seedIfEmpty(context: container.mainContext)
            }

            // Anyone whose install already holds work has effectively been
            // onboarded, whatever the flag says. Running this after seeding
            // means the UI-test world — which is a used install — behaves like
            // one, and a genuinely empty install still gets first-run setup.
            let jobCount = try container.mainContext.fetchCount(FetchDescriptor<Job>())
            OnboardingState().completeIfInstallHasExistingData(
                jobCount: jobCount,
                preferences: AppPreferences()
            )

            modelContainer = container
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                entitlementOverride: entitlementOverride,
                analytics: analytics,
                liveActivity: liveActivity
            )
        }
        .modelContainer(modelContainer)
    }
}
