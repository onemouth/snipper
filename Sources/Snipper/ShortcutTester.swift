import AppKit
import Carbon
import Combine

/// Foundation smoke test only: receives global shortcuts without capturing content.
@MainActor
final class ShortcutTester: ObservableObject {
    @Published private(set) var registrationStatus = "Shortcuts not registered."
    @Published private(set) var lastReceived = "No shortcut received yet."
    @Published private(set) var isRegistered = false

    private static let signature: OSType = 0x534E4950 // SNIP
    private var handler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []
    private var subscription: AnyCancellable?
    private var toast: NSPanel?
    private var dismissal: Task<Void, Never>?
    private var receivedCount = 0

    func start(settings: AppSettings) {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == 0x534E4950 else {
                return OSStatus(eventNotHandledErr)
            }
            // The application event target dispatches on the main thread.
            return MainActor.assumeIsolated {
                let tester = Unmanaged<ShortcutTester>.fromOpaque(context).takeUnretainedValue()
                tester.receive(identifier.id)
                return noErr
            }
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else {
            registrationStatus = "Could not install shortcut handler (\(status))."
            return
        }
        register(settings)
        subscription = settings.$captureShortcut.combineLatest(settings.$recaptureShortcut)
            .dropFirst()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self, weak settings] _ in
                MainActor.assumeIsolated {
                    guard let settings else { return }
                    self?.register(settings)
                }
            }
    }

    func register(_ settings: AppSettings) {
        unregister()
        guard handler != nil else { return }
        if let warning = settings.shortcutWarning {
            registrationStatus = "Shortcuts disabled: \(warning)"
            return
        }
        for (index, shortcut) in [settings.captureShortcut, settings.recaptureShortcut].enumerated() {
            guard let keyCode = Self.keyCodes[shortcut.key],
                  let modifiers = ShortcutModifiers(rawValue: shortcut.modifiers) else {
                registrationStatus = "Shortcuts disabled: unsupported key."
                unregister()
                return
            }
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(keyCode, Self.carbonModifiers(modifiers), EventHotKeyID(signature: Self.signature, id: UInt32(index + 1)), GetApplicationEventTarget(), 0, &reference)
            guard status == noErr, let reference else {
                unregister()
                let action = index == 0 ? "Capture" : "Recapture"
                registrationStatus = status == eventHotKeyExistsErr
                    ? "\(action) shortcut is already in use. Change it or quit the other app, then Retry. Both shortcuts are disabled."
                    : "\(action) shortcut registration failed (\(status)). Both shortcuts are disabled."
                return
            }
            hotKeys.append(reference)
        }
        isRegistered = true
        registrationStatus = "Both shortcuts enabled — test mode (no capture)."
    }

    func stop() {
        subscription?.cancel()
        subscription = nil
        unregister()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        dismissal?.cancel()
        toast?.orderOut(nil)
    }

    private func unregister() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        isRegistered = false
    }

    private func receive(_ id: UInt32) {
        guard isRegistered, id == 1 || id == 2 else { return }
        receivedCount += 1
        let message = id == 1 ? "Capture shortcut received" : "Recapture shortcut received"
        lastReceived = "\(message) · test #\(receivedCount)"
        showToast(message)
    }

    private func showToast(_ message: String) {
        dismissal?.cancel()
        if toast == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 88), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let background = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
            background.material = .hudWindow
            background.state = .active
            background.wantsLayer = true
            background.layer?.cornerRadius = 14
            background.layer?.masksToBounds = true
            let label = NSTextField(wrappingLabelWithString: "")
            label.identifier = NSUserInterfaceItemIdentifier("message")
            label.alignment = .center
            label.font = .systemFont(ofSize: 15, weight: .medium)
            label.frame = NSRect(x: 12, y: 14, width: 336, height: 60)
            background.addSubview(label)
            panel.contentView = background
            toast = panel
        }
        guard let toast else { return }
        if let label = toast.contentView?.subviews.first as? NSTextField {
            label.stringValue = "✓ \(message)\nTest only — no screenshot taken"
        }
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            toast.setFrameOrigin(NSPoint(x: frame.midX - toast.frame.width / 2, y: frame.maxY - toast.frame.height - 28))
        }
        toast.orderFrontRegardless()
        dismissal = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            self?.toast?.orderOut(nil)
        }
    }

    private static func carbonModifiers(_ modifiers: ShortcutModifiers) -> UInt32 {
        switch modifiers {
        case .commandShift: UInt32(cmdKey | shiftKey)
        case .controlOption: UInt32(controlKey | optionKey)
        case .commandOption: UInt32(cmdKey | optionKey)
        }
    }

    // Physical ANSI key positions; digits match the MVP's default shortcuts.
    private static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32,
        "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    ]
}
