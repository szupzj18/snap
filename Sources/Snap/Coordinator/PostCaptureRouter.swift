import AppKit
import SnapCore

/// Decides what happens to a finished capture, based on the user's after-capture settings.
@MainActor
final class PostCaptureRouter {
    private let settings: AppSettings
    private let actions: CaptureActions
    private let quickAccess: QuickAccessController
    private let pins: PinController
    private let editors: EditorPresenter
    private let history: CaptureHistory

    init(
        settings: AppSettings,
        actions: CaptureActions,
        quickAccess: QuickAccessController,
        pins: PinController,
        editors: EditorPresenter,
        history: CaptureHistory
    ) {
        self.settings = settings
        self.actions = actions
        self.quickAccess = quickAccess
        self.pins = pins
        self.editors = editors
        self.history = history
    }

    func handle(_ capture: Capture) {
        if settings.playSound { CaptureSound.play() }
        if settings.historyEnabled {
            Task { [history] in
                do { try await history.add(capture) } catch { NSLog("Snap: couldn't add capture to history: \(error)") }
            }
        }
        let enabled = settings.afterCapture
        var savedURL: URL?
        do {
            if enabled.contains(.save) {
                savedURL = try actions.save(capture)
            }
            if enabled.contains(.copyToClipboard) {
                try actions.copy(capture)
            }
        } catch {
            ErrorPresenter.present(error)
        }
        if enabled.contains(.openEditor) {
            editors.edit(capture)
        }
        if enabled.contains(.pin) {
            pins.pin(capture)
        }
        if enabled.contains(.showQuickAccess) {
            quickAccess.show(capture, savedURL: savedURL)
        } else {
            confirmWithoutQuickAccess(saved: savedURL, copied: enabled.contains(.copyToClipboard))
        }
    }

    /// Without the preview, a silent save or copy would leave the user guessing.
    private func confirmWithoutQuickAccess(saved: URL?, copied: Bool) {
        switch (saved, copied) {
        case let (url?, true): Toast.show("Saved \(url.lastPathComponent) and copied", systemImage: "checkmark.circle")
        case let (url?, false): Toast.show("Saved \(url.lastPathComponent)", systemImage: "checkmark.circle")
        case (nil, true): Toast.show("Copied to clipboard", systemImage: "doc.on.clipboard")
        case (nil, false): break
        }
    }

    /// Recordings honour save, copy and Quick Access; the editor, pins and history are for images.
    func handle(_ recording: Recording) {
        let enabled = settings.afterCapture
        var recording = recording
        var saved = false
        do {
            // Without Quick Access nothing else would keep the file, so save it regardless.
            if enabled.contains(.save) || !enabled.contains(.showQuickAccess) {
                recording.url = try actions.saveRecording(recording)
                saved = true
            }
            if enabled.contains(.copyToClipboard) {
                actions.copyFile(recording.url)
            }
        } catch {
            ErrorPresenter.present(error)
        }
        if enabled.contains(.showQuickAccess) {
            quickAccess.show(recording, saved: saved)
        } else {
            confirmWithoutQuickAccess(saved: saved ? recording.url : nil, copied: enabled.contains(.copyToClipboard))
        }
    }
}
