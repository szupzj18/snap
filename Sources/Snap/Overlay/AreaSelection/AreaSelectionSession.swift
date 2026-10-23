import AppKit
import SnapCapture
import SnapCore

enum AreaSelectionResult {
    case selected(Capture)
    case cancelled
    /// The user pressed Space before dragging: they want a window instead.
    case switchToWindow

    var capture: Capture? {
        if case let .selected(capture) = self { capture } else { nil }
    }
}

/// Lets the user drag out a rectangle on a frozen image of the screens.
///
/// Each screen gets its own panel. A selection stays within the screen it started on.
@MainActor
final class AreaSelectionSession {
    private let presenter = OverlayPresenter()
    private let mode: CaptureMode
    private let allowsWindowSwitch: Bool
    private var continuation: CheckedContinuation<AreaSelectionResult, Never>?

    init(mode: CaptureMode = .area, allowsWindowSwitch: Bool = false) {
        self.mode = mode
        self.allowsWindowSwitch = allowsWindowSwitch
    }

    func run(snapshots: [DisplaySnapshot]) async -> AreaSelectionResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            var panels: [OverlayPanel] = []
            for snapshot in snapshots {
                guard let screen = NSScreen.screen(for: snapshot.displayID) else { continue }
                let panel = OverlayPanel(screen: screen)
                let view = AreaSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size), snapshot: snapshot)
                view.onSelect = { [weak self] rect in self?.finish(snapshot: snapshot, selection: rect) }
                view.onCancel = { [weak self] in self?.finish(.cancelled) }
                if allowsWindowSwitch {
                    view.onSwitchToWindow = { [weak self] in self?.finish(.switchToWindow) }
                }
                panel.contentView = view
                panel.makeFirstResponder(view)
                panels.append(panel)
            }
            guard !panels.isEmpty else {
                finish(.cancelled)
                return
            }
            presenter.show(panels)
        }
    }

    private func finish(snapshot: DisplaySnapshot, selection: CGRect) {
        let pixels = ScreenGeometry.pixelRect(fromBottomLeft: selection, in: snapshot.frame.size, scale: snapshot.scale)
        guard let image = snapshot.image.cropping(to: pixels) else {
            finish(.cancelled)
            return
        }
        // Back from pixels to Quartz global points, so the result knows where it was on screen.
        let source = CGRect(
            x: snapshot.frame.minX + pixels.minX / snapshot.scale,
            y: snapshot.frame.minY + pixels.minY / snapshot.scale,
            width: pixels.width / snapshot.scale,
            height: pixels.height / snapshot.scale
        )
        finish(.selected(Capture(image: image, scale: snapshot.scale, mode: mode, sourceRect: source, displayID: snapshot.displayID)))
    }

    private func finish(_ result: AreaSelectionResult) {
        presenter.dismiss()
        continuation?.resume(returning: result)
        continuation = nil
    }
}
