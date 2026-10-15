import Foundation
import Vision

enum OCRError: LocalizedError {
    case unsupportedLanguages([String])
    case noText
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedLanguages(let codes):
            "Unsupported OCR language codes: \(codes.joined(separator: ", ")). Update Recognition language codes in Settings."
        case .noText:
            "No readable text found. Try a larger or clearer selection. Clipboard unchanged."
        case .recognitionFailed:
            "Vision could not recognize this image. Try capturing again."
        }
    }
}

/// Vision work runs on this actor, not the UI thread.
actor OCRService {
    func recognize(_ image: CGImage, languagePreference: String) throws -> String {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let supported: [String]
        do { supported = try request.supportedRecognitionLanguages() }
        catch { throw OCRError.recognitionFailed }
        let preferred = Self.parseLanguages(languagePreference)
        let unsupported = preferred.filter { !supported.contains($0) }
        guard unsupported.isEmpty else { throw OCRError.unsupportedLanguages(unsupported) }
        // Blank preference lets Vision choose its default recognition languages.
        if !preferred.isEmpty { request.recognitionLanguages = preferred }
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            throw OCRError.recognitionFailed
        }
        try Task.checkCancellation()
        // Keep Vision's reading order and line boundaries, not screen typography.
        let text = Self.joinLines((request.results ?? []).compactMap { $0.topCandidates(1).first?.string })
        guard !text.isEmpty else { throw OCRError.noText }
        return text
    }

    nonisolated static func parseLanguages(_ preference: String) -> [String] {
        var seen = Set<String>()
        return preference.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    nonisolated static func joinLines(_ lines: [String]) -> String {
        lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
