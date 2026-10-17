import AppKit
import Foundation
import Testing
@testable import Snipper

@Suite @MainActor
struct DictionarySearchTests {
    private func entry(definitions: [Any], resources: URL) throws -> DictionarySearchEntry {
        let dictionary = ImportedDictionary(id: UUID().uuidString, title: "Original test dictionary", revision: "1",
                                            termCount: 1, resourceCount: 0, importedAt: Date())
        let data = try JSONSerialization.data(withJSONObject: definitions)
        let term = DictionaryTerm(headword: "猫", reading: "ねこ", definitionsJSON: String(decoding: data, as: UTF8.self), sequence: 1)
        return DictionarySearchEntry(dictionary: dictionary, term: term, resources: resources)
    }

    @Test func rendersHeadwordsReadingsDefinitionsAndLocalImages() async throws {
        let fixture = try DictionaryFixture(files: DictionaryFixture.files())
        defer { fixture.cleanup() }
        let store = DictionaryStore(root: fixture.root)
        _ = try await store.importDictionary(from: fixture.archive)
        let matches = try await store.search("猫")
        let rendered = DictionaryDefinitionRenderer().render(matches)
        #expect(rendered.string.contains("猫"))
        #expect(rendered.string.contains("ねこ"))
        #expect(rendered.string.contains("Snipper Original Test Dictionary"))
        #expect(rendered.string.contains("original test definition"))
        #expect(!rendered.string.contains("Image unavailable"))
        var attachments = 0
        rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if value is NSTextAttachment { attachments += 1 }
        }
        #expect(attachments == 1)
    }

    @Test func markupAndLinksCannotExecuteOrFetch() throws {
        let fixture = try DictionaryFixture(files: [])
        defer { fixture.cleanup() }
        let content: [String: Any] = ["type": "structured-content", "content": [
            ["tag": "a", "href": "https://invalid.example/private", "content": "A link label"],
            ["tag": "br"],
            ["tag": "span", "style": ["fontWeight": "bold"], "content": "Emphasized"],
        ]]
        let match = try entry(definitions: ["<script>not HTML</script>", content], resources: fixture.root)
        let rendered = DictionaryDefinitionRenderer().render([match])
        #expect(rendered.string.contains("<script>not HTML</script>"))
        #expect(rendered.string.contains("A link label"))
        #expect(rendered.string.contains("Emphasized"))
        var hasLink = false
        rendered.enumerateAttribute(.link, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if value != nil { hasLink = true }
        }
        #expect(!hasLink)
    }

    @Test func imageTraversalAndSymlinksAreNotRead() throws {
        let fixture = try DictionaryFixture(files: [])
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
        let outside = fixture.directory.appendingPathComponent("outside.png")
        try DictionaryFixture.png.write(to: outside)
        try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("linked.png"), withDestinationURL: outside)
        let definitions: [[String: Any]] = [
            ["type": "image", "path": "../outside.png"],
            ["type": "image", "path": "linked.png"],
            ["type": "image", "path": "https://invalid.example/image.png"],
        ]
        let match = try entry(definitions: definitions, resources: fixture.root)
        let rendered = DictionaryDefinitionRenderer().render([match])
        #expect(rendered.string.contains("Image unavailable"))
        var hasImage = false
        rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if value != nil { hasImage = true }
        }
        #expect(!hasImage)
    }

    @Test func previewsHaveTextBudgets() throws {
        let fixture = try DictionaryFixture(files: [])
        defer { fixture.cleanup() }
        let match = try entry(definitions: [String(repeating: "あ", count: 150_000)], resources: fixture.root)
        let rendered = DictionaryDefinitionRenderer().render([match])
        #expect(rendered.length < 100_100)
        #expect(rendered.string.contains("shortened"))
    }

    @Test func searchModelShowsNoMatchesAndRejectsStaleSearches() async throws {
        let fixture = try DictionaryFixture(files: DictionaryFixture.files())
        defer { fixture.cleanup() }
        let store = DictionaryStore(root: fixture.root)
        _ = try await store.importDictionary(from: fixture.archive)
        let model = DictionariesModel(store: store)
        await model.refresh()
        model.search("猫", dictionaryID: nil)
        try await waitForSearch(model)
        #expect(model.searchResults.count == 2)
        #expect(model.showSearchResults)
        model.search("猫", dictionaryID: nil)
        model.search("not-in-the-dictionary", dictionaryID: nil)
        try await waitForSearch(model)
        #expect(model.searchResults.isEmpty)
        #expect(!model.showSearchResults)
        #expect(model.searchStatus.contains("No headword"))
        model.search("猫", dictionaryID: nil)
        model.resetSearch()
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.searchResults.isEmpty)
        #expect(!model.showSearchResults)
        #expect(!model.isSearching)
        model.search(String(repeating: "a", count: 257), dictionaryID: nil)
        #expect(model.searchStatus.contains("256"))
    }

    private func waitForSearch(_ model: DictionariesModel) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while model.isSearching && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!model.isSearching)
    }
}
