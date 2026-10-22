import AppKit
import KeyboardShortcuts
import SnapkitCapture
import SnapkitCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            window = HostingWindow.make(title: "Snapkit Settings", rootView: SettingsView(settings: .shared))
        }
        HostingWindow.present(window!)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 520)
        .fixedSize()
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var hasPermission = ScreenRecordingPermission.isGranted

    var body: some View {
        Form {
            Section("Saving") {
                LabeledContent("Folder") {
                    HStack {
                        Text(settings.saveDirectory.abbreviatedPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                TextField("File name", text: $settings.filenameTemplate)
                LabeledContent("Preview") {
                    Text(previewFilename + ".png").foregroundStyle(.secondary)
                }
                Text(FilenameFormatter.tokens.map { "\($0.token)  \($0.meaning)" }.joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("After capture") {
                ForEach(AfterCaptureAction.allCases) { action in
                    Toggle(action.title, isOn: binding(for: action))
                }
            }

            Section("Window capture") {
                Toggle("Add shadow", isOn: $settings.windowShadow)
            }

            Section("Permissions") {
                LabeledContent("Screen Recording") {
                    if hasPermission {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open System Settings") {
                            ScreenRecordingPermission.request()
                            ScreenRecordingPermission.openSystemSettings()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { hasPermission = ScreenRecordingPermission.isGranted }
    }

    private var previewFilename: String {
        FilenameFormatter.filename(template: settings.filenameTemplate, date: Date(), mode: .window, appName: "Safari")
    }

    private func binding(for action: AfterCaptureAction) -> Binding<Bool> {
        Binding(
            get: { settings.afterCapture.contains(action) },
            set: { isOn in
                if isOn { settings.afterCapture.insert(action) } else { settings.afterCapture.remove(action) }
            }
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.saveDirectory
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectory = url
        }
    }
}

private struct ShortcutSettingsView: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Capture Area", name: .captureArea)
                KeyboardShortcuts.Recorder("Capture Window", name: .captureWindow)
                KeyboardShortcuts.Recorder("Capture Fullscreen", name: .captureFullscreen)
            } footer: {
                Text("⌘⇧3, ⌘⇧4 and ⌘⇧5 belong to macOS. To use them for Snapkit, first turn them off in System Settings › Keyboard › Keyboard Shortcuts › Screenshots.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private extension URL {
    var abbreviatedPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
