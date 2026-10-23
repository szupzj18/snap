import Foundation

/// Expands a filename template such as `Snap {date} at {time}` into a file name (without extension).
public enum FilenameFormatter {
    public static let defaultTemplate = "Snap {date} at {time}"

    /// Supported tokens and what they expand to, for display in settings.
    public static let tokens: [(token: String, meaning: String)] = [
        ("{date}", "Date, e.g. 2026-10-22"),
        ("{time}", "Time, e.g. 15.04.05"),
        ("{mode}", "Capture mode: Area, Window, Fullscreen, Scrolling or Recording"),
        ("{app}", "App name for window captures"),
    ]

    public static func filename(
        template: String,
        date: Date,
        mode: CaptureMode,
        appName: String? = nil,
        timeZone: TimeZone = .current
    ) -> String {
        var result = template
        result = result.replacingOccurrences(of: "{date}", with: format(date, "yyyy-MM-dd", timeZone))
        result = result.replacingOccurrences(of: "{time}", with: format(date, "HH.mm.ss", timeZone))
        result = result.replacingOccurrences(of: "{mode}", with: mode.title)
        result = result.replacingOccurrences(of: "{app}", with: appName ?? "")
        return sanitize(result)
    }

    private static func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// Removes path separators and collapses the whitespace left behind by empty tokens.
    private static func sanitize(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return trimmed.isEmpty ? "Screenshot" : trimmed
    }
}
