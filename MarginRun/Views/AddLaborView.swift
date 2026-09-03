import SwiftData
import SwiftUI

struct AddLaborView: View {
    let job: Job

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var analytics: AnalyticsService
    @State private var draft: AddLaborDraft
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    init(job: Job, preferences: AppPreferences = AppPreferences()) {
        self.job = job
        _draft = State(initialValue: AddLaborDraft(
            defaultHourlyCostText: preferences.defaultHourlyCostText
        ))
    }

    private var canSave: Bool {
        job.status == .active && draft.canSave && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Work logged") {
                    TextField("Hours", text: $draft.hoursText)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("laborHoursField")

                    CurrencyTextField(
                        title: "Hourly cost",
                        text: $draft.hourlyCostText,
                        accessibilityIdentifier: "laborHourlyCostField"
                    )

                    DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                        .accessibilityIdentifier("laborDatePicker")

                    TextField("Note (optional)", text: $draft.note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Labor cost")
                            .accessibilityIdentifier("laborCostLabel")
                        Spacer()
                        Text(draft.laborCost.map(MoneyFormat.usd) ?? "—")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Hours × hourly cost. This amount is added to the job as soon as you save.")
                }
            }
            .keyboardEscapes()
            .navigationTitle("Add Labor")
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
                "Couldn’t save labor",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "The labor entry could not be saved.")
            }
        }
    }

    private func save() {
        guard job.status == .active, let entry = draft.makeEntry(job: job) else { return }
        isSaving = true
        modelContext.insert(entry)

        do {
            try modelContext.save()
            analytics.trackLaborAdded(source: .manual)
            dismiss()
        } catch {
            modelContext.delete(entry)
            saveErrorMessage = "We couldn’t save this labor entry. Please try again."
            isSaving = false
        }
    }
}
