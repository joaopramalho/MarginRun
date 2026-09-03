import Foundation
import Testing
@testable import MarginRun

@MainActor
struct ExtraRevenueDraftTests {
    @Test func validatesAndBuildsExtraRevenue() throws {
        let job = Job(
            name: "Kitchen remodel",
            customerName: "Chen Residence",
            contractValue: 18_000,
            targetMargin: 35,
            estimatedMaterials: 5_000,
            estimatedLabor: 4_000,
            estimatedSubcontractors: 1_500,
            estimatedEquipment: 700,
            estimatedOther: 300
        )
        let date = Date(timeIntervalSince1970: 1_788_000_000)
        var draft = ExtraRevenueDraft()
        draft.description = "  Custom pantry  "
        draft.additionalRevenueText = "2400"
        draft.additionalExpectedCostText = "850"
        draft.isApproved = false
        draft.date = date
        draft.note = "  Waiting for signed change order  "

        #expect(draft.canSave)
        let extraRevenue = try #require(draft.makeExtraRevenue(job: job))
        #expect(extraRevenue.extraDescription == "Custom pantry")
        #expect(extraRevenue.revenueAmount == 2_400)
        #expect(extraRevenue.estimatedCost == 850)
        #expect(!extraRevenue.isApproved)
        #expect(extraRevenue.createdAt == date)
        #expect(extraRevenue.note == "Waiting for signed change order")

        job.extraRevenues.append(extraRevenue)
        #expect(job.financials.extraRevenue == 0)
        extraRevenue.isApproved = true
        #expect(job.financials.extraRevenue == 2_400)
    }

    @Test func requiresDescriptionPositiveRevenueAndNonnegativeCost() {
        var draft = ExtraRevenueDraft()
        draft.description = "Change order"
        draft.additionalRevenueText = "0"
        draft.additionalExpectedCostText = "200"
        #expect(!draft.canSave)

        draft.additionalRevenueText = "1200"
        draft.additionalExpectedCostText = "-1"
        #expect(!draft.canSave)

        draft.additionalExpectedCostText = ""
        #expect(draft.canSave)

        draft.description = "   "
        #expect(!draft.canSave)
    }

    @Test func completedJobRejectsNewExtraRevenue() {
        let job = Job(
            name: "Finished deck",
            customerName: "Miller Residence",
            contractValue: 8_000,
            targetMargin: 30,
            estimatedMaterials: 2_000,
            estimatedLabor: 2_000,
            estimatedSubcontractors: 0,
            estimatedEquipment: 0,
            estimatedOther: 0
        )
        job.complete()

        var draft = ExtraRevenueDraft()
        draft.description = "Late change order"
        draft.additionalRevenueText = "1200"
        draft.additionalExpectedCostText = "300"

        #expect(draft.canSave)
        #expect(draft.makeExtraRevenue(job: job) == nil)
    }
}
