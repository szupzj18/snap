import AppKit
import SnapCapture
import SwiftUI

/// Walks the user through granting Screen Recording access.
@MainActor
final class PermissionOnboardingController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            window = HostingWindow.make(
                title: "Welcome to Snap",
                rootView: PermissionOnboardingView(close: { [weak self] in self?.window?.close() })
            )
        }
        HostingWindow.present(window!)
    }
}

struct PermissionOnboardingView: View {
    let close: () -> Void

    @State private var isGranted = ScreenRecordingPermission.isGranted
    @State private var didOpenSettings = false
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow Screen Recording").font(.title2.bold())
                    Text("Snap needs it to take screenshots.").foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("1. Click **Open System Settings**.")
                Text("2. Turn on **Snap** under *Screen & System Audio Recording*.")
                Text("3. If macOS asks, or Snap still can't capture, click **Relaunch Snap**.")
            }

            Text("Snap only reads the screen when you take a screenshot. Nothing leaves your Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)

            statusRow

            HStack {
                if isGranted {
                    Spacer()
                    Button("Done", action: close).keyboardShortcut(.defaultAction)
                } else {
                    Button("Later", action: close)
                    Spacer()
                    if didOpenSettings {
                        Button("Relaunch Snap") { AppRelauncher.relaunch() }
                    }
                    Button("Open System Settings") {
                        // The first request shows the system prompt and adds Snap to the list.
                        ScreenRecordingPermission.request()
                        ScreenRecordingPermission.openSystemSettings()
                        didOpenSettings = true
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .onReceive(poll) { _ in isGranted = ScreenRecordingPermission.isGranted }
    }

    @ViewBuilder
    private var statusRow: some View {
        if isGranted {
            Label("Permission granted. You're all set.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Label("Not granted yet", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}
