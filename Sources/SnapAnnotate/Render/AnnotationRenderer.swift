import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Draws an image with its annotations. The editor canvas and PNG export both go through
/// `draw(_:in:)`, so what you see is what you export.
///
/// The context's user space must be image pixels with a top-left origin (y grows down).
public final class AnnotationRenderer {
    private let base: CGImage
    private let scale: CGFloat
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private lazy var ciBase = CIImage(cgImage: base).clampedToExtent()
    private var effectCache: [EffectKey: CGImage] = [:]

    private struct EffectKey: Hashable {
        let isBlur: Bool
        let rect: CGRect
    }

    /// `scale` is the capture's pixels per point; effect strengths are tuned in points.
    public init(base: CGImage, scale: CGFloat) {
        self.base = base
        self.scale = scale
    }

    public var imageSize: CGSize { CGSize(width: base.width, height: base.height) }

    public func draw(_ annotations: [Annotation], in context: CGContext) {
        drawImage(base, in: CGRect(origin: .zero, size: imageSize), context: context)
        for annotation in annotations {
            draw(annotation, in: context)
        }
    }

    /// The flattened result at full resolution.
    public func export(_ annotations: [Annotation]) -> CGImage? {
        let colorSpace = base.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.translateBy(x: 0, y: CGFloat(base.height))
        context.scaleBy(x: 1, y: -1)
        draw(annotations, in: context)
        return context.makeImage()
    }

    public func draw(_ annotation: Annotation, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        let color = annotation.color.cgColor
        let width = annotation.lineWidth

        switch annotation.shape {
        case let .arrow(from, to):
            drawArrow(from: from, to: to, width: width, color: color, in: context)

        case let .rectangle(rect):
            context.setStrokeColor(color)
            context.setLineWidth(width)
            context.setLineJoin(.round)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: width, cornerHeight: width, transform: nil))
            context.strokePath()

        case let .highlight(rect):
            context.setBlendMode(.multiply)
            context.setFillColor(annotation.color.withAlpha(0.45).cgColor)
            context.fill(rect)

        case let .pixelate(rect):
            if let image = effect(isBlur: false, rect: rect) {
                drawImage(image, in: rect.integral, context: context)
            }

        case let .blur(rect):
            if let image = effect(isBlur: true, rect: rect) {
                drawImage(image, in: rect.integral, context: context)
            }

        case let .text(origin, string, fontSize):
            let attributed = Self.attributedText(string, fontSize: fontSize, color: annotation.color)
            withAppKitContext(context) {
                attributed.draw(at: origin)
            }

        case let .counter(center, number, radius):
            let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.setShadow(offset: .zero, blur: radius * 0.3, color: CGColor(gray: 0, alpha: 0.35))
            context.setFillColor(color)
            context.fillEllipse(in: circle)
            context.setShadow(offset: .zero, blur: 0, color: nil)
            let label = NSAttributedString(string: "\(number)", attributes: [
                .font: NSFont.systemFont(ofSize: radius * 1.15, weight: .bold),
                .foregroundColor: annotation.color == .white ? NSColor.black : NSColor.white,
            ])
            let size = label.size()
            withAppKitContext(context) {
                label.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
            }
        }
    }

    /// Text attributes shared with the editor's live text field.
    public static func attributedText(_ string: String, fontSize: CGFloat, color: RGBA) -> NSAttributedString {
        let shadow = NSShadow()
        shadow.shadowBlurRadius = fontSize * 0.12
        shadow.shadowColor = NSColor.black.withAlphaComponent(color == .black ? 0 : 0.35)
        return NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor(cgColor: color.cgColor) ?? .red,
            .shadow: shadow,
        ])
    }

    // MARK: - Pieces

    private func drawArrow(from: CGPoint, to: CGPoint, width: CGFloat, color: CGColor, in context: CGContext) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 0 else { return }
        let headLength = min(max(width * 4, 10), length)
        let headHalfWidth = headLength * 0.5
        let unit = CGPoint(x: dx / length, y: dy / length)
        let base = CGPoint(x: to.x - unit.x * headLength, y: to.y - unit.y * headLength)
        let normal = CGPoint(x: -unit.y, y: unit.x)

        context.setShadow(offset: .zero, blur: width, color: CGColor(gray: 0, alpha: 0.3))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.move(to: from)
        // Stop the shaft inside the head so its round cap doesn't poke out of the tip.
        context.addLine(to: CGPoint(x: base.x + unit.x * headLength * 0.3, y: base.y + unit.y * headLength * 0.3))
        context.strokePath()
        context.move(to: to)
        context.addLine(to: CGPoint(x: base.x + normal.x * headHalfWidth, y: base.y + normal.y * headHalfWidth))
        context.addLine(to: CGPoint(x: base.x - normal.x * headHalfWidth, y: base.y - normal.y * headHalfWidth))
        context.closePath()
        context.fillPath()
        context.endTransparencyLayer()
    }

    /// Pixelated or blurred copy of the base image under `rect`. Only the original pixels are
    /// used, so stacking annotations never leaks through.
    private func effect(isBlur: Bool, rect: CGRect) -> CGImage? {
        let rect = rect.integral.intersection(CGRect(origin: .zero, size: imageSize))
        guard !rect.isEmpty else { return nil }
        let key = EffectKey(isBlur: isBlur, rect: rect)
        if let cached = effectCache[key] { return cached }

        // Core Image is y-up.
        let ciRect = CGRect(x: rect.minX, y: imageSize.height - rect.maxY, width: rect.width, height: rect.height)
        let output: CIImage?
        if isBlur {
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = ciBase
            filter.radius = Float(10 * scale)
            output = filter.outputImage
        } else {
            let filter = CIFilter.pixellate()
            filter.inputImage = ciBase
            filter.scale = Float(max(8 * scale, min(rect.width, rect.height) / 12))
            filter.center = CGPoint(x: ciRect.minX, y: ciRect.minY)
            output = filter.outputImage
        }
        guard let output,
              let image = ciContext.createCGImage(output, from: ciRect, format: .RGBA8, colorSpace: base.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB))
        else { return nil }

        if effectCache.count > 32 { effectCache.removeAll() }
        effectCache[key] = image
        return image
    }

    /// CGContext.draw puts images upside down in a y-down space; flip locally around the rect.
    private func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height))
        context.restoreGState()
    }

    private func withAppKitContext(_ context: CGContext, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }
}
