import AVKit
import SnapCore

/// QuickTime-style trimming of a recording, using AVKit's own trim bar.
@MainActor
final class TrimWindowController: NSObject, NSWindowDelegate {
    private let url: URL
    let window: NSWindow
    private let playerView = AVPlayerView()
    private let completion: (Bool) -> Void
    private var finished = false

    /// `completion` gets true once the file at `url` has been replaced by the trimmed movie.
    init(url: URL, completion: @escaping (Bool) -> Void) {
        self.url = url
        self.completion = completion
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 480),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Trim — \(url.lastPathComponent)"
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 480, height: 320)
        window.delegate = self
        playerView.controlsStyle = .inline
        playerView.player = AVPlayer(url: url)
        window.contentView = playerView
        window.center()
    }

    func present() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        Task { await beginTrimming() }
    }

    func beginTrimming() async {
        // The trim bar needs a loaded item.
        for _ in 0..<50 where !playerView.canBeginTrimming {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard playerView.canBeginTrimming else {
            finish(trimmed: false)
            return
        }
        let result = await playerView.beginTrimming()
        guard result == .okButton, let item = playerView.player?.currentItem else {
            finish(trimmed: false)
            return
        }
        // After trimming, the item's playback window is the kept range.
        await export(CMTimeRange(start: item.reversePlaybackEndTime, end: item.forwardPlaybackEndTime))
    }

    private func export(_ range: CMTimeRange) async {
        playerView.player?.pause()
        playerView.player = nil
        do {
            try await VideoTrimming.trim(url, to: range)
            finish(trimmed: true)
        } catch {
            finish(trimmed: false)
            ErrorPresenter.present(error)
        }
    }

    private func finish(trimmed: Bool) {
        guard !finished else { return }
        finished = true
        window.close()
        completion(trimmed)
    }

    func windowWillClose(_ notification: Notification) {
        playerView.player?.pause()
        finish(trimmed: false)
    }
}
