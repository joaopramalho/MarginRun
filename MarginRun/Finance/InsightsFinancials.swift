import Foundation

nonisolated enum InsightsPeriod: String, CaseIterable, Identifiable, Sendable {
    case days30
    case days90
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .days30: "30D"
        case .days90: "90D"
        case .allTime: "All time"
        }
    }

    var description: String {
        switch self {
        case .days30: "Last 30 days"
        case .days90: "Last 90 days"
        case .allTime: "All completed jobs"
        }
    }

    func contains(_ date: Date, relativeTo now: Date) -> Bool {
        guard date <= now else { return false }

        let days: Int?
        switch self {
        case .days30: days = 30
        case .days90: days = 90
        case .allTime: days = nil
        }

        guard let days else { return true }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) else {
            return false
        }
        return date >= cutoff
    }
}

nonisolated struct CompletedJobInsightSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let customerName: String
    let completedAt: Date
    let revenue: Decimal
    let actualProfit: Decimal
    let actualMargin: Decimal?
    let profitVariance: Decimal
    let categoryBudgets: [CategoryBudget]
}

nonisolated struct CategoryOverrunInsight: Equatable, Sendable {
    let title: String
    let amount: Decimal
    let affectedJobCount: Int
}

nonisolated struct InsightsFinancials: Equatable, Sendable {
    let completedJobCount: Int
    let revenue: Decimal
    let profit: Decimal
    let weightedActualMargin: Decimal?
    let bestCompletedJob: CompletedJobInsightSnapshot?
    let worstCompletedJob: CompletedJobInsightSnapshot?
    let biggestMissVsEstimate: CompletedJobInsightSnapshot?
    let mostOverBudgetCategory: CategoryOverrunInsight?

    init(
        snapshots: [CompletedJobInsightSnapshot],
        period: InsightsPeriod,
        now: Date = .now
    ) {
        let filtered = snapshots.filter { period.contains($0.completedAt, relativeTo: now) }

        completedJobCount = filtered.count
        revenue = filtered.reduce(0) { $0 + $1.revenue }
        profit = filtered.reduce(0) { $0 + $1.actualProfit }
        weightedActualMargin = JobFinancials.margin(profit: profit, revenue: revenue)

        bestCompletedJob = filtered.max(by: Self.isLowerPerforming)
        worstCompletedJob = filtered.min(by: Self.isLowerPerforming)
        biggestMissVsEstimate = filtered
            .filter { $0.profitVariance < 0 }
            .min { $0.profitVariance < $1.profitVariance }

        var categoryTotals: [String: CategoryAccumulator] = [:]
        for job in filtered {
            for category in job.categoryBudgets where category.variance > 0 {
                var accumulator = categoryTotals[category.title, default: CategoryAccumulator()]
                accumulator.amount += category.variance
                accumulator.affectedJobCount += 1
                categoryTotals[category.title] = accumulator
            }
        }

        mostOverBudgetCategory = categoryTotals
            .map { title, total in
                CategoryOverrunInsight(
                    title: title,
                    amount: total.amount,
                    affectedJobCount: total.affectedJobCount
                )
            }
            .sorted {
                if $0.amount == $1.amount { return $0.title < $1.title }
                return $0.amount > $1.amount
            }
            .first
    }

    private static func isLowerPerforming(
        _ lhs: CompletedJobInsightSnapshot,
        _ rhs: CompletedJobInsightSnapshot
    ) -> Bool {
        if lhs.actualProfit == rhs.actualProfit {
            return (lhs.actualMargin ?? 0) < (rhs.actualMargin ?? 0)
        }
        return lhs.actualProfit < rhs.actualProfit
    }
}

private nonisolated struct CategoryAccumulator {
    var amount: Decimal = 0
    var affectedJobCount = 0
}
