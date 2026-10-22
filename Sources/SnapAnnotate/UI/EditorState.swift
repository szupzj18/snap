import Combine
import CoreGraphics

public enum AnnotationTool: String, CaseIterable, Identifiable {
    case arrow, rectangle, text, highlight, pixelate, blur, counter

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .text: "Text"
        case .highlight: "Highlight"
        case .pixelate: "Pixelate"
        case .blur: "Blur"
        case .counter: "Counter"
        }
    }

    var systemImage: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .text: "t.square"
        case .highlight: "highlighter"
        case .pixelate: "squareshape.split.3x3"
        case .blur: "drop.halffull"
        case .counter: "1.circle"
        }
    }

    /// Single-key shortcut while the canvas has focus.
    var key: Character {
        switch self {
        case .arrow: "a"
        case .rectangle: "r"
        case .text: "t"
        case .highlight: "h"
        case .pixelate: "p"
        case .blur: "b"
        case .counter: "n"
        }
    }

    /// Pixelate and blur ignore the color.
    var usesColor: Bool { self != .pixelate && self != .blur }
}

public enum AnnotationSize: String, CaseIterable, Identifiable {
    case small, medium, large

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        }
    }

    // All in points; multiplied by the capture scale to get pixels.
    var lineWidth: CGFloat { [.small: 3, .medium: 5, .large: 9][self]! }
    var fontSize: CGFloat { [.small: 16, .medium: 24, .large: 36][self]! }
    var counterRadius: CGFloat { [.small: 11, .medium: 15, .large: 21][self]! }
}

/// The editor's current tool settings.
final class EditorState: ObservableObject {
    @Published var tool: AnnotationTool = .arrow
    @Published var color: RGBA = .red
    @Published var size: AnnotationSize = .medium
}
