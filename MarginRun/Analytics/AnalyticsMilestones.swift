import Foundation

nonisolated enum AnalyticsStorageKeys {
    static let firstOpenDate = "analytics.firstOpenDate"
    static let firedMilestones = "analytics.firedMilestones"
}

/// The once-per-install facts the funnel needs.
///
/// Two jobs only: remember when this install was first opened, so every "time
/// to first X" question has a denominator, and remember which `first_*` events
/// have already fired, so `first_job_created` means what it says on a device
/// that has created forty jobs.
///
/// Nothing here identifies a person — it is a date and a set of event names.
nonisolated struct AnalyticsMilestones {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// When this install was first opened, or `nil` before the first launch is
    /// recorded.
    var firstOpenDate: Date? {
        let interval = defaults.double(forKey: AnalyticsStorageKeys.firstOpenDate)
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    /// Stamps the first-open date if it is not already set.
    ///
    /// - Returns: `true` when this launch is genuinely the first one, which is
    ///   the only time `app_first_open` may be sent.
    @discardableResult
    func markFirstOpenIfNeeded(now: Date = .now) -> Bool {
        guard firstOpenDate == nil else { return false }
        defaults.set(now.timeIntervalSince1970, forKey: AnalyticsStorageKeys.firstOpenDate)
        return true
    }

    /// Whole days between the first open and `now`, or `nil` if the install has
    /// never been stamped.
    func daysSinceFirstOpen(now: Date = .now) -> Int? {
        guard let firstOpenDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: firstOpenDate, to: now).day
        return max(0, days ?? 0)
    }

    /// Records that `name` has now happened once.
    ///
    /// - Returns: `true` the first time it is called for a given name, `false`
    ///   forever after.
    @discardableResult
    func markFirstTime(_ name: String) -> Bool {
        var fired = Set(defaults.stringArray(forKey: AnalyticsStorageKeys.firedMilestones) ?? [])
        guard fired.insert(name).inserted else { return false }
        defaults.set(Array(fired).sorted(), forKey: AnalyticsStorageKeys.firedMilestones)
        return true
    }

    func hasFired(_ name: String) -> Bool {
        Set(defaults.stringArray(forKey: AnalyticsStorageKeys.firedMilestones) ?? []).contains(name)
    }

    func resetForUITesting() {
        defaults.removeObject(forKey: AnalyticsStorageKeys.firstOpenDate)
        defaults.removeObject(forKey: AnalyticsStorageKeys.firedMilestones)
    }
}
