import Foundation

/// The editable fields of an expense that has already been recorded.
///
/// A separate draft from the one ``AddExpenseView`` builds, because adding an
/// expense is mostly about the *photo* — camera, library, scanner — while
/// correcting one is only ever about the five values underneath it.
struct EditExpenseDraft: Equatable {
    var category: ExpenseCategory = .materials
    var amountText = ""
    var vendor = ""
    var note = ""
    var date = Date()

    init() {}

    /// Seeds the draft from an expense that already exists.
    ///
    /// The amount is written in canonical dot-decimal form, which
    /// ``MoneyInput/parse(_:locale:)`` recognizes before it consults the
    /// locale — a comma-locale device would otherwise re-read `7.5` as `7`.
    init(expense: Expense) {
        category = expense.category
        amountText = NSDecimalNumber(decimal: expense.amount).stringValue
        vendor = expense.vendor
        note = expense.note
        date = expense.createdAt
    }

    var amount: Decimal? {
        guard let value = MoneyInput.parse(amountText), value > 0 else { return nil }
        return value
    }

    var canSave: Bool { amount != nil }

    var trimmedVendor: String {
        vendor.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether saving would change anything on `expense`.
    ///
    /// Compared through the parsed amount rather than the field text: a money
    /// field rewrites itself for display the moment it appears, so a textual
    /// comparison reports an edit before the contractor has touched the form.
    func differs(from expense: Expense) -> Bool {
        guard let amount else { return false }
        return amount != expense.amount
            || category != expense.category
            || trimmedVendor != expense.vendor
            || trimmedNote != expense.note
            || date != expense.createdAt
    }

    /// Writes the validated draft onto `expense`.
    ///
    /// Returns `false` — leaving `expense` untouched — when the amount is
    /// missing or not positive, so a half-cleared form cannot zero out a cost
    /// the job's margin is calculated from.
    @discardableResult
    func apply(to expense: Expense) -> Bool {
        guard let amount else { return false }
        expense.category = category
        expense.amount = amount
        expense.vendor = trimmedVendor
        expense.note = trimmedNote
        expense.createdAt = date
        return true
    }
}
