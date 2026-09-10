import Foundation
import Testing
@testable import MarginRun

@MainActor
struct MarginAlertEngineTests {
    @Test func createsAndPrioritizesBudgetAndMarginAlerts() {
        let jobID = UUID()
        let financials = JobFinancials(inputs: JobFinancialInputs(
            contractValue: 2_000,
            targetMarginPercent: 45,
            estimatedMaterials: 1_000,
            estimatedLabor: 0,
            estimatedSubcontractors: 0,
            estimatedEquipment: 0,
            estimatedOther: 0,
            expenses: [ExpenseLine(category: .materials, amount: 1_120)],
            laborEntries: [],
            extraRevenues: []
        ))

        let alerts = MarginAlertEngine.alerts(for: [MarginAlertJobSnapshot(
            jobID: jobID,
            jobName: "Kitchen remodel",
            targetMarginPercent: 45,
            financials: financials
        )])

        #expect(alerts.map(\.kind) == [
            .categoryOverBudget,
            .projectedMarginBelowTarget,
            .belowExpectedProfit,
        ])
        #expect(alerts[0].message == "Materials are 12% over budget")
        #expect(alerts[1].message == "Projected margin is below your 45% target")
        #expect(alerts[1].severity == .warning)
        #expect(alerts[2].message.contains("\(MoneyFormat.usd(120)) below expected profit"))
    }

    @Test func warnsWhenCategoryReachesNinetyPercent() {
        let financials = JobFinancials(inputs: JobFinancialInputs(
            contractValue: 5_000,
            targetMarginPercent: 30,
            estimatedMaterials: 0,
            estimatedLabor: 1_000,
            estimatedSubcontractors: 0,
            estimatedEquipment: 0,
            estimatedOther: 0,
            expenses: [],
            laborEntries: [LaborLine(hours: 18, hourlyCost: 50)],
            extraRevenues: []
        ))

        let alerts = MarginAlertEngine.alerts(for: [MarginAlertJobSnapshot(
            jobID: UUID(),
            jobName: "Fence",
            targetMarginPercent: 30,
            financials: financials
        )])

        #expect(alerts.count == 1)
        #expect(alerts.first?.kind == .categoryNearLimit)
        // The percentage is rendered in the device's locale, so the expectation
        // is built the same way rather than pinning a decimal separator here.
        // What this asserts is the sentence: the category, the verb agreement,
        // and the figure it reports.
        let ninetyPercent = MoneyFormat.percent(ratio: Decimal(string: "0.9")!)
        #expect(alerts.first?.message == "Labor has used \(ninetyPercent) of its budget")
    }
}
