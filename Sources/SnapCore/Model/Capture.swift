import CoreGraphics
import Foundation

/// A finished screenshot plus where it came from.
public struct Capture: Identifiable {
    public let id = UUID()
    public let image: CGImage
    /// Pixels per point of the display the image was taken on (2 on Retina displays).
    public let scale: CGFloat
    public let mode: CaptureMode
    /// The captured area in Quartz global coordinates (points).
    public let sourceRect: CGRect
    public let displayID: CGDirectDisplayID?
    /// Name of the app that owns the captured window, for window captures.
    public let appName: String?
    public let date: Date

    public init(
        image: CGImage,
        scale: CGFloat,
        mode: CaptureMode,
        sourceRect: CGRect,
        displayID: CGDirectDisplayID?,
        appName: String? = nil,
        date: Date = Date()
    ) {
        self.image = image
        self.scale = scale
        self.mode = mode
        self.sourceRect = sourceRect
        self.displayID = displayID
        self.appName = appName
        self.date = date
    }

    /// Image size in points, i.e. how large it looked on screen.
    public var pointSize: CGSize {
        CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }
}
