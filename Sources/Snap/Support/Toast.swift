import AppKit
import SwiftUI

/// A short message near the bottom of the screen that fades by itself and never takes focus.
@MainActor
enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ message: String, systemImage: String, on screen: NSScreen? = NSScreen.underMouse) {
        guard let screen else { return }
        let host = NSHostingView(rootView: ToastView(message: message, systemImage: systemImage))
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
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

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .fixedSize()
    }
}
