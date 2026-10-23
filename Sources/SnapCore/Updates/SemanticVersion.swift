import Foundation

/// A `major.minor.patch[-prerelease]` version, as used for release tags (`v0.2.0`, `0.3.0-beta.1`).
public struct SemanticVersion: Comparable, CustomStringConvertible {
    public let numbers: [Int]
    /// Text after `-`, if any. A pre-release sorts before the release it leads up to.
    public let prerelease: String?

    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        let parts = text.split(separator: "-", maxSplits: 1)
        guard let core = parts.first else { return nil }
        let numbers = core.split(separator: ".").map { Int($0) }
        guard !numbers.isEmpty, numbers.count <= 3, numbers.allSatisfy({ $0 != nil }) else { return nil }
        self.numbers = numbers.compactMap { $0 } + Array(repeating: 0, count: 3 - numbers.count)
        prerelease = parts.count > 1 ? String(parts[1]) : nil
    }

    public var description: String {
        numbers.map(String.init).joined(separator: ".") + (prerelease.map { "-\($0)" } ?? "")
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.numbers != rhs.numbers {
            return lhs.numbers.lexicographicallyPrecedes(rhs.numbers)
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil), (nil, _): return false
        case (_, nil): return true
        case let (left?, right?): return left.compare(right, options: .numeric) == .orderedAscending
        }
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.numbers == rhs.numbers && lhs.prerelease == rhs.prerelease
    }
}
