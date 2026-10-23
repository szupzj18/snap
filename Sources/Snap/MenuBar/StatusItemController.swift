import AppKit
import KeyboardShortcuts
import SnapCore

/// Owns the menu bar icon and its menu.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let coordinator: CaptureCoordinator
    private let settingsWindow: SettingsWindowController
    private let historyWindow: HistoryWindowController
    private let recording: RecordingController
    private lazy var mainMenu = makeMenu()
    private var recordingTimer: Timer?

    init(
        coordinator: CaptureCoordinator,
        settingsWindow: SettingsWindowController,
        historyWindow: HistoryWindowController,
        recording: RecordingController
    ) {
        self.coordinator = coordinator
        self.settingsWindow = settingsWindow
        self.historyWindow = historyWindow
        self.recording = recording
        super.init()
        showIdle()
    }

    // MARK: Recording state

    /// While recording, the icon turns into a stop button with the elapsed time.
    func update(for state: RecordingController.State) {
        recordingTimer?.invalidate()
        recordingTimer = nil
        guard case let .recording(since) = state else {
            showIdle()
            return
        }
        statusItem.menu = makeRecordingMenu()
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop recording")
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        let tick = { [weak button] in
            button?.title = " " + Recording.formatDuration(Date().timeIntervalSince(since))
        }
        tick()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
    }

    private func showIdle() {
        statusItem.menu = mainMenu
        guard let button = statusItem.button else { return }
        button.image = MenuBarIcon.make()
        button.title = ""
        button.imagePosition = .imageOnly
    }

    private func makeRecordingMenu() -> NSMenu {
        let menu = NSMenu()
        let stop = NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "")
        stop.target = self
        stop.setShortcut(for: .recordScreen)
        menu.addItem(stop)
        let cancel = NSMenuItem(title: "Cancel Recording", action: #selector(cancelRecording), keyEquivalent: "")
        cancel.target = self
        menu.addItem(cancel)
        return menu
    }

    @objc private func stopRecording() {
        recording.toggle()
    }

    @objc private func cancelRecording() {
        recording.cancel()
    }

    // MARK: Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for mode in CaptureMode.allCases {
            if mode == .recording { menu.addItem(.separator()) }
            let title = mode == .recording ? "Record Screen" : "Capture \(mode.title)"
            let item = NSMenuItem(title: title, action: #selector(captureFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.setShortcut(for: mode.shortcutName)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let history = NSMenuItem(title: "History…", action: #selector(openHistory), keyEquivalent: "")
        history.target = self
        menu.addItem(history)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Snap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func openHistory() {
        historyWindow.show()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func captureFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = CaptureMode(rawValue: raw) else { return }
        // Let the menu finish fading out so it doesn't end up in the screenshot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [coordinator] in
            coordinator.start(mode)
        }
    }
}
