import AppKit
import CoreGraphics

/// The Screen Recording (TCC) permission that ScreenCaptureKit needs.
public enum ScreenRecordingPermission {
    /// Whether access is granted. macOS may only report a fresh grant after the app relaunches.
    public static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Shows the system prompt the first time and adds the app to the list in System Settings.
    /// Later calls return immediately.
    @discardableResult
    public static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
