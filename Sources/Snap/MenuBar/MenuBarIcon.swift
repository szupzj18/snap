import AppKit

/// The menu bar glyph: the small-size cut of the Snap symbol (design/icon/snap-symbol-small.svg),
/// drawn as a template image so macOS tints it for light and dark menu bars.
enum MenuBarIcon {
    /// Symbol geometry on the 256-unit design grid, top-left origin.
    private static let block: [CGPoint] = [
        CGPoint(x: 36, y: 56), CGPoint(x: 180, y: 56), CGPoint(x: 180, y: 94), CGPoint(x: 146, y: 94),
        CGPoint(x: 146, y: 138), CGPoint(x: 102, y: 138), CGPoint(x: 102, y: 172), CGPoint(x: 36, y: 172),
    ]
    private static let crosshair: [CGRect] = [
        CGRect(x: 122, y: 158, width: 40, height: 28),
        CGRect(x: 198, y: 158, width: 40, height: 28),
        CGRect(x: 166, y: 114, width: 28, height: 40),
        CGRect(x: 166, y: 190, width: 28, height: 40),
    ]
    /// Bounds of the drawing on the grid.
    private static let bounds = CGRect(x: 36, y: 56, width: 202, height: 174)

    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: CGSize(width: size, height: size), flipped: true) { rect in
            let scale = (rect.width - 2) / bounds.width
            let transform = NSAffineTransform()
            transform.translateX(by: (rect.width - bounds.width * scale) / 2,
                                 yBy: (rect.height - bounds.height * scale) / 2)
            transform.scale(by: scale)
            transform.translateX(by: -bounds.minX, yBy: -bounds.minY)

            let path = NSBezierPath()
            path.move(to: block[0])
            block.dropFirst().forEach { path.line(to: $0) }
            path.close()
            crosshair.forEach { path.appendRect($0) }
            path.transform(using: transform as AffineTransform)
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Snap"
        return image
    }
}
