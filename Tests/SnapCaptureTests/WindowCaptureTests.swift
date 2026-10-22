import AppKit
import XCTest
@testable import SnapCapture

final class WindowCaptureTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SNAP_INTEGRATION"] == "1", "Set SNAP_INTEGRATION=1 to run")
    }

    @MainActor
    func testCapturesOwnWindowWithRoundedCorners() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let frame = CGRect(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.maxY - 200, width: 240, height: 160)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.backgroundColor = .systemRed
        window.title = "Snap test window"
        window.orderFrontRegardless()
        defer { window.close() }
        try await Task.sleep(nanoseconds: 500_000_000)

        // The test runner's own bundle id would otherwise exclude its window.
        let service = ScreenshotService(ownBundleIdentifier: "test.none")
        let windows = try await service.pickableWindows()
        let picked = try XCTUnwrap(windows.first { $0.windowID == CGWindowID(window.windowNumber) })
        XCTAssertEqual(picked.frame.size, window.frame.size)

        let plain = try await service.captureWindow(picked)
        XCTAssertEqual(plain.scale, screen.backingScaleFactor)
        XCTAssertEqual(plain.image.width, Int(window.frame.width * plain.scale))
        XCTAssertEqual(plain.image.height, Int(window.frame.height * plain.scale))
        XCTAssertEqual(alpha(of: plain.image, x: 0, y: 0), 0, "rounded corner should be transparent")
        XCTAssertEqual(alpha(of: plain.image, x: plain.image.width / 2, y: plain.image.height / 2), 255)

    }

    private func alpha(of image: CGImage, x: Int, y: Int) -> UInt8 {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Draw so that pixel (x, y), counted from the top-left, lands on the 1x1 context.
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return pixel[3]
    }
}
