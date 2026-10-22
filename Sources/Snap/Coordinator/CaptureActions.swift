import AppKit
import SnapCore

/// The things a user can do with a capture, shared by the router, Quick Access, pins and the editor.
@MainActor
final class CaptureActions {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
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

    func copy(_ capture: Capture) throws {
        try Clipboard.copy(capture.image, scale: capture.scale)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// A file for drag and drop: the saved file if there is one, otherwise a temporary copy.
    func draggableFile(for capture: Capture, savedURL: URL?) throws -> URL {
        if let savedURL, FileManager.default.fileExists(atPath: savedURL.path) {
            return savedURL
        }
        let directory = Self.dragDirectory.appendingPathComponent(capture.id.uuidString)
        return try ImageExporter.writePNG(capture.image, scale: capture.scale, to: directory, filename: settings.filename(for: capture))
    }

    /// Temporary files from earlier drags. Receivers copy dropped files, so these can go on launch.
    static let dragDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Snap")
        .appendingPathComponent("Drag")

    static func removeDragFiles() {
        try? FileManager.default.removeItem(at: dragDirectory)
    }
}
