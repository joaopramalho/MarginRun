import Foundation
import Testing
import UIKit
@testable import MarginRun

@MainActor
struct ReceiptStorageTests {
    @Test func savesLoadsAndDeletesReceiptLocally() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 120))
        let image = renderer.image { context in
            UIColor.systemYellow.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 80, height: 120))
        }
        let sourceData = try #require(image.pngData())

        let fileName = try ReceiptStorage.save(imageData: sourceData, in: baseDirectory)

        #expect(fileName.hasSuffix(".jpg"))
        #expect(ReceiptStorage.fileExists(fileName: fileName, in: baseDirectory))
        #expect(ReceiptStorage.image(fileName: fileName, in: baseDirectory) != nil)

        try ReceiptStorage.delete(fileName: fileName, in: baseDirectory)
        #expect(!ReceiptStorage.fileExists(fileName: fileName, in: baseDirectory))
    }

    @Test func rejectsInvalidImageData() {
        #expect(throws: ReceiptStorageError.self) {
            try ReceiptStorage.save(imageData: Data("not an image".utf8))
        }
    }

    @Test func expensePersistsReceiptReference() {
        let expense = Expense(
            category: .materials,
            amount: 84.73,
            vendor: "Builders Supply",
            receiptFileName: "receipt-photo.jpg"
        )

        #expect(expense.receiptFileName == "receipt-photo.jpg")
    }

    @Test func missingReceiptIsSafeToReadAndDelete() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        #expect(ReceiptStorage.image(fileName: "missing.jpg", in: baseDirectory) == nil)
        #expect(!ReceiptStorage.fileExists(fileName: "missing.jpg", in: baseDirectory))
        try ReceiptStorage.delete(fileName: "missing.jpg", in: baseDirectory)
    }

    @Test func corruptedJPEGIsReportedAsUnavailable() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let receiptDirectory = baseDirectory.appendingPathComponent("Receipts", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        try FileManager.default.createDirectory(
            at: receiptDirectory,
            withIntermediateDirectories: true
        )
        try Data("corrupted jpeg".utf8).write(
            to: receiptDirectory.appendingPathComponent("corrupted.jpg")
        )

        #expect(ReceiptStorage.fileExists(fileName: "corrupted.jpg", in: baseDirectory))
        #expect(ReceiptStorage.image(fileName: "corrupted.jpg", in: baseDirectory) == nil)
    }

    @Test func expenseCanSafelyReferenceAMissingReceipt() {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let expense = Expense(
            category: .materials,
            amount: 187.42,
            vendor: "Home Depot",
            receiptFileName: "no-longer-there.jpg"
        )

        guard let fileName = expense.receiptFileName else {
            Issue.record("Expense should retain its receipt reference")
            return
        }
        #expect(ReceiptStorage.image(fileName: fileName, in: baseDirectory) == nil)
    }

    @Test func deletingExpenseReceiptCleansUpJPEG() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }
        let imageData = try #require(image.jpegData(compressionQuality: 0.8))
        let fileName = try ReceiptStorage.save(imageData: imageData, in: baseDirectory)
        let expense = Expense(
            category: .materials,
            amount: 12,
            receiptFileName: fileName
        )

        try ExpenseReceiptCleanup.deleteReceipt(
            fileName: expense.receiptFileName,
            in: baseDirectory
        )

        #expect(!ReceiptStorage.fileExists(fileName: fileName, in: baseDirectory))
    }
}
