import AppKit

/// A borderless panel covering one screen, above everything including the menu bar and Dock.
final class OverlayPanel: NSPanel {
    let targetScreen: NSScreen

    init(screen: NSScreen) {
        targetScreen = screen
        // Non-activating so the panel can become key (and get Esc) even if macOS declines
        // to activate us, which macOS 14's cooperative activation is allowed to do.
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        // Opt in explicitly so clicks on fully transparent areas still reach us.
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Shows overlay panels on every screen and restores the previously active app afterwards.
@MainActor
final class OverlayPresenter {
    private(set) var panels: [OverlayPanel] = []
    private var previousApp: NSRunningApplication?

    func show(_ panels: [OverlayPanel]) {
        self.panels = panels
        previousApp = NSWorkspace.shared.frontmostApplication
        // Being the active app lets us own the cursor.
        NSApp.activate()
        let keyScreen = NSScreen.underMouse
        for panel in panels {
            if panel.targetScreen == keyScreen {
                panel.makeKeyAndOrderFront(nil)
            } else {
                panel.orderFrontRegardless()
            }
        }
        NSCursor.crosshair.set()
    }

    func dismiss() {
        for panel in panels {
            panel.orderOut(nil)
        }
        panels = []
        NSCursor.arrow.set()
        if let previousApp, previousApp != NSRunningApplication.current {
            previousApp.activate()
        }
        previousApp = nil
    }
}
