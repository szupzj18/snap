import AppKit
import Combine
import SnapCapture
import SnapCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let onboarding = PermissionOnboardingController()
    private let settingsWindow = SettingsWindowController()
    private lazy var actions = CaptureActions(settings: settings)
    private lazy var editors = EditorPresenter(settings: settings)
    private lazy var pins = PinController(actions: actions, editors: editors)
    private lazy var quickAccess = QuickAccessController(settings: settings, actions: actions, pins: pins, editors: editors)
    private lazy var history = CaptureHistory(directory: CaptureHistory.defaultDirectory, limit: settings.historyLimit)
    private lazy var historyWindow = HistoryWindowController(history: history, handlers: historyHandlers())
    private lazy var router = PostCaptureRouter(
        settings: settings, actions: actions, quickAccess: quickAccess, pins: pins, editors: editors, history: history
    )
    private lazy var coordinator = CaptureCoordinator(settings: settings, onboarding: onboarding, router: router, actions: actions)
    private var statusItemController: StatusItemController?
    private var observations: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        CaptureActions.removeDragFiles()
        statusItemController = StatusItemController(coordinator: coordinator, settingsWindow: settingsWindow, historyWindow: historyWindow)
        settings.$historyLimit
            .sink { [weak self] limit in self?.history.limit = limit }
            .store(in: &observations)
        Hotkeys.register(coordinator)
        if !ScreenRecordingPermission.isGranted {
            onboarding.show()
        }
    }

    private func historyHandlers() -> HistoryHandlers {
        let restore: (HistoryEntry) -> Capture? = { [unowned self] entry in
            guard let capture = history.capture(for: entry) else {
                ErrorPresenter.present(CocoaError(.fileReadNoSuchFile))
                return nil
            }
            return capture
        }
        return HistoryHandlers(
            copy: { [unowned self] entry in
                guard let capture = restore(entry) else { return }
                do {
                    try actions.copy(capture)
                    Toast.show("Copied", systemImage: "doc.on.clipboard")
                } catch {
                    ErrorPresenter.present(error)
                }
            },
            edit: { [unowned self] entry in restore(entry).map(editors.edit) },
            pin: { [unowned self] entry in restore(entry).map(pins.pin) },
            reveal: { [unowned self] entry in actions.revealInFinder(history.fileURL(for: entry)) }
        )
    }
}
