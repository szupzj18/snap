import AppKit

/// The sound macOS itself plays for a screenshot.
@MainActor
enum CaptureSound {
    private static let sound: NSSound? = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        byReference: true
    )

    static func play() {
        // Restart if a previous shot is still playing, so quick captures each get a click.
        sound?.stop()
        sound?.play()
    }
}
