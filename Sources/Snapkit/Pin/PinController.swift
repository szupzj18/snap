import AppKit
import SnapkitCore

/// Keeps captures pinned to the screen as always-on-top windows.
@MainActor
final class PinController {
    private let actions: CaptureActions
    private var pins: [PinPanel] = []

    init(actions: CaptureActions) {
        self.actions = actions
    }

    func pin(_ capture: Capture) {
        let panel = PinPanel(capture: capture, frame: initialFrame(for: capture))
        panel.onCopy = { [weak self] in self?.perform { try self?.actions.copy(capture) } }
        panel.onSave = { [weak self] in
            self?.perform {
                if let url = try self?.actions.save(capture) { self?.actions.revealInFinder(url) }
            }
        }
        panel.onClose = { [weak self, weak panel] in
            guard let panel else { return }
            panel.orderOut(nil)
            self?.pins.removeAll { $0 === panel }
        }
        pins.append(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { ErrorPresenter.present(error) }
    }

    /// Where the pixels were on screen, shrunk to fit if the capture is bigger than the screen.
    private func initialFrame(for capture: Capture) -> CGRect {
        let source = ScreenGeometry.flip(capture.sourceRect, primaryScreenHeight: NSScreen.primaryHeight)
        var size = capture.pointSize
        let screen = capture.displayID.flatMap(NSScreen.screen(for:)) ?? NSScreen.underMouse ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let fit = min(1, visible.width * 0.9 / size.width, visible.height * 0.9 / size.height)
        size = CGSize(width: size.width * fit, height: size.height * fit)
        // Centered on the source, so a window capture's added shadow spreads evenly around it.
        var frame = CGRect(x: source.midX - size.width / 2, y: source.midY - size.height / 2, width: size.width, height: size.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return frame
    }
}
