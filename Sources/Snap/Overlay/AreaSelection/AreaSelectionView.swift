import AppKit
import SnapCapture

/// Shows one screen's frozen image, dims it, and tracks the rectangle being dragged.
final class AreaSelectionView: NSView {
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let scale: CGFloat
    private let overlay = SelectionOverlayView()
    private var dragOrigin: CGPoint?

    /// Smaller drags count as an accidental click.
    private let minimumSize: CGFloat = 4

    init(frame: CGRect, snapshot: DisplaySnapshot) {
        scale = snapshot.scale
        super.init(frame: frame)
        // The frozen screen is a layer's contents, so moving the selection never redraws it.
        wantsLayer = true
        layer?.contents = snapshot.image
        layer?.contentsGravity = .resize
        overlay.frame = bounds
        overlay.autoresizingMask = [.width, .height]
        overlay.scale = scale
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
        overlay.pointer = location(of: event)
    }

    override func mouseExited(with event: NSEvent) {
        overlay.pointer = nil
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = location(of: event)
        overlay.pointer = nil
        overlay.selection = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        var current = location(of: event)
        if event.modifierFlags.contains(.shift) {
            // Shift makes it a square.
            let side = max(abs(current.x - origin.x), abs(current.y - origin.y))
            current = CGPoint(x: origin.x + (current.x < origin.x ? -side : side),
                              y: origin.y + (current.y < origin.y ? -side : side))
        }
        let rect = CGRect(x: min(origin.x, current.x), y: min(origin.y, current.y),
                          width: abs(current.x - origin.x), height: abs(current.y - origin.y))
        overlay.selection = rect.intersection(bounds)
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragOrigin = nil }
        guard let selection = overlay.selection,
              selection.width >= minimumSize, selection.height >= minimumSize else {
            overlay.selection = nil
            overlay.pointer = location(of: event)
            return
        }
        onSelect?(selection)
    }

    override func rightMouseDown(with event: NSEvent) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    private func location(of event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
    }
}

/// Draws the dimming, the selection outline, crosshair guides and the size label.
private final class SelectionOverlayView: NSView {
    var scale: CGFloat = 1
    var selection: CGRect? { didSet { needsDisplay = true } }
    var pointer: CGPoint? { didSet { needsDisplay = true } }

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
}
