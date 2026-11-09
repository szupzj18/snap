import AppKit
import SnapCapture
import SnapCore

/// Shows one screen's frozen image, dims it, and tracks the rectangle being dragged.
///
/// While dragging: Shift makes a square, Option grows from the center, holding Space moves the
/// whole selection. Before dragging, Space switches to window capture (when allowed).
///
/// With `adjustsBeforeCapture` (or a selection handed in to start from), letting go doesn't capture
/// yet: drag the handles or the inside, use the arrow keys (⇧ for 10 pt, ⌥ to resize), click the
/// size to type exact pixels, then Return or double-click to capture. Dragging outside starts over.
final class AreaSelectionView: NSView, NSTextFieldDelegate {
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    /// Set to offer Space-to-switch to window capture, like macOS's own ⌘⇧4.
    var onSwitchToWindow: (() -> Void)?
    /// Called when a new selection starts here, so other screens can drop theirs.
    var onBeginSelection: (() -> Void)?
    var adjustsBeforeCapture = false

    private let scale: CGFloat
    private let overlay: SelectionOverlayView
    /// The fixed corner (or the center, with Option) of the selection being dragged.
    private var anchor: CGPoint?
    private var lastPoint: CGPoint = .zero
    private var isMovingSelection = false

    /// A finished selection waiting for Return; it shows handles.
    private(set) var isAdjusting = false {
        didSet { overlay.showsHandles = isAdjusting }
    }
    private enum Adjustment {
        case move
        case resize(SelectionGeometry.Handle)
    }
    private var adjustment: Adjustment?
    private var sizeField: NSTextField?

    /// Smaller drags count as an accidental click.
    private let minimumSize: CGFloat = 4

    init(frame: CGRect, snapshot: DisplaySnapshot) {
        scale = snapshot.scale
        overlay = SelectionOverlayView(image: snapshot.image, scale: snapshot.scale)
        super.init(frame: frame)
        // The frozen screen is a layer's contents, so moving the selection never redraws it.
        wantsLayer = true
        layer?.contents = snapshot.image
        layer?.contentsGravity = .resize
        overlay.frame = bounds
        overlay.autoresizingMask = [.width, .height]
        addSubview(overlay)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Starts from an existing selection (view coordinates), ready to adjust.
    func adjust(_ selection: CGRect) {
        overlay.selection = selection.intersection(bounds)
        overlay.pointer = nil
        overlay.loupe = nil
        isAdjusting = true
    }

    func clearSelection() {
        endSizeEditing()
        overlay.selection = nil
        isAdjusting = false
        adjustment = nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) { cursor(at: location(of: event)).set() }

    override func mouseEntered(with event: NSEvent) {
        cursor(at: location(of: event)).set()
        window?.makeKey()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = location(of: event)
        cursor(at: point).set()
        guard !isAdjusting else { return }
        overlay.pointer = point
        overlay.loupe = point
    }

    override func mouseExited(with event: NSEvent) {
        overlay.pointer = nil
        overlay.loupe = nil
    }

    private func cursor(at point: CGPoint) -> NSCursor {
        guard isAdjusting, let selection = overlay.selection else { return .crosshair }
        if SelectionGeometry.handle(at: point, of: selection) != nil { return .crosshair }
        if overlay.sizeLabelFrame(for: selection).contains(point) { return .iBeam }
        return selection.contains(point) ? .openHand : .crosshair
    }

    override func mouseDown(with event: NSEvent) {
        let point = location(of: event)
        if sizeField != nil { endSizeEditing() }
        if isAdjusting, let selection = overlay.selection {
            if overlay.sizeLabelFrame(for: selection).contains(point) {
                beginSizeEditing(selection)
                return
            }
            if let handle = SelectionGeometry.handle(at: point, of: selection) {
                adjustment = .resize(handle)
                lastPoint = point
                overlay.loupe = point
                return
            }
            if selection.contains(point) {
                if event.clickCount == 2 {
                    onSelect?(selection)
                    return
                }
                adjustment = .move
                lastPoint = point
                NSCursor.closedHand.set()
                return
            }
            // Outside: start a new selection.
            isAdjusting = false
        }
        onBeginSelection?()
        anchor = point
        lastPoint = point
        isMovingSelection = false
        overlay.pointer = nil
        overlay.selection = nil
        overlay.loupe = point
    }

    override func mouseDragged(with event: NSEvent) {
        let point = location(of: event)
        if let adjustment, let selection = overlay.selection {
            let delta = CGVector(dx: point.x - lastPoint.x, dy: point.y - lastPoint.y)
            lastPoint = point
            switch adjustment {
            case .move:
                overlay.selection = SelectionGeometry.move(selection, by: delta, within: bounds)
            case let .resize(handle):
                overlay.selection = SelectionGeometry.resize(selection, handle: handle, by: delta, within: bounds, minimum: minimumSize)
                overlay.loupe = point
            }
            return
        }
        guard let anchor else { return }
        defer {
            lastPoint = point
            overlay.loupe = point
        }

        if isMovingSelection, let selection = overlay.selection {
            let moved = SelectionGeometry.move(
                selection, by: CGVector(dx: point.x - lastPoint.x, dy: point.y - lastPoint.y), within: bounds
            )
            // The anchor travels with the selection, so resizing picks up from here after Space.
            self.anchor = CGPoint(x: anchor.x + moved.minX - selection.minX, y: anchor.y + moved.minY - selection.minY)
            overlay.selection = moved
            return
        }

        overlay.selection = SelectionGeometry.rect(
            anchor: anchor,
            current: point,
            square: event.modifierFlags.contains(.shift),
            fromCenter: event.modifierFlags.contains(.option),
            bounds: bounds
        )
    }

    override func mouseUp(with event: NSEvent) {
        if adjustment != nil {
            adjustment = nil
            overlay.loupe = nil
            cursor(at: location(of: event)).set()
            return
        }
        guard anchor != nil else { return }
        defer {
            anchor = nil
            isMovingSelection = false
        }
        guard let selection = overlay.selection,
              selection.width >= minimumSize, selection.height >= minimumSize else {
            overlay.selection = nil
            let point = location(of: event)
            overlay.pointer = point
            overlay.loupe = point
            return
        }
        if adjustsBeforeCapture {
            overlay.loupe = nil
            isAdjusting = true
        } else {
            onSelect?(selection)
        }
    }

    override func rightMouseDown(with event: NSEvent) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        if isAdjusting, let selection = overlay.selection {
            let flags = event.modifierFlags
            if let offset = KeyNudge.offset(keyCode: event.keyCode, shift: flags.contains(.shift)) {
                overlay.selection = flags.contains(.option)
                    ? SelectionGeometry.resize(selection, handle: .bottomRight, by: offset, within: bounds, minimum: minimumSize)
                    : SelectionGeometry.move(selection, by: offset, within: bounds)
                return
            }
            if event.keyCode == 36 || event.keyCode == 76 { // Return, Enter
                onSelect?(selection)
                return
            }
        }
        switch event.keyCode {
        case 53: // Esc
            onCancel?()
        case 49: // Space
            guard !event.isARepeat, !isAdjusting else { return }
            if anchor != nil {
                isMovingSelection = true
            } else {
                onSwitchToWindow?()
            }
        default:
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            isMovingSelection = false
        } else {
            super.keyUp(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    // MARK: Typing a size

    private func beginSizeEditing(_ selection: CGRect) {
        let field = NSTextField(string: "\(Int((selection.width * scale).rounded()))x\(Int((selection.height * scale).rounded()))")
        field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        field.alignment = .center
        field.focusRingType = .none
        field.delegate = self
        let label = overlay.sizeLabelFrame(for: selection)
        field.frame = CGRect(x: label.minX, y: label.minY, width: max(label.width, 110), height: label.height)
        addSubview(field)
        sizeField = field
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    private func endSizeEditing() {
        guard let field = sizeField else { return }
        sizeField = nil
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
    }

    /// Return applies the typed pixel size (keeping the top-left corner); Esc leaves it as it was.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            if let size = SelectionGeometry.parseSize(control.stringValue), let selection = overlay.selection {
                overlay.selection = SelectionGeometry.resized(
                    selection, to: CGSize(width: CGFloat(size.width) / scale, height: CGFloat(size.height) / scale), within: bounds
                )
            } else {
                NSSound.beep()
            }
            endSizeEditing()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            endSizeEditing()
            return true
        default:
            return false
        }
    }

    private func location(of event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
    }
}

/// Draws the dimming, the selection outline, crosshair guides, the size label and the loupe.
private final class SelectionOverlayView: NSView {
    var selection: CGRect? { didSet { needsDisplay = true } }
    /// Where to draw the crosshair guides (only while not dragging).
    var pointer: CGPoint? { didSet { needsDisplay = true } }
    /// Where to center the magnifier.
    var loupe: CGPoint? { didSet { needsDisplay = true } }
    /// Grab points and a hint, while the selection waits for Return.
    var showsHandles = false { didSet { needsDisplay = true } }

    private let image: CGImage
    private let scale: CGFloat

    /// Pixels across the magnifier, and how big each is drawn.
    private let loupePixels = 15
    private let loupeCell: CGFloat = 8

    init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let selection { dim.addRect(selection) }
        context.addPath(dim)
        context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        context.fillPath(using: .evenOdd)

        if let pointer {
            drawGuides(at: pointer, in: context)
        }

        if let selection {
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1)
            context.stroke(selection.insetBy(dx: -0.5, dy: -0.5))
            drawSizeLabel(for: selection)
            if showsHandles {
                drawHandles(on: selection, in: context)
                drawHint(for: selection)
            }
        }

        if let loupe {
            drawLoupe(at: loupe, in: context)
        }
    }

    private func drawGuides(at point: CGPoint, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
        context.setLineWidth(1 / scale)
        context.setShadow(offset: .zero, blur: 1, color: NSColor.black.withAlphaComponent(0.6).cgColor)
        context.strokeLineSegments(between: [
            CGPoint(x: point.x, y: 0), CGPoint(x: point.x, y: bounds.height),
            CGPoint(x: 0, y: point.y), CGPoint(x: bounds.width, y: point.y),
        ])
        context.restoreGState()
    }

    private static let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white,
    ]
    private static let labelPadding = CGSize(width: 8, height: 4)

    private func sizeText(for selection: CGRect) -> String {
        "\(Int((selection.width * scale).rounded())) × \(Int((selection.height * scale).rounded()))"
    }

    /// Where the size label goes: below the selection's bottom-right, or inside it near the bottom.
    func sizeLabelFrame(for selection: CGRect) -> CGRect {
        let size = (sizeText(for: selection) as NSString).size(withAttributes: Self.labelAttributes)
        let padding = Self.labelPadding
        var box = CGRect(
            x: selection.maxX - size.width - padding.width * 2,
            y: selection.minY - size.height - padding.height * 2 - 6,
            width: size.width + padding.width * 2,
            height: size.height + padding.height * 2
        )
        // No room below the selection: tuck the label inside its bottom edge.
        if box.minY < 0 { box.origin.y = selection.minY + 6 }
        box.origin.x = max(box.minX, 0)
        return box
    }

    private func drawSizeLabel(for selection: CGRect) {
        let box = sizeLabelFrame(for: selection)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        (sizeText(for: selection) as NSString).draw(
            at: CGPoint(x: box.minX + Self.labelPadding.width, y: box.minY + Self.labelPadding.height),
            withAttributes: Self.labelAttributes
        )
    }

    private func drawHandles(on selection: CGRect, in context: CGContext) {
        context.saveGState()
        context.setShadow(offset: .zero, blur: 2, color: NSColor.black.withAlphaComponent(0.6).cgColor)
        for handle in SelectionGeometry.Handle.allCases {
            let point = handle.point(on: selection)
            let dot = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: dot)
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: dot.insetBy(dx: 0.75, dy: 0.75))
        }
        context.restoreGState()
    }

    /// What to do next, above the selection (or inside its top edge when there's no room).
    private func drawHint(for selection: CGRect) {
        let text = "Return to capture · Arrows move, ⌥ resizes · Click the size to type it · Esc cancels" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        var box = CGRect(x: selection.minX, y: selection.maxY + 6, width: size.width + 16, height: size.height + 6)
        if box.maxY > bounds.maxY { box.origin.y = selection.maxY - box.height - 6 }
        box.origin.x = min(max(box.minX, 0), max(bounds.maxX - box.width, 0))
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        text.draw(at: CGPoint(x: box.minX + 8, y: box.minY + 3), withAttributes: attributes)
    }

    /// A magnified view of the pixels under the pointer, with their coordinates, for exact edges.
    private func drawLoupe(at point: CGPoint, in context: CGContext) {
        let side = CGFloat(loupePixels) * loupeCell
        // Bottom-right of the pointer, flipped to the other side near the screen's edges.
        var frame = CGRect(x: point.x + 24, y: point.y - 24 - side, width: side, height: side)
        if frame.maxX > bounds.maxX - 8 { frame.origin.x = point.x - 24 - side }
        if frame.minY < 34 { frame.origin.y = point.y + 24 }

        // Pixel under the pointer, counted from the top-left of the frozen image.
        let pixelX = min(Int(point.x * scale), image.width - 1)
        let pixelY = min(Int((bounds.height - point.y) * scale), image.height - 1)
        let half = loupePixels / 2
        let originX = min(max(pixelX - half, 0), image.width - loupePixels)
        let originY = min(max(pixelY - half, 0), image.height - loupePixels)
        guard let pixels = image.cropping(to: CGRect(x: originX, y: originY, width: loupePixels, height: loupePixels)) else { return }

        let shape = CGPath(roundedRect: frame, cornerWidth: 10, cornerHeight: 10, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        context.addPath(shape)
        context.setFillColor(NSColor.black.cgColor)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(shape)
        context.clip()
        context.interpolationQuality = .none
        context.draw(pixels, in: frame)
        // The pixel under the pointer (the image's rows run top to bottom, the view's bottom to top).
        let cell = CGRect(
            x: frame.minX + CGFloat(pixelX - originX) * loupeCell,
            y: frame.maxY - CGFloat(pixelY - originY + 1) * loupeCell,
            width: loupeCell,
            height: loupeCell
        )
        context.setLineWidth(1)
        context.setStrokeColor(NSColor.black.cgColor)
        context.stroke(cell.insetBy(dx: -0.5, dy: -0.5))
        context.setStrokeColor(NSColor.white.cgColor)
        context.stroke(cell.insetBy(dx: 0.5, dy: 0.5))
        context.restoreGState()

        context.addPath(shape)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(2)
        context.strokePath()

        let text = "\(pixelX), \(pixelY)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let label = CGRect(x: frame.midX - size.width / 2 - 7, y: frame.minY - size.height - 10, width: size.width + 14, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: label, xRadius: label.height / 2, yRadius: label.height / 2).fill()
        (text as NSString).draw(at: CGPoint(x: label.minX + 7, y: label.minY + 2), withAttributes: attributes)
    }
}
