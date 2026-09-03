import Foundation

nonisolated struct PortfolioJobSnapshot: Equatable, Sendable {
    var isActive: Bool
    var isAtRisk: Bool
    var revenue: Decimal
    var projectedProfit: Decimal
    var actualProfit: Decimal
}

nonisolated struct PortfolioFinancials: Equatable, Sendable {
    let activeJobCount: Int
    let completedJobCount: Int
    let atRiskJobCount: Int
    let activeRevenue: Decimal
    let activeProjectedProfit: Decimal
    let activeWeightedMargin: Decimal?
    let completedRevenue: Decimal
    let completedActualProfit: Decimal

    init(snapshots: [PortfolioJobSnapshot]) {
        let activeSnapshots = snapshots.filter(\.isActive)
        let completedSnapshots = snapshots.filter { !$0.isActive }

        activeJobCount = activeSnapshots.count
        completedJobCount = completedSnapshots.count
        atRiskJobCount = activeSnapshots.count(where: \.isAtRisk)
        activeRevenue = activeSnapshots.reduce(0) { $0 + $1.revenue }
        activeProjectedProfit = activeSnapshots.reduce(0) { $0 + $1.projectedProfit }
        activeWeightedMargin = JobFinancials.margin(
            profit: activeProjectedProfit,
            revenue: activeRevenue
        )
        completedRevenue = completedSnapshots.reduce(0) { $0 + $1.revenue }
        completedActualProfit = completedSnapshots.reduce(0) { $0 + $1.actualProfit }
    }
}
