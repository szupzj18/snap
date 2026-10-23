import AVFoundation
import CoreMedia

/// Writes a screen recording: H.264 video plus up to two AAC audio tracks, with pause support.
///
/// Not thread-safe: call everything from the same serial queue.
final class MovieWriter {
    enum Track {
        case video
        case systemAudio
        case microphone
    }

    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private var audio: [Track: AVAssetWriterInput] = [:]
    private var started = false
    private(set) var lastFrameTime: CMTime?

    /// Total paused time, taken off every later timestamp so pauses leave no gap.
    private var pausedTotal = CMTime.zero
    private var pausedAt: CMTime?

    var hasFrames: Bool { started }
    var isPaused: Bool { pausedAt != nil }

    init(url: URL, width: Int, height: Int, fps: Int, audioTracks: [Track] = []) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
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
        video.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else { throw RecordingError.cannotAddInput }
        writer.add(video)

        for track in audioTracks where track != .video {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw RecordingError.cannotAddInput }
            writer.add(input)
            audio[track] = input
        }
    }

    /// Stereo AAC; sources deliver 48 kHz stereo PCM (see `ScreenRecorder.audioFormat`).
    static let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 160_000,
    ]

    /// The timeline starts at the first video frame; earlier audio is dropped.
    func append(_ sampleBuffer: CMSampleBuffer, to track: Track) {
        guard pausedAt == nil else { return }
        let input: AVAssetWriterInput
        if track == .video {
            input = video
            if !started {
                guard writer.startWriting() else { return }
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                started = true
            }
        } else {
            guard started, let audioInput = audio[track] else { return }
            input = audioInput
        }
        guard let buffer = shifted(sampleBuffer) else { return }
        // Dropping a sample beats blocking the capture queue.
        guard input.isReadyForMoreMediaData, input.append(buffer) else { return }
        if track == .video {
            lastFrameTime = CMSampleBufferGetPresentationTimeStamp(buffer)
        }
    }

    /// `time` is on the same (host) clock as the samples.
    func pause(at time: CMTime) {
        guard pausedAt == nil else { return }
        pausedAt = time
    }

    func resume(at time: CMTime) {
        guard let pausedAt else { return }
        pausedTotal = pausedTotal + (time - pausedAt)
        self.pausedAt = nil
    }

    /// Ends the movie at `endTime`, so a still screen at the end isn't cut short.
    func finish(at endTime: CMTime) async throws {
        guard started else {
            writer.cancelWriting()
            throw RecordingError.noFrames
        }
        video.markAsFinished()
        audio.values.forEach { $0.markAsFinished() }
        // Stopped while paused: the movie ends where the pause began.
        let end = (pausedAt ?? endTime) - pausedTotal
        if let lastFrameTime, end > lastFrameTime {
            writer.endSession(atSourceTime: end)
        }
        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? RecordingError.writeFailed
        }
    }

    func cancel() {
        if started { writer.cancelWriting() }
    }

    /// The sample moved earlier by the time spent paused.
    private func shifted(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard pausedTotal > .zero else { return sampleBuffer }
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: max(count, 1))
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: timing.count, arrayToFill: &timing, entriesNeededOut: &count)
        for index in timing.indices {
            timing[index].presentationTimeStamp = timing[index].presentationTimeStamp - pausedTotal
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = timing[index].decodeTimeStamp - pausedTotal
            }
        }
        var copy: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sampleBuffer, sampleTimingEntryCount: timing.count,
                                              sampleTimingArray: &timing, sampleBufferOut: &copy)
        return copy
    }
}

public enum RecordingError: LocalizedError {
    case cannotAddInput
    case noFrames
    case writeFailed
    case noMicrophone
    case microphoneDenied

    public var errorDescription: String? {
        switch self {
        case .noMicrophone: "No microphone is available."
        case .microphoneDenied: "Snap isn't allowed to use the microphone. Allow it in System Settings › Privacy & Security › Microphone, or turn off microphone recording in Snap's settings."
        case .cannotAddInput: "Couldn't set up the video encoder."
        case .noFrames: "The recording didn't capture any frames."
        case .writeFailed: "Couldn't write the video file."
        }
    }
}
