import AVFoundation
import AppKit
import XCTest
@testable import SnapCapture

final class ScreenRecorderTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SNAP_INTEGRATION"] == "1", "Set SNAP_INTEGRATION=1 to run")
    }

    /// Records a small area of the main display for about a second.
    @MainActor
    func testRecordsAnAreaToMP4() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let displayID = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = ScreenRecorder()
        // Quartz global points: the top-left 200×120 of that display.
        let origin = CGDisplayBounds(displayID).origin
        let rect = CGRect(x: origin.x, y: origin.y, width: 200, height: 120)
        try await recorder.start(displayID: displayID, rect: rect, options: .init(fps: 30), to: url)
        try await Task.sleep(nanoseconds: 1_200_000_000)
        let output = try await recorder.stop()

        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration).seconds
        XCTAssertGreaterThan(duration, 0.8)
        let track = try await asset.loadTracks(withMediaType: .video).first
        let size = try await XCTUnwrap(track).load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 200 * screen.backingScaleFactor, height: 120 * screen.backingScaleFactor))
    }
}

final class ScreenRecorderAudioTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SNAP_INTEGRATION"] == "1", "Set SNAP_INTEGRATION=1 to run")
    }

    /// System audio gets its own track (silence is fine), and pausing shortens the movie.
    @MainActor
    func testRecordsSystemAudioAndPauses() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let displayID = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = ScreenRecorder()
        let origin = CGDisplayBounds(displayID).origin
        try await recorder.start(displayID: displayID, rect: CGRect(x: origin.x, y: origin.y, width: 160, height: 100),
                                 options: .init(fps: 30, systemAudio: true), to: url)
        try await Task.sleep(nanoseconds: 700_000_000)
        recorder.pause()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        recorder.resume()
        try await Task.sleep(nanoseconds: 700_000_000)
        let output = try await recorder.stop()

        let asset = AVURLAsset(url: output)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audio.count, 1)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 1.4, accuracy: 0.3, "2.4 s wall clock minus the 1 s pause")
    }
}
