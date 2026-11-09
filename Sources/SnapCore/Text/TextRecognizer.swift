import CoreGraphics
import Foundation
import Vision

/// What OCR found in an image: its text and the payloads of any QR codes.
public struct RecognizedContent: Equatable {
    public var text: String
    public var qrCodes: [String]

    public init(text: String, qrCodes: [String]) {
        self.text = text
        self.qrCodes = qrCodes
    }

    /// What goes on the clipboard. A QR code is the more likely reason to capture an image that
    /// has one; the text stays available as an alternative.
    public enum Choice: Equatable {
        case qrCode(String, alsoHasText: Bool)
        case text(String)
        case nothing
    }

    public var choice: Choice {
        if !qrCodes.isEmpty {
            return .qrCode(qrCodes.joined(separator: "\n"), alsoHasText: !text.isEmpty)
        }
        return text.isEmpty ? .nothing : .text(text)
    }

    /// The payload as a web link, if it is one.
    public static func webURL(in payload: String) -> URL? {
        guard let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil
        else { return nil }
        return url
    }
}

/// On-device text and QR code recognition with the Vision framework.
public enum TextRecognizer {
    /// The text in `image`, one line per recognized line, top to bottom. Empty if there is none.
    public static func recognize(in image: CGImage) async throws -> String {
        try await recognizeContent(in: image).text
    }

    /// Text and QR codes in one pass over the image.
    public static func recognizeContent(in image: CGImage) async throws -> RecognizedContent {
        try await Task.detached(priority: .userInitiated) {
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = true
            textRequest.automaticallyDetectsLanguage = true
            let qrRequest = VNDetectBarcodesRequest()
            qrRequest.symbologies = [.qr]
            try VNImageRequestHandler(cgImage: image).perform([textRequest, qrRequest])
            var seen = Set<String>()
            let qrCodes = (qrRequest.results ?? []).compactMap(\.payloadStringValue).filter { seen.insert($0).inserted }
            return RecognizedContent(text: format(textRequest.results ?? []), qrCodes: qrCodes)
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
