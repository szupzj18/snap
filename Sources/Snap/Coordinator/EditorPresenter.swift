import AppKit
import SnapAnnotate
import SnapCore

/// Opens annotation editors and keeps them alive until they close.
@MainActor
final class EditorPresenter {
    private let settings: AppSettings
    private var open: [EditorWindowController] = []

    init(settings: AppSettings) {
        self.settings = settings
    }

    func edit(_ capture: Capture) {
        let editor = EditorWindowController(capture: capture, settings: settings)
        editor.onClose = { [weak self, weak editor] in
            self?.open.removeAll { $0 === editor }
        }
        open.append(editor)
        editor.present()
    }
}
