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

// MARK: - Editing an existing entry

extension AddLaborDraft {

    /// Seeds the draft from an entry that already exists.
    ///
    /// Amounts are written in canonical dot-decimal form, which
    /// ``MoneyInput/parse(_:locale:)`` recognizes before it consults the
    /// locale — a comma-locale device would otherwise re-read `7.5` as `7`.
    init(entry: LaborEntry) {
        self.init()
        hoursText = NSDecimalNumber(decimal: entry.hours).stringValue
        hourlyCostText = NSDecimalNumber(decimal: entry.hourlyCost).stringValue
        date = entry.createdAt
        note = entry.note
    }

    /// Whether saving would change anything on `entry`.
    ///
    /// Compared through the parsed values rather than the field text, because a
    /// money field rewrites itself for display as soon as it appears.
    func differs(from entry: LaborEntry) -> Bool {
        guard let hours, let hourlyCost else { return false }
        return hours != entry.hours
            || hourlyCost != entry.hourlyCost
            || date != entry.createdAt
            || note.trimmingCharacters(in: .whitespacesAndNewlines) != entry.note
    }

    /// Writes the validated draft onto `entry`, leaving it untouched when the
    /// draft is incomplete.
    @discardableResult
    func apply(to entry: LaborEntry) -> Bool {
        guard let hours, let hourlyCost else { return false }
        entry.hours = hours
        entry.hourlyCost = hourlyCost
        entry.createdAt = date
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return true
    }
}
