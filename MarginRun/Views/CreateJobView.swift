import SwiftUI
import SwiftData

struct CreateJobView: View {
    /// Where this was opened from. Reported to analytics so we can tell whether
    /// onboarding actually produces first jobs.
    var source: JobCreationSource = .history

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var analytics: AnalyticsService

    @State private var draft: CreateJobDraft
    /// Set once the job exists. Swaps the form for the "what now" step rather
    /// than dropping the contractor back onto a screen with nothing to do.
    @State private var createdJob: Job?
    @State private var isAddingExpense = false
    @State private var isAddingLabor = false
    /// The three less common cost lines, folded away so a first job asks for
    /// the two that almost every job has.
    @State private var isShowingAllCostFields = false
    @State private var saveErrorMessage: String?

    init(source: JobCreationSource = .history, preferences: AppPreferences = AppPreferences()) {
        self.source = source
        var initialDraft = CreateJobDraft()
        initialDraft.targetMarginText = preferences.defaultTargetMarginText
        _draft = State(initialValue: initialDraft)
    }

    private var financials: JobFinancials { draft.financials }

    var body: some View {
        NavigationStack {
            Group {
                if let createdJob {
                    StartTrackingStep(
                        job: createdJob,
                        addExpense: { isAddingExpense = true },
                        addLabor: { isAddingLabor = true },
                        done: { dismiss() }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
                } else {
                    form
                        .transition(.opacity)
                }
            }
            // The job now exists — worth confirming in the hand, not just on
            // screen, because the form it replaces looked identical a moment ago.
            .sensoryFeedback(.success, trigger: createdJob?.id)
            .keyboardEscapes()
            .navigationTitle(createdJob == nil ? "New Job" : "Job Created")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if createdJob == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .accessibilityIdentifier("createJobCancelButton")
                    }
                }
            }
            .sheet(isPresented: $isAddingExpense) {
                if let createdJob {
                    AddExpenseView(job: createdJob, source: .jobCreationFollowUp)
                }
            }
            .sheet(isPresented: $isAddingLabor) {
                if let createdJob {
                    AddLaborView(job: createdJob)
                }
            }
            .alert(
                "Couldn’t create job",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "The job could not be saved.")
            }
        }
    }

    // MARK: - Form

    private var form: some View {
        Form {
            Section {
                TextField("Job name", text: $draft.name)
                    .accessibilityIdentifier("createJobNameField")
                TextField("Customer (optional)", text: $draft.customerName)
                    .accessibilityIdentifier("createJobCustomerField")
                CurrencyTextField(
                    title: "Contract value",
                    text: $draft.contractValueText,
                    accessibilityIdentifier: "createJobContractValueField"
                )
            } header: {
                Text("The job")
            } footer: {
                Text("Contract value is what the customer is paying you for this job.")
            }

            Section {
                costField("Materials", text: $draft.materialsText, identifier: "createJobMaterialsField")
                costField("Labor", text: $draft.laborText, identifier: "createJobLaborField")

                DisclosureGroup("More cost lines", isExpanded: $isShowingAllCostFields) {
                    costField(
                        "Subcontractors",
                        text: $draft.subcontractorsText,
                        identifier: "createJobSubcontractorsField"
                    )
                    costField(
                        "Equipment",
                        text: $draft.equipmentText,
                        identifier: "createJobEquipmentField"
                    )
                    costField("Other", text: $draft.otherText, identifier: "createJobOtherField")
                }
                .accessibilityIdentifier("createJobMoreCostsDisclosure")
            } header: {
                Text("What you expect it to cost")
            } footer: {
                Text("Your best estimate is enough. MarginRun compares real costs against it as the job runs, and you can leave anything at zero.")
            }

            Section {
                // Plain enough to read cold, but the same words the rest of
                // MarginRun uses — the first job is where that vocabulary is
                // learned, so it should not be a dialect of its own.
                previewRow("Estimated cost", MoneyFormat.usd(financials.estimatedTotalCost))
                previewRow("Projected profit", MoneyFormat.usd(financials.expectedProfit))
                previewRow("Projected margin", MoneyFormat.percent(ratio: financials.expectedMargin))

                HStack {
                    Text("Target margin")
                    Spacer(minLength: 12)
                    TextField("30", text: $draft.targetMarginText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 70)
                        .monospacedDigit()
                        .accessibilityLabel("Target margin percent")
                        .accessibilityIdentifier("createJobTargetMarginField")
                    Text("%")
                        .foregroundStyle(.secondary)
                }

                if financials.isExpectedMarginBelowTarget {
                    Label(
                        "This job is priced below your \(targetMarginLabel) target.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                } else if financials.expectedMargin != nil {
                    Label(
                        "On track for your \(targetMarginLabel) target.",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                }
            } header: {
                Text("What you'd make")
            } footer: {
                Text("Projected profit is contract value minus estimated cost. MarginRun warns you when real costs start eating into it.")
            }

            Section {
                Button("Create Job") {
                    save()
                }
                .disabled(!draft.canSave)
                .accessibilityIdentifier("createJobSaveButton")
            }
        }
    }

    private var targetMarginLabel: String {
        if let value = MoneyInput.parse(draft.targetMarginText) {
            return "\(value)%"
        }
        return "target"
    }

    private func costField(
        _ title: String,
        text: Binding<String>,
        identifier: String
    ) -> some View {
        CurrencyTextField(title: title, text: text, accessibilityIdentifier: identifier)
    }

    private func previewRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
    }

    private func save() {
        guard createdJob == nil, let job = draft.makeJob() else { return }
        modelContext.insert(job)

        do {
            try modelContext.save()
        } catch {
            modelContext.delete(job)
            saveErrorMessage = "We couldn’t save this job. Please try again."
            return
        }

        analytics.trackJobCreated(
            source: source,
            quotedValue: job.contractValue,
            financials: job.financials
        )
        withAnimation(.snappy(duration: 0.3)) {
            createdJob = job
        }
    }
}

/// What to do with a job that has just been created.
///
/// The whole point of the app is the costs that land against a job, so the
/// screen after "created" offers the two ways to record one rather than an
/// empty congratulation. No tutorial, no coach marks — two buttons and a way out.
private struct StartTrackingStep: View {
    let job: Job
    let addExpense: () -> Void
    let addLabor: () -> Void
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)

                    Text("Start tracking this job")
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text("\(job.name) is set up. Log costs as they happen and MarginRun keeps the margin up to date.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    Button(action: addExpense) {
                        Label("Add Expense", systemImage: "doc.text")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("startTrackingAddExpenseButton")

                    Button(action: addLabor) {
                        Label("Add Labor", systemImage: "person.badge.clock")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("startTrackingAddLaborButton")

                    Button("I'll do this later", action: done)
                        .font(.subheadline.weight(.medium))
                        .padding(.top, 4)
                        .accessibilityIdentifier("startTrackingDoneButton")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    CreateJobView()
        .modelContainer(PreviewSupport.container())
        .environmentObject(AnalyticsService(backend: NoOpAnalyticsBackend()))
        .environmentObject(SubscriptionStore(entitlementOverride: false))
}
