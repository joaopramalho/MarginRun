import Foundation
import Testing
@testable import MarginRun

/// The launch arguments decide which world the app boots into, and a UI test
/// asserting on the wrong world fails for reasons that look like product bugs.
@MainActor
struct LaunchConfigurationTests {

    @Test func aNormalLaunchSeedsNothingAndPinsNothing() {
        let launch = LaunchConfiguration(arguments: ["/path/to/MarginRun.app"])

        #expect(launch.isUITesting == false)
        #expect(launch.entitlementOverride == nil)
        #expect(launch.usesInMemoryStore == false)
        // A real first launch must be empty, or a new contractor lands in demo
        // data and burns a free active-job slot before entering anything.
        #expect(launch.seedsDemoData == false)
    }

    @Test func uiTestingUsesAnInMemoryStoreSeededWithTheFixtures() {
        let launch = LaunchConfiguration(arguments: ["-ui-testing"])

        #expect(launch.isUITesting)
        #expect(launch.usesInMemoryStore)
        #expect(launch.seedsDemoData)
        #expect(launch.entitlementOverride == false)
    }

    @Test func uiTestingProPinsTheEntitlement() {
        let launch = LaunchConfiguration(arguments: ["-ui-testing", "-ui-testing-pro"])

        #expect(launch.entitlementOverride == true)
    }

    /// The world first-run onboarding is tested in: no jobs at all.
    @Test func freshInstallSkipsTheFixtures() {
        let launch = LaunchConfiguration(
            arguments: ["-ui-testing", "-ui-testing-fresh-install"]
        )

        #expect(launch.isFreshInstall)
        #expect(launch.seedsDemoData == false)
        #expect(launch.usesInMemoryStore)
    }

    @Test func demoDataCanBeAskedForExplicitlyDuringDevelopment() {
        let launch = LaunchConfiguration(arguments: ["-seed-demo-data"])

        #expect(launch.seedsDemoData)
        #expect(launch.isUITesting == false)
    }

    @Test func theProOverrideIsIgnoredOutsideUITests() {
        #expect(LaunchConfiguration(arguments: ["-ui-testing-pro"]).entitlementOverride == nil)
    }
}

extension LaunchConfigurationTests {

    /// A UI test would strand a real activity on the host simulator's Lock
    /// Screen; a unit-test host would reconcile against the live activity
    /// daemon before the suite connects. Neither is allowed near ActivityKit.
    @Test func noTestRunReachesTheOutsideWorld() {
        let uiTest = LaunchConfiguration(arguments: ["-ui-testing"], environment: [:])
        #expect(uiTest.isTestRun)
        #expect(uiTest.usesLiveActivities == false)
        #expect(uiTest.sendsAnalytics == false)

        // The one a `-ui-testing` check cannot see: XCTest launches the host
        // app with no arguments at all.
        let unitTestHost = LaunchConfiguration(
            arguments: [],
            environment: [LaunchConfiguration.testConfigurationKey: "/tmp/whatever.xctestconfiguration"]
        )
        #expect(unitTestHost.isHostingTests)
        #expect(unitTestHost.isTestRun)
        #expect(unitTestHost.usesLiveActivities == false)
        #expect(unitTestHost.sendsAnalytics == false)
    }

    @Test func aNormalLaunchMayPresentTheLiveActivity() {
        let launch = LaunchConfiguration(arguments: [], environment: [:])

        #expect(launch.isHostingTests == false)
        #expect(launch.isTestRun == false)
        #expect(launch.usesLiveActivities)
        #expect(launch.sendsAnalytics)
        // Unchanged by the new signal: only `-ui-testing` shapes the world.
        #expect(launch.usesInMemoryStore == false)
        #expect(launch.seedsDemoData == false)
        #expect(launch.entitlementOverride == nil)
    }
}
