import CoreGraphics
import Foundation

/// A color stored as plain components so the model stays value-typed and comparable.
public struct RGBA: Equatable, Hashable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat

    public init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    public func withAlpha(_ alpha: CGFloat) -> RGBA { RGBA(red, green, blue, alpha) }

    public static let red = RGBA(1, 0.23, 0.19)
    public static let orange = RGBA(1, 0.58, 0)
    public static let yellow = RGBA(1, 0.84, 0.04)
    public static let green = RGBA(0.2, 0.78, 0.35)
    public static let blue = RGBA(0, 0.48, 1)
    public static let purple = RGBA(0.69, 0.32, 0.87)
    public static let black = RGBA(0, 0, 0)
    public static let white = RGBA(1, 1, 1)
    public static let palette: [RGBA] = [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]
}

/// Geometry of an annotation, in image pixels with a top-left origin.
public enum AnnotationShape: Equatable {
    case arrow(from: CGPoint, to: CGPoint)
    case rectangle(CGRect)
    case highlight(CGRect)
    case pixelate(CGRect)
    case blur(CGRect)
    /// `origin` is the top-left corner of the text.
    case text(origin: CGPoint, string: String, fontSize: CGFloat)
    case counter(center: CGPoint, number: Int, radius: CGFloat)
}

extension AnnotationShape {
    /// Pixelate and blur don't use a color.
    var usesColor: Bool {
        switch self {
        case .pixelate, .blur: false
        default: true
        }
    }
}

public struct Annotation: Identifiable, Equatable {
    public let id: UUID
    public var shape: AnnotationShape
    public var color: RGBA
    /// Stroke width in image pixels.
    public var lineWidth: CGFloat

    public init(id: UUID = UUID(), shape: AnnotationShape, color: RGBA, lineWidth: CGFloat) {
        self.id = id
        self.shape = shape
        self.color = color
        self.lineWidth = lineWidth
    }
}
