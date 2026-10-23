import AppKit
import SnapCore
import SwiftUI

struct QuickAccessCardView: View {
    @ObservedObject var item: QuickAccessItem
    let handlers: QuickAccessHandlers
    /// The file to share, made on first hover so an image isn't written out unless it's needed.
    @State private var shareURL: URL?

    static let cornerRadius: CGFloat = 10

    var body: some View {
        ZStack {
            // Behind images with transparency (window captures): glass, like other floating panels.
            Rectangle().fill(.thinMaterial)

            DragSource(item: item, handlers: handlers)

            if item.isHovered {
                // Just enough to make white controls readable on any screenshot.
                LinearGradient(
                    colors: [.black.opacity(0.38), .black.opacity(0.18), .black.opacity(0.38)],
                    startPoint: .top, endPoint: .bottom
                )
                .allowsHitTesting(false)
                .transition(.opacity)

                VStack(spacing: 6) {
                    OverlayPillButton(title: "Copy", action: handlers.copy)
                    OverlayPillButton(title: item.savedURL == nil ? "Save" : "Show in Finder", action: handlers.save)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))

                corners
                    .padding(6)
                    .transition(.opacity)
            }

            if let recording = item.recording, !item.isHovered {
                VStack {
                    Spacer()
                    HStack {
                        DurationBadge(duration: recording.duration)
                        Spacer()
                    }
                }
                .padding(7)
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        // A light inner edge and a dark outer one keep the card's outline crisp on any desktop.
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(.black.opacity(0.28), lineWidth: 0.5)
        )
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.14), value: item.isHovered)
        .onChange(of: item.isHovered) { _, hovered in
            if hovered, shareURL == nil {
                shareURL = handlers.fileForDrag()
            }
        }
    }

    /// Close and share on top; per-kind actions at the bottom.
    private var corners: some View {
        VStack {
            HStack(spacing: 5) {
                OverlayIconButton(systemImage: "xmark", help: "Close (⌥-click closes all)", action: handlers.close)
                Spacer()
                if let shareURL {
                    ShareLink(item: shareURL) {
                        OverlayIcon(systemImage: "square.and.arrow.up", isHighlighted: false)
                    }
                    .buttonStyle(OverlayPressStyle())
                    .help("Share")
                }
                if item.recording == nil {
                    OverlayIconButton(systemImage: "pin.fill", help: "Pin to screen", action: handlers.pin)
                }
            }
            Spacer()
            HStack(spacing: 5) {
                if item.recording == nil {
                    OverlayIconButton(systemImage: "pencil", help: "Annotate", action: handlers.edit)
                    Spacer()
                    OverlayIconButton(systemImage: "text.viewfinder", help: "Copy text (OCR)", action: handlers.copyText)
                } else {
                    // Clicking a recording's thumbnail plays it too; this says so.
                    OverlayIconButton(systemImage: "play.fill", help: "Play", action: handlers.edit)
                    Spacer()
                    OverlayIconButton(systemImage: "photo.stack", help: "Save as GIF", action: handlers.exportGIF)
                }
            }
        }
    }
}

/// Shrinks a touch while pressed.
private struct OverlayPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// Copy / Save: small dark glass capsules with white text.
private struct OverlayPillButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minWidth: 82, minHeight: 24)
                .background(
                    // Dark glass: blurs what's behind and stays readable over light screenshots.
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(.black.opacity(isHovered ? 0.32 : 0.5)))
                )
                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .contentShape(Capsule())
        }
        .buttonStyle(OverlayPressStyle())
        .onHover { isHovered = $0 }
    }
}

/// The small round buttons in the corners.
private struct OverlayIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            OverlayIcon(systemImage: systemImage, isHighlighted: isHovered)
        }
        .buttonStyle(OverlayPressStyle())
        .onHover { isHovered = $0 }
        .help(help)
    }
}

private struct OverlayIcon: View {
    let systemImage: String
    let isHighlighted: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(
                Circle().fill(.ultraThinMaterial)
                    .overlay(Circle().fill(.black.opacity(isHighlighted ? 0.32 : 0.5)))
            )
            .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .contentShape(Circle())
    }
}

private struct DurationBadge: View {
    let duration: TimeInterval

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "video.fill").font(.system(size: 8, weight: .bold))
            Text(Recording.formatDuration(duration)).font(.system(size: 10.5, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(.black.opacity(0.55)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
    }
}

/// The thumbnail. Also the drag source and the hover tracker, which live in AppKit so they keep
/// working while Snap isn't the active app.
private struct DragSource: NSViewRepresentable {
    let item: QuickAccessItem
    let handlers: QuickAccessHandlers

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView(image: item.capture.image)
        view.onHover = { [weak item] in item?.isHovered = $0 }
        view.fileForDrag = handlers.fileForDrag
        view.onDragEnded = handlers.dragEnded
        view.onSwipe = handlers.close
        view.onClick = handlers.edit
        return view
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {}
}

final class DragSourceView: NSView, NSDraggingSource {
    var onHover: ((Bool) -> Void)?
    var fileForDrag: (() -> URL?)?
    var onDragEnded: (() -> Void)?
    var onClick: (() -> Void)?

    private let image: CGImage
    private var mouseDownEvent: NSEvent?
    var onSwipe: (() -> Void)?
    /// Sideways trackpad scrolling so far in the current gesture.
    private var swipeDistance: CGFloat = 0

    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        // The card already has the image's proportions; fill covers any rounding difference.
        layer?.contentsGravity = .resizeAspectFill
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }

    override func mouseExited(with event: NSEvent) {
        // Moving onto a button drawn above us isn't leaving the card.
        guard let window, !window.frame.contains(NSEvent.mouseLocation) else { return }
        onHover?(false)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        let start = down.locationInWindow
        let now = event.locationInWindow
        guard hypot(now.x - start.x, now.y - start.y) > 3 else { return }
        mouseDownEvent = nil
        guard let url = fileForDrag?() else { return }

        let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
        let preview = NSImage(cgImage: image, size: bounds.size)
        draggingItem.setDraggingFrame(bounds, contents: preview)
        beginDraggingSession(with: [draggingItem], event: down, source: self)
    }

    /// A two-finger swipe sideways flicks the card away.
    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else { return }
        if event.phase == .began { swipeDistance = 0 }
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            swipeDistance += event.scrollingDeltaX
        }
        if abs(swipeDistance) > 50 {
            swipeDistance = 0
            onSwipe?()
        }
        if event.phase == .ended || event.phase == .cancelled { swipeDistance = 0 }
    }

    override func mouseUp(with event: NSEvent) {
        // Still set means the mouse never moved far enough to start a drag: a plain click.
        if mouseDownEvent != nil {
            onClick?()
        }
        mouseDownEvent = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation != [] {
            onDragEnded?()
        }
    }
}
