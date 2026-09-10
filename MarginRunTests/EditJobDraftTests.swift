import Foundation
import Testing
@testable import MarginRun

/// Editing an existing job, which reuses ``CreateJobDraft`` for its form.
///
/// The stakes here are higher than on the create form: these fields belong to a
/// job that already has costs logged against it, so a partial write or a lost
/// value corrupts a result the contractor has been watching for weeks.
@MainActor
struct EditJobDraftTests {

    private func sampleJob() -> Job {
        Job(
            name: "Kitchen remodel",
            customerName: "Alvarez",
            contractValue: 18_000,
            targetMargin: 35,
            estimatedMaterials: 5_000,
            estimatedLabor: 4_000,
            estimatedSubcontractors: 1_500,
            estimatedEquipment: 700,
            estimatedOther: 300
        )
    }

    @Test func seedsEveryFieldFromTheJob() {
        let draft = CreateJobDraft(job: sampleJob())

        #expect(draft.name == "Kitchen remodel")
        #expect(draft.customerName == "Alvarez")
        #expect(draft.contractValueText == "18000")
        #expect(draft.materialsText == "5000")
        #expect(draft.laborText == "4000")
        #expect(draft.subcontractorsText == "1500")
        #expect(draft.equipmentText == "700")
        #expect(draft.otherText == "300")
        #expect(draft.targetMarginText == "35")
        #expect(draft.canSave)
    }

    /// Seeding and applying with nothing touched has to be a no-op. This is
    /// what lets the Save button be driven by a plain draft comparison.
    @Test func seedingThenApplyingChangesNothing() {
        let job = sampleJob()
        let draft = CreateJobDraft(job: job)

        let changes = draft.apply(to: job)

        #expect(changes == JobEditChanges())
        #expect(changes?.isEmpty == true)
        #expect(job.contractValue == 18_000)
        #expect(job.estimatedMaterials == 5_000)
        #expect(draft == CreateJobDraft(job: job))
    }

    /// The form's money fields rewrite themselves for display as soon as they
    /// appear, so the seeded text no longer matches what seeded it. Change
    /// detection has to survive that, or Save is live on a form nobody touched.
    @Test func displayFormattingIsNotAChange() {
        let job = sampleJob()
        var draft = CreateJobDraft(job: job)

        #expect(!draft.differs(from: job))

        // Exactly what `CurrencyTextField` does on appear.
        draft.contractValueText = MoneyInput.displayText(draft.contractValueText)
        draft.materialsText = MoneyInput.displayText(draft.materialsText)
        draft.laborText = MoneyInput.displayText(draft.laborText)

        #expect(draft.contractValueText != "18000", "The display value should have been reformatted")
        #expect(!draft.differs(from: job), "Reformatting for display is not an edit")
    }

    @Test func differsSpotsEveryEditableField() {
        let job = sampleJob()

        for mutate in [
            { (d: inout CreateJobDraft) in d.name = "Renamed" },
            { d in d.customerName = "Someone else" },
            { d in d.contractValueText = "19000" },
            { d in d.materialsText = "5001" },
            { d in d.laborText = "4001" },
            { d in d.subcontractorsText = "1501" },
            { d in d.equipmentText = "701" },
            { d in d.otherText = "301" },
            { d in d.targetMarginText = "36" },
        ] {
            var draft = CreateJobDraft(job: job)
            mutate(&draft)
            #expect(draft.differs(from: job))
        }
    }

    /// An incomplete draft cannot be saved, so it is not an outstanding change.
    @Test func anUnsavableDraftReportsNoChange() {
        let job = sampleJob()
        var draft = CreateJobDraft(job: job)
        draft.contractValueText = ""

        #expect(!draft.differs(from: job))
    }

    @Test func appliesEditedValuesToTheJob() {
        let job = sampleJob()
        var draft = CreateJobDraft(job: job)
        draft.name = "  Kitchen remodel — phase 2  "
        draft.customerName = "Alvarez Homes"
        draft.contractValueText = "21500"
        draft.materialsText = "6200"
        draft.targetMarginText = "40"

        let changes = draft.apply(to: job)

        #expect(changes?.changedContractValue == true)
        #expect(changes?.changedEstimate == true)
        #expect(job.name == "Kitchen remodel — phase 2")
        #expect(job.customerName == "Alvarez Homes")
        #expect(job.contractValue == 21_500)
        #expect(job.estimatedMaterials == 6_200)
        #expect(job.targetMargin == 40)
        // Untouched fields survive the write.
        #expect(job.estimatedLabor == 4_000)
        #expect(job.estimatedOther == 300)
    }

    /// The two flags are reported separately because they answer different
    /// product questions: one is a correction, the other is a revision.
    @Test func distinguishesAContractCorrectionFromAnEstimateRevision() {
        let job = sampleJob()
        var contractOnly = CreateJobDraft(job: job)
        contractOnly.contractValueText = "19000"

        let contractChanges = contractOnly.apply(to: job)
        #expect(contractChanges?.changedContractValue == true)
        #expect(contractChanges?.changedEstimate == false)

        let revised = sampleJob()
        var estimateOnly = CreateJobDraft(job: revised)
        estimateOnly.equipmentText = "1200"

        let estimateChanges = estimateOnly.apply(to: revised)
        #expect(estimateChanges?.changedContractValue == false)
        #expect(estimateChanges?.changedEstimate == true)
    }

    /// Renaming is a real edit but neither of the reported flags — the event
    /// says what happened to the numbers, and a name is not one of them.
    @Test func renamingReportsNoNumericChange() {
        let job = sampleJob()
        var draft = CreateJobDraft(job: job)
        draft.name = "Kitchen remodel (Alvarez)"

        let changes = draft.apply(to: job)

        #expect(changes?.isEmpty == true)
        #expect(job.name == "Kitchen remodel (Alvarez)")
    }

    /// The important one. A blanked contract value must not reach the job:
    /// every margin figure MarginRun shows is computed from it.
    @Test func refusesToApplyAnIncompleteDraft() {
        let job = sampleJob()
        var draft = CreateJobDraft(job: job)
        draft.contractValueText = ""

        #expect(!draft.canSave)
        #expect(draft.apply(to: job) == nil)
        #expect(job.contractValue == 18_000)

        draft.contractValueText = "18000"
        draft.name = "   "
        #expect(draft.apply(to: job) == nil)
        #expect(job.name == "Kitchen remodel")
    }

    /// A zero or negative contract value is as destructive as a blank one.
    @Test func refusesANonPositiveContractValue() {
        let job = sampleJob()
        var draft = CreateJobDraft(job: job)

        draft.contractValueText = "0"
        #expect(draft.apply(to: job) == nil)

        draft.contractValueText = "-500"
        #expect(draft.apply(to: job) == nil)
        #expect(job.contractValue == 18_000)
    }

    /// The edit form previews against costs already logged, unlike the create
    /// form, which has none to preview against.
    @Test func previewsRevisedEstimatesAgainstLoggedCosts() {
        let job = sampleJob()
        job.expenses = [Expense(category: .materials, amount: 5_800, job: job)]
        job.laborEntries = [LaborEntry(hours: 20, hourlyCost: 50, job: job)]

        var draft = CreateJobDraft(job: job)
        draft.materialsText = "6000"

        let financials = draft.financials(withActualsFrom: job)

        // Costs already spent are carried into the preview…
        #expect(financials.actualCost == 6_800)
        // …while the estimate reflects what is being typed, not what is stored.
        #expect(financials.estimatedTotalCost == 12_500)
        #expect(job.estimatedMaterials == 5_000)

        // The create form's preview, by contrast, knows nothing about them.
        #expect(draft.financials.actualCost == 0)
    }

    /// Round-tripping through the seed has to survive fractional amounts, which
    /// is where a locale-formatted string would quietly lose or shift a digit.
    @Test func roundTripsFractionalAmounts() {
        let job = Job(
            name: "Deck repair",
            customerName: "",
            contractValue: Decimal(string: "4250.75")!,
            targetMargin: Decimal(string: "27.5")!,
            estimatedMaterials: Decimal(string: "1200.40")!,
            estimatedLabor: 0,
            estimatedSubcontractors: 0,
            estimatedEquipment: 0,
            estimatedOther: 0
        )

        let draft = CreateJobDraft(job: job)
        let changes = draft.apply(to: job)

        #expect(changes?.isEmpty == true)
        #expect(job.contractValue == Decimal(string: "4250.75"))
        #expect(job.estimatedMaterials == Decimal(string: "1200.4"))
        #expect(job.targetMargin == Decimal(string: "27.5"))
    }
}
