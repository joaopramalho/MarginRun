import Foundation

nonisolated enum MoneyFormat {
    static func usd(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .autoupdatingCurrent
        formatter.currencyCode = formatter.locale.currency?.identifier ?? "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "—"
    }

    /// The same currency, rounded to whole units.
    ///
    /// For prose. `"$18,000.00 of work"` puts two zeros in a sentence that is
    /// making a point about scale, not about a balance; `"$18,000"` reads the
    /// way a contractor would say it. Ledger figures keep using ``usd(_:)``.
    static func wholeUnits(_ value: Decimal, locale: Locale = .autoupdatingCurrent) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = locale.currency?.identifier ?? "USD"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: value as NSDecimalNumber) ?? "—"
    }

    /// `"a"` or `"an"` for an amount that is about to be read aloud.
    ///
    /// Copy that says "a $18,000 job" is wrong out loud, and hard-coding "an"
    /// only moves the error to "an $5,000 job". The article follows the first
    /// word the number is spoken as, which is vowel-initial in exactly two
    /// cases: anything starting with eight or eighty, and eleven or eighteen
    /// when those two digits are a whole spoken group — 18, 18,000, 18,000,000,
    /// but not 180 ("one hundred eighty") or 1,800 ("one thousand eight
    /// hundred").
    static func article(for value: Decimal) -> String {
        var input = abs(value)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .plain)

        let digits = NSDecimalNumber(decimal: rounded).stringValue
        guard let first = digits.first else { return "a" }
        if first == "8" { return "an" }

        let leadingGroupIsWholeTens = digits.count % 3 == 2
        let leadingPair = digits.prefix(2)
        if leadingGroupIsWholeTens, leadingPair == "11" || leadingPair == "18" { return "an" }

        return "a"
    }

    /// Formats a ratio such as `0.361` as `"36.1%"`.
    static func percent(ratio: Decimal?) -> String {
        guard let ratio else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.locale = Locale(identifier: "en_US")
        let formatted = formatter.string(from: (ratio * 100) as NSDecimalNumber) ?? "—"
        return "\(formatted)%"
    }

    static func roundedPercent(_ ratio: Decimal) -> Decimal {
        var value = ratio * 100
        var result = Decimal()
        NSDecimalRound(&result, &value, 1, .plain)
        return result
    }
}
