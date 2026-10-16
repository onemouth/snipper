import AppKit
import Testing
@testable import Snipper

struct PanelPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let panelSize = CGSize(width: 460, height: 548)

    @Test func usesRightSideWhenRoomExists() {
        let source = CGRect(x: 200, y: 250, width: 300, height: 200)
        let frame = PanelPlacement.frame(size: panelSize, near: source, in: screen)
        #expect(screen.contains(frame))
        #expect(frame.minX == source.maxX + 12)
        #expect(!frame.intersects(source))
    }

    @Test func usesLeftSideNearRightEdge() {
        let source = CGRect(x: 1200, y: 400, width: 200, height: 100)
        let frame = PanelPlacement.frame(size: panelSize, near: source, in: screen)
        #expect(screen.contains(frame))
        #expect(frame.maxX == source.minX - 12)
        #expect(!frame.intersects(source))
    }

    @Test func usesBelowWhenNeitherSideFits() {
        let source = CGRect(x: 100, y: 750, width: 1240, height: 100)
        let frame = PanelPlacement.frame(size: panelSize, near: source, in: screen)
        #expect(screen.contains(frame))
        #expect(frame.maxY == source.minY - 12)
        #expect(!frame.intersects(source))
    }

    @Test func staysOnscreenForLargeSourceAndNegativeDisplayOrigin() {
        let visible = CGRect(x: -1600, y: -700, width: 1200, height: 900)
        let source = visible.insetBy(dx: 10, dy: 10)
        let frame = PanelPlacement.frame(size: panelSize, near: source, in: visible)
        #expect(visible.contains(frame))
    }

    @Test func pinnedFrameIsUnchangedWhenStillOnscreen() {
        let frame = CGRect(x: 30, y: 80, width: 440, height: 488)
        #expect(PanelPlacement.clamped(frame, to: screen) == frame)
    }

    @Test func movesDisconnectedDisplayFrameBackOnscreen() {
        let offscreen = CGRect(x: -1000, y: 1800, width: 440, height: 488)
        #expect(screen.contains(PanelPlacement.clamped(offscreen, to: screen)))
    }

    @Test func shrinksOversizedFrameToVisibleScreen() {
        let small = CGRect(x: 0, y: 0, width: 300, height: 250)
        #expect(PanelPlacement.clamped(CGRect(x: -50, y: -50, width: 440, height: 488), to: small) == small)
    }
}

struct ResultPanelStateTests {
    @Test func startsEmptyWithTranslationCopyUnavailable() {
        let state = ResultPanelState()
        #expect(!state.hasResult)
        #expect(!state.canCopyTranslation)
        #expect(!state.isPinned)
    }

    @Test func translationUpdatesNeverReplaceOriginal() {
        var state = ResultPanelState()
        state.presentOriginal("Original\n日本語")
        state.applyTranslation("翻譯")
        #expect(state.original == "Original\n日本語")
        #expect(state.canCopyTranslation)
        state.applyTranslation(nil)
        #expect(!state.canCopyTranslation)
        #expect(state.original == "Original\n日本語")
    }

    @Test func captureReplacesOriginalAndClearsStaleTranslationWithoutUnpinning() {
        var state = ResultPanelState(original: "Old", translation: "Old translation", isPinned: true)
        #expect(state.canCopyTranslation)
        state.presentOriginal("New original\n日本語")
        #expect(state.original == "New original\n日本語")
        #expect(state.hasResult)
        #expect(state.translation == nil)
        #expect(!state.canCopyTranslation)
        #expect(state.isPinned)
    }
}

@MainActor
struct ClipboardWriterTests {
    @Test func copiesExactPlainTextToIsolatedPasteboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        #expect(ClipboardWriter.write("Original\n日本語", to: pasteboard))
        #expect(pasteboard.string(forType: .string) == "Original\n日本語")
        // macOS also advertises the legacy NSStringPboardType alias.
        #expect(pasteboard.types?.contains(.string) == true)
        #expect(pasteboard.types?.contains(.rtf) != true)
        #expect(pasteboard.types?.contains(.html) != true)
    }

    @Test func unavailableTranslationCannotOverwriteClipboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        #expect(ClipboardWriter.write("sentinel", to: pasteboard))
        let changeCount = pasteboard.changeCount
        #expect(!ClipboardWriter.write(nil, to: pasteboard))
        #expect(!ClipboardWriter.write("", to: pasteboard))
        #expect(pasteboard.string(forType: .string) == "sentinel")
        #expect(pasteboard.changeCount == changeCount)
    }
}
