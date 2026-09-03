import Foundation
import SwiftData
import Testing
@testable import MarginRun

/// What the seeded demo world is worth to Insights.
///
/// Regression: the fixture shipped a single completed job, so Insights always
/// took its `completedJobCount == 1` branch — "comparison pending" — and best,
/// worst, biggest miss and the cost pattern never rendered at all. Nothing
/// failed; the screen was simply empty of the thing it exists to show, in the
/// app and in every marketing screenshot taken from it.
///
/// These assertions are about the *fixture*, not the arithmetic, which
/// ``InsightsFinancialsTests`` already covers.
@MainActor
struct DemoFixtureInsightsTests {

    private func insights(period: InsightsPeriod = .days30) -> InsightsFinancials {
        let completed = [
            MockData.kitchenRemodelJob(),
            MockData.bathroomRetileJob(),
            MockData.garageConversionJob(),
        ]

        return InsightsFinancials(
            snapshots: completed.map { job in
                let report = job.completionReport
                return CompletedJobInsightSnapshot(
                    id: job.id,
                    name: job.name,
                    customerName: job.customerName,
                    completedAt: job.completedAt ?? job.createdAt,
                    revenue: report.totalRevenue,
                    actualProfit: report.actualProfit,
                    actualMargin: report.actualMargin,
                    profitVariance: report.profitVariance,
                    categoryBudgets: report.categoryBudgets
                )
            },
            period: period
        )
    }

    /// The load-bearing one: two or more completed jobs is what unlocks the
    /// comparison branch. At one, Insights shows nothing to compare.
    @Test func theFixtureHasEnoughCompletedJobsToCompare() {
        #expect(insights().completedJobCount == 3)
    }

    /// All three have to sit inside the default period, or the screen the app
    /// opens on is still empty however many jobs exist.
    @Test func everyCompletedJobFallsInsideTheDefaultPeriod() {
        #expect(insights(period: .days30).completedJobCount == insights(period: .allTime).completedJobCount)
    }

    @Test func theOverviewTotalsAreTheOnesTheFixtureAdvertises() {
        let result = insights()

        // 18,000 + 9,500 + 12,000
        #expect(result.revenue == 39_500)
        // 5,100 + 3,810 + 1,520
        #expect(result.profit == 10_430)
        #expect(result.weightedActualMargin == Decimal(10_430) / Decimal(39_500))
    }

    /// A comparison of three near-identical jobs shows nothing, so the fixture
    /// has to spread across the rows.
    ///
    /// "Best" here is the job that *earned the most*, not the one with the best
    /// margin — so Kitchen remodel wins on $5,100 of profit despite overrunning
    /// three categories and landing under its 35% target, ahead of Bathroom
    /// retile's cleaner $3,810 at 40.1%. That is the app's definition, and the
    /// fixture is built to exercise it rather than to flatter it.
    @Test func theThreeJobsProduceAContrastingComparison() {
        let result = insights()

        #expect(result.bestCompletedJob?.name == "Kitchen remodel")
        #expect(result.bestCompletedJob?.actualProfit == 5_100)

        #expect(result.worstCompletedJob?.name == "Garage conversion")
        #expect(result.worstCompletedJob?.actualProfit == 1_520)

        #expect(result.biggestMissVsEstimate?.name == "Garage conversion")
        #expect(result.biggestMissVsEstimate?.profitVariance == -2_080)
    }

    /// The middle job is the one that behaved: under budget in every category,
    /// and the only one of the three that beat its own estimate.
    @Test func oneJobBeatsItsEstimate() {
        let bathroom = MockData.bathroomRetileJob().completionReport

        #expect(bathroom.actualProfit == 3_810)
        #expect(bathroom.profitVariance == 410)
        #expect(bathroom.categoryBudgets.allSatisfy { !$0.isOverBudget })
    }

    /// Labor overran on two of the three, which is the right story for an app
    /// whose headline Pro feature is a labor timer.
    @Test func laborIsTheMostOverBudgetCategory() {
        let category = insights().mostOverBudgetCategory

        #expect(category?.title == "Labor")
        // Kitchen +500, Garage +1,200.
        #expect(category?.amount == 1_700)
        #expect(category?.affectedJobCount == 2)
    }

    /// The two jobs the UI tests navigate by name have to keep existing, and
    /// the active/completed split has to keep the free tier out of its limit.
    @Test func theFixtureKeepsTheNamesAndCountsTheSuiteDependsOn() {
        let container = PreviewSupport.container()
        let jobs = try? container.mainContext.fetch(FetchDescriptor<Job>())
        let names = Set((jobs ?? []).map(\.name))

        #expect(names.contains("Kitchen remodel"))
        #expect(names.contains("Backyard fence"))
        #expect((jobs ?? []).filter { $0.status == .active }.count == 1)
        #expect((jobs ?? []).filter { $0.status == .completed }.count == 3)
    }
}
