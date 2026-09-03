import Foundation

nonisolated struct ExpenseLine: Equatable, Sendable {
    var category: ExpenseCategory
    var amount: Decimal
}

nonisolated struct LaborLine: Equatable, Sendable {
    var hours: Decimal
    var hourlyCost: Decimal

    var cost: Decimal { hours * hourlyCost }
}

nonisolated struct ExtraRevenueLine: Equatable, Sendable {
    var revenueAmount: Decimal
    var estimatedCost: Decimal
    var isApproved: Bool = true
}

nonisolated struct JobFinancialInputs: Equatable, Sendable {
    var contractValue: Decimal
    var targetMarginPercent: Decimal
    var estimatedMaterials: Decimal
    var estimatedLabor: Decimal
    var estimatedSubcontractors: Decimal
    var estimatedEquipment: Decimal
    var estimatedOther: Decimal
    var expenses: [ExpenseLine]
    var laborEntries: [LaborLine]
    var extraRevenues: [ExtraRevenueLine]
}

nonisolated struct CategoryBudget: Equatable, Sendable, Identifiable {
    var id: String { title }
    var title: String
    var estimated: Decimal
    var actual: Decimal

    var variance: Decimal { actual - estimated }
    var isOverBudget: Bool { actual > estimated }
    var isNearLimit: Bool {
        guard let utilization else { return false }
        return utilization >= Decimal(string: "0.9")! && !isOverBudget
    }

    var utilization: Decimal? {
        guard estimated > 0 else { return nil }
        return actual / estimated
    }

    var remaining: Decimal { estimated - actual }
}

nonisolated struct JobFinancials: Equatable, Sendable {
    let estimatedTotalCost: Decimal
    let expectedProfit: Decimal
    let expectedMargin: Decimal?

    let extraRevenue: Decimal
    let extraEstimatedCost: Decimal
    let totalRevenue: Decimal

    let actualCost: Decimal
    let actualProfit: Decimal
    let actualMargin: Decimal?

    /// Best current estimate for the final result. Categories still under
    /// budget retain their estimate; categories already over budget retain the
    /// higher actual amount.
    let projectedFinalCost: Decimal
    let projectedProfit: Decimal
    let projectedMargin: Decimal?
    let projectedProfitVsExpected: Decimal

    /// Estimated cost that has not yet been logged. A negative value means the
    /// job has exceeded its total estimated cost.
    let budgetRemaining: Decimal
    let budgetUtilization: Decimal?

    /// Actual profit minus expected profit. Negative means below expected.
    let profitVsExpected: Decimal

    let materialsActual: Decimal
    let laborActual: Decimal
    let subcontractorsActual: Decimal
    let equipmentActual: Decimal
    let otherActual: Decimal

    let categoryBudgets: [CategoryBudget]
    let overBudgetCategories: [CategoryBudget]
    let isBelowTargetMargin: Bool
    let isExpectedMarginBelowTarget: Bool
    let isExpectedMarginAtRisk: Bool
    let expectedMarginHeadroomPercent: Decimal?
    let isProjectedMarginBelowTarget: Bool
    let isProjectedMarginAtRisk: Bool
    let projectedMarginHeadroomPercent: Decimal?

    init(inputs: JobFinancialInputs) {
        let approvedExtraRevenues = inputs.extraRevenues.filter(\.isApproved)
        let baseEstimatedCost =
            inputs.estimatedMaterials
            + inputs.estimatedLabor
            + inputs.estimatedSubcontractors
            + inputs.estimatedEquipment
            + inputs.estimatedOther

        extraRevenue = approvedExtraRevenues.reduce(0) { $0 + $1.revenueAmount }
        extraEstimatedCost = approvedExtraRevenues.reduce(0) { $0 + $1.estimatedCost }
        totalRevenue = inputs.contractValue + extraRevenue
        estimatedTotalCost = baseEstimatedCost + extraEstimatedCost
        expectedProfit = totalRevenue - estimatedTotalCost
        expectedMargin = Self.margin(profit: expectedProfit, revenue: totalRevenue)

        materialsActual = Self.sum(inputs.expenses, category: .materials)
        laborActual =
            Self.sum(inputs.expenses, category: .labor)
            + inputs.laborEntries.reduce(0) { $0 + $1.cost }
        subcontractorsActual = Self.sum(inputs.expenses, category: .subcontractors)
        equipmentActual = Self.sum(inputs.expenses, category: .equipment)
        otherActual =
            Self.sum(inputs.expenses, category: .other)
            + Self.sum(inputs.expenses, category: .travel)

        actualCost =
            materialsActual
            + laborActual
            + subcontractorsActual
            + equipmentActual
            + otherActual

        actualProfit = totalRevenue - actualCost
        actualMargin = Self.margin(profit: actualProfit, revenue: totalRevenue)
        profitVsExpected = actualProfit - expectedProfit
        budgetRemaining = estimatedTotalCost - actualCost
        budgetUtilization = estimatedTotalCost > 0 ? actualCost / estimatedTotalCost : nil

        categoryBudgets = [
            CategoryBudget(title: "Materials", estimated: inputs.estimatedMaterials, actual: materialsActual),
            CategoryBudget(title: "Labor", estimated: inputs.estimatedLabor, actual: laborActual),
            CategoryBudget(title: "Subcontractors", estimated: inputs.estimatedSubcontractors, actual: subcontractorsActual),
            CategoryBudget(title: "Equipment", estimated: inputs.estimatedEquipment, actual: equipmentActual),
            CategoryBudget(title: "Other", estimated: inputs.estimatedOther, actual: otherActual),
        ]
        overBudgetCategories = categoryBudgets.filter(\.isOverBudget)

        projectedFinalCost = categoryBudgets.reduce(extraEstimatedCost) { total, category in
            total + max(category.estimated, category.actual)
        }
        projectedProfit = totalRevenue - projectedFinalCost
        projectedMargin = Self.margin(profit: projectedProfit, revenue: totalRevenue)
        projectedProfitVsExpected = projectedProfit - expectedProfit

        if let actualMargin {
            isBelowTargetMargin = (actualMargin * 100) < inputs.targetMarginPercent
        } else {
            isBelowTargetMargin = false
        }

        if let expectedMargin {
            let headroom = (expectedMargin * 100) - inputs.targetMarginPercent
            expectedMarginHeadroomPercent = headroom
            isExpectedMarginBelowTarget = headroom < 0
            isExpectedMarginAtRisk = headroom >= 0 && headroom < 5
        } else {
            expectedMarginHeadroomPercent = nil
            isExpectedMarginBelowTarget = false
            isExpectedMarginAtRisk = false
        }


        if let projectedMargin {
            let headroom = (projectedMargin * 100) - inputs.targetMarginPercent
            projectedMarginHeadroomPercent = headroom
            isProjectedMarginBelowTarget = headroom < 0
            isProjectedMarginAtRisk = headroom >= 0 && headroom < 5
        } else {
            projectedMarginHeadroomPercent = nil
            isProjectedMarginBelowTarget = false
            isProjectedMarginAtRisk = false
        }
    }

    static func margin(profit: Decimal, revenue: Decimal) -> Decimal? {
        guard revenue != 0 else { return nil }
        return profit / revenue
    }

    private static func sum(_ expenses: [ExpenseLine], category: ExpenseCategory) -> Decimal {
        expenses.reduce(0) { partial, line in
            line.category == category ? partial + line.amount : partial
        }
    }
}

nonisolated struct JobCompletionReport: Equatable, Sendable {
    let contractValue: Decimal
    let totalRevenue: Decimal
    let targetMarginPercent: Decimal
    let estimatedCost: Decimal
    let actualCost: Decimal
    let expectedProfit: Decimal
    let actualProfit: Decimal
    let expectedMargin: Decimal?
    let actualMargin: Decimal?
    let additionalRevenue: Decimal
    let additionalExpectedCost: Decimal
    let categoryBudgets: [CategoryBudget]

    var profitVariance: Decimal { actualProfit - expectedProfit }
    var costVariance: Decimal { actualCost - estimatedCost }

    var isBelowTargetMargin: Bool {
        guard let actualMargin else { return false }
        return (actualMargin * 100) < targetMarginPercent
    }

    var categoryVariances: [CategoryBudget] {
        categoryBudgets
            .filter { $0.variance != 0 }
            .sorted { abs($0.variance) > abs($1.variance) }
    }
}

extension JobFinancials {
    var isOverBudget: Bool { budgetRemaining < 0 }

    /// A job needs attention when margin is below or close to target, or when a
    /// cost category has reached at least 90% of its estimate.
    var hasBudgetRisk: Bool {
        isProjectedMarginBelowTarget
            || isProjectedMarginAtRisk
            || !overBudgetCategories.isEmpty
            || highestNearLimitCategory != nil
    }

    var largestOverBudgetCategory: CategoryBudget? {
        overBudgetCategories.max { $0.variance < $1.variance }
    }

    var highestNearLimitCategory: CategoryBudget? {
        categoryBudgets
            .filter(\.isNearLimit)
            .max { ($0.utilization ?? 0) < ($1.utilization ?? 0) }
    }

    var profitVsExpectedSummary: String {
        let amount = MoneyFormat.usd(abs(profitVsExpected))
        if profitVsExpected < 0 {
            return "\(amount) below expected profit"
        }
        if profitVsExpected > 0 {
            return "\(amount) above expected profit"
        }
        return "On expected profit"
    }


    var projectedProfitVsExpectedSummary: String {
        let amount = MoneyFormat.usd(abs(projectedProfitVsExpected))
        if projectedProfitVsExpected < 0 {
            return "\(amount) below expected profit"
        }
        if projectedProfitVsExpected > 0 {
            return "\(amount) above expected profit"
        }
        return "On expected profit"
    }
}
