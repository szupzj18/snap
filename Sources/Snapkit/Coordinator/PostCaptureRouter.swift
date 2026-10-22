import AppKit
import SnapkitCore

/// Decides what happens to a finished capture, based on the user's after-capture settings.
@MainActor
final class PostCaptureRouter {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func handle(_ capture: Capture) {
        do {
            let actions = settings.afterCapture
            if actions.contains(.copyToClipboard) {
                try Clipboard.copy(capture.image, scale: capture.scale)
            }
            if actions.contains(.save) {
                try save(capture)
            }
        } catch {
            ErrorPresenter.present(error)
        }
    }

    @discardableResult
    func save(_ capture: Capture) throws -> URL {
        try ImageExporter.writePNG(
            capture.image,
            scale: capture.scale,
            to: settings.saveDirectory,
            filename: settings.filename(for: capture)
        )
    }
}
