import Foundation

/// What first-run setup collects, and the rules for committing it.
///
/// Split out from the view so the part that matters — that a skipped field
/// never overwrites a good default, and that a bad number never reaches
/// ``AppPreferences`` — is testable without a UI.
nonisolated struct OnboardingDraft: Equatable {
    var businessName: String = ""
    var trade: ContractorTrade?
    var hourlyCostText: String = ""
    var targetMarginText: String

    /// The margin the app already defaults to, so the field starts pre-filled
    /// with a sensible number rather than empty.
    init(targetMarginText: String = AppPreferences.fallbackTargetMarginText) {
        self.targetMarginText = targetMarginText
    }

    var trimmedBusinessName: String {
        businessName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `nil` when the field is empty or not a positive number. Both mean the
    /// same thing to the app: no default hourly cost yet.
    var hourlyCost: Decimal? {
        guard let value = MoneyInput.parse(hourlyCostText), value > 0 else { return nil }
        return value
    }

    /// Whether the typed hourly cost is unusable *and* non-empty — the only
    /// case worth showing an inline correction for.
    var hasInvalidHourlyCost: Bool {
        !hourlyCostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hourlyCost == nil
    }

    /// A target margin is only accepted when it parses and lands in a range a
    /// contractor could plausibly mean.
    var targetMargin: Decimal? {
        guard
            let value = MoneyInput.parse(targetMarginText),
            value >= 0,
            value < 100
        else { return nil }
        return value
    }

    var hasInvalidTargetMargin: Bool {
        !targetMarginText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && targetMargin == nil
    }

    /// Whether setup may move on. Every field is optional, so the only blocker
    /// is a value that is present and wrong.
    var canFinish: Bool {
        !hasInvalidHourlyCost && !hasInvalidTargetMargin
    }

    /// Whether the contractor changed the margin away from what MarginRun
    /// already suggested. Reported to analytics as a flag, never as a number.
    func changedTargetMargin(from defaultText: String) -> Bool {
        guard let typed = targetMargin, let original = MoneyInput.parse(defaultText) else {
            return false
        }
        return typed != original
    }

    /// Writes the draft into the app's real settings.
    ///
    /// Only fields the contractor actually filled in are written: skipping the
    /// hourly cost leaves whatever was there rather than clearing it, which is
    /// what "This can be skipped" has to mean for someone re-running setup.
    func apply(to preferences: AppPreferences) {
        if !trimmedBusinessName.isEmpty {
            preferences.businessName = trimmedBusinessName
        }
        if let trade {
            preferences.trade = trade
        }
        if let hourlyCost {
            preferences.defaultHourlyCostText = NSDecimalNumber(decimal: hourlyCost).stringValue
        }
        if let targetMargin {
            preferences.defaultTargetMarginText = NSDecimalNumber(decimal: targetMargin).stringValue
        }
    }
}
