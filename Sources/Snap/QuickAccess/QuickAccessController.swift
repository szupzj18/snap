import AppKit
import Combine
import SnapCore
import SwiftUI

/// One capture shown in Quick Access.
@MainActor
final class QuickAccessItem: ObservableObject {
    let capture: Capture
    @Published var savedURL: URL?
    @Published var isHovered = false

    init(capture: Capture, savedURL: URL?) {
        self.capture = capture
        self.savedURL = savedURL
    }
}

/// Stacks capture previews in the bottom-right corner of the screen they were taken on.
@MainActor
final class QuickAccessController {
    private let settings: AppSettings
    private let actions: CaptureActions
    private let pins: PinController
    private let editors: EditorPresenter
    /// Oldest first.
    private var cards: [QuickAccessCard] = []
    private let maximumCards = 5

    init(settings: AppSettings, actions: CaptureActions, pins: PinController, editors: EditorPresenter) {
        self.settings = settings
        self.actions = actions
        self.pins = pins
        self.editors = editors
    }

    func show(_ capture: Capture, savedURL: URL?) {
        let screen = capture.displayID.flatMap(NSScreen.screen(for:)) ?? NSScreen.underMouse ?? NSScreen.screens[0]
        let item = QuickAccessItem(capture: capture, savedURL: savedURL)
        let card = QuickAccessCard(item: item, screen: screen, handlers: handlers(for: item))
        cards.append(card)
        if cards.count > maximumCards {
            close(cards[0])
        }
        layout(appearing: card)
        card.startAutoClose(after: settings.quickAccessAutoClose)
    }

    private func handlers(for item: QuickAccessItem) -> QuickAccessHandlers {
        QuickAccessHandlers(
            copy: { [weak self, weak item] in
                guard let self, let item else { return }
                self.perform { try self.actions.copy(item.capture) }
                self.close(item)
            },
            save: { [weak self, weak item] in
                guard let self, let item else { return }
                if let url = item.savedURL {
                    self.actions.revealInFinder(url)
                } else {
                    self.perform { item.savedURL = try self.actions.save(item.capture) }
                }
                self.close(item)
            },
            edit: { [weak self, weak item] in
                guard let self, let item else { return }
                self.editors.edit(item.capture)
                self.close(item)
            },
            pin: { [weak self, weak item] in
                guard let self, let item else { return }
                self.pins.pin(item.capture)
                self.close(item)
            },
            close: { [weak self, weak item] in
                guard let self, let item else { return }
                self.close(item)
            },
            fileForDrag: { [weak self, weak item] in
                guard let self, let item else { return nil }
                return try? self.actions.draggableFile(for: item.capture, savedURL: item.savedURL)
            },
            dragEnded: { [weak self, weak item] in
                guard let self, let item else { return }
                self.close(item)
            }
        )
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { ErrorPresenter.present(error) }
    }

    private func close(_ item: QuickAccessItem) {
        if let card = cards.first(where: { $0.item === item }) {
            close(card)
        }
    }

    private func close(_ card: QuickAccessCard) {
        cards.removeAll { $0 === card }
        card.dismiss()
        layout(appearing: nil)
    }

    /// Newest card at the bottom, older ones pushed up, per screen.
    private func layout(appearing newCard: QuickAccessCard?) {
        let margin: CGFloat = 16
        let spacing: CGFloat = 12
        var nextY: [NSScreen: CGFloat] = [:]
        for card in cards.reversed() {
            let visible = card.screen.visibleFrame
            let y = nextY[card.screen] ?? visible.minY + margin
            let size = card.size
            let frame = CGRect(x: visible.maxX - margin - size.width, y: y, width: size.width, height: size.height)
            nextY[card.screen] = y + size.height + spacing
            if card === newCard {
                card.slideIn(to: frame)
            } else {
                card.move(to: frame)
            }
        }
    }
}

struct QuickAccessHandlers {
    let copy: () -> Void
    let save: () -> Void
    let edit: () -> Void
    let pin: () -> Void
    let close: () -> Void
    let fileForDrag: () -> URL?
    let dragEnded: () -> Void
}

/// The floating panel for one preview.
@MainActor
final class QuickAccessCard {
    let item: QuickAccessItem
    let screen: NSScreen
    let size: CGSize
    private let panel: QuickAccessPanel
    private var timer: Timer?
    private var autoClose: TimeInterval = 0
    private var hoverObservation: AnyCancellable?
    private let onTimeout: () -> Void

    init(item: QuickAccessItem, screen: NSScreen, handlers: QuickAccessHandlers) {
        self.item = item
        self.screen = screen
        onTimeout = handlers.close
        size = Self.cardSize(for: item.capture.pointSize)
        panel = QuickAccessPanel(contentRect: CGRect(origin: .zero, size: size))
        let host = FirstMouseHostingView(rootView: QuickAccessCardView(item: item, handlers: handlers))
        host.frame = CGRect(origin: .zero, size: size)
        panel.contentView = host
        hoverObservation = item.$isHovered.sink { [weak self] hovered in
            self?.hoverChanged(hovered)
        }
    }

    /// Fits the thumbnail into a card no wider than 240pt and between 110 and 200pt tall.
    private static func cardSize(for imageSize: CGSize) -> CGSize {
        let width: CGFloat = 240
        let aspect = imageSize.height / max(imageSize.width, 1)
        return CGSize(width: width, height: min(max(width * aspect, 110), 200).rounded())
    }

    func startAutoClose(after seconds: TimeInterval) {
        autoClose = seconds
        restartTimer()
    }

    private func hoverChanged(_ hovered: Bool) {
        if hovered {
            timer?.invalidate()
            timer = nil
        } else {
            restartTimer()
        }
    }

    private func restartTimer() {
        timer?.invalidate()
        guard autoClose > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: autoClose, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTimeout() }
        }
    }

    func slideIn(to frame: CGRect) {
        panel.setFrame(frame.offsetBy(dx: frame.width + 40, dy: 0), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func move(to frame: CGRect) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().setFrame(frame, display: true)
        }
    }

    func dismiss() {
        timer?.invalidate()
        hoverObservation = nil
        let panel = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }
}

/// Floats above normal windows without ever taking focus from the app the user is in.
final class QuickAccessPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
}

/// Lets the first click on an inactive panel hit buttons instead of being swallowed.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
