import Foundation

/// The seam between the Labor Timer and ActivityKit.
///
/// ``LaborTimerStore`` stays the sole source of truth for whether a timer is
/// running and how long it has run; this protocol only ever *reflects* that
/// state on the Lock Screen. Nothing behind it may write a timer, a duration,
/// or a financial record, and no method can fail in a way the timer has to
/// care about — every one of them returns void, because a Live Activity
/// failure is never a timer failure.
///
/// The methods are synchronous on purpose. The store calls them inline while
/// it already holds the authoritative state, and the production conformance
/// does its own awaiting internally. That keeps orchestration deterministic in
/// tests without any of them touching a real activity session.
@MainActor
protocol LaborLiveActivityManaging: AnyObject {
    /// A timer just started and has already been persisted.
    func timerDidStart(_ session: LaborTimerSession)

    /// The running timer is over — stopped, discarded, or thrown away during
    /// review. Idempotent: calling it with nothing on screen does nothing and
    /// reports nothing.
    func timerDidEnd(reason: LiveActivityEndReason)

    /// Brings the Lock Screen back in line with the timer after a relaunch or
    /// a return to the foreground.
    ///
    /// - Parameter runningSession: the timer that is *currently running*, or
    ///   `nil` if there isn't one. A stopped session awaiting review is not a
    ///   running timer and must not keep an activity alive.
    func reconcile(runningSession: LaborTimerSession?)
}

/// Does nothing, successfully.
///
/// The default everywhere a real Lock Screen would be wrong or unwanted: unit
/// tests, previews, and UI-test runs, where an activity escaping onto the host
/// simulator would outlive the run.
@MainActor
final class NoOpLaborLiveActivityManager: LaborLiveActivityManaging {
    /// `nonisolated` so it can stand as a default argument, which Swift
    /// evaluates outside the caller's actor.
    nonisolated init() {}

    func timerDidStart(_ session: LaborTimerSession) {}
    func timerDidEnd(reason: LiveActivityEndReason) {}
    func reconcile(runningSession: LaborTimerSession?) {}
}
