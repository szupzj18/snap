import AVFoundation
import CoreMedia

/// Writes screen frames (CMSampleBuffers) to an H.264 MP4.
///
/// Not thread-safe: call `append` and `finish` from the same serial queue.
final class VideoFileWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var started = false
    private(set) var lastFrameTime: CMTime?

    var hasFrames: Bool { started }

    init(url: URL, width: Int, height: Int, fps: Int) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                // Screen content compresses well; this keeps text crisp without huge files.
                AVVideoAverageBitRateKey: max(width * height * fps / 8, 2_000_000),
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw RecordingError.cannotAddInput }
        writer.add(input)
    }

    /// The timeline starts at the first frame.
    func append(_ sampleBuffer: CMSampleBuffer) {
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if !started {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: time)
            started = true
        }
        // Dropping a frame beats blocking the capture queue.
        guard input.isReadyForMoreMediaData, input.append(sampleBuffer) else { return }
        lastFrameTime = time
    }

    /// Ends the movie at `endTime`, so a still screen at the end isn't cut short.
    func finish(at endTime: CMTime) async throws {
        guard started else {
            writer.cancelWriting()
            throw RecordingError.noFrames
        }
        input.markAsFinished()
        if let lastFrameTime, endTime > lastFrameTime {
            writer.endSession(atSourceTime: endTime)
        }
        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? RecordingError.writeFailed
        }
    }

    func cancel() {
        if started { writer.cancelWriting() }
    }
}

public enum RecordingError: LocalizedError {
    case cannotAddInput
    case noFrames
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .cannotAddInput: "Couldn't set up the video encoder."
        case .noFrames: "The recording didn't capture any frames."
        case .writeFailed: "Couldn't write the video file."
        }
    }
}
