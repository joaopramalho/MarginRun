import Foundation
import Testing
@testable import MarginRun

@MainActor
struct DeepLinkRouterTests {

    private struct Harness {
        let router: DeepLinkRouter
        let backend: RecordingAnalyticsBackend
        let suiteName: String

        func tearDown() {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeHarness(now: @escaping () -> Date = { .now }) throws -> Harness {
        let suiteName = "DeepLinkRouterTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let backend = RecordingAnalyticsBackend()
        let service = AnalyticsService(
            backend: backend,
            milestones: AnalyticsMilestones(defaults: defaults)
        )
        return Harness(
            router: DeepLinkRouter(analytics: service, now: now),
            backend: backend,
            suiteName: suiteName
        )
    }

    private var openedEvents: (RecordingAnalyticsBackend) -> [String] {
        { $0.recordedNames.filter { $0 == "labor_live_activity_opened" } }
    }

    // MARK: - URL vocabulary

    /// The extension builds this URL and the app parses it. If the two ever
    /// disagree the Live Activity becomes a dead tap target, so both sides read
    /// the same constant and this pins its shape.
    @Test func theLaborTimerLinkIsTheDocumentedURL() {
        #expect(LaborTimerDeepLink.url.absoluteString == "marginrun://labor-timer")
        #expect(LaborTimerDeepLink.matches(LaborTimerDeepLink.url))
        #expect(DeepLink(url: LaborTimerDeepLink.url) == .laborTimer)
    }

    @Test func theSchemeAndHostAreMatchedCaseInsensitively() throws {
        let shouted = try #require(URL(string: "MARGINRUN://LABOR-TIMER"))
        #expect(DeepLink(url: shouted) == .laborTimer)
    }

    @Test func unrelatedURLsAreNotClaimed() throws {
        for string in [
            "marginrun://dashboard",
            "https://marginrun.app/labor-timer",
            "otherapp://labor-timer",
        ] {
            let url = try #require(URL(string: string))
            #expect(DeepLink(url: url) == nil, "\(string) should not resolve")
        }
    }

    // MARK: - Navigation

    @Test func openingTheLinkSelectsTheTimerTab() throws {
        let harness = try makeHarness()
        defer { harness.tearDown() }

        harness.router.selectedTab = .dashboard
        #expect(harness.router.handle(LaborTimerDeepLink.url))
        #expect(harness.router.selectedTab == .timer)
    }

    /// Routing is navigation only. Nothing here reaches the timer store, so a
    /// deep link cannot bring a second timer into existence — the Timer tab
    /// simply shows whichever session already exists.
    @Test func anUnknownLinkChangesNothing() throws {
        let harness = try makeHarness()
        defer { harness.tearDown() }

        harness.router.selectedTab = .insights
        let url = try #require(URL(string: "marginrun://not-a-screen"))

        #expect(harness.router.handle(url) == false)
        #expect(harness.router.selectedTab == .insights)
        #expect(openedEvents(harness.backend).isEmpty)
    }

    // MARK: - Analytics

    @Test func oneTapReportsOneOpen() throws {
        let harness = try makeHarness()
        defer { harness.tearDown() }

        harness.router.handle(LaborTimerDeepLink.url)

        #expect(openedEvents(harness.backend) == ["labor_live_activity_opened"])
        #expect(
            harness.backend.properties(for: "labor_live_activity_opened")?["source"]
                == .string("live_activity")
        )
    }

    /// A redelivered URL, or a second handler added later, must not turn one
    /// tap on the Lock Screen into two rows in the funnel. Navigation still
    /// happens both times; only the event is collapsed.
    @Test func aRepeatedDeliveryOfTheSameTapReportsOnce() throws {
        var now = Date(timeIntervalSince1970: 1_788_000_000)
        let harness = try makeHarness(now: { now })
        defer { harness.tearDown() }

        harness.router.handle(LaborTimerDeepLink.url)
        harness.router.selectedTab = .settings
        now = now.addingTimeInterval(0.2)
        harness.router.handle(LaborTimerDeepLink.url)

        #expect(openedEvents(harness.backend) == ["labor_live_activity_opened"])
        #expect(harness.router.selectedTab == .timer)
    }

    @Test func aGenuinelyLaterTapIsReportedAgain() throws {
        var now = Date(timeIntervalSince1970: 1_788_000_000)
        let harness = try makeHarness(now: { now })
        defer { harness.tearDown() }

        harness.router.handle(LaborTimerDeepLink.url)
        now = now.addingTimeInterval(60)
        harness.router.handle(LaborTimerDeepLink.url)

        #expect(openedEvents(harness.backend).count == 2)
    }
}
