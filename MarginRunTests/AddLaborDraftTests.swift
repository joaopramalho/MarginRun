import Foundation
import Testing
@testable import MarginRun

@MainActor
struct AddLaborDraftTests {
    @Test func calculatesLaborCostAndBuildsEntry() throws {
        let job = Job(
            name: "Backyard fence",
            customerName: "Rivera Family",
            contractValue: 4_800,
            targetMargin: 30,
            estimatedMaterials: 2_100,
            estimatedLabor: 1_200,
            estimatedSubcontractors: 0,
            estimatedEquipment: 150,
            estimatedOther: 50
        )
        let date = try #require(
            Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 31))
        )
        var draft = AddLaborDraft()
        draft.hoursText = "7.5"
        draft.hourlyCostText = "42.50"
        draft.date = date
        draft.note = "  Fence posts and framing  "

        #expect(draft.laborCost == Decimal(string: "318.75"))
        #expect(draft.canSave)

        let entry = try #require(draft.makeEntry(job: job))
        #expect(entry.hours == Decimal(string: "7.5"))
        #expect(entry.hourlyCost == Decimal(string: "42.50"))
        #expect(entry.cost == Decimal(string: "318.75"))
        #expect(entry.note == "Fence posts and framing")
        #expect(entry.createdAt == date)
    }

    @Test func requiresPositiveHoursAndHourlyCost() {
        var draft = AddLaborDraft()
        draft.hoursText = "8"
        draft.hourlyCostText = "0"
        #expect(!draft.canSave)

        draft.hourlyCostText = "50"
        draft.hoursText = "-1"
        #expect(!draft.canSave)

        draft.hoursText = "abc"
        #expect(!draft.canSave)
    }

    @Test func laborEntryChangesJobActualCostImmediately() {
        let job = Job(
            name: "Deck repair",
            customerName: "Miller Residence",
            contractValue: 3_000,
            targetMargin: 30,
            estimatedMaterials: 500,
            estimatedLabor: 1_000,
            estimatedSubcontractors: 0,
            estimatedEquipment: 0,
            estimatedOther: 0
        )
        let entry = LaborEntry(hours: 6, hourlyCost: 55, job: job)

        job.laborEntries.append(entry)

        #expect(job.financials.laborActual == 330)
        #expect(job.financials.actualCost == 330)
        #expect(job.financials.budgetRemaining == 1_170)
    }
}
