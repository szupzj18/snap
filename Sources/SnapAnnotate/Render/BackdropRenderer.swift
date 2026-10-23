import CoreGraphics

/// Lays a screenshot onto a backdrop. The canvas and export use the same geometry, so the preview
/// matches the file.
public enum BackdropRenderer {
    /// Where the screenshot sits on the canvas, both in pixels.
    public struct Layout: Equatable {
        public let canvasSize: CGSize
        /// The screenshot's rect on the canvas, top-left origin.
        public let contentRect: CGRect
    }

    /// `contentSize` and the result are pixels; `backdrop` lengths are points times `scale`.
    public static func layout(contentSize: CGSize, backdrop: Backdrop, scale: CGFloat) -> Layout {
        let padding = (backdrop.padding * scale).rounded()
        var canvas = CGSize(width: contentSize.width + padding * 2, height: contentSize.height + padding * 2)
        if let ratio = backdrop.aspect.ratio {
            // Grow the short side; never crop the screenshot.
            if canvas.width / canvas.height < ratio {
                canvas.width = (canvas.height * ratio).rounded()
            } else {
                canvas.height = (canvas.width / ratio).rounded()
            }
        }
        let origin = CGPoint(x: ((canvas.width - contentSize.width) / 2).rounded(),
                             y: ((canvas.height - contentSize.height) / 2).rounded())
        return Layout(canvasSize: canvas, contentRect: CGRect(origin: origin, size: contentSize))
    }

    /// The finished image: backdrop, shadow, then the screenshot with rounded corners.
    public static func compose(_ content: CGImage, backdrop: Backdrop, scale: CGFloat) -> CGImage? {
        let layout = layout(contentSize: CGSize(width: content.width, height: content.height), backdrop: backdrop, scale: scale)
        let colorSpace = content.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: Int(layout.canvasSize.width), height: Int(layout.canvasSize.height), bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // Work top-left like the rest of the editor.
        context.translateBy(x: 0, y: layout.canvasSize.height)
        context.scaleBy(x: 1, y: -1)
        draw(content, layout: layout, backdrop: backdrop, scale: scale, in: context)
        return context.makeImage()
    }

    /// Draws into a context whose user space is canvas pixels, top-left origin.
    public static func draw(_ content: CGImage, layout: Layout, backdrop: Backdrop, scale: CGFloat, in context: CGContext) {
        let canvas = CGRect(origin: .zero, size: layout.canvasSize)
        drawFill(backdrop.fill, in: canvas, context: context)
        drawFrame(around: layout.contentRect, backdrop: backdrop, scale: scale, in: context) {
            drawImage(content, in: layout.contentRect, context: context)
        }
    }

    public static func drawFill(_ fill: Backdrop.Fill, in rect: CGRect, context: CGContext) {
        switch fill {
        case let .gradient(top, bottom):
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
            context.saveGState()
            context.clip(to: rect)
            // Top-left to bottom-right.
            context.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
            context.restoreGState()
        case let .solid(color):
            context.setFillColor(color.cgColor)
            context.fill(rect)
        case let .image(image):
            // Cover: scale up until both sides are filled, centered.
            let cover = max(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * cover, height: CGFloat(image.height) * cover)
            let target = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
            context.saveGState()
            context.clip(to: rect)
            drawImage(image, in: target, context: context)
            context.restoreGState()
        case .clear:
            break
        }
    }

    /// Shadow and rounded clip around the screenshot; `drawContent` paints the screenshot itself
    /// (with its annotations, in the editor).
    public static func drawFrame(around rect: CGRect, backdrop: Backdrop, scale: CGFloat, in context: CGContext, drawContent: () -> Void) {
        let radius = min(backdrop.cornerRadius * scale, rect.width / 2, rect.height / 2)
        let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if backdrop.shadow > 0 {
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: 10 * scale * backdrop.shadow),
                              blur: 36 * scale * backdrop.shadow,
                              color: CGColor(gray: 0, alpha: 0.55 * backdrop.shadow))
            context.addPath(shape)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fillPath()
            context.restoreGState()
        }
        context.saveGState()
        context.addPath(shape)
        context.clip()
        drawContent()
        context.restoreGState()
    }

    /// CGContext.draw flips images in a y-down space; flip back around the target rect.
    private static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height))
        context.restoreGState()
    }
}
