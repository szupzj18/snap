import AppKit
import Combine
import SnapCore

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

    /// The crop being dragged out, before it's committed on mouse up.
    private var cropDraft: CGRect?
    /// The pen stroke so far.
    private var penPoints: [CGPoint] = []
    /// How far a zoomed-in canvas is scrolled from centered, in view points.
    private var pan: CGPoint = .zero
    /// The text annotation being re-edited; hidden while its field is open.
    private var editingTextID: Annotation.ID?

    init(document: AnnotationDocument, state: EditorState) {
        self.document = document
        self.state = state
        renderer = AnnotationRenderer(base: document.image, scale: document.scale)
        super.init(frame: .zero)
        document.$annotations
            .sink { [weak self] _ in self?.needsDisplay = true }
            .store(in: &observations)
        document.$backdrop
            .sink { [weak self] _ in self?.needsDisplay = true }
            .store(in: &observations)
        document.$crop
            .sink { [weak self] _ in
                self?.commitText()
                self?.needsDisplay = true
            }
            .store(in: &observations)
        state.$tool
            .sink { [weak self] tool in
                guard let self else { return }
                self.commitText()
                if tool != .select { self.deselect() }
                // Entering or leaving the crop tool changes what part of the image is shown.
                self.needsDisplay = true
                self.window?.invalidateCursorRects(for: self)
            }
            .store(in: &observations)
        // Published values arrive before they're stored, so use the value passed in.
        state.$color
            .sink { [weak self] color in self?.updateSelection { $0.color = color } }
            .store(in: &observations)
        state.$zoom
            .sink { [weak self] zoom in
                if zoom == nil { self?.pan = .zero }
                self?.commitText()
                self?.needsDisplay = true
            }
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

    /// The part of the image on screen, in image pixels: all of it while cropping, so the crop can
    /// be redrawn anywhere; otherwise just the crop.
    private var shownRect: CGRect {
        state.tool == .crop ? CGRect(origin: .zero, size: renderer.imageSize) : document.visibleRect
    }

    /// The background around the screenshot, when on. Hidden while cropping, which needs the whole image.
    private var backdropLayout: BackdropRenderer.Layout? {
        guard document.backdrop.isEnabled, state.tool != .crop else { return nil }
        return BackdropRenderer.layout(contentSize: shownRect.size, backdrop: document.backdrop, scale: document.scale)
    }

    /// Everything drawn, in view coordinates: the background canvas if there is one, otherwise the
    /// screenshot. Fitted with a margin, never larger than its point size.
    private var canvasRect: CGRect {
        let size = canvasPointSize
        let zoom = state.zoom ?? fitZoom
        let shown = CGSize(width: size.width * zoom, height: size.height * zoom)
        let offset = clamped(pan, for: shown)
        return CGRect(x: bounds.midX - shown.width / 2 + offset.x, y: bounds.midY - shown.height / 2 + offset.y,
                      width: shown.width, height: shown.height).integral
    }

    /// The whole drawing (background included) in image points.
    private var canvasPointSize: CGSize {
        let pixels = backdropLayout?.canvasSize ?? shownRect.size
        return CGSize(width: pixels.width / document.scale, height: pixels.height / document.scale)
    }

    /// The zoom that fits the drawing in the view with a margin, never above 100 %.
    private var fitZoom: CGFloat {
        let size = canvasPointSize
        let available = bounds.insetBy(dx: 24, dy: 24)
        return max(min(1, available.width / size.width, available.height / size.height), 0.01)
    }

    /// Keeps a zoomed-in drawing from being scrolled out of sight; centers one that fits.
    private func clamped(_ pan: CGPoint, for size: CGSize) -> CGPoint {
        let limitX = max((size.width - bounds.width) / 2 + 24, 0)
        let limitY = max((size.height - bounds.height) / 2 + 24, 0)
        return CGPoint(x: min(max(pan.x, -limitX), limitX), y: min(max(pan.y, -limitY), limitY))
    }

    // MARK: Zoom

    static let zoomLevels: [CGFloat] = [0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 6, 8]

    /// Zooms so that whatever is under `anchor` (view coordinates) stays put.
    func setZoom(_ newZoom: CGFloat?, around anchor: CGPoint? = nil) {
        let oldRect = canvasRect
        let anchor = anchor ?? CGPoint(x: bounds.midX, y: bounds.midY)
        guard let newZoom else {
            pan = .zero
            state.zoom = nil
            return
        }
        let zoom = min(max(newZoom, 0.1), 8)
        let factor = zoom / (oldRect.width / canvasPointSize.width)
        // Where the drawing's origin must go for the anchor to stay over the same pixel.
        let origin = CGPoint(x: anchor.x - (anchor.x - oldRect.minX) * factor, y: anchor.y - (anchor.y - oldRect.minY) * factor)
        let size = CGSize(width: canvasPointSize.width * zoom, height: canvasPointSize.height * zoom)
        pan = CGPoint(x: origin.x - (bounds.midX - size.width / 2), y: origin.y - (bounds.midY - size.height / 2))
        state.zoom = zoom
    }

    func zoomIn() {
        let current = state.zoom ?? fitZoom
        setZoom(Self.zoomLevels.first { $0 > current + 0.001 } ?? 8)
    }

    func zoomOut() {
        let current = state.zoom ?? fitZoom
        setZoom(Self.zoomLevels.last { $0 < current - 0.001 } ?? 0.1)
    }

    override func magnify(with event: NSEvent) {
        let current = state.zoom ?? fitZoom
        setZoom(current * (1 + event.magnification), around: convert(event.locationInWindow, from: nil))
    }

    /// Two-finger scrolling moves a zoomed-in drawing around.
    override func scrollWheel(with event: NSEvent) {
        guard state.zoom != nil else { return super.scrollWheel(with: event) }
        let size = canvasRect.size
        pan = clamped(CGPoint(x: pan.x + event.scrollingDeltaX, y: pan.y + event.scrollingDeltaY), for: size)
        commitText()
        needsDisplay = true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]) == .command,
              window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers {
        case "=", "+": zoomIn()
        case "-": zoomOut()
        case "0": setZoom(nil)
        case "1": setZoom(1)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    /// Where `shownRect` is drawn, in view coordinates.
    private var imageRect: CGRect {
        let canvas = canvasRect
        guard let layout = backdropLayout else { return canvas }
        let scale = canvas.width / layout.canvasSize.width
        return CGRect(x: canvas.minX + layout.contentRect.minX * scale, y: canvas.minY + layout.contentRect.minY * scale,
                      width: layout.contentRect.width * scale, height: layout.contentRect.height * scale)
    }

    /// View points per image pixel.
    private var viewScale: CGFloat { imageRect.width / shownRect.width }

    private func imagePoint(_ viewPoint: CGPoint) -> CGPoint {
        let rect = imageRect
        let shown = shownRect
        let x = shown.minX + (viewPoint.x - rect.minX) / viewScale
        let y = shown.minY + (viewPoint.y - rect.minY) / viewScale
        return CGPoint(x: min(max(x, shown.minX), shown.maxX), y: min(max(y, shown.minY), shown.maxY))
    }

    private func viewPoint(_ imagePoint: CGPoint) -> CGPoint {
        let shown = shownRect
        return CGPoint(x: imageRect.minX + (imagePoint.x - shown.minX) * viewScale,
                       y: imageRect.minY + (imagePoint.y - shown.minY) * viewScale)
    }

    private func viewRect(_ imageRect: CGRect) -> CGRect {
        let origin = viewPoint(imageRect.origin)
        return CGRect(x: origin.x, y: origin.y, width: imageRect.width * viewScale, height: imageRect.height * viewScale)
    }

    override func setFrameSize(_ newSize: NSSize) {
        // The text field is positioned for the old size.
        if newSize != frame.size { commitText() }
        super.setFrameSize(newSize)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let shownZoom = canvasRect.width / canvasPointSize.width
        if abs(state.displayedZoom - shownZoom) > 0.001 {
            DispatchQueue.main.async { [state] in state.displayedZoom = shownZoom }
        }
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        var annotations = document.annotations.filter { $0.id != editingTextID }
        if let movePreview, let index = annotations.firstIndex(where: { $0.id == movePreview.id }) {
            annotations[index] = movePreview
        }
        annotations += [draft].compactMap { $0 }
        context.interpolationQuality = .high

        let drawScreenshot = { [self] in
            let rect = imageRect
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: viewScale, y: viewScale)
            context.translateBy(x: -shownRect.minX, y: -shownRect.minY)
            renderer.draw(annotations, in: context)
            context.restoreGState()
        }

        if let layout = backdropLayout {
            // Same geometry as the export, scaled to the view.
            let canvas = canvasRect
            let scale = canvas.width / layout.canvasSize.width
            context.saveGState()
            context.translateBy(x: canvas.minX, y: canvas.minY)
            context.scaleBy(x: scale, y: scale)
            BackdropRenderer.drawFill(document.backdrop.fill, in: CGRect(origin: .zero, size: layout.canvasSize), context: context)
            BackdropRenderer.drawFrame(around: layout.contentRect, backdrop: document.backdrop, scale: document.scale, in: context) {
                context.saveGState()
                // Undo the canvas transform so the screenshot draws exactly as without a background.
                context.scaleBy(x: 1 / scale, y: 1 / scale)
                context.translateBy(x: -canvas.minX, y: -canvas.minY)
                drawScreenshot()
                context.restoreGState()
            }
            context.restoreGState()
        } else {
            context.saveGState()
            context.clip(to: imageRect)
            drawScreenshot()
            context.restoreGState()
        }

        if let selected = movePreview ?? selectedAnnotation {
            drawSelection(around: selected)
        }
        if state.tool == .crop, let crop = cropDraft ?? document.crop {
            drawCropOverlay(viewRect(crop), in: context)
        }
    }

    /// Dims what the crop leaves out and marks its corners.
    private func drawCropOverlay(_ crop: CGRect, in context: CGContext) {
        let dim = CGMutablePath()
        dim.addRect(imageRect)
        dim.addRect(crop)
        context.addPath(dim)
        context.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        context.fillPath(using: .evenOdd)

        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1)
        context.stroke(crop.insetBy(dx: 0.5, dy: 0.5))
        let arm = min(16, crop.width / 3, crop.height / 3)
        context.setLineWidth(3)
        for (x, dx) in [(crop.minX, arm), (crop.maxX, -arm)] {
            for (y, dy) in [(crop.minY, arm), (crop.maxY, -arm)] {
                context.move(to: CGPoint(x: x + dx, y: y))
                context.addLine(to: CGPoint(x: x, y: y))
                context.addLine(to: CGPoint(x: x, y: y + dy))
            }
        }
        context.strokePath()
    }

    private func drawSelection(around annotation: Annotation) {
        let rect = viewRect(annotation.bounds).insetBy(dx: -4, dy: -4)
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

        // Double-clicking a text annotation reopens it for editing.
        if event.clickCount == 2, state.tool == .select || state.tool == .text,
           let hit = document.annotation(at: point, tolerance: 6 / viewScale), case .text = hit.shape {
            moving = nil
            deselect()
            commitText()
            beginText(at: point, editing: hit)
            return
        }

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
        case .crop:
            dragStart = point
            cropDraft = nil
        case .pen:
            dragStart = point
            penPoints = [point]
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
        // Shift: squares and 45° arrows. Option: shapes grow from where the drag started.
        let shift = event.modifierFlags.contains(.shift)
        let rect = SelectionGeometry.rect(
            anchor: start, current: point, square: shift, fromCenter: event.modifierFlags.contains(.option),
            bounds: CGRect(origin: .zero, size: renderer.imageSize)
        )
        if state.tool == .crop {
            cropDraft = rect
            needsDisplay = true
            return
        }
        let shape: AnnotationShape
        switch state.tool {
        case .arrow: shape = .arrow(from: start, to: shift ? Self.snapped(point, from: start) : point)
        case .rectangle: shape = .rectangle(rect)
        case .ellipse: shape = .ellipse(rect)
        case .line: shape = .line(from: start, to: shift ? Self.snapped(point, from: start) : point)
        case .spotlight: shape = .spotlight(rect)
        case .pen:
            // Skip points closer than about a screen point; they only add jitter.
            if let last = penPoints.last, hypot(point.x - last.x, point.y - last.y) < 1.5 / viewScale { return }
            penPoints.append(point)
            shape = .freehand(penPoints)
        case .highlight: shape = .highlight(rect)
        case .pixelate: shape = .pixelate(rect)
        case .blur: shape = .blur(rect)
        case .select, .crop, .text, .counter: return
        }
        draft = Annotation(id: draft?.id ?? UUID(), shape: shape, color: state.color, lineWidth: state.size.lineWidth * document.scale)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if state.tool == .crop {
            // A click without a real drag keeps the current crop.
            if let cropDraft, cropDraft.width > 8, cropDraft.height > 8 {
                document.setCrop(cropDraft)
            }
            cropDraft = nil
            dragStart = nil
            needsDisplay = true
            return
        }
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

    /// The end of an arrow turned to the nearest multiple of 45°, keeping its length.
    static func snapped(_ point: CGPoint, from start: CGPoint) -> CGPoint {
        let dx = point.x - start.x
        let dy = point.y - start.y
        let step = CGFloat.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        let length = hypot(dx, dy)
        return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
    }

    /// Ignore accidental clicks that would leave a speck.
    private static func isBigEnough(_ shape: AnnotationShape) -> Bool {
        switch shape {
        case let .arrow(from, to), let .line(from, to): hypot(to.x - from.x, to.y - from.y) > 6
        case let .rectangle(rect), let .ellipse(rect), let .highlight(rect), let .pixelate(rect), let .blur(rect):
            rect.width > 3 && rect.height > 3
        case let .spotlight(rect): rect.width > 8 && rect.height > 8
        case let .freehand(points): points.count > 1
        case .text, .counter: true
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        if modifiers.isEmpty, state.tool == .crop {
            switch event.keyCode {
            case 51, 117: // Delete, Forward Delete: back to the whole image
                document.setCrop(nil)
                return
            case 36, 76, 53: // Return, Enter, Esc: done cropping
                state.tool = .select
                return
            default:
                break
            }
        }
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

    /// Opens a text field at `point`, or over an existing text annotation to change it.
    private func beginText(at point: CGPoint, editing existing: Annotation? = nil) {
        var string = ""
        if let existing, case let .text(origin, text, fontSize) = existing.shape {
            editingTextID = existing.id
            textOrigin = origin
            textColor = existing.color
            textFontSize = fontSize
            string = text
            needsDisplay = true
        } else {
            editingTextID = nil
            textOrigin = point
            textColor = state.color
            textFontSize = state.size.fontSize * document.scale
        }
        let field = NSTextField(string: string)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.delegate = self
        let fontSize = textFontSize * viewScale
        field.font = .systemFont(ofSize: fontSize, weight: .bold)
        field.textColor = NSColor(cgColor: textColor.cgColor)
        field.placeholderString = "Text"
        let origin = viewPoint(textOrigin)
        let width = max(field.attributedStringValue.size().width + 16, fontSize * 4, 60)
        field.frame = CGRect(x: origin.x - 2, y: origin.y, width: width, height: ceil(fontSize * 1.3))
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
        let editingID = editingTextID
        editingTextID = nil
        needsDisplay = true
        let shape = AnnotationShape.text(origin: textOrigin, string: string, fontSize: textFontSize)
        if let editingID {
            // Emptying an existing text deletes it.
            if string.isEmpty {
                document.remove(id: editingID)
            } else {
                document.replace(Annotation(id: editingID, shape: shape, color: textColor, lineWidth: 0))
            }
        } else if !string.isEmpty {
            document.add(Annotation(shape: shape, color: textColor, lineWidth: 0))
        }
    }

    private func cancelText() {
        textField?.removeFromSuperview()
        textField = nil
        editingTextID = nil
        needsDisplay = true
        window?.makeFirstResponder(self)
    }
}
