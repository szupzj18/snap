import Combine
import CoreGraphics

/// The annotations on one image, with snapshot-based undo and redo.
public final class AnnotationDocument: ObservableObject {
    public let image: CGImage
    /// Pixels per point of the original capture.
    public let scale: CGFloat

    @Published public private(set) var annotations: [Annotation] = []
    @Published public private(set) var canUndo = false
    @Published public private(set) var canRedo = false

    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    public init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
    }

    public var imageSize: CGSize { CGSize(width: image.width, height: image.height) }

    public var isEdited: Bool { !annotations.isEmpty }

    public func add(_ annotation: Annotation) {
        apply(annotations + [annotation])
    }

    /// Numbers continue from the highest counter, so undoing one frees its number.
    public var nextCounterNumber: Int {
        let numbers = annotations.compactMap { annotation -> Int? in
            if case let .counter(_, number, _) = annotation.shape { return number }
            return nil
        }
        return (numbers.max() ?? 0) + 1
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        updateFlags()
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        updateFlags()
    }

    private func apply(_ newAnnotations: [Annotation]) {
        undoStack.append(annotations)
        redoStack.removeAll()
        annotations = newAnnotations
        updateFlags()
    }

    private func updateFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}
