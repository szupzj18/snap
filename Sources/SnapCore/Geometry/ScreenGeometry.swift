import CoreGraphics

/// Conversions between the coordinate spaces macOS uses for screens.
///
/// - AppKit global space: points, origin at the bottom-left of the primary display, y grows up.
///   `NSScreen.frame`, `NSWindow.frame` and `NSEvent.mouseLocation` live here.
/// - Quartz global space: points, origin at the top-left of the primary display, y grows down.
///   CoreGraphics and ScreenCaptureKit (`SCDisplay.frame`, `SCWindow.frame`) live here.
/// - Image space: pixels, origin at the top-left of a captured image.
///
/// Every display has its own pixels-per-point scale, so pixel values are never shared across displays.
public enum ScreenGeometry {
    /// Converts a rect between AppKit and Quartz global space. The conversion is its own inverse.
    public static func flip(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Converts a point between AppKit and Quartz global space. The conversion is its own inverse.
    public static func flip(_ point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    /// Maps a rect given in a bottom-left-origin point space of size `area` (a screen or view)
    /// to the matching pixel rect of an image of that area captured at `scale`.
    ///
    /// The result is snapped outward to whole pixels and clamped to the image bounds.
    public static func pixelRect(fromBottomLeft rect: CGRect, in area: CGSize, scale: CGFloat) -> CGRect {
        let topLeft = CGRect(x: rect.minX, y: area.height - rect.maxY, width: rect.width, height: rect.height)
        let pixels = CGRect(
            x: topLeft.minX * scale,
            y: topLeft.minY * scale,
            width: topLeft.width * scale,
            height: topLeft.height * scale
        ).integral
        let imageBounds = CGRect(x: 0, y: 0, width: (area.width * scale).rounded(), height: (area.height * scale).rounded())
        return pixels.intersection(imageBounds)
    }
}
