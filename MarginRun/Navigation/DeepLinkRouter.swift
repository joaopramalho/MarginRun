import Combine
import Foundation

/// The tabs of the root ``ContentView``, named so something other than a tap
/// can select one.
nonisolated enum AppTab: String, Hashable, Sendable, CaseIterable {
    case dashboard
    case history
    case timer
    case insights
    case settings
}

/// An external entry point into MarginRun.
///
/// One case today: the Labor Timer Live Activity. Modelled as an enum anyway
/// so the URL vocabulary lives in one place and a malformed link resolves to
/// `nil` rather than to "whatever the last screen was".
nonisolated enum DeepLink: Equatable, Sendable {
    case laborTimer

    init?(url: URL) {
        guard LaborTimerDeepLink.matches(url) else { return nil }
        self = .laborTimer
    }
}

/// Turns an opened URL into a tab selection, and reports it exactly once.
///
/// Navigation only. The router never starts, stops or reads a timer — opening
/// `marginrun://labor-timer` shows whatever ``LaborTimerStore`` already holds,
/// so a deep link cannot bring a second timer into existence.
@MainActor
final class DeepLinkRouter: ObservableObject {
    /// Bound to the root `TabView`.
    @Published var selectedTab: AppTab = .dashboard

    private let analytics: AnalyticsService
    private let now: () -> Date
    private var lastLaborTimerOpen: Date?

    /// Two opens of the same link inside this window count as one tap.
    ///
    /// `onOpenURL` fires once per open, so this is belt and braces against the
    /// duplicate that matters: a redelivery, or a second handler added later,
    /// turning one tap on the Lock Screen into two `labor_live_activity_opened`
    /// rows. Navigation still happens either way — only the event is collapsed.
    private static let duplicateWindow: TimeInterval = 1.5

    init(analytics: AnalyticsService, now: @escaping () -> Date = { .now }) {
        self.analytics = analytics
        self.now = now
    }

    /// - Returns: whether MarginRun recognised the URL, so an unknown one can
    ///   fall through to the system instead of silently doing nothing.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let link = DeepLink(url: url) else { return false }

        switch link {
        case .laborTimer:
            selectedTab = .timer

            let openedAt = now()
            if
                let lastLaborTimerOpen,
                openedAt.timeIntervalSince(lastLaborTimerOpen) < Self.duplicateWindow
            {
                return true
            }
            lastLaborTimerOpen = openedAt
            analytics.track(.laborLiveActivityOpened(source: .liveActivity))
            return true
        }
    }
}
