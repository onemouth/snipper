import AppKit

struct ResultPanelState {
    private(set) var original = ""
    private(set) var translation: String?
    var isPinned = false

    var hasResult: Bool { !original.isEmpty }
    var canCopyTranslation: Bool { translation.map { !$0.isEmpty } ?? false }

    mutating func presentOriginal(_ text: String) {
        original = text
        // Never let a new capture display an old translation.
        translation = nil
    }
}

@MainActor
enum ClipboardWriter {
    /// Empty/unavailable content must not clear the user's existing clipboard.
    static func write(_ text: String?, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let text, !text.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
