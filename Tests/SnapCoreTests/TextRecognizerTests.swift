import AppKit
import XCTest
@testable import SnapCore

final class TextRecognizerTests: XCTestCase {
    func testArrangeOrdersLinesAndJoinsCells() {
        // Vision boxes: normalized, y grows up.
        let pieces: [(box: CGRect, text: String)] = [
            (CGRect(x: 0.6, y: 0.70, width: 0.3, height: 0.1), "right"),
            (CGRect(x: 0.1, y: 0.20, width: 0.5, height: 0.1), "bottom"),
            (CGRect(x: 0.1, y: 0.72, width: 0.3, height: 0.1), "left"),
        ]
        XCTAssertEqual(TextRecognizer.arrange(pieces), "left\tright\nbottom")
    }

    func testArrangeEmpty() {
        XCTAssertEqual(TextRecognizer.arrange([]), "")
    }

    func testRecognizesRenderedText() async throws {
        let image = render(lines: ["Snap reads text", "截图识字 2026"])
        let text = try await TextRecognizer.recognize(in: image)
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2, text)
        XCTAssertEqual(lines.first, "Snap reads text")
        XCTAssertTrue(lines.last?.contains("2026") ?? false, text)
    }

    func testBlankImageHasNoText() async throws {
        let text = try await TextRecognizer.recognize(in: render(lines: []))
        XCTAssertEqual(text, "")
    }

    private func render(lines: [String]) -> CGImage {
        let size = CGSize(width: 800, height: 240)
        let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for (index, line) in lines.enumerated() {
            (line as NSString).draw(at: CGPoint(x: 40, y: size.height - 90 - CGFloat(index) * 80), withAttributes: [
                .font: NSFont.systemFont(ofSize: 44),
                .foregroundColor: NSColor.black,
            ])
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()!
    }
}
