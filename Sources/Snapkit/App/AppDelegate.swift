import AppKit
import SnapkitCapture

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let onboarding = PermissionOnboardingController()
    private lazy var router = PostCaptureRouter()
    private lazy var coordinator = CaptureCoordinator(onboarding: onboarding, router: router)
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        statusItemController = StatusItemController(coordinator: coordinator)
        if !ScreenRecordingPermission.isGranted {
            onboarding.show()
        }
    }
}
