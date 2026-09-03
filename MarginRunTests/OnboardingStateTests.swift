import Foundation
import Testing
@testable import MarginRun

/// Onboarding shows once, and never to someone who has already been using the
/// app. Both halves of that are easy to break in a way no build error catches.
@MainActor
struct OnboardingStateTests {

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "OnboardingStateTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    @Test func freshInstallHasNotCompletedOnboarding() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(OnboardingState(defaults: defaults).isCompleted == false)
    }

    @Test func completionPersistsAcrossReads() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        OnboardingState(defaults: defaults).isCompleted = true

        #expect(OnboardingState(defaults: defaults).isCompleted)
    }

    @Test func emptyInstallIsStillOfferedOnboarding() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = OnboardingState(defaults: defaults)
        let migrated = state.completeIfInstallHasExistingData(
            jobCount: 0,
            preferences: AppPreferences(defaults: defaults)
        )

        #expect(migrated == false)
        #expect(state.isCompleted == false)
    }

    /// The upgrade case: a contractor with jobs must never be interrupted to be
    /// asked their trade.
    @Test func installWithJobsIsTreatedAsAlreadyOnboarded() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = OnboardingState(defaults: defaults)
        let migrated = state.completeIfInstallHasExistingData(
            jobCount: 3,
            preferences: AppPreferences(defaults: defaults)
        )

        #expect(migrated)
        #expect(state.isCompleted)
    }

    @Test func installWithSavedDefaultsIsTreatedAsAlreadyOnboarded() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = AppPreferences(defaults: defaults)
        preferences.defaultHourlyCostText = "55"

        #expect(OnboardingState(defaults: defaults)
            .completeIfInstallHasExistingData(jobCount: 0, preferences: preferences))
    }

    @Test func namedBusinessCountsAsExistingData() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = AppPreferences(defaults: defaults)
        preferences.businessName = "Johnson Remodeling"

        #expect(OnboardingState.hasMeaningfulData(jobCount: 0, preferences: preferences))
    }

    @Test func whitespaceBusinessNameIsNotExistingData() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = AppPreferences(defaults: defaults)
        preferences.businessName = "   "

        #expect(OnboardingState.hasMeaningfulData(jobCount: 0, preferences: preferences) == false)
    }

    /// Migration must not undo a completion, and must not re-run once decided.
    @Test func migrationIsAOneWayDoor() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = OnboardingState(defaults: defaults)
        state.isCompleted = true

        let migrated = state.completeIfInstallHasExistingData(
            jobCount: 0,
            preferences: AppPreferences(defaults: defaults)
        )

        #expect(migrated == false, "already-complete installs are left alone")
        #expect(state.isCompleted)
    }

    @Test func resetForUITestingClearsCompletion() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = OnboardingState(defaults: defaults)
        state.isCompleted = true
        state.resetForUITesting()

        #expect(state.isCompleted == false)
    }
}
