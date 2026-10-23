import CoreGraphics
import XCTest
@testable import SnapCore

final class ScrollStitcherTests: XCTestCase {
    private let width = 120
    private let viewport = 100

    /// A page whose every row is different, so any slice can be located.
    private func page(rows: Int, seed: Int = 1) -> [[UInt8]] {
        var state = UInt32(truncatingIfNeeded: seed &* 2_654_435_761)
        func next() -> UInt8 {
            state = state &* 1_664_525 &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: state >> 24)
        }
        return (0..<rows).map { _ in
            // Blocks of 8 pixels share a value, like text and UI rather than pure noise.
            (0..<(width / 8)).flatMap { _ -> [UInt8] in
                let v = next()
                return Array(repeating: [v, v &+ 40, v &+ 80, 255], count: 8).flatMap { $0 }
            }
        }
    }

    private func solidRows(_ count: Int, value: UInt8) -> [[UInt8]] {
        Array(repeating: Array(repeating: [value, value, value, 255], count: width).flatMap { $0 }, count: count)
    }

    /// What the viewport shows at `offset`, with fixed header and footer drawn over the content.
    private func frame(_ content: [[UInt8]], offset: Int, header: [[UInt8]] = [], footer: [[UInt8]] = []) -> PixelFrame {
        let visible = viewport - header.count - footer.count
        let rows = header + Array(content[offset..<(offset + visible)]) + footer
        return PixelFrame(width: width, height: viewport, bytes: rows.flatMap { $0 })
    }

    private func rows(of image: CGImage) -> [[UInt8]] {
        let bytes = Array(image.dataProvider!.data! as Data)
        return (0..<image.height).map { Array(bytes[($0 * width * 4)..<(($0 + 1) * width * 4)]) }
    }

    /// Compares row by row and reports the first difference instead of dumping every pixel.
    private func assertRows(_ actual: [[UInt8]], _ expected: [[UInt8]], file: StaticString = #filePath, line: UInt = #line) {
        let mismatch = zip(actual, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset
        XCTAssertTrue(actual.count == expected.count && mismatch == nil,
                      "got \(actual.count) rows, expected \(expected.count); first different row: \(mismatch.map(String.init) ?? "none")",
                      file: file, line: line)
    }

    private func stitch(_ frames: [PixelFrame]) -> [[UInt8]] {
        let stitcher = ScrollStitcher(width: width, frameHeight: viewport)
        frames.forEach { stitcher.add($0) }
        let image = stitcher.makeImage(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))!
        XCTAssertEqual(image.height, stitcher.height)
        return rows(of: image)
    }

    func testPlainScrollRebuildsThePage() {
        let content = page(rows: 400)
        // Up to 60 % of the viewport between frames; the live stream delivers far smaller steps.
        let offsets = [0, 13, 41, 42, 90, 150, 210, 260, 300]
        let result = stitch(offsets.map { frame(content, offset: $0) })
        assertRows(result, content)
    }

    func testFixedHeaderAndFooterAppearOnce() {
        let content = page(rows: 400)
        let header = solidRows(12, value: 30)
        let footer = page(rows: 10, seed: 99)
        let visible = viewport - 22
        let offsets = [0, 20, 55, 100, 140, 185, 230, 270, 318]
        let result = stitch(offsets.map { frame(content, offset: $0, header: header, footer: footer) })
        assertRows(result, header + Array(content[0..<(318 + visible)]) + footer)
    }

    func testRepeatedAndUnmovedFramesAddNothing() {
        let content = page(rows: 300)
        let result = stitch([frame(content, offset: 0), frame(content, offset: 0), frame(content, offset: 50), frame(content, offset: 50)])
        assertRows(result, Array(content[0..<150]))
    }

    func testUnmatchableFrameIsSkipped() {
        let content = page(rows: 300)
        let unrelated = page(rows: 300, seed: 7)
        let result = stitch([frame(content, offset: 0), frame(unrelated, offset: 0), frame(content, offset: 60)])
        assertRows(result, Array(content[0..<160]))
    }

    func testSingleFrameComesOutWhole() {
        let content = page(rows: 100)
        assertRows(stitch([frame(content, offset: 0)]), content)
    }

    func testFrameMatchingIsFastEnoughForLiveCapture() {
        // A Retina-sized area: 700×600 pt at 2x.
        let stitcher = ScrollStitcher(width: 1400, frameHeight: 1200)
        var state: UInt32 = 7
        let tall: [UInt8] = (0..<(1400 * 2000)).flatMap { index -> [UInt8] in
            if index % 8 == 0 { state = state &* 1_664_525 &+ 1_013_904_223 }
            let v = UInt8(truncatingIfNeeded: state >> 24)
            return [v, v, v, 255]
        }
        func viewport(_ offset: Int) -> PixelFrame {
            PixelFrame(width: 1400, height: 1200, bytes: Array(tall[(offset * 1400 * 4)..<((offset + 1200) * 1400 * 4)]))
        }
        let frames = [0, 150, 400, 700].map(viewport)
        let start = Date()
        frames.forEach { stitcher.add($0) }
        let perFrame = Date().timeIntervalSince(start) / Double(frames.count)
        XCTAssertEqual(stitcher.height, 1900)
        print("stitcher: \(Int(perFrame * 1000)) ms per frame")
        XCTAssertLessThan(perFrame, 0.5)
    }

    func testMaximumHeightStopsGrowth() {
        let content = page(rows: 400)
        let stitcher = ScrollStitcher(width: width, frameHeight: viewport, maximumHeight: 150)
        for offset in [0, 50, 100, 200, 300] { stitcher.add(frame(content, offset: offset)) }
        XCTAssertTrue(stitcher.isFull)
        XCTAssertEqual(stitcher.height, 150)
    }
}
