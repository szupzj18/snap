/// What the user asked to capture.
///
/// Phase 2 modes (scrolling capture, screen recording) get their own cases here.
public enum CaptureMode: String, CaseIterable, Sendable {
    case area
    case window
    case fullscreen
    /// Select an area and copy the text in it (OCR) instead of keeping the image.
    case text

    public var title: String {
        switch self {
        case .area: "Area"
        case .window: "Window"
        case .fullscreen: "Fullscreen"
        case .text: "Text"
        }
    }
}
