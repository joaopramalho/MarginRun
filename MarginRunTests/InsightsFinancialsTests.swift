import Foundation
import Testing
@testable import MarginRun

@MainActor
struct InsightsFinancialsTests {
    private let now = Date(timeIntervalSince1970: 1_788_192_000)

    @Test func thirtyDaysIncludesOnlyRecentCompletedJobs() {
        let insights = InsightsFinancials(
            snapshots: fixtures,
            period: .days30,
            now: now
        )

        #expect(insights.completedJobCount == 1)
        #expect(insights.revenue == 500)
        #expect(insights.profit == 400)
        #expect(insights.weightedActualMargin == Decimal(string: "0.8"))
        #expect(insights.bestCompletedJob?.name == "Small repair")
        #expect(insights.worstCompletedJob?.name == "Small repair")
        #expect(insights.biggestMissVsEstimate == nil)
        #expect(insights.mostOverBudgetCategory?.title == "Materials")
        #expect(insights.mostOverBudgetCategory?.amount == 100)
        #expect(insights.mostOverBudgetCategory?.affectedJobCount == 1)
    }

    @Test func weightedMarginUsesTotalProfitDividedByRevenue() {
        let insights = InsightsFinancials(
            snapshots: fixtures,
            period: .days90,
            now: now
        )

        #expect(insights.completedJobCount == 2)
        #expect(insights.revenue == 50_500)
        #expect(insights.profit == 10_400)
        #expect(insights.weightedActualMargin == Decimal(10_400) / Decimal(50_500))
        #expect(insights.weightedActualMargin != Decimal(string: "0.5"))
        #expect(insights.bestCompletedJob?.name == "Commercial buildout")
        #expect(insights.worstCompletedJob?.name == "Small repair")
        #expect(insights.biggestMissVsEstimate?.name == "Commercial buildout")
        #expect(insights.mostOverBudgetCategory?.title == "Labor")
        #expect(insights.mostOverBudgetCategory?.amount == 1_000)
    }

    @Test func allTimeFindsLargestProfitMissAndAggregatesCategoryOverruns() {
        let insights = InsightsFinancials(
            snapshots: fixtures,
            period: .allTime,
            now: now
        )

        #expect(insights.completedJobCount == 3)
        #expect(insights.bestCompletedJob?.name == "Commercial buildout")
        #expect(insights.worstCompletedJob?.name == "Deck replacement")
        #expect(insights.biggestMissVsEstimate?.name == "Deck replacement")
        #expect(insights.biggestMissVsEstimate?.profitVariance == -4_000)
        #expect(insights.mostOverBudgetCategory?.title == "Labor")
        #expect(insights.mostOverBudgetCategory?.amount == 1_000)
        #expect(insights.mostOverBudgetCategory?.affectedJobCount == 1)
    }

    @Test func emptyPeriodHasZeroTotalsAndNoRankings() {
        let insights = InsightsFinancials(
            snapshots: [],
            period: .allTime,
            now: now
        )

        #expect(insights.completedJobCount == 0)
        #expect(insights.revenue == 0)
        #expect(insights.profit == 0)
        #expect(insights.weightedActualMargin == nil)
        #expect(insights.bestCompletedJob == nil)
        #expect(insights.worstCompletedJob == nil)
        #expect(insights.biggestMissVsEstimate == nil)
        #expect(insights.mostOverBudgetCategory == nil)
    }

    private var fixtures: [CompletedJobInsightSnapshot] {
        [
            CompletedJobInsightSnapshot(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Small repair",
                customerName: "Gray Home",
                completedAt: now.addingTimeInterval(-10 * 24 * 60 * 60),
                revenue: 500,
                actualProfit: 400,
                actualMargin: Decimal(string: "0.8"),
                profitVariance: 50,
                categoryBudgets: [
                    CategoryBudget(title: "Materials", estimated: 100, actual: 200),
                ]
            ),
            CompletedJobInsightSnapshot(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "Commercial buildout",
                customerName: "Northpoint LLC",
                completedAt: now.addingTimeInterval(-60 * 24 * 60 * 60),
                revenue: 50_000,
                actualProfit: 10_000,
                actualMargin: Decimal(string: "0.2"),
                profitVariance: -2_500,
                categoryBudgets: [
                    CategoryBudget(title: "Labor", estimated: 4_000, actual: 5_000),
                ]
            ),
            CompletedJobInsightSnapshot(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                name: "Deck replacement",
                customerName: "Stone Residence",
                completedAt: now.addingTimeInterval(-200 * 24 * 60 * 60),
                revenue: 10_000,
                actualProfit: -500,
                actualMargin: Decimal(string: "-0.05"),
                profitVariance: -4_000,
                categoryBudgets: [
                    CategoryBudget(title: "Materials", estimated: 1_000, actual: 1_400),
                ]
            ),
        ]
    }
}
