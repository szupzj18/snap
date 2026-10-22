import AppKit
import Combine

/// Shows the image fitted into the view and turns mouse input into annotations.
final class EditorCanvasView: NSView, NSTextFieldDelegate {
    private let document: AnnotationDocument
    private let state: EditorState
    private let renderer: AnnotationRenderer
    private var draft: Annotation?
    private var dragStart: CGPoint?
    private var textField: NSTextField?
    /// Where the text being typed starts (image pixels) and how it looks, fixed when typing begins.
    private var textOrigin: CGPoint = .zero
    private var textColor: RGBA = .red
    private var textFontSize: CGFloat = 0
    private var observations: Set<AnyCancellable> = []

    // Select tool.
    private var selectedID: Annotation.ID?
    /// The annotation being dragged and where the drag started (image pixels).
    private var moving: (original: Annotation, start: CGPoint)?
    /// Where the dragged annotation is now; written to the document on mouse up (one undo step).
    private var movePreview: Annotation?
    /// Set while the toolbar is updated to match a newly selected annotation.
    private var isSyncingToolbar = false

    init(document: AnnotationDocument, state: EditorState) {
        self.document = document
        self.state = state
        renderer = AnnotationRenderer(base: document.image, scale: document.scale)
        super.init(frame: .zero)
        document.$annotations
            .sink { [weak self] _ in self?.needsDisplay = true }
            .store(in: &observations)
        state.$tool
            .sink { [weak self] tool in
                guard let self else { return }
                self.commitText()
                if tool != .select { self.deselect() }
                self.window?.invalidateCursorRects(for: self)
            }
            .store(in: &observations)
        // Published values arrive before they're stored, so use the value passed in.
        state.$color
            .sink { [weak self] color in self?.updateSelection { $0.color = color } }
            .store(in: &observations)
        state.$size
            .sink { [weak self] size in
                guard let self else { return }
                self.updateSelection { $0 = $0.resized(to: size, scale: self.document.scale) }
            }
            .store(in: &observations)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // MARK: Geometry

    /// The image's rect in view coordinates: fitted with a margin, never larger than its point size.
    private var imageRect: CGRect {
        let pointSize = CGSize(width: renderer.imageSize.width / document.scale, height: renderer.imageSize.height / document.scale)
        let available = bounds.insetBy(dx: 24, dy: 24)
        let fit = min(1, available.width / pointSize.width, available.height / pointSize.height)
        let size = CGSize(width: pointSize.width * fit, height: pointSize.height * fit)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height).integral
    }

    /// View points per image pixel.
    private var viewScale: CGFloat { imageRect.width / renderer.imageSize.width }

    private func imagePoint(_ viewPoint: CGPoint) -> CGPoint {
        let rect = imageRect
        let x = (viewPoint.x - rect.minX) / viewScale
        let y = (viewPoint.y - rect.minY) / viewScale
        return CGPoint(x: min(max(x, 0), renderer.imageSize.width), y: min(max(y, 0), renderer.imageSize.height))
    }

    private func viewPoint(_ imagePoint: CGPoint) -> CGPoint {
        CGPoint(x: imageRect.minX + imagePoint.x * viewScale, y: imageRect.minY + imagePoint.y * viewScale)
    }

    override func setFrameSize(_ newSize: NSSize) {
        // The text field is positioned for the old size.
        if newSize != frame.size { commitText() }
        super.setFrameSize(newSize)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = imageRect
        context.saveGState()
        context.clip(to: rect)
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: viewScale, y: viewScale)
        context.interpolationQuality = .high
        var annotations = document.annotations
        if let movePreview, let index = annotations.firstIndex(where: { $0.id == movePreview.id }) {
            annotations[index] = movePreview
        }
        renderer.draw(annotations + [draft].compactMap { $0 }, in: context)
        context.restoreGState()

        if let selected = movePreview ?? selectedAnnotation {
            drawSelection(around: selected)
        }
    }

    private func drawSelection(around annotation: Annotation) {
        let box = annotation.bounds
        let origin = viewPoint(box.origin)
        let rect = CGRect(x: origin.x, y: origin.y, width: box.width * viewScale, height: box.height * viewScale)
            .insetBy(dx: -4, dy: -4)
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        path.lineWidth = 1.5
        NSColor.white.withAlphaComponent(0.9).setStroke()
        path.stroke()
        path.setLineDash([4, 3], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }

    override func resetCursorRects() {
        let cursor: NSCursor = switch state.tool {
        case .select: .arrow
        case .text: .iBeam
        default: .crosshair
        }
        addCursorRect(imageRect, cursor: cursor)
    }

    // MARK: Selection

    private var selectedAnnotation: Annotation? {
        selectedID.flatMap { id in document.annotations.first { $0.id == id } }
    }

    private func select(_ annotation: Annotation?) {
        selectedID = annotation?.id
        if let annotation, state.tool.usesColor, annotation.shape.usesColor {
            isSyncingToolbar = true
            state.color = annotation.color
            isSyncingToolbar = false
        }
        needsDisplay = true
    }

    private func deselect() {
        guard selectedID != nil else { return }
        selectedID = nil
        moving = nil
        movePreview = nil
        needsDisplay = true
    }

    private func updateSelection(_ change: (inout Annotation) -> Void) {
        guard !isSyncingToolbar, var annotation = selectedAnnotation else { return }
        change(&annotation)
        document.replace(annotation)
    }

    private func deleteSelection() {
        guard let selectedID else { return }
        document.remove(id: selectedID)
        deselect()
    }

    @objc func delete(_ sender: Any?) {
        deleteSelection()
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)
        let point = imagePoint(location)
        let scale = document.scale

        switch state.tool {
        case .select:
            // A few screen points of slack, whatever the zoom.
            let hit = document.annotation(at: point, tolerance: 6 / viewScale)
            select(hit)
            moving = hit.map { ($0, point) }
        case .text:
            if textField != nil {
                commitText()
            } else if imageRect.contains(location) {
                beginText(at: point)
            }
        case .counter:
            guard imageRect.contains(location) else { return }
            document.add(Annotation(
                shape: .counter(center: point, number: document.nextCounterNumber, radius: state.size.counterRadius * scale),
                color: state.color,
                lineWidth: 0
            ))
        default:
            dragStart = point
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = imagePoint(convert(event.locationInWindow, from: nil))
        if let moving {
            movePreview = moving.original.moved(by: CGVector(dx: point.x - moving.start.x, dy: point.y - moving.start.y))
            needsDisplay = true
            return
        }
        guard let start = dragStart else { return }
        let rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
        let shape: AnnotationShape
        switch state.tool {
        case .arrow: shape = .arrow(from: start, to: point)
        case .rectangle: shape = .rectangle(rect)
        case .highlight: shape = .highlight(rect)
        case .pixelate: shape = .pixelate(rect)
        case .blur: shape = .blur(rect)
        case .select, .text, .counter: return
        }
        draft = Annotation(id: draft?.id ?? UUID(), shape: shape, color: state.color, lineWidth: state.size.lineWidth * document.scale)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if moving != nil {
            if let movePreview { document.replace(movePreview) }
            moving = nil
            movePreview = nil
            needsDisplay = true
            return
        }
        defer {
            draft = nil
            dragStart = nil
            needsDisplay = true
        }
        guard let draft, Self.isBigEnough(draft.shape) else { return }
        document.add(draft)
    }

    /// Ignore accidental clicks that would leave a speck.
    private static func isBigEnough(_ shape: AnnotationShape) -> Bool {
        switch shape {
        case let .arrow(from, to): hypot(to.x - from.x, to.y - from.y) > 6
        case let .rectangle(rect), let .highlight(rect), let .pixelate(rect), let .blur(rect): rect.width > 3 && rect.height > 3
        case .text, .counter: true
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        if modifiers.isEmpty, selectedID != nil {
            switch event.keyCode {
            case 51, 117: // Delete, Forward Delete
                deleteSelection()
                return
            case 53: // Esc
                deselect()
                return
            default:
                break
            }
        }
        if modifiers.isEmpty, let character = event.charactersIgnoringModifiers?.lowercased().first,
           let tool = AnnotationTool.allCases.first(where: { $0.key == character }) {
            state.tool = tool
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: Text

    private func beginText(at point: CGPoint) {
        textOrigin = point
        textColor = state.color
        textFontSize = state.size.fontSize * document.scale
        let field = NSTextField(string: "")
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.delegate = self
        let fontSize = textFontSize * viewScale
        field.font = .systemFont(ofSize: fontSize, weight: .bold)
        field.textColor = NSColor(cgColor: textColor.cgColor)
        field.placeholderString = "Text"
        let origin = viewPoint(point)
        field.frame = CGRect(x: origin.x - 2, y: origin.y, width: max(fontSize * 4, 60), height: ceil(fontSize * 1.3))
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = textField else { return }
        let width = field.attributedStringValue.size().width + 16
        field.frame.size.width = max(width, field.font.map { $0.pointSize * 4 } ?? 60)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(insertNewline(_:)):
            commitText()
            return true
        case #selector(cancelOperation(_:)):
            cancelText()
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        commitText()
    }

    private func commitText() {
        guard let field = textField else { return }
        textField = nil
        let string = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        guard !string.isEmpty else { return }
        document.add(Annotation(
            shape: .text(origin: textOrigin, string: string, fontSize: textFontSize),
            color: textColor,
            lineWidth: 0
        ))
    }

    private func cancelText() {
        textField?.removeFromSuperview()
        textField = nil
        window?.makeFirstResponder(self)
    }
}
