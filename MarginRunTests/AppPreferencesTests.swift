import Foundation
import Testing
@testable import MarginRun

@MainActor
struct AppPreferencesTests {
    @Test func storesDefaultsAndPrefillsLaborDraft() throws {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)

        #expect(preferences.defaultTargetMarginText == "30")
        #expect(preferences.defaultHourlyCost == nil)

        preferences.businessName = "Ramalho Contracting"
        preferences.defaultHourlyCostText = "62.50"
        preferences.defaultTargetMarginText = "28"

        let restored = AppPreferences(defaults: defaults)
        let laborDraft = AddLaborDraft(defaultHourlyCostText: restored.defaultHourlyCostText)

        #expect(restored.businessName == "Ramalho Contracting")
        #expect(restored.defaultHourlyCost == Decimal(string: "62.50"))
        #expect(restored.defaultTargetMargin == 28)
        #expect(laborDraft.hourlyCostText == "62.50")
    }
}
