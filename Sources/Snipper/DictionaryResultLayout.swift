import Foundation

/// Preserve ranking order while showing each spelling/reading and dictionary
/// heading once. Homographs with different readings remain separate.
struct DictionaryResultGroup: Sendable {
    let headword: String
    let reading: String
    var sources: [DictionaryResultSource]
}

struct DictionaryResultSource: Sendable {
    let dictionary: ImportedDictionary
    var entries: [DictionarySearchEntry]
}

enum DictionaryResultLayout {
    private struct Key: Hashable {
        let headword: String
        let reading: String
    }

    static func groups(_ entries: [DictionarySearchEntry]) -> [DictionaryResultGroup] {
        var result: [DictionaryResultGroup] = []
        var indices: [Key: Int] = [:]
        for entry in entries.prefix(100) {
            let key = Key(headword: entry.term.headword, reading: entry.term.reading)
            let index: Int
            if let existing = indices[key] { index = existing }
            else {
                index = result.count
                indices[key] = index
                result.append(DictionaryResultGroup(headword: key.headword, reading: key.reading, sources: []))
            }
            if let source = result[index].sources.firstIndex(where: { $0.dictionary.id == entry.dictionary.id }) {
                result[index].sources[source].entries.append(entry)
            } else {
                result[index].sources.append(DictionaryResultSource(dictionary: entry.dictionary, entries: [entry]))
            }
        }
        return result
    }
}

enum DictionarySourceLayout {
    static func canExpand(_ source: String) -> Bool { source.count > 16 || source.contains(where: \.isNewline) }
    static func height(expanded: Bool) -> CGFloat { expanded ? 120 : 44 }
}
