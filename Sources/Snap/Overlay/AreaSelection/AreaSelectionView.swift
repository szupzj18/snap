import AppKit
import SnapCapture
import SnapCore

/// Shows one screen's frozen image, dims it, and tracks the rectangle being dragged.
///
/// While dragging: Shift makes a square, Option grows from the center, holding Space moves the
/// whole selection. Before dragging, Space switches to window capture (when allowed).
final class AreaSelectionView: NSView {
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    /// Set to offer Space-to-switch to window capture, like macOS's own ⌘⇧4.
    var onSwitchToWindow: (() -> Void)?

    private let scale: CGFloat
    private let overlay: SelectionOverlayView
    /// The fixed corner (or the center, with Option) of the selection being dragged.
    private var anchor: CGPoint?
    private var lastPoint: CGPoint = .zero
    private var isMovingSelection = false

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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.crosshair.set()
        window?.makeKey()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        let point = location(of: event)
        overlay.pointer = point
        overlay.loupe = point
    }

    override func mouseExited(with event: NSEvent) {
        overlay.pointer = nil
        overlay.loupe = nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = location(of: event)
        anchor = point
        lastPoint = point
        isMovingSelection = false
        overlay.pointer = nil
        overlay.selection = nil
        overlay.loupe = point
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor else { return }
        let point = location(of: event)
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
        onSelect?(selection)
    }

    override func rightMouseDown(with event: NSEvent) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            onCancel?()
        case 49: // Space
            guard !event.isARepeat else { return }
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

    private func drawSizeLabel(for selection: CGRect) {
        let text = "\(Int((selection.width * scale).rounded())) × \(Int((selection.height * scale).rounded()))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding = CGSize(width: 8, height: 4)
        var box = CGRect(
            x: selection.maxX - size.width - padding.width * 2,
            y: selection.minY - size.height - padding.height * 2 - 6,
            width: size.width + padding.width * 2,
            height: size.height + padding.height * 2
        )
        // No room below the selection: tuck the label inside its bottom edge.
        if box.minY < 0 { box.origin.y = selection.minY + 6 }
        box.origin.x = max(box.minX, 0)

        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + padding.width, y: box.minY + padding.height), withAttributes: attributes)
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
