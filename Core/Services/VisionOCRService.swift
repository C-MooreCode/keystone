import Foundation
import Vision
#if canImport(UIKit)
import UIKit
#endif

struct VisionOCRConfidence<Value> {
    let value: Value?
    let confidence: Float
}

struct VisionOCRLineItem {
    let name: VisionOCRConfidence<String>
    let quantity: VisionOCRConfidence<Decimal>
    let price: VisionOCRConfidence<Decimal>
}

struct VisionOCRResult {
    let merchant: VisionOCRConfidence<String>
    let date: VisionOCRConfidence<Date>
    let total: VisionOCRConfidence<Decimal>
    let lineItems: [VisionOCRLineItem]
}

protocol VisionOCRServicing {
    func scan(image: PlatformImage) async throws -> VisionOCRResult
    func scan(at url: URL) async throws -> VisionOCRResult
}

#if canImport(UIKit)
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#else
typealias PlatformImage = Any
#endif

enum VisionOCRError: LocalizedError {
    case invalidImage
    case recognitionFailed(Error)
    case unsupportedPlatform

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The provided image could not be processed for OCR."
        case let .recognitionFailed(error):
            return "Text recognition failed with error: \(error.localizedDescription)"
        case .unsupportedPlatform:
            return "OCR is not supported on the current platform."
        }
    }
}

final class VisionOCRService: VisionOCRServicing {
    private let recognitionLanguages: [String]
    private let totalKeywords: [String]
    private let dateParsers: [DateFormatter]

    init(
        recognitionLanguages: [String] = Locale.preferredLanguages,
        totalKeywords: [String] = ["total", "amount", "balance"],
        dateFormats: [String] = [
            "yyyy-MM-dd",
            "MM/dd/yyyy",
            "dd/MM/yyyy",
            "MMM d, yyyy",
            "MMMM d, yyyy"
        ]
    ) {
        self.recognitionLanguages = recognitionLanguages
        self.totalKeywords = totalKeywords
        self.dateParsers = dateFormats.map { format in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter
        }
    }

    func scan(image: PlatformImage) async throws -> VisionOCRResult {
        #if canImport(UIKit)
        guard let cgImage = image.cgImage else {
            throw VisionOCRError.invalidImage
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        return try await performScan(handler: handler)
        #elseif canImport(AppKit)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw VisionOCRError.invalidImage
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        return try await performScan(handler: handler)
        #else
        throw VisionOCRError.unsupportedPlatform
        #endif
    }

    func scan(at url: URL) async throws -> VisionOCRResult {
        let handler = VNImageRequestHandler(url: url, options: [:])
        return try await performScan(handler: handler)
    }

    private func performScan(handler: VNImageRequestHandler) async throws -> VisionOCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = recognitionLanguages

        let observations: [VNRecognizedTextObservation] = try await withCheckedThrowingContinuation { continuation in
            if #available(iOS 16, macOS 13, *) {
                request.revision = VNRecognizeTextRequestRevision3
            }
            request.progressHandler = { _, _, progress, _ in
                if progress >= 1.0 {
                    // no-op, required to keep handler alive during recognition
                }
            }

            request.completionHandler = { request, error in
                if let error {
                    continuation.resume(throwing: VisionOCRError.recognitionFailed(error))
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: observations)
            }

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: VisionOCRError.recognitionFailed(error))
                }
            }
        }

        let recognizedStrings = observations.compactMap { observation -> (text: String, confidence: Float)? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return (candidate.string, candidate.confidence)
        }

        let merchant = extractMerchant(from: recognizedStrings)
        let date = extractDate(from: recognizedStrings)
        let total = extractTotal(from: recognizedStrings)
        let lineItems = extractLineItems(from: recognizedStrings)

        return VisionOCRResult(merchant: merchant, date: date, total: total, lineItems: lineItems)
    }

    private func extractMerchant(from recognizedStrings: [(text: String, confidence: Float)]) -> VisionOCRConfidence<String> {
        guard let first = recognizedStrings.first else {
            return VisionOCRConfidence(value: nil, confidence: .zero)
        }
        return VisionOCRConfidence(value: first.text, confidence: first.confidence)
    }

    private func extractDate(from recognizedStrings: [(text: String, confidence: Float)]) -> VisionOCRConfidence<Date> {
        for candidate in recognizedStrings {
            for formatter in dateParsers {
                if let date = formatter.date(from: candidate.text) {
                    return VisionOCRConfidence(value: date, confidence: candidate.confidence)
                }
            }
        }
        return VisionOCRConfidence(value: nil, confidence: .zero)
    }

    private func extractTotal(from recognizedStrings: [(text: String, confidence: Float)]) -> VisionOCRConfidence<Decimal> {
        var bestCandidate: (value: Decimal, confidence: Float)?

        for candidate in recognizedStrings {
            let lowercased = candidate.text.lowercased()
            let containsKeyword = totalKeywords.contains { lowercased.contains($0) }

            if containsKeyword, let decimal = DecimalFormatter.decimal(from: candidate.text) {
                if let existing = bestCandidate {
                    if candidate.confidence > existing.confidence {
                        bestCandidate = (decimal, candidate.confidence)
                    }
                } else {
                    bestCandidate = (decimal, candidate.confidence)
                }
            }
        }

        if let bestCandidate {
            return VisionOCRConfidence(value: bestCandidate.value, confidence: bestCandidate.confidence)
        }

        if let fallback = recognizedStrings.compactMap({ string -> (Decimal, Float)? in
            guard let value = DecimalFormatter.decimal(from: string.text) else { return nil }
            return (value, string.confidence)
        }).max(by: { lhs, rhs in lhs.0 < rhs.0 }) {
            return VisionOCRConfidence(value: fallback.0, confidence: fallback.1)
        }

        return VisionOCRConfidence(value: nil, confidence: .zero)
    }

    private func extractLineItems(from recognizedStrings: [(text: String, confidence: Float)]) -> [VisionOCRLineItem] {
        recognizedStrings.compactMap { candidate in
            let tokenizer = LineItemTokenizer(text: candidate.text)
            guard let name = tokenizer.name else { return nil }

            let quantityConfidence = tokenizer.quantity != nil ? candidate.confidence : .zero
            let priceConfidence = tokenizer.price != nil ? candidate.confidence : .zero

            return VisionOCRLineItem(
                name: .init(value: name, confidence: candidate.confidence),
                quantity: .init(value: tokenizer.quantity, confidence: quantityConfidence),
                price: .init(value: tokenizer.price, confidence: priceConfidence)
            )
        }
    }
}

private enum DecimalFormatter {
    static func decimal(from string: String) -> Decimal? {
        let allowedCharacters = CharacterSet(charactersIn: "0123456789.,-")
        let filteredScalars = string.unicodeScalars.filter { allowedCharacters.contains($0) }
        var sanitized = String(String.UnicodeScalarView(filteredScalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return nil }

        if sanitized.contains(",") && !sanitized.contains(".") {
            sanitized = sanitized.replacingOccurrences(of: ".", with: "")
            sanitized = sanitized.replacingOccurrences(of: ",", with: ".")
        } else {
            sanitized = sanitized.replacingOccurrences(of: ",", with: "")
        }

        return Decimal(string: sanitized)
    }
}

private struct LineItemTokenizer {
    let name: String?
    let quantity: Decimal?
    let price: Decimal?

    init(text: String) {
        let components = text.split(separator: " ").map(String.init)
        var quantity: Decimal?
        var price: Decimal?
        var nameComponents: [String] = []

        for component in components {
            if quantity == nil,
               let decimal = DecimalFormatter.decimal(from: component),
               component.rangeOfCharacter(from: CharacterSet.letters) == nil,
               !component.contains(".") {
                quantity = decimal
                continue
            }

            if price == nil,
               let decimal = DecimalFormatter.decimal(from: component),
               component.contains(".") || component.contains(",") {
                price = decimal
                continue
            }

            nameComponents.append(component)
        }

        let sanitizedName = nameComponents.joined(separator: " ")

        self.name = sanitizedName.isEmpty ? nil : sanitizedName
        self.quantity = quantity
        self.price = price
    }
}
