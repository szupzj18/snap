import ServiceManagement
import SwiftUI

/// "Open at login", backed by the system's login items rather than a stored preference.
struct LaunchAtLoginToggle: View {
    @State private var status = SMAppService.mainApp.status
    @State private var errorMessage: String?

    var body: some View {
        Toggle("Open Snap at login", isOn: Binding(
            get: { status == .enabled || status == .requiresApproval },
            set: { setEnabled($0) }
        ))
        if status == .requiresApproval {
            HStack {
                Text("macOS needs your OK in Login Items.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
            }
            .font(.callout)
        }
        if let errorMessage {
            Text(errorMessage).font(.callout).foregroundStyle(.red)
        }
    }

    private func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        status = SMAppService.mainApp.status
    }
}
