import AppKit
import SwiftUI

/// A button on a toast, for the one thing the user may want to do next.
struct ToastAction {
    let title: String
    let perform: @MainActor () -> Void
}

/// A short message near the bottom of the screen that fades by itself and never takes focus.
@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    /// With an `action`, the toast takes clicks and stays a little longer so there's time to use it.
    static func show(_ message: String, systemImage: String, on screen: NSScreen? = NSScreen.underMouse, action: ToastAction? = nil) {
        guard let screen else { return }
        let button = action.map { action in
            ToastAction(title: action.title) {
                hide()
                action.perform()
            }
        }
        let host = NSHostingView(rootView: ToastView(message: message, systemImage: systemImage, action: button))
        let size = host.fittingSize
        let frame = CGRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + 80,
            width: size.width,
            height: size.height
        )

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = host
        panel.ignoresMouseEvents = action == nil
        panel.setFrame(frame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (action == nil ? 1.6 : 4), execute: work)
    }

    private static func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Not .statusBar: windows at that level are kept in screenshots (it's where the menu bar icon lives).
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        return panel
    }
}

private struct ToastView: View {
    let message: String
    let systemImage: String
    let action: ToastAction?

    var body: some View {
        HStack(spacing: 10) {
            Label(message, systemImage: systemImage)
            if let action {
                Button(action.title) { action.perform() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .fixedSize()
    }
}
