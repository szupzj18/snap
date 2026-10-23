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
    private let updates: UpdateChecker
    private lazy var mainMenu = makeMenu()
    private var updateItems: [NSMenuItem] = []
    private var recordingTimer: Timer?

    init(
        coordinator: CaptureCoordinator,
        settingsWindow: SettingsWindowController,
        historyWindow: HistoryWindowController,
        recording: RecordingController,
        updates: UpdateChecker
    ) {
        self.coordinator = coordinator
        self.settingsWindow = settingsWindow
        self.historyWindow = historyWindow
        self.recording = recording
        self.updates = updates
        super.init()
        showIdle()
    }

    // MARK: Recording state

    /// While recording, the icon turns into a stop button with the elapsed time; while paused,
    /// a pause symbol with the time standing still.
    func update(for state: RecordingController.State) {
        recordingTimer?.invalidate()
        recordingTimer = nil
        guard state == .recording || state == .paused else {
            showIdle()
            return
        }
        let paused = state == .paused
        statusItem.menu = makeRecordingMenu(paused: paused)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: paused ? "pause.circle.fill" : "stop.circle.fill",
                               accessibilityDescription: paused ? "Recording paused" : "Stop recording")
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        let tick = { [weak button, recording] in
            button?.title = " " + Recording.formatDuration(recording.elapsed)
        }
        tick()
        guard !paused else { return }
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

    private func makeRecordingMenu(paused: Bool) -> NSMenu {
        let menu = NSMenu()
        let stop = NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "")
        stop.target = self
        stop.setShortcut(for: .recordScreen)
        menu.addItem(stop)
        let pause = NSMenuItem(title: paused ? "Resume Recording" : "Pause Recording", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        let cancel = NSMenuItem(title: "Cancel Recording", action: #selector(cancelRecording), keyEquivalent: "")
        cancel.target = self
        menu.addItem(cancel)
        return menu
    }

    @objc private func stopRecording() {
        recording.toggle()
    }

    @objc private func togglePause() {
        recording.togglePause()
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
        let checkForUpdates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        checkForUpdates.target = self
        menu.addItem(checkForUpdates)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Snap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    /// Puts "Snap x.y.z Is Available…" at the top of the menu, or removes it.
    func showUpdate(_ release: GitHubRelease?) {
        updateItems.forEach { mainMenu.removeItem($0) }
        updateItems = []
        guard let release else { return }
        let item = ClosureMenuItem(title: "Snap \(release.version) Is Available…") { [weak self] in
            self?.updates.offer(release)
        }
        item.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
        let separator = NSMenuItem.separator()
        mainMenu.insertItem(separator, at: 0)
        mainMenu.insertItem(item, at: 0)
        updateItems = [item, separator]
    }

    @objc private func checkForUpdates() {
        Task { await updates.check(userInitiated: true) }
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
