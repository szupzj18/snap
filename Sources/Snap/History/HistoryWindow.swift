import AppKit
import SnapCore
import SwiftUI

/// What the history window can do with an entry.
struct HistoryHandlers {
    let copy: (HistoryEntry) -> Void
    let edit: (HistoryEntry) -> Void
    let pin: (HistoryEntry) -> Void
    let reveal: (HistoryEntry) -> Void
}

@MainActor
final class HistoryWindowController {
    private let history: CaptureHistory
    private let handlers: HistoryHandlers
    private var window: NSWindow?

    init(history: CaptureHistory, handlers: HistoryHandlers) {
        self.history = history
        self.handlers = handlers
    }

    func show() {
        if window == nil {
            let window = HostingWindow.make(
                title: "Capture History",
                rootView: HistoryView(history: history, handlers: handlers),
                resizable: true
            )
            window.setContentSize(CGSize(width: 760, height: 520))
            window.minSize = CGSize(width: 420, height: 300)
            window.center()
            window.setFrameAutosaveName("History")
            self.window = window
        }
        HostingWindow.present(window!)
    }
}

struct HistoryView: View {
    @ObservedObject var history: CaptureHistory
    let handlers: HistoryHandlers
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(history.entries.isEmpty ? "No captures" : "\(history.entries.count) captures")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear History…", role: .destructive) { confirmClear = true }
                    .disabled(history.entries.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            content
        }
        .confirmationDialog("Delete all \(history.entries.count) captures from the history?", isPresented: $confirmClear) {
            Button("Delete All", role: .destructive) { history.clear() }
        } message: {
            Text("Files you saved elsewhere aren't affected.")
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if history.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("No captures yet").font(.headline)
                    Text("Captures you take show up here.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                        ForEach(history.entries) { entry in
                            HistoryCell(history: history, entry: entry, handlers: handlers)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}

private struct HistoryCell: View {
    let history: CaptureHistory
    let entry: HistoryEntry
    let handlers: HistoryHandlers

    @State private var thumbnail: CGImage?
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                }
                if isHovered {
                    HStack(spacing: 6) {
                        CellButton(systemImage: "doc.on.doc", help: "Copy") { handlers.copy(entry) }
                        CellButton(systemImage: "pencil", help: "Annotate") { handlers.edit(entry) }
                        CellButton(systemImage: "pin.fill", help: "Pin to screen") { handlers.pin(entry) }
                        CellButton(systemImage: "folder", help: "Show in Finder") { handlers.reveal(entry) }
                    }
                    .padding(6)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .frame(height: 120)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture(count: 2) { handlers.edit(entry) }
            .onDrag { NSItemProvider(contentsOf: history.fileURL(for: entry)) ?? NSItemProvider() }
            .contextMenu {
                Button("Copy") { handlers.copy(entry) }
                Button("Annotate…") { handlers.edit(entry) }
                Button("Pin to Screen") { handlers.pin(entry) }
                Button("Show in Finder") { handlers.reveal(entry) }
                Divider()
                Button("Delete", role: .destructive) { history.remove(entry) }
            }

            HStack {
                Text(entry.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                Spacer()
                Text(verbatim: "\(entry.pixelWidth) × \(entry.pixelHeight)").monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .task(id: entry.id) {
            let url = history.fileURL(for: entry)
            thumbnail = await Task.detached(priority: .utility) {
                history.thumbnail(for: url, maxPixelSize: 400)
            }.value
        }
    }
}

private struct CellButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.9), in: Circle())
                .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
