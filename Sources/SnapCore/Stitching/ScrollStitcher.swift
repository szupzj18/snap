import CoreGraphics
import Foundation

/// One video frame as tightly packed 4-byte pixels (any channel order, as long as it's consistent).
public struct PixelFrame {
    public let width: Int
    public let height: Int
    public let bytes: [UInt8]

    public init(width: Int, height: Int, bytes: [UInt8]) {
        precondition(bytes.count == width * height * 4)
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    func row(_ index: Int) -> ArraySlice<UInt8> {
        bytes[(index * width * 4)..<((index + 1) * width * 4)]
    }
}

/// Builds one tall image from frames of the same area taken while its content scrolls down.
///
/// Each new frame is matched against the previous one to find how far the content moved, and
/// only the newly revealed rows are added. Rows at the bottom that stay identical while the
/// content moves (a fixed footer or toolbar) are held back and added once, at the end. A fixed
/// header is only kept from the first frame, since matching uses the middle of the frame.
public final class ScrollStitcher {
    public let width: Int
    public let frameHeight: Int
    /// Stops growing past this many rows.
    public let maximumHeight: Int

    /// Accumulated page rows, top to bottom.
    private var pixels: [UInt8] = []
    private var pageRows = 0
    private var previous: PixelFrame?
    private var previousSignature = Signature(rows: 0, columns: 0, values: [])
    /// Page row shown at the top of `previous`.
    private var previousOffset = 0
    /// Bottom rows of `previous` not yet added: the fixed footer, or the whole first frame until
    /// a second one shows which of its rows are a footer.
    private var footerRows = 0

    public init(width: Int, frameHeight: Int, maximumHeight: Int = 40_000) {
        self.width = width
        self.frameHeight = frameHeight
        self.maximumHeight = maximumHeight
    }

    /// Height of the finished image if it were made now.
    public var height: Int {
        guard previous != nil else { return 0 }
        return min(pageRows + footerRows, maximumHeight)
    }

    public var isFull: Bool { pageRows >= maximumHeight }

    /// Adds a frame. Returns true if the image grew.
    @discardableResult
    public func add(_ frame: PixelFrame) -> Bool {
        guard frame.width == width, frame.height == frameHeight, !isFull else { return false }
        let signature = Self.signature(of: frame)
        guard let previous else {
            // Held back whole until the next frame shows where its footer starts.
            self.previous = frame
            previousSignature = signature
            footerRows = frame.height
            return true
        }
        // Couldn't tell how far it moved (blank area, or a jump): keep the old reference frame so
        // a later frame can still be matched against it.
        guard let shift = Self.shift(from: previousSignature, to: signature) else { return false }
        guard shift > 0 else {
            // Same position; take the newer pixels as the reference (e.g. a cursor blink).
            self.previous = frame
            previousSignature = signature
            return false
        }

        let offset = previousOffset + shift
        let footer = Self.staticBottomRows(previous, frame, limit: frame.height / 3)
        if pageRows == 0 {
            // First movement: the first frame, header included, down to the footer.
            append(previous, rows: 0..<(previous.height - footer))
        }
        // Page rows [pageRows, offset + height - footer) are new.
        let first = pageRows - offset
        let last = frame.height - footer
        let grew = last > first
        if grew {
            append(frame, rows: max(first, 0)..<last)
        }
        self.previous = frame
        previousSignature = signature
        previousOffset = offset
        footerRows = footer
        return grew
    }

    /// The stitched image, with the last frame's held-back footer at the bottom.
    public func makeImage(colorSpace: CGColorSpace, bitmapInfo: CGBitmapInfo) -> CGImage? {
        guard let previous else { return nil }
        var pixels = pixels
        var rows = pageRows
        if footerRows > 0 {
            for row in (previous.height - footerRows)..<previous.height where rows < maximumHeight {
                pixels.append(contentsOf: previous.row(row))
                rows += 1
            }
        }
        guard rows > 0, let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: rows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo, provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        )
    }

    private func append(_ frame: PixelFrame, rows: Range<Int>) {
        for row in rows where pageRows < maximumHeight {
            pixels.append(contentsOf: frame.row(row))
            pageRows += 1
        }
    }

    // MARK: Matching

    /// Per-row fingerprints: the brightness of evenly spaced pixels, row after row.
    struct Signature {
        let rows: Int
        let columns: Int
        let values: [Int32]
    }

    /// Columns sampled per row when comparing frames.
    private static let sampleColumns = 96

    static func signature(of frame: PixelFrame) -> Signature {
        let columns = min(sampleColumns, frame.width)
        let offsets = (0..<columns).map { (($0 * frame.width) / columns) * 4 }
        var values = [Int32](repeating: 0, count: frame.height * columns)
        frame.bytes.withUnsafeBufferPointer { bytes in
            for row in 0..<frame.height {
                let base = row * frame.width * 4
                for (column, offset) in offsets.enumerated() {
                    let index = base + offset
                    values[row * columns + column] = Int32(bytes[index]) + Int32(bytes[index + 1]) + Int32(bytes[index + 2])
                }
            }
        }
        return Signature(rows: frame.height, columns: columns, values: values)
    }

    /// How many rows the content moved up between two frames, or nil if it can't be told.
    ///
    /// A band of rows from the new frame is looked up in the old one. Bands are tried at several
    /// heights: one in a fixed header or footer only ever matches at 0, and a band near the top
    /// is needed to find big jumps. The largest convincing shift wins.
    static func shift(from old: Signature, to new: Signature) -> Int? {
        let height = new.rows
        let bandHeight = max(8, min(48, height / 8))
        let starts = Set([height / 8, height / 4, height / 3, height / 2]).sorted()
            .filter { $0 + bandHeight <= height }
        var found: Int?
        for start in starts where hasDetail(new, rows: start..<(start + bandHeight)) {
            if let shift = locate(new, band: start, height: bandHeight, in: old) {
                found = max(found ?? 0, shift)
            }
        }
        return found
    }

    /// Best shift for one band, if the match is close enough to be the same content.
    private static func locate(_ new: Signature, band start: Int, height bandHeight: Int, in old: Signature) -> Int? {
        let columns = new.columns
        let bandLength = bandHeight * columns
        var best: (shift: Int, cost: Int)?
        new.values.withUnsafeBufferPointer { newValues in
            old.values.withUnsafeBufferPointer { oldValues in
                let band = newValues.baseAddress! + start * columns
                // The band at new row r shows what old row r + shift showed.
                for shift in 0...(old.rows - bandHeight - start) {
                    let candidate = oldValues.baseAddress! + (start + shift) * columns
                    let limit = best?.cost ?? Int.max
                    var cost = 0
                    var index = 0
                    while index < bandLength {
                        cost += Int(abs(band[index] - candidate[index]))
                        index += 1
                        // Check the running total once per row.
                        if index % columns == 0, cost >= limit { break }
                    }
                    if cost < limit { best = (shift, cost) }
                }
            }
        }
        guard let best else { return nil }
        // On average within a few levels per channel: it's the same content.
        return best.cost <= bandLength * 3 * 4 ? best.shift : nil
    }

    /// Whether a band has enough variation to be located unambiguously.
    private static func hasDetail(_ signature: Signature, rows: Range<Int>) -> Bool {
        let columns = signature.columns
        let slice = signature.values[(rows.lowerBound * columns)..<(rows.upperBound * columns)]
        guard let low = slice.min(), let high = slice.max(), high - low > 30 else { return false }
        let firstRow = signature.values[(rows.lowerBound * columns)..<((rows.lowerBound + 1) * columns)]
        // Rows that all look the same (a gradient, a ruled line pattern) can't pin a position.
        return rows.dropFirst().contains { row in
            signature.values[(row * columns)..<((row + 1) * columns)] != firstRow
        }
    }

    /// Bottom rows that are byte-for-byte the same in both frames.
    static func staticBottomRows(_ a: PixelFrame, _ b: PixelFrame, limit: Int) -> Int {
        var count = 0
        while count < limit, a.row(a.height - 1 - count) == b.row(b.height - 1 - count) {
            count += 1
        }
        return count
    }
}
