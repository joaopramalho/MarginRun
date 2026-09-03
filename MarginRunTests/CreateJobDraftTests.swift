import Foundation
import Testing
@testable import MarginRun

@MainActor
struct CreateJobDraftTests {
    @Test func emptyCostsAreZeroAndKitchenPreviewMatches() {
        var draft = CreateJobDraft()
        draft.name = "Kitchen remodel"
        draft.contractValueText = "18000"
        draft.materialsText = "5000"
        draft.laborText = "4000"
        draft.subcontractorsText = "1500"
        draft.equipmentText = "700"
        draft.otherText = "300"
        draft.targetMarginText = "35"

        let financials = draft.financials
        #expect(financials.estimatedTotalCost == 11_500)
        #expect(financials.expectedProfit == 6_500)
        #expect(MoneyFormat.roundedPercent(financials.expectedMargin!) == Decimal(string: "36.1"))
        #expect(!financials.isExpectedMarginBelowTarget)
        #expect(draft.canSave)
    }

    @Test func blankCostFieldsCountAsZero() {
        var draft = CreateJobDraft()
        draft.name = "Paint job"
        draft.contractValueText = "1000"

        #expect(draft.financials.estimatedTotalCost == 0)
        #expect(draft.financials.expectedProfit == 1_000)
        #expect(draft.canSave)

        let job = draft.makeJob()
        #expect(job?.estimatedMaterials == 0)
        #expect(job?.estimatedLabor == 0)
        #expect(job?.targetMargin == 30)
    }

    @Test func rejectsEmptyName() {
        var draft = CreateJobDraft()
        draft.name = "   "
        draft.contractValueText = "1000"
        #expect(!draft.canSave)
        #expect(draft.makeJob() == nil)
    }

    @Test func rejectsZeroOrNegativeContractValue() {
        var draft = CreateJobDraft()
        draft.name = "Deck"

        draft.contractValueText = "0"
        #expect(!draft.canSave)

        draft.contractValueText = "-10"
        #expect(!draft.canSave)

        draft.contractValueText = ""
        #expect(!draft.canSave)
    }

    @Test func rejectsNegativeEstimatedCosts() {
        var draft = CreateJobDraft()
        draft.name = "Fence"
        draft.contractValueText = "4800"
        draft.materialsText = "-1"
        #expect(!draft.canSave)
    }

    @Test func rejectsInvalidNumbers() {
        var draft = CreateJobDraft()
        draft.name = "Bath"
        draft.contractValueText = "abc"
        #expect(!draft.canSave)
    }

    @Test func expectedMarginBelowTargetShowsWarningState() {
        var draft = CreateJobDraft()
        draft.name = "Thin margin job"
        draft.contractValueText = "10000"
        draft.materialsText = "8000"
        draft.targetMarginText = "30"

        #expect(draft.financials.expectedProfit == 2_000)
        #expect(draft.financials.isExpectedMarginBelowTarget)
    }
}
