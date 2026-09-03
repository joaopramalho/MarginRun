import ActivityKit
import Foundation
import OSLog

/// The only type in MarginRun that calls ActivityKit.
///
/// Views never request, update or end an activity; they change the timer, and
/// ``LaborTimerStore`` tells this manager what happened. Centralising it is
/// what makes the one-activity-per-timer rule enforceable and what keeps the
/// "start it, but never at the timer's expense" contract in a single place.
///
/// ### What it deliberately does not do
///
/// - It never updates content on a schedule. The Lock Screen and Dynamic
///   Island count with `Text(timerInterval:)` from the persisted start date,
///   so a two-hour session costs exactly one `request` and one `end`.
/// - It never writes to SwiftData, `UserDefaults`, or the timer. Reconciliation
///   reads the timer and edits activities, never the reverse.
@MainActor
final class LaborLiveActivityManager: LaborLiveActivityManaging {
    private typealias LaborActivity = Activity<LaborTimerActivityAttributes>

    private let analytics: AnalyticsService?
    private let logger = Logger(subsystem: "app.marginrun", category: "live-activity")

    /// The activity this process believes it owns. Held so `timerDidEnd` can
    /// decide *synchronously* whether there is anything to end, which is what
    /// keeps `labor_live_activity_ended` at one event per real teardown.
    private var activity: LaborActivity?

    init(analytics: AnalyticsService? = nil) {
        self.analytics = analytics
    }

    // MARK: - Timer lifecycle

    func timerDidStart(_ session: LaborTimerSession) {
        request(for: session, source: .timerStart)
    }

    func timerDidEnd(reason: LiveActivityEndReason) {
        guard let activity else { return }
        self.activity = nil
        analytics?.track(.laborLiveActivityEnded(reason: reason))
        end(activity)
    }

    // MARK: - Reconciliation

    func reconcile(runningSession: LaborTimerSession?) {
        // Every labor activity alive in this install, including ones requested
        // by a launch that was killed before it could end them.
        let live = LaborActivity.activities
        let plan = LaborLiveActivityReconciler.plan(
            existing: live.map {
                LiveActivityDescriptor(activityID: $0.id, sessionID: $0.attributes.sessionID)
            },
            runningSessionID: runningSession?.id
        )

        let byID = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for ending in plan.end {
            guard let stale = byID[ending.activityID] else { continue }
            analytics?.track(.laborLiveActivityEnded(reason: ending.reason))
            end(stale)
        }

        // Adopted, not re-requested: an activity already counting from the
        // right start date is correct, and touching it would only make a good
        // Lock Screen flicker.
        activity = plan.keep.flatMap { byID[$0] }

        if plan.requestsNewActivity, let runningSession {
            request(for: runningSession, source: .reconciliation)
        }
    }

    // MARK: - ActivityKit

    private func request(for session: LaborTimerSession, source: LiveActivitySource) {
        // A timer that is no longer running has nothing to present.
        guard session.isRunning else { return }

        // Already showing this exact session: requesting again would put a
        // second card on the Lock Screen for one timer.
        if let activity, activity.attributes.sessionID == session.id { return }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            // Switched off in Settings, or a device that has no Lock Screen
            // surface for this. Reported, never surfaced: the timer is running
            // and persisted regardless, and an alert here would be noise about
            // a setting the customer chose.
            analytics?.track(.laborLiveActivityUnavailable(reason: .notEnabled))
            return
        }

        let attributes = LaborTimerActivityAttributes(
            sessionID: session.id,
            jobID: session.jobID,
            jobName: session.jobName
        )
        let content = ActivityContent(
            state: LaborTimerActivityAttributes.ContentState(startedAt: session.startedAt),
            // No stale date: the elapsed time is derived from `startedAt` by
            // the system, so the content cannot go out of date on its own.
            staleDate: nil
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                // Entirely local. No APNs token, no push-to-start, no server.
                pushType: nil
            )
            analytics?.track(.laborLiveActivityStarted(source: source))
        } catch {
            logger.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
            analytics?.track(.laborLiveActivityUnavailable(reason: .requestFailed))
        }
    }

    /// Ends `activity` with content that reads as stopped, and dismisses it at
    /// once so a finished session never lingers on the Lock Screen still
    /// counting up.
    private func end(_ activity: LaborActivity) {
        let final = ActivityContent(
            state: LaborTimerActivityAttributes.ContentState(
                startedAt: activity.content.state.startedAt,
                isRunning: false
            ),
            staleDate: nil
        )
        Task { await activity.end(final, dismissalPolicy: .immediate) }
    }
}
