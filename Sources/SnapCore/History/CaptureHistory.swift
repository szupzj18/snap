import Combine
import CoreGraphics
import Foundation
import ImageIO

/// A capture kept in the history.
public struct HistoryEntry: Codable, Identifiable, Equatable {
    public let id: UUID
    public let date: Date
    public let mode: String
    public let appName: String?
    public let scale: CGFloat
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let sourceRect: CGRect
    public let displayID: CGDirectDisplayID?
}

/// Recent captures stored as PNG files plus an index, newest first.
@MainActor
public final class CaptureHistory: ObservableObject {
    @Published public private(set) var entries: [HistoryEntry] = []

    public let directory: URL
    /// How many captures to keep; older ones are deleted.
    public var limit: Int {
        didSet { prune() }
    }

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    public init(directory: URL, limit: Int) {
        self.directory = directory
        self.limit = limit
        load()
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Snap")
            .appendingPathComponent("History")
    }

    public func fileURL(for entry: HistoryEntry) -> URL {
        directory.appendingPathComponent("\(entry.id.uuidString).png")
    }

    /// Stores a capture. The PNG is encoded off the main thread; the entry appears once it's written.
    public func add(_ capture: Capture) async throws {
        let entry = HistoryEntry(
            id: capture.id,
            date: capture.date,
            mode: capture.mode.rawValue,
            appName: capture.appName,
            scale: capture.scale,
            pixelWidth: capture.image.width,
            pixelHeight: capture.image.height,
            sourceRect: capture.sourceRect,
            displayID: capture.displayID
        )
        let url = fileURL(for: entry)
        let directory = directory
        let image = capture.image
        let scale = capture.scale
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try ImageExporter.pngData(image, scale: scale).write(to: url, options: .atomic)
        }.value
        entries.insert(entry, at: 0)
        prune()
        try saveIndex()
    }

    /// Rebuilds a `Capture` from a stored entry, or nil if its file is gone.
    public func capture(for entry: HistoryEntry) -> Capture? {
        guard let source = CGImageSourceCreateWithURL(fileURL(for: entry) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return Capture(
            image: image,
            scale: entry.scale,
            mode: CaptureMode(rawValue: entry.mode) ?? .area,
            sourceRect: entry.sourceRect,
            displayID: entry.displayID,
            appName: entry.appName,
            date: entry.date
        )
    }

    /// A small version for the history grid, decoded without loading the full image.
    public nonisolated func thumbnail(for url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    public func remove(_ entry: HistoryEntry) {
        try? FileManager.default.removeItem(at: fileURL(for: entry))
        entries.removeAll { $0.id == entry.id }
        try? saveIndex()
    }

    public func clear() {
        entries.forEach { try? FileManager.default.removeItem(at: fileURL(for: $0)) }
        entries = []
        try? saveIndex()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let stored = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        // Drop entries whose image was deleted behind our back.
        entries = stored.filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
        prune()
    }

    private func prune() {
        guard entries.count > max(limit, 0) else { return }
        let removed = entries[max(limit, 0)...]
        removed.forEach { try? FileManager.default.removeItem(at: fileURL(for: $0)) }
        entries.removeLast(removed.count)
        try? saveIndex()
    }

    private func saveIndex() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: indexURL, options: .atomic)
    }
}
