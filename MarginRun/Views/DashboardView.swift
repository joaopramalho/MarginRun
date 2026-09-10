import SwiftUI
import SwiftData

struct DashboardView: View {
    @Query(sort: \Job.createdAt, order: .reverse) private var jobs: [Job]
    @StateObject private var notificationService = MarginNotificationService()
    @EnvironmentObject private var subscriptions: SubscriptionStore
    @State private var paywallFeature: ProFeature?
    @State private var isCreatingJob = false

    private var activeJobs: [Job] {
        jobs.filter { $0.status == .active }
    }

    /// Dashboard is the launch tab, so its empty state is the first thing a new
    /// contractor sees. It used to name another tab and offer no way to get
    /// there — a screen that describes the next step but does not perform it
    /// leaves the decision to the customer at exactly the point they have the
    /// least reason to make it. The gate is the same one History applies, so a
    /// free account still meets the limit at the limit, not before.
    private func startCreatingJob() {
        guard subscriptions.requireActiveJobSlot(
            activeJobCount: activeJobs.count,
            presenting: $paywallFeature
        ) else { return }
        isCreatingJob = true
    }

    private var marginAlerts: [MarginAlert] {
        MarginAlertEngine.alerts(for: activeJobs.map { job in
            MarginAlertJobSnapshot(
                jobID: job.id,
                jobName: job.name,
                targetMarginPercent: job.targetMargin,
                financials: job.financials
            )
        })
    }

    private var portfolio: PortfolioFinancials {
        PortfolioFinancials(
            snapshots: jobs.map { job in
                let financials = job.financials
                let isActive = job.status == .active
                let completionReport = job.completionReport
                return PortfolioJobSnapshot(
                    isActive: isActive,
                    isAtRisk: job.isAtRisk,
                    revenue: isActive ? financials.totalRevenue : completionReport.totalRevenue,
                    projectedProfit: financials.projectedProfit,
                    actualProfit: isActive ? financials.actualProfit : completionReport.actualProfit
                )
            }
        )
    }

    /// Nothing has ever been tracked. Distinct from "no *active* jobs", which
    /// is a real portfolio that happens to be between jobs.
    private var isFirstRun: Bool { jobs.isEmpty }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if isFirstRun {
                    firstRunInvitation
                } else {
                    portfolioOverview

                    dashboardSection("Top alerts") {
                        if !subscriptions.isUnlocked(.marginAlerts) {
                            marginAlertsUpsell
                        } else if marginAlerts.isEmpty {
                            Label("No active job alerts", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(18)
                                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(marginAlerts.prefix(3))) { alert in
                                    if let job = activeJobs.first(where: { $0.id == alert.jobID }) {
                                        NavigationLink {
                                            JobDetailView(job: job)
                                        } label: {
                                            alertRow(alert)
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    if alert.id != marginAlerts.prefix(3).last?.id {
                                        Divider()
                                            .padding(.leading, 44)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                        }

                        if subscriptions.isUnlocked(.marginAlerts) {
                            notificationPermissionRow
                        }
                    }

                    dashboardSection("Active jobs") {
                        if activeJobs.isEmpty {
                            ContentUnavailableView {
                                Label("No active jobs", systemImage: "hammer")
                            } description: {
                                Text("Create a job and MarginRun starts tracking its budget and margin as costs land.")
                            } actions: {
                                Button("Create Job") {
                                    startCreatingJob()
                                }
                                .accessibilityIdentifier("dashboardCreateJobButton")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(activeJobs) { job in
                                    NavigationLink {
                                        JobDetailView(job: job)
                                    } label: {
                                        JobSummaryRow(job: job)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.vertical, 14)
                                    }
                                    .buttonStyle(.plain)

                                    if job.id != activeJobs.last?.id {
                                        Divider()
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 36)
        }
        .navigationTitle("Dashboard")
        .task(id: notificationSyncID) {
            // Margin alerts are Pro. The financial calculations above still run
            // for everyone; only the watching and notifying is withheld.
            guard subscriptions.isUnlocked(.marginAlerts) else { return }
            await notificationService.refreshAndSync(alerts: marginAlerts)
        }
        .sheet(isPresented: $isCreatingJob) {
            CreateJobView(source: .dashboardEmptyState)
        }
        .proPaywall(for: $paywallFeature) { feature in
            // Buying Pro because the job limit was reached should open the
            // create sheet, not return to the button that was blocked.
            if feature == .unlimitedJobs { isCreatingJob = true }
        }
    }

    /// The whole dashboard on a brand new account.
    ///
    /// What used to render here was a portfolio card reading zero across zero
    /// jobs, a locked-feature upsell for alerts with nothing to watch, and —
    /// below the fold, under the tab bar — the one thing that matters. Three
    /// blocks of chrome ahead of the only available action is an attention
    /// hierarchy pointing away from activation, and selling a Pro feature to
    /// someone who has not yet tracked anything asks before any value has
    /// arrived. Both come back the moment there is a first job to describe.
    private var firstRunInvitation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "hammer.fill")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Track your first job")
                .font(.title.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("Add what you're charging and what you expect it to cost. MarginRun tracks the margin from there, and tells you when a job starts eating it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                startCreatingJob()
            } label: {
                Text("Create Job")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
            .accessibilityIdentifier("dashboardCreateJobButton")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    /// Re-runs when the alert set changes *or* when Pro is gained or lost, so a
    /// purchase starts the watching immediately without an app restart.
    private var notificationSyncID: String {
        "\(subscriptions.isPro)|\(marginAlerts.map(\.id).joined(separator: "|"))"
    }

    private var portfolioOverview: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Projected profit")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(MoneyFormat.usd(portfolio.activeProjectedProfit))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .tracking(-1.2)
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                Text(activeJobsSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 0) {
                overviewMetric("Active revenue", MoneyFormat.usd(portfolio.activeRevenue))
                Divider()
                    .padding(.horizontal, 16)
                overviewMetric("Average margin", MoneyFormat.percent(ratio: portfolio.activeWeightedMargin))
            }

            Divider()

            HStack(spacing: 0) {
                countMetric("Active jobs", value: portfolio.activeJobCount, color: .primary)
                Spacer()
                countMetric(
                    "Jobs at risk",
                    value: portfolio.atRiskJobCount,
                    color: portfolio.atRiskJobCount > 0 ? .orange : .green
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
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func countMetric(_ title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Text("\(value)")
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func dashboardSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.bold())
            content()
        }
    }

    /// Names how many jobs need attention without pretending every warning is
    /// a budget overrun: margin-only problems belong in this count too.
    private var marginAlertsUpsell: some View {
        ProUpsellRow(
            feature: .marginAlerts,
            title: marginAlerts.isEmpty
                ? "Watch every budget automatically"
                : "\(marginAlerts.count) job\(marginAlerts.count == 1 ? " needs" : "s need") attention",
            detail: "Pro alerts you the moment a job starts eating its margin."
        ) {
            subscriptions.requirePro(.marginAlerts, presenting: $paywallFeature)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("marginAlertsUpsell")
    }

    @ViewBuilder
    private var notificationPermissionRow: some View {
        if notificationService.canRequestPermission && !marginAlerts.isEmpty {
            Button {
                Task {
                    await notificationService.requestPermissionAndSync(alerts: marginAlerts)
                }
            } label: {
                Label("Enable local margin notifications", systemImage: "bell.badge")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.top, 4)
        } else if notificationService.notificationsDenied && !marginAlerts.isEmpty {
            Label("Margin notifications are off in iOS Settings", systemImage: "bell.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private func alertRow(_ alert: MarginAlert) -> some View {
        HStack(spacing: 12) {
            Image(systemName: alert.severity == .critical
                ? "exclamationmark.triangle.fill"
                : "exclamationmark.circle.fill")
                .foregroundStyle(alert.severity == .critical ? Color.red : Color.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.jobName)
                    .fontWeight(.semibold)
                Text(alert.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var activeJobsSubtitle: String {
        let noun = portfolio.activeJobCount == 1 ? "job" : "jobs"
        return "Across \(portfolio.activeJobCount) active \(noun)"
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
    .modelContainer(PreviewSupport.container())
    .environmentObject(SubscriptionStore(entitlementOverride: false))
}
