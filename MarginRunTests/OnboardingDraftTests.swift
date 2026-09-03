import Foundation
import Testing
@testable import MarginRun

/// Every field in setup is optional, so the rules that matter are about what
/// happens when one is left blank or filled in wrongly.
@MainActor
struct OnboardingDraftTests {

    private func makePreferences() throws -> (AppPreferences, UserDefaults, String) {
        let suiteName = "OnboardingDraftTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (AppPreferences(defaults: defaults), defaults, suiteName)
    }

    @Test func startsFromTheMarginTheAppAlreadySuggests() {
        #expect(OnboardingDraft().targetMarginText == AppPreferences.fallbackTargetMarginText)
    }

    @Test func anEmptyDraftCanStillFinish() {
        let draft = OnboardingDraft()

        #expect(draft.canFinish)
        #expect(draft.hourlyCost == nil)
    }

    @Test func aNonNumericHourlyCostBlocksFinishing() {
        var draft = OnboardingDraft()
        draft.hourlyCostText = "forty five"

        #expect(draft.hasInvalidHourlyCost)
        #expect(draft.canFinish == false)
    }

    @Test func zeroIsNotAnHourlyCost() {
        var draft = OnboardingDraft()
        draft.hourlyCostText = "0"

        #expect(draft.hourlyCost == nil)
        #expect(draft.hasInvalidHourlyCost)
    }

    @Test func targetMarginMustBeAPercentage() {
        var draft = OnboardingDraft()

        draft.targetMarginText = "120"
        #expect(draft.targetMargin == nil)
        #expect(draft.canFinish == false)

        draft.targetMarginText = "35"
        #expect(draft.targetMargin == 35)
        #expect(draft.canFinish)
    }

    @Test func writesFilledFieldsIntoSettings() throws {
        let (preferences, defaults, suite) = try makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }

        var draft = OnboardingDraft()
        draft.businessName = "  Johnson Remodeling  "
        draft.trade = .remodeling
        draft.hourlyCostText = "62.50"
        draft.targetMarginText = "28"
        draft.apply(to: preferences)

        #expect(preferences.businessName == "Johnson Remodeling")
        #expect(preferences.trade == .remodeling)
        #expect(preferences.defaultHourlyCost == Decimal(string: "62.50"))
        #expect(preferences.defaultTargetMargin == 28)
    }

    /// "This can be skipped" has to mean the existing value survives, or
    /// re-running setup would quietly wipe a contractor's rate.
    @Test func skippedFieldsLeaveExistingSettingsAlone() throws {
        let (preferences, defaults, suite) = try makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }

        preferences.businessName = "Existing Co"
        preferences.defaultHourlyCostText = "80"
        preferences.trade = .roofing

        OnboardingDraft().apply(to: preferences)

        #expect(preferences.businessName == "Existing Co")
        #expect(preferences.defaultHourlyCost == 80)
        #expect(preferences.trade == .roofing)
    }

    @Test func anInvalidHourlyCostIsNeverWritten() throws {
        let (preferences, defaults, suite) = try makePreferences()
        defer { defaults.removePersistentDomain(forName: suite) }

        var draft = OnboardingDraft()
        draft.hourlyCostText = "abc"
        draft.apply(to: preferences)

        #expect(preferences.defaultHourlyCost == nil)
    }

    @Test func reportsWhetherTheSuggestedMarginWasChanged() {
        var draft = OnboardingDraft(targetMarginText: "30")
        #expect(draft.changedTargetMargin(from: "30") == false)

        draft.targetMarginText = "40"
        #expect(draft.changedTargetMargin(from: "30"))
    }

    @Test func everyTradeHasATitle() {
        for trade in ContractorTrade.allCases {
            #expect(!trade.title.isEmpty, "missing title for \(trade.rawValue)")
        }
        #expect(Set(ContractorTrade.allCases.map(\.title)).count == ContractorTrade.allCases.count)
    }
}
