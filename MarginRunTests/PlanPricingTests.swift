import Foundation
import Testing
@testable import MarginRun

struct PlanPricingTests {

    @Test func yearlyPlanShowsSavingsAgainstMonthly() {
        // $4.99/mo equivalent against a $7.99 monthly plan is a 38% saving.
        let percent = PlanPricing.savingsPercent(
            monthlyEquivalent: Decimal(string: "4.99")!,
            monthlyReference: Decimal(string: "7.99")!
        )

        #expect(percent == 38)
    }

    @Test func savingsRoundsToNearestWholePercent() {
        let percent = PlanPricing.savingsPercent(
            monthlyEquivalent: Decimal(string: "5.00")!,
            monthlyReference: Decimal(string: "10.00")!
        )

        #expect(percent == 50)
    }

    @Test func noBadgeWhenPlanIsNotCheaper() {
        #expect(
            PlanPricing.savingsPercent(
                monthlyEquivalent: Decimal(string: "9.99")!,
                monthlyReference: Decimal(string: "7.99")!
            ) == nil
        )
    }

    @Test func noBadgeWhenSavingIsTooSmallToBeWorthClaiming() {
        // A 2% saving undersells the plan more than showing nothing.
        #expect(
            PlanPricing.savingsPercent(
                monthlyEquivalent: Decimal(string: "9.79")!,
                monthlyReference: Decimal(string: "9.99")!
            ) == nil
        )
    }

    @Test func nonPositivePricesProduceNoBadge() {
        #expect(PlanPricing.savingsPercent(monthlyEquivalent: 0, monthlyReference: 10) == nil)
        #expect(PlanPricing.savingsPercent(monthlyEquivalent: 5, monthlyReference: 0) == nil)
    }

    @Test func identicalPricesProduceNoBadge() {
        let price = Decimal(string: "9.99")!
        #expect(PlanPricing.savingsPercent(monthlyEquivalent: price, monthlyReference: price) == nil)
    }
}

/// The badge is the one place a price claim is made in words, so what it may
/// and may not say is pinned here.
struct RecommendedBadgeTests {

    @Test func theBadgeNamesBothTheRankAndTheSaving() {
        #expect(PlanPricing.recommendedBadge(savingsPercent: 33) == "BEST VALUE · SAVE 33%")
    }

    /// No saving worth claiming still leaves the plan recommended — it just
    /// stops short of quoting a number the current products don't support.
    @Test func withoutASavingTheBadgeClaimsNoPercentage() {
        let badge = PlanPricing.recommendedBadge(savingsPercent: nil)

        #expect(badge == "BEST VALUE")
        #expect(badge.contains("%") == false)
    }

    @Test func theQuotedPercentageAlwaysComesFromTheLivePrices() {
        let savings = PlanPricing.savingsPercent(
            monthlyEquivalent: Decimal(string: "6.67")!,
            monthlyReference: Decimal(string: "9.99")!
        )

        #expect(PlanPricing.recommendedBadge(savingsPercent: savings) == "BEST VALUE · SAVE 33%")
    }
}
