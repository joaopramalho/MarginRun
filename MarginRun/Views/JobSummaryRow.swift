import SwiftUI

struct JobSummaryRow: View {
    let job: Job

    private var financials: JobFinancials { job.financials }
    private var completionReport: JobCompletionReport { job.completionReport }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(job.name)
                .font(.headline)
            Text(job.customerName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if job.status == .completed {
                completedSummary
            } else {
                activeSummary
            }
        }
    }

    private var completedSummary: some View {
        let profit = Text(MoneyFormat.usd(completionReport.actualProfit))
            .foregroundStyle(completionReport.actualProfit < 0 ? Color.red : Color.primary)
        let margin = Text("\(MoneyFormat.percent(ratio: completionReport.actualMargin)) margin")
            .foregroundStyle(completedMarginColor)

        return Text("Profit \(profit) · \(margin)\(belowTargetLabel)")
            .font(.caption)
            .monospacedDigit()
    }

    private var belowTargetLabel: Text {
        guard completionReport.isBelowTargetMargin else { return Text("") }
        return Text(" · Below target").foregroundStyle(.orange)
    }

    private var completedMarginColor: Color {
        if completionReport.actualProfit < 0 { return .red }
        if completionReport.isBelowTargetMargin { return .orange }
        return .primary
    }

    private var activeSummary: some View {
        Text("Spent \(MoneyFormat.usd(financials.actualCost)) of \(MoneyFormat.usd(financials.estimatedTotalCost)) · \(Text(activeHealthLabel).foregroundStyle(activeHealthColor))")
            .font(.caption)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }

    private var activeHealthLabel: String {
        if financials.largestOverBudgetCategory != nil { return "Over budget" }
        if financials.isProjectedMarginBelowTarget { return "Margin below target" }
        if let category = financials.highestNearLimitCategory {
            return "\(category.title) near limit"
        }
        if financials.isProjectedMarginAtRisk { return "Margin at risk" }
        guard financials.budgetUtilization != nil else { return "No budget" }
        return "On budget"
    }

    private var activeHealthColor: Color {
        if financials.largestOverBudgetCategory != nil { return .red }
        if financials.isProjectedMarginBelowTarget { return .orange }
        if financials.highestNearLimitCategory != nil { return .orange }
        if financials.isProjectedMarginAtRisk { return .orange }
        return financials.budgetUtilization == nil ? .secondary : .green
    }
}
