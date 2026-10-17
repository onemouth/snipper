import Foundation
import NaturalLanguage

struct DictionaryWordCandidate: Sendable, Equatable {
    let text: String
    let range: Range<Int> // Character offsets in the full OCR source.
}

enum DictionaryLookupText {
    static func automaticCandidates(in text: String) -> [DictionaryWordCandidate] {
        let characters = Array(text)
        guard !characters.isEmpty else { return [] }
        var results: [DictionaryWordCandidate] = []
        // A tightly selected dictionary headword should work even if the tokenizer
        // considers it multiple units. Sentences still remain available for clicking.
        if characters.count <= 48 && characters.allSatisfy(isWordCharacter) {
            results.append(DictionaryWordCandidate(text: text, range: 0..<characters.count))
        }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var tokens: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if text[range].contains(where: isWordCharacter) { tokens.append(range) }
            return tokens.count < 2
        }
        if tokens.count == 1, let token = tokens.first {
            let word = String(text[token])
            if word.count <= 48 && !results.contains(where: { $0.text == word }) {
                results.append(DictionaryWordCandidate(text: word, range: text.distance(from: text.startIndex, to: token.lowerBound)..<text.distance(from: text.startIndex, to: token.upperBound)))
            }
        }
        return results
    }

    static func candidates(in text: String, characterOffset: Int) -> [DictionaryWordCandidate] {
        let characters = Array(text)
        guard characters.indices.contains(characterOffset), isWordCharacter(characters[characterOffset]) else { return [] }
        var lower = characterOffset, upper = characterOffset + 1
        while lower > 0 && characterOffset - lower < 47 && isWordCharacter(characters[lower - 1]) { lower -= 1 }
        while upper < characters.count && upper - characterOffset < 48 && isWordCharacter(characters[upper]) { upper += 1 }
        let fragment = String(characters[lower..<upper])
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = fragment
        let tokenIndex = fragment.index(fragment.startIndex, offsetBy: characterOffset - lower)
        let tokenRange = tokenizer.tokenRange(at: tokenIndex)
        var results: [DictionaryWordCandidate] = []
        var seen = Set<String>()
        func add(_ word: String, range: Range<Int>) {
            guard !word.isEmpty, word.count <= 48, seen.insert(word).inserted else { return }
            results.append(DictionaryWordCandidate(text: word, range: range))
        }
        if !tokenRange.isEmpty {
            let start = lower + fragment.distance(from: fragment.startIndex, to: tokenRange.lowerBound)
            let end = lower + fragment.distance(from: fragment.startIndex, to: tokenRange.upperBound)
            add(String(fragment[tokenRange]), range: start..<end)
        }
        // Bounded Japanese substring matching, always containing the clicked character.
        for length in stride(from: min(12, upper - lower), through: 1, by: -1) {
            let first = max(lower, characterOffset - length + 1)
            let last = min(characterOffset, upper - length)
            guard first <= last else { continue }
            for start in first...last { add(String(characters[start..<(start + length)]), range: start..<(start + length)) }
        }
        // Prefer a complete inflected word over a shorter tokenizer stem or
        // incidental exact substring (e.g. 食べなかった before 食べ).
        return results.enumerated().sorted {
            if $0.element.text.count != $1.element.text.count { return $0.element.text.count > $1.element.text.count }
            return $0.offset < $1.offset
        }.map(\.element)
    }

    static func utf16Range(_ range: Range<Int>, in text: String) -> NSRange? {
        guard range.lowerBound >= 0, range.upperBound <= text.count, !range.isEmpty else { return nil }
        let start = text.index(text.startIndex, offsetBy: range.lowerBound)
        let end = text.index(text.startIndex, offsetBy: range.upperBound)
        return NSRange(start..<end, in: text)
    }

    static func characterOffset(atUTF16 index: Int, in text: String) -> Int? {
        let nsText = text as NSString
        guard index >= 0, index < nsText.length else { return nil }
        let cluster = nsText.rangeOfComposedCharacterSequence(at: index)
        let start = String.Index(utf16Offset: cluster.location, in: text)
        return text.distance(from: text.startIndex, to: start)
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.letters.union(.decimalDigits).contains($0) }
            || character == "ー" || character == "々" || character == "'" || character == "’"
    }
}
