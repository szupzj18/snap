import CoreGraphics

/// Arrow-key nudges for things the user positions by hand (pins, selections).
public enum KeyNudge {
    /// Points to move for an arrow key, in AppKit coordinates (y grows up): 1 pt, or 10 with Shift.
    /// Nil for any other key.
    public static func offset(keyCode: UInt16, shift: Bool) -> CGVector? {
        let step: CGFloat = shift ? 10 : 1
        switch keyCode {
        case 123: return CGVector(dx: -step, dy: 0) // ←
        case 124: return CGVector(dx: step, dy: 0) // →
        case 125: return CGVector(dx: 0, dy: -step) // ↓
        case 126: return CGVector(dx: 0, dy: step) // ↑
        default: return nil
        }
    }
}
