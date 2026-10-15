import AppKit

@MainActor
private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Selection is restricted to the display where dragging begins.
@MainActor
final class RegionSelector {
    private var panels: [NSPanel] = []
    private var completion: ((CaptureRegion?) -> Void)?
    private var eventMonitor: Any?
    private var displayObserver: NSObjectProtocol?

    func begin(completion: @escaping (CaptureRegion?) -> Void) {
        cancel()
        self.completion = completion
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let panel = SelectionPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.onCancel = { [weak self] in self?.finish(nil) }
            view.onSelection = { [weak self] rect in
                guard rect.width >= 4, rect.height >= 4 else {
                    self?.finish(nil)
                    return
                }
                self?.finish(CaptureRegion(displayID: id.uint32Value, displaySize: screen.frame.size, localRect: rect))
            }
            panel.contentView = view
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        // A nonactivating key panel receives Escape without activating Snipper.
        let mouse = NSEvent.mouseLocation
        let panel = panels.first(where: { $0.frame.contains(mouse) }) ?? panels.first
        panel?.makeKey()
        if let panel { panel.makeFirstResponder(panel.contentView) }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.finish(nil)
                return nil
            }
            // Do not send typing to another app while the selection overlay owns input.
            return nil
        }
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(nil) }
        }
        if panels.isEmpty { finish(nil) }
    }

    func cancel() { finish(nil) }

    private func finish(_ region: CaptureRegion?) {
        let callback = completion
        completion = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        displayObserver = nil
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        callback?(region)
    }
}

@MainActor
private final class SelectionView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var start: CGPoint?
    private var selection: CGRect = .zero

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        start = convert(event.locationInWindow, from: nil)
        selection = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        selection = CaptureRegion.selection(from: start, to: convert(event.locationInWindow, from: nil), in: bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        let rect = CaptureRegion.selection(from: start, to: convert(event.locationInWindow, from: nil), in: bounds)
        self.start = nil
        onSelection?(rect)
    }

    override func rightMouseDown(with event: NSEvent) { onCancel?() }
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        let dim = NSBezierPath(rect: bounds)
        if selection.width > 0 && selection.height > 0 {
            dim.appendRect(selection)
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.24).setFill()
        dim.fill()
        if selection.width > 0 && selection.height > 0 {
            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1
            outline.stroke()
        }
        let message = "Drag to select text · Escape or right-click to cancel"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.65),
        ]
        let size = (message as NSString).size(withAttributes: attributes)
        (message as NSString).draw(at: CGPoint(x: max(12, bounds.midX - size.width / 2), y: bounds.maxY - 90), withAttributes: attributes)
    }
}
