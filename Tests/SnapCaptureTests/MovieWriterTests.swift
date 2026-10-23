import AVFoundation
import XCTest
@testable import SnapCapture

/// Synthetic video frames and silent stereo audio, timestamped like ScreenCaptureKit's (host clock).
enum TestSamples {
    static let start = CMTime(seconds: 1000, preferredTimescale: 48_000)

    static func video(width: Int = 128, height: Int = 96, at time: CMTime) -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer)
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer!, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixelBuffer!, formatDescription: format!,
                                                 sampleTiming: &timing, sampleBufferOut: &sample)
        return sample!
    }

    /// `frames` of 48 kHz stereo Float32 silence.
    static func audio(frames: Int = 4800, at time: CMTime) -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        let length = frames * 8
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil,
                                           customBlockSource: nil, offsetToData: 0, dataLength: length,
                                           flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block!, offsetIntoDestination: 0, dataLength: length)
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block!, formatDescription: format!,
                                                             sampleCount: frames, presentationTimeStamp: time,
                                                             packetDescriptions: nil, sampleBufferOut: &sample)
        return sample!
    }

    static func at(_ seconds: Double) -> CMTime {
        start + CMTime(seconds: seconds, preferredTimescale: 48_000)
    }
}

final class MovieWriterTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    private func load() async throws -> (duration: Double, video: [AVAssetTrack], audio: [AVAssetTrack]) {
        let asset = AVURLAsset(url: url)
        return (try await asset.load(.duration).seconds,
                try await asset.loadTracks(withMediaType: .video),
                try await asset.loadTracks(withMediaType: .audio))
    }

    func testWritesMovieThatLastsUntilStop() async throws {
        let writer = try MovieWriter(url: url, width: 128, height: 96, fps: 30)
        for index in 0..<10 {
            writer.append(TestSamples.video(at: TestSamples.at(Double(index) / 30)), to: .video)
        }
        // The screen then sits still until the user stops at +0.8 s.
        try await writer.finish(at: TestSamples.at(0.8))

        let movie = try await load()
        XCTAssertEqual(movie.duration, 0.8, accuracy: 0.05)
        let size = try await XCTUnwrap(movie.video.first).load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 128, height: 96))
        XCTAssertTrue(movie.audio.isEmpty)
    }

    func testFinishWithoutFramesThrows() async throws {
        let writer = try MovieWriter(url: url, width: 64, height: 64, fps: 30)
        do {
            try await writer.finish(at: .zero)
            XCTFail("expected an error")
        } catch RecordingError.noFrames {}
    }

    func testWritesAudioTracks() async throws {
        let writer = try MovieWriter(url: url, width: 128, height: 96, fps: 30, audioTracks: [.systemAudio, .microphone])
        // Audio before the first frame is dropped, not an error.
        writer.append(TestSamples.audio(at: TestSamples.at(-0.2)), to: .systemAudio)
        for tick in 0..<10 {
            let seconds = Double(tick) / 10
            writer.append(TestSamples.video(at: TestSamples.at(seconds)), to: .video)
            writer.append(TestSamples.audio(at: TestSamples.at(seconds)), to: .systemAudio)
            writer.append(TestSamples.audio(at: TestSamples.at(seconds)), to: .microphone)
        }
        try await writer.finish(at: TestSamples.at(1))

        let movie = try await load()
        XCTAssertEqual(movie.audio.count, 2)
        XCTAssertEqual(movie.duration, 1, accuracy: 0.06)
    }

    func testPausedTimeLeavesNoGap() async throws {
        let writer = try MovieWriter(url: url, width: 128, height: 96, fps: 30, audioTracks: [.systemAudio])
        func record(from start: Double, to end: Double) {
            var time = start
            while time < end {
                writer.append(TestSamples.video(at: TestSamples.at(time)), to: .video)
                writer.append(TestSamples.audio(at: TestSamples.at(time)), to: .systemAudio)
                time += 0.1
            }
        }
        record(from: 0, to: 0.5)
        writer.pause(at: TestSamples.at(0.5))
        record(from: 0.5, to: 3.5) // ignored while paused
        writer.resume(at: TestSamples.at(3.5))
        record(from: 3.5, to: 4.0)
        try await writer.finish(at: TestSamples.at(4.0))

        let movie = try await load()
        XCTAssertEqual(movie.duration, 1.0, accuracy: 0.06, "0.5 s before the pause + 0.5 s after")
    }

    func testStoppingWhilePausedEndsAtThePause() async throws {
        let writer = try MovieWriter(url: url, width: 128, height: 96, fps: 30)
        for index in 0..<6 {
            writer.append(TestSamples.video(at: TestSamples.at(Double(index) / 10)), to: .video)
        }
        writer.pause(at: TestSamples.at(0.6))
        try await writer.finish(at: TestSamples.at(5))
        let movie = try await load()
        XCTAssertEqual(movie.duration, 0.6, accuracy: 0.05)
    }

    func testMixdownMergesAudioIntoOneTrack() async throws {
        let writer = try MovieWriter(url: url, width: 128, height: 96, fps: 30, audioTracks: [.systemAudio, .microphone])
        for tick in 0..<10 {
            let seconds = Double(tick) / 10
            writer.append(TestSamples.video(at: TestSamples.at(seconds)), to: .video)
            writer.append(TestSamples.audio(at: TestSamples.at(seconds)), to: .systemAudio)
            writer.append(TestSamples.audio(at: TestSamples.at(seconds)), to: .microphone)
        }
        try await writer.finish(at: TestSamples.at(1))

        try await AudioMixdown.mergeAudioTracks(in: url)
        let movie = try await load()
        XCTAssertEqual(movie.audio.count, 1)
        XCTAssertEqual(movie.video.count, 1)
        XCTAssertEqual(movie.duration, 1, accuracy: 0.08)
    }
}

final class ScreenRecorderSizingTests: XCTestCase {
    func testPixelSizeIsEvenAndCapped() {
        let retina = ScreenRecorder.pixelSize(for: CGSize(width: 301, height: 201), scale: 2)
        XCTAssertEqual(retina.width, 602)
        XCTAssertEqual(retina.height, 402)

        let odd = ScreenRecorder.pixelSize(for: CGSize(width: 101.5, height: 51), scale: 1)
        XCTAssertEqual(odd.width, 100)
        XCTAssertEqual(odd.height, 50)

        let huge = ScreenRecorder.pixelSize(for: CGSize(width: 2560, height: 1440), scale: 2)
        XCTAssertEqual(huge.width, 3840)
        XCTAssertEqual(huge.height, 2160)
    }
}
