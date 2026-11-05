import SwiftUI
import SwiftData

struct JobsListView: View {
    @Query(sort: \Job.createdAt, order: .reverse) private var jobs: [Job]
    @EnvironmentObject private var subscriptions: SubscriptionStore
    @State private var isCreatingJob = false
    @State private var paywallFeature: ProFeature?
    @State private var selectedFilter: JobHistoryFilter = .active
    @State private var searchText = ""
    /// Where the create sheet was opened from, so the funnel can tell a
    /// deliberate "Create Job" from the empty state's prompt.
    @State private var creationSource: JobCreationSource = .history

    /// Only active jobs count toward the free limit, so completing work always
    /// frees a slot instead of forcing an upgrade.
    private var activeJobCount: Int {
        jobs.filter { $0.status == .active }.count
    }

    private func startCreatingJob(from source: JobCreationSource) {
        creationSource = source
        guard subscriptions.requireActiveJobSlot(
            activeJobCount: activeJobCount,
            presenting: $paywallFeature
        ) else { return }
        isCreatingJob = true
    }

    private var filteredJobs: [Job] {
        jobs.filter { job in
            guard job.status == selectedFilter.status else { return false }
            guard !searchText.isEmpty else { return true }
            return job.name.localizedCaseInsensitiveContains(searchText)
                || job.customerName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Job status", selection: $selectedFilter) {
                    ForEach(JobHistoryFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                freePlanSlotMeter
            }

            Section(selectedFilter.sectionTitle) {
                ForEach(filteredJobs) { job in
                    NavigationLink {
                        JobDetailView(job: job)
                    } label: {
                        JobSummaryRow(job: job)
                    }
                }
            }
        }
        .navigationTitle("History")
        .searchable(text: $searchText, prompt: "Job or customer")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Create Job") {
                    startCreatingJob(from: .history)
                }
                .accessibilityIdentifier("createJobButton")
            }
        }
        .sheet(isPresented: $isCreatingJob) {
            CreateJobView(source: creationSource)
        }
        .proPaywall(for: $paywallFeature) { feature in
            // Buying Pro because the third job was blocked should open the
            // create sheet, not return to the button that was blocked.
            if feature == .unlimitedJobs { isCreatingJob = true }
        }
        .overlay {
            if filteredJobs.isEmpty {
                ContentUnavailableView {
                    Label(emptyStateTitle, systemImage: selectedFilter.systemImage)
                } description: {
                    Text(emptyStateDescription)
                } actions: {
                    if jobs.isEmpty && searchText.isEmpty {
                        Button("Create Job") {
                            startCreatingJob(from: .historyEmptyState)
                        }
                        .accessibilityIdentifier("createJobEmptyStateButton")
                    }
                }
                .offset(y: 70)
            }
        }
    }

    /// How much of the free plan is spoken for, shown before it blocks anything.
    ///
    /// A limit a customer only meets by being stopped reads as a toll booth; the
    /// same limit, visible while there is still room, reads as the shape of the
    /// plan they chose. It also means the last free slot is *seen* being spent,
    /// which is the moment the upgrade actually means something — and the offer
    /// appears only then, never as a standing advertisement.
    ///
    /// Completing a job frees a slot, so that route is named first: the upgrade
    /// has to be the better option, not the only one.
    @ViewBuilder
    private var freePlanSlotMeter: some View {
        if !subscriptions.isPro, selectedFilter == .active, searchText.isEmpty {
            let limit = FreePlanLimits.maxActiveJobs
            let isAtLimit = activeJobCount >= limit
            let remaining = max(0, limit - activeJobCount)

            Group {
                if isAtLimit {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(slotMessage(remaining: remaining, limit: limit))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("Complete an active job to free a slot.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            subscriptions.requirePro(.unlimitedJobs, presenting: $paywallFeature)
                        } label: {
                            HStack(spacing: 8) {
                                Text("Unlock Unlimited Jobs")
                                ProBadge()
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.leading)
                        .accessibilityLabel("Unlock Unlimited Jobs")
                        .accessibilityHint("Opens MarginRun Pro plans")
                        .accessibilityIdentifier("freePlanSlotUpsell")
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                } else {
                    Text(slotMessage(remaining: remaining, limit: limit))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("freePlanSlotMeter")
        }
    }

    private func slotMessage(remaining: Int, limit: Int) -> String {
        if remaining == 0 { return "Free active job limit reached" }
        if remaining == 1 { return "1 free active job slot remaining" }
        return "Free includes \(limit) active job slots"
    }

    private var emptyStateTitle: String {
        if !searchText.isEmpty { return "No matches" }
        return selectedFilter == .active ? "No active jobs" : "No completed jobs"
    }

    private var emptyStateDescription: String {
        if !searchText.isEmpty {
            return "Try searching for a different job or customer."
        }
        return selectedFilter == .active
            ? "Create a job to start tracking its budget."
            : "Completed jobs and their final results will appear here."
    }
}

private enum JobHistoryFilter: String, CaseIterable, Identifiable {
    case active
    case completed

    var id: String { rawValue }

    var status: JobStatus {
        switch self {
        case .active: .active
        case .completed: .completed
        }
    }

    var title: String {
        switch self {
        case .active: "Active"
        case .completed: "Completed"
        }
    }

    var sectionTitle: String {
        switch self {
        case .active: "Active jobs"
        case .completed: "Completed jobs"
        }
    }

    var systemImage: String {
        switch self {
        case .active: "hammer"
        case .completed: "checkmark.seal"
        }
    }
}

#Preview {
    NavigationStack {
        JobsListView()
    }
    .modelContainer(PreviewSupport.container())
    .environmentObject(SubscriptionStore(entitlementOverride: false))
}
