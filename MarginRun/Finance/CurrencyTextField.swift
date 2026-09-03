import SwiftUI

/// A money field that stays plain while typing and becomes locale-aware on
/// blur. The bound value remains text because drafts already validate through
/// `MoneyInput`; parsing and every downstream calculation stay Decimal-based.
struct CurrencyTextField: View {
    let title: String
    @Binding var text: String
    var alignment: TextAlignment = .leading
    var maxWidth: CGFloat? = nil
    var accessibilityLabel: String? = nil
    var accessibilityIdentifier: String? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(alignment)
            .frame(maxWidth: maxWidth)
            .monospacedDigit()
            .focused($isFocused)
            .onAppear { formatForDisplay() }
            .onChange(of: isFocused) { _, focused in
                text = focused ? MoneyInput.editingText(text) : MoneyInput.displayText(text)
            }
            .accessibilityLabel(accessibilityLabel ?? title)
            .accessibilityIdentifier(accessibilityIdentifier ?? title)
    }

    private func formatForDisplay() {
        guard !isFocused else { return }
        text = MoneyInput.displayText(text)
    }
}
