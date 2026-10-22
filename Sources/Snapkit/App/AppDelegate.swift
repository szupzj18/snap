import AppKit
import SnapkitCapture
import SnapkitCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let onboarding = PermissionOnboardingController()
    private let settingsWindow = SettingsWindowController()
    private lazy var actions = CaptureActions(settings: settings)
    private lazy var pins = PinController(actions: actions)
    private lazy var quickAccess = QuickAccessController(settings: settings, actions: actions, pins: pins)
    private lazy var router = PostCaptureRouter(settings: settings, actions: actions, quickAccess: quickAccess, pins: pins)
    private lazy var coordinator = CaptureCoordinator(settings: settings, onboarding: onboarding, router: router)
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
