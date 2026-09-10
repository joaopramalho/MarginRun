import SwiftData
import SwiftUI

struct AddLaborView: View {
    let job: Job
    /// The entry being corrected, or `nil` when logging a new one.
    ///
    /// One view for both, the way ``AddExtraRevenueView`` already does it: the
    /// fields, the arithmetic and the live cost line are identical, and two
    /// copies of them would be two things to keep in step.
    let entry: LaborEntry?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var analytics: AnalyticsService
    @State private var draft: AddLaborDraft
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    init(job: Job, entry: LaborEntry? = nil, preferences: AppPreferences = AppPreferences()) {
        self.job = job
        self.entry = entry
        _draft = State(initialValue: entry.map(AddLaborDraft.init(entry:))
            ?? AddLaborDraft(defaultHourlyCostText: preferences.defaultHourlyCostText))
    }

    private var isEditing: Bool { entry != nil }

    private var canSave: Bool {
        guard job.status == .active, draft.canSave, !isSaving else { return false }
        // Save stays inert on an untouched edit. A money field rewrites itself
        // for display on appear, so this is compared through parsed values.
        if let entry { return draft.differs(from: entry) }
        return true
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
                    Text(isEditing
                         ? "Hours × hourly cost. Saving updates what this job has spent on labor."
                         : "Hours × hourly cost. This amount is added to the job as soon as you save.")
                }
            }
            .keyboardEscapes()
            .navigationTitle(isEditing ? "Edit Labor" : "Add Labor")
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
                isEditing ? "Couldn’t save changes" : "Couldn’t save labor",
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
        guard canSave else { return }
        isSaving = true

        if let entry {
            update(entry)
        } else {
            insert()
        }
    }

    private func insert() {
        guard let newEntry = draft.makeEntry(job: job) else {
            isSaving = false
            return
        }
        modelContext.insert(newEntry)

        do {
            try modelContext.save()
            analytics.trackLaborAdded(source: .manual)
            dismiss()
        } catch {
            modelContext.delete(newEntry)
            saveErrorMessage = "We couldn’t save this labor entry. Please try again."
            isSaving = false
        }
    }

    private func update(_ entry: LaborEntry) {
        // Captured before the write, so a failed save puts back exactly what
        // was on screen rather than leaving the entry half-edited in memory.
        let original = AddLaborDraft(entry: entry)
        guard draft.apply(to: entry) else {
            isSaving = false
            return
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            original.apply(to: entry)
            saveErrorMessage = "We couldn’t save this change. Please try again."
            isSaving = false
        }
    }
}
