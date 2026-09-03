import SwiftUI
import SwiftData

struct JobDetailView: View {
    @Bindable var job: Job
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var laborTimer: LaborTimerStore
    @EnvironmentObject private var subscriptions: SubscriptionStore
    @EnvironmentObject private var analytics: AnalyticsService
    @State private var isAddingExpense = false
    @State private var isAddingLabor = false
    @State private var isAddingExtraRevenue = false
    @State private var paywallFeature: ProFeature?
    @State private var isShowingLaborTimer = false
    @State private var isEnteringTimerRate = false
    @State private var timerHourlyCostText = ""
    @State private var isConfirmingCompletion = false
    @State private var completionErrorMessage: String?
    @State private var costEntryErrorMessage: String?
    @State private var selectedReceiptExpense: Expense?
    @State private var selectedExtraRevenue: ExtraRevenue?

    private var financials: JobFinancials { job.financials }
    private var completionReport: JobCompletionReport { job.completionReport }
    private var jobAlerts: [MarginAlert] {
        MarginAlertEngine.alerts(for: [MarginAlertJobSnapshot(
            jobID: job.id,
            jobName: job.name,
            targetMarginPercent: job.targetMargin,
            financials: financials
        )])
    }

    var body: some View {
        List {
            if job.status == .active {
                activeJobHealthSection
                activeAlertsSection
            } else {
                completedJobResultsSection
            }

            extraRevenueSection

            if shouldShowMarginWarning {
                Section {
                    Text(marginWarningText)
                        .foregroundStyle(.orange)
                }
            }

            if job.status == .active {
                activeCategoryBudgetSection
            } else {
                completedCostDriversSection
            }

            laborSection

            Section("Expenses") {
                if job.expenses.isEmpty {
                    Text("No expenses yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(job.expenses.sorted { $0.createdAt > $1.createdAt }) { expense in
                        HStack(alignment: .top, spacing: 12) {
                            if let receiptFileName = expense.receiptFileName {
                                Button {
                                    selectedReceiptExpense = expense
                                } label: {
                                    ReceiptThumbnailView(fileName: receiptFileName)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens receipt details")
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(expense.category.title)
                                    Spacer()
                                    Text(MoneyFormat.usd(expense.amount))
                                        .monospacedDigit()
                                }
                                if !expense.vendor.isEmpty {
                                    Text(expense.vendor)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if !expense.note.isEmpty {
                                    Text(expense.note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .padding(.vertical, expense.receiptFileName == nil ? 0 : 3)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if job.status == .active {
                                Button("Delete", role: .destructive) {
                                    deleteExpense(expense)
                                }
                            }
                        }
                    }
                }
            }

            if job.status == .active {
                Section {
                    Button("Complete job") {
                        isConfirmingCompletion = true
                    }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("completeJobButton")
                    // Attached to the button, not to the List. SwiftUI anchors
                    // a confirmation dialog to whatever view carries the
                    // modifier, so hanging it off the whole screen points the
                    // popover at the middle of the list instead of at the
                    // control the customer just tapped.
                    .confirmationDialog(
                        "Complete \(job.name)?",
                        isPresented: $isConfirmingCompletion,
                        titleVisibility: .visible
                    ) {
                        Button("Complete job") {
                            completeJob()
                        }
                        .accessibilityIdentifier("confirmCompleteJobButton")
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("MarginRun will treat \(MoneyFormat.usd(financials.actualCost)) as the final cost. Confirm that all expenses and labor have been entered.")
                    }
                } footer: {
                    Text("Confirm only after every cost has been logged. This locks the job and records its final profit and margin.")
                }
            }
        }
        .navigationTitle(job.name)
        .toolbar {
            if job.status == .active {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Expense") {
                        isAddingExpense = true
                    }
                    .accessibilityIdentifier("addExpenseButton")
                }
            }
        }
        .sheet(isPresented: $isAddingExpense) {
            AddExpenseView(job: job)
        }
        .sheet(isPresented: $isAddingLabor) {
            AddLaborView(job: job)
        }
        .sheet(isPresented: $isAddingExtraRevenue) {
            AddExtraRevenueView(job: job)
        }
        .proPaywall(for: $paywallFeature) { feature in
            // Resume whatever the customer was blocked from doing, so a
            // purchase lands them in the flow rather than back on the button.
            switch feature {
            case .laborTimer: startOrShowTimer()
            case .extraRevenue: isAddingExtraRevenue = true
            default: break
            }
        }
        .sheet(item: $selectedExtraRevenue) { extraRevenue in
            AddExtraRevenueView(job: job, extraRevenue: extraRevenue)
        }
        .sheet(isPresented: $isShowingLaborTimer) {
            NavigationStack {
                LaborTimerView(showsCloseButton: true)
            }
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $selectedReceiptExpense) { expense in
            ReceiptDetailView(expense: expense, allowsEditing: job.status == .active)
        }
        .alert(
            "Couldn’t complete job",
            isPresented: Binding(
                get: { completionErrorMessage != nil },
                set: { if !$0 { completionErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(completionErrorMessage ?? "The job could not be saved.")
        }
        .alert(
            "Cost entry update",
            isPresented: Binding(
                get: { costEntryErrorMessage != nil },
                set: { if !$0 { costEntryErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(costEntryErrorMessage ?? "The cost entry could not be updated.")
        }
        .alert("Start Work", isPresented: $isEnteringTimerRate) {
            TextField("Hourly cost", text: $timerHourlyCostText)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {}
            Button("Start") {
                startTimerWithEnteredRate()
            }
            .disabled(enteredTimerHourlyCost == nil)
        } message: {
            Text("Enter the hourly cost for this work session.")
        }
    }

    private var laborSection: some View {
        Section {
            if job.laborEntries.isEmpty {
                Text("No labor logged yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(job.laborEntries.sorted { $0.createdAt > $1.createdAt }) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Text(MoneyFormat.usd(entry.cost))
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }

                        Text("\(formattedHours(entry.hours)) × \(MoneyFormat.usd(entry.hourlyCost))/hr")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        if !entry.note.isEmpty {
                            Text(entry.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 2)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if job.status == .active {
                            Button("Delete", role: .destructive) {
                                deleteLaborEntry(entry)
                            }
                        }
                    }
                }
            }

            if job.status == .active {
                Button {
                    isAddingLabor = true
                } label: {
                    Label("Add Labor", systemImage: "person.badge.clock")
                        .fontWeight(.medium)
                }
                .accessibilityIdentifier("addLaborButton")

                Button {
                    startOrShowTimer()
                } label: {
                    Label(timerButtonTitle, systemImage: "timer")
                        .fontWeight(.medium)
                }
            }
        } header: {
            Text("Labor")
        } footer: {
            if !job.laborEntries.isEmpty {
                Text("\(formattedHours(trackedLaborHours)) logged · \(MoneyFormat.usd(trackedLaborCost)) tracked labor")
            }
        }
    }

    private var extraRevenueSection: some View {
        Section {
            if job.extraRevenues.isEmpty {
                Text("No extra revenue yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(job.extraRevenues.sorted { $0.createdAt > $1.createdAt }) { extraRevenue in
                    if job.status == .active {
                        Button {
                            // Reading an existing record is always free; only
                            // opening it for edit is gated, so a lapsed
                            // subscription never hides work already recorded.
                            guard subscriptions.requirePro(
                                .extraRevenue,
                                presenting: $paywallFeature
                            ) else { return }
                            selectedExtraRevenue = extraRevenue
                        } label: {
                            extraRevenueRow(extraRevenue)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Delete", role: .destructive) {
                                deleteExtraRevenue(extraRevenue)
                            }
                        }
                    } else {
                        extraRevenueRow(extraRevenue)
                    }
                }
            }

            if job.status == .active {
                Button {
                    guard subscriptions.requirePro(
                        .extraRevenue,
                        presenting: $paywallFeature
                    ) else { return }
                    isAddingExtraRevenue = true
                } label: {
                    Label("Add Extra Revenue", systemImage: "plus.circle")
                        .fontWeight(.medium)
                }
            }
        } header: {
            Text("Extra revenue")
        } footer: {
            if !job.extraRevenues.isEmpty {
                Text("Approved \(MoneyFormat.usd(financials.extraRevenue)) · Projected margin \(MoneyFormat.percent(ratio: financials.projectedMargin))")
            }
        }
    }

    private func extraRevenueRow(_ extraRevenue: ExtraRevenue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(extraRevenue.extraDescription)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Spacer()
                Label(
                    extraRevenue.isApproved ? "Approved" : "Not approved",
                    systemImage: extraRevenue.isApproved ? "checkmark.circle.fill" : "clock.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(extraRevenue.isApproved ? Color.green : Color.orange)
            }

            Text("+\(MoneyFormat.usd(extraRevenue.revenueAmount)) revenue · \(MoneyFormat.usd(extraRevenue.estimatedCost)) expected cost")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            HStack(spacing: 8) {
                Text(extraRevenue.createdAt.formatted(date: .abbreviated, time: .omitted))
                if !extraRevenue.note.isEmpty {
                    Text("·")
                    Text(extraRevenue.note)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var trackedLaborHours: Decimal {
        job.laborEntries.reduce(0) { $0 + $1.hours }
    }

    private var trackedLaborCost: Decimal {
        job.laborEntries.reduce(0) { $0 + $1.cost }
    }

    private var timerButtonTitle: String {
        laborTimer.session == nil ? "Start Work" : "View Timer"
    }

    private func startOrShowTimer() {
        // Viewing a running timer stays free; only starting one is Pro, so a
        // subscription that lapses mid-job never strands the timer.
        if laborTimer.session != nil {
            isShowingLaborTimer = true
            return
        }

        guard subscriptions.requirePro(.laborTimer, presenting: $paywallFeature) else { return }

        let preferences = AppPreferences()
        guard let hourlyCost = preferences.defaultHourlyCost else {
            timerHourlyCostText = preferences.defaultHourlyCostText
            isEnteringTimerRate = true
            return
        }

        startTimer(hourlyCost: hourlyCost)
    }

    private var enteredTimerHourlyCost: Decimal? {
        guard let value = MoneyInput.parse(timerHourlyCostText), value > 0 else { return nil }
        return value
    }

    private func startTimerWithEnteredRate() {
        guard let hourlyCost = enteredTimerHourlyCost else { return }
        startTimer(hourlyCost: hourlyCost)
    }

    private func startTimer(hourlyCost: Decimal) {
        do {
            try laborTimer.start(jobID: job.id, jobName: job.name, hourlyCost: hourlyCost)
            analytics.track(.laborTimerStarted(source: .jobDetail))
            Task { @MainActor in
                // When the rate came from the alert, wait for that presentation
                // to dismiss before opening the timer sheet.
                await Task.yield()
                isShowingLaborTimer = true
            }
        } catch {
            costEntryErrorMessage = error.localizedDescription
        }
    }

    private func formattedHours(_ hours: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "en_US")
        let value = formatter.string(from: hours as NSDecimalNumber) ?? "—"
        return "\(value) \(hours == 1 ? "hour" : "hours")"
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
    }

    private var activeJobHealthSection: some View {
        Section("Job health") {
            metricRow("Contract value", MoneyFormat.usd(job.contractValue))
            metricRow("Projected profit", MoneyFormat.usd(financials.projectedProfit))
            metricRow("Projected margin", MoneyFormat.percent(ratio: financials.projectedMargin))
            metricRow(
                "Spent so far",
                "\(MoneyFormat.usd(financials.actualCost)) / \(MoneyFormat.usd(financials.estimatedTotalCost))"
            )
            metricRow("Budget remaining", MoneyFormat.usd(financials.budgetRemaining))

            Label(activeBudgetHealthText, systemImage: activeBudgetHealthIcon)
                .font(.headline)
                .foregroundStyle(activeBudgetHealthColor)
        }
    }

    @ViewBuilder
    private var activeAlertsSection: some View {
        if !jobAlerts.isEmpty {
            Section("Margin alerts") {
                ForEach(jobAlerts.prefix(4)) { alert in
                    Label {
                        Text(alert.message)
                    } icon: {
                        Image(systemName: alert.severity == .critical
                            ? "exclamationmark.triangle.fill"
                            : "exclamationmark.circle.fill")
                    }
                    .foregroundStyle(alert.severity == .critical ? Color.red : Color.orange)
                }
            }
        }
    }

    private var completedJobResultsSection: some View {
        Section("Final results") {
            metricRow("Contract value", MoneyFormat.usd(completionReport.contractValue))
            if completionReport.totalRevenue != completionReport.contractValue {
                metricRow("Total revenue", MoneyFormat.usd(completionReport.totalRevenue))
            }
            if completionReport.additionalRevenue > 0 {
                metricRow(
                    "Approved additional revenue",
                    MoneyFormat.usd(completionReport.additionalRevenue)
                )
            }
            if completionReport.additionalExpectedCost > 0 {
                metricRow(
                    "Additional expected cost",
                    MoneyFormat.usd(completionReport.additionalExpectedCost)
                )
            }
            comparisonRow(
                "Cost",
                expected: MoneyFormat.usd(completionReport.estimatedCost),
                actual: MoneyFormat.usd(completionReport.actualCost),
                expectedLabel: "Estimated"
            )
            comparisonRow(
                "Profit",
                expected: MoneyFormat.usd(completionReport.expectedProfit),
                actual: MoneyFormat.usd(completionReport.actualProfit),
                expectedLabel: "Expected"
            )
            comparisonRow(
                "Margin",
                expected: MoneyFormat.percent(ratio: completionReport.expectedMargin),
                actual: MoneyFormat.percent(ratio: completionReport.actualMargin),
                expectedLabel: "Expected"
            )

            Text(profitVarianceSummary)
                .font(.headline)
                .foregroundStyle(profitVarianceColor)
        }
    }

    private func comparisonRow(
        _ title: String,
        expected: String,
        actual: String,
        expectedLabel: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(expectedLabel) \(expected)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Actual \(actual)")
                    .fontWeight(.semibold)
            }
            .monospacedDigit()
        }
    }

    private var profitVarianceSummary: String {
        let amount = MoneyFormat.usd(abs(completionReport.profitVariance))
        if completionReport.profitVariance < 0 { return "You made \(amount) less than expected" }
        if completionReport.profitVariance > 0 { return "You made \(amount) more than expected" }
        return "You made exactly what was expected"
    }

    /// Missing the estimate is a warning; it is not a loss when the final
    /// profit itself remains positive. Red stays reserved for an actual loss.
    private var profitVarianceColor: Color {
        if completionReport.actualProfit < 0 { return .red }
        if completionReport.profitVariance < 0 { return .orange }
        return .green
    }

    private var shouldShowMarginWarning: Bool {
        job.status == .completed && completionReport.isBelowTargetMargin
    }

    private var marginWarningText: String {
        return "Actual margin is below the \(completionReport.targetMarginPercent)% target."
    }

    private var activeCategoryBudgetSection: some View {
        Section("Budget vs actual") {
            ForEach(financials.categoryBudgets) { row in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(row.title)
                        Spacer()
                        if row.isOverBudget {
                            Text("\(MoneyFormat.usd(row.variance)) over")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    Text("\(MoneyFormat.usd(row.actual)) / \(MoneyFormat.usd(row.estimated))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    ProgressView(value: progress(for: row))
                        .tint(progressColor(for: row))
                        .accessibilityLabel("\(row.title) budget used")
                        .accessibilityValue(progressAccessibilityValue(for: row))
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var completedCostDriversSection: some View {
        Section("Cost drivers") {
            if completionReport.categoryVariances.isEmpty {
                Label("Every category matched its estimate", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                ForEach(completionReport.categoryVariances) { row in
                    HStack {
                        Text(row.title)
                        Spacer()
                        Text(categoryVarianceText(row))
                            .foregroundStyle(row.variance > 0 ? .red : .green)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func categoryVarianceText(_ row: CategoryBudget) -> String {
        let amount = MoneyFormat.usd(abs(row.variance))
        return row.variance > 0 ? "\(amount) over" : "\(amount) under"
    }

    private var activeBudgetHealthText: String {
        if let category = financials.largestOverBudgetCategory {
            return "\(category.title) \(MoneyFormat.usd(category.variance)) over budget"
        }
        guard let utilization = financials.budgetUtilization else {
            return "No cost budget set"
        }
        if utilization >= Decimal(string: "0.9")! {
            return "\(MoneyFormat.percent(ratio: utilization)) of budget used"
        }
        return "On budget"
    }

    private var activeBudgetHealthIcon: String {
        if financials.largestOverBudgetCategory != nil { return "exclamationmark.triangle.fill" }
        if financials.budgetUtilization == nil { return "minus.circle.fill" }
        if financials.budgetUtilization! >= Decimal(string: "0.9")! { return "exclamationmark.circle.fill" }
        return "checkmark.circle.fill"
    }

    private var activeBudgetHealthColor: Color {
        if financials.largestOverBudgetCategory != nil { return .red }
        guard let utilization = financials.budgetUtilization else { return .secondary }
        return utilization >= Decimal(string: "0.9")! ? .orange : .green
    }

    private func progress(for row: CategoryBudget) -> Double {
        guard let utilization = row.utilization else {
            return row.actual > 0 ? 1 : 0
        }
        return min(max(NSDecimalNumber(decimal: utilization).doubleValue, 0), 1)
    }

    private func progressColor(for row: CategoryBudget) -> Color {
        if row.isOverBudget { return .red }
        guard let utilization = row.utilization else { return .secondary }
        return utilization >= Decimal(string: "0.9")! ? .orange : .green
    }

    private func progressAccessibilityValue(for row: CategoryBudget) -> String {
        if row.isOverBudget {
            return "\(MoneyFormat.usd(row.variance)) over budget"
        }
        return MoneyFormat.percent(ratio: row.utilization)
    }

    private func completeJob() {
        if laborTimer.session?.jobID == job.id {
            completionErrorMessage = "Stop and confirm or discard the active labor timer before completing this job."
            return
        }
        job.complete()
        do {
            try modelContext.save()
        } catch {
            job.discardCompletion()
            completionErrorMessage = "We couldn’t save the final result. Please try again."
            return
        }

        // Read from the frozen completion report, and reported as two flags
        // rather than as the amounts behind them.
        let report = job.completionReport
        analytics.trackJobCompleted(report: report)
    }

    private func deleteExpense(_ expense: Expense) {
        let receiptFileName = expense.receiptFileName
        modelContext.delete(expense)

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            costEntryErrorMessage = "The expense wasn’t deleted. Please try again."
            return
        }

        do {
            try ExpenseReceiptCleanup.deleteReceipt(fileName: receiptFileName)
        } catch {
            costEntryErrorMessage = "The expense was deleted, but its local receipt photo couldn’t be removed."
        }
    }

    private func deleteLaborEntry(_ entry: LaborEntry) {
        modelContext.delete(entry)

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            costEntryErrorMessage = "The labor entry wasn’t deleted. Please try again."
        }
    }

    private func deleteExtraRevenue(_ extraRevenue: ExtraRevenue) {
        modelContext.delete(extraRevenue)

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            costEntryErrorMessage = "The extra revenue wasn’t deleted. Please try again."
        }
    }
}

#Preview {
    let container = PreviewSupport.container()
    let job = (try? container.mainContext.fetch(FetchDescriptor<Job>()))?.first
        ?? MockData.kitchenRemodelJob()

    NavigationStack {
        JobDetailView(job: job)
    }
    .environmentObject(LaborTimerStore())
    .environmentObject(AnalyticsService(backend: NoOpAnalyticsBackend()))
    .modelContainer(container)
    .environmentObject(SubscriptionStore(entitlementOverride: false))
}
