import Foundation
import SwiftData

@Model
final class Expense {
    @Attribute(.unique) var id: UUID
    var categoryRaw: String
    var amount: Decimal
    var vendor: String
    var note: String
    var receiptFileName: String?
    var createdAt: Date
    var job: Job?

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        category: ExpenseCategory,
        amount: Decimal,
        vendor: String = "",
        note: String = "",
        receiptFileName: String? = nil,
        createdAt: Date = .now,
        job: Job? = nil
    ) {
        self.id = id
        self.categoryRaw = category.rawValue
        self.amount = amount
        self.vendor = vendor
        self.note = note
        self.receiptFileName = receiptFileName
        self.createdAt = createdAt
        self.job = job
    }
}
