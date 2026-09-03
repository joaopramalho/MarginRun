import Foundation
import Testing
@testable import MarginRun

@MainActor
struct JobFinancialsTests {
    @Test func kitchenRemodelExample() {
        let financials = JobFinancials(inputs: kitchenExampleInputs())

        #expect(financials.estimatedTotalCost == 11_500)
        #expect(financials.expectedProfit == 6_500)
        #expect(MoneyFormat.roundedPercent(financials.expectedMargin!) == Decimal(string: "36.1"))

        #expect(financials.actualCost == 12_900)
        #expect(financials.actualProfit == 5_100)
        #expect(MoneyFormat.roundedPercent(financials.actualMargin!) == Decimal(string: "28.3"))
        #expect(financials.profitVsExpected == -1_400)
        #expect(financials.profitVsExpectedSummary.contains("below expected profit"))
        #expect(financials.budgetRemaining == -1_400)
        #expect(financials.isOverBudget)
        #expect(financials.largestOverBudgetCategory?.title == "Materials")
        #expect(financials.projectedFinalCost == 12_900)
        #expect(financials.projectedProfit == 5_100)
        #expect(financials.projectedProfitVsExpected == -1_400)
    }

    @Test func addingExpenseLowersProfitImmediately() {
        var inputs = kitchenExampleInputs()
        let before = JobFinancials(inputs: inputs)

        inputs.expenses.append(ExpenseLine(category: .materials, amount: 250))
        let after = JobFinancials(inputs: inputs)

        #expect(after.actualCost == before.actualCost + 250)
        #expect(after.actualProfit == before.actualProfit - 250)
        #expect(after.profitVsExpected == before.profitVsExpected - 250)
    }

    @Test func extraRevenueIncreasesTotalRevenueAndProfit() {
        var inputs = kitchenExampleInputs()
        inputs.extraRevenues = [ExtraRevenueLine(revenueAmount: 800, estimatedCost: 200)]
        let financials = JobFinancials(inputs: inputs)

        #expect(financials.totalRevenue == 18_800)
        #expect(financials.extraEstimatedCost == 200)
        #expect(financials.estimatedTotalCost == 11_700)
        #expect(financials.expectedProfit == 7_100)
        #expect(financials.actualProfit == 5_900)
    }

    @Test func pendingExtraRevenueDoesNotAffectProjectionUntilApproved() {
        let base = JobFinancialInputs(
            contractValue: 10_000,
            targetMarginPercent: 30,
            estimatedMaterials: 3_000,
            estimatedLabor: 2_000,
            estimatedSubcontractors: 0,
            estimatedEquipment: 0,
            estimatedOther: 0,
            expenses: [],
            laborEntries: [],
            extraRevenues: [
                ExtraRevenueLine(
                    revenueAmount: 2_000,
                    estimatedCost: 500,
                    isApproved: false
                )
            ]
        )

        let pending = JobFinancials(inputs: base)
        var approvedInputs = base
        approvedInputs.extraRevenues[0].isApproved = true
        let approved = JobFinancials(inputs: approvedInputs)

        #expect(pending.totalRevenue == 10_000)
        #expect(pending.estimatedTotalCost == 5_000)
        #expect(pending.projectedProfit == 5_000)
        #expect(pending.projectedMargin == Decimal(string: "0.5"))

        #expect(approved.totalRevenue == 12_000)
        #expect(approved.estimatedTotalCost == 5_500)
        #expect(approved.projectedProfit == 6_500)
        #expect(approved.projectedMargin == Decimal(6_500) / Decimal(12_000))
    }

    @Test func marginIsNilWhenRevenueIsZero() {
        let inputs = JobFinancialInputs(
            contractValue: 0,
            targetMarginPercent: 30,
            estimatedMaterials: 100,
            estimatedLabor: 0,
            estimatedSubcontractors: 0,
            estimatedEquipment: 0,
            estimatedOther: 0,
            expenses: [],
            laborEntries: [],
            extraRevenues: []
        )
        let financials = JobFinancials(inputs: inputs)

        #expect(financials.expectedMargin == nil)
        #expect(financials.actualMargin == nil)
        #expect(financials.expectedProfit == -100)
        #expect(financials.actualProfit == 0)
    }

    @Test func laborEntriesCountTowardActualLabor() {
        let inputs = JobFinancialInputs(
            contractValue: 10_000,
            targetMarginPercent: 30,
            estimatedMaterials: 0,
            estimatedLabor: 2_000,
            estimatedSubcontractors: 0,
            estimatedEquipment: 0,
            estimatedOther: 0,
            expenses: [ExpenseLine(category: .labor, amount: 100)],
            laborEntries: [LaborLine(hours: 8, hourlyCost: 50)],
            extraRevenues: []
        )
        let financials = JobFinancials(inputs: inputs)

        #expect(financials.laborActual == 500)
        #expect(financials.actualCost == 500)
    }

    @Test func overBudgetFlagsCategoriesAboveEstimate() {
        let financials = JobFinancials(inputs: kitchenExampleInputs())
        let overBudgetTitles = financials.overBudgetCategories.map(\.title)

        #expect(overBudgetTitles.contains("Materials"))
        #expect(overBudgetTitles.contains("Labor"))
        #expect(overBudgetTitles.contains("Subcontractors"))
        #expect(!overBudgetTitles.contains("Equipment"))
    }

    @Test func belowTargetMargin() {
        let financials = JobFinancials(inputs: kitchenExampleInputs())
        #expect(financials.isBelowTargetMargin)
    }

    @Test func expectedMarginMeetsTargetWhenEstimatesAreOnPlan() {
        var inputs = kitchenExampleInputs()
        inputs.expenses = []
        inputs.laborEntries = []
        let financials = JobFinancials(inputs: inputs)

        #expect(MoneyFormat.roundedPercent(financials.expectedMargin!) == Decimal(string: "36.1"))
        #expect(!financials.isExpectedMarginBelowTarget)
        #expect(financials.budgetRemaining == 11_500)
        #expect(financials.budgetUtilization == 0)
    }

    @Test func newJobHasFullBudgetRemainingWithoutImplyingFinalPerformance() {
        let inputs = JobFinancialInputs(
            contractValue: 10_000,
            targetMarginPercent: 40,
            estimatedMaterials: 1_500,
            estimatedLabor: 2_500,
            estimatedSubcontractors: 600,
            estimatedEquipment: 300,
            estimatedOther: 150,
            expenses: [],
            laborEntries: [],
            extraRevenues: []
        )
        let financials = JobFinancials(inputs: inputs)

        #expect(financials.actualCost == 0)
        #expect(financials.estimatedTotalCost == 5_050)
        #expect(financials.budgetRemaining == 5_050)
        #expect(financials.budgetUtilization == 0)
        #expect(financials.expectedProfit == 4_950)
        #expect(MoneyFormat.roundedPercent(financials.expectedMargin!) == Decimal(string: "49.5"))
        #expect(financials.projectedFinalCost == 5_050)
        #expect(financials.projectedProfit == 4_950)
        #expect(financials.projectedMargin == financials.expectedMargin)
    }

    @Test func consumingNinetyPercentOfBudgetMarksJobAsRisk() {
        let inputs = JobFinancialInputs(
            contractValue: 10_000,
            targetMarginPercent: 30,
            estimatedMaterials: 5_000,
            estimatedLabor: 0,
            estimatedSubcontractors: 0,
            estimatedEquipment: 0,
            estimatedOther: 0,
            expenses: [ExpenseLine(category: .materials, amount: 4_500)],
            laborEntries: [],
            extraRevenues: []
        )
        let financials = JobFinancials(inputs: inputs)

        #expect(financials.budgetUtilization == Decimal(string: "0.9"))
        #expect(financials.highestNearLimitCategory?.title == "Materials")
        #expect(financials.hasBudgetRisk)
    }

    @Test func projectionKeepsUnspentBudgetsAndAddsOnlyKnownOverruns() {
        let inputs = JobFinancialInputs(
            contractValue: 10_000,
            targetMarginPercent: 35,
            estimatedMaterials: 2_000,
            estimatedLabor: 2_000,
            estimatedSubcontractors: 500,
            estimatedEquipment: 250,
            estimatedOther: 250,
            expenses: [ExpenseLine(category: .materials, amount: 2_400)],
            laborEntries: [LaborLine(hours: 10, hourlyCost: 50)],
            extraRevenues: []
        )
        let financials = JobFinancials(inputs: inputs)

        #expect(financials.actualCost == 2_900)
        #expect(financials.estimatedTotalCost == 5_000)
        #expect(financials.projectedFinalCost == 5_400)
        #expect(financials.expectedProfit == 5_000)
        #expect(financials.projectedProfit == 4_600)
        #expect(financials.projectedProfitVsExpected == -400)
    }

    @Test func marginWithinFivePointsOfTargetIsAtRisk() {
        let inputs = JobFinancialInputs(
            contractValue: 10_000,
            targetMarginPercent: 30,
            estimatedMaterials: 6_800,
            estimatedLabor: 0,
            estimatedSubcontractors: 0,
            estimatedEquipment: 0,
            estimatedOther: 0,
            expenses: [],
            laborEntries: [],
            extraRevenues: []
        )
        let financials = JobFinancials(inputs: inputs)

        #expect(financials.expectedMarginHeadroomPercent == 2)
        #expect(!financials.isExpectedMarginBelowTarget)
        #expect(financials.isExpectedMarginAtRisk)
        #expect(financials.hasBudgetRisk)
    }

    private func kitchenExampleInputs() -> JobFinancialInputs {
        JobFinancialInputs(
            contractValue: 18_000,
            targetMarginPercent: 35,
            estimatedMaterials: 5_000,
            estimatedLabor: 4_000,
            estimatedSubcontractors: 1_500,
            estimatedEquipment: 700,
            estimatedOther: 300,
            expenses: [
                ExpenseLine(category: .materials, amount: 5_800),
                ExpenseLine(category: .subcontractors, amount: 1_600),
                ExpenseLine(category: .equipment, amount: 700),
                ExpenseLine(category: .travel, amount: 200),
                ExpenseLine(category: .other, amount: 100),
            ],
            laborEntries: [LaborLine(hours: 90, hourlyCost: 50)],
            extraRevenues: []
        )
    }
}
