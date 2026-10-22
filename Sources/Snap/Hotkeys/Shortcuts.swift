import KeyboardShortcuts
import SnapCore

// Defaults use ⌥⇧ so they don't collide with macOS's own ⌘⇧3/4/5 screenshot shortcuts.
extension KeyboardShortcuts.Name {
    static let captureArea = Self("captureArea", default: .init(.four, modifiers: [.option, .shift]))
    static let captureWindow = Self("captureWindow", default: .init(.five, modifiers: [.option, .shift]))
    static let captureFullscreen = Self("captureFullscreen", default: .init(.three, modifiers: [.option, .shift]))
    static let captureText = Self("captureText", default: .init(.two, modifiers: [.option, .shift]))
}

extension CaptureMode {
    var shortcutName: KeyboardShortcuts.Name {
        switch self {
        case .area: .captureArea
        case .window: .captureWindow
        case .fullscreen: .captureFullscreen
        case .text: .captureText
        }
    }
}

@MainActor
enum Hotkeys {
    static func register(_ coordinator: CaptureCoordinator) {
        for mode in CaptureMode.allCases {
            KeyboardShortcuts.onKeyDown(for: mode.shortcutName) { [weak coordinator] in
                coordinator?.start(mode)
            }
        }
    }
}
