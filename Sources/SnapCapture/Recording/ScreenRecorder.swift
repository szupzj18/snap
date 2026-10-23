import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// Records an area of one display to an MP4 with ScreenCaptureKit.
public final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    public struct Options {
        public var fps: Int
        public var showsCursor: Bool

        public init(fps: Int = 30, showsCursor: Bool = true) {
            self.fps = fps
            self.showsCursor = showsCursor
        }
    }

    /// Longest side of the video in pixels. H.264 encoders top out around 4K.
    static let maximumDimension = 3840

    private let service: ScreenshotService
    private let queue = DispatchQueue(label: "Snap.ScreenRecorder")
    private var stream: SCStream?
    private var writer: VideoFileWriter?
    private var outputURL: URL?
    /// Called on the main queue if the stream stops by itself (e.g. the display went away).
    public var onUnexpectedStop: ((Error) -> Void)?

    /// Pixels per point of the recording.
    public private(set) var scale: CGFloat = 1

    public init(service: ScreenshotService = ScreenshotService()) {
        self.service = service
    }

    /// Starts recording `rect` (Quartz global points) on `displayID` into `url`.
    public func start(displayID: CGDirectDisplayID, rect: CGRect, options: Options, to url: URL) async throws {
        let content = try await service.shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let filter = SCContentFilter(display: display, excludingWindows: service.ownWindows(in: content))
        let local = rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            .intersection(CGRect(origin: .zero, size: display.frame.size))
        guard local.width >= 2, local.height >= 2 else { throw CaptureError.displayNotFound }
        let size = Self.pixelSize(for: local.size, scale: CGFloat(filter.pointPixelScale))
        scale = CGFloat(size.width) / local.width

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = local
        configuration.width = size.width
        configuration.height = size.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.fps))
        configuration.showsCursor = options.showsCursor
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 6
        configuration.capturesAudio = false

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let writer = try VideoFileWriter(url: url, width: size.width, height: size.height, fps: options.fps)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.writer = writer
        self.stream = stream
        outputURL = url
        try await service.mapErrors { try await stream.startCapture() }
    }

    /// Stops and returns the finished movie.
    public func stop() async throws -> URL {
        guard let stream, let outputURL else { throw RecordingError.writeFailed }
        try? await stream.stopCapture()
        let end = CMClockGetTime(CMClockGetHostTimeClock())
        self.stream = nil
        try await finishWriter(at: end)
        return outputURL
    }

    /// Stops and throws the recording away.
    public func cancel() async {
        try? await stream?.stopCapture()
        stream = nil
        queue.sync { writer?.cancel() }
        writer = nil
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
    }

    /// Even pixel dimensions (H.264 needs them), scaled down if longer than `maximumDimension`.
    static func pixelSize(for points: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        var scale = scale
        let longest = max(points.width, points.height) * scale
        if longest > CGFloat(maximumDimension) {
            scale *= CGFloat(maximumDimension) / longest
        }
        func even(_ value: CGFloat) -> Int { max(2, Int(value.rounded(.down)) & ~1) }
        return (even(points.width * scale), even(points.height * scale))
    }

    private func finishWriter(at end: CMTime) async throws {
        // All frames are appended on `queue`; finish there too, after any frame in flight.
        let writer: VideoFileWriter? = queue.sync { self.writer }
        self.writer = nil
        guard let writer else { throw RecordingError.writeFailed }
        try await writer.finish(at: end)
    }

    // MARK: SCStreamOutput

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, Self.isCompleteFrame(sampleBuffer) else { return }
        writer?.append(sampleBuffer)
    }

    /// ScreenCaptureKit also sends status-only buffers (e.g. "idle" when nothing changed).
    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else { return false }
        return status == .complete
    }

    // MARK: SCStreamDelegate

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onUnexpectedStop?(error)
        }
    }
}
