import AppKit
import ImageIO
import SwiftUI

struct DictionaryResultsPopover: View {
    let entries: [DictionarySearchEntry]
    var query: String? = nil
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Dictionary lookup", systemImage: "book.closed")
                    .font(.headline)
                Spacer()
                Text(entries.contains { $0.inflection != nil } ? "Japanese base forms" : "Exact match")
                    .font(.caption).foregroundStyle(.secondary)
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close dictionary results")
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
            if let query {
                HStack(alignment: .firstTextBaseline) {
                    Text("Lookup:").foregroundStyle(.secondary)
                    Text(query).fontWeight(.semibold).textSelection(.enabled)
                    Spacer()
                }
                .font(.callout)
                .padding(.horizontal, 14).padding(.bottom, 10)
            }
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

@MainActor
private final class DictionaryDefinitionTextView: NSTextView {
    override var needsPanelToBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) {
        if window is NSPanel { window?.performClose(sender) }
        else { super.cancelOperation(sender) }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelOperation(nil) }
        else { super.keyDown(with: event) }
    }
}

struct DictionaryResultsText: NSViewRepresentable {
    let entries: [DictionarySearchEntry]

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let text = DictionaryDefinitionTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 380))
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
    private var indent: CGFloat = 0
    private var hanging: CGFloat = 0
    private var lists: [(ordered: Bool, next: Int)] = []

    func render(_ entries: [DictionarySearchEntry]) -> NSAttributedString {
        // A renderer can be reused without retaining previous results or budgets.
        output.setAttributedString(NSAttributedString(string: ""))
        nodes = 0; images = 0; truncated = false
        lists.removeAll()
        imageCache.removeAll()
        for (index, group) in DictionaryResultLayout.groups(entries).enumerated() {
            if output.length >= 100_000 { truncated = true; break }
            indent = 0; hanging = 0
            if index > 0 { append("\n────────────────────────\n", font: .systemFont(ofSize: 11), color: .separatorColor) }
            let headword = group.headword.isEmpty ? group.reading : group.headword
            if group.reading != headword {
                append(group.reading + "\n", font: .systemFont(ofSize: 14), color: .secondaryLabelColor)
            }
            append(headword + "\n", font: .systemFont(ofSize: 28, weight: .semibold))
            var inflections = Set<DictionaryInflection>()
            for entry in group.sources.flatMap(\.entries) {
                if let inflection = entry.inflection, inflections.insert(inflection).inserted {
                    append("\(inflection.source) → \(inflection.base)", font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
                    if !inflection.reasons.isEmpty {
                        append(" · " + inflection.reasons.joined(separator: " → "), font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
                    }
                    append("\n")
                }
            }
            for source in group.sources {
                if output.length >= 100_000 { truncated = true; break }
                indent = 0; hanging = 0
                append(" " + source.dictionary.title + " ", font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor,
                       background: .controlAccentColor.withAlphaComponent(0.10))
                append("\n")
                let sections: [(DictionarySearchEntry, [Any]?)] = source.entries.map { entry in
                    let definitions = entry.term.definitionsJSON.utf8.count <= 512_000
                        ? (try? JSONSerialization.jsonObject(with: Data(entry.term.definitionsJSON.utf8))) as? [Any] : nil
                    return (entry, definitions)
                }
                let numbered = sections.reduce(0) { $0 + ($1.1?.count ?? 1) } > 1
                var number = 0
                for (entry, definitions) in sections {
                    resources = entry.resources
                    guard let definitions else {
                        append("Definition is too large or cannot be displayed.\n", color: .secondaryLabelColor)
                        continue
                    }
                    for (definitionIndex, definition) in definitions.enumerated() {
                        guard output.length < 100_000 else { truncated = true; break }
                        number += 1
                        indent = 4; hanging = numbered ? 24 : 0
                        if numbered { append("\(number).\t", font: .systemFont(ofSize: 13, weight: .medium), color: .secondaryLabelColor) }
                        if definitionIndex == 0 {
                            for tag in entry.term.definitionTags.prefix(12) {
                                append(" " + String(tag.prefix(32)) + " ", font: .systemFont(ofSize: 11),
                                       color: .secondaryLabelColor, background: .quaternaryLabelColor)
                                append(" ")
                            }
                        }
                        glossary(definition)
                        if !output.string.hasSuffix("\n") { append("\n") }
                    }
                }
            }
        }
        if truncated { append("\n[Preview shortened for display.]", color: .secondaryLabelColor, force: true) }
        return NSAttributedString(attributedString: output)
    }

    private func append(_ text: String, font customFont: NSFont? = nil, color: NSColor = .labelColor,
                        background: NSColor? = nil, force: Bool = false) {
        guard force || output.length < 100_000 else { truncated = true; return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 6
        paragraph.firstLineHeadIndent = indent
        paragraph.headIndent = indent + hanging
        paragraph.defaultTabInterval = 120
        if hanging > 0 { paragraph.tabStops = [NSTextTab(textAlignment: .left, location: indent + hanging)] }
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
        if tag == "ul" || tag == "ol" {
            if !output.string.hasSuffix("\n") { append("\n") }
            let oldIndent = indent, oldHanging = hanging
            indent += max(16, hanging); hanging = 20
            lists.append((ordered: tag == "ol", next: 1))
            if let content = object["content"] { node(content, depth: depth + 1) }
            lists.removeLast()
            indent = oldIndent; hanging = oldHanging
            return
        }
        if tag == "li" {
            if !output.string.hasSuffix("\n") { append("\n") }
            if let list = lists.last, list.ordered {
                append("\(list.next).\t", color: .secondaryLabelColor)
                lists[lists.count - 1].next += 1
            } else { append("•\t", color: .secondaryLabelColor) }
        }
        let block = ["div", "tr", "table", "details", "p", "blockquote"].contains(tag)
        if block, !output.string.hasSuffix("\n"), !output.string.hasSuffix("\t") { append("\n") }
        if tag == "rt" { append("(") }
        let start = output.length
        if let content = object["content"] { node(content, depth: depth + 1) }
        if output.length > start {
            let range = NSRange(location: start, length: output.length - start)
            let style = object["style"] as? [String: Any]
            if ["b", "strong", "th"].contains(tag) || style?["fontWeight"] as? String == "bold" {
                output.enumerateAttribute(.font, in: range) { value, run, _ in
                    if let font = value as? NSFont {
                        output.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask), range: run)
                    }
                }
            }
            if ["i", "em"].contains(tag) || style?["fontStyle"] as? String == "italic" {
                output.enumerateAttribute(.font, in: range) { value, run, _ in
                    if let font = value as? NSFont {
                        output.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask), range: run)
                    }
                }
            }
            if tag == "small" || style?["fontSize"] as? String == "0.8em" {
                output.addAttributes([.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor], range: range)
            }
            if tag == "u" { output.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
        }
        if tag == "rt" { append(")") }
        if ["td", "th"].contains(tag) { append("\t") }
        if (block || tag == "li"), !output.string.hasSuffix("\n") { append("\n") }
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
