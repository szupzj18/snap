import AppKit
import SnapkitCore

/// An always-on-top window showing one capture.
///
/// Drag to move, scroll or pinch to zoom, ⌥-scroll to change opacity, right-click for more.
final class PinPanel: NSPanel {
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?

    private let imageSize: CGSize
    private let pinView: PinView
    private var zoom: CGFloat
    private let hud = PinHUD()

    init(capture: Capture, frame: CGRect) {
        imageSize = capture.pointSize
        zoom = frame.width / capture.pointSize.width
        pinView = PinView(image: capture.image)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentAspectRatio = imageSize
        minSize = CGSize(width: 40, height: 40 * imageSize.height / imageSize.width)

        pinView.frame = CGRect(origin: .zero, size: frame.size)
        pinView.autoresizingMask = [.width, .height]
        pinView.panel = self
        contentView = pinView
        hud.frame = CGRect(x: 0, y: 0, width: 64, height: 26)
        pinView.addSubview(hud)
    }

    override var canBecomeKey: Bool { true }

    // MARK: Zoom and opacity

    func setZoom(_ newZoom: CGFloat) {
        guard let screen = screen ?? NSScreen.main else { return }
        let maxZoom = min(screen.visibleFrame.width / imageSize.width, screen.visibleFrame.height / imageSize.height, 4)
        zoom = min(max(newZoom, 40 / imageSize.width), max(maxZoom, 1))
        let size = CGSize(width: imageSize.width * zoom, height: imageSize.height * zoom)
        // Grow and shrink around the center.
        let center = CGPoint(x: frame.midX, y: frame.midY)
        setFrame(CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height), display: true)
        hud.flash("\(Int((zoom * 100).rounded()))%", in: pinView)
    }

    func zoomBy(_ factor: CGFloat) { setZoom(zoom * factor) }

    func setOpacity(_ value: CGFloat) {
        alphaValue = min(max(value, 0.1), 1)
        hud.flash("\(Int((alphaValue * 100).rounded()))%", in: pinView)
    }

    // MARK: Keyboard

    // ⌘W and ⌘C arrive through the main menu when Snapkit is active, and as keyDown otherwise.
    override func performClose(_ sender: Any?) { onClose?() }
    @objc func copy(_ sender: Any?) { onCopy?() }

    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        switch (event.keyCode, command, event.charactersIgnoringModifiers) {
        case (53, _, _): onClose?() // Esc
        case (_, true, "w"): onClose?()
        case (_, true, "c"): onCopy?()
        case (_, true, "s"): onSave?()
        case (_, true, "="), (_, true, "+"): zoomBy(1.25)
        case (_, true, "-"): zoomBy(0.8)
        case (_, true, "0"): setZoom(1)
        default: super.keyDown(with: event)
        }
    }

    // MARK: Context menu

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Copy", key: "c") { [weak self] in self?.onCopy?() })
        menu.addItem(item("Save", key: "s") { [weak self] in self?.onSave?() })
        menu.addItem(.separator())
        menu.addItem(item("Actual Size", key: "0") { [weak self] in self?.setZoom(1) })
        menu.addItem(item("Zoom In", key: "=") { [weak self] in self?.zoomBy(1.25) })
        menu.addItem(item("Zoom Out", key: "-") { [weak self] in self?.zoomBy(0.8) })
        let opacity = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        for percent in [100, 80, 60, 40, 20] {
            let entry = item("\(percent)%") { [weak self] in self?.setOpacity(CGFloat(percent) / 100) }
            entry.state = Int((alphaValue * 100).rounded()) == percent ? .on : .off
            opacityMenu.addItem(entry)
        }
        opacity.submenu = opacityMenu
        menu.addItem(opacity)
        menu.addItem(.separator())
        menu.addItem(item("Close", key: "w") { [weak self] in self?.onClose?() })
        return menu
    }

    private func item(_ title: String, key: String = "", action: @escaping () -> Void) -> NSMenuItem {
        ClosureMenuItem(title: title, keyEquivalent: key, action: action)
    }
}

/// Menu item that runs a closure, to avoid a selector per entry.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String = "", action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}

/// Draws the image and handles mouse input for a pin.
private final class PinView: NSView {
    weak var panel: PinPanel?
    private let closeButton = NSButton()

    init(image: CGImage) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .linear
        layer?.minificationFilter = .trilinear

        closeButton.bezelStyle = .circular
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.isBordered = true
        closeButton.target = self
        closeButton.action = #selector(close)
        closeButton.frame = CGRect(x: 6, y: 0, width: 22, height: 22)
        closeButton.isHidden = true
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override func layout() {
        super.layout()
        closeButton.frame.origin = CGPoint(x: 6, y: bounds.height - 28)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { closeButton.isHidden = false }
    override func mouseExited(with event: NSEvent) { closeButton.isHidden = true }

    override func mouseDown(with event: NSEvent) {
        panel?.makeKey()
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let panel else { return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 100 : event.scrollingDeltaY / 10
        if event.modifierFlags.contains(.option) {
            panel.setOpacity(panel.alphaValue + delta)
        } else {
            panel.zoomBy(1 + delta)
        }
    }

    override func magnify(with event: NSEvent) {
        panel?.zoomBy(1 + event.magnification)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        panel?.makeMenu()
    }

    @objc private func close() { panel?.onClose?() }
}

/// A short-lived label showing the current zoom or opacity.
private final class PinHUD: NSView {
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        layer?.cornerRadius = 6
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        addSubview(label)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func flash(_ text: String, in container: NSView) {
        label.stringValue = text
        label.sizeToFit()
        let size = CGSize(width: max(label.frame.width + 16, 56), height: 24)
        frame = CGRect(x: container.bounds.midX - size.width / 2, y: container.bounds.midY - size.height / 2, width: size.width, height: size.height)
        label.frame = CGRect(x: 0, y: (size.height - label.frame.height) / 2, width: size.width, height: label.frame.height)
        isHidden = false
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.isHidden = true }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
}
