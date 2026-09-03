import Foundation
import ImageIO
import UIKit
import Vision

nonisolated struct ReceiptOCRResult: Sendable, Equatable {
    let vendor: String?
    let total: Decimal?
    let date: Date?
}

nonisolated enum ReceiptOCRError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "MarginRun couldn’t read this receipt image. You can still enter the details manually."
        }
    }
}

nonisolated enum ReceiptOCRService {
    static func scan(imageData: Data) async throws -> ReceiptOCRResult {
        try await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
                throw ReceiptOCRError.invalidImage
            }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: image.imageOrientation.cgImageOrientation,
                options: [:]
            )
            try handler.perform([request])

            let lines = (request.results ?? [])
                .sorted { first, second in
                    if abs(first.boundingBox.midY - second.boundingBox.midY) > 0.02 {
                        return first.boundingBox.midY > second.boundingBox.midY
                    }
                    return first.boundingBox.minX < second.boundingBox.minX
                }
                .compactMap { $0.topCandidates(1).first?.string }

            return parse(lines: lines)
        }.value
    }

    static func parse(lines: [String]) -> ReceiptOCRResult {
        let cleanedLines = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return ReceiptOCRResult(
            vendor: detectVendor(in: cleanedLines),
            total: detectTotal(in: cleanedLines),
            date: detectDate(in: cleanedLines)
        )
    }

    private static func detectVendor(in lines: [String]) -> String? {
        let excludedTerms = [
            "receipt", "invoice", "order", "cashier", "terminal", "register",
            "store #", "www.", "http", "thank you", "subtotal", "tax", "total",
            "street", " st ", "road", " rd ", "avenue", " ave ", "boulevard",
            " blvd", "phone", "tel:"
        ]

        return lines.prefix(8).first { line in
            let lowercase = " \(line.lowercased()) "
            let letterCount = line.unicodeScalars.filter(CharacterSet.letters.contains).count
            let digitCount = line.unicodeScalars.filter(CharacterSet.decimalDigits.contains).count
            let looksLikeDate = parseDate(from: line) != nil

            return letterCount >= 3
                && digitCount <= letterCount
                && !looksLikeDate
                && !excludedTerms.contains(where: lowercase.contains)
        }
    }

    private static func detectTotal(in lines: [String]) -> Decimal? {
        let priorities = ["grand total", "amount due", "balance due", "total due", "total"]

        for keyword in priorities {
            for line in lines.reversed() {
                let lowercase = line.lowercased()
                guard lowercase.contains(keyword) else { continue }
                guard !lowercase.contains("subtotal"), !lowercase.contains("tax") else { continue }
                if let amount = amounts(in: line).last { return amount }
            }
        }

        return lines
            .flatMap(amounts(in:))
            .filter { $0 > 0 }
            .max()
    }

    private static func amounts(in line: String) -> [Decimal] {
        let pattern = #"(?<!\d)(?:\$\s*)?(\d{1,3}(?:,\d{3})*|\d+)\.\d{2}(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)

        return regex.matches(in: line, range: range).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: line) else { return nil }
            let value = line[valueRange].replacingOccurrences(of: ",", with: "")
            let centsRange = Range(match.range, in: line).map { line[$0] } ?? ""
            guard let decimalPoint = centsRange.lastIndex(of: ".") else { return nil }
            let cents = centsRange[centsRange.index(after: decimalPoint)...]
            return Decimal(string: "\(value).\(cents)", locale: Locale(identifier: "en_US_POSIX"))
        }
    }

    private static func detectDate(in lines: [String]) -> Date? {
        for line in lines.prefix(14) {
            if let date = parseDate(from: line) { return date }
        }
        return nil
    }

    private static func parseDate(from text: String) -> Date? {
        let candidates = dateCandidates(in: text)
        let formats = [
            "M/d/yyyy", "MM/dd/yyyy", "M/d/yy", "MM/dd/yy",
            "yyyy-MM-dd", "MMM d, yyyy", "MMMM d, yyyy",
            "MMM d yyyy", "MMMM d yyyy", "d MMM yyyy", "d MMMM yyyy"
        ]

        for candidate in candidates {
            for format in formats {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.timeZone = .current
                formatter.dateFormat = format
                formatter.isLenient = false
                if let date = formatter.date(from: candidate) { return date }
            }
        }
        return nil
    }

    private static func dateCandidates(in text: String) -> [String] {
        let patterns = [
            #"\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b"#,
            #"\b\d{4}-\d{1,2}-\d{1,2}\b"#,
            #"\b(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{1,2},?\s+\d{4}\b"#,
            #"\b\d{1,2}\s+(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{4}\b"#
        ]

        return patterns.flatMap { pattern -> [String] in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return []
            }
            let range = NSRange(text.startIndex..., in: text)
            return regex.matches(in: text, range: range).compactMap { match in
                Range(match.range, in: text).map { String(text[$0]) }
            }
        }
    }
}

private nonisolated extension UIImage.Orientation {
    var cgImageOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
