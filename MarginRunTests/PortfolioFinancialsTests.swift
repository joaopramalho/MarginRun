import Foundation
import Testing
@testable import MarginRun

@MainActor
struct PortfolioFinancialsTests {
    @Test func weightsActiveMarginByRevenueAndKeepsCompletedActualsSeparate() {
        let portfolio = PortfolioFinancials(
            snapshots: [
                PortfolioJobSnapshot(
                    isActive: true,
                    isAtRisk: false,
                    revenue: 500,
                    projectedProfit: 400,
                    actualProfit: 0
                ),
                PortfolioJobSnapshot(
                    isActive: true,
                    isAtRisk: true,
                    revenue: 50_000,
                    projectedProfit: 10_000,
                    actualProfit: 0
                ),
                PortfolioJobSnapshot(
                    isActive: false,
                    isAtRisk: false,
                    revenue: 10_000,
                    projectedProfit: 3_000,
                    actualProfit: 2_200
                ),
            ]
        )

        #expect(portfolio.activeJobCount == 2)
        #expect(portfolio.completedJobCount == 1)
        #expect(portfolio.atRiskJobCount == 1)
        #expect(portfolio.activeRevenue == 50_500)
        #expect(portfolio.activeProjectedProfit == 10_400)
        #expect(portfolio.activeWeightedMargin == Decimal(10_400) / Decimal(50_500))
        #expect(portfolio.activeWeightedMargin != Decimal(string: "0.5"))
        #expect(portfolio.completedRevenue == 10_000)
        #expect(portfolio.completedActualProfit == 2_200)
    }

    @Test func completingAJobRecordsFinalStateOnlyOnce() {
        let job = Job(
            name: "Porch repair",
            customerName: "Morris Home",
            contractValue: 8_400,
            targetMargin: 30,
            estimatedMaterials: 2_500,
            estimatedLabor: 2_100,
            estimatedSubcontractors: 0,
            estimatedEquipment: 250,
            estimatedOther: 150
        )
        let completedAt = Date(timeIntervalSince1970: 1_788_000_000)
        let laterDate = completedAt.addingTimeInterval(60)

        job.complete(at: completedAt)
        let firstReport = job.completionReport
        job.complete(at: laterDate)

        #expect(job.status == .completed)
        #expect(job.completedAt == completedAt)
        #expect(job.completionReport == firstReport)
        #expect(!job.isAtRisk)
    }

    @Test func completionSnapshotDoesNotChangeWithUnderlyingJobData() {
        let job = Job(
            name: "Bathroom renovation",
            customerName: "Parker Home",
            contractValue: 12_000,
            targetMargin: 30,
            estimatedMaterials: 3_500,
            estimatedLabor: 2_500,
            estimatedSubcontractors: 500,
            estimatedEquipment: 250,
            estimatedOther: 250
        )
        job.expenses = [
            Expense(category: .materials, amount: 4_100, job: job),
            Expense(category: .other, amount: 100, job: job),
        ]
        job.laborEntries = [LaborEntry(hours: 40, hourlyCost: 50, job: job)]
        let approvedExtra = ExtraRevenue(
            description: "Built-in shelving",
            revenueAmount: 1_500,
            estimatedCost: 400,
            isApproved: true,
            job: job
        )
        let unapprovedExtra = ExtraRevenue(
            description: "Heated floor option",
            revenueAmount: 900,
            estimatedCost: 200,
            isApproved: false,
            job: job
        )
        job.extraRevenues = [approvedExtra, unapprovedExtra]

        job.complete(at: Date(timeIntervalSince1970: 1_788_000_000))
        let finalReport = job.completionReport

        job.contractValue = 99_000
        job.estimatedMaterials = 1
        job.expenses.append(Expense(category: .materials, amount: 8_000, job: job))
        approvedExtra.revenueAmount = 99_000
        approvedExtra.estimatedCost = 50_000
        approvedExtra.isApproved = false
        unapprovedExtra.isApproved = true

        #expect(job.completionReport == finalReport)
        #expect(finalReport.additionalRevenue == 1_500)
        #expect(finalReport.additionalExpectedCost == 400)
        #expect(finalReport.totalRevenue == 13_500)
        #expect(finalReport.estimatedCost == 7_400)
        #expect(finalReport.actualCost == 6_200)
        #expect(finalReport.expectedProfit == 6_100)
        #expect(finalReport.actualProfit == 7_300)
        #expect(finalReport.profitVariance == 1_200)
        #expect(finalReport.categoryVariances.first?.title == "Materials")
        #expect(finalReport.categoryVariances.first?.variance == 600)
    }
}
