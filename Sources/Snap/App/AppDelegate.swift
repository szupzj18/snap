import AppKit
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
    private lazy var router = PostCaptureRouter(
        settings: settings, actions: actions, quickAccess: quickAccess, pins: pins, editors: editors
    )
    private lazy var coordinator = CaptureCoordinator(settings: settings, onboarding: onboarding, router: router, actions: actions)
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        CaptureActions.removeDragFiles()
        statusItemController = StatusItemController(coordinator: coordinator, settingsWindow: settingsWindow)
        Hotkeys.register(coordinator)
        if !ScreenRecordingPermission.isGranted {
            onboarding.show()
        }
    }
}
