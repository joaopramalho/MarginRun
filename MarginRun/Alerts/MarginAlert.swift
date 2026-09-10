import Foundation

nonisolated enum MarginAlertSeverity: Int, Comparable, Sendable {
    case warning = 1
    case critical = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

nonisolated enum MarginAlertKind: Sendable {
    case categoryOverBudget
    case projectedMarginBelowTarget
    case categoryNearLimit
    case belowExpectedProfit

    var priority: Int {
        switch self {
        case .categoryOverBudget: 4
        case .projectedMarginBelowTarget: 3
        case .categoryNearLimit: 2
        case .belowExpectedProfit: 1
        }
    }
}

nonisolated struct MarginAlert: Identifiable, Equatable, Sendable {
    let id: String
    let jobID: UUID
    let jobName: String
    let kind: MarginAlertKind
    let severity: MarginAlertSeverity
    let message: String
    let sortAmount: Decimal
}

nonisolated struct MarginAlertJobSnapshot: Sendable {
    let jobID: UUID
    let jobName: String
    let targetMarginPercent: Decimal
    let financials: JobFinancials
}

nonisolated enum MarginAlertEngine {
    static func alerts(for snapshots: [MarginAlertJobSnapshot]) -> [MarginAlert] {
        snapshots
            .flatMap(alerts)
            .sorted {
                if $0.kind.priority != $1.kind.priority {
                    return $0.kind.priority > $1.kind.priority
                }
                if $0.severity != $1.severity {
                    return $0.severity > $1.severity
                }
                if $0.sortAmount != $1.sortAmount {
                    return $0.sortAmount > $1.sortAmount
                }
                return $0.jobName.localizedStandardCompare($1.jobName) == .orderedAscending
            }
    }

    private static func alerts(for snapshot: MarginAlertJobSnapshot) -> [MarginAlert] {
        let financials = snapshot.financials
        var results: [MarginAlert] = []

        for category in financials.overBudgetCategories {
            let message: String
            if category.estimated > 0, let utilization = category.utilization {
                let percentOver = MoneyFormat.roundedPercent(utilization - 1)
                message = "\(category.title) \(overBudgetVerb(for: category)) \(decimalText(percentOver))% over budget"
            } else {
                message = "\(category.title) \(overBudgetVerb(for: category)) \(MoneyFormat.usd(category.variance)) over budget"
            }
            results.append(MarginAlert(
                id: "\(snapshot.jobID.uuidString).over.\(category.id)",
                jobID: snapshot.jobID,
                jobName: snapshot.jobName,
                kind: .categoryOverBudget,
                severity: .critical,
                message: message,
                sortAmount: category.variance
            ))
        }

        if financials.isProjectedMarginBelowTarget {
            results.append(MarginAlert(
                id: "\(snapshot.jobID.uuidString).projected-margin",
                jobID: snapshot.jobID,
                jobName: snapshot.jobName,
                kind: .projectedMarginBelowTarget,
                severity: .warning,
                message: "Projected margin is below your \(decimalText(snapshot.targetMarginPercent))% target",
                sortAmount: abs(financials.projectedMarginHeadroomPercent ?? 0)
            ))
        }

        for category in financials.categoryBudgets where category.isNearLimit {
            results.append(MarginAlert(
                id: "\(snapshot.jobID.uuidString).near.\(category.id)",
                jobID: snapshot.jobID,
                jobName: snapshot.jobName,
                kind: .categoryNearLimit,
                severity: .warning,
                message: "\(category.title) \(usageVerb(for: category)) used \(MoneyFormat.percent(ratio: category.utilization)) of its budget",
                sortAmount: category.utilization ?? 0
            ))
        }

        if financials.projectedProfitVsExpected < 0 {
            results.append(MarginAlert(
                id: "\(snapshot.jobID.uuidString).below-expected-profit",
                jobID: snapshot.jobID,
                jobName: snapshot.jobName,
                kind: .belowExpectedProfit,
                severity: .warning,
                message: "You’re \(MoneyFormat.usd(abs(financials.projectedProfitVsExpected))) below expected profit",
                sortAmount: abs(financials.projectedProfitVsExpected)
            ))
        }

        return results
    }

    /// Locale-aware for the same reason ``MoneyFormat/percent(ratio:locale:)``
    /// is: an alert reads `"Materials are 12% over budget"` right beside an
    /// amount that already follows the device.
    private static func decimalText(
        _ value: Decimal,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.locale = locale
        return formatter.string(from: value as NSDecimalNumber) ?? "0"
    }

    private static func overBudgetVerb(for category: CategoryBudget) -> String {
        category.title == "Materials" ? "are" : "is"
    }

    private static func usageVerb(for category: CategoryBudget) -> String {
        category.title == "Materials" ? "have" : "has"
    }
}
