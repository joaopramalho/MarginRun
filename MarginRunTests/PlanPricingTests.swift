import Foundation
import RevenueCat
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

@MainActor
struct TrialOfferTests {
    @Test func eligibleYearlyPlanShowsStoreKitSevenDayTrialAndRenewalPrice() throws {
        let offering = PaywallFixture.offering()
        let yearly = try #require(offering.annual)
        let options = PlanOption.options(
            from: offering,
            introEligibilityByProductID: [yearly.storeProduct.productIdentifier: .eligible]
        )
        let plan = try #require(options.first(where: { $0.analyticsPlan == .yearly }))

        #expect(plan.trial?.duration == "7 days")
        #expect(plan.trial?.renewalLine == "Then $99.99/year")
        #expect(plan.trial?.reassuranceHeadline == "Try every Pro feature free for 7 days")
        #expect(plan.trial?.reassuranceDetail == "Then $99.99/year. Cancel anytime.")
        #expect(plan.terms.contains("7 days free, then $99.99/year"))
    }

    @Test(arguments: [IntroEligibilityStatus.ineligible, .unknown])
    func ineligibleOrUnknownCustomerSeesNoTrial(status: IntroEligibilityStatus) throws {
        let offering = PaywallFixture.offering()
        let yearly = try #require(offering.annual)
        let options = PlanOption.options(
            from: offering,
            introEligibilityByProductID: [yearly.storeProduct.productIdentifier: status]
        )
        let plan = try #require(options.first(where: { $0.analyticsPlan == .yearly }))

        #expect(plan.trial == nil)
        #expect(plan.terms == "Renews yearly until cancelled.")
    }

    @Test func monthlyNeverAdvertisesATrial() throws {
        let offering = PaywallFixture.offering()
        let monthly = try #require(offering.monthly)
        let options = PlanOption.options(
            from: offering,
            introEligibilityByProductID: [monthly.storeProduct.productIdentifier: .eligible]
        )
        let plan = try #require(options.first(where: { $0.analyticsPlan == .monthly }))

        #expect(plan.trial == nil)
        #expect(plan.terms == "Renews monthly until cancelled.")
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
