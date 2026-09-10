import Combine
import Foundation

/// Ambient state attached to every event.
///
/// Read from the app's existing sources of truth at send time — RevenueCat for
/// the entitlement, SwiftData for the job counts — so analytics never keeps a
/// second copy of anything, least of all subscription state.
nonisolated struct AnalyticsContext: Equatable, Sendable {
    var isPro = false
    var activeJobCount = 0
    var totalJobCount = 0
    var completedJobCount = 0
    var onboardingCompleted = false
    var trade: ContractorTrade?

    static let empty = AnalyticsContext()
}

/// The only analytics entry point in the app.
///
/// Features call `analytics.track(.firstThing(...))` with a typed event and
/// never touch a vendor SDK, a string name, or a network call. Three guarantees
/// hold at this boundary:
///
/// - **Nothing private leaves.** ``AnalyticsEvent`` has no case that can carry
///   user-entered text or a dollar amount; see its file comment.
/// - **Nothing blocks.** ``AnalyticsBackend/record(_:)`` cannot throw and is
///   contractually non-blocking, and every call here is wrapped so a
///   misbehaving backend still cannot take a financial code path down with it.
/// - **First-time milestones are automatic.** A call site logs `job_created`;
///   this type decides whether that was also `first_job_created`.
@MainActor
final class AnalyticsService: ObservableObject {
    private let backend: AnalyticsBackend
    private let milestones: AnalyticsMilestones
    private let now: () -> Date

    /// Ambient state attached to every event.
    ///
    /// `ContentView` refreshes this whenever the entitlement or the job list
    /// changes, reading from RevenueCat and SwiftData. It is a cache of those
    /// sources, never a second source of truth: nothing in the app makes a
    /// decision from it.
    var context: AnalyticsContext = .empty

    init(
        backend: AnalyticsBackend = OSLogAnalyticsBackend(),
        milestones: AnalyticsMilestones = AnalyticsMilestones(),
        now: @escaping () -> Date = { .now }
    ) {
        self.backend = backend
        self.milestones = milestones
        self.now = now
    }

    /// Records `event`, plus its once-per-install companion the first time.
    func track(_ event: AnalyticsEvent) {
        if let firstTimeName = event.firstTimeName, milestones.markFirstTime(firstTimeName) {
            // The milestone leads, so a funnel query reading events in order
            // sees "first" before the recurring event that produced it.
            emit(name: firstTimeName, properties: event.properties)
        }
        emit(name: event.name, properties: event.properties)
    }

    /// Records `app_first_open`, exactly once per install.
    ///
    /// Also stamps the install date, which is the denominator for every
    /// "time to first job / first cost / first paywall" question later.
    func trackAppOpen() {
        guard milestones.markFirstOpenIfNeeded(now: now()) else { return }
        track(.appFirstOpen)
    }

    // MARK: - Persisted domain actions

    /// These helpers are called only after the matching SwiftData save
    /// succeeds. Keeping the event construction here makes the behavior easy
    /// to test without coupling a view test to a live analytics provider.
    func trackJobCreated(source: JobCreationSource, financials: JobFinancials) {
        track(.jobCreated(
            source: source,
            hasCostEstimate: financials.estimatedTotalCost > 0,
            meetsTargetMargin: !financials.isExpectedMarginBelowTarget
        ))
    }

    func trackExpenseAdded(
        category: ExpenseCategory,
        hasReceipt: Bool,
        source: ExpenseCreationSource
    ) {
        track(.expenseAdded(category: category, hasReceipt: hasReceipt, source: source))
    }

    func trackLaborAdded(source: LaborEntrySource) {
        track(.laborAdded(source: source))
    }

    func trackJobCompleted(report: JobCompletionReport) {
        track(.jobCompleted(
            metTargetMargin: !report.isBelowTargetMargin,
            beatExpectedProfit: report.profitVariance >= 0
        ))
    }

    // MARK: - Emission

    private func emit(name: String, properties: [String: AnalyticsValue]) {
        let payload = AnalyticsPayload(
            name: name,
            properties: properties.merging(ambientProperties()) { specific, _ in specific },
            timestamp: now()
        )
        backend.record(payload)
    }

    /// Attached to every event so any milestone can be sliced by entitlement,
    /// account size and install age without a join.
    private func ambientProperties() -> [String: AnalyticsValue] {
        var properties: [String: AnalyticsValue] = [
            "is_pro": .bool(context.isPro),
            "active_job_count": .int(context.activeJobCount),
            "job_count_bucket": .string(AnalyticsBucket.jobCount(context.totalJobCount)),
            "completed_job_count_bucket": .string(
                AnalyticsBucket.jobCount(context.completedJobCount)
            ),
            "onboarding_completed": .bool(context.onboardingCompleted),
        ]

        if let trade = context.trade {
            properties["trade"] = .string(trade.rawValue)
        }

        if let days = milestones.daysSinceFirstOpen(now: now()) {
            properties["days_since_first_open_bucket"] =
                .string(AnalyticsBucket.daysSinceFirstOpen(days))
        }

        return properties
    }
}
