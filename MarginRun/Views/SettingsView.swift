import SwiftUI

struct SettingsView: View {
    // The same keys onboarding writes. Setup collects these once; Settings is
    // where they are edited afterwards — one stored value each, no second copy.
    @AppStorage(AppPreferenceKeys.businessName) private var businessName = ""
    @AppStorage(AppPreferenceKeys.defaultHourlyCost) private var hourlyCostText = ""
    @AppStorage(AppPreferenceKeys.defaultTargetMargin) private var targetMarginText = AppPreferences.fallbackTargetMarginText
    @AppStorage(AppPreferenceKeys.trade) private var tradeRawValue = ""

    private var trade: Binding<ContractorTrade?> {
        Binding(
            get: { ContractorTrade(rawValue: tradeRawValue) },
            set: { tradeRawValue = $0?.rawValue ?? "" }
        )
    }

    var body: some View {
        Form {
            Section {
                TextField("Business name", text: $businessName)
                    .textContentType(.organizationName)
                    .accessibilityIdentifier("settingsBusinessNameField")

                Picker("Trade", selection: trade) {
                    Text("Not set").tag(ContractorTrade?.none)
                    ForEach(ContractorTrade.allCases) { option in
                        Text(option.title).tag(ContractorTrade?.some(option))
                    }
                }
                .accessibilityIdentifier("settingsTradePicker")

                HStack {
                    Text("Default hourly cost")
                    Spacer()
                    CurrencyTextField(
                        title: "0.00",
                        text: $hourlyCostText,
                        alignment: .trailing,
                        maxWidth: 140,
                        accessibilityLabel: "Default hourly cost",
                        accessibilityIdentifier: "settingsHourlyCostField"
                    )
                }

                HStack {
                    Text("Target margin default")
                    Spacer()
                    TextField("30", text: $targetMarginText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                        .accessibilityLabel("Target margin default")
                        .accessibilityIdentifier("settingsTargetMarginField")
                    Text("%")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Defaults prefill new jobs and labor entries. You can still edit them before saving. Trade is used for labelling only — it never changes your numbers.")
            }

            SubscriptionSettingsSection()
        }
        .keyboardEscapes()
        .navigationTitle("Settings")
    }
}

#Preview("Settings — Free") {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(SubscriptionStore(entitlementOverride: false))
}

#Preview("Settings — Pro") {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(SubscriptionStore(entitlementOverride: true))
}
