import CoreGraphics
import Foundation

/// Last selection is kept only in memory, relative to its physical display.
struct CaptureRegion: Equatable, Sendable {
    let displayID: CGDirectDisplayID
    let displaySize: CGSize
    let localRect: CGRect

    func isValid(on size: CGSize) -> Bool {
        displaySize == size && localRect.width >= 4 && localRect.height >= 4
            && CGRect(origin: .zero, size: size).contains(localRect)
    }

    /// AppKit uses bottom-left coordinates; screen capture uses top-left display space.
    func quartzRect(screenFrame: CGRect, primaryMaxY: CGFloat) -> CGRect {
        let global = localRect.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
        return CGRect(x: global.minX, y: primaryMaxY - global.maxY, width: global.width, height: global.height)
    }

    static func selection(from start: CGPoint, to end: CGPoint, in bounds: CGRect) -> CGRect {
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(start.x - end.x), height: abs(start.y - end.y))
        return rect.intersection(bounds)
    }
}
