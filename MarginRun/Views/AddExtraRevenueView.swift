import SwiftData
import SwiftUI

struct AddExtraRevenueView: View {
    let job: Job
    let extraRevenue: ExtraRevenue?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ExtraRevenueDraft
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(job: Job, extraRevenue: ExtraRevenue? = nil) {
        self.job = job
        self.extraRevenue = extraRevenue
        _draft = State(initialValue: ExtraRevenueDraft(extraRevenue: extraRevenue))
    }

    private var previewFinancials: JobFinancials {
        var inputs = job.financialInputs(excludingExtraRevenueID: extraRevenue?.id)
        inputs.extraRevenues.append(draft.previewLine)
        return JobFinancials(inputs: inputs)
    }

    private var canSave: Bool {
        job.status == .active && draft.canSave && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Extra revenue") {
                    TextField("Description", text: $draft.description)

                    CurrencyTextField(
                        title: "Additional revenue",
                        text: $draft.additionalRevenueText
                    )

                    CurrencyTextField(
                        title: "Additional expected cost",
                        text: $draft.additionalExpectedCostText
                    )
                }

                Section {
                    Toggle("Approved", isOn: $draft.isApproved)
                    DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                    TextField("Note (optional)", text: $draft.note, axis: .vertical)
                        .lineLimit(2...5)
                } footer: {
                    Text("Unapproved revenue stays on the job but does not affect financial projections until approved.")
                }

                Section("Projected impact") {
                    impactRow(
                        "Projected margin",
                        current: MoneyFormat.percent(ratio: job.financials.projectedMargin),
                        after: MoneyFormat.percent(ratio: previewFinancials.projectedMargin)
                    )
                    impactRow(
                        "Projected profit",
                        current: MoneyFormat.usd(job.financials.projectedProfit),
                        after: MoneyFormat.usd(previewFinancials.projectedProfit)
                    )

                    if draft.isApproved {
                        LabeledContent("Expected contribution") {
                            Text(expectedContributionText)
                                .fontWeight(.semibold)
                                .foregroundStyle(expectedContribution >= 0 ? Color.green : Color.red)
                                .monospacedDigit()
                        }
                    } else {
                        Label("Not included until approved", systemImage: "clock.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(extraRevenue == nil ? "Add Extra Revenue" : "Edit Extra Revenue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
            .alert(
                "Couldn’t save extra revenue",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "The extra revenue could not be saved.")
            }
        }
    }

    private var expectedContribution: Decimal {
        (draft.additionalRevenue ?? 0) - (draft.additionalExpectedCost ?? 0)
    }

    private var expectedContributionText: String {
        let amount = MoneyFormat.usd(abs(expectedContribution))
        if expectedContribution > 0 { return "+\(amount)" }
        if expectedContribution < 0 { return "−\(amount)" }
        return MoneyFormat.usd(0)
    }

    private func impactRow(_ title: String, current: String, after: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Current \(current)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("After save \(after)")
                    .fontWeight(.semibold)
            }
            .monospacedDigit()
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true

        if let extraRevenue {
            let original = ExtraRevenueDraft(extraRevenue: extraRevenue)
            applyDraft(to: extraRevenue)
            do {
                try modelContext.save()
                dismiss()
            } catch {
                apply(original, to: extraRevenue)
                errorMessage = "We couldn’t update this extra revenue. Please try again."
                isSaving = false
            }
        } else {
            guard let newExtraRevenue = draft.makeExtraRevenue(job: job) else {
                isSaving = false
                return
            }
            modelContext.insert(newExtraRevenue)
            do {
                try modelContext.save()
                dismiss()
            } catch {
                modelContext.delete(newExtraRevenue)
                errorMessage = "We couldn’t add this extra revenue. Please try again."
                isSaving = false
            }
        }
    }

    private func applyDraft(to extraRevenue: ExtraRevenue) {
        apply(draft, to: extraRevenue)
    }

    private func apply(_ source: ExtraRevenueDraft, to extraRevenue: ExtraRevenue) {
        guard let revenue = source.additionalRevenue, let cost = source.additionalExpectedCost else { return }
        extraRevenue.extraDescription = source.trimmedDescription
        extraRevenue.revenueAmount = revenue
        extraRevenue.estimatedCost = cost
        extraRevenue.isApproved = source.isApproved
        extraRevenue.createdAt = source.date
        extraRevenue.note = source.note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    let container = PreviewSupport.container()
    let job = (try? container.mainContext.fetch(FetchDescriptor<Job>()))?.first
        ?? MockData.kitchenRemodelJob()

    AddExtraRevenueView(job: job)
        .modelContainer(container)
}
