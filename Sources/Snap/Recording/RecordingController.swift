import AppKit
import SnapCapture
import SnapCore

/// Runs a screen recording: area selection, the border around the recorded area, start and stop.
@MainActor
final class RecordingController {
    enum State: Equatable {
        case idle
        /// Selecting the area, starting, or finishing the file.
        case busy
        case recording(since: Date)
    }

    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }

    private let settings: AppSettings
    private let service: ScreenshotService
    private let onboarding: PermissionOnboardingController
    private let router: PostCaptureRouter
    private var recorder: ScreenRecorder?
    private var border: RecordingBorder?
    private var area: (rect: CGRect, displayID: CGDirectDisplayID)?

    init(settings: AppSettings, service: ScreenshotService, onboarding: PermissionOnboardingController, router: PostCaptureRouter) {
        self.settings = settings
        self.service = service
        self.onboarding = onboarding
        self.router = router
    }

    /// Starts a recording, or stops the current one.
    func toggle() {
        switch state {
        case .idle: Task { await start() }
        case .recording: Task { await stop() }
        case .busy: break
        }
    }

    func cancel() {
        guard case .recording = state else { return }
        state = .busy
        Task {
            await recorder?.cancel()
            reset()
        }
    }

    private func start() async {
        guard ScreenRecordingPermission.isGranted else {
            onboarding.show()
            return
        }
        state = .busy
        do {
            let snapshots = try await service.captureAllDisplays()
            guard let selection = await AreaSelectionSession(mode: .recording).run(snapshots: snapshots),
                  let displayID = selection.displayID else {
                reset()
                return
            }
            area = (selection.sourceRect, displayID)

            // The border must be on screen before the stream starts, so it's in the list of
            // our own windows that the recording leaves out.
            let border = RecordingBorder(recordedRect: ScreenGeometry.flip(selection.sourceRect, primaryScreenHeight: NSScreen.primaryHeight))
            border.orderFrontRegardless()
            self.border = border

            let recorder = ScreenRecorder(service: service)
            recorder.onUnexpectedStop = { [weak self] error in
                Task { await self?.stop(after: error) }
            }
            self.recorder = recorder
            let url = CaptureActions.recordingsDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
            try await recorder.start(
                displayID: displayID,
                rect: selection.sourceRect,
                options: .init(fps: settings.recordingFPS, showsCursor: settings.recordingShowsCursor),
                to: url
            )
            state = .recording(since: Date())
        } catch {
            await recorder?.cancel()
            reset()
            if case CaptureError.permissionDenied = error { onboarding.show() } else { ErrorPresenter.present(error) }
        }
    }

    private func stop(after streamError: Error? = nil) async {
        guard case .recording = state, let recorder, let area else { return }
        state = .busy
        border?.orderOut(nil)
        do {
            let url = try await recorder.stop()
            let recording = try await Recording.load(url: url, scale: recorder.scale, sourceRect: area.rect, displayID: area.displayID)
            reset()
            router.handle(recording)
        } catch {
            reset()
            ErrorPresenter.present(streamError ?? error)
        }
    }

    private func reset() {
        border?.orderOut(nil)
        border = nil
        recorder = nil
        area = nil
        state = .idle
    }
}

/// A thin frame drawn just outside the recorded area, so it never shows up in the video.
final class RecordingBorder: NSPanel {
    private static let width: CGFloat = 2

    /// `recordedRect` is in AppKit global coordinates.
    init(recordedRect: CGRect) {
        let frame = recordedRect.insetBy(dx: -Self.width, dy: -Self.width)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        contentView = BorderView(frame: CGRect(origin: .zero, size: frame.size))
    }

    private final class BorderView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(rect: bounds.insetBy(dx: RecordingBorder.width / 2, dy: RecordingBorder.width / 2))
            path.lineWidth = RecordingBorder.width
            path.setLineDash([6, 4], count: 2, phase: 0)
            NSColor.systemRed.setStroke()
            path.stroke()
        }
    }
}
