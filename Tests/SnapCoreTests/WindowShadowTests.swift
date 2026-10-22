import CoreGraphics
import XCTest
@testable import SnapCore

final class WindowShadowTests: XCTestCase {
    func testAddsMarginsAndKeepsWindowPixels() throws {
        let window = TestImage.solid(width: 200, height: 100, red: 1)
        let result = try XCTUnwrap(WindowShadow.apply(to: window, scale: 2))

        let margins = WindowShadow.margins
        XCTAssertEqual(result.width, 200 + Int(margins.sides * 2) * 2)
        XCTAssertEqual(result.height, 100 + Int(margins.top * 2) + Int(margins.bottom * 2))

        // The window itself is untouched...
        let center = TestImage.pixel(of: result, x: result.width / 2, y: Int(margins.top * 2) + 50)
        XCTAssertEqual(center, [255, 0, 0, 255])
        // ...the far corner stays transparent...
        XCTAssertEqual(TestImage.pixel(of: result, x: 0, y: 0)[3], 0)
        // ...and just below the window there is shadow.
        let belowWindow = TestImage.pixel(of: result, x: result.width / 2, y: Int(margins.top * 2) + 100 + 10)
        XCTAssertGreaterThan(belowWindow[3], 0)
    }
}

enum TestImage {
    static func solid(width: Int, height: Int, red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// RGBA of the pixel at (x, y), counted from the top-left.
    static func pixel(of image: CGImage, x: Int, y: Int) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return pixel
    }
}
