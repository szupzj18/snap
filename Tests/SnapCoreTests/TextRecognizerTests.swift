import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
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

    func testReadsQRCode() async throws {
        let content = try await TextRecognizer.recognizeContent(in: qrCode("https://github.com/szupzj18/snap"))
        XCTAssertEqual(content.qrCodes, ["https://github.com/szupzj18/snap"])
        XCTAssertEqual(content.choice, .qrCode("https://github.com/szupzj18/snap", alsoHasText: false))
    }

    func testNoQRCodeInText() async throws {
        let content = try await TextRecognizer.recognizeContent(in: render(lines: ["Snap reads text"]))
        XCTAssertEqual(content.qrCodes, [])
        XCTAssertEqual(content.choice, .text("Snap reads text"))
    }

    func testChoicePrefersQRCodeAndRemembersText() {
        XCTAssertEqual(RecognizedContent(text: "hi", qrCodes: ["a", "b"]).choice, .qrCode("a\nb", alsoHasText: true))
        XCTAssertEqual(RecognizedContent(text: "", qrCodes: []).choice, .nothing)
    }

    func testWebURL() {
        XCTAssertEqual(RecognizedContent.webURL(in: " https://example.com/x \n"), URL(string: "https://example.com/x"))
        XCTAssertNil(RecognizedContent.webURL(in: "WIFI:S:home;T:WPA;P:secret;;"))
        XCTAssertNil(RecognizedContent.webURL(in: "javascript:alert(1)"))
        XCTAssertNil(RecognizedContent.webURL(in: "just words"))
    }

    /// A QR code with a white quiet zone, scaled up so each module is several pixels.
    private func qrCode(_ payload: String) -> CGImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        let code = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let padded = code.transformed(by: CGAffineTransform(translationX: 40, y: 40))
            .composited(over: CIImage(color: .white).cropped(to: code.extent.insetBy(dx: -40, dy: -40).offsetBy(dx: 40, dy: 40)))
        return CIContext().createCGImage(padded, from: padded.extent)!
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
