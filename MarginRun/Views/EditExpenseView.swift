import SwiftUI
import SwiftData

/// Corrects an expense that has already been recorded.
///
/// Until now a recorded expense could only be deleted and re-entered. The one
/// field that could be changed — the amount — could only be changed as a side
/// effect of *replacing the receipt photo*, so an expense with no photo, or a
/// right photo with a mistyped total, had no way back at all. Every figure on
/// the job is built from these amounts, which makes correcting one of them the
/// last thing that should require re-entering the rest.
struct EditExpenseView: View {
    let expense: Expense

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var draft: EditExpenseDraft
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    @State private var isShowingReceipt = false

    /// Editing follows the job, not the expense: a completed job is a frozen
    /// record, so its costs are shown but not changed.
    let allowsEditing: Bool

    init(expense: Expense, allowsEditing: Bool) {
        self.expense = expense
        self.allowsEditing = allowsEditing
        _draft = State(initialValue: EditExpenseDraft(expense: expense))
    }

    private var canSave: Bool {
        allowsEditing && draft.canSave && draft.differs(from: expense) && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Category") {
                        Picker("Category", selection: $draft.category) {
                            ForEach(ExpenseCategory.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("editExpenseCategoryPicker")
                    }

                    LabeledContent("Amount") {
                        CurrencyTextField(
                            title: "0",
                            text: $draft.amountText,
                            alignment: .trailing,
                            accessibilityLabel: "Amount",
                            accessibilityIdentifier: "editExpenseAmountField"
                        )
                    }

                    LabeledContent("Vendor") {
                        TextField("Optional", text: $draft.vendor)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("editExpenseVendorField")
                    }

                    DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                        .accessibilityIdentifier("editExpenseDatePicker")

                    LabeledContent("Note") {
                        TextField("Optional", text: $draft.note)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("editExpenseNoteField")
                    }
                } header: {
                    Text("Expense")
                } footer: {
                    Text(allowsEditing
                         ? "Changing an amount updates this job's budget and margin immediately."
                         : "This job is complete, so its costs can no longer be changed.")
                }

                if expense.receiptFileName != nil {
                    Section {
                        Button {
                            isShowingReceipt = true
                        } label: {
                            Label("View Receipt", systemImage: "doc.text.image")
                        }
                        .accessibilityIdentifier("editExpenseViewReceiptButton")
                    }
                }
            }
            .keyboardEscapes()
            .disabled(!allowsEditing)
            .navigationTitle(allowsEditing ? "Edit Expense" : "Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(allowsEditing ? "Cancel" : "Done") { dismiss() }
                        .accessibilityIdentifier("editExpenseCancelButton")
                }
                if allowsEditing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSaving ? "Saving…" : "Save") { save() }
                            .disabled(!canSave)
                            .accessibilityIdentifier("editExpenseSaveButton")
                    }
                }
            }
            .fullScreenCover(isPresented: $isShowingReceipt) {
                ReceiptDetailView(expense: expense, allowsEditing: allowsEditing)
            }
            .alert(
                "Couldn’t save expense",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "The expense could not be saved.")
            }
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true

        // Captured before the write, so a failed save puts back exactly what was
        // on screen rather than leaving the expense half-edited in memory.
        let original = EditExpenseDraft(expense: expense)
        guard draft.apply(to: expense) else {
            isSaving = false
            return
        }

        do {
            try modelContext.save()
        } catch {
            original.apply(to: expense)
            saveErrorMessage = "We couldn’t save this change. Please try again."
            isSaving = false
            return
        }

        dismiss()
    }
}

#Preview {
    let container = PreviewSupport.container()
    let job = (try? container.mainContext.fetch(FetchDescriptor<Job>()))?.first
        ?? MockData.kitchenRemodelJob()
    let expense = job.expenses.first ?? Expense(category: .materials, amount: 120, job: job)

    return EditExpenseView(expense: expense, allowsEditing: true)
        .modelContainer(container)
}
