import Foundation
import UIKit

enum ReceiptStorageError: LocalizedError {
    case invalidImage
    case encodingFailed
    case invalidFileName

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "The selected file isn’t a valid image."
        case .encodingFailed:
            "MarginRun couldn’t prepare this receipt image."
        case .invalidFileName:
            "The receipt file name is invalid."
        }
    }
}

enum ReceiptStorage {
    private static let folderName = "Receipts"
    private static let maximumDimension: CGFloat = 2_000

    static func save(imageData: Data, in baseDirectory: URL? = nil) throws -> String {
        let jpegData = try normalizedJPEGData(from: imageData)
        let directory = try receiptDirectory(in: baseDirectory)
        let fileName = "\(UUID().uuidString).jpg"
        let destination = directory.appendingPathComponent(fileName, isDirectory: false)

        try jpegData.write(to: destination, options: .atomic)
        return fileName
    }

    static func image(fileName: String, in baseDirectory: URL? = nil) -> UIImage? {
        guard let url = try? fileURL(for: fileName, in: baseDirectory) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    static func fileExists(fileName: String, in baseDirectory: URL? = nil) -> Bool {
        guard let url = try? fileURL(for: fileName, in: baseDirectory) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func delete(fileName: String, in baseDirectory: URL? = nil) throws {
        let url = try fileURL(for: fileName, in: baseDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func fileURL(for fileName: String, in baseDirectory: URL?) throws -> URL {
        guard
            !fileName.isEmpty,
            URL(fileURLWithPath: fileName).lastPathComponent == fileName
        else {
            throw ReceiptStorageError.invalidFileName
        }

        return try receiptDirectory(in: baseDirectory)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private static func receiptDirectory(in baseDirectory: URL?) throws -> URL {
        let root: URL
        if let baseDirectory {
            root = baseDirectory
        } else {
            root = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }

        let directory = root.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private static func normalizedJPEGData(from data: Data) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw ReceiptStorageError.invalidImage
        }

        let longestSide = max(image.size.width, image.size.height)
        let resizeScale = longestSide > maximumDimension ? maximumDimension / longestSide : 1
        let targetSize = CGSize(
            width: max(image.size.width * resizeScale, 1),
            height: max(image.size.height * resizeScale, 1)
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let normalizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpegData = normalizedImage.jpegData(compressionQuality: 0.82) else {
            throw ReceiptStorageError.encodingFailed
        }
        return jpegData
    }
}

enum ExpenseReceiptCleanup {
    static func deleteReceipt(fileName: String?, in baseDirectory: URL? = nil) throws {
        guard let fileName else { return }
        try ReceiptStorage.delete(fileName: fileName, in: baseDirectory)
    }
}
