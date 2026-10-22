import AppKit
import SnapkitCore

/// Owns the menu bar icon and its menu.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let coordinator: CaptureCoordinator

    init(coordinator: CaptureCoordinator) {
        self.coordinator = coordinator
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Snapkit")
            button.image?.isTemplate = true
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
            item.isEnabled = mode == .fullscreen
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: nil, keyEquivalent: ",")
        settings.isEnabled = false
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Snapkit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func captureFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = CaptureMode(rawValue: raw) else { return }
        // Let the menu finish fading out so it doesn't end up in the screenshot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [coordinator] in
            coordinator.start(mode)
        }
    }
}
