import AppKit
import Foundation
import Testing
@testable import Snipper

// Original, tiny fixtures generated in memory. No third-party dictionary content.
struct DictionaryFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SnipperDictionaryTests-\(UUID().uuidString)")
    var root: URL { directory.appendingPathComponent("installed") }
    var archive: URL { directory.appendingPathComponent("dictionary.zip") }

    init(files: [(String, Data)]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.zip(files).write(to: archive)
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }

    static func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
    static func index(format: Int = 3, title: String = "Snipper Original Test Dictionary") throws -> Data {
        try json(["title": title, "format": format, "revision": "1", "sequenced": true])
    }
    static var png: Data { Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aQ1sAAAAASUVORK5CYII=")! }
    static func terms() throws -> Data {
        let structured: [String: Any] = ["type": "structured-content", "content": ["A sample glyph ", ["tag": "img", "path": "images/glyph.png"]]]
        return try json([
            ["猫", "ねこ", "noun", "", 10, ["An original test definition: cat."], 1, "common"] as [Any],
            ["猫", "ねこ", NSNull(), "", 2, [structured], 1, ""] as [Any],
            ["test", "", "", "", 0, ["Reading falls back to the headword."], 2, ""] as [Any],
        ])
    }
    static func files() throws -> [(String, Data)] {
        try [("index.json", index()), ("term_bank_1.json", terms()),
             ("tag_bank_1.json", json([["noun", "partOfSpeech", 0, "Noun", 0]])),
             ("images/glyph.png", png)]
    }

    // Minimal ZIP writer for stored fixtures, including deliberately unsafe names.
    static func zip(_ files: [(String, Data)], symlinks: Set<String> = []) -> Data {
        var archive = Data(), central = Data()
        func crc32(_ data: Data) -> UInt32 {
            var crc: UInt32 = 0xffffffff
            for byte in data {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) }
            }
            return crc ^ 0xffffffff
        }
        for (path, data) in files {
            let name = Data(path.utf8), offset = UInt32(archive.count), crc = crc32(data)
            archive.le(UInt32(0x04034b50)); archive.le(UInt16(20)); archive.le(UInt16(0x800))
            archive.le(UInt16(0)); archive.le(UInt16(0)); archive.le(UInt16(0))
            archive.le(crc); archive.le(UInt32(data.count)); archive.le(UInt32(data.count))
            archive.le(UInt16(name.count)); archive.le(UInt16(0)); archive.append(name); archive.append(data)
            central.le(UInt32(0x02014b50)); central.le(UInt16(0x0314)); central.le(UInt16(20)); central.le(UInt16(0x800))
            central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt16(0))
            central.le(crc); central.le(UInt32(data.count)); central.le(UInt32(data.count))
            central.le(UInt16(name.count)); central.le(UInt16(0)); central.le(UInt16(0))
            central.le(UInt16(0)); central.le(UInt16(0))
            central.le(UInt32(symlinks.contains(path) ? 0o120777 : 0o100644) << 16)
            central.le(offset); central.append(name)
        }
        let offset = UInt32(archive.count)
        archive.append(central)
        archive.le(UInt32(0x06054b50)); archive.le(UInt16(0)); archive.le(UInt16(0))
        archive.le(UInt16(files.count)); archive.le(UInt16(files.count)); archive.le(UInt32(central.count))
        archive.le(offset); archive.le(UInt16(0))
        return archive
    }
}

private extension Data {
    mutating func le<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}

struct DictionaryTests {
    @Test func importsPersistsQueriesAndDeletes() async throws {
        let fixture = try DictionaryFixture(files: DictionaryFixture.files())
        defer { fixture.cleanup() }
        let store = DictionaryStore(root: fixture.root)
        let summary = try await store.importDictionary(from: fixture.archive)
        #expect(summary.termCount == 3)
        #expect(summary.resourceCount == 1)
        #expect(summary.revision == "1")
        let words = try await store.lookup("猫", dictionaryID: summary.id)
        #expect(words.count == 2)
        #expect(words[0].definitionsJSON.contains("original test definition"))
        #expect(words[1].definitionsJSON.contains("images/glyph.png"))
        #expect(try await store.lookup("ねこ", dictionaryID: summary.id) == words)
        #expect(try await store.lookup("unknown", dictionaryID: summary.id).isEmpty)
        #expect(try await store.lookup("test", dictionaryID: summary.id).first?.reading == "test")
        let resource = fixture.root.appendingPathComponent(summary.id).appendingPathComponent("resources/images/glyph.png")
        #expect(try Data(contentsOf: resource) == DictionaryFixture.png)
        let reopened = DictionaryStore(root: fixture.root)
        #expect(try await reopened.dictionaries() == [summary])
        try await reopened.delete(id: summary.id)
        #expect(try await reopened.dictionaries().isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.archive.path))
        #expect(!FileManager.default.fileExists(atPath: resource.path))
    }

    @Test func searchesAcrossDictionariesWithSelectionAndLimits() async throws {
        let fixture = try DictionaryFixture(files: DictionaryFixture.files())
        defer { fixture.cleanup() }
        let store = DictionaryStore(root: fixture.root)
        let first = try await store.importDictionary(from: fixture.archive)
        var secondFiles = try DictionaryFixture.files().filter { $0.0 != "index.json" }
        secondFiles.append(("index.json", try DictionaryFixture.index(title: "Second Original Test Dictionary")))
        try DictionaryFixture.zip(secondFiles).write(to: fixture.archive)
        let second = try await store.importDictionary(from: fixture.archive)
        #expect(try await store.search(" 猫 \n").count == 4)
        let selected = try await store.search("ねこ", dictionaryID: second.id)
        #expect(selected.count == 2)
        #expect(selected.allSatisfy { $0.dictionary.id == second.id })
        #expect(selected.first?.resources.lastPathComponent == "resources")
        #expect(try await store.search("猫", dictionaryID: first.id, limit: 1).count == 1)
        #expect(try await store.search("猫", limit: 3).count == 3)
        #expect(try await store.search("  ").isEmpty)
        #expect(try await store.search(String(repeating: "x", count: 257)).isEmpty)
        #expect(try await store.search("missing").isEmpty)
        await #expect(throws: DictionaryError.self) { try await store.search("猫", dictionaryID: UUID().uuidString) }
    }

    @Test func duplicateDoesNotChangeExistingDictionary() async throws {
        let fixture = try DictionaryFixture(files: DictionaryFixture.files())
        defer { fixture.cleanup() }
        let store = DictionaryStore(root: fixture.root)
        let original = try await store.importDictionary(from: fixture.archive)
        await #expect(throws: DictionaryError.self) { try await store.importDictionary(from: fixture.archive) }
        #expect(try await store.dictionaries() == [original])
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path) == [original.id])
    }

    @Test func invalidEntriesRollback() async throws {
        var files = try DictionaryFixture.files()
        files.append(("term_bank_2.json", try DictionaryFixture.json([["broken"]])))
        let fixture = try DictionaryFixture(files: files)
        defer { fixture.cleanup() }
        let store = DictionaryStore(root: fixture.root)
        await #expect(throws: DictionaryError.self) { try await store.importDictionary(from: fixture.archive) }
        #expect(try await store.dictionaries().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).isEmpty)
    }

    @Test func tagsAreValidatedAndRollback() async throws {
        var files = try DictionaryFixture.files().filter { $0.0 != "tag_bank_1.json" }
        files.append(("tag_bank_1.json", try DictionaryFixture.json([["broken"]])))
        let fixture = try DictionaryFixture(files: files)
        defer { fixture.cleanup() }
        let store = DictionaryStore(root: fixture.root)
        await #expect(throws: DictionaryError.self) { try await store.importDictionary(from: fixture.archive) }
        #expect(try await store.dictionaries().isEmpty)
    }

    @Test func symlinksAndCorruptCRCRejected() async throws {
        let original = try DictionaryFixture.files()
        let fixture = try DictionaryFixture(files: original)
        defer { fixture.cleanup() }
        let store = DictionaryStore(root: fixture.root)
        let linked = original + [("outside-link", Data("../../outside".utf8))]
        try DictionaryFixture.zip(linked, symlinks: ["outside-link"]).write(to: fixture.archive)
        await #expect(throws: DictionaryError.self) { try await store.importDictionary(from: fixture.archive) }
        #expect(try await store.dictionaries().isEmpty)
        var damaged = DictionaryFixture.zip(original)
        // Change a byte in the first entry payload without updating its CRC.
        damaged[30 + original[0].0.utf8.count] ^= 1
        try damaged.write(to: fixture.archive)
        await #expect(throws: DictionaryError.self) { try await store.importDictionary(from: fixture.archive) }
        #expect(try await store.dictionaries().isEmpty)
    }

    @Test func missingResourceRollsBack() async throws {
        let fixture = try DictionaryFixture(files: DictionaryFixture.files().filter { !$0.0.hasSuffix(".png") })
        defer { fixture.cleanup() }
        let store = DictionaryStore(root: fixture.root)
        await #expect(throws: DictionaryError.self) { try await store.importDictionary(from: fixture.archive) }
        #expect(try await store.dictionaries().isEmpty)
    }

    @Test(arguments: ["../escape.png", "/absolute.png", "images/../escape.png", "images//escape.png"])
    func unsafeArchivePathsAreRejected(path: String) async throws {
        var files = try DictionaryFixture.files()
        files.append((path, Data([1])))
        let fixture = try DictionaryFixture(files: files)
        defer { fixture.cleanup() }
        let store = DictionaryStore(root: fixture.root)
        await #expect(throws: DictionaryError.self) { try await store.importDictionary(from: fixture.archive) }
        #expect(try await store.dictionaries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("escape.png").path))
    }

    @Test func duplicateArchivePathsAreRejected() async throws {
        var files = try DictionaryFixture.files()
        files.append(("IMAGES/glyph.png", DictionaryFixture.png))
        let fixture = try DictionaryFixture(files: files)
        defer { fixture.cleanup() }
        let store = DictionaryStore(root: fixture.root)
        await #expect(throws: DictionaryError.self) { try await store.importDictionary(from: fixture.archive) }
        #expect(try await store.dictionaries().isEmpty)
    }

    @Test func unsupportedFormatAndMissingIndex() async throws {
        for index in [try DictionaryFixture.index(format: 2), Data("{}".utf8)] {
            var files = try DictionaryFixture.files().filter { $0.0 != "index.json" }
            files.append(("index.json", index))
            let fixture = try DictionaryFixture(files: files)
            defer { fixture.cleanup() }
            let store = DictionaryStore(root: fixture.root)
            await #expect(throws: DictionaryError.self) { try await store.importDictionary(from: fixture.archive) }
            #expect(try await store.dictionaries().isEmpty)
        }
    }

    @Test func importLimits() async throws {
        let fixture = try DictionaryFixture(files: DictionaryFixture.files())
        defer { fixture.cleanup() }
        for limits in [DictionaryImportLimits(archiveBytes: 1), .init(expandedBytes: 10),
                       .init(fileBytes: 10), .init(files: 1), .init(terms: 1)] {
            let store = DictionaryStore(root: fixture.root, limits: limits)
            await #expect(throws: DictionaryError.self) { try await store.importDictionary(from: fixture.archive) }
            #expect(try await store.dictionaries().isEmpty)
        }
    }

    @Test func cancellationRollsBack() async throws {
        // Put terms first so cancellation happens after rows were actually inserted.
        let files = try DictionaryFixture.files()
        let fixture = try DictionaryFixture(files: files.filter { $0.0.hasPrefix("term_bank_") } + files.filter { !$0.0.hasPrefix("term_bank_") })
        defer { fixture.cleanup() }
        let store = DictionaryStore(root: fixture.root)
        let task = Task {
            try await store.importDictionary(from: fixture.archive) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await store.dictionaries().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).isEmpty)
    }

    @Test func booleanNumbersAndUnsafeReferencesRejected() throws {
        #expect(throws: DictionaryError.self) { try DictionaryFormat.safePath("images\\escape.png") }
        var references = Set<String>()
        let invalid: [Any] = ["test", "", "", "", true, ["definition"], 1, ""]
        #expect(throws: DictionaryError.self) { try DictionaryFormat.term(invalid, references: &references) }
        let image: [String: Any] = ["type": "image", "path": "../outside.png"]
        let unsafe: [Any] = ["test", "", "", "", 0, [image], 1, ""]
        #expect(throws: DictionaryError.self) { try DictionaryFormat.term(unsafe, references: &references) }
        let emptyHeadword: [Any] = ["", "", "", "", 0, ["An empty-headword entry is allowed by format 3."], 1, ""]
        #expect(try DictionaryFormat.term(emptyHeadword, references: &references).headword.isEmpty)
    }

    @Test func corruptArchiveAndInvalidIDs() async throws {
        let fixture = try DictionaryFixture(files: DictionaryFixture.files())
        defer { fixture.cleanup() }
        try Data("Not a ZIP".utf8).write(to: fixture.archive)
        let store = DictionaryStore(root: fixture.root)
        await #expect(throws: DictionaryError.self) { try await store.importDictionary(from: fixture.archive) }
        await #expect(throws: DictionaryError.self) { try await store.delete(id: "../outside") }
        await #expect(throws: DictionaryError.self) { try await store.lookup("test", dictionaryID: "../outside") }
        #expect(try await store.dictionaries().isEmpty)
    }

    @Test func interruptedStagingIsCleaned() async throws {
        let fixture = try DictionaryFixture(files: [])
        defer { fixture.cleanup() }
        let staging = fixture.root.appendingPathComponent(".import-interrupted")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let store = DictionaryStore(root: fixture.root)
        #expect(try await store.dictionaries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: staging.path))
    }

    // Opt-in local integration: private ZIP never enters the repository or test bundle.
    @Test func localDictionaryIntegration() async throws {
        guard let path = ProcessInfo.processInfo.environment["SNIPPER_TEST_DICTIONARY"] else { return }
        let fixture = try DictionaryFixture(files: [])
        defer { fixture.cleanup() }
        let store = DictionaryStore(root: fixture.root)
        let summary = try await store.importDictionary(from: URL(fileURLWithPath: path))
        #expect(summary.termCount == 92_217)
        #expect(summary.resourceCount == 2_598)
        #expect(!(try await store.lookup("猫", dictionaryID: summary.id)).isEmpty)
        #expect(try await DictionaryStore(root: fixture.root).dictionaries() == [summary])
    }
}
