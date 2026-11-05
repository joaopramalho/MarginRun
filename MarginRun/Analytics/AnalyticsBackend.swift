import Foundation
import OSLog

/// A single value attached to an analytics event.
///
/// Deliberately narrow: strings, whole numbers and flags cover every property
/// MarginRun sends. Financial analytics is admitted only after a source value
/// has been coarsely rounded by ``JobValueAnalytics``; free-form customer and
/// job content has no representation here.
nonisolated enum AnalyticsValue: Equatable, Sendable, CustomStringConvertible {
    case string(String)
    case int(Int)
    case bool(Bool)

    var description: String {
        switch self {
        case .string(let value): value
        case .int(let value): String(value)
        case .bool(let value): value ? "true" : "false"
        }
    }
}

/// One event, ready to leave the app.
nonisolated struct AnalyticsPayload: Equatable, Sendable {
    let name: String
    let properties: [String: AnalyticsValue]
    let timestamp: Date

    init(name: String, properties: [String: AnalyticsValue], timestamp: Date = .now) {
        self.name = name
        self.properties = properties
        self.timestamp = timestamp
    }
}

/// A destination for analytics events.
///
/// The whole app talks to this one protocol and never to a vendor SDK, so
/// changing provider is a new conformance plus a one-line swap in
/// ``AnalyticsService`` — not an edit to every call site.
///
/// - Important: `record` is called on the main actor and **must not block**.
///   Conformances are expected to enqueue and flush elsewhere, exactly as the
///   mainstream product-analytics SDKs do. The signature cannot throw, so a
///   backend has no way to push a failure back into the UI or into a financial
///   code path.
nonisolated protocol AnalyticsBackend: Sendable {
    func record(_ payload: AnalyticsPayload)
}

/// Drops everything. The default for UI tests, where no event should escape.
nonisolated struct NoOpAnalyticsBackend: AnalyticsBackend {
    func record(_ payload: AnalyticsPayload) {}
}

/// Writes events to the unified log.
///
/// The honest default until a provider is chosen: the funnel is fully
/// instrumented and inspectable in Console.app, and no third party receives
/// anything. Swapping in a vendor means writing one more conformance.
nonisolated struct OSLogAnalyticsBackend: AnalyticsBackend {
    private let logger = Logger(subsystem: "app.marginrun", category: "analytics")

    func record(_ payload: AnalyticsPayload) {
        let properties = payload.properties
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.description)" }
            .joined(separator: " ")
        logger.log("event=\(payload.name, privacy: .public) \(properties, privacy: .public)")
    }
}

/// Keeps every event in memory. For tests and previews.
///
/// Thread-safe because ``AnalyticsBackend`` is `Sendable` and a conformance may
/// legitimately be handed to a background flush, even though MarginRun only
/// records from the main actor today.
nonisolated final class RecordingAnalyticsBackend: AnalyticsBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [AnalyticsPayload] = []

    init() {}

    var recorded: [AnalyticsPayload] {
        lock.withLock { storage }
    }

    var recordedNames: [String] {
        recorded.map(\.name)
    }

    func properties(for name: String) -> [String: AnalyticsValue]? {
        recorded.first { $0.name == name }?.properties
    }

    func record(_ payload: AnalyticsPayload) {
        lock.withLock { storage.append(payload) }
    }

    func reset() {
        lock.withLock { storage.removeAll() }
    }
}
