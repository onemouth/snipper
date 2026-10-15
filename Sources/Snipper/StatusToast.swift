import AppKit

@MainActor
final class StatusToast {
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?

    func show(_ title: String, detail: String = "") {
        hide()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let label = panel.contentView?.subviews.first as? NSTextField {
            label.stringValue = detail.isEmpty ? title : "\(title)\n\(detail)"
        }
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - panel.frame.height - 28))
        }
        panel.orderFrontRegardless()
        dismissal = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.hide()
        }
    }

    func hide() {
        dismissal?.cancel()
        dismissal = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        let label = NSTextField(wrappingLabelWithString: "")
        label.alignment = .center
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.frame = NSRect(x: 14, y: 12, width: 372, height: 76)
        background.addSubview(label)
        panel.contentView = background
        return panel
    }
}
