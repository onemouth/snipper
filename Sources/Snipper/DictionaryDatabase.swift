import CSQLite
import Foundation

struct ImportedDictionary: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let revision: String
    let termCount: Int
    let resourceCount: Int
    let importedAt: Date
}

struct DictionaryTerm: Equatable, Sendable {
    let headword: String
    let reading: String
    let definitionsJSON: String
    let sequence: Int64
}

enum DictionaryError: LocalizedError {
    case invalidArchive, unsafePath, limits, invalidIndex, invalidTerm, invalidTag
    case unsupportedFormat, duplicate, missingResource, storage, missingDictionary

    var errorDescription: String? {
        switch self {
        case .invalidArchive: "The ZIP could not be read. It may be damaged, encrypted, or unsupported."
        case .unsafePath: "The ZIP contains an unsafe path or a link. Nothing was imported."
        case .limits: "The dictionary exceeds the import size or entry limits."
        case .invalidIndex: "The dictionary needs a valid index.json at the ZIP root."
        case .invalidTerm: "A term bank contains invalid or unsupported entry data."
        case .invalidTag: "A tag bank contains invalid entry data."
        case .unsupportedFormat: "Only Yomitan format 3 term dictionaries are supported."
        case .duplicate: "A dictionary with this title is already installed. Delete it before importing a replacement."
        case .missingResource: "A definition references a missing or unsupported local image."
        case .storage: "Dictionary storage could not be read or written. Check available disk space and folder permissions."
        case .missingDictionary: "The selected dictionary is no longer available."
        }
    }
}

// Confined to the DictionaryStore actor. No connections or statements cross actors.
final class DictionaryDatabase {
    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL, create: Bool) throws {
        let flags = create ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            handle = nil
            throw DictionaryError.storage
        }
        sqlite3_progress_handler(handle, 10_000, { _ in Task.isCancelled ? 1 : 0 }, nil)
        if create {
            try execute("""
                PRAGMA journal_mode=DELETE;
                PRAGMA synchronous=FULL;
                PRAGMA user_version=1;
                CREATE TABLE dictionary (summary TEXT NOT NULL, source_metadata TEXT NOT NULL);
                CREATE TABLE terms (
                    id INTEGER PRIMARY KEY, headword TEXT NOT NULL, reading TEXT NOT NULL,
                    definition_tags TEXT, rules TEXT NOT NULL, score REAL NOT NULL,
                    definitions_json TEXT NOT NULL, sequence INTEGER NOT NULL, term_tags TEXT NOT NULL
                );
                CREATE TABLE tags (name TEXT NOT NULL, category TEXT NOT NULL, sort_order REAL NOT NULL,
                                   notes TEXT NOT NULL, score REAL NOT NULL);
                """)
        }
    }

    deinit { if let handle { sqlite3_close(handle) } }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            try Task.checkCancellation()
            throw DictionaryError.storage
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DictionaryError.storage
        }
        return statement
    }

    func bind(_ value: String?, to statement: OpaquePointer, at index: Int32) throws {
        let result: Int32
        if let value {
            result = value.withCString { sqlite3_bind_text(statement, index, $0, Int32(value.utf8.count), Self.transient) }
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else { throw DictionaryError.storage }
    }

    private func insert(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            try Task.checkCancellation()
            throw DictionaryError.storage
        }
    }

    func insertTerms(_ rows: [[Any]], check: () throws -> Void, references: inout Set<String>) throws -> Int {
        let statement = try prepare("INSERT INTO terms VALUES(NULL, ?, ?, ?, ?, ?, ?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        for (index, row) in rows.enumerated() {
            if index % 128 == 0 { try check() }
            let term = try DictionaryFormat.term(row, references: &references)
            try bind(term.headword, to: statement, at: 1)
            try bind(term.reading, to: statement, at: 2)
            try bind(row[2] as? String, to: statement, at: 3)
            try bind(row[3] as? String, to: statement, at: 4)
            guard sqlite3_bind_double(statement, 5, (row[4] as! NSNumber).doubleValue) == SQLITE_OK else { throw DictionaryError.storage }
            try bind(term.definitionsJSON, to: statement, at: 6)
            guard sqlite3_bind_int64(statement, 7, term.sequence) == SQLITE_OK else { throw DictionaryError.storage }
            try bind(row[7] as? String, to: statement, at: 8)
            try insert(statement)
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        return rows.count
    }

    func insertTags(_ rows: [[Any]]) throws {
        let statement = try prepare("INSERT INTO tags VALUES(?, ?, ?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        for row in rows {
            try Task.checkCancellation()
            guard row.count == 5, let name = row[0] as? String,
                  let category = row[1] as? String, let notes = row[3] as? String,
                  let order = DictionaryFormat.number(row[2]), let score = DictionaryFormat.number(row[4]) else {
                throw DictionaryError.invalidTag
            }
            try bind(name, to: statement, at: 1)
            try bind(category, to: statement, at: 2)
            try bind(notes, to: statement, at: 4)
            guard sqlite3_bind_double(statement, 3, order) == SQLITE_OK,
                  sqlite3_bind_double(statement, 5, score) == SQLITE_OK else { throw DictionaryError.storage }
            try insert(statement)
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
    }

    func finish(summary: ImportedDictionary, metadata: Data) throws {
        try execute("""
            CREATE INDEX terms_headword ON terms(headword);
            CREATE INDEX terms_reading ON terms(reading);
            CREATE INDEX terms_sequence ON terms(sequence);
            """)
        let statement = try prepare("INSERT INTO dictionary VALUES(?, ?)")
        defer { sqlite3_finalize(statement) }
        try bind(String(decoding: JSONEncoder().encode(summary), as: UTF8.self), to: statement, at: 1)
        try bind(String(decoding: metadata, as: UTF8.self), to: statement, at: 2)
        try insert(statement)
        try execute("COMMIT")
    }

    func summary() throws -> ImportedDictionary {
        let statement = try prepare("SELECT summary FROM dictionary LIMIT 1")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0),
              let summary = try? JSONDecoder().decode(ImportedDictionary.self, from: Data(String(cString: text).utf8)) else {
            throw DictionaryError.storage
        }
        return summary
    }

    func lookup(_ text: String, limit: Int) throws -> [DictionaryTerm] {
        let statement = try prepare("""
            SELECT headword, reading, definitions_json, sequence FROM terms
            WHERE headword = ? OR reading = ? ORDER BY score DESC, id LIMIT ?
            """)
        defer { sqlite3_finalize(statement) }
        try bind(text, to: statement, at: 1)
        try bind(text, to: statement, at: 2)
        sqlite3_bind_int(statement, 3, Int32(max(1, min(limit, 100))))
        var terms: [DictionaryTerm] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return terms }
            guard status == SQLITE_ROW else { throw DictionaryError.storage }
            func string(_ column: Int32) -> String { String(cString: sqlite3_column_text(statement, column)) }
            terms.append(DictionaryTerm(headword: string(0), reading: string(1), definitionsJSON: string(2), sequence: sqlite3_column_int64(statement, 3)))
        }
    }
}
