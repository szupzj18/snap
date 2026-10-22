import AppKit
import SnapkitCapture
import SnapkitCore

/// Highlights the window under the pointer and returns the one the user clicks.
@MainActor
final class WindowPickerSession {
    private let presenter = OverlayPresenter()
    private var views: [WindowPickerView] = []
    private var windows: [PickableWindow] = []
    private var continuation: CheckedContinuation<PickableWindow?, Never>?

    private var hovered: PickableWindow? {
        didSet {
            guard hovered?.windowID != oldValue?.windowID else { return }
            views.forEach { $0.highlighted = hovered }
        }
    }

    /// `windows` must be ordered frontmost first. Returns nil if the user cancels.
    func run(windows: [PickableWindow]) async -> PickableWindow? {
        self.windows = windows
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            var panels: [OverlayPanel] = []
            for screen in NSScreen.screens {
                let panel = OverlayPanel(screen: screen)
                let view = WindowPickerView(frame: CGRect(origin: .zero, size: screen.frame.size), screenFrame: screen.frame)
                view.onMove = { [weak self] in self?.updateHovered() }
                view.onClick = { [weak self] in self?.pick() }
                view.onCancel = { [weak self] in self?.finish(nil) }
                panel.contentView = view
                panel.makeFirstResponder(view)
                panels.append(panel)
                views.append(view)
            }
            presenter.show(panels)
            updateHovered()
        }
    }

    private func updateHovered() {
        let point = ScreenGeometry.flip(NSEvent.mouseLocation, primaryScreenHeight: NSScreen.primaryHeight)
        hovered = windows.first { $0.frame.contains(point) }
    }

    private func pick() {
        updateHovered()
        // Clicking on the desktop picks nothing; keep going.
        guard let hovered else { return }
        finish(hovered)
    }

    private func finish(_ window: PickableWindow?) {
        presenter.dismiss()
        views = []
        continuation?.resume(returning: window)
        continuation = nil
    }
}

/// Transparent overlay for one screen that draws the highlight for its part of the hovered window.
final class WindowPickerView: NSView {
    var onMove: (() -> Void)?
    var onClick: (() -> Void)?
    var onCancel: (() -> Void)?

    var highlighted: PickableWindow? { didSet { needsDisplay = true } }

    /// This screen's frame in AppKit global coordinates.
    private let screenFrame: CGRect

    init(frame: CGRect, screenFrame: CGRect) {
        self.screenFrame = screenFrame
        super.init(frame: frame)
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

    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }

    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        onMove?()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.pointingHand.set()
        onMove?()
    }

    override func mouseUp(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func draw(_ dirtyRect: NSRect) {
        // A barely visible fill; a fully clear window would let some clicks fall through.
        NSColor.black.withAlphaComponent(0.01).setFill()
        bounds.fill()

        guard let window = highlighted else { return }
        let global = ScreenGeometry.flip(window.frame, primaryScreenHeight: NSScreen.primaryHeight)
        let local = global.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        guard local.intersects(bounds) else { return }

        let path = NSBezierPath(roundedRect: local, xRadius: 10, yRadius: 10)
        NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
        path.fill()
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 2
        path.stroke()

        // Label on the screen that holds the window's center.
        if bounds.contains(CGPoint(x: local.midX, y: local.midY)) {
            drawLabel(for: window, centeredIn: local)
        }
    }

    private func drawLabel(for window: PickableWindow, centeredIn rect: CGRect) {
        let size = "\(Int(window.frame.width)) × \(Int(window.frame.height))"
        let text = [window.appName, size].compactMap { $0 }.joined(separator: "  ·  ")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let box = CGRect(
            x: rect.midX - textSize.width / 2 - 10,
            y: rect.midY - textSize.height / 2 - 5,
            width: textSize.width + 20,
            height: textSize.height + 10
        )
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + 10, y: box.minY + 5), withAttributes: attributes)
    }
}
