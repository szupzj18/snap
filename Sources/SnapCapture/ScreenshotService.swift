import AppKit
import CoreGraphics
import ScreenCaptureKit

public enum CaptureError: LocalizedError {
    case permissionDenied
    case displayNotFound

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: "Snap doesn't have Screen Recording permission."
        case .displayNotFound: "The display to capture is no longer available."
        }
    }
}

/// One display's pixels, captured at its native resolution.
public struct DisplaySnapshot {
    public let displayID: CGDirectDisplayID
    /// Display bounds in Quartz global coordinates (points).
    public let frame: CGRect
    /// Pixels per point.
    public let scale: CGFloat
    public let image: CGImage
}

/// Takes still screenshots with ScreenCaptureKit.
public final class ScreenshotService {
    let ownBundleIdentifier: String?
    /// Asked before every capture, so a settings change applies to the next one.
    let hidesDesktopIcons: () -> Bool

    public init(ownBundleIdentifier: String? = Bundle.main.bundleIdentifier, hidesDesktopIcons: @escaping () -> Bool = { false }) {
        self.ownBundleIdentifier = ownBundleIdentifier
        self.hidesDesktopIcons = hidesDesktopIcons
    }

    /// Captures every connected display in parallel.
    public func captureAllDisplays() async throws -> [DisplaySnapshot] {
        let content = try await shareableContent()
        let excluded = excludedWindows(in: content)
        return try await withThrowingTaskGroup(of: DisplaySnapshot.self) { group in
            for display in content.displays {
                group.addTask { try await self.capture(display, excluding: excluded) }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
    }

    public func captureDisplay(_ displayID: CGDirectDisplayID) async throws -> DisplaySnapshot {
        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        return try await capture(display, excluding: excludedWindows(in: content))
    }

    private func capture(_ display: SCDisplay, excluding excluded: [SCWindow]) async throws -> DisplaySnapshot {
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = Int((CGFloat(display.width) * scale).rounded())
        configuration.height = Int((CGFloat(display.height) * scale).rounded())
        configuration.captureResolution = .best
        configuration.showsCursor = false
        let image = try await mapErrors {
            try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        }
        return DisplaySnapshot(displayID: display.displayID, frame: display.frame, scale: scale, image: image)
    }

    /// A filter for one display without our own windows, plus `rect` (Quartz global points)
    /// in that display's local coordinates, for streams that capture part of a display.
    func areaFilter(displayID: CGDirectDisplayID, rect: CGRect) async throws -> (filter: SCContentFilter, localRect: CGRect) {
        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows(in: content))
        let local = rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            .intersection(CGRect(origin: .zero, size: display.frame.size))
        guard local.width >= 2, local.height >= 2 else { throw CaptureError.displayNotFound }
        return (filter, local)
    }

    func shareableContent() async throws -> SCShareableContent {
        try await mapErrors {
            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
    }

    /// Windows left out of display captures: always our own, plus the desktop icons when asked.
    func excludedWindows(in content: SCShareableContent) -> [SCWindow] {
        var excluded = ownWindows(in: content)
        if hidesDesktopIcons() {
            excluded += content.windows.filter {
                Self.isDesktopClutter(layer: $0.windowLayer, bundleIdentifier: $0.owningApplication?.bundleIdentifier)
            }
        }
        return excluded
    }

    /// Finder's desktop icons sit at the desktop-icon level; desktop widgets (macOS 14+) belong to
    /// Notification Center below the normal level. The wallpaper (Dock, desktop level) stays.
    static func isDesktopClutter(layer: Int, bundleIdentifier: String?) -> Bool {
        if layer == Int(CGWindowLevelForKey(.desktopIconWindow)) { return true }
        return bundleIdentifier == "com.apple.notificationcenterui" && layer < Int(CGWindowLevelForKey(.normalWindow))
    }

    /// Our own windows (overlays, previews, pins) never belong in a screenshot.
    /// The menu bar icon stays, like every other app's.
    func ownWindows(in content: SCShareableContent) -> [SCWindow] {
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        return content.windows.filter {
            $0.owningApplication?.bundleIdentifier == ownBundleIdentifier && $0.windowLayer != statusLevel
        }
    }

    func mapErrors<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as NSError where error.domain == SCStreamErrorDomain && error.code == SCStreamError.userDeclined.rawValue {
            throw CaptureError.permissionDenied
        }
    }
}
