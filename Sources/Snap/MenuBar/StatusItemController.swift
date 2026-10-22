import AppKit
import KeyboardShortcuts
import SnapCore

/// Owns the menu bar icon and its menu.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let coordinator: CaptureCoordinator
    private let settingsWindow: SettingsWindowController
    private let historyWindow: HistoryWindowController

    init(coordinator: CaptureCoordinator, settingsWindow: SettingsWindowController, historyWindow: HistoryWindowController) {
        self.coordinator = coordinator
        self.settingsWindow = settingsWindow
        self.historyWindow = historyWindow
        super.init()
        if let button = statusItem.button {
            button.image = MenuBarIcon.make()
        }
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for mode in CaptureMode.allCases {
            let item = NSMenuItem(title: "Capture \(mode.title)", action: #selector(captureFromMenu(_:)), keyEquivalent: "")
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
