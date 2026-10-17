// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import Snipper

struct JapaneseDeinflectionTests {
    private struct Fixture: Decodable {
        struct Case: Decodable {
            let category: String
            let valid: Bool
            let source: String
            let term: String
            let conditions: UInt32?
            let reasons: [String]?
        }
        let revision: String
        let cases: [Case]
    }

    @Test func matchesAllUpstreamJapaneseCasesIncludingReasonChains() throws {
        let url = try #require(Bundle.module.url(forResource: "JapaneseDeinflectionTests", withExtension: "json"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let engine = try JapaneseDeinflector.load()
        #expect(fixture.revision == engine.revision)
        #expect(fixture.cases.count == 1446)
        var cache: [String: [JapaneseDeinflection]] = [:]
        for test in fixture.cases {
            let forms: [JapaneseDeinflection]
            if let cached = cache[test.source] { forms = cached }
            else { forms = try engine.deinflect(test.source); cache[test.source] = forms }
            let found = forms.contains { form in
                form.text == test.term
                    && (test.conditions == nil || form.conditions == 0 || form.conditions & test.conditions! != 0)
                    && (test.reasons == nil || form.reasons == test.reasons!)
            }
            #expect(found == test.valid, "\(test.category): \(test.source) → \(test.term), reasons \(test.reasons ?? [])")
        }
    }

    @Test func commonFormsAndDictionaryRuleFiltering() throws {
        let engine = try JapaneseDeinflector.load()
        for (source, base, rule) in [
            ("食べた", "食べる", "v1"), ("食べなかった", "食べる", "v1"),
            ("読んでいる", "読む", "v5"), ("行きました", "行く", "v5"),
            ("高かった", "高い", "adj-i"), ("勉強しました", "勉強する", "vs"),
            ("来なかった", "来る", "vk"), ("食べさせられなかった", "食べる", "v1"),
        ] {
            let forms = try engine.deinflect(source)
            let form = try #require(forms.first { $0.text == base && engine.matches($0.conditions, dictionaryRules: rule) })
            #expect(!form.reasons.isEmpty)
            #expect(!engine.matches(form.conditions, dictionaryRules: "noun"))
            #expect(!engine.matches(form.conditions, dictionaryRules: ""))
            #expect(engine.matches(form.conditions, dictionaryRules: "unknown \(rule)"))
        }
        #expect(try engine.deinflect("test").count == 1)
    }

    @Test func boundedExpansionAndCancellation() async throws {
        let engine = try JapaneseDeinflector.load()
        let forms = try engine.deinflect("食べさせられなくなってしまいました", maximumResults: 12, maximumDepth: 3)
        #expect(forms.count <= 12)
        #expect(forms.allSatisfy { $0.reasons.count <= 3 })
        #expect(try engine.deinflect(String(repeating: "た", count: 100)).count == 1)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try engine.deinflect("食べなかった")
        }
        do { _ = try await task.value; Issue.record("Cancelled deinflection should throw") }
        catch is CancellationError { }
    }
}

struct DictionaryDeinflectionSearchTests {
    private func fixture(includeExact: Bool = false) throws -> DictionaryFixture {
        var rows: [[Any]] = [
            ["食べる", "たべる", "", "v1", 10, ["Original synthetic ichidan definition."], 1, ""],
            ["読む", "よむ", "", "v5", 10, ["Original synthetic godan definition."], 2, ""],
            ["行く", "いく", "", "v5", 10, ["Original synthetic irregular godan definition."], 3, ""],
            ["高い", "たかい", "", "adj-i", 10, ["Original synthetic adjective definition."], 4, ""],
            ["する", "する", "", "vs", 10, ["Original synthetic suru definition."], 5, ""],
            ["来る", "くる", "", "vk", 10, ["Original synthetic kuru definition."], 6, ""],
            ["着る", "きる", "", "v1", 10, ["Original synthetic kiru definition."], 7, ""],
            ["謎る", "なぞる", "", "", 10, ["No rule tags: exact lookup only."], 8, ""],
        ]
        // High-scoring incompatible rows must not hide a compatible entry after
        // the 30-result cutoff. These intentionally nonsensical rows are synthetic.
        for index in 0..<45 {
            rows.append(["食べる", "たべる", "", "noun", 1000, ["Incompatible noun \(index)."], 100 + index, ""])
        }
        if includeExact { rows.append(["食べた", "たべた", "", "", 10, ["Exact spelling must win."], 500, ""]) }
        return try DictionaryFixture(files: [("index.json", DictionaryFixture.index()), ("term_bank_1.json", DictionaryFixture.json(rows))])
    }

    @Test func searchAndOCRCandidatesUseFilteredBaseForms() async throws {
        let fixture = try fixture()
        defer { fixture.cleanup() }
        let store = DictionaryStore(root: fixture.root)
        let dictionary = try await store.importDictionary(from: fixture.archive)
        for (source, base) in [("食べなかった", "食べる"), ("読んでいる", "読む"), ("行きました", "行く"),
                               ("高かった", "高い"), ("しました", "する"), ("来なかった", "来る")] {
            let entries = try await store.search(source, dictionaryID: dictionary.id, limit: 1)
            #expect(entries.count == 1)
            #expect(entries.first?.term.headword == base)
            #expect(entries.first?.inflection?.source == source)
            #expect(entries.first?.inflection?.base == base)
            #expect(entries.first?.inflection?.reasons.isEmpty == false)
        }
        let text = "昨日は食べなかった。"
        let candidates = DictionaryLookupText.candidates(in: text, characterOffset: 3)
        let match = try #require(await store.searchCandidateMatch(candidates.map(\.text)))
        #expect(match.query == "食べなかった")
        #expect(match.entries.count == 1)
        #expect(match.entries.first?.term.headword == "食べる")
        #expect(try await store.search("謎った").isEmpty)
        #expect(try await store.search("謎る").count == 1)
        #expect(try await store.lookup("食べなかった", dictionaryID: dictionary.id).isEmpty)
    }

    @Test func exactMatchWinsAndAmbiguousLemmasRemainVisible() async throws {
        let fixture = try fixture(includeExact: true)
        defer { fixture.cleanup() }
        let store = DictionaryStore(root: fixture.root)
        _ = try await store.importDictionary(from: fixture.archive)
        let exact = try await store.search("食べた")
        #expect(exact.count == 1)
        #expect(exact.first?.term.headword == "食べた")
        #expect(exact.first?.inflection == nil)
        let ambiguous = try await store.search("きた")
        #expect(Set(ambiguous.map { $0.term.headword }) == ["来る", "着る"])
        #expect(Set(ambiguous.compactMap { $0.inflection?.base }) == ["くる", "きる"])
    }

    @Test @MainActor func sourceSelectionStaysOnSurfaceFormAndRendererExplainsDerivation() async throws {
        let fixture = try fixture()
        defer { fixture.cleanup() }
        let store = DictionaryStore(root: fixture.root)
        _ = try await store.importDictionary(from: fixture.archive)
        let model = DictionaryCaptureModel(store: store)
        model.setSource("🙂食べなかった。")
        model.lookup(at: 1)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while model.isSearching && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!model.isSearching)
        #expect(model.query == "食べなかった")
        #expect(model.baseForms == ["食べる"])
        #expect(model.selectedRange == NSRange(location: 2, length: 6))
        let rendered = DictionaryDefinitionRenderer().render(model.entries).string
        #expect(rendered.contains("食べなかった → 食べる"))
        #expect(rendered.contains("negative"))
        #expect(!rendered.contains("Incompatible noun"))
        model.clear()
        #expect(model.baseForms.isEmpty)
    }
}
