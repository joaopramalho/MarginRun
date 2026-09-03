import Foundation
import SwiftData

@Model
final class ExtraRevenue {
    @Attribute(.unique) var id: UUID
    var extraDescription: String
    var revenueAmount: Decimal
    var estimatedCost: Decimal
    var isApproved: Bool = true
    var note: String = ""
    var createdAt: Date
    var job: Job?

    init(
        id: UUID = UUID(),
        description: String,
        revenueAmount: Decimal,
        estimatedCost: Decimal,
        isApproved: Bool = true,
        note: String = "",
        createdAt: Date = .now,
        job: Job? = nil
    ) {
        self.id = id
        self.extraDescription = description
        self.revenueAmount = revenueAmount
        self.estimatedCost = estimatedCost
        self.isApproved = isApproved
        self.note = note
        self.createdAt = createdAt
        self.job = job
    }
}
