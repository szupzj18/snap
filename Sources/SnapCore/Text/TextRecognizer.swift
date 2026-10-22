import CoreGraphics
import Vision

/// On-device text recognition (OCR) with the Vision framework.
public enum TextRecognizer {
    /// The text in `image`, one line per recognized line, top to bottom. Empty if there is none.
    public static func recognize(in image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            try VNImageRequestHandler(cgImage: image).perform([request])
            return format(request.results ?? [])
        }.value
    }

    /// Orders observations into reading order. Vision's order isn't guaranteed, and pieces of one
    /// visual line (e.g. table cells) come back as separate observations, so join those with tabs.
    static func format(_ observations: [VNRecognizedTextObservation]) -> String {
        let pieces = observations.compactMap { observation -> (box: CGRect, text: String)? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return (observation.boundingBox, text)
        }
        return arrange(pieces)
    }

    /// `box` uses Vision's normalized, bottom-left-origin coordinates.
    static func arrange(_ pieces: [(box: CGRect, text: String)]) -> String {
        // Top to bottom.
        let sorted = pieces.sorted { $0.box.midY > $1.box.midY }
        var lines: [[(box: CGRect, text: String)]] = []
        for piece in sorted {
            // Same line if it overlaps the line's vertical span by more than half its height.
            if let last = lines.last?.first,
               min(last.box.maxY, piece.box.maxY) - max(last.box.minY, piece.box.minY) > piece.box.height / 2 {
                lines[lines.count - 1].append(piece)
            } else {
                lines.append([piece])
            }
        }
        return lines
            .map { line in line.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: "\t") }
            .joined(separator: "\n")
    }
}
