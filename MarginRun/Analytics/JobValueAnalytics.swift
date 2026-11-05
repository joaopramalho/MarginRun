import Foundation

/// Coarse, anonymous financial context for aggregate product analytics.
///
/// The exact amount remains in the job model. This type can carry only a broad
/// range and a heavily rounded whole number, which keeps event construction
/// from accidentally attaching the source value to PostHog.
nonisolated struct JobValueAnalytics: Equatable, Sendable {
    enum Bucket: String, CaseIterable, Sendable {
        case under1K = "under_1k"
        case oneTo5K = "1k_5k"
        case fiveTo10K = "5k_10k"
        case tenTo25K = "10k_25k"
        case twentyFiveTo50K = "25k_50k"
        case fiftyTo100K = "50k_100k"
        case hundredKPlus = "100k_plus"
    }

    let currency: String
    let bucket: Bucket
    let roundedValue: Int

    init(value: Decimal, currency: String) {
        self.currency = Self.normalizedCurrency(currency)
        bucket = Self.bucket(for: value)
        roundedValue = Self.roundedValue(for: value)
    }

    /// The app's money fields follow the device currency. `XXX` is the ISO 4217
    /// code for no currency, and is safer than silently labelling an unknown
    /// value as USD.
    static func currencyCode(locale: Locale = .autoupdatingCurrent) -> String {
        normalizedCurrency(locale.currency?.identifier ?? "XXX")
    }

    static func bucket(for value: Decimal) -> Bucket {
        let value = max(0, value)
        if value < 1_000 { return .under1K }
        if value < 5_000 { return .oneTo5K }
        if value < 10_000 { return .fiveTo10K }
        if value < 25_000 { return .tenTo25K }
        if value < 50_000 { return .twentyFiveTo50K }
        if value < 100_000 { return .fiftyTo100K }
        return .hundredKPlus
    }

    /// Values below 1k contribute zero to the approximate sum. This deliberately
    /// avoids turning a very small job into a 1k job and provides stronger
    /// privacy at the low end. Larger values round deterministically to the
    /// nearest 1k using decimal, half-up rounding.
    static func roundedValue(for value: Decimal) -> Int {
        let value = max(0, value)
        guard value >= 1_000 else { return 0 }

        var thousands = value / 1_000
        var roundedThousands = Decimal()
        NSDecimalRound(&roundedThousands, &thousands, 0, .plain)
        let rounded = roundedThousands * 1_000

        guard rounded < Decimal(Int.max) else { return Int.max }
        return NSDecimalNumber(decimal: rounded).intValue
    }

    private static func normalizedCurrency(_ currency: String) -> String {
        let normalized = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? "XXX" : normalized
    }
}
