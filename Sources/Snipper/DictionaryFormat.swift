import CoreFoundation
import Foundation

// Format-compatible parsing written for Snipper; no Yomitan implementation code.
enum DictionaryFormat {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp"]

    static func safePath(_ path: String) throws -> String {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              !path.contains(":"), !path.contains("\0"), path.utf8.count <= 1024 else {
            throw DictionaryError.unsafePath
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw DictionaryError.unsafePath
        }
        return path
    }

    static func number(_ value: Any) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }

    static func index(_ data: Data) throws -> (title: String, revision: String) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = object["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let revision = object["revision"] as? String, !revision.isEmpty,
              title.utf8.count <= 1024, revision.utf8.count <= 1024,
              !title.contains("\0"), !revision.contains("\0") else { throw DictionaryError.invalidIndex }
        guard let format = object["format"], number(format) == 3 else { throw DictionaryError.unsupportedFormat }
        return (title, revision)
    }

    static func term(_ row: [Any], references: inout Set<String>) throws -> DictionaryTerm {
        guard row.count == 8, let headword = row[0] as? String,
              let reading = row[1] as? String,
              row[2] is String || row[2] is NSNull, row[3] is String,
              number(row[4]) != nil, let definitions = row[5] as? [Any],
              let sequence = number(row[6]), sequence.rounded() == sequence,
              abs(sequence) <= 9_007_199_254_740_991, row[7] is String else { throw DictionaryError.invalidTerm }
        for definition in definitions {
            if definition is String { continue }
            guard let object = definition as? [String: Any], let type = object["type"] as? String else {
                throw DictionaryError.invalidTerm
            }
            switch type {
            case "text":
                guard object["text"] is String else { throw DictionaryError.invalidTerm }
            case "image":
                try image(object, references: &references)
            case "structured-content":
                guard let content = object["content"] else { throw DictionaryError.invalidTerm }
                try contentNode(content, depth: 0, references: &references)
            default: throw DictionaryError.invalidTerm
            }
        }
        let data = try JSONSerialization.data(withJSONObject: definitions, options: [.sortedKeys, .withoutEscapingSlashes])
        return DictionaryTerm(headword: headword, reading: reading.isEmpty ? headword : reading,
                              definitionsJSON: String(decoding: data, as: UTF8.self), sequence: Int64(sequence))
    }

    private static func image(_ object: [String: Any], references: inout Set<String>) throws {
        guard let path = object["path"] as? String else { throw DictionaryError.invalidTerm }
        let safe = try safePath(path)
        guard imageExtensions.contains((safe as NSString).pathExtension.lowercased()) else {
            throw DictionaryError.missingResource
        }
        references.insert(safe)
    }

    private static func contentNode(_ value: Any, depth: Int, references: inout Set<String>) throws {
        guard depth < 64 else { throw DictionaryError.limits }
        if value is String { return }
        if let array = value as? [Any] {
            for node in array { try contentNode(node, depth: depth + 1, references: &references) }
            return
        }
        guard let object = value as? [String: Any], let tag = object["tag"] as? String,
              ["br", "ruby", "rt", "rp", "table", "thead", "tbody", "tfoot", "tr", "td", "th",
               "span", "div", "ol", "ul", "li", "details", "summary", "img", "a"].contains(tag) else {
            throw DictionaryError.invalidTerm
        }
        if tag == "img" { try image(object, references: &references) }
        if let content = object["content"] { try contentNode(content, depth: depth + 1, references: &references) }
        // Formatting is preserved as data, not interpreted or executed during import.
    }
}
