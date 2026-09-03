import Foundation
import Testing
@testable import MarginRun

/// Records what the timer asked ActivityKit to do, without an ActivityKit
/// session existing.
///
/// This is the whole point of ``LaborLiveActivityManaging``: the orchestration
/// — when an activity is asked for, when it is torn down, and what happens when
/// it cannot be created — is ordinary logic that runs in a normal unit test.
@MainActor
final class SpyLaborLiveActivityManager: LaborLiveActivityManaging {
    enum Call: Equatable {
        case start(sessionID: UUID)
        case end(reason: LiveActivityEndReason)
        case reconcile(runningSessionID: UUID?)
    }

    private(set) var calls: [Call] = []

    /// Stands in for Live Activities being switched off, or ActivityKit
    /// refusing the request: the manager is asked, and nothing appears.
    var isAvailable = true

    /// The sessions this spy believes are on screen, so "one timer does not
    /// create two activities" is observable.
    private(set) var presentedSessionIDs: [UUID] = []

    nonisolated init() {}

    func timerDidStart(_ session: LaborTimerSession) {
        calls.append(.start(sessionID: session.id))
        guard isAvailable else { return }
        guard !presentedSessionIDs.contains(session.id) else { return }
        presentedSessionIDs.append(session.id)
    }

    func timerDidEnd(reason: LiveActivityEndReason) {
        // Mirrors the production contract: with nothing on screen there is
        // nothing to end and nothing to report.
        guard !presentedSessionIDs.isEmpty else { return }
        presentedSessionIDs.removeAll()
        calls.append(.end(reason: reason))
    }

    func reconcile(runningSession: LaborTimerSession?) {
        calls.append(.reconcile(runningSessionID: runningSession?.id))
    }
}

@MainActor
struct LaborTimerLiveActivityOrchestrationTests {

    private func makeStore(
        _ spy: SpyLaborLiveActivityManager
    ) throws -> (store: LaborTimerStore, cleanUp: () -> Void) {
        let suiteName = "LaborLiveActivityTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = LaborTimerStore(defaults: defaults, liveActivity: spy)
        return (store, { defaults.removePersistentDomain(forName: suiteName) })
    }

    private let startedAt = Date(timeIntervalSince1970: 1_788_000_000)

    // MARK: - Start

    @Test func startingTheTimerAsksForALiveActivity() throws {
        let spy = SpyLaborLiveActivityManager()
        let (store, cleanUp) = try makeStore(spy)
        defer { cleanUp() }

        try store.start(jobID: UUID(), jobName: "Kitchen remodel", hourlyCost: 50, at: startedAt)

        let session = try #require(store.session)
        #expect(spy.calls == [.start(sessionID: session.id)])
        #expect(spy.presentedSessionIDs == [session.id])
    }

    /// The load-bearing guarantee of the whole feature: a Lock Screen that
    /// cannot appear must not cost the customer their tracked time.
    @Test func aTimerStartsAndPersistsEvenWhenActivityKitIsUnavailable() throws {
        let suiteName = "LaborLiveActivityTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let spy = SpyLaborLiveActivityManager()
        spy.isAvailable = false
        let store = LaborTimerStore(defaults: defaults, liveActivity: spy)

        try store.start(jobID: UUID(), jobName: "Deck rebuild", hourlyCost: 60, at: startedAt)

        #expect(store.session?.isRunning == true)
        #expect(spy.presentedSessionIDs.isEmpty)

        // Persisted, which is the part that actually matters.
        let restored = LaborTimerStore(defaults: defaults)
        #expect(restored.session?.isRunning == true)
        #expect(restored.session?.startedAt == startedAt)
    }

    @Test func oneTimerNeverProducesTwoActivities() throws {
        let spy = SpyLaborLiveActivityManager()
        let (store, cleanUp) = try makeStore(spy)
        defer { cleanUp() }

        try store.start(jobID: UUID(), jobName: "Kitchen remodel", hourlyCost: 50, at: startedAt)
        // The one-active-timer rule rejects this, so nothing new is presented.
        #expect(throws: LaborTimerError.self) {
            try store.start(jobID: UUID(), jobName: "Fence", hourlyCost: 40, at: startedAt)
        }

        #expect(spy.presentedSessionIDs.count == 1)
        #expect(spy.calls.filter { if case .start = $0 { true } else { false } }.count == 1)
    }

    // MARK: - End

    @Test func stoppingTheTimerEndsTheActivityImmediately() throws {
        let spy = SpyLaborLiveActivityManager()
        let (store, cleanUp) = try makeStore(spy)
        defer { cleanUp() }

        try store.start(jobID: UUID(), jobName: "Kitchen remodel", hourlyCost: 50, at: startedAt)
        try store.stop(at: startedAt.addingTimeInterval(3_600))

        #expect(spy.presentedSessionIDs.isEmpty)
        #expect(spy.calls.last == .end(reason: .timerStopped))
        // The session survives for review — only the Lock Screen went away.
        #expect(store.session?.isRunning == false)
        #expect(store.runningSession == nil)
    }

    /// Stop → review → Confirm. The activity ends at Stop, and saving the
    /// labor entry afterwards must not resurrect or re-end it.
    @Test func confirmingAfterReviewLeavesNoSecondEnd() throws {
        let spy = SpyLaborLiveActivityManager()
        let (store, cleanUp) = try makeStore(spy)
        defer { cleanUp() }

        try store.start(jobID: UUID(), jobName: "Kitchen remodel", hourlyCost: 50, at: startedAt)
        try store.stop(at: startedAt.addingTimeInterval(3_600))
        try store.updateReview(hourlyCost: 65, note: "Framing")
        store.finish()

        let ends = spy.calls.filter { if case .end = $0 { true } else { false } }
        #expect(ends == [.end(reason: .timerStopped)])
        #expect(spy.presentedSessionIDs.isEmpty)
    }

    @Test func discardingARunningTimerEndsTheActivity() throws {
        let spy = SpyLaborLiveActivityManager()
        let (store, cleanUp) = try makeStore(spy)
        defer { cleanUp() }

        try store.start(jobID: UUID(), jobName: "Kitchen remodel", hourlyCost: 50, at: startedAt)
        store.discard()

        #expect(spy.presentedSessionIDs.isEmpty)
        #expect(spy.calls.last == .end(reason: .timerDiscarded))
        #expect(store.session == nil)
    }

    /// The activity represents an active timer, not a saved `LaborEntry`.
    /// Whichever way a reviewed session is thrown away, nothing is left
    /// counting on the Lock Screen.
    @Test func discardingAReviewedSessionCannotLeaveAnActivityRunning() throws {
        let spy = SpyLaborLiveActivityManager()
        let (store, cleanUp) = try makeStore(spy)
        defer { cleanUp() }

        try store.start(jobID: UUID(), jobName: "Kitchen remodel", hourlyCost: 50, at: startedAt)
        try store.stop(at: startedAt.addingTimeInterval(1_800))
        store.discard()

        #expect(spy.presentedSessionIDs.isEmpty)
        #expect(store.session == nil)
    }

    // MARK: - Reconciliation entry point

    @Test func reconciliationReportsOnlyARunningTimer() throws {
        let spy = SpyLaborLiveActivityManager()
        let (store, cleanUp) = try makeStore(spy)
        defer { cleanUp() }

        store.reconcileLiveActivity()
        #expect(spy.calls.last == .reconcile(runningSessionID: nil))

        try store.start(jobID: UUID(), jobName: "Kitchen remodel", hourlyCost: 50, at: startedAt)
        let session = try #require(store.session)
        store.reconcileLiveActivity()
        #expect(spy.calls.last == .reconcile(runningSessionID: session.id))

        // Stopped and awaiting review is not a running timer.
        try store.stop(at: startedAt.addingTimeInterval(60))
        store.reconcileLiveActivity()
        #expect(spy.calls.last == .reconcile(runningSessionID: nil))
    }
}

// MARK: - Reconciliation policy

/// The decisions ``LaborLiveActivityManager`` makes on foreground, exercised
/// without ActivityKit. The manager itself only looks up the real `Activity`
/// objects a plan names and ends or requests them.
struct LaborLiveActivityReconcilerTests {

    @Test func aMatchingActivityIsLeftAlone() {
        let session = UUID()
        let plan = LaborLiveActivityReconciler.plan(
            existing: [LiveActivityDescriptor(activityID: "a", sessionID: session)],
            runningSessionID: session
        )

        #expect(plan.keep == "a")
        #expect(plan.end.isEmpty)
        #expect(plan.requestsNewActivity == false)
    }

    @Test func aRunningTimerWithNoActivityGetsOne() {
        let plan = LaborLiveActivityReconciler.plan(existing: [], runningSessionID: UUID())

        #expect(plan.keep == nil)
        #expect(plan.end.isEmpty)
        #expect(plan.requestsNewActivity)
    }

    @Test func anOrphanedActivityIsEnded() {
        let plan = LaborLiveActivityReconciler.plan(
            existing: [LiveActivityDescriptor(activityID: "a", sessionID: UUID())],
            runningSessionID: nil
        )

        #expect(plan.keep == nil)
        #expect(plan.end == [LiveActivityEnding(activityID: "a", reason: .orphanReconciled)])
        #expect(plan.requestsNewActivity == false)
    }

    /// The Live Activity follows the *running* timer, so a leftover activity
    /// from an older session is an orphan even though a timer exists.
    @Test func anActivityForAPreviousSessionIsReplaced() {
        let plan = LaborLiveActivityReconciler.plan(
            existing: [LiveActivityDescriptor(activityID: "old", sessionID: UUID())],
            runningSessionID: UUID()
        )

        #expect(plan.keep == nil)
        #expect(plan.end == [LiveActivityEnding(activityID: "old", reason: .orphanReconciled)])
        #expect(plan.requestsNewActivity)
    }

    /// Should never happen — MarginRun allows one timer — so the rule is
    /// stated rather than assumed: keep the one that matches, end the rest.
    @Test func multipleStaleActivitiesAreCleanedUpDownToOne() {
        let session = UUID()
        let plan = LaborLiveActivityReconciler.plan(
            existing: [
                LiveActivityDescriptor(activityID: "keep", sessionID: session),
                LiveActivityDescriptor(activityID: "dupe", sessionID: session),
                LiveActivityDescriptor(activityID: "orphan", sessionID: UUID()),
            ],
            runningSessionID: session
        )

        #expect(plan.keep == "keep")
        #expect(plan.end == [
            LiveActivityEnding(activityID: "dupe", reason: .staleDuplicate),
            LiveActivityEnding(activityID: "orphan", reason: .orphanReconciled),
        ])
        #expect(plan.requestsNewActivity == false)
    }

    @Test func everyActivityIsEndedWhenNoTimerIsRunning() {
        let plan = LaborLiveActivityReconciler.plan(
            existing: [
                LiveActivityDescriptor(activityID: "a", sessionID: UUID()),
                LiveActivityDescriptor(activityID: "b", sessionID: UUID()),
            ],
            runningSessionID: nil
        )

        #expect(plan.end.map(\.activityID) == ["a", "b"])
        #expect(plan.end.allSatisfy { $0.reason == .orphanReconciled })
        #expect(plan.requestsNewActivity == false)
    }
}
