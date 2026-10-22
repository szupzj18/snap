import AppKit
import SnapkitCapture
import SnapkitCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let onboarding = PermissionOnboardingController()
    private let settingsWindow = SettingsWindowController()
    private lazy var router = PostCaptureRouter(settings: .shared)
    private lazy var coordinator = CaptureCoordinator(onboarding: onboarding, router: router)
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        statusItemController = StatusItemController(coordinator: coordinator, settingsWindow: settingsWindow)
        Hotkeys.register(coordinator)
        if !ScreenRecordingPermission.isGranted {
            onboarding.show()
        }
    }
}
