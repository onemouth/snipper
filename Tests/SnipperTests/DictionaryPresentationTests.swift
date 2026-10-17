import AppKit
import Foundation
import Testing
@testable import Snipper

@Suite @MainActor
struct DictionaryPresentationTests {
    private func dictionary(_ title: String = "Test Dictionary") -> ImportedDictionary {
        ImportedDictionary(id: UUID().uuidString, title: title, revision: "1", termCount: 10, resourceCount: 0, importedAt: Date())
    }

    private func entry(_ dictionary: ImportedDictionary, headword: String = "猫", reading: String = "ねこ",
                       definitions: [Any] = ["An original synthetic definition."] ) throws -> DictionarySearchEntry {
        let data = try JSONSerialization.data(withJSONObject: definitions)
        let term = DictionaryTerm(headword: headword, reading: reading, definitionsJSON: String(decoding: data, as: UTF8.self), sequence: 1)
        return DictionarySearchEntry(dictionary: dictionary, term: term, resources: URL(fileURLWithPath: "/unused-test-resources"))
    }

    @Test func groupsSpellingReadingAndSourcesWithoutMergingHomographs() throws {
        let first = dictionary(), second = dictionary("Other Dictionary")
        let entries = try [entry(first), entry(second, headword: "犬", reading: "いぬ"),
                           entry(first), entry(first, reading: "びょう"), entry(second)]
        let groups = DictionaryResultLayout.groups(entries)
        #expect(groups.count == 3)
        #expect(groups[0].headword == "猫")
        #expect(groups[0].reading == "ねこ")
        #expect(groups[0].sources.map { $0.dictionary.id } == [first.id, second.id])
        #expect(groups[0].sources[0].entries.count == 2)
        #expect(groups[1].headword == "犬")
        #expect(groups[2].reading == "びょう")
    }

    @Test func headingsAppearOnceAndSensesHaveHangingIndents() throws {
        let source = dictionary()
        let entries = try [entry(source, definitions: ["First sense."]), entry(source, definitions: ["Second sense."])]
        let rendered = DictionaryDefinitionRenderer().render(entries)
        #expect(rendered.string.components(separatedBy: "猫\n").count == 2)
        #expect(rendered.string.components(separatedBy: "ねこ\n").count == 2)
        #expect(rendered.string.components(separatedBy: source.title).count == 2)
        #expect(rendered.string.contains("1.\tFirst sense."))
        #expect(rendered.string.contains("2.\tSecond sense."))
        let range = (rendered.string as NSString).range(of: "First sense")
        let paragraph = try #require(rendered.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)
        #expect(paragraph.headIndent > paragraph.firstLineHeadIndent)
    }

    @Test func inflectionIsExplainedOncePerHeadwordNotOncePerEntry() throws {
        let source = dictionary()
        var first = try entry(source, headword: "食べる", reading: "たべる")
        first.inflection = DictionaryInflection(source: "食べた", base: "食べる", reasons: ["-た"])
        var second = try entry(source, headword: "食べる", reading: "たべる")
        second.inflection = first.inflection
        let rendered = DictionaryDefinitionRenderer().render([first, second]).string
        #expect(rendered.components(separatedBy: "食べた → 食べる").count == 2)
    }

    @Test func structuredListsAndNestedEmphasisRemainNative() throws {
        let content: [String: Any] = ["type": "structured-content", "content": [
            ["tag": "ol", "content": [
                ["tag": "li", "content": "First item"],
                ["tag": "li", "content": ["Second item", ["tag": "ul", "content": [
                    ["tag": "li", "content": "Nested item"],
                ]]]],
            ]],
            ["tag": "strong", "content": ["tag": "em", "content": "Emphasis"]],
        ]]
        let rendered = DictionaryDefinitionRenderer().render([try entry(dictionary(), definitions: [content])])
        #expect(rendered.string.contains("1.\tFirst item"))
        #expect(rendered.string.contains("2.\tSecond item"))
        #expect(rendered.string.contains("•\tNested item"))
        let range = (rendered.string as NSString).range(of: "Emphasis")
        let font = try #require(rendered.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
        let traits = NSFontManager.shared.traits(of: font)
        #expect(traits.contains(.boldFontMask))
        #expect(traits.contains(.italicFontMask))
        let nestedRange = (rendered.string as NSString).range(of: "Nested item")
        let nested = try #require(rendered.attribute(.paragraphStyle, at: nestedRange.location, effectiveRange: nil) as? NSParagraphStyle)
        #expect(nested.headIndent > 30)
    }

    @Test func reusableRendererDoesNotKeepOldResults() throws {
        let renderer = DictionaryDefinitionRenderer()
        let first = renderer.render([try entry(dictionary(), definitions: ["Old content."])])
        let second = renderer.render([try entry(dictionary(), definitions: ["New content."])]).string
        #expect(second.contains("New content."))
        #expect(!second.contains("Old content."))
        #expect(first.string.contains("Old content."))
        #expect(!first.string.contains("New content."))
    }

    @Test func persistedDefinitionTagsBecomeNativeBadges() async throws {
        let fixture = try DictionaryFixture(files: DictionaryFixture.files())
        defer { fixture.cleanup() }
        let store = DictionaryStore(root: fixture.root)
        _ = try await store.importDictionary(from: fixture.archive)
        let entries = try await store.search("猫")
        #expect(entries.first?.term.definitionTags == ["noun"])
        #expect(entries.last?.term.definitionTags.isEmpty == true)
        let rendered = DictionaryDefinitionRenderer().render(entries)
        let range = (rendered.string as NSString).range(of: " noun ")
        #expect(range.location != NSNotFound)
        if range.location != NSNotFound {
            #expect(rendered.attribute(.backgroundColor, at: range.location, effectiveRange: nil) != nil)
        }
    }

    @Test func originalTextStartsCompactAndLongTextCanExpand() {
        #expect(DictionarySourceLayout.height(expanded: false) == 44)
        #expect(DictionarySourceLayout.height(expanded: true) > DictionarySourceLayout.height(expanded: false))
        #expect(!DictionarySourceLayout.canExpand("食べなかった"))
        #expect(DictionarySourceLayout.canExpand("猫\n犬"))
        #expect(DictionarySourceLayout.canExpand(String(repeating: "猫", count: 17)))
    }
}
