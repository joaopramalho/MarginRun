import Foundation

nonisolated enum OnboardingStorageKeys {
    static let completed = "onboarding.completed"
}

/// Whether first-run setup has been dealt with.
///
/// Deliberately one boolean in `UserDefaults`, read by `ContentView` through
/// `@AppStorage` and written here. The business name, hourly cost and target
/// margin that onboarding collects are *not* stored here — they go straight to
/// ``AppPreferences``, which Settings already owns, so there is one source of
/// truth per value rather than an onboarding copy that drifts.
nonisolated struct OnboardingState {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isCompleted: Bool {
        get { defaults.bool(forKey: OnboardingStorageKeys.completed) }
        nonmutating set { defaults.set(newValue, forKey: OnboardingStorageKeys.completed) }
    }

    /// Treats an install that already holds real work as onboarded.
    ///
    /// Someone updating from a build that predates onboarding has never seen
    /// the flag, and interrupting a contractor mid-season to ask their trade is
    /// the worst possible upgrade experience. Any existing job — or a default
    /// they took the trouble to set — is proof enough that setup happened.
    ///
    /// - Returns: `true` if this call marked onboarding complete.
    @discardableResult
    func completeIfInstallHasExistingData(
        jobCount: Int,
        preferences: AppPreferences
    ) -> Bool {
        guard !isCompleted else { return false }
        guard Self.hasMeaningfulData(jobCount: jobCount, preferences: preferences) else {
            return false
        }
        isCompleted = true
        return true
    }

    /// What counts as "this install has been used".
    static func hasMeaningfulData(jobCount: Int, preferences: AppPreferences) -> Bool {
        if jobCount > 0 { return true }
        if !preferences.businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if preferences.defaultHourlyCost != nil { return true }
        return false
    }

    func resetForUITesting() {
        defaults.removeObject(forKey: OnboardingStorageKeys.completed)
    }
}
