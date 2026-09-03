import ActivityKit
import Foundation

/// What the Labor Timer Live Activity is allowed to know.
///
/// The activity is a *presentation* of ``LaborTimerSession``, never a second
/// timer. It therefore carries the smallest set of facts a Lock Screen or
/// Dynamic Island needs to draw itself and to be matched back to the session
/// that owns it:
///
/// - `sessionID` / `jobID` — identity, so reconciliation can tell "the
///   activity for the running timer" from a stale one left behind by a crash.
/// - `jobName` — the only user-entered text here, and only because an activity
///   that cannot say *which* job it is timing is not useful. It is rendered
///   `privacySensitive()` so the system redacts it on a locked device.
/// - `startedAt` — the one input the elapsed time is derived from. SwiftUI's
///   `Text(timerInterval:)` counts from it without the app being awake, so
///   nothing ever pushes a per-second update into ActivityKit.
///
/// Deliberately absent, and to stay absent: customer name, hourly cost, labor
/// cost, contract value, profit, margin, and any receipt or vendor detail.
/// None of it belongs on a Lock Screen that a stranger can read.
nonisolated struct LaborTimerActivityAttributes: ActivityAttributes {

    /// The part of the activity that changes while it is on screen.
    ///
    /// `isRunning` exists for exactly one moment: the final content handed to
    /// `Activity.end(_:dismissalPolicy:)`, which freezes the display so a
    /// dismissed activity cannot spend its last frames pretending to still
    /// count. Nothing updates this state per second.
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// The persisted start of the labor session. The single input the
        /// system's own timer text counts up from.
        var startedAt: Date

        /// `false` only in the final content sent when the activity ends.
        var isRunning: Bool

        init(startedAt: Date, isRunning: Bool = true) {
            self.startedAt = startedAt
            self.isRunning = isRunning
        }
    }

    /// The labor session this activity was requested for. Reconciliation
    /// matches on this, so restarting a timer can never adopt the previous
    /// timer's activity.
    var sessionID: UUID

    /// The job being worked. Identity only — no financial record is attached.
    var jobID: UUID

    /// The job's display name, shown so the activity is identifiable at a
    /// glance. Treated as sensitive user text at every render site.
    var jobName: String

    init(sessionID: UUID, jobID: UUID, jobName: String) {
        self.sessionID = sessionID
        self.jobID = jobID
        self.jobName = jobName
    }
}

/// The URL a tapped Labor Timer Live Activity opens.
///
/// Declared beside the attributes because both targets need it: the extension
/// attaches it to the activity, the app resolves it on `onOpenURL`. One
/// spelling, no string literal duplicated across a process boundary.
nonisolated enum LaborTimerDeepLink {
    static let scheme = "marginrun"
    static let host = "labor-timer"

    /// `marginrun://labor-timer`
    static let url: URL = {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        // Force-unwrapped against two compile-time constants: if this is ever
        // nil the scheme itself is malformed, which a test catches at once.
        return components.url!
    }()

    static func matches(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme && url.host()?.lowercased() == host
    }
}
