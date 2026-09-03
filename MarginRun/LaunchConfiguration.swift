import Foundation

/// What the launch arguments are asking for.
///
/// UI tests need three different starting worlds — a used install, a brand new
/// one, and a Pro account — and reading `ProcessInfo` inline in three places is
/// how those drift apart. Parsed once here, and testable on its own.
nonisolated struct LaunchConfiguration: Equatable, Sendable {
    static let uiTesting = "-ui-testing"
    static let uiTestingPro = "-ui-testing-pro"
    static let uiTestingFreshInstall = "-ui-testing-fresh-install"
    static let seedDemoData = "-seed-demo-data"

    /// Set by XCTest in the host process it injects a test bundle into.
    static let testConfigurationKey = "XCTestConfigurationFilePath"

    let isUITesting: Bool
    let isFreshInstall: Bool
    let entitlementOverride: Bool?
    let seedsDemoData: Bool

    /// Whether this process was launched to host an XCTest bundle.
    ///
    /// Unit tests run *inside* the app, and they launch it without any of the
    /// arguments above — so `-ui-testing` cannot speak for them. XCTest sets
    /// this variable in the host's environment, which is the only reliable
    /// signal available before the first view is built.
    let isHostingTests: Bool

    init(arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment) {
        let arguments = Set(arguments)
        isUITesting = arguments.contains(Self.uiTesting)
        isHostingTests = environment[Self.testConfigurationKey] != nil
        isFreshInstall = arguments.contains(Self.uiTestingFreshInstall)
        entitlementOverride = isUITesting ? arguments.contains(Self.uiTestingPro) : nil

        // Demo jobs are a fixture, not a product feature. Seeding them into a
        // real first launch would drop a new contractor into someone else's
        // kitchen remodel and burn one of their two free active-job slots
        // before they have entered anything — which is exactly the first-run
        // experience onboarding exists to fix.
        seedsDemoData =
            (isUITesting && !isFreshInstall) || arguments.contains(Self.seedDemoData)
    }

    /// The store is in memory for UI tests so runs cannot contaminate each other.
    var usesInMemoryStore: Bool { isUITesting }

    /// Any run driven by XCTest, of either kind.
    ///
    /// The two arrive by different routes — a UI test passes `-ui-testing` to
    /// the app it drives, a unit test host is launched with no arguments at
    /// all — and everything that must not reach the outside world during a
    /// test has to exclude both.
    var isTestRun: Bool { isUITesting || isHostingTests }

    /// Whether the process may talk to ActivityKit.
    ///
    /// A UI test would leave a real activity on the host simulator's Lock
    /// Screen after the run; a unit-test host would reconcile against the live
    /// activity daemon on launch, which is work no unit test asked for and —
    /// observed in practice — can hang the host before the suite ever connects.
    var usesLiveActivities: Bool { !isTestRun }

    /// Whether real analytics may leave the process.
    ///
    /// A test run's events are not product behaviour, and a CI job repeating
    /// the suite would otherwise write `app_first_open` into the same project
    /// the funnel is read from.
    var sendsAnalytics: Bool { !isTestRun }
}
