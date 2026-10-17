import AppKit
import Foundation
import Testing
@testable import Snipper

struct DictionaryLookupTextTests {
    @Test func nonactivatingPanelClicksAreClassifiedByPositionNotEventOwnership() {
        let frame = CGRect(x: -900, y: -400, width: 560, height: 620)
        // First-click/global-monitor events inside the source/definitions/title bar
        // must not close the panel, even when no matching event.window is supplied.
        for point in [CGPoint(x: -800, y: -300), CGPoint(x: -500, y: 100),
                      CGPoint(x: -700, y: 215), CGPoint(x: -337, y: 0)] {
            #expect(!DictionaryPanelHitTest.shouldDismiss(click: point, frame: frame))
        }
        #expect(DictionaryPanelHitTest.shouldDismiss(click: CGPoint(x: 0, y: 0), frame: frame))
        #expect(!DictionaryPanelHitTest.shouldDismiss(click: .zero, frame: nil))
    }

    @Test func clickedCharacterProducesBoundedCandidatesWithoutCrossingPunctuation() {
        let candidates = DictionaryLookupText.candidates(in: "昨日、猫を見た。", characterOffset: 3)
        #expect(candidates.contains(where: { $0.text == "猫" && $0.range == 3..<4 }))
        #expect(candidates.allSatisfy { $0.range.contains(3) })
        #expect(!candidates.contains(where: { $0.text.contains("、") || $0.text.contains("。") || $0.text.contains("昨日") }))
        #expect(candidates.count <= 79)
        #expect(DictionaryLookupText.candidates(in: "猫。", characterOffset: 1).isEmpty)
        #expect(DictionaryLookupText.candidates(in: "猫", characterOffset: -1).isEmpty)
        #expect(DictionaryLookupText.candidates(in: "猫", characterOffset: 10).isEmpty)
        #expect(DictionaryLookupText.candidates(in: "Hello Snipper", characterOffset: 8).first?.text == "Snipper")
        #expect(DictionaryLookupText.candidates(in: String(repeating: "日", count: 100), characterOffset: 50).count <= 79)
    }

    @Test func automaticLookupRecognizesSingleWordsButLeavesSpacedTextForClicking() {
        #expect(DictionaryLookupText.automaticCandidates(in: "猫").first?.text == "猫")
        #expect(DictionaryLookupText.automaticCandidates(in: "test.").first?.text == "test")
        #expect(DictionaryLookupText.automaticCandidates(in: "Hello world").isEmpty)
        #expect(DictionaryLookupText.automaticCandidates(in: "猫\ntest").isEmpty)
        #expect(DictionaryLookupText.automaticCandidates(in: "").isEmpty)
    }

    @Test func repeatedWordsKeepTheClickedOccurrence() {
        let target = DictionaryLookupText.candidates(in: "猫と猫", characterOffset: 2).first { $0.text == "猫" }
        #expect(target?.range == 2..<3)
        #expect(DictionaryLookupText.utf16Range(2..<3, in: "猫と猫") == NSRange(location: 2, length: 1))
    }

    @Test func unicodeOffsetsHandleEmojiAndCombiningCharacters() {
        let text = "🙂か\u{3099}猫"
        #expect(text.count == 3)
        #expect(DictionaryLookupText.characterOffset(atUTF16: 1, in: text) == 0)
        #expect(DictionaryLookupText.characterOffset(atUTF16: 3, in: text) == 1)
        #expect(DictionaryLookupText.characterOffset(atUTF16: 4, in: text) == 2)
        #expect(DictionaryLookupText.utf16Range(2..<3, in: text) == NSRange(location: 4, length: 1))
        #expect(DictionaryLookupText.characterOffset(atUTF16: 99, in: text) == nil)
        #expect(DictionaryLookupText.utf16Range(0..<99, in: text) == nil)
    }

    @Test func candidateSearchFindsWordInSentence() async throws {
        let fixture = try DictionaryFixture(files: DictionaryFixture.files())
        defer { fixture.cleanup() }
        let store = DictionaryStore(root: fixture.root)
        _ = try await store.importDictionary(from: fixture.archive)
        let candidates = DictionaryLookupText.candidates(in: "昨日は猫を見た", characterOffset: 3)
        let match = try await store.searchCandidateMatch(candidates.map(\.text))
        #expect(match?.query == "猫")
        #expect(match?.entries.count == 2)
    }
}

@Suite @MainActor
struct DictionaryCaptureModelTests {
    @Test func singleWordSearchesAutomaticallyAndMultiwordTextCanBeClicked() async throws {
        let fixture = try DictionaryFixture(files: DictionaryFixture.files())
        defer { fixture.cleanup() }
        let store = DictionaryStore(root: fixture.root)
        _ = try await store.importDictionary(from: fixture.archive)
        let model = DictionaryCaptureModel(store: store)
        model.beginRecognizing()
        #expect(model.isRecognizing)
        #expect(model.status.contains("OCR"))
        model.setSource("猫")
        try await waitForSearch(model)
        #expect(!model.isRecognizing)
        #expect(model.entries.count == 2)
        #expect(model.query == "猫")
        #expect(model.selectedRange == NSRange(location: 0, length: 1))
        model.setSource("猫を見る。test")
        #expect(model.entries.isEmpty)
        model.lookup(at: 5)
        try await waitForSearch(model)
        #expect(model.entries.count == 1)
        #expect(model.query == "test")
        #expect(model.selectedRange == NSRange(location: 5, length: 4))
        #expect(model.source == "猫を見る。test")
        model.lookup(at: 0)
        try await waitForSearch(model)
        #expect(model.query == "猫")
        #expect(model.entries.count == 2)
        model.lookup(at: 4)
        #expect(model.entries.isEmpty)
        #expect(model.selectedRange == nil)
    }

    @Test func closingAndReplacingSourceRejectsLateResults() async throws {
        let fixture = try DictionaryFixture(files: DictionaryFixture.files())
        defer { fixture.cleanup() }
        let store = DictionaryStore(root: fixture.root)
        _ = try await store.importDictionary(from: fixture.archive)
        let cat = try #require(await store.searchCandidateMatch(["猫"]))
        let test = try #require(await store.searchCandidateMatch(["test"]))
        let model = DictionaryCaptureModel(store: store) { candidates in
            if candidates.first == "猫" {
                try? await Task.sleep(for: .milliseconds(80)) // Deliberately return after cancellation.
                return cat
            }
            return test
        }
        model.setSource("猫")
        await Task.yield()
        model.setSource("test")
        try await waitForSearch(model)
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.query == "test")
        #expect(model.entries.first?.term.headword == "test")
        model.setSource("猫")
        model.clear()
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.source.isEmpty)
        #expect(model.entries.isEmpty)
        #expect(!model.isSearching)
        #expect(!model.isRecognizing)
        #expect(model.query == nil)
    }

    @Test func noMatchAndRecognitionFailureRetainSafeState() async throws {
        let store = DictionaryStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let model = DictionaryCaptureModel(store: store, search: { _ in nil })
        model.setSource("absent")
        try await waitForSearch(model)
        #expect(model.source == "absent")
        #expect(model.entries.isEmpty)
        #expect(model.status.contains("Click a word"))
        model.lookup(at: 1)
        try await waitForSearch(model)
        #expect(model.status.contains("No dictionary-form match"))
        model.beginRecognizing()
        model.failRecognition("No readable text. Clipboard unchanged.")
        #expect(!model.isRecognizing)
        #expect(model.source.isEmpty)
        #expect(model.entries.isEmpty)
        #expect(model.status.contains("No readable text"))
    }

    private func waitForSearch(_ model: DictionaryCaptureModel) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while model.isSearching && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!model.isSearching)
    }
}

@Suite(.serialized) @MainActor
struct DictionaryCaptureOCRTests {
    @Test func regionOCRCanSearchJapaneseWordInsideSentence() async throws {
        let fixture = try DictionaryFixture(files: DictionaryFixture.files())
        defer { fixture.cleanup() }
        let store = DictionaryStore(root: fixture.root)
        _ = try await store.importDictionary(from: fixture.archive)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 300, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: 1000, height: 300).fill()
        ("猫を見る" as NSString).draw(at: CGPoint(x: 40, y: 180), withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let image = try #require(bitmap.cgImage)
        let text = try await OCRService().recognize(image, languagePreference: "en-US, ja-JP")
        let index = try #require(text.firstIndex(of: "猫"))
        let candidates = DictionaryLookupText.candidates(in: text, characterOffset: text.distance(from: text.startIndex, to: index))
        let match = try await store.searchCandidateMatch(candidates.map(\.text))
        #expect(match?.query == "猫")
        #expect(match?.entries.count == 2)
    }
}
