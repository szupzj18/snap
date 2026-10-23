import AppKit
import KeyboardShortcuts
import SnapCapture
import SnapCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            window = HostingWindow.make(title: "Snap Settings", rootView: SettingsView(settings: .shared))
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
            CaptureSettingsView(settings: settings)
                .tabItem { Label("Capture", systemImage: "camera.viewfinder") }
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
            Section("General") {
                LaunchAtLoginToggle()
                Toggle("Play a sound when capturing", isOn: $settings.playSound)
            }

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
                Picker("Close Quick Access after", selection: $settings.quickAccessAutoClose) {
                    Text("Never").tag(TimeInterval(0))
                    ForEach([3, 5, 10, 20], id: \.self) { seconds in
                        Text("\(seconds) seconds").tag(TimeInterval(seconds))
                    }
                }
                .disabled(!settings.afterCapture.contains(.showQuickAccess))
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

private struct CaptureSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("History") {
                Toggle("Keep a history of captures", isOn: $settings.historyEnabled)
                Picker("Keep the last", selection: $settings.historyLimit) {
                    ForEach([20, 50, 100, 200], id: \.self) { Text("\($0) captures").tag($0) }
                }
                .disabled(!settings.historyEnabled)
            }

            Section("Recording") {
                Picker("Frame rate", selection: $settings.recordingFPS) {
                    ForEach([15, 30, 60], id: \.self) { Text("\($0) fps").tag($0) }
                }
                Toggle("Show the pointer", isOn: $settings.recordingShowsCursor)
            }

            Section("Window capture") {
                Toggle("Add shadow", isOn: $settings.windowShadow)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutSettingsView: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Capture Area", name: .captureArea)
                KeyboardShortcuts.Recorder("Capture Window", name: .captureWindow)
                KeyboardShortcuts.Recorder("Capture Fullscreen", name: .captureFullscreen)
                KeyboardShortcuts.Recorder("Capture Text (OCR)", name: .captureText)
                KeyboardShortcuts.Recorder("Capture Scrolling", name: .captureScrolling)
                KeyboardShortcuts.Recorder("Record Screen", name: .recordScreen)
            } footer: {
                Text("⌘⇧3, ⌘⇧4 and ⌘⇧5 belong to macOS. To use them for Snap, first turn them off in System Settings › Keyboard › Keyboard Shortcuts › Screenshots.")
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
