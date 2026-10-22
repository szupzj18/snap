import AppKit
import SnapkitCore

/// Decides what happens to a finished capture.
@MainActor
final class PostCaptureRouter {
    func handle(_ capture: Capture) {
        do {
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            let name = FilenameFormatter.filename(
                template: FilenameFormatter.defaultTemplate,
                date: capture.date,
                mode: capture.mode,
                appName: capture.appName
            )
            try ImageExporter.writePNG(capture.image, scale: capture.scale, to: desktop, filename: name)
        } catch {
            ErrorPresenter.present(error)
        }
    }
}
