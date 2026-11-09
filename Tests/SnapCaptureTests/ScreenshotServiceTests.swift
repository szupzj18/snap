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

final class DesktopClutterTests: XCTestCase {
    func testFinderDesktopIconsAreClutter() {
        let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        XCTAssertTrue(ScreenshotService.isDesktopClutter(layer: iconLevel, bundleIdentifier: "com.apple.finder"))
    }

    func testDesktopWidgetsAreClutter() {
        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
        XCTAssertTrue(ScreenshotService.isDesktopClutter(layer: desktopLevel + 1, bundleIdentifier: "com.apple.notificationcenterui"))
    }

    func testWallpaperAndNormalWindowsStay() {
        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
        let normal = Int(CGWindowLevelForKey(.normalWindow))
        XCTAssertFalse(ScreenshotService.isDesktopClutter(layer: desktopLevel - 1, bundleIdentifier: "com.apple.dock"))
        XCTAssertFalse(ScreenshotService.isDesktopClutter(layer: normal, bundleIdentifier: "com.apple.finder"))
        // Notification banners float above everything; only the widgets below normal windows go.
        XCTAssertFalse(ScreenshotService.isDesktopClutter(layer: normal + 100, bundleIdentifier: "com.apple.notificationcenterui"))
    }
}
