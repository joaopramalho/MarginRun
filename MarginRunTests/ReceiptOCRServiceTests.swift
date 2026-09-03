import Foundation
import Testing
@testable import MarginRun

struct ReceiptOCRServiceTests {
    @Test func parsesVendorTotalAndDateFromReceiptText() throws {
        let result = ReceiptOCRService.parse(lines: [
            "HOME DEPOT",
            "Store #6211",
            "2455 Paces Ferry Rd",
            "08/31/2026 14:22",
            "SUBTOTAL 172.94",
            "TAX 14.48",
            "TOTAL $187.42",
            "THANK YOU"
        ])

        #expect(result.vendor == "HOME DEPOT")
        #expect(result.total == Decimal(string: "187.42"))

        let date = try #require(result.date)
        let components = Calendar(identifier: .gregorian)
            .dateComponents([.year, .month, .day], from: date)
        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 31)
    }

    @Test func prioritizesAmountDueOverSubtotalAndTax() {
        let result = ReceiptOCRService.parse(lines: [
            "Builders Supply",
            "Subtotal $220.00",
            "Tax $18.70",
            "Amount Due $238.70"
        ])

        #expect(result.vendor == "Builders Supply")
        #expect(result.total == Decimal(string: "238.70"))
    }

    @Test func returnsPartialResultWhenFieldsAreMissing() {
        let result = ReceiptOCRService.parse(lines: ["Receipt", "Thank you"])

        #expect(result.vendor == nil)
        #expect(result.total == nil)
        #expect(result.date == nil)
    }
}
