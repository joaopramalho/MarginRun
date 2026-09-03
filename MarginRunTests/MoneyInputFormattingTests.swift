import Foundation
import Testing
@testable import MarginRun

struct MoneyInputFormattingTests {
    private let us = Locale(identifier: "en_US")

    @Test func wholeMoneyFormatsWithCurrencyAndGroupingOnBlur() {
        #expect(MoneyInput.displayText("18400", locale: us) == "$18,400")
    }

    @Test func currencyDisplayReturnsToUnformattedDecimalEditingText() {
        #expect(MoneyInput.editingText("$18,400", locale: us) == "18400")
    }

    @Test func formattedInputStillParsesAsDecimalWithoutLosingCents() {
        #expect(MoneyInput.parse("$6,200.45", locale: us) == Decimal(string: "6200.45"))
    }

    // MARK: - Prose formatting

    /// Used in copy rather than in a ledger, so the cents come off.
    @Test func wholeUnitsDropsTheCents() {
        #expect(MoneyFormat.wholeUnits(18_000, locale: us) == "$18,000")
        #expect(MoneyFormat.wholeUnits(Decimal(string: "18000.49")!, locale: us) == "$18,000")
        #expect(MoneyFormat.wholeUnits(0, locale: us) == "$0")
    }

    /// The article has to follow how the amount is *spoken*, or the sentence
    /// reads wrong for every job that is not eighteen thousand dollars.
    @Test func theArticleMatchesHowTheAmountIsRead() {
        for amount in [Decimal(8), 80, 800, 8_000, 85_000, 11, 11_000, 18, 18_000, 18_000_000] {
            #expect(MoneyFormat.article(for: amount) == "an", "\(amount) should take \"an\"")
        }

        // "one hundred eighty", "one thousand eight hundred", "one hundred
        // eighty thousand" — all consonant-initial despite the 8 and 18 inside.
        for amount in [Decimal(5), 180, 1_800, 180_000, 110, 1_100, 5_000, 0] {
            #expect(MoneyFormat.article(for: amount) == "a", "\(amount) should take \"a\"")
        }
    }
}
