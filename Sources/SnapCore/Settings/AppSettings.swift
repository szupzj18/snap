import Combine
import Foundation

/// Things that can happen automatically right after a capture. Several can be on at once.
public enum AfterCaptureAction: String, CaseIterable, Identifiable {
    case showQuickAccess
    case save
    case copyToClipboard
    case openEditor
    case pin

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .showQuickAccess: "Show Quick Access preview"
        case .save: "Save to folder"
        case .copyToClipboard: "Copy to clipboard"
        case .openEditor: "Open in editor"
        case .pin: "Pin to screen"
        }
    }
}

/// User preferences, persisted in UserDefaults.
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private enum Key {
        static let saveDirectory = "saveDirectory"
        static let filenameTemplate = "filenameTemplate"
        static let afterCapture = "afterCapture"
        static let windowShadow = "windowShadow"
        static let quickAccessAutoClose = "quickAccessAutoClose"
        static let historyEnabled = "historyEnabled"
        static let historyLimit = "historyLimit"
        static let recordingFPS = "recordingFPS"
        static let recordingShowsCursor = "recordingShowsCursor"
    }

    private let defaults: UserDefaults

    @Published public var saveDirectory: URL {
        didSet { defaults.set(saveDirectory.path, forKey: Key.saveDirectory) }
    }

    @Published public var filenameTemplate: String {
        didSet { defaults.set(filenameTemplate, forKey: Key.filenameTemplate) }
    }

    @Published public var afterCapture: Set<AfterCaptureAction> {
        didSet { defaults.set(afterCapture.map(\.rawValue).sorted(), forKey: Key.afterCapture) }
    }

    /// Whether window captures get a drop shadow.
    @Published public var windowShadow: Bool {
        didSet { defaults.set(windowShadow, forKey: Key.windowShadow) }
    }

    /// Seconds before an untouched Quick Access preview closes itself; 0 keeps it open.
    @Published public var quickAccessAutoClose: TimeInterval {
        didSet { defaults.set(quickAccessAutoClose, forKey: Key.quickAccessAutoClose) }
    }

    /// Whether every capture is also kept in the history.
    @Published public var historyEnabled: Bool {
        didSet { defaults.set(historyEnabled, forKey: Key.historyEnabled) }
    }

    /// How many captures the history keeps.
    @Published public var historyLimit: Int {
        didSet { defaults.set(historyLimit, forKey: Key.historyLimit) }
    }

    @Published public var recordingFPS: Int {
        didSet { defaults.set(recordingFPS, forKey: Key.recordingFPS) }
    }

    @Published public var recordingShowsCursor: Bool {
        didSet { defaults.set(recordingShowsCursor, forKey: Key.recordingShowsCursor) }
    }

    public static let defaultSaveDirectory = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    public static let defaultAfterCapture: Set<AfterCaptureAction> = [.showQuickAccess, .save]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        saveDirectory = defaults.string(forKey: Key.saveDirectory).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? Self.defaultSaveDirectory
        filenameTemplate = defaults.string(forKey: Key.filenameTemplate) ?? FilenameFormatter.defaultTemplate
        afterCapture = defaults.stringArray(forKey: Key.afterCapture)
            .map { Set($0.compactMap(AfterCaptureAction.init(rawValue:))) }
            ?? Self.defaultAfterCapture
        windowShadow = defaults.object(forKey: Key.windowShadow) as? Bool ?? true
        quickAccessAutoClose = defaults.object(forKey: Key.quickAccessAutoClose) as? TimeInterval ?? 5
        historyEnabled = defaults.object(forKey: Key.historyEnabled) as? Bool ?? true
        historyLimit = defaults.object(forKey: Key.historyLimit) as? Int ?? 50
        recordingFPS = defaults.object(forKey: Key.recordingFPS) as? Int ?? 30
        recordingShowsCursor = defaults.object(forKey: Key.recordingShowsCursor) as? Bool ?? true
    }

    public func filename(for capture: Capture) -> String {
        FilenameFormatter.filename(template: filenameTemplate, date: capture.date, mode: capture.mode, appName: capture.appName)
    }
}
