import AppKit
import SwiftUI

@MainActor
enum HostingWindow {
    /// A regular titled window hosting a SwiftUI view. Callers keep the reference.
    static func make<Content: View>(title: String, rootView: Content, resizable: Bool = false) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.title = title
        var style: NSWindow.StyleMask = [.titled, .closable]
        if resizable { style.formUnion([.resizable, .miniaturizable]) }
        window.styleMask = style
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    /// Brings a window to the front. Menu bar apps are never active on their own,
    /// so the app has to be activated too.
    static func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

enum AppRelauncher {
    /// Starts a fresh copy of the app once this one has quit. macOS often only applies a new
    /// Screen Recording grant to processes started after it.
    @MainActor
    static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.1; done; open \"$0\"", path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
