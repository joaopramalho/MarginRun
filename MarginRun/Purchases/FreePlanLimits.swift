import Foundation

/// What the free tier allows.
///
/// Free has to stay genuinely useful: a contractor can run real jobs, log real
/// costs, and read their own history without paying. Pro sells the capabilities
/// that save time and protect margin — never access to work already recorded.
nonisolated enum FreePlanLimits {

    /// Active jobs a free account may run at once. Completed jobs never count,
    /// so finishing work always frees a slot rather than forcing an upgrade.
    static let maxActiveJobs = 2

    /// Whether another active job may be created.
    static func canCreateActiveJob(isPro: Bool, activeJobCount: Int) -> Bool {
        if isPro { return true }
        return activeJobCount < maxActiveJobs
    }
}
