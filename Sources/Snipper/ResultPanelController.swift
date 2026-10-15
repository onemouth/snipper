import AppKit

@MainActor
private final class ResultPanel: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onDismiss?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDismiss?() }
        else { super.keyDown(with: event) }
    }
    override func performClose(_ sender: Any?) { onDismiss?() }
}

@MainActor
private final class ResultTextView: NSTextView {
    override var needsPanelToBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { window?.performClose(nil) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { window?.performClose(nil) }
        else { super.keyDown(with: event) }
    }
}

@MainActor
final class ResultPanelController: NSObject, NSWindowDelegate {
    private(set) var state = ResultPanelState()
    private var panel: ResultPanel?
    private var originalView: NSTextView?
    private var translationView: NSTextView?
    private var translationCopyButton: NSButton?
    private var pinButton: NSButton?
    private var feedback: NSTextField?
    private var restoreAfterCapture = false
    private var displayObserver: NSObjectProtocol?

    var hasResult: Bool { state.hasResult }

    /// Hide even a pinned panel so recapturing its area cannot OCR our own text.
    func suspendForCapture() {
        restoreAfterCapture = panel?.isVisible == true
        panel?.orderOut(nil)
    }

    func restoreAfterCancelledOrFailedCapture() {
        guard restoreAfterCapture else { return }
        restoreAfterCapture = false
        showLastResult()
    }

    func present(_ result: CaptureResult, copiedAutomatically: Bool) {
        ensurePanel()
        guard let panel else { return }
        state.presentOriginal(result.text)
        originalView?.string = state.original
        originalView?.scrollToBeginningOfDocument(nil)
        translationView?.string = "Translation will be available in Step 4.\nNo text has been sent to a provider."
        translationView?.scrollToBeginningOfDocument(nil)
        translationCopyButton?.isEnabled = state.canCopyTranslation
        feedback?.stringValue = copiedAutomatically ? "Original text copied automatically." : "Original text recognized. Copy to try again."
        if !state.isPinned {
            position(near: result.region)
        } else {
            keepOnscreen()
        }
        restoreAfterCapture = false
        // Do not call activate(), makeKey(), or makeKeyAndOrderFront().
        panel.orderFrontRegardless()
    }

    func showLastResult() {
        guard state.hasResult else { return }
        keepOnscreen()
        panel?.orderFrontRegardless()
    }

    func stop() {
        hide()
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        displayObserver = nil
        originalView?.string = ""
        translationView?.string = ""
        state = ResultPanelState()
    }

    @objc private func hide() {
        restoreAfterCapture = false
        panel?.orderOut(nil)
    }

    @objc private func copyOriginal() {
        feedback?.stringValue = ClipboardWriter.write(state.original) ? "Original text copied." : "Could not copy original text. Try again."
    }

    @objc private func copyTranslation() {
        guard state.canCopyTranslation else { return }
        feedback?.stringValue = ClipboardWriter.write(state.translation) ? "Translation copied." : "Could not copy translation. Try again."
    }

    @objc private func togglePin() {
        state.isPinned.toggle()
        pinButton?.state = state.isPinned ? .on : .off
        pinButton?.title = state.isPinned ? "Position pinned" : "Pin position"
        feedback?.stringValue = state.isPinned ? "New captures will keep this panel position." : "New captures will place the panel near the selection."
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = ResultPanel(
            contentRect: CGRect(x: 0, y: 0, width: 440, height: 460),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = "Snipper"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentMinSize = CGSize(width: 360, height: 360)
        panel.delegate = self
        panel.onDismiss = { [weak self] in self?.hide() }
        panel.contentView = makeContent()
        self.panel = panel
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepOnscreen() }
        }
    }

    private func makeContent() -> NSView {
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 440, height: 460))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
        ])

        let originalCopy = button("Copy Original", action: #selector(copyOriginal))
        let translatedCopy = button("Copy Translation", action: #selector(copyTranslation))
        translatedCopy.isEnabled = false
        translatedCopy.toolTip = "Available once a translation exists (Step 4)."
        translationCopyButton = translatedCopy

        let originalScroll = textArea(label: "Original text")
        let translatedScroll = textArea(label: "Translated text")
        originalView = originalScroll.documentView as? NSTextView
        translationView = translatedScroll.documentView as? NSTextView
        let pin = button("Pin position", action: #selector(togglePin))
        pin.setButtonType(.pushOnPushOff)
        pin.toolTip = "Keep this panel's position for subsequent captures. You can still drag it."
        pinButton = pin
        let hint = NSTextField(labelWithString: "Click text, then Esc to close")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        let footer = row([pin, NSView(), hint])
        let feedback = NSTextField(labelWithString: "")
        feedback.font = .systemFont(ofSize: 12)
        feedback.textColor = .secondaryLabelColor
        feedback.lineBreakMode = .byTruncatingTail
        self.feedback = feedback

        let views: [NSView] = [
            row([heading("Original"), NSView(), originalCopy]),
            originalScroll,
            row([heading("Translation"), NSView(), translatedCopy]),
            translatedScroll,
            footer,
            feedback,
        ]
        for view in views {
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        originalScroll.heightAnchor.constraint(equalTo: translatedScroll.heightAnchor).isActive = true
        originalScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        return root
    }

    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    private func textArea(label: String) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        let text = ResultTextView(frame: CGRect(x: 0, y: 0, width: 400, height: 120))
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        text.textContainerInset = CGSize(width: 8, height: 8)
        text.font = .systemFont(ofSize: 14)
        text.backgroundColor = .textBackgroundColor
        text.setAccessibilityLabel(label)
        scroll.documentView = text
        return scroll
    }

    private func position(near region: CaptureRegion) {
        guard let panel else { return }
        let sourceScreen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == region.displayID
        }
        guard let screen = sourceScreen ?? NSScreen.main else { return }
        let source = region.localRect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        panel.setFrame(PanelPlacement.frame(size: panel.frame.size, near: source, in: screen.visibleFrame), display: true)
    }

    private func keepOnscreen() {
        guard let panel, !NSScreen.screens.isEmpty else { return }
        // Nearest display also works after the display containing the panel disconnects.
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let screen = NSScreen.screens.min {
            distance(center, to: $0.visibleFrame) < distance(center, to: $1.visibleFrame)
        }!
        panel.setFrame(PanelPlacement.clamped(panel.frame, to: screen.visibleFrame), display: true)
    }

    private func distance(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
