import Combine
import Foundation

/// Things that can happen automatically right after a capture. Several can be on at once.
public enum AfterCaptureAction: String, CaseIterable, Identifiable {
    case save
    case copyToClipboard

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .save: "Save to folder"
        case .copyToClipboard: "Copy to clipboard"
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

    public static let defaultSaveDirectory = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    public static let defaultAfterCapture: Set<AfterCaptureAction> = [.save]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        saveDirectory = defaults.string(forKey: Key.saveDirectory).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? Self.defaultSaveDirectory
        filenameTemplate = defaults.string(forKey: Key.filenameTemplate) ?? FilenameFormatter.defaultTemplate
        afterCapture = defaults.stringArray(forKey: Key.afterCapture)
            .map { Set($0.compactMap(AfterCaptureAction.init(rawValue:))) }
            ?? Self.defaultAfterCapture
        windowShadow = defaults.object(forKey: Key.windowShadow) as? Bool ?? true
    }

    public func filename(for capture: Capture) -> String {
        FilenameFormatter.filename(template: filenameTemplate, date: capture.date, mode: capture.mode, appName: capture.appName)
    }
}
