import AppKit
import Testing
@testable import Snipper

struct CaptureRegionTests {
    @Test func convertsPrimaryDisplayCoordinates() {
        let region = CaptureRegion(displayID: 1, displaySize: CGSize(width: 1440, height: 900), localRect: CGRect(x: 100, y: 200, width: 300, height: 80))
        #expect(region.quartzRect(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), primaryMaxY: 900) == CGRect(x: 100, y: 620, width: 300, height: 80))
    }

    @Test func convertsDisplayLeftAndAbovePrimary() {
        let region = CaptureRegion(displayID: 2, displaySize: CGSize(width: 1000, height: 800), localRect: CGRect(x: 40, y: 50, width: 300, height: 100))
        #expect(region.quartzRect(screenFrame: CGRect(x: -1000, y: 900, width: 1000, height: 800), primaryMaxY: 900) == CGRect(x: -960, y: -150, width: 300, height: 100))
    }

    @Test func convertsDisplayBelowPrimary() {
        let region = CaptureRegion(displayID: 2, displaySize: CGSize(width: 1000, height: 800), localRect: CGRect(x: 40, y: 50, width: 300, height: 100))
        #expect(region.quartzRect(screenFrame: CGRect(x: 0, y: -800, width: 1000, height: 800), primaryMaxY: 900) == CGRect(x: 40, y: 1550, width: 300, height: 100))
    }

    @Test func clipsReverseDragToStartingDisplay() {
        let rect = CaptureRegion.selection(from: CGPoint(x: 300, y: 200), to: CGPoint(x: -10, y: -20), in: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(rect == CGRect(x: 0, y: 0, width: 300, height: 200))
    }

    @Test func rejectsChangedResolutionAndInvalidRegions() {
        let size = CGSize(width: 800, height: 600)
        let region = CaptureRegion(displayID: 1, displaySize: size, localRect: CGRect(x: 20, y: 20, width: 100, height: 50))
        #expect(region.isValid(on: size))
        #expect(!region.isValid(on: CGSize(width: 1600, height: 1200)))
        #expect(!CaptureRegion(displayID: 1, displaySize: size, localRect: CGRect(x: 790, y: 20, width: 100, height: 50)).isValid(on: size))
        #expect(!CaptureRegion(displayID: 1, displaySize: size, localRect: CGRect(x: 0, y: 0, width: 2, height: 2)).isValid(on: size))
    }
}

@Suite(.serialized)
struct OCRServiceTests {
    @Test func languagePreferencesAreTrimmedAndDeduplicated() {
        #expect(OCRService.parseLanguages(" en-US, ja-JP, en-US, , \n") == ["en-US", "ja-JP"])
        #expect(OCRService.parseLanguages("").isEmpty)
    }

    @Test func preservesUsefulLineBreaks() {
        #expect(OCRService.joinLines([" Hello world ", "", "日本語のテスト", " \n"]) == "Hello world\n日本語のテスト")
    }

    @Test @MainActor func recognizesGeneratedEnglishAndJapanese() async throws {
        let image = try makeImage(lines: ["Hello Snipper", "日本語のテスト"])
        let text = try await OCRService().recognize(image, languagePreference: "en-US, ja-JP")
        #expect(text.contains("Hello Snipper"))
        #expect(text.contains("日本語のテスト"))
        #expect(text.contains("\n"))
    }

    @Test @MainActor func blankImageProducesNoTextError() async throws {
        let image = try makeImage(lines: [])
        do {
            _ = try await OCRService().recognize(image, languagePreference: "en-US")
            Issue.record("Expected no-text error")
        } catch OCRError.noText {
            // Empty OCR must not result in a clipboard write.
        }
    }

    @Test @MainActor func unsupportedLanguageProducesConfigurationError() async throws {
        let image = try makeImage(lines: ["Hello"])
        do {
            _ = try await OCRService().recognize(image, languagePreference: "not-a-language")
            Issue.record("Expected unsupported-language error")
        } catch OCRError.unsupportedLanguages(let codes) {
            #expect(codes == ["not-a-language"])
        }
    }

    @MainActor
    private func makeImage(lines: [String]) throws -> CGImage {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 300, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1000, height: 300).fill()
        for (index, line) in lines.enumerated() {
            (line as NSString).draw(at: CGPoint(x: 40, y: 210 - index * 90), withAttributes: [
                .font: NSFont.systemFont(ofSize: 48),
                .foregroundColor: NSColor.black,
            ])
        }
        context.flushGraphics()
        return try #require(bitmap.cgImage)
    }
}
