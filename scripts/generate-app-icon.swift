import AppKit

// Original pixel-art concept C. Generate the transparent 1024px source and a
// complete macOS iconset; iconutil packages it into Resources/AppIcon.icns.
// Run from the repository root: swift scripts/generate-app-icon.swift
let output = URL(fileURLWithPath: "Resources", isDirectory: true)
let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

func color(_ hex: Int) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}

func render(size: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill(using: .copy)
    // 360-unit artwork with optical margin for the native macOS icon silhouette.
    let scale = CGFloat(size) / 432
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let offset = NSAffineTransform()
    offset.translateX(by: 36, yBy: 42)
    offset.concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 360, height: 360), xRadius: 80, yRadius: 80)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.shadowBlurRadius = 12 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -6 * scale)
    shadow.set()
    color(0x1E203C).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0x34325F), ending: color(0x1E203C))!.draw(in: tile, angle: -90)

    func pixel(_ column: Int, _ row: Int, _ width: Int = 1, _ height: Int = 1, _ hex: Int = 0x70E6D4) {
        // Align each edge to a device pixel, keeping small sizes crisp.
        func align(_ value: CGFloat) -> CGFloat { ((value + 36) * scale).rounded() / scale - 36 }
        let x = CGFloat(60 + column * 15), y = CGFloat(60 + row * 15)
        let minX = align(x), minY = align(y)
        let maxX = align(x + CGFloat(width * 15)), maxY = align(y + CGFloat(height * 15))
        color(hex).setFill()
        NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).fill()
    }
    // Capture brackets, a cream text glyph, and a warm amber accent.
    pixel(1, 12, 1, 3); pixel(2, 14, 3, 1)
    pixel(11, 14, 3, 1); pixel(14, 12, 1, 3)
    pixel(1, 1, 1, 3); pixel(2, 1, 3, 1)
    pixel(11, 1, 3, 1); pixel(14, 1, 1, 3)
    pixel(5, 10, 6, 2, 0xF8F6EB); pixel(7, 5, 2, 5, 0xF8F6EB)
    pixel(10, 4, 2, 1, 0xFFCF85); pixel(5, 4, 2, 1, 0xF8F6EB)
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for multiplier in [1, 2] {
        let suffix = multiplier == 2 ? "@2x" : ""
        let png = try render(size: points * multiplier)
        try png.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
        if points == 512 && multiplier == 2 {
            try png.write(to: output.appendingPathComponent("AppIcon.png"))
        }
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Generated Resources/AppIcon.png and Resources/AppIcon.icns")
