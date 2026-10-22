import AppKit
import SnapkitCore

/// Decides what happens to a finished capture, based on the user's after-capture settings.
@MainActor
final class PostCaptureRouter {
    private let settings: AppSettings
    private let actions: CaptureActions
    private let quickAccess: QuickAccessController

    init(settings: AppSettings, actions: CaptureActions, quickAccess: QuickAccessController) {
        self.settings = settings
        self.actions = actions
        self.quickAccess = quickAccess
    }

    func handle(_ capture: Capture) {
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
        if enabled.contains(.showQuickAccess) {
            quickAccess.show(capture, savedURL: savedURL)
        }
    }
}
