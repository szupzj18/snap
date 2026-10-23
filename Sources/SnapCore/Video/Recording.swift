import AVFoundation
import CoreGraphics
import Foundation

/// A finished screen recording.
public struct Recording {
    public let id = UUID()
    /// Where the movie is now; changes when it's saved.
    public var url: URL
    /// First frame, for previews.
    public let thumbnail: CGImage
    /// Pixels per point of the recorded display.
    public let scale: CGFloat
    public let duration: TimeInterval
    /// The recorded area in Quartz global coordinates (points).
    public let sourceRect: CGRect
    public let displayID: CGDirectDisplayID?
    public let date: Date

    public init(url: URL, thumbnail: CGImage, scale: CGFloat, duration: TimeInterval,
                sourceRect: CGRect, displayID: CGDirectDisplayID?, date: Date = Date()) {
        self.url = url
        self.thumbnail = thumbnail
        self.scale = scale
        self.duration = duration
        self.sourceRect = sourceRect
        self.displayID = displayID
        self.date = date
    }

    /// Reads duration and first frame from a finished movie file.
    public static func load(url: URL, scale: CGFloat, sourceRect: CGRect, displayID: CGDirectDisplayID?) async throws -> Recording {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let thumbnail = try await VideoFrames.image(from: asset, at: .zero, maxPixelSize: nil)
        return Recording(url: url, thumbnail: thumbnail, scale: scale, duration: duration, sourceRect: sourceRect, displayID: displayID)
    }

    /// "0:07", "1:23".
    public static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
