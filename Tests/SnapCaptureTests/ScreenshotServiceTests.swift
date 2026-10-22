import AppKit
import XCTest
@testable import SnapCapture

final class ScreenshotServiceTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SNAP_INTEGRATION"] == "1", "Set SNAP_INTEGRATION=1 to run")
    }

    func testCapturesEveryDisplayAtNativeResolution() async throws {
        let snapshots = try await ScreenshotService().captureAllDisplays()
        let screens = await MainActor.run { NSScreen.screens.map { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID, $0.backingScaleFactor, $0.frame.size) } }
        XCTAssertEqual(snapshots.count, screens.count)
        for (displayID, backingScale, size) in screens {
            let snapshot = try XCTUnwrap(snapshots.first { $0.displayID == displayID })
            XCTAssertEqual(snapshot.scale, backingScale)
            XCTAssertEqual(snapshot.frame.size, size)
            XCTAssertEqual(snapshot.image.width, Int(size.width * backingScale))
            XCTAssertEqual(snapshot.image.height, Int(size.height * backingScale))
        }
    }
}
