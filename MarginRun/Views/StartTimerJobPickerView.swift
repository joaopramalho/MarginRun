import SwiftData
import SwiftUI

struct StartTimerJobPickerView: View {
    @EnvironmentObject private var timerStore: LaborTimerStore
    @EnvironmentObject private var analytics: AnalyticsService
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Job.createdAt, order: .reverse) private var jobs: [Job]

    @State private var searchText = ""
    @State private var errorMessage: String?

    private var activeJobs: [Job] {
        jobs.filter { job in
            guard job.status == .active else { return false }
            guard !searchText.isEmpty else { return true }
            return job.name.localizedStandardContains(searchText)
                || job.customerName.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        Group {
            if jobs.contains(where: { $0.status == .active }) {
                List(activeJobs) { job in
                    Button {
                        startTimer(for: job)
                    } label: {
                        jobRow(job)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Starts the labor timer immediately")
                }
                .overlay {
                    if activeJobs.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No active jobs", systemImage: "hammer")
                } description: {
                    Text("Create a job before starting a labor timer.")
                }
            }
        }
        .navigationTitle("Choose a Job")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Job or customer")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Label("Timing starts as soon as you tap a job", systemImage: "bolt.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.bar)
        }
        .alert(
            "Couldn’t start timer",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "The timer could not be started.")
        }
    }

    private func jobRow(_ job: Job) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "hammer.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(job.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(job.customerName.isEmpty ? "No customer" : job.customerName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Image(systemName: "play.fill")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.accentColor, in: Circle())
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func startTimer(for job: Job) {
        let hourlyCost = AppPreferences().defaultHourlyCost ?? 0

        do {
            try timerStore.start(
                jobID: job.id,
                jobName: job.name,
                hourlyCost: hourlyCost
            )
            analytics.track(.laborTimerStarted(source: .timerTab))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        StartTimerJobPickerView()
    }
    .environmentObject(LaborTimerStore())
    .environmentObject(AnalyticsService(backend: NoOpAnalyticsBackend()))
    .modelContainer(PreviewSupport.container())
}
