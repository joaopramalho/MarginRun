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
