import AppKit
import SnapkitCapture
import SnapkitCore

/// Lets the user drag out a rectangle on a frozen image of the screens.
///
/// Each screen gets its own panel. A selection stays within the screen it started on.
@MainActor
final class AreaSelectionSession {
    private let presenter = OverlayPresenter()
    private var continuation: CheckedContinuation<Capture?, Never>?

    /// Returns nil if the user cancels.
    func run(snapshots: [DisplaySnapshot]) async -> Capture? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            var panels: [OverlayPanel] = []
            for snapshot in snapshots {
                guard let screen = NSScreen.screen(for: snapshot.displayID) else { continue }
                let panel = OverlayPanel(screen: screen)
                let view = AreaSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size), snapshot: snapshot)
                view.onSelect = { [weak self] rect in self?.finish(snapshot: snapshot, selection: rect) }
                view.onCancel = { [weak self] in self?.finish(nil) }
                panel.contentView = view
                panel.makeFirstResponder(view)
                panels.append(panel)
            }
            guard !panels.isEmpty else {
                finish(nil)
                return
            }
            presenter.show(panels)
        }
    }

    private func finish(snapshot: DisplaySnapshot, selection: CGRect) {
        let pixels = ScreenGeometry.pixelRect(fromBottomLeft: selection, in: snapshot.frame.size, scale: snapshot.scale)
        guard let image = snapshot.image.cropping(to: pixels) else {
            finish(nil)
            return
        }
        // Back from pixels to Quartz global points, so the result knows where it was on screen.
        let source = CGRect(
            x: snapshot.frame.minX + pixels.minX / snapshot.scale,
            y: snapshot.frame.minY + pixels.minY / snapshot.scale,
            width: pixels.width / snapshot.scale,
            height: pixels.height / snapshot.scale
        )
        finish(Capture(image: image, scale: snapshot.scale, mode: .area, sourceRect: source, displayID: snapshot.displayID))
    }

    private func finish(_ capture: Capture?) {
        presenter.dismiss()
        continuation?.resume(returning: capture)
        continuation = nil
    }
}
