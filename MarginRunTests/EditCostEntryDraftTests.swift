import Foundation
import Testing
@testable import MarginRun

/// Correcting costs that have already been recorded.
///
/// Both drafts write onto a live record that the job's margin is computed from,
/// so the case that matters most is the one where they must *refuse* to write.
@MainActor
struct EditCostEntryDraftTests {

    // MARK: - Expenses

    private func sampleExpense() -> Expense {
        Expense(
            category: .materials,
            amount: Decimal(string: "412.50")!,
            vendor: "Ferreira Supply",
            note: "Second delivery",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @Test func expenseDraftSeedsEveryField() {
        let expense = sampleExpense()
        let draft = EditExpenseDraft(expense: expense)

        #expect(draft.category == .materials)
        #expect(draft.amountText == "412.5")
        #expect(draft.vendor == "Ferreira Supply")
        #expect(draft.note == "Second delivery")
        #expect(draft.date == expense.createdAt)
        #expect(draft.canSave)
        #expect(!draft.differs(from: expense))
    }

    /// A money field rewrites itself for display as soon as it appears, so the
    /// seeded text stops matching what seeded it. Save must stay inert anyway.
    @Test func expenseDisplayFormattingIsNotAChange() {
        let expense = sampleExpense()
        var draft = EditExpenseDraft(expense: expense)

        draft.amountText = MoneyInput.displayText(draft.amountText)

        #expect(draft.amountText != "412.5", "The amount should have been reformatted")
        #expect(!draft.differs(from: expense), "Reformatting for display is not an edit")
    }

    @Test func expenseDraftSpotsEveryEditableField() {
        let expense = sampleExpense()

        for mutate in [
            { (d: inout EditExpenseDraft) in d.amountText = "500" },
            { d in d.category = .equipment },
            { d in d.vendor = "Someone else" },
            { d in d.note = "Different note" },
            { d in d.date = Date(timeIntervalSince1970: 1) },
        ] {
            var draft = EditExpenseDraft(expense: expense)
            mutate(&draft)
            #expect(draft.differs(from: expense))
        }
    }

    /// Whitespace is trimmed on write, so padding an existing value is not an
    /// edit — otherwise Save lights up for a stray space.
    @Test func expenseTrimsBeforeComparing() {
        let expense = sampleExpense()
        var draft = EditExpenseDraft(expense: expense)
        draft.vendor = "  Ferreira Supply  "
        draft.note = " Second delivery "

        #expect(!draft.differs(from: expense))
    }

    @Test func expenseAppliesEditedValues() {
        let expense = sampleExpense()
        var draft = EditExpenseDraft(expense: expense)
        draft.amountText = "389.90"
        draft.category = .subcontractors
        draft.vendor = "  Nova Build  "

        #expect(draft.apply(to: expense))
        #expect(expense.amount == Decimal(string: "389.9"))
        #expect(expense.category == .subcontractors)
        #expect(expense.vendor == "Nova Build")
        #expect(expense.note == "Second delivery")
    }

    /// The important one. A blanked or zeroed amount must not reach the record:
    /// it would silently reduce what the job has spent.
    @Test func expenseRefusesANonPositiveAmount() {
        let expense = sampleExpense()
        var draft = EditExpenseDraft(expense: expense)

        for text in ["", "0", "-5", "abc"] {
            draft.amountText = text
            #expect(!draft.canSave, "\(text) should not be savable")
            #expect(!draft.apply(to: expense), "\(text) should not be written")
            #expect(!draft.differs(from: expense), "\(text) is not an outstanding change")
        }

        #expect(expense.amount == Decimal(string: "412.50"))
    }

    // MARK: - Labor

    private func sampleLabor() -> LaborEntry {
        LaborEntry(
            hours: Decimal(string: "6.5")!,
            hourlyCost: 45,
            note: "Framing",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @Test func laborDraftSeedsEveryField() {
        let entry = sampleLabor()
        let draft = AddLaborDraft(entry: entry)

        #expect(draft.hoursText == "6.5")
        #expect(draft.hourlyCostText == "45")
        #expect(draft.note == "Framing")
        #expect(draft.date == entry.createdAt)
        #expect(draft.canSave)
        #expect(!draft.differs(from: entry))
        #expect(draft.laborCost == Decimal(string: "292.5"))
    }

    @Test func laborDisplayFormattingIsNotAChange() {
        let entry = sampleLabor()
        var draft = AddLaborDraft(entry: entry)

        draft.hourlyCostText = MoneyInput.displayText(draft.hourlyCostText)

        #expect(!draft.differs(from: entry), "Reformatting for display is not an edit")
    }

    @Test func laborDraftSpotsEveryEditableField() {
        let entry = sampleLabor()

        for mutate in [
            { (d: inout AddLaborDraft) in d.hoursText = "7" },
            { d in d.hourlyCostText = "50" },
            { d in d.note = "Different note" },
            { d in d.date = Date(timeIntervalSince1970: 1) },
        ] {
            var draft = AddLaborDraft(entry: entry)
            mutate(&draft)
            #expect(draft.differs(from: entry))
        }
    }

    @Test func laborAppliesEditedValues() {
        let entry = sampleLabor()
        var draft = AddLaborDraft(entry: entry)
        draft.hoursText = "8"
        draft.hourlyCostText = "52.50"
        draft.note = "  Framing and sheathing  "

        #expect(draft.apply(to: entry))
        #expect(entry.hours == 8)
        #expect(entry.hourlyCost == Decimal(string: "52.5"))
        #expect(entry.note == "Framing and sheathing")
        #expect(entry.cost == 420)
    }

    /// Hours and rate are both multiplicands of the labor cost, so zeroing
    /// either one would quietly erase the entry's contribution to the job.
    @Test func laborRefusesNonPositiveHoursOrRate() {
        let entry = sampleLabor()
        var draft = AddLaborDraft(entry: entry)

        draft.hoursText = "0"
        #expect(!draft.apply(to: entry))

        draft = AddLaborDraft(entry: entry)
        draft.hourlyCostText = ""
        #expect(!draft.apply(to: entry))

        #expect(entry.hours == Decimal(string: "6.5"))
        #expect(entry.hourlyCost == 45)
    }
}
