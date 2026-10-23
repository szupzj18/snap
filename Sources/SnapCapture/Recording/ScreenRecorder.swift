import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// Records an area of one display to an MP4 with ScreenCaptureKit.
public final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    public struct Options {
        public var fps: Int
        public var showsCursor: Bool
        /// Sound playing on the Mac (not Snap's own).
        public var systemAudio: Bool
        public var microphone: Bool

        public init(fps: Int = 30, showsCursor: Bool = true, systemAudio: Bool = false, microphone: Bool = false) {
            self.fps = fps
            self.showsCursor = showsCursor
            self.systemAudio = systemAudio
            self.microphone = microphone
        }
    }

    /// Longest side of the video in pixels. H.264 encoders top out around 4K.
    static let maximumDimension = 3840

    private let service: ScreenshotService
    private let queue = DispatchQueue(label: "Snap.ScreenRecorder")
    private var stream: SCStream?
    private var writer: MovieWriter?
    private var microphone: MicrophoneCapture?
    private var hasTwoAudioTracks = false
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
        if options.microphone, !(await MicrophoneCapture.requestAccess()) {
            throw RecordingError.microphoneDenied
        }
        let (filter, local) = try await service.areaFilter(displayID: displayID, rect: rect)
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
        configuration.capturesAudio = options.systemAudio
        if options.systemAudio {
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            configuration.excludesCurrentProcessAudio = true
        }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var audioTracks: [MovieWriter.Track] = []
        if options.systemAudio { audioTracks.append(.systemAudio) }
        if options.microphone { audioTracks.append(.microphone) }
        hasTwoAudioTracks = audioTracks.count == 2
        let writer = try MovieWriter(url: url, width: size.width, height: size.height, fps: options.fps, audioTracks: audioTracks)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if options.systemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }
        if options.microphone {
            // Same queue as the stream, so the writer is only ever touched from one place.
            microphone = try MicrophoneCapture(queue: queue) { [weak self] sample in
                self?.writer?.append(sample, to: .microphone)
            }
        }
        self.writer = writer
        self.stream = stream
        outputURL = url
        try await service.mapErrors { try await stream.startCapture() }
        microphone?.start()
    }

    /// Stops and returns the finished movie.
    public func stop() async throws -> URL {
        guard let stream, let outputURL else { throw RecordingError.writeFailed }
        try? await stream.stopCapture()
        microphone?.stop()
        microphone = nil
        let end = CMClockGetTime(CMClockGetHostTimeClock())
        self.stream = nil
        try await finishWriter(at: end)
        if hasTwoAudioTracks {
            try await AudioMixdown.mergeAudioTracks(in: outputURL)
        }
        return outputURL
    }

    /// Stops taking frames and sound until `resume()`; the pause leaves no gap in the movie.
    public func pause() {
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        queue.async { self.writer?.pause(at: now) }
    }

    public func resume() {
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        queue.async { self.writer?.resume(at: now) }
    }

    /// Stops and throws the recording away.
    public func cancel() async {
        try? await stream?.stopCapture()
        microphone?.stop()
        microphone = nil
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
        let writer: MovieWriter? = queue.sync { self.writer }
        self.writer = nil
        guard let writer else { throw RecordingError.writeFailed }
        try await writer.finish(at: end)
    }

    // MARK: SCStreamOutput

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            guard Self.isCompleteFrame(sampleBuffer) else { return }
            writer?.append(sampleBuffer, to: .video)
        case .audio:
            writer?.append(sampleBuffer, to: .systemAudio)
        default:
            break
        }
    }

    /// ScreenCaptureKit also sends status-only buffers (e.g. "idle" when nothing changed).
    static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
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
