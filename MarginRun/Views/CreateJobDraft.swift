import Foundation

struct CreateJobDraft: Equatable {
    var name: String = ""
    var customerName: String = ""
    var contractValueText: String = ""
    var materialsText: String = ""
    var laborText: String = ""
    var subcontractorsText: String = ""
    var equipmentText: String = ""
    var otherText: String = ""
    var targetMarginText: String = "30"

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedCustomerName: String {
        customerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var financials: JobFinancials {
        JobFinancials(inputs: previewInputs)
    }

    var canSave: Bool { validatedFields != nil }

    func makeJob() -> Job? {
        guard let fields = validatedFields else { return nil }
        return Job(
            name: fields.name,
            customerName: fields.customerName,
            contractValue: fields.contractValue,
            targetMargin: fields.targetMargin,
            estimatedMaterials: fields.estimatedMaterials,
            estimatedLabor: fields.estimatedLabor,
            estimatedSubcontractors: fields.estimatedSubcontractors,
            estimatedEquipment: fields.estimatedEquipment,
            estimatedOther: fields.estimatedOther
        )
    }

    private struct Fields: Equatable {
        var name: String
        var customerName: String
        var contractValue: Decimal
        var targetMargin: Decimal
        var estimatedMaterials: Decimal
        var estimatedLabor: Decimal
        var estimatedSubcontractors: Decimal
        var estimatedEquipment: Decimal
        var estimatedOther: Decimal
    }

    private var validatedFields: Fields? {
        guard !trimmedName.isEmpty else { return nil }
        guard let contractValue = MoneyInput.parse(contractValueText), contractValue > 0 else { return nil }
        guard let estimatedMaterials = MoneyInput.parse(materialsText), estimatedMaterials >= 0 else { return nil }
        guard let estimatedLabor = MoneyInput.parse(laborText), estimatedLabor >= 0 else { return nil }
        guard let estimatedSubcontractors = MoneyInput.parse(subcontractorsText), estimatedSubcontractors >= 0 else { return nil }
        guard let estimatedEquipment = MoneyInput.parse(equipmentText), estimatedEquipment >= 0 else { return nil }
        guard let estimatedOther = MoneyInput.parse(otherText), estimatedOther >= 0 else { return nil }
        guard let targetMargin = MoneyInput.parse(targetMarginText), targetMargin >= 0 else { return nil }

        return Fields(
            name: trimmedName,
            customerName: trimmedCustomerName,
            contractValue: contractValue,
            targetMargin: targetMargin,
            estimatedMaterials: estimatedMaterials,
            estimatedLabor: estimatedLabor,
            estimatedSubcontractors: estimatedSubcontractors,
            estimatedEquipment: estimatedEquipment,
            estimatedOther: estimatedOther
        )
    }

    private var previewInputs: JobFinancialInputs {
        JobFinancialInputs(
            contractValue: MoneyInput.parse(contractValueText) ?? 0,
            targetMarginPercent: MoneyInput.parse(targetMarginText) ?? 30,
            estimatedMaterials: MoneyInput.parse(materialsText) ?? 0,
            estimatedLabor: MoneyInput.parse(laborText) ?? 0,
            estimatedSubcontractors: MoneyInput.parse(subcontractorsText) ?? 0,
            estimatedEquipment: MoneyInput.parse(equipmentText) ?? 0,
            estimatedOther: MoneyInput.parse(otherText) ?? 0,
            expenses: [],
            laborEntries: [],
            extraRevenues: []
        )
    }
}

// MARK: - Editing an existing job

/// What an edit actually altered, for the `job_edited` event.
///
/// Categorical, never the values themselves: knowing *that* contractors revise
/// their contract value is the product question, and no amount needs to leave
/// the device to answer it.
nonisolated struct JobEditChanges: Equatable, Sendable {
    var changedContractValue = false
    var changedEstimate = false

    /// Whether anything at all was altered. A Save that changed nothing is
    /// still a successful save, but it is not an edit worth reporting.
    var isEmpty: Bool { self == JobEditChanges() }
}

extension CreateJobDraft {

    /// Seeds the draft from a job that already exists, so the edit form opens
    /// on the exact numbers currently driving that job's margin.
    ///
    /// Amounts are written in canonical dot-decimal form, which is what
    /// ``MoneyInput/parse(_:locale:)`` recognizes before it consults the
    /// locale — a comma-locale device would otherwise re-read `7.5` as `7`.
    init(job: Job) {
        self.init(
            name: job.name,
            customerName: job.customerName,
            contractValueText: Self.canonicalText(job.contractValue),
            materialsText: Self.canonicalText(job.estimatedMaterials),
            laborText: Self.canonicalText(job.estimatedLabor),
            subcontractorsText: Self.canonicalText(job.estimatedSubcontractors),
            equipmentText: Self.canonicalText(job.estimatedEquipment),
            otherText: Self.canonicalText(job.estimatedOther),
            targetMarginText: Self.canonicalText(job.targetMargin)
        )
    }

    /// Writes the validated draft onto `job`.
    ///
    /// Returns `nil` — leaving `job` untouched — when the draft is incomplete,
    /// so a half-filled form can never blank out a contract value that the
    /// whole margin is computed from. Costs already logged are never touched:
    /// an edit revises the *estimate*, never the record of what was spent.
    @discardableResult
    func apply(to job: Job) -> JobEditChanges? {
        guard let fields = validatedFields else { return nil }

        var changes = JobEditChanges()
        changes.changedContractValue = job.contractValue != fields.contractValue
        changes.changedEstimate = job.estimatedMaterials != fields.estimatedMaterials
            || job.estimatedLabor != fields.estimatedLabor
            || job.estimatedSubcontractors != fields.estimatedSubcontractors
            || job.estimatedEquipment != fields.estimatedEquipment
            || job.estimatedOther != fields.estimatedOther

        job.name = fields.name
        job.customerName = fields.customerName
        job.contractValue = fields.contractValue
        job.targetMargin = fields.targetMargin
        job.estimatedMaterials = fields.estimatedMaterials
        job.estimatedLabor = fields.estimatedLabor
        job.estimatedSubcontractors = fields.estimatedSubcontractors
        job.estimatedEquipment = fields.estimatedEquipment
        job.estimatedOther = fields.estimatedOther

        return changes
    }

    /// Whether saving would actually change anything on `job`.
    ///
    /// Compared through the parsed values, never the field text. A money field
    /// rewrites itself for display the moment it appears — `"4800"` becomes
    /// `"$4,800.00"` — so a textual comparison reports an edit before the
    /// contractor has touched the form, which is exactly when Save must stay
    /// inert.
    func differs(from job: Job) -> Bool {
        guard let fields = validatedFields else { return false }

        return fields.name != job.name
            || fields.customerName != job.customerName
            || fields.contractValue != job.contractValue
            || fields.targetMargin != job.targetMargin
            || fields.estimatedMaterials != job.estimatedMaterials
            || fields.estimatedLabor != job.estimatedLabor
            || fields.estimatedSubcontractors != job.estimatedSubcontractors
            || fields.estimatedEquipment != job.estimatedEquipment
            || fields.estimatedOther != job.estimatedOther
    }

    /// The draft's estimates measured against the costs `job` has already
    /// logged.
    ///
    /// The create form previews an empty job, where estimate *is* the whole
    /// picture. An edit happens mid-job, so the number that matters is what the
    /// revised estimate does to the margin given what has already been spent —
    /// which is the question the contractor opened the form to answer.
    func financials(withActualsFrom job: Job) -> JobFinancials {
        var inputs = job.financialInputs
        inputs.contractValue = MoneyInput.parse(contractValueText) ?? 0
        inputs.targetMarginPercent = MoneyInput.parse(targetMarginText) ?? job.targetMargin
        inputs.estimatedMaterials = MoneyInput.parse(materialsText) ?? 0
        inputs.estimatedLabor = MoneyInput.parse(laborText) ?? 0
        inputs.estimatedSubcontractors = MoneyInput.parse(subcontractorsText) ?? 0
        inputs.estimatedEquipment = MoneyInput.parse(equipmentText) ?? 0
        inputs.estimatedOther = MoneyInput.parse(otherText) ?? 0
        return JobFinancials(inputs: inputs)
    }

    /// Dot-decimal, no grouping separator, no trailing `.0` on a whole number.
    private static func canonicalText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
