import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.displayID == displayID }
    }

    /// The screen containing the mouse pointer, falling back to the main screen.
    static var underMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) } ?? main
    }

    /// Height of the primary display (the one with the menu bar), which anchors the
    /// flip between AppKit and Quartz global coordinates.
    static var primaryHeight: CGFloat {
        screens.first?.frame.height ?? 0
    }
}
