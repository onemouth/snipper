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
    func recognize(_ image: CGImage, languagePreference: String) async throws -> String {
        try Task.checkCancellation()
        // The legacy VNRecognizeTextRequest missed vertical Japanese entirely in
        // our page fixture. macOS 26 document recognition handles that layout and
        // supplies a reading-order transcript instead of isolated text fragments.
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = true
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        request.barcodeDetectionOptions.enabled = false
        let preferred = Self.parseLanguages(languagePreference)
        let supported = Set(request.supportedRecognitionLanguages.map(\.maximalIdentifier))
        let unsupported = preferred.filter {
            !supported.contains(Locale.Language(identifier: $0).maximalIdentifier)
        }
        guard unsupported.isEmpty else { throw OCRError.unsupportedLanguages(unsupported) }
        // Blank preference lets Vision choose its default recognition languages.
        if !preferred.isEmpty {
            request.textRecognitionOptions.recognitionLanguages = preferred.map { Locale.Language(identifier: $0) }
        }
        let documents: [DocumentObservation]
        do {
            documents = try await request.perform(on: image)
        } catch {
            try Task.checkCancellation()
            throw OCRError.recognitionFailed
        }
        try Task.checkCancellation()
        // Keep document reading order, including right-to-left vertical columns.
        let text = Self.joinLines(documents.map { $0.document.text.transcript })
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
