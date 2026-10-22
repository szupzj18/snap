import CoreGraphics

/// Adds a macOS-style drop shadow around a window capture.
///
/// ScreenCaptureKit sizes single-window captures to the window itself, which clips its own
/// shadow, so we capture without it and draw one here on a transparent margin.
public enum WindowShadow {
    /// Margins in points around the window, leaving room for the blur and the downward offset.
    public static let margins = (top: CGFloat(28), sides: CGFloat(36), bottom: CGFloat(44))

    public static func apply(to image: CGImage, scale: CGFloat) -> CGImage? {
        let top = Int((margins.top * scale).rounded())
        let sides = Int((margins.sides * scale).rounded())
        let bottom = Int((margins.bottom * scale).rounded())
        let width = image.width + sides * 2
        let height = image.height + top + bottom
        let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // CoreGraphics is y-up: a negative y offset pushes the shadow down.
        context.setShadow(
            offset: CGSize(width: 0, height: -12 * scale),
            blur: 30 * scale,
            color: CGColor(gray: 0, alpha: 0.5)
        )
        context.draw(image, in: CGRect(x: sides, y: bottom, width: image.width, height: image.height))
        return context.makeImage()
    }
}
