import AppKit
import ImageIO
import SwiftUI

struct DictionaryResultsPopover: View {
    let entries: [DictionarySearchEntry]
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Dictionary lookup", systemImage: "book.closed")
                    .font(.headline)
                Spacer()
                Text("Exact match").font(.caption).foregroundStyle(.secondary)
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close dictionary results")
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Divider()
            DictionaryResultsText(entries: entries)
            Divider()
            Text("\(entries.count) entries · Select text to copy · Escape to close")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }
        .frame(width: 520, height: 480)
        .onExitCommand(perform: dismiss)
    }
}

private struct DictionaryResultsText: NSViewRepresentable {
    let entries: [DictionarySearchEntry]

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 380))
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.isRichText = true
        text.importsGraphics = false
        text.isAutomaticLinkDetectionEnabled = false
        text.isHorizontallyResizable = false
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.textContainerInset = NSSize(width: 16, height: 14)
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.lineFragmentPadding = 0
        text.textContainer?.containerSize = NSSize(width: 480, height: CGFloat.greatestFiniteMagnitude)
        text.setAccessibilityLabel("Dictionary definitions")
        scroll.documentView = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let ids = entries.map(\.id)
        guard context.coordinator.ids != ids, let text = scroll.documentView as? NSTextView else { return }
        context.coordinator.ids = ids
        text.textStorage?.setAttributedString(DictionaryDefinitionRenderer().render(entries))
        text.scrollToBeginningOfDocument(nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var ids: [UUID] = [] }
}

// Native attributed-text rendering, inspired by dictionary-popup conventions.
// No HTML interpreter, JavaScript, remote resource loading, or dictionary CSS.
@MainActor
final class DictionaryDefinitionRenderer {
    private let output = NSMutableAttributedString(string: "")
    private var nodes = 0
    private var images = 0
    private var imageCache: [URL: NSImage] = [:]
    private var resources = URL(fileURLWithPath: "/")
    private var truncated = false
    private let font = NSFont.systemFont(ofSize: 16)

    func render(_ entries: [DictionarySearchEntry]) -> NSAttributedString {
        for (index, entry) in entries.prefix(100).enumerated() {
            if output.length >= 100_000 { truncated = true; break }
            resources = entry.resources
            if index > 0 { append("\n────────────────────────────\n\n", color: .separatorColor) }
            if entry.term.reading != entry.term.headword {
                append(entry.term.reading + "\n", font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
            }
            append(entry.term.headword + "\n", font: .systemFont(ofSize: 27, weight: .semibold), color: .controlAccentColor)
            append(" " + entry.dictionary.title + " ", font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor,
                   background: .quaternaryLabelColor)
            append("\n\n")
            guard entry.term.definitionsJSON.utf8.count <= 512_000,
                  let definitions = try? JSONSerialization.jsonObject(with: Data(entry.term.definitionsJSON.utf8)) as? [Any] else {
                append("Definition is too large or cannot be displayed.\n", color: .secondaryLabelColor)
                continue
            }
            for (number, definition) in definitions.enumerated() {
                if definitions.count > 1 { append("\(number + 1). ", color: .secondaryLabelColor) }
                glossary(definition)
                append("\n")
            }
        }
        if truncated { append("\n[Preview shortened for display.]", color: .secondaryLabelColor, force: true) }
        return output
    }

    private func append(_ text: String, font customFont: NSFont? = nil, color: NSColor = .labelColor,
                        background: NSColor? = nil, force: Bool = false) {
        guard force || output.length < 100_000 else { truncated = true; return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        var attributes: [NSAttributedString.Key: Any] = [.font: customFont ?? font, .foregroundColor: color, .paragraphStyle: paragraph]
        if let background { attributes[.backgroundColor] = background }
        let remaining = force ? 100 : max(0, 100_000 - output.length)
        let bounded = String(decoding: text.utf16.prefix(remaining), as: UTF16.self)
        if text.utf16.count > remaining { truncated = true }
        output.append(NSAttributedString(string: bounded, attributes: attributes))
    }

    private func glossary(_ value: Any) {
        if let text = value as? String { append(text); return }
        guard let object = value as? [String: Any] else { return }
        switch object["type"] as? String {
        case "text": if let text = object["text"] as? String { append(text) }
        case "image": image(object, defaultHeight: 96)
        case "structured-content": if let content = object["content"] { node(content, depth: 0) }
        default: append("[Unsupported definition]", color: .secondaryLabelColor)
        }
    }

    private func node(_ value: Any, depth: Int) {
        nodes += 1
        guard depth < 64, nodes <= 10_000, output.length < 100_000 else { truncated = true; return }
        if let text = value as? String { append(text); return }
        if let array = value as? [Any] {
            for child in array {
                guard nodes < 10_000, output.length < 100_000 else { truncated = true; break }
                node(child, depth: depth + 1)
            }
            return
        }
        guard let object = value as? [String: Any], let tag = object["tag"] as? String else { return }
        if tag == "img" { image(object, defaultHeight: 18); return }
        if tag == "br" { append("\n"); return }
        if tag == "li" { append("\n• ") }
        if ["div", "tr", "table", "details"].contains(tag), !output.string.hasSuffix("\n") { append("\n") }
        if tag == "rt" { append("(") }
        let start = output.length
        if let content = object["content"] { node(content, depth: depth + 1) }
        if let style = object["style"] as? [String: Any], style["fontWeight"] as? String == "bold", output.length > start {
            output.addAttribute(.font, value: NSFont.systemFont(ofSize: 16, weight: .semibold), range: NSRange(location: start, length: output.length - start))
        }
        if tag == "rt" { append(")") }
        if ["td", "th"].contains(tag) { append("\t") }
        // Links are rendered as text only. No dictionary URL is opened or fetched.
    }

    private func image(_ object: [String: Any], defaultHeight: CGFloat) {
        guard images < 64 else { truncated = true; return }
        images += 1
        guard let path = object["path"] as? String,
              let safe = try? DictionaryFormat.safePath(path),
              DictionaryFormat.imageExtensions.contains((safe as NSString).pathExtension.lowercased()) else {
            append("[Image unavailable]", color: .secondaryLabelColor); return
        }
        let root = resources.resolvingSymlinksInPath().standardizedFileURL
        let url = resources.appendingPathComponent(safe).resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(root.path + "/"), let image = loadImage(url) else {
            append((object["alt"] as? String) ?? "[Image unavailable]", color: .secondaryLabelColor); return
        }
        let units: CGFloat = object["sizeUnits"] as? String == "em" ? 16 : 1
        let requestedHeight = (object["height"] as? NSNumber).map { CGFloat($0.doubleValue) * units } ?? defaultHeight
        let height = requestedHeight.isFinite ? min(180, max(12, requestedHeight)) : defaultHeight
        let ratio = image.size.width / max(1, image.size.height)
        let requestedWidth = (object["width"] as? NSNumber).map { CGFloat($0.doubleValue) * units } ?? height * ratio
        let width = requestedWidth.isFinite ? min(420, max(8, requestedWidth)) : height
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -3, width: width, height: height)
        output.append(NSAttributedString(attachment: attachment))
    }

    private func loadImage(_ url: URL) -> NSImage? {
        if let cached = imageCache[url] { return cached }
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true, let size = values.fileSize, size <= 8_000_000,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0,
              width.doubleValue * height.doubleValue <= 16_000_000,
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        imageCache[url] = image
        return image
    }
}
