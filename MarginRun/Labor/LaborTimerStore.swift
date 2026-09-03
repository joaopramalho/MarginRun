import Combine
import Foundation

nonisolated struct LaborTimerSession: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let jobID: UUID
    let jobName: String
    let startedAt: Date
    var stoppedAt: Date?
    var hourlyCost: Decimal
    var note: String

    init(
        id: UUID = UUID(),
        jobID: UUID,
        jobName: String,
        startedAt: Date,
        stoppedAt: Date? = nil,
        hourlyCost: Decimal,
        note: String = ""
    ) {
        self.id = id
        self.jobID = jobID
        self.jobName = jobName
        self.startedAt = startedAt
        self.stoppedAt = stoppedAt
        self.hourlyCost = hourlyCost
        self.note = note
    }

    var isRunning: Bool { stoppedAt == nil }

    func durationSeconds(at date: Date = .now) -> TimeInterval {
        max(0, (stoppedAt ?? date).timeIntervalSince(startedAt))
    }

    func durationHours(at date: Date = .now) -> Decimal {
        Decimal(durationSeconds(at: date) / 3_600)
    }

    func cost(at date: Date = .now) -> Decimal {
        durationHours(at: date) * hourlyCost
    }
}

enum LaborTimerError: LocalizedError {
    case alreadyActive(String)
    case noActiveTimer
    case invalidStopDate

    var errorDescription: String? {
        switch self {
        case .alreadyActive(let jobName):
            return "A timer is already active for \(jobName)."
        case .noActiveTimer:
            return "There is no active timer."
        case .invalidStopDate:
            return "The stop time must be after the start time."
        }
    }
}

@MainActor
final class LaborTimerStore: ObservableObject {
    private static let storageKey = "labor.activeTimerSession"

    @Published private(set) var session: LaborTimerSession?
    private let defaults: UserDefaults

    /// Presentation only. The store tells it what happened *after* the change
    /// is already persisted here, and never reads state back from it.
    private let liveActivity: LaborLiveActivityManaging

    /// The session only if it is still counting.
    ///
    /// A stopped session sitting in review is still `session` — the review
    /// screen needs it — but it is no longer a running timer, and anything
    /// presenting "work in progress" must key off this instead.
    var runningSession: LaborTimerSession? {
        guard let session, session.isRunning else { return nil }
        return session
    }

    /// - Parameter liveActivity: defaults to the no-op so tests, previews and
    ///   UI-test runs cannot put a real activity on a real Lock Screen. The
    ///   app injects the production manager explicitly.
    init(
        defaults: UserDefaults = .standard,
        liveActivity: LaborLiveActivityManaging = NoOpLaborLiveActivityManager()
    ) {
        self.defaults = defaults
        self.liveActivity = liveActivity
        if
            let data = defaults.data(forKey: Self.storageKey),
            let decoded = try? JSONDecoder().decode(LaborTimerSession.self, from: data)
        {
            session = decoded
        }
    }

    /// Re-syncs the Lock Screen with the timer. Called when the app becomes
    /// active; deliberately not called from `init`, because ActivityKit will
    /// not accept a request from a process that is not yet foreground.
    func reconcileLiveActivity() {
        liveActivity.reconcile(runningSession: runningSession)
    }

    func start(jobID: UUID, jobName: String, hourlyCost: Decimal, at date: Date = .now) throws {
        if let session {
            throw LaborTimerError.alreadyActive(session.jobName)
        }

        let started = LaborTimerSession(
            jobID: jobID,
            jobName: jobName,
            startedAt: date,
            hourlyCost: hourlyCost
        )
        session = started
        // Persisted before ActivityKit hears about it: the saved session is
        // what survives a crash, and it must exist before anything presents it.
        persist()
        liveActivity.timerDidStart(started)
    }

    func stop(at date: Date = .now) throws {
        guard var session else { throw LaborTimerError.noActiveTimer }
        guard date >= session.startedAt else { throw LaborTimerError.invalidStopDate }
        session.stoppedAt = date
        self.session = session
        persist()
        // At Stop, not at Confirm. The review step can take as long as the
        // customer likes, and none of it is time on the job.
        liveActivity.timerDidEnd(reason: .timerStopped)
    }

    func updateReview(hourlyCost: Decimal, note: String) throws {
        guard var session else { throw LaborTimerError.noActiveTimer }
        session.hourlyCost = hourlyCost
        session.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
        persist()
    }

    func discard() {
        session = nil
        defaults.removeObject(forKey: Self.storageKey)
        // Idempotent by design: reaching here after `stop()` already took the
        // activity down is a no-op that reports nothing. Discarding a *running*
        // timer, which never passed through `stop()`, ends it here.
        liveActivity.timerDidEnd(reason: .timerDiscarded)
    }

    func finish() {
        discard()
    }

    static func resetForUITesting(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }

    private func persist() {
        guard let session, let data = try? JSONEncoder().encode(session) else {
            defaults.removeObject(forKey: Self.storageKey)
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}
