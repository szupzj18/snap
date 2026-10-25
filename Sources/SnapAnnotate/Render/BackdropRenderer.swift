import CoreGraphics

/// Lays a screenshot onto a backdrop. The canvas and export use the same geometry, so the preview
/// matches the file.
public enum BackdropRenderer {
    /// Where the screenshot sits on the canvas, both in pixels.
    public struct Layout: Equatable {
        public let canvasSize: CGSize
        /// The screenshot plus the frame's bar above it, top-left origin. The same as
        /// `contentRect` without a frame.
        public let frameRect: CGRect
        /// The screenshot's rect on the canvas, top-left origin.
        public let contentRect: CGRect
    }

    /// `contentSize` and the result are pixels; `backdrop` lengths are points times `scale`.
    public static func layout(contentSize: CGSize, backdrop: Backdrop, scale: CGFloat) -> Layout {
        let padding = (backdrop.padding * scale).rounded()
        let bar = (backdrop.frame.barHeight * scale).rounded()
        let framed = CGSize(width: contentSize.width, height: contentSize.height + bar)
        var canvas = CGSize(width: framed.width + padding * 2, height: framed.height + padding * 2)
        if let ratio = backdrop.aspect.ratio {
            // Grow the short side; never crop the screenshot.
            if canvas.width / canvas.height < ratio {
                canvas.width = (canvas.height * ratio).rounded()
            } else {
                canvas.height = (canvas.width / ratio).rounded()
            }
        }
        let origin = CGPoint(x: ((canvas.width - framed.width) / 2).rounded(),
                             y: ((canvas.height - framed.height) / 2).rounded())
        return Layout(canvasSize: canvas, frameRect: CGRect(origin: origin, size: framed),
                      contentRect: CGRect(origin: CGPoint(x: origin.x, y: origin.y + bar), size: contentSize))
    }

    /// The finished image: backdrop, shadow, frame, then the screenshot with rounded corners.
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
        drawFrame(layout: layout, backdrop: backdrop, scale: scale, in: context) {
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

    /// Shadow, rounded clip and window bar around the screenshot; `drawContent` paints the
    /// screenshot itself (with its annotations, in the editor), clipped to `contentRect`.
    public static func drawFrame(layout: Layout, backdrop: Backdrop, scale: CGFloat, in context: CGContext, drawContent: () -> Void) {
        let rect = layout.frameRect
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
        if backdrop.frame != .none {
            let bar = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: layout.contentRect.minY - rect.minY)
            drawBar(backdrop.frame, dark: backdrop.darkFrame, in: bar, scale: scale, context: context)
        }
        context.clip(to: layout.contentRect)
        drawContent()
        context.restoreGState()
    }

    /// A Mac title bar: traffic lights, and for a browser an empty address field.
    private static func drawBar(_ frame: Backdrop.Frame, dark: Bool, in rect: CGRect, scale: CGFloat, context: CGContext) {
        context.setFillColor((dark ? RGBA(0.2, 0.2, 0.2) : RGBA(0.93, 0.93, 0.93)).cgColor)
        context.fill(rect)
        context.setFillColor(RGBA(0, 0, 0, dark ? 0.5 : 0.12).cgColor)
        context.fill(CGRect(x: rect.minX, y: rect.maxY - scale, width: rect.width, height: scale))

        let lights = [RGBA(1, 0.37, 0.34), RGBA(1, 0.74, 0.18), RGBA(0.16, 0.78, 0.25)]
        let diameter = 12 * scale
        for (index, color) in lights.enumerated() {
            let center = CGPoint(x: rect.minX + (20 + 20 * CGFloat(index)) * scale, y: rect.midY)
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
        }

        guard frame == .browser else { return }
        // Centered, clear of the traffic lights on both sides.
        let width = min(rect.width - 2 * 84 * scale, 480 * scale)
        guard width > 40 * scale else { return }
        let height = 24 * scale
        let field = CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
        context.addPath(CGPath(roundedRect: field, cornerWidth: 7 * scale, cornerHeight: 7 * scale, transform: nil))
        context.setFillColor(RGBA(1, 1, 1, dark ? 0.1 : 1).cgColor)
        context.fillPath()
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
