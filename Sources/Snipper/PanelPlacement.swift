import CoreGraphics

/// Pure geometry in AppKit's global, bottom-left screen coordinates.
enum PanelPlacement {
    static func clamped(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let size = CGSize(width: min(frame.width, visibleFrame.width), height: min(frame.height, visibleFrame.height))
        return CGRect(
            x: min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - size.height),
            width: size.width, height: size.height
        )
    }

    static func frame(size: CGSize, near source: CGRect, in visibleFrame: CGRect) -> CGRect {
        let gap: CGFloat = 12
        let candidates = [
            CGRect(x: source.maxX + gap, y: source.maxY - size.height, width: size.width, height: size.height),
            CGRect(x: source.minX - gap - size.width, y: source.maxY - size.height, width: size.width, height: size.height),
            CGRect(x: source.minX, y: source.minY - gap - size.height, width: size.width, height: size.height),
            CGRect(x: source.minX, y: source.maxY + gap, width: size.width, height: size.height),
        ].map { clamped($0, to: visibleFrame) }
        let protectedSource = source.insetBy(dx: -gap / 2, dy: -gap / 2)
        if let clear = candidates.first(where: { !$0.intersects(protectedSource) }) { return clear }
        // If no side has room, minimize source occlusion while keeping the panel onscreen.
        return candidates.min { overlap($0, source) < overlap($1, source) }!
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
