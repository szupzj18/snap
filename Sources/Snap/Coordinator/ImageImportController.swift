import AppKit
import SnapCore
import UniformTypeIdentifiers

/// Opens existing images, from a file or the clipboard, in the editor or as a pin.
@MainActor
final class ImageImportController {
    private let editors: EditorPresenter
    private let pins: PinController

    init(editors: EditorPresenter, pins: PinController) {
        self.editors = editors
        self.pins = pins
    }

    var clipboardHasImage: Bool { ImageImport.pasteboardHasImage(.general) }

    func openFile() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.prompt = "Annotate"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do {
                editors.edit(try ImageImport.capture(fromFile: url))
            } catch {
                ErrorPresenter.present(error)
            }
        }
    }

    func annotateClipboard() {
        guard let capture = ImageImport.capture(from: .general) else { return noImage() }
        editors.edit(capture)
    }

    func pinClipboard() {
        guard let capture = ImageImport.capture(from: .general) else { return noImage() }
        pins.pin(capture)
    }

    private func noImage() {
        Toast.show("No image on the clipboard", systemImage: "doc.on.clipboard")
    }
}
