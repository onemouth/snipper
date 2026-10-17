import AppKit
import SwiftUI

enum DictionaryPanelHitTest {
    static func shouldDismiss(click: CGPoint, frame: CGRect?) -> Bool {
        guard let frame else { return false }
        // Include the resize handles just outside the native window frame.
        return !frame.insetBy(dx: -6, dy: -6).contains(click)
    }
}

@MainActor
private final class DictionaryCaptureWindow: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
    override func performClose(_ sender: Any?) { onDismiss?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDismiss?() }
        else { super.keyDown(with: event) }
    }
}

@MainActor
final class DictionaryCapturePanel {
    var onDismiss: (() -> Void)?
    private var panel: DictionaryCaptureWindow?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var displayObserver: NSObjectProtocol?

    private func dismiss() {
        hide()
        onDismiss?()
    }

    private func dismissIfOutside(at point: CGPoint) {
        if DictionaryPanelHitTest.shouldDismiss(click: point, frame: panel?.frame) { dismiss() }
    }

    func show(model: DictionaryCaptureModel, near source: CGRect, on screen: NSScreen) {
        hide()
        let frame = PanelPlacement.frame(size: CGSize(width: 560, height: 620), near: source, in: screen.visibleFrame)
        let window = DictionaryCaptureWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "Snipper — Dictionary"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentMinSize = NSSize(width: 420, height: 380)
        window.onDismiss = { [weak self] in self?.dismiss() }
        window.contentView = NSHostingView(rootView: DictionaryCaptureView(model: model))
        // Include the title bar when clamping to the actual display.
        window.setFrame(PanelPlacement.clamped(window.frame, to: screen.visibleFrame), display: false)
        panel = window
        window.orderFrontRegardless()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                // A nonactivating panel's first click can be reported without
                // our window identity. Test screen position, not event ownership.
                let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
                self?.dismissIfOutside(at: point)
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissIfOutside(at: NSEvent.mouseLocation) }
        }
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        localMonitor = nil
        globalMonitor = nil
        displayObserver = nil
    }
}

private struct DictionaryCaptureView: View {
    @ObservedObject var model: DictionaryCaptureModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("OCR → Dictionary", systemImage: "book.closed").font(.headline)
                Spacer()
                if model.isRecognizing || model.isSearching { ProgressView().controlSize(.small) }
            }
            Text("OCR text · Click a word to look it up")
                .font(.caption).foregroundStyle(.secondary)
            DictionarySourceText(model: model)
                .frame(height: 110)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 1).allowsHitTesting(false))
            if let query = model.query {
                HStack(alignment: .firstTextBaseline) {
                    Text("Lookup:").foregroundStyle(.secondary)
                    Text(query).fontWeight(.semibold).textSelection(.enabled)
                }
            }
            Text(model.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Divider()
            if model.isRecognizing {
                VStack { Spacer(); ProgressView("Recognizing selected text locally…"); Spacer() }
                    .frame(maxWidth: .infinity)
            } else {
                DictionaryResultsText(entries: model.entries).frame(maxHeight: .infinity)
            }
            Divider()
            Text("Local only · No automatic copying or translation · No deinflection yet")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
    }
}

@MainActor
private final class DictionarySourceTextView: NSTextView {
    var onWordClick: ((Int) -> Void)?
    override var needsPanelToBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { window?.performClose(sender) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelOperation(nil) }
        else { super.keyDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // A drag is ordinary text selection/copying; a click requests lookup.
        guard selectedRange().length == 0, let layoutManager, let textContainer else { return }
        var point = convert(event.locationInWindow, from: nil)
        point.x -= textContainerOrigin.x
        point.y -= textContainerOrigin.y
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
        guard glyph < layoutManager.numberOfGlyphs else { return }
        let bounds = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard bounds.insetBy(dx: -2, dy: -2).contains(point) else { return }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        if let offset = DictionaryLookupText.characterOffset(atUTF16: index, in: string) { onWordClick?(offset) }
    }
}

private struct DictionarySourceText: NSViewRepresentable {
    @ObservedObject var model: DictionaryCaptureModel

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let text = DictionarySourceTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 110))
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainerInset = NSSize(width: 10, height: 8)
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 500, height: CGFloat.greatestFiniteMagnitude)
        text.font = .systemFont(ofSize: 18)
        text.textColor = .labelColor
        text.backgroundColor = .textBackgroundColor
        text.setAccessibilityLabel("Recognized original text. Click a word for dictionary lookup.")
        scroll.documentView = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? DictionarySourceTextView else { return }
        text.onWordClick = { [weak model] in model?.lookup(at: $0) }
        if text.string != model.source {
            text.string = model.source
            text.scrollToBeginningOfDocument(nil)
        }
        if context.coordinator.selectedRange != model.selectedRange {
            context.coordinator.selectedRange = model.selectedRange
            if let range = model.selectedRange {
                text.setSelectedRange(range)
                text.scrollRangeToVisible(range)
            } else {
                text.setSelectedRange(NSRange(location: 0, length: 0))
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var selectedRange: NSRange? }
}
