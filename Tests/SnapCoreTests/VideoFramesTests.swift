import AVFoundation
import ImageIO
import XCTest
@testable import SnapCore

final class VideoFramesTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRecordingLoadReadsDurationAndThumbnail() async throws {
        let url = try await TestVideo.make(in: directory, width: 64, height: 48, seconds: 1, fps: 30)
        let recording = try await Recording.load(url: url, scale: 2, sourceRect: .zero, displayID: nil)
        XCTAssertEqual(recording.duration, 1, accuracy: 0.05)
        XCTAssertEqual(recording.thumbnail.width, 64)
        XCTAssertEqual(recording.thumbnail.height, 48)
    }

    func testGIFHasOneFramePerTickAndLoops() async throws {
        let video = try await TestVideo.make(in: directory, width: 320, height: 240, seconds: 1, fps: 30)
        let gif = directory.appendingPathComponent("out.gif")
        let frames = try await VideoFrames.exportGIF(from: video, to: gif, fps: 10, maxPixelSize: 160)
        XCTAssertEqual(frames, 10)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(gif as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 10)
        let properties = try XCTUnwrap(CGImageSourceCopyProperties(source, nil) as? [CFString: Any])
        let gifProperties = try XCTUnwrap(properties[kCGImagePropertyGIFDictionary] as? [CFString: Any])
        XCTAssertEqual(gifProperties[kCGImagePropertyGIFLoopCount] as? Int, 0)
        let first = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(first.width, 160)
        XCTAssertEqual(first.height, 120)
    }

    func testFormatDuration() {
        XCTAssertEqual(Recording.formatDuration(7.9), "0:07")
        XCTAssertEqual(Recording.formatDuration(83), "1:23")
    }
}

/// Writes a short H.264 movie whose frames cycle through colors.
enum TestVideo {
    static func make(in directory: URL, width: Int, height: Int, seconds: Double, fps: Int32) async throws -> URL {
        let url = directory.appendingPathComponent("\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let frameCount = Int(seconds * Double(fps))
        for index in 0..<frameCount {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            let pixels = buffer!
            CVPixelBufferLockBaseAddress(pixels, [])
            let value = UInt8((index * 255) / max(frameCount - 1, 1))
            memset(CVPixelBufferGetBaseAddress(pixels), Int32(value), CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: fps))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frameCount), timescale: fps))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return url
    }
}
