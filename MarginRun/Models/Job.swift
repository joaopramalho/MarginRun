import Foundation
import SwiftData

@Model
final class Job {
    @Attribute(.unique) var id: UUID
    var name: String
    var customerName: String
    var contractValue: Decimal
    var targetMargin: Decimal
    var estimatedMaterials: Decimal
    var estimatedLabor: Decimal
    var estimatedSubcontractors: Decimal
    var estimatedEquipment: Decimal
    var estimatedOther: Decimal
    var statusRaw: String
    var createdAt: Date
    var completedAt: Date?

    // Finalized jobs read from this snapshot instead of recalculating their
    // result from mutable estimates or cost relationships.
    var completionContractValue: Decimal?
    var completionTotalRevenue: Decimal?
    var completionTargetMargin: Decimal?
    var completionEstimatedCost: Decimal?
    var completionActualCost: Decimal?
    var completionExpectedProfit: Decimal?
    var completionActualProfit: Decimal?
    var completionExpectedMargin: Decimal?
    var completionActualMargin: Decimal?
    var completionAdditionalRevenue: Decimal?
    var completionAdditionalExpectedCost: Decimal?
    var completionEstimatedMaterials: Decimal?
    var completionActualMaterials: Decimal?
    var completionEstimatedLabor: Decimal?
    var completionActualLabor: Decimal?
    var completionEstimatedSubcontractors: Decimal?
    var completionActualSubcontractors: Decimal?
    var completionEstimatedEquipment: Decimal?
    var completionActualEquipment: Decimal?
    var completionEstimatedOther: Decimal?
    var completionActualOther: Decimal?

    @Relationship(deleteRule: .cascade, inverse: \Expense.job)
    var expenses: [Expense] = []

    @Relationship(deleteRule: .cascade, inverse: \LaborEntry.job)
    var laborEntries: [LaborEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \ExtraRevenue.job)
    var extraRevenues: [ExtraRevenue] = []

    var status: JobStatus {
        get { JobStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        customerName: String,
        contractValue: Decimal,
        targetMargin: Decimal,
        estimatedMaterials: Decimal,
        estimatedLabor: Decimal,
        estimatedSubcontractors: Decimal,
        estimatedEquipment: Decimal,
        estimatedOther: Decimal,
        status: JobStatus = .active,
        createdAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.customerName = customerName
        self.contractValue = contractValue
        self.targetMargin = targetMargin
        self.estimatedMaterials = estimatedMaterials
        self.estimatedLabor = estimatedLabor
        self.estimatedSubcontractors = estimatedSubcontractors
        self.estimatedEquipment = estimatedEquipment
        self.estimatedOther = estimatedOther
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.completionContractValue = nil
        self.completionTotalRevenue = nil
        self.completionTargetMargin = nil
        self.completionEstimatedCost = nil
        self.completionActualCost = nil
        self.completionExpectedProfit = nil
        self.completionActualProfit = nil
        self.completionExpectedMargin = nil
        self.completionActualMargin = nil
        self.completionAdditionalRevenue = nil
        self.completionAdditionalExpectedCost = nil
        self.completionEstimatedMaterials = nil
        self.completionActualMaterials = nil
        self.completionEstimatedLabor = nil
        self.completionActualLabor = nil
        self.completionEstimatedSubcontractors = nil
        self.completionActualSubcontractors = nil
        self.completionEstimatedEquipment = nil
        self.completionActualEquipment = nil
        self.completionEstimatedOther = nil
        self.completionActualOther = nil
    }

    var financialInputs: JobFinancialInputs {
        financialInputs(excludingExtraRevenueID: nil)
    }

    func financialInputs(excludingExtraRevenueID excludedID: UUID?) -> JobFinancialInputs {
        JobFinancialInputs(
            contractValue: contractValue,
            targetMarginPercent: targetMargin,
            estimatedMaterials: estimatedMaterials,
            estimatedLabor: estimatedLabor,
            estimatedSubcontractors: estimatedSubcontractors,
            estimatedEquipment: estimatedEquipment,
            estimatedOther: estimatedOther,
            expenses: expenses.map { ExpenseLine(category: $0.category, amount: $0.amount) },
            laborEntries: laborEntries.map { LaborLine(hours: $0.hours, hourlyCost: $0.hourlyCost) },
            extraRevenues: extraRevenues.compactMap { extraRevenue in
                guard extraRevenue.id != excludedID else { return nil }
                return ExtraRevenueLine(
                    revenueAmount: extraRevenue.revenueAmount,
                    estimatedCost: extraRevenue.estimatedCost,
                    isApproved: extraRevenue.isApproved
                )
            }
        )
    }

    var financials: JobFinancials {
        JobFinancials(inputs: financialInputs)
    }

    var isAtRisk: Bool {
        status == .active && financials.hasBudgetRisk
    }

    var completionReport: JobCompletionReport {
        let live = financials
        guard
            let completionContractValue,
            let completionTotalRevenue,
            let completionTargetMargin,
            let completionEstimatedCost,
            let completionActualCost,
            let completionExpectedProfit,
            let completionActualProfit
        else {
            return JobCompletionReport(
                contractValue: contractValue,
                totalRevenue: live.totalRevenue,
                targetMarginPercent: targetMargin,
                estimatedCost: live.estimatedTotalCost,
                actualCost: live.actualCost,
                expectedProfit: live.expectedProfit,
                actualProfit: live.actualProfit,
                expectedMargin: live.expectedMargin,
                actualMargin: live.actualMargin,
                additionalRevenue: live.extraRevenue,
                additionalExpectedCost: live.extraEstimatedCost,
                categoryBudgets: live.categoryBudgets
            )
        }

        return JobCompletionReport(
            contractValue: completionContractValue,
            totalRevenue: completionTotalRevenue,
            targetMarginPercent: completionTargetMargin,
            estimatedCost: completionEstimatedCost,
            actualCost: completionActualCost,
            expectedProfit: completionExpectedProfit,
            actualProfit: completionActualProfit,
            expectedMargin: completionExpectedMargin,
            actualMargin: completionActualMargin,
            additionalRevenue: completionAdditionalRevenue
                ?? max(0, completionTotalRevenue - completionContractValue),
            additionalExpectedCost: completionAdditionalExpectedCost
                ?? legacyCompletionAdditionalExpectedCost,
            categoryBudgets: [
                CategoryBudget(
                    title: "Materials",
                    estimated: completionEstimatedMaterials ?? estimatedMaterials,
                    actual: completionActualMaterials ?? live.materialsActual
                ),
                CategoryBudget(
                    title: "Labor",
                    estimated: completionEstimatedLabor ?? estimatedLabor,
                    actual: completionActualLabor ?? live.laborActual
                ),
                CategoryBudget(
                    title: "Subcontractors",
                    estimated: completionEstimatedSubcontractors ?? estimatedSubcontractors,
                    actual: completionActualSubcontractors ?? live.subcontractorsActual
                ),
                CategoryBudget(
                    title: "Equipment",
                    estimated: completionEstimatedEquipment ?? estimatedEquipment,
                    actual: completionActualEquipment ?? live.equipmentActual
                ),
                CategoryBudget(
                    title: "Other",
                    estimated: completionEstimatedOther ?? estimatedOther,
                    actual: completionActualOther ?? live.otherActual
                ),
            ]
        )
    }

    func complete(at date: Date = .now) {
        guard status == .active else { return }
        let final = financials

        completionContractValue = contractValue
        completionTotalRevenue = final.totalRevenue
        completionTargetMargin = targetMargin
        completionEstimatedCost = final.estimatedTotalCost
        completionActualCost = final.actualCost
        completionExpectedProfit = final.expectedProfit
        completionActualProfit = final.actualProfit
        completionExpectedMargin = final.expectedMargin
        completionActualMargin = final.actualMargin
        completionAdditionalRevenue = final.extraRevenue
        completionAdditionalExpectedCost = final.extraEstimatedCost
        completionEstimatedMaterials = estimatedMaterials
        completionActualMaterials = final.materialsActual
        completionEstimatedLabor = estimatedLabor
        completionActualLabor = final.laborActual
        completionEstimatedSubcontractors = estimatedSubcontractors
        completionActualSubcontractors = final.subcontractorsActual
        completionEstimatedEquipment = estimatedEquipment
        completionActualEquipment = final.equipmentActual
        completionEstimatedOther = estimatedOther
        completionActualOther = final.otherActual
        status = .completed
        completedAt = date
    }

    func discardCompletion() {
        status = .active
        completedAt = nil
        completionContractValue = nil
        completionTotalRevenue = nil
        completionTargetMargin = nil
        completionEstimatedCost = nil
        completionActualCost = nil
        completionExpectedProfit = nil
        completionActualProfit = nil
        completionExpectedMargin = nil
        completionActualMargin = nil
        completionAdditionalRevenue = nil
        completionAdditionalExpectedCost = nil
        completionEstimatedMaterials = nil
        completionActualMaterials = nil
        completionEstimatedLabor = nil
        completionActualLabor = nil
        completionEstimatedSubcontractors = nil
        completionActualSubcontractors = nil
        completionEstimatedEquipment = nil
        completionActualEquipment = nil
        completionEstimatedOther = nil
        completionActualOther = nil
    }

    private var legacyCompletionAdditionalExpectedCost: Decimal {
        guard let completionEstimatedCost else { return 0 }
        let categoryEstimate =
            (completionEstimatedMaterials ?? estimatedMaterials)
            + (completionEstimatedLabor ?? estimatedLabor)
            + (completionEstimatedSubcontractors ?? estimatedSubcontractors)
            + (completionEstimatedEquipment ?? estimatedEquipment)
            + (completionEstimatedOther ?? estimatedOther)
        return max(0, completionEstimatedCost - categoryEstimate)
    }
}
