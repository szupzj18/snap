import Combine
import CoreGraphics

public enum AnnotationTool: String, CaseIterable, Identifiable {
    case select, crop, arrow, rectangle, ellipse, line, pen, text, highlight, pixelate, blur, spotlight, counter

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .select: "Select"
        case .crop: "Crop"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .line: "Line"
        case .pen: "Pen"
        case .spotlight: "Spotlight"
        case .text: "Text"
        case .highlight: "Highlight"
        case .pixelate: "Pixelate"
        case .blur: "Blur"
        case .counter: "Counter"
        }
    }

    var systemImage: String {
        switch self {
        case .select: "cursorarrow"
        case .crop: "crop"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .line: "line.diagonal"
        case .pen: "scribble"
        case .spotlight: "light.max"
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
        case .select: "v"
        case .crop: "c"
        case .arrow: "a"
        case .rectangle: "r"
        case .ellipse: "o"
        case .line: "l"
        case .pen: "d"
        case .spotlight: "s"
        case .text: "t"
        case .highlight: "h"
        case .pixelate: "p"
        case .blur: "b"
        case .counter: "n"
        }
    }

    /// Pixelate, blur, spotlight and crop ignore the color.
    var usesColor: Bool { ![.pixelate, .blur, .spotlight, .crop].contains(self) }

    /// Tools that share one toolbar button with a menu, to keep the toolbar narrow.
    static let groups: [[AnnotationTool]] = [[.rectangle, .ellipse, .line], [.pixelate, .blur]]

    /// The toolbar, in order; a group shows as one button.
    static let toolbar: [[AnnotationTool]] = [
        [.select], [.crop], [.arrow], groups[0], [.pen], [.text], [.highlight], groups[1], [.spotlight], [.counter],
    ]
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
    public var lineWidth: CGFloat { [.small: 3, .medium: 5, .large: 9][self]! }
    public var fontSize: CGFloat { [.small: 16, .medium: 24, .large: 36][self]! }
    public var counterRadius: CGFloat { [.small: 11, .medium: 15, .large: 21][self]! }
}

/// The editor's current tool settings.
final class EditorState: ObservableObject {
    @Published var tool: AnnotationTool = .arrow {
        didSet {
            if let index = AnnotationTool.groups.firstIndex(where: { $0.contains(tool) }) {
                lastInGroup[index] = tool
            }
        }
    }
    @Published var color: RGBA = .red
    @Published var size: AnnotationSize = .medium
    /// View points per image point; nil fits the image in the window.
    @Published var zoom: CGFloat?
    /// The zoom actually shown (the fit value when `zoom` is nil), for the toolbar.
    @Published var displayedZoom: CGFloat = 1
    /// What each grouped toolbar button shows: the tool last used from that group.
    @Published private(set) var lastInGroup: [Int: AnnotationTool] = [:]

    func shownTool(for group: [AnnotationTool]) -> AnnotationTool {
        guard let index = AnnotationTool.groups.firstIndex(of: group) else { return group[0] }
        return lastInGroup[index] ?? group[0]
    }
}
