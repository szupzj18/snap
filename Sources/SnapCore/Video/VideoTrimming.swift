import AVFoundation

public enum VideoTrimming {
    /// Cuts `url` down to `range` in place, copying the video and audio without re-encoding.
    public static func trim(_ url: URL, to range: CMTimeRange) async throws {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw VideoExportError.encodingFailed
        }
        let trimmed = url.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).\(url.pathExtension)")
        session.outputURL = trimmed
        session.outputFileType = .mp4
        session.timeRange = range
        await session.export()
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: trimmed)
            throw session.error ?? VideoExportError.encodingFailed
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: trimmed)
    }
}
