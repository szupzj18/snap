import AppKit
import XCTest
@testable import SnapCapture

final class ScrollingCapturerTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SNAP_INTEGRATION"] == "1", "Set SNAP_INTEGRATION=1 to run")
    }

    /// Opens a small scrolling window, scrolls it in code while capturing, and checks that the
    /// stitched image is as tall as the whole document.
    @MainActor
    func testStitchesAScrolledDocument() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let viewport = CGSize(width: 240, height: 200)
        let documentHeight: CGFloat = 900
        let frame = CGRect(x: screen.visibleFrame.minX + 30, y: screen.visibleFrame.maxY - viewport.height - 30,
                           width: viewport.width, height: viewport.height)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .floating
        let scrollView = NSScrollView(frame: CGRect(origin: .zero, size: viewport))
        scrollView.hasVerticalScroller = false
        scrollView.documentView = StripedDocument(frame: CGRect(x: 0, y: 0, width: viewport.width, height: documentHeight))
        window.contentView = scrollView
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        scrollView.contentView.scroll(to: .zero)
        try await Task.sleep(nanoseconds: 300_000_000)

        let displayID = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
        // The window's area in Quartz global points (the primary display anchors both spaces).
        let rect = CGRect(x: frame.minX, y: screen.frame.height - frame.maxY, width: frame.width, height: frame.height)
        let capturer = ScrollingCapturer()
        try await capturer.start(displayID: displayID, rect: rect)
        try await Task.sleep(nanoseconds: 300_000_000)

        var y: CGFloat = 0
        while y < documentHeight - viewport.height {
            y = min(y + 35, documentHeight - viewport.height)
            scrollView.contentView.scroll(to: CGPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        let image = try await capturer.finish()
        XCTAssertEqual(image.width, Int(viewport.width * capturer.scale))
        XCTAssertEqual(image.height, Int(documentHeight * capturer.scale), accuracy: Int(4 * capturer.scale))
    }
}

/// Flipped so scrolling down moves to higher y; every band is labelled and differently tinted.
private final class StripedDocument: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        for band in stride(from: 0, to: Int(bounds.height), by: 30) {
            let hue = CGFloat((band / 30) % 12) / 12
            NSColor(hue: hue, saturation: 0.5, brightness: 0.95, alpha: 1).setFill()
            CGRect(x: 0, y: CGFloat(band), width: bounds.width, height: 30).fill()
            ("Row \(band / 30) · \(band)" as NSString).draw(at: CGPoint(x: 10 + CGFloat(band % 90), y: CGFloat(band) + 7), withAttributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.black,
            ])
        }
    }
}
