import Foundation

nonisolated enum MoneyInput {
    /// Parses a money or percent field.
    /// Empty or whitespace becomes `0`. Invalid text returns `nil`.
    static func parse(_ text: String, locale: Locale = .autoupdatingCurrent) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }

        // Existing drafts and preferences store a canonical dot-decimal value.
        // Recognize the whole string before asking a locale parser, whose
        // permissive APIs can otherwise read `7.5` as `7` in a comma locale.
        if isCanonicalDecimal(trimmed) {
            return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
        }

        // Blurred currency fields include the locale's symbol and grouping.
        // NumberFormatter returns an NSDecimalNumber here; no Double enters the
        // financial model.
        let currency = NumberFormatter()
        currency.numberStyle = .currency
        currency.locale = locale
        currency.isLenient = true
        if let value = currency.number(from: trimmed) {
            return value.decimalValue
        }

        let decimal = NumberFormatter()
        decimal.numberStyle = .decimal
        decimal.locale = locale
        decimal.isLenient = false
        return decimal.number(from: trimmed)?.decimalValue
    }

    /// Locale-aware display used only while a field is not being edited.
    static func displayText(_ text: String, locale: Locale = .autoupdatingCurrent) -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let value = parse(text, locale: locale) else { return text }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = locale.currency?.identifier ?? "USD"
        formatter.minimumFractionDigits = value == value.roundedToWhole ? 0 : formatter.minimumFractionDigits
        formatter.maximumFractionDigits = max(formatter.maximumFractionDigits, value.fractionDigitCount)
        return formatter.string(from: value as NSDecimalNumber) ?? text
    }

    /// Plain localized numeric text restored when editing begins, so the
    /// symbol and grouping never fight cursor movement or deletion.
    static func editingText(_ text: String, locale: Locale = .autoupdatingCurrent) -> String {
        guard let value = parse(text, locale: locale) else { return text }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = max(16, value.fractionDigitCount)
        return formatter.string(from: value as NSDecimalNumber) ?? text
    }

    private static func isCanonicalDecimal(_ text: String) -> Bool {
        var body = text[...]
        if body.first == "+" || body.first == "-" { body = body.dropFirst() }
        guard !body.isEmpty else { return false }

        let pieces = body.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 2, pieces.allSatisfy({ !$0.isEmpty }) else { return false }
        return pieces.allSatisfy { piece in piece.allSatisfy(\.isNumber) }
    }
}

private extension Decimal {
    nonisolated var roundedToWhole: Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, 0, .plain)
        return result
    }

    nonisolated var fractionDigitCount: Int {
        let canonical = NSDecimalNumber(decimal: self).stringValue
        guard let separator = canonical.firstIndex(of: ".") else { return 0 }
        return canonical.distance(from: canonical.index(after: separator), to: canonical.endIndex)
    }
}
