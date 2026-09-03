import SwiftData
import SwiftUI

struct InsightsView: View {
    @Query(sort: \Job.createdAt, order: .reverse) private var jobs: [Job]
    @EnvironmentObject private var analytics: AnalyticsService
    @State private var selectedPeriod: InsightsPeriod = .days30

    private var completedJobs: [Job] {
        jobs.filter { $0.status == .completed }
    }

    private var snapshots: [CompletedJobInsightSnapshot] {
        completedJobs.map { job in
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
        }
    }

    private var insights: InsightsFinancials {
        InsightsFinancials(snapshots: snapshots, period: selectedPeriod)
    }

    /// All-time figures, used only to make the locked state concrete.
    private var allTimeInsights: InsightsFinancials {
        InsightsFinancials(snapshots: snapshots, period: .allTime)
    }

    var body: some View {
        ProGate(
            feature: .insights,
            title: lockedTitle,
            message: lockedMessage
        ) {
            lockedTeaser
        } content: {
            insightsContent
        }
        .navigationTitle("Insights")
        // Reported whether or not the customer is entitled: the locked view is
        // still a visit to Insights, and the gap between the two is the whole
        // conversion question for this tab.
        .task { analytics.track(.insightsOpened) }
    }

    /// Points at the work already sitting in the app rather than describing a
    /// feature — and says it the way the customer would. The earlier wording
    /// counted jobs as "unanalyzed", which reads as a system status about a
    /// record rather than an offer about their own job.
    private var lockedTitle: String {
        let count = allTimeInsights.completedJobCount
        guard count > 0 else { return "Insights is part of Pro" }
        return count == 1
            ? "See what this job tells you."
            : "See what your jobs are telling you."
    }

    private var lockedMessage: String {
        let count = allTimeInsights.completedJobCount
        guard count > 0 else {
            return "Once you complete a job, Pro shows where your margin actually went."
        }

        // The work the customer already did leads, in their own terms, and the
        // offer follows as its own sentence. `revenue` is the total across
        // every completed job, so calling it "a job" is only true when there
        // is one — the plural says what the number actually covers.
        let amount = MoneyFormat.wholeUnits(allTimeInsights.revenue)
        let tracked = count == 1
            ? "You tracked \(MoneyFormat.article(for: allTimeInsights.revenue)) \(amount) job."
            : "You tracked \(amount) of work across \(count) jobs."

        return "\(tracked) Pro shows where the margin went and what affected the result."
    }

    /// Real metric names with their values withheld — the customer sees exactly
    /// what is behind the gate instead of a generic feature list.
    private var lockedTeaser: some View {
        VStack(spacing: 0) {
            LockedMetricRow(label: "Overall margin", placeholder: "00.0%")
            Divider()
            LockedMetricRow(label: "Biggest profit miss", placeholder: "$0,000.00")
            Divider()
            LockedMetricRow(label: "Most over-budget category", placeholder: "Materials")
        }
        .padding(.horizontal, 16)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
    }

    private var insightsContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                periodPicker

                if insights.completedJobCount == 0 {
                    emptyState
                } else if insights.completedJobCount == 1 {
                    overview
                    comparisonPendingState
                } else {
                    overview
                    jobPerformance
                    costPattern
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 36)
        }
    }

    private var periodPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Period", selection: $selectedPeriod) {
                ForEach(InsightsPeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.segmented)

            Text("Completed jobs · \(selectedPeriod.description)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No completed jobs", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text("Complete a job or choose a wider date range to see financial insights.")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profit")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(MoneyFormat.usd(insights.profit))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .tracking(-1.2)
                    .monospacedDigit()
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                Text(completedJobsSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 0) {
                overviewMetric("Revenue", MoneyFormat.usd(insights.revenue))
                Divider()
                    .padding(.horizontal, 16)
                overviewMetric(
                    "Overall margin",
                    MoneyFormat.percent(ratio: insights.weightedActualMargin)
                )
            }
        }
        .padding(22)
        .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 26))
        .accessibilityElement(children: .contain)
    }

    private func overviewMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var jobPerformance: some View {
        insightsSection("Job performance") {
            VStack(spacing: 0) {
                if let best = insights.bestCompletedJob {
                    performanceLink(
                        label: "Best completed job",
                        icon: "arrow.up.right",
                        color: best.actualProfit >= 0 ? .green : .red,
                        valueColor: best.actualProfit >= 0 ? .green : .red,
                        snapshot: best,
                        value: MoneyFormat.usd(best.actualProfit),
                        detail: "Actual profit · \(MoneyFormat.percent(ratio: best.actualMargin)) margin"
                    )
                }

                Divider().padding(.leading, 52)

                if let worst = insights.worstCompletedJob {
                    performanceLink(
                        label: "Worst completed job",
                        icon: "arrow.down.right",
                        color: worst.actualProfit >= 0 ? .orange : .red,
                        valueColor: worst.actualProfit >= 0 ? .primary : .red,
                        snapshot: worst,
                        value: MoneyFormat.usd(worst.actualProfit),
                        detail: "Actual profit · \(MoneyFormat.percent(ratio: worst.actualMargin)) margin"
                    )
                }

                Divider().padding(.leading, 52)

                if let miss = insights.biggestMissVsEstimate {
                    performanceLink(
                        label: "Biggest miss vs estimate",
                        icon: "scope",
                        color: .red,
                        valueColor: .red,
                        snapshot: miss,
                        // The qualifier belongs in the detail line, not glued
                        // to the number: "$2,080.00 below" is wide enough to
                        // wrap, and the other two rows in this section carry a
                        // bare amount. `biggestMissVsEstimate` already filters
                        // to negative variance, so "below" is always true.
                        value: MoneyFormat.usd(abs(miss.profitVariance)),
                        detail: "Below expected profit"
                    )
                } else {
                    positiveVarianceRow
                }
            }
            .padding(.horizontal, 16)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var costPattern: some View {
        insightsSection("Cost pattern") {
            HStack(spacing: 14) {
                Image(systemName: insights.mostOverBudgetCategory == nil
                    ? "checkmark.circle.fill"
                    : "chart.bar.fill")
                    .font(.headline)
                    .foregroundStyle(insights.mostOverBudgetCategory == nil ? Color.green : Color.red)
                    .frame(width: 28, height: 28)
                    .background(
                        (insights.mostOverBudgetCategory == nil ? Color.green : Color.red).opacity(0.1),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Most over-budget category")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let category = insights.mostOverBudgetCategory {
                        Text(category.title)
                            .font(.headline)
                        Text("\(MoneyFormat.usd(category.amount)) over budget · \(affectedJobsText(category.affectedJobCount))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text("No category overruns")
                            .font(.headline)
                        Text("Completed jobs stayed within category budgets.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func performanceLink(
        label: String,
        icon: String,
        color: Color,
        valueColor: Color,
        snapshot: CompletedJobInsightSnapshot,
        value: String,
        detail: String
    ) -> some View {
        Group {
            if let job = completedJobs.first(where: { $0.id == snapshot.id }) {
                NavigationLink {
                    JobDetailView(job: job)
                } label: {
                    performanceRow(
                        label: label,
                        icon: icon,
                        color: color,
                        valueColor: valueColor,
                        snapshot: snapshot,
                        value: value,
                        detail: detail,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                performanceRow(
                    label: label,
                    icon: icon,
                    color: color,
                    valueColor: valueColor,
                    snapshot: snapshot,
                    value: value,
                    detail: detail,
                    showsChevron: false
                )
            }
        }
    }

    private func performanceRow(
        label: String,
        icon: String,
        color: Color,
        valueColor: Color,
        snapshot: CompletedJobInsightSnapshot,
        value: String,
        detail: String,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.bold())
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(snapshot.name)
                    .font(.headline)
                Text(snapshot.customerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 3) {
                Text(value)
                    .font(.subheadline.bold())
                    .foregroundStyle(valueColor)
                    .monospacedDigit()
                    // The VStack trailing-aligns the block, but the lines
                    // *inside* a wrapped Text keep their own default leading
                    // alignment — which is what let the second line drift left.
                    .multilineTextAlignment(.trailing)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var positiveVarianceRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.subheadline.bold())
                .foregroundStyle(.green)
                .frame(width: 28, height: 28)
                .background(Color.green.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Biggest miss vs estimate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("No profit misses")
                    .font(.headline)
                Text("Every completed job met or beat expected profit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 14)
    }

    /// A single result can produce totals, but it cannot produce a meaningful
    /// best/worst comparison without repeating the same job under both labels.
    private var comparisonPendingState: some View {
        Label {
            Text("Complete another job to compare performance.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "chart.bar.xaxis")
                .foregroundStyle(.tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("insightsComparisonPending")
    }

    private func insightsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.bold())
            content()
        }
    }

    private var completedJobsSubtitle: String {
        let noun = insights.completedJobCount == 1 ? "job" : "jobs"
        return "Final results across \(insights.completedJobCount) completed \(noun)"
    }

    private func affectedJobsText(_ count: Int) -> String {
        count == 1 ? "1 job affected" : "\(count) jobs affected"
    }
}

#Preview("Insights — Pro") {
    NavigationStack {
        InsightsView()
    }
    .modelContainer(PreviewSupport.container())
    .environmentObject(SubscriptionStore(entitlementOverride: true))
}

#Preview("Insights — Locked") {
    NavigationStack {
        InsightsView()
    }
    .modelContainer(PreviewSupport.container())
    .environmentObject(SubscriptionStore(entitlementOverride: false))
}
