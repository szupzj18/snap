import AppKit
import SnapkitCapture
import SnapkitCore

/// Runs one capture at a time: checks permission, lets the user pick what to capture,
/// grabs the pixels and hands the result to the router.
@MainActor
final class CaptureCoordinator {
    private let service = ScreenshotService()
    private let onboarding: PermissionOnboardingController
    private let router: PostCaptureRouter
    private var isCapturing = false

    init(onboarding: PermissionOnboardingController, router: PostCaptureRouter) {
        self.onboarding = onboarding
        self.router = router
    }

    func start(_ mode: CaptureMode) {
        guard !isCapturing else { return }
        guard ScreenRecordingPermission.isGranted else {
            onboarding.show()
            return
        }
        isCapturing = true
        Task {
            defer { isCapturing = false }
            do {
                if let capture = try await capture(mode) {
                    router.handle(capture)
                }
            } catch CaptureError.permissionDenied {
                onboarding.show()
            } catch {
                ErrorPresenter.present(error)
            }
        }
    }

    /// Returns nil when the user cancels.
    private func capture(_ mode: CaptureMode) async throws -> Capture? {
        switch mode {
        case .fullscreen:
            return try await captureFullscreen()
        case .area:
            // Freeze first, then select: what the user sees is exactly what gets cropped.
            let snapshots = try await service.captureAllDisplays()
            return await AreaSelectionSession().run(snapshots: snapshots)
        case .window:
            return nil
        }
    }

    /// Captures the display under the mouse pointer.
    private func captureFullscreen() async throws -> Capture {
        guard let displayID = NSScreen.underMouse?.displayID else { throw CaptureError.displayNotFound }
        let snapshot = try await service.captureDisplay(displayID)
        return Capture(
            image: snapshot.image,
            scale: snapshot.scale,
            mode: .fullscreen,
            sourceRect: snapshot.frame,
            displayID: snapshot.displayID
        )
    }
}

@MainActor
enum ErrorPresenter {
    static func present(_ error: Error) {
        NSApp.activate()
        NSAlert(error: error).runModal()
    }
}
