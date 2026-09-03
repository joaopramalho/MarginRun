import Foundation

nonisolated enum AppPreferenceKeys {
    static let businessName = "settings.businessName"
    static let defaultHourlyCost = "settings.defaultHourlyCost"
    static let defaultTargetMargin = "settings.defaultTargetMargin"
    static let trade = "settings.trade"
    static let marginNotificationsEnabled = "settings.marginNotificationsEnabled"
}

nonisolated struct AppPreferences {
    static let fallbackTargetMarginText = "30"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var businessName: String {
        get { defaults.string(forKey: AppPreferenceKeys.businessName) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: AppPreferenceKeys.businessName) }
    }

    var defaultHourlyCostText: String {
        get { defaults.string(forKey: AppPreferenceKeys.defaultHourlyCost) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: AppPreferenceKeys.defaultHourlyCost) }
    }

    var defaultTargetMarginText: String {
        get {
            defaults.string(forKey: AppPreferenceKeys.defaultTargetMargin)
                ?? Self.fallbackTargetMarginText
        }
        nonmutating set { defaults.set(newValue, forKey: AppPreferenceKeys.defaultTargetMargin) }
    }

    /// What the contractor does.
    ///
    /// Metadata only — no financial calculation reads it. Onboarding collects
    /// it and Settings edits it; both write here, so there is no second copy.
    var trade: ContractorTrade? {
        get {
            guard let raw = defaults.string(forKey: AppPreferenceKeys.trade) else { return nil }
            return ContractorTrade(rawValue: raw)
        }
        nonmutating set {
            guard let newValue else {
                defaults.removeObject(forKey: AppPreferenceKeys.trade)
                return
            }
            defaults.set(newValue.rawValue, forKey: AppPreferenceKeys.trade)
        }
    }

    var defaultHourlyCost: Decimal? {
        guard let value = MoneyInput.parse(defaultHourlyCostText), value > 0 else { return nil }
        return value
    }

    var defaultTargetMargin: Decimal {
        guard let value = MoneyInput.parse(defaultTargetMarginText), value >= 0 else {
            return Decimal(string: Self.fallbackTargetMarginText)!
        }
        return value
    }

    func resetForUITesting() {
        defaults.removeObject(forKey: AppPreferenceKeys.businessName)
        defaults.removeObject(forKey: AppPreferenceKeys.defaultHourlyCost)
        defaults.removeObject(forKey: AppPreferenceKeys.defaultTargetMargin)
        defaults.removeObject(forKey: AppPreferenceKeys.marginNotificationsEnabled)
        defaults.removeObject(forKey: AppPreferenceKeys.trade)
    }
}
