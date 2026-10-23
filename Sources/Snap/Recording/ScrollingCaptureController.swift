import AppKit
import SnapCapture
import SnapCore
import SwiftUI

/// Runs a scrolling capture: pick an area, scroll it, click Done, get one tall image.
@MainActor
final class ScrollingCaptureController {
    private enum State {
        case idle, busy, capturing
    }

    private var state: State = .idle
    private let service: ScreenshotService
    private let onboarding: PermissionOnboardingController
    private let router: PostCaptureRouter
    private var capturer: ScrollingCapturer?
    private var border: RecordingBorder?
    private var controls: NSPanel?
    private let progress = ScrollingProgress()
    private var area: (rect: CGRect, displayID: CGDirectDisplayID)?

    init(service: ScreenshotService, onboarding: PermissionOnboardingController, router: PostCaptureRouter) {
        self.service = service
        self.onboarding = onboarding
        self.router = router
    }

    /// Starts a scrolling capture, or finishes the current one.
    func toggle() {
        switch state {
        case .idle: Task { await start() }
        case .capturing: Task { await finish() }
        case .busy: break
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
            guard let selection = await AreaSelectionSession(mode: .scrolling).run(snapshots: snapshots).capture,
                  let displayID = selection.displayID else {
                reset()
                return
            }
            area = (selection.sourceRect, displayID)

            // On screen before the stream starts, so they count as our own windows and stay out of it.
            let appKitRect = ScreenGeometry.flip(selection.sourceRect, primaryScreenHeight: NSScreen.primaryHeight)
            let border = RecordingBorder(recordedRect: appKitRect)
            border.orderFrontRegardless()
            self.border = border
            showControls(near: appKitRect, on: NSScreen.screen(for: displayID))

            let capturer = ScrollingCapturer(service: service)
            capturer.onProgress = { [weak self] height in self?.progress.height = height }
            self.capturer = capturer
            progress.height = 0
            try await capturer.start(displayID: displayID, rect: selection.sourceRect)
            state = .capturing
        } catch {
            await capturer?.cancel()
            reset()
            if case CaptureError.permissionDenied = error { onboarding.show() } else { ErrorPresenter.present(error) }
        }
    }

    private func finish() async {
        guard state == .capturing, let capturer, let area else { return }
        state = .busy
        border?.orderOut(nil)
        controls?.orderOut(nil)
        do {
            let image = try await capturer.finish()
            let capture = Capture(image: image, scale: capturer.scale, mode: .scrolling, sourceRect: area.rect, displayID: area.displayID)
            reset()
            router.handle(capture)
        } catch {
            reset()
            ErrorPresenter.present(error)
        }
    }

    private func cancel() {
        guard state == .capturing else { return }
        state = .busy
        Task {
            await capturer?.cancel()
            reset()
        }
    }

    private func reset() {
        border?.orderOut(nil)
        controls?.orderOut(nil)
        border = nil
        controls = nil
        capturer = nil
        area = nil
        state = .idle
    }

    /// Done/Cancel bar just below the area, or above it when there's no room.
    private func showControls(near area: CGRect, on screen: NSScreen?) {
        let host = FirstMouseHostingView(rootView: ScrollingControlsView(
            progress: progress,
            done: { [weak self] in self?.toggle() },
            cancel: { [weak self] in self?.cancel() }
        ))
        let size = host.fittingSize
        let visible = screen?.visibleFrame ?? area
        var origin = CGPoint(x: area.midX - size.width / 2, y: area.minY - size.height - 12)
        if origin.y < visible.minY { origin.y = area.maxY + 12 }
        if origin.y + size.height > visible.maxY { origin.y = area.minY + 12 }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)

        let panel = NSPanel(contentRect: CGRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        panel.orderFrontRegardless()
        controls = panel
    }
}

final class ScrollingProgress: ObservableObject {
    /// Stitched height in pixels.
    @Published var height = 0
}

private struct ScrollingControlsView: View {
    @ObservedObject var progress: ScrollingProgress
    let done: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.to.line.compact")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Scroll down to capture").font(.system(size: 12, weight: .semibold))
                Text(progress.height == 0 ? "Waiting for the first frame…" : "\(String(progress.height)) px tall")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button("Cancel", action: cancel)
            Button("Done", action: done)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .fixedSize()
    }
}
