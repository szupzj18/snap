import CoreMedia
import ScreenCaptureKit
import SnapCore

/// Watches an area while the user scrolls it and stitches the frames into one tall image.
public final class ScrollingCapturer: NSObject, SCStreamOutput {
    /// Called on the main queue with the stitched height in pixels whenever it grows.
    public var onProgress: ((Int) -> Void)?

    private let service: ScreenshotService
    private let queue = DispatchQueue(label: "Snap.ScrollingCapturer")
    private var stream: SCStream?
    private var stitcher: ScrollStitcher?
    private var colorSpace: CGColorSpace?

    /// Pixels per point of the result.
    public private(set) var scale: CGFloat = 1

    public init(service: ScreenshotService = ScreenshotService()) {
        self.service = service
    }

    /// Starts watching `rect` (Quartz global points) on `displayID`.
    public func start(displayID: CGDirectDisplayID, rect: CGRect) async throws {
        let (filter, local) = try await service.areaFilter(displayID: displayID, rect: rect)
        scale = CGFloat(filter.pointPixelScale)
        let width = Int((local.width * scale).rounded())
        let height = Int((local.height * scale).rounded())

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = local
        configuration.width = width
        configuration.height = height
        // Frames only arrive when something changes; this caps how often while scrolling.
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 12)
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 4

        stitcher = ScrollStitcher(width: width, frameHeight: height)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
        try await service.mapErrors { try await stream.startCapture() }
    }

    /// Stops and returns the stitched image.
    public func finish() async throws -> CGImage {
        try? await stream?.stopCapture()
        stream = nil
        // Let any frame still being stitched finish first.
        let image: CGImage? = queue.sync {
            defer { stitcher = nil }
            return stitcher?.makeImage(
                colorSpace: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
            )
        }
        guard let image else { throw RecordingError.noFrames }
        return image
    }

    public func cancel() async {
        try? await stream?.stopCapture()
        stream = nil
        queue.sync { stitcher = nil }
    }

    // MARK: SCStreamOutput

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, ScreenRecorder.isCompleteFrame(sampleBuffer),
              let stitcher, !stitcher.isFull,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let frame = Self.frame(from: pixelBuffer) else { return }
        if colorSpace == nil {
            colorSpace = CVImageBufferGetColorSpace(pixelBuffer)?.takeUnretainedValue()
        }
        if stitcher.add(frame) {
            let height = stitcher.height
            DispatchQueue.main.async { [weak self] in self?.onProgress?(height) }
        }
    }

    /// Copies a BGRA pixel buffer into tightly packed rows.
    private static func frame(from pixelBuffer: CVPixelBuffer) -> PixelFrame? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let rowBytes = width * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * height)
        bytes.withUnsafeMutableBytes { destination in
            for row in 0..<height {
                memcpy(destination.baseAddress! + row * rowBytes, base + row * stride, rowBytes)
            }
        }
        return PixelFrame(width: width, height: height, bytes: bytes)
    }
}
