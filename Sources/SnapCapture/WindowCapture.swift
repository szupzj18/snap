import CoreGraphics
import ScreenCaptureKit

/// A window the user can pick for a window capture.
public struct PickableWindow {
    public let windowID: CGWindowID
    /// Window bounds in Quartz global coordinates (points), without the shadow.
    public let frame: CGRect
    public let title: String?
    public let appName: String?
    let scWindow: SCWindow
}

extension ScreenshotService {
    /// Normal app windows that are on screen, frontmost first.
    public func pickableWindows() async throws -> [PickableWindow] {
        let content = try await shareableContent()
        let order = Self.frontToBackOrder()
        return content.windows
            .filter { window in
                window.windowLayer == 0
                    && window.isOnScreen
                    && window.frame.width > 20 && window.frame.height > 20
                    && window.owningApplication.map { $0.bundleIdentifier != ownBundleIdentifier } ?? false
                    && order[window.windowID] != nil
            }
            .sorted { order[$0.windowID]! < order[$1.windowID]! }
            .map {
                PickableWindow(
                    windowID: $0.windowID,
                    frame: $0.frame,
                    title: $0.title,
                    appName: $0.owningApplication?.applicationName,
                    scWindow: $0
                )
            }
    }

    /// Captures a single window on a transparent background, keeping its rounded corners.
    ///
    /// The system shadow is left out: ScreenCaptureKit sizes the image to the window and would
    /// clip it. Use `WindowShadow` to add one.
    public func captureWindow(_ window: PickableWindow) async throws -> (image: CGImage, scale: CGFloat) {
        let filter = SCContentFilter(desktopIndependentWindow: window.scWindow)
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.shouldBeOpaque = false
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.width = Int((filter.contentRect.width * scale).rounded())
        configuration.height = Int((filter.contentRect.height * scale).rounded())
        let image = try await mapErrors {
            try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        }
        return (image, scale)
    }

    /// ScreenCaptureKit doesn't promise any window order, so take z-order from the window server.
    private static func frontToBackOrder() -> [CGWindowID: Int] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] ?? []
        var order: [CGWindowID: Int] = [:]
        for (index, entry) in info.enumerated() {
            if let number = entry[kCGWindowNumber] as? CGWindowID {
                order[number] = index
            }
        }
        return order
    }
}
