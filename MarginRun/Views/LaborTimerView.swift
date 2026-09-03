import SwiftData
import SwiftUI
import UIKit

struct LaborTimerView: View {
    let showsCloseButton: Bool

    @EnvironmentObject private var timerStore: LaborTimerStore
    @EnvironmentObject private var subscriptions: SubscriptionStore
    @EnvironmentObject private var analytics: AnalyticsService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var jobs: [Job]

    @State private var hourlyCostText = ""
    @State private var note = ""
    @State private var errorMessage: String?
    @State private var isConfirmingDiscard = false
    @State private var isChoosingJob = false
    @State private var paywallFeature: ProFeature?
    @State private var isSaving = false
    @FocusState private var focusedField: ReviewField?

    init(showsCloseButton: Bool = false) {
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        Group {
            if let session = timerStore.session {
                timerContent(session)
            } else {
                emptyTimer
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                }
            }
        }
        // Stopping and confirming both change what the job costs; each is
        // worth a beat of feedback on a noisy site where the screen is glanced
        // at rather than watched.
        .sensoryFeedback(.impact(weight: .medium), trigger: timerStore.session?.isRunning)
        .onAppear(perform: loadReviewFields)
        .onChange(of: timerStore.session?.id) { _, _ in loadReviewFields() }
        .proPaywall(for: $paywallFeature) { feature in
            // Buying Pro from the empty timer should continue straight into
            // choosing a job, which is what the customer tapped for.
            if feature == .laborTimer { isChoosingJob = true }
        }
        .sheet(isPresented: $isChoosingJob) {
            NavigationStack {
                StartTimerJobPickerView()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert(
            "Timer update",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "The timer could not be updated.")
        }
    }

    private var navigationTitle: String {
        guard let session = timerStore.session else { return "Labor Timer" }
        return session.isRunning ? "Timer" : "Review Work"
    }

    @ViewBuilder
    private func timerContent(_ session: LaborTimerSession) -> some View {
        if session.isRunning {
            runningTimer(session)
        } else {
            reviewTimer(session)
        }
    }

    private var emptyTimer: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 52)

                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 104, height: 104)
                    Image(systemName: "timer")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(spacing: 10) {
                    Text("Ready when you are")
                        .font(.title2.bold())
                    Text("Choose an active job, then start the timer when work begins. MarginRun keeps counting if you close the app.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 330)
                }

                Button {
                    guard subscriptions.requirePro(
                        .laborTimer,
                        presenting: $paywallFeature
                    ) else { return }
                    isChoosingJob = true
                } label: {
                    Label("Choose a Job", systemImage: "hammer")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 6)

                VStack(alignment: .leading, spacing: 14) {
                    instructionRow(number: 1, text: "Choose an active job")
                    instructionRow(number: 2, text: "Timing starts immediately")
                    instructionRow(number: 3, text: "Stop, review, and save")
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.12), in: Circle())
            Text(text)
                .font(.subheadline.weight(.medium))
        }
    }

    private func runningTimer(_ session: LaborTimerSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                jobHeader(session, status: "Tracking now", statusColor: .green)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 12) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("LIVE")
                                .font(.caption2.bold())
                                .tracking(1.3)
                                .foregroundStyle(.secondary)
                        }

                        Text(Self.durationText(session.durationSeconds(at: context.date)))
                            .font(.system(size: 58, weight: .bold, design: .rounded))
                            .tracking(-1.8)
                            .monospacedDigit()
                            .minimumScaleFactor(0.66)
                            .lineLimit(1)
                            .accessibilityLabel("Elapsed time")
                            .accessibilityValue(Self.durationText(session.durationSeconds(at: context.date)))

                        Text("Started \(session.startedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Divider()
                            .padding(.vertical, 4)

                        HStack(spacing: 0) {
                            liveMetric(
                                title: "Hourly cost",
                                value: runningHourlyCostText(session)
                            )
                            Divider()
                                .padding(.horizontal, 18)
                            liveMetric(
                                title: "Cost so far",
                                value: runningCostText(session, at: context.date)
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity)
                    .background(
                        Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 26)
                    )
                    .accessibilityElement(children: .contain)
                }

                Label("Timer continues if you close MarginRun", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 140)
        }
        .safeAreaInset(edge: .bottom) {
            runningActions
        }
    }

    private func jobHeader(
        _ session: LaborTimerSession,
        status: String,
        statusColor: Color
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "hammer.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 3) {
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                Text(session.jobName)
                    .font(.headline)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func liveMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .minimumScaleFactor(0.72)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var runningActions: some View {
        VStack(spacing: 10) {
            Button {
                stopTimer()
            } label: {
                Label("Stop Work", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.red)

            Button("Discard Timer", role: .destructive) {
                isConfirmingDiscard = true
            }
            .font(.subheadline.weight(.medium))
            .discardTimerConfirmation(isPresented: $isConfirmingDiscard, discard: discardTimer)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private func reviewTimer(_ session: LaborTimerSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                jobHeader(session, status: "Work stopped", statusColor: .secondary)

                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    Text("Session complete")
                        .font(.subheadline.weight(.semibold))
                    Text(Self.durationText(session.durationSeconds()))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .tracking(-1.2)
                        .monospacedDigit()
                    Text(sessionDateRange(session))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 24)
                )

                VStack(alignment: .leading, spacing: 18) {
                    Text("Review details")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Hourly cost")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            CurrencyTextField(
                                title: "0.00",
                                text: $hourlyCostText,
                                accessibilityLabel: "Hourly cost"
                            )
                            Text("/ hr")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13))

                        if !hourlyCostText.isEmpty && reviewHourlyCost == nil {
                            Text("Enter an hourly cost greater than zero.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if hourlyCostText.isEmpty {
                            Text("Add a rate to calculate and save this labor entry.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Note")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        TextField("What did you work on? (optional)", text: $note, axis: .vertical)
                            .lineLimit(3...5)
                            .focused($focusedField, equals: .note)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13))
                    }
                }
                .padding(18)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 22)
                )

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Labor cost")
                            .font(.subheadline.weight(.medium))
                        Text("Added to this job after you confirm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 18)
                    Text(reviewCost(session))
                        .font(.title2.bold())
                        .monospacedDigit()
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                }
                .padding(18)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 160)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            reviewActions(session)
        }
    }

    private func reviewActions(_ session: LaborTimerSession) -> some View {
        VStack(spacing: 10) {
            Button {
                confirm(session)
            } label: {
                Group {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Label("Confirm Labor", systemImage: "checkmark")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(reviewHourlyCost == nil || isSaving)

            Button("Discard Session", role: .destructive) {
                isConfirmingDiscard = true
            }
            .font(.subheadline.weight(.medium))
            .disabled(isSaving)
            .discardTimerConfirmation(isPresented: $isConfirmingDiscard, discard: discardTimer)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var reviewHourlyCost: Decimal? {
        guard let value = MoneyInput.parse(hourlyCostText), value > 0 else { return nil }
        return value
    }

    private func reviewCost(_ session: LaborTimerSession) -> String {
        guard let reviewHourlyCost else { return "—" }
        return MoneyFormat.usd(session.durationHours() * reviewHourlyCost)
    }

    private func runningHourlyCostText(_ session: LaborTimerSession) -> String {
        guard session.hourlyCost > 0 else { return "Set at review" }
        return "\(MoneyFormat.usd(session.hourlyCost))/hr"
    }

    private func runningCostText(_ session: LaborTimerSession, at date: Date) -> String {
        guard session.hourlyCost > 0 else { return "Pending rate" }
        return MoneyFormat.usd(session.cost(at: date))
    }

    private func sessionDateRange(_ session: LaborTimerSession) -> String {
        let start = session.startedAt.formatted(date: .abbreviated, time: .shortened)
        let end = session.stoppedAt?.formatted(date: .omitted, time: .shortened) ?? "Now"
        return "\(start) – \(end)"
    }

    private func stopTimer() {
        do {
            try timerStore.stop()
            loadReviewFields()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirm(_ session: LaborTimerSession) {
        guard !isSaving, let hourlyCost = reviewHourlyCost else { return }
        guard let job = jobs.first(where: { $0.id == session.jobID && $0.status == .active }) else {
            errorMessage = "This job no longer exists or has already been completed."
            return
        }

        isSaving = true
        do {
            try timerStore.updateReview(hourlyCost: hourlyCost, note: note)
            let entry = LaborEntry(
                hours: session.durationHours(),
                hourlyCost: hourlyCost,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                createdAt: session.startedAt,
                job: job
            )
            modelContext.insert(entry)
            try modelContext.save()
            analytics.trackLaborAdded(source: .timer)
            analytics.track(
                .laborTimerCompleted(
                    durationBucket: AnalyticsBucket.laborDuration(hours: session.durationHours())
                )
            )
            timerStore.finish()
            isSaving = false
            if showsCloseButton { dismiss() }
        } catch {
            modelContext.rollback()
            isSaving = false
            errorMessage = "We couldn’t save this labor entry. Please try again."
        }
    }

    private func discardTimer() {
        timerStore.discard()
        if showsCloseButton { dismiss() }
    }

    private func loadReviewFields() {
        guard let session = timerStore.session else {
            hourlyCostText = ""
            note = ""
            return
        }
        hourlyCostText = session.hourlyCost > 0
            ? NSDecimalNumber(decimal: session.hourlyCost).stringValue
            : ""
        note = session.note
    }

    nonisolated static func durationText(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private enum ReviewField: Hashable {
        case hourlyCost
        case note
    }
}

private extension View {
    /// The discard confirmation, attached to whichever button raised it.
    ///
    /// SwiftUI anchors a confirmation dialog to the view carrying the modifier.
    /// Hanging one off the whole screen puts the popover in the middle of it,
    /// pointing at nothing; the running and review screens therefore each own
    /// a copy anchored to their own destructive button.
    func discardTimerConfirmation(
        isPresented: Binding<Bool>,
        discard: @escaping () -> Void
    ) -> some View {
        confirmationDialog("Discard this timer?", isPresented: isPresented) {
            Button("Discard Timer", role: .destructive, action: discard)
            Button("Keep Timer", role: .cancel) {}
        } message: {
            Text("This tracked time won’t be added to the job.")
        }
    }
}

#Preview("Empty") {
    NavigationStack {
        LaborTimerView()
    }
    .environmentObject(LaborTimerStore())
    .modelContainer(PreviewSupport.container())
    .environmentObject(SubscriptionStore(entitlementOverride: false))
}
