/// What the user asked to capture.
///
/// Phase 2 modes (scrolling capture, screen recording) get their own cases here.
public enum CaptureMode: String, CaseIterable, Sendable {
    case area
    case window
    case fullscreen

    public var title: String {
        switch self {
        case .area: "Area"
        case .window: "Window"
        case .fullscreen: "Fullscreen"
        }
    }
}
