import AppKit
import SwiftUI

@main
@MainActor
enum SnipperApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let shortcutTester = ShortcutTester()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: "Snipper")
            button.toolTip = "Snipper — OCR + Translation"
        }
        let menu = NSMenu()
        let title = NSMenuItem(title: "Snipper — Foundation", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        let capture = NSMenuItem(title: "Capture Region (coming next)", action: nil, keyEquivalent: "")
        capture.isEnabled = false
        menu.addItem(capture)
        menu.addItem(.separator())
        let preferences = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Snipper", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
        shortcutTester.start(settings: settings)
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 530),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Snipper Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings, shortcutTester: shortcutTester))
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        shortcutTester.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
