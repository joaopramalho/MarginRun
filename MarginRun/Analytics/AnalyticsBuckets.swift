import Foundation

/// Turns raw counts into the coarse buckets the funnel is analysed on.
///
/// Buckets rather than raw values for two reasons: the questions we actually
/// ask ("do people with more jobs convert better?") are answered at this
/// resolution, and a low-cardinality property cannot be joined back to an
/// individual contractor's book of work.
nonisolated enum AnalyticsBucket {

    /// How many jobs the account holds, as a band.
    static func jobCount(_ count: Int) -> String {
        switch count {
        case ..<0: "0"
        case 0: "0"
        case 1: "1"
        case 2: "2"
        case 3...5: "3-5"
        case 6...10: "6-10"
        default: "11+"
        }
    }

    /// Age of the install, as a band. The denominator for every "time to X"
    /// activation metric.
    static func daysSinceFirstOpen(_ days: Int) -> String {
        switch days {
        case ..<0: "0"
        case 0: "0"
        case 1: "1"
        case 2...3: "2-3"
        case 4...7: "4-7"
        case 8...30: "8-30"
        default: "31+"
        }
    }

    /// Length of a tracked labor session, as a band. Never the exact duration,
    /// which combined with a rate would reconstruct a cost.
    static func laborDuration(hours: Decimal) -> String {
        let minutes = NSDecimalNumber(decimal: hours * 60).doubleValue
        if minutes < 15 { return "under-15m" }
        if minutes < 60 { return "15-60m" }
        if minutes < 240 { return "1-4h" }
        if minutes < 480 { return "4-8h" }
        return "8h+"
    }
}
