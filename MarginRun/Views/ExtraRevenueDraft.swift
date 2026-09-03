import Foundation

struct ExtraRevenueDraft: Equatable {
    var description = ""
    var additionalRevenueText = ""
    var additionalExpectedCostText = ""
    var isApproved = true
    var date = Date()
    var note = ""

    init(extraRevenue: ExtraRevenue? = nil) {
        guard let extraRevenue else { return }
        description = extraRevenue.extraDescription
        additionalRevenueText = NSDecimalNumber(decimal: extraRevenue.revenueAmount).stringValue
        additionalExpectedCostText = NSDecimalNumber(decimal: extraRevenue.estimatedCost).stringValue
        isApproved = extraRevenue.isApproved
        date = extraRevenue.createdAt
        note = extraRevenue.note
    }

    var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var additionalRevenue: Decimal? {
        guard let value = MoneyInput.parse(additionalRevenueText), value > 0 else { return nil }
        return value
    }

    var additionalExpectedCost: Decimal? {
        guard let value = MoneyInput.parse(additionalExpectedCostText), value >= 0 else { return nil }
        return value
    }

    var canSave: Bool {
        !trimmedDescription.isEmpty
            && additionalRevenue != nil
            && additionalExpectedCost != nil
    }

    var previewLine: ExtraRevenueLine {
        ExtraRevenueLine(
            revenueAmount: additionalRevenue ?? 0,
            estimatedCost: additionalExpectedCost ?? 0,
            isApproved: isApproved
        )
    }

    func makeExtraRevenue(job: Job) -> ExtraRevenue? {
        guard
            job.status == .active,
            let additionalRevenue,
            let additionalExpectedCost,
            !trimmedDescription.isEmpty
        else {
            return nil
        }
        return ExtraRevenue(
            description: trimmedDescription,
            revenueAmount: additionalRevenue,
            estimatedCost: additionalExpectedCost,
            isApproved: isApproved,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: date,
            job: job
        )
    }
}
