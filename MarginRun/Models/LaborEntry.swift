import Foundation
import SwiftData

@Model
final class LaborEntry {
    @Attribute(.unique) var id: UUID
    var hours: Decimal
    var hourlyCost: Decimal
    var note: String = ""
    var createdAt: Date
    var job: Job?

    init(
        id: UUID = UUID(),
        hours: Decimal,
        hourlyCost: Decimal,
        note: String = "",
        createdAt: Date = .now,
        job: Job? = nil
    ) {
        self.id = id
        self.hours = hours
        self.hourlyCost = hourlyCost
        self.note = note
        self.createdAt = createdAt
        self.job = job
    }

    var cost: Decimal { hours * hourlyCost }
}
