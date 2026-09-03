import Foundation

/// One Live Activity as reconciliation needs to see it: which activity, and
/// which labor session it was requested for.
///
/// A plain value rather than an `Activity`, so the policy below can be reasoned
/// about — and tested — without a real ActivityKit session.
nonisolated struct LiveActivityDescriptor: Equatable, Sendable {
    let activityID: String
    let sessionID: UUID

    init(activityID: String, sessionID: UUID) {
        self.activityID = activityID
        self.sessionID = sessionID
    }
}

/// An activity to take down, and why.
nonisolated struct LiveActivityEnding: Equatable, Sendable {
    let activityID: String
    let reason: LiveActivityEndReason
}

/// What reconciliation decided, before anything acts on it.
nonisolated struct LiveActivityReconciliationPlan: Equatable, Sendable {
    /// The one activity allowed to survive, already showing the running timer.
    /// Left alone entirely — re-requesting or updating it would only make a
    /// correct Lock Screen flicker.
    var keep: String?

    /// Everything else on screen, in the order it was found.
    var end: [LiveActivityEnding] = []

    /// A timer is running and nothing on screen represents it.
    var requestsNewActivity = false
}

/// Decides what the Lock Screen should look like given what is on it and what
/// the timer says.
///
/// Pure and total: same inputs, same plan, no ActivityKit, no I/O, and no route
/// by which it could touch a `Job`, a `LaborEntry`, or any other financial
/// record. ``LaborLiveActivityManager`` is the only thing that carries a plan
/// out, and all it can do with one is end activities and request one.
nonisolated enum LaborLiveActivityReconciler {

    /// - Parameters:
    ///   - existing: every MarginRun labor activity currently alive, including
    ///     ones requested by a previous launch of the app.
    ///   - runningSessionID: the timer that is *running now*, or `nil`. A
    ///     stopped session awaiting review is not running and must not keep an
    ///     activity alive.
    static func plan(
        existing: [LiveActivityDescriptor],
        runningSessionID: UUID?
    ) -> LiveActivityReconciliationPlan {
        var plan = LiveActivityReconciliationPlan()

        guard let runningSessionID else {
            // Nothing is running, so nothing is entitled to be on screen —
            // whichever launch put it there.
            plan.end = existing.map {
                LiveActivityEnding(activityID: $0.activityID, reason: .orphanReconciled)
            }
            return plan
        }

        for candidate in existing {
            let isForRunningTimer = candidate.sessionID == runningSessionID

            if isForRunningTimer, plan.keep == nil {
                plan.keep = candidate.activityID
                continue
            }

            // MarginRun permits one timer, so it permits one activity. A second
            // card for the same session is a duplicate; a card for any other
            // session belongs to a timer that no longer exists.
            plan.end.append(
                LiveActivityEnding(
                    activityID: candidate.activityID,
                    reason: isForRunningTimer ? .staleDuplicate : .orphanReconciled
                )
            )
        }

        plan.requestsNewActivity = plan.keep == nil
        return plan
    }
}
