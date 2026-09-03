import Foundation

/// Presentation-scoped guard used by the paywall's `@State`.
/// SwiftUI may re-run body and tasks; one reporter instance emits once.
@MainActor
struct PaywallAnalyticsReporter {
    private(set) var didReport = false

    mutating func reportIfNeeded(feature: ProFeature?, analytics: AnalyticsService) {
        guard !didReport else { return }
        didReport = true
        analytics.track(.paywallViewed(feature: feature))
    }
}
