import Combine
import CoreGraphics

/// The annotations and crop of one image, with snapshot-based undo and redo.
public final class AnnotationDocument: ObservableObject {
    public let image: CGImage
    /// Pixels per point of the original capture.
    public let scale: CGFloat

    @Published public private(set) var annotations: [Annotation] = []
    /// The part of the image to keep, in image pixels; nil keeps all of it. Annotations stay in
    /// full-image coordinates, so widening the crop later brings them back.
    @Published public private(set) var crop: CGRect?
    /// The sharing background. A way of presenting the result rather than an edit, so not undoable.
    @Published public var backdrop = Backdrop()
    @Published public private(set) var canUndo = false
    @Published public private(set) var canRedo = false

    private struct Snapshot {
        var annotations: [Annotation]
        var crop: CGRect?
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    public init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
    }

    public var imageSize: CGSize { CGSize(width: image.width, height: image.height) }

    /// What's shown and exported: the crop, or the whole image.
    public var visibleRect: CGRect { crop ?? CGRect(origin: .zero, size: imageSize) }

    public var isEdited: Bool { !annotations.isEmpty || crop != nil || backdrop.isEnabled }

    public func add(_ annotation: Annotation) {
        apply(Snapshot(annotations: annotations + [annotation], crop: crop))
    }

    /// Swaps in a changed version of an existing annotation, keeping its stacking order.
    public func replace(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }),
              annotations[index] != annotation else { return }
        var updated = annotations
        updated[index] = annotation
        apply(Snapshot(annotations: updated, crop: crop))
    }

    public func remove(id: Annotation.ID) {
        guard annotations.contains(where: { $0.id == id }) else { return }
        apply(Snapshot(annotations: annotations.filter { $0.id != id }, crop: crop))
    }

    /// Crops to `rect` (snapped to whole pixels and kept inside the image), or removes the crop.
    public func setCrop(_ rect: CGRect?) {
        let full = CGRect(origin: .zero, size: imageSize)
        var newCrop = rect.map { $0.integral.intersection(full) }
        if let candidate = newCrop, candidate.isEmpty || candidate == full { newCrop = nil }
        guard newCrop != crop else { return }
        apply(Snapshot(annotations: annotations, crop: newCrop))
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
        redoStack.append(current)
        restore(previous)
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(current)
        restore(next)
    }

    private var current: Snapshot { Snapshot(annotations: annotations, crop: crop) }

    private func apply(_ snapshot: Snapshot) {
        undoStack.append(current)
        redoStack.removeAll()
        restore(snapshot)
    }

    private func restore(_ snapshot: Snapshot) {
        if snapshot.annotations != annotations { annotations = snapshot.annotations }
        if snapshot.crop != crop { crop = snapshot.crop }
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}
