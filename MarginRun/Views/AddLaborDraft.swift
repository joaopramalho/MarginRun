import Foundation

struct AddLaborDraft: Equatable {
    var hoursText = ""
    var hourlyCostText = ""
    var date = Date()
    var note = ""

    init(defaultHourlyCostText: String = "") {
        self.hourlyCostText = defaultHourlyCostText
    }

    var hours: Decimal? {
        guard let value = MoneyInput.parse(hoursText), value > 0 else { return nil }
        return value
    }

    var hourlyCost: Decimal? {
        guard let value = MoneyInput.parse(hourlyCostText), value > 0 else { return nil }
        return value
    }

    var laborCost: Decimal? {
        guard let hours, let hourlyCost else { return nil }
        return hours * hourlyCost
    }

    var canSave: Bool { laborCost != nil }

    func makeEntry(job: Job) -> LaborEntry? {
        guard let hours, let hourlyCost else { return nil }
        return LaborEntry(
            hours: hours,
            hourlyCost: hourlyCost,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: date,
            job: job
        )
    }
}
