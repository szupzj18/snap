import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum VideoExportError: Error {
    case noFrames
    case encodingFailed
}

/// Frame extraction and GIF export for recordings.
public enum VideoFrames {
    static func image(from asset: AVAsset, at time: CMTime, maxPixelSize: CGFloat?) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)
        if let maxPixelSize {
            generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        }
        return try await generator.image(at: time).image
    }

    /// Writes an endlessly looping GIF of the movie at `fps`, scaled so neither side exceeds
    /// `maxPixelSize`. Returns the number of frames written.
    @discardableResult
    public static func exportGIF(from videoURL: URL, to gifURL: URL, fps: Double = 15, maxPixelSize: CGFloat = 960) async throws -> Int {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        let count = max(1, Int((duration * fps).rounded(.down)))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        // A little slack lets the generator reuse decoded frames instead of seeking for each one.
        let tolerance = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        guard let destination = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw VideoExportError.encodingFailed
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 1 / fps,
                kCGImagePropertyGIFUnclampedDelayTime: 1 / fps,
            ],
        ] as CFDictionary

        var written = 0
        for index in 0..<count {
            let time = CMTime(seconds: Double(index) / fps, preferredTimescale: 600)
            guard let frame = try? await generator.image(at: time).image else { continue }
            CGImageDestinationAddImage(destination, frame, frameProperties)
            written += 1
        }
        guard written > 0 else { throw VideoExportError.noFrames }
        guard CGImageDestinationFinalize(destination) else { throw VideoExportError.encodingFailed }
        return written
    }
}
