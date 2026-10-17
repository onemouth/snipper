import Combine
import Foundation

@MainActor
final class DictionaryCaptureModel: ObservableObject {
    @Published private(set) var source = ""
    @Published private(set) var entries: [DictionarySearchEntry] = []
    @Published private(set) var query: String?
    @Published private(set) var selectedRange: NSRange?
    @Published private(set) var status = ""
    @Published private(set) var isRecognizing = false
    @Published private(set) var isSearching = false
    var baseForms: [String] {
        var seen = Set<String>()
        return entries.compactMap { $0.inflection?.base }.filter { seen.insert($0).inserted }
    }

    private var task: Task<Void, Never>?
    private var generation = UUID()
    private let search: @Sendable ([String]) async throws -> DictionaryCandidateMatch?

    init(store: DictionaryStore,
         search: (@Sendable ([String]) async throws -> DictionaryCandidateMatch?)? = nil) {
        self.search = search ?? { candidates in try await store.searchCandidateMatch(candidates) }
    }

    func beginRecognizing() {
        clear()
        isRecognizing = true
        status = "OCR recognizing selected text locally…"
    }

    func setSource(_ text: String) {
        clear()
        source = text
        let candidates = DictionaryLookupText.automaticCandidates(in: text)
        if candidates.isEmpty {
            status = "Click a word in the OCR text to look it up."
        } else {
            runSearch(candidates, automatic: true)
        }
    }

    func lookup(at characterOffset: Int) {
        guard !isRecognizing else { return }
        let candidates = DictionaryLookupText.candidates(in: source, characterOffset: characterOffset)
        guard !candidates.isEmpty else {
            resetResults()
            status = "Click a word in the OCR text, not punctuation or blank space."
            return
        }
        runSearch(candidates, automatic: false)
    }

    func failRecognition(_ message: String) {
        clear()
        status = message
    }

    func clear() {
        resetResults()
        source = ""
        status = ""
        isRecognizing = false
    }

    private func resetResults() {
        generation = UUID()
        task?.cancel()
        task = nil
        entries = []
        query = nil
        selectedRange = nil
        isSearching = false
    }

    private func runSearch(_ candidates: [DictionaryWordCandidate], automatic: Bool) {
        resetResults()
        let id = generation
        let text = source
        isSearching = true
        status = "Searching local dictionaries…"
        query = candidates.first?.text
        task = Task { [weak self, search] in
            do {
                let match = try await search(candidates.map(\.text))
                guard let self, self.generation == id, !Task.isCancelled else { return }
                self.isSearching = false
                self.task = nil
                guard let match else {
                    self.status = automatic
                        ? "Click a word in the OCR text to look it up. No headword or Japanese base-form match for the full selection."
                        : "No dictionary-form match after Japanese deinflection. Try another word or a clearer OCR selection."
                    return
                }
                self.query = match.query
                self.entries = match.entries
                if let candidate = candidates.first(where: { $0.text == match.query }) {
                    self.selectedRange = DictionaryLookupText.utf16Range(candidate.range, in: text)
                }
                self.status = "\(match.entries.count) dictionary entries · Clipboard unchanged."
            } catch {
                guard let self, self.generation == id, !Task.isCancelled else { return }
                self.isSearching = false
                self.task = nil
                self.status = (error as? DictionaryError)?.errorDescription
                    ?? "Dictionary search failed. Check the installed dictionary and retry."
            }
        }
    }
}
