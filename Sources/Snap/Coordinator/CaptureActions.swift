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

    /// Recognizes the text in the capture and puts it on the clipboard, with a toast either way.
    func copyText(from capture: Capture) async {
        do {
            let text = try await TextRecognizer.recognize(in: capture.image)
            if text.isEmpty {
                Toast.show("No text found", systemImage: "text.viewfinder")
            } else {
                Clipboard.copy(text)
                Toast.show("Copied \(text.count) characters", systemImage: "doc.on.clipboard")
            }
        } catch {
            ErrorPresenter.present(error)
        }
    }

    // MARK: Recordings

    /// Moves a recording from the temporary folder into the save folder.
    func saveRecording(_ recording: Recording) throws -> URL {
        let name = FilenameFormatter.filename(template: settings.filenameTemplate, date: recording.date, mode: .recording)
        try FileManager.default.createDirectory(at: settings.saveDirectory, withIntermediateDirectories: true)
        let destination = ImageExporter.uniqueURL(in: settings.saveDirectory, filename: name, pathExtension: "mp4")
        try FileManager.default.moveItem(at: recording.url, to: destination)
        return destination
    }

    /// Puts a file on the clipboard, the way Finder's Copy does.
    func copyFile(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    /// Converts a recording to a GIF next to the other captures.
    func exportGIF(from videoURL: URL, date: Date) async {
        Toast.show("Making GIF…", systemImage: "hourglass")
        do {
            let name = FilenameFormatter.filename(template: settings.filenameTemplate, date: date, mode: .recording)
            try FileManager.default.createDirectory(at: settings.saveDirectory, withIntermediateDirectories: true)
            let gif = ImageExporter.uniqueURL(in: settings.saveDirectory, filename: name, pathExtension: "gif")
            try await VideoFrames.exportGIF(from: videoURL, to: gif)
            Toast.show("Saved \(gif.lastPathComponent)", systemImage: "checkmark.circle")
        } catch {
            ErrorPresenter.present(error)
        }
    }

    /// Recordings wait here until they're saved.
    static let recordingsDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Snap")
        .appendingPathComponent("Recordings")

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

    /// Drag copies and unsaved recordings from an earlier run.
    static func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: dragDirectory)
        try? FileManager.default.removeItem(at: recordingsDirectory)
    }
}
