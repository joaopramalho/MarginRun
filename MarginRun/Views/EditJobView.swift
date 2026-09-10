import SwiftUI
import SwiftData

/// Revises the numbers an active job is measured against.
///
/// A job's contract value and estimate drive every figure MarginRun shows, and
/// until now both were frozen at creation — a mistyped contract value made the
/// margin on that job permanently wrong, with deleting the job and re-entering
/// its costs the only way out. Estimates also legitimately change mid-job.
///
/// Only active jobs are editable. A completed job reads from the snapshot taken
/// at completion, so editing one would leave a result that no longer matches
/// the numbers it was calculated from.
struct EditJobView: View {
    @Bindable var job: Job

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var analytics: AnalyticsService

    @State private var draft: CreateJobDraft
    /// Expanded from the start when any of the three folded lines already
    /// carries a number — hiding a cost the contractor entered is worse than
    /// showing three empty fields.
    @State private var isShowingAllCostFields: Bool
    @State private var saveErrorMessage: String?

    init(job: Job) {
        self.job = job
        let draft = CreateJobDraft(job: job)
        _draft = State(initialValue: draft)
        _isShowingAllCostFields = State(
            initialValue: job.estimatedSubcontractors > 0
                || job.estimatedEquipment > 0
                || job.estimatedOther > 0
        )
    }

    /// The revised estimate measured against what this job has already spent,
    /// rather than the empty-job preview the create form shows.
    private var financials: JobFinancials { draft.financials(withActualsFrom: job) }

    private var hasChanges: Bool { draft.differs(from: job) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Job name") {
                        TextField("Job name", text: $draft.name)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("editJobNameField")
                    }
                    LabeledContent("Customer") {
                        TextField("Optional", text: $draft.customerName)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("editJobCustomerField")
                    }
                    LabeledContent("Contract value") {
                        CurrencyTextField(
                            title: "0",
                            text: $draft.contractValueText,
                            alignment: .trailing,
                            accessibilityLabel: "Contract value",
                            accessibilityIdentifier: "editJobContractValueField"
                        )
                    }
                } header: {
                    Text("The job")
                } footer: {
                    Text("Contract value is what the customer is paying you for this job.")
                }

                Section {
                    costField("Materials", text: $draft.materialsText, identifier: "editJobMaterialsField")
                    costField("Labor", text: $draft.laborText, identifier: "editJobLaborField")

                    DisclosureGroup("More cost lines", isExpanded: $isShowingAllCostFields) {
                        costField(
                            "Subcontractors",
                            text: $draft.subcontractorsText,
                            identifier: "editJobSubcontractorsField"
                        )
                        costField(
                            "Equipment",
                            text: $draft.equipmentText,
                            identifier: "editJobEquipmentField"
                        )
                        costField("Other", text: $draft.otherText, identifier: "editJobOtherField")
                    }
                } header: {
                    Text("What you expect it to cost")
                } footer: {
                    Text("Revising an estimate only changes what MarginRun measures against. Expenses and labor you already logged are never touched.")
                }

                Section {
                    previewRow("Spent so far", MoneyFormat.usd(financials.actualCost))
                    previewRow("Estimated cost", MoneyFormat.usd(financials.estimatedTotalCost))
                    previewRow("Projected profit", MoneyFormat.usd(financials.projectedProfit))
                    previewRow("Projected margin", MoneyFormat.percent(ratio: financials.projectedMargin))

                    HStack {
                        Text("Target margin")
                        Spacer(minLength: 12)
                        TextField("30", text: $draft.targetMarginText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 70)
                            .monospacedDigit()
                            .accessibilityLabel("Target margin percent")
                            .accessibilityIdentifier("editJobTargetMarginField")
                        Text("%")
                            .foregroundStyle(.secondary)
                    }

                    if financials.isProjectedMarginBelowTarget {
                        Label(
                            "These numbers put the job below your \(targetMarginLabel) target.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Where this leaves the job")
                } footer: {
                    Text("Projected figures already include everything logged against this job.")
                }
            }
            .keyboardEscapes()
            .navigationTitle("Edit Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("editJobCancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!draft.canSave || !hasChanges)
                        .accessibilityIdentifier("editJobSaveButton")
                }
            }
            .alert(
                "Couldn’t save changes",
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

    private var targetMarginLabel: String {
        if let value = MoneyInput.parse(draft.targetMarginText) {
            return "\(value)%"
        }
        return "target"
    }

    /// Labelled, unlike the create form's equivalent.
    ///
    /// A `TextField`'s title is only a placeholder, so it disappears the moment
    /// the field has content. On the create form every field starts empty and
    /// the placeholders read as labels; on this form every field arrives
    /// pre-filled, which without an explicit label leaves five money amounts in
    /// a column with nothing saying which one is materials.
    private func costField(
        _ title: String,
        text: Binding<String>,
        identifier: String
    ) -> some View {
        LabeledContent(title) {
            CurrencyTextField(
                title: "0",
                text: text,
                alignment: .trailing,
                accessibilityLabel: title,
                accessibilityIdentifier: identifier
            )
        }
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
        // Captured before the write, so a failed save can put back exactly what
        // was on screen rather than a job left half-edited in memory.
        let original = CreateJobDraft(job: job)
        guard let changes = draft.apply(to: job) else { return }

        do {
            try modelContext.save()
        } catch {
            original.apply(to: job)
            saveErrorMessage = "We couldn’t save these changes. Please try again."
            return
        }

        if !changes.isEmpty {
            analytics.track(.jobEdited(
                changedContractValue: changes.changedContractValue,
                changedEstimate: changes.changedEstimate
            ))
        }
        dismiss()
    }
}

#Preview {
    EditJobView(job: MockData.kitchenRemodelJob())
        .modelContainer(PreviewSupport.container())
        .environmentObject(AnalyticsService(backend: NoOpAnalyticsBackend()))
}
