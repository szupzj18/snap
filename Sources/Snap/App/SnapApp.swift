import AppKit

@main
enum SnapApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Menu bar app: no Dock icon even when launched outside the .app bundle (e.g. `swift run`).
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
