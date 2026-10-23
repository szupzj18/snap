import AVFoundation
import XCTest
@testable import SnapCapture

final class VideoFileWriterTests: XCTestCase {
    private func sampleBuffer(width: Int, height: Int, at time: CMTime) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer)
        let pixels = try XCTUnwrap(pixelBuffer)
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixels, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixels, formatDescription: format!,
                                                 sampleTiming: &timing, sampleBufferOut: &sample)
        return try XCTUnwrap(sample)
    }

    func testWritesMovieThatLastsUntilStop() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try VideoFileWriter(url: url, width: 128, height: 96, fps: 30)
        // Timestamps start far from zero, like host-clock times from ScreenCaptureKit.
        let start = CMTime(seconds: 1000, preferredTimescale: 600)
        for index in 0..<10 {
            writer.append(try sampleBuffer(width: 128, height: 96, at: start + CMTime(value: CMTimeValue(index), timescale: 30)))
        }
        // The screen then sits still until the user stops at +0.8 s.
        try await writer.finish(at: start + CMTime(seconds: 0.8, preferredTimescale: 600))

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 0.8, accuracy: 0.05)
        let track = try await asset.loadTracks(withMediaType: .video).first
        let size = try await XCTUnwrap(track).load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 128, height: 96))
    }

    func testFinishWithoutFramesThrows() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        let writer = try VideoFileWriter(url: url, width: 64, height: 64, fps: 30)
        do {
            try await writer.finish(at: .zero)
            XCTFail("expected an error")
        } catch RecordingError.noFrames {}
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
