import CoreGraphics
import XCTest
@testable import SnapAnnotate

final class BackdropRendererTests: XCTestCase {
    func testPaddingAddsAroundAtScale() {
        let layout = BackdropRenderer.layout(contentSize: CGSize(width: 400, height: 200),
                                             backdrop: Backdrop(isEnabled: true, padding: 50), scale: 2)
        XCTAssertEqual(layout.canvasSize, CGSize(width: 600, height: 400))
        XCTAssertEqual(layout.contentRect, CGRect(x: 100, y: 100, width: 400, height: 200))
    }

    func testAspectGrowsShortSideAndCenters() {
        let wide = BackdropRenderer.layout(contentSize: CGSize(width: 400, height: 400),
                                           backdrop: Backdrop(isEnabled: true, padding: 0, aspect: .wide), scale: 1)
        XCTAssertEqual(wide.canvasSize, CGSize(width: 711, height: 400))
        XCTAssertEqual(wide.contentRect.minX, 156)

        let square = BackdropRenderer.layout(contentSize: CGSize(width: 800, height: 200),
                                             backdrop: Backdrop(isEnabled: true, padding: 0, aspect: .square), scale: 1)
        XCTAssertEqual(square.canvasSize, CGSize(width: 800, height: 800))
        XCTAssertEqual(square.contentRect.minY, 300)
    }

    func testComposeFillsBackgroundAndKeepsContent() throws {
        let content = Pixels.solid(width: 100, height: 60)
        let backdrop = Backdrop(isEnabled: true, fill: .solid(RGBA(0, 0, 1)), padding: 20, cornerRadius: 0, shadow: 0)
        let output = try XCTUnwrap(BackdropRenderer.compose(content, backdrop: backdrop, scale: 1))
        XCTAssertEqual(output.width, 140)
        XCTAssertEqual(output.height, 100)
        XCTAssertEqual(Pixels.at(output, x: 5, y: 5), [0, 0, 255, 255], "background")
        XCTAssertEqual(Pixels.at(output, x: 70, y: 50), [255, 255, 255, 255], "screenshot")
    }

    func testRoundedCornersShowTheBackground() throws {
        let content = Pixels.solid(width: 100, height: 100)
        let backdrop = Backdrop(isEnabled: true, fill: .solid(RGBA(0, 0, 0)), padding: 10, cornerRadius: 20, shadow: 0)
        let output = try XCTUnwrap(BackdropRenderer.compose(content, backdrop: backdrop, scale: 1))
        XCTAssertEqual(Pixels.at(output, x: 11, y: 11), [0, 0, 0, 255], "corner rounded off")
        XCTAssertEqual(Pixels.at(output, x: 60, y: 11), [255, 255, 255, 255], "edge middle kept")
    }

    func testClearFillLeavesTransparencyWithShadow() throws {
        let content = Pixels.solid(width: 100, height: 100)
        let backdrop = Backdrop(isEnabled: true, fill: .clear, padding: 40, cornerRadius: 0, shadow: 1)
        let output = try XCTUnwrap(BackdropRenderer.compose(content, backdrop: backdrop, scale: 1))
        XCTAssertEqual(Pixels.at(output, x: 0, y: 0)[3], 0, "far corner transparent")
        XCTAssertGreaterThan(Pixels.at(output, x: 90, y: 145)[3], 0, "shadow below the screenshot")
    }

    func testFrameAddsABarAboveTheScreenshot() {
        let layout = BackdropRenderer.layout(contentSize: CGSize(width: 400, height: 200),
                                             backdrop: Backdrop(isEnabled: true, padding: 50, frame: .window), scale: 2)
        // 28 pt bar at 2x.
        XCTAssertEqual(layout.canvasSize, CGSize(width: 600, height: 456))
        XCTAssertEqual(layout.frameRect, CGRect(x: 100, y: 100, width: 400, height: 256))
        XCTAssertEqual(layout.contentRect, CGRect(x: 100, y: 156, width: 400, height: 200))

        let browser = BackdropRenderer.layout(contentSize: CGSize(width: 400, height: 200),
                                              backdrop: Backdrop(isEnabled: true, padding: 0, frame: .browser), scale: 1)
        XCTAssertEqual(browser.contentRect.minY, 40)
    }

    func testAspectCountsTheBar() {
        let layout = BackdropRenderer.layout(contentSize: CGSize(width: 400, height: 372),
                                             backdrop: Backdrop(isEnabled: true, padding: 0, aspect: .square, frame: .window), scale: 1)
        XCTAssertEqual(layout.canvasSize, CGSize(width: 400, height: 400))
        XCTAssertEqual(layout.frameRect, CGRect(x: 0, y: 0, width: 400, height: 400))
    }

    func testWindowFrameDrawsBarAndTrafficLights() throws {
        let content = Pixels.solid(width: 200, height: 100)
        let light = Backdrop(isEnabled: true, fill: .solid(RGBA(0, 0, 1)), padding: 10, cornerRadius: 0, shadow: 0, frame: .window)
        let output = try XCTUnwrap(BackdropRenderer.compose(content, backdrop: light, scale: 1))
        XCTAssertEqual(output.height, 148)
        XCTAssertEqual(Pixels.at(output, x: 5, y: 5), [0, 0, 255, 255], "background")
        XCTAssertEqual(Pixels.at(output, x: 30, y: 24), [255, 94, 87, 255], "close button")
        XCTAssertEqual(Pixels.at(output, x: 150, y: 20), [237, 237, 237, 255], "light bar")
        XCTAssertEqual(Pixels.at(output, x: 150, y: 100), [255, 255, 255, 255], "screenshot below the bar")

        var dark = light
        dark.darkFrame = true
        let darkOutput = try XCTUnwrap(BackdropRenderer.compose(content, backdrop: dark, scale: 1))
        XCTAssertEqual(Pixels.at(darkOutput, x: 150, y: 20), [51, 51, 51, 255], "dark bar")
    }

    func testBrowserFrameHasAnAddressField() throws {
        let content = Pixels.solid(width: 400, height: 100)
        let backdrop = Backdrop(isEnabled: true, fill: .clear, padding: 0, cornerRadius: 0, shadow: 0, frame: .browser)
        let output = try XCTUnwrap(BackdropRenderer.compose(content, backdrop: backdrop, scale: 1))
        XCTAssertEqual(Pixels.at(output, x: 200, y: 20), [255, 255, 255, 255], "address field")
        XCTAssertEqual(Pixels.at(output, x: 200, y: 4), [237, 237, 237, 255], "bar above the field")
        XCTAssertEqual(Pixels.at(output, x: 75, y: 20), [237, 237, 237, 255], "bar beside the field")
    }

    func testContentIsClippedBelowTheBar() throws {
        let backdrop = Backdrop(isEnabled: true, fill: .clear, padding: 0, cornerRadius: 0, shadow: 0, frame: .window)
        let layout = BackdropRenderer.layout(contentSize: CGSize(width: 100, height: 100), backdrop: backdrop, scale: 1)
        let context = CGContext(data: nil, width: 100, height: 128, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: 128)
        context.scaleBy(x: 1, y: -1)
        BackdropRenderer.drawFrame(layout: layout, backdrop: backdrop, scale: 1, in: context) {
            // An annotation sticking out above the screenshot must not cover the bar.
            context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 128))
        }
        let output = try XCTUnwrap(context.makeImage())
        XCTAssertEqual(Pixels.at(output, x: 90, y: 10), [237, 237, 237, 255], "bar untouched")
        XCTAssertEqual(Pixels.at(output, x: 90, y: 60), [255, 0, 0, 255], "content drawn")
    }
}
