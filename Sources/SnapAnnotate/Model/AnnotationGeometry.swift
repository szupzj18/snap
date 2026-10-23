import AppKit

extension Annotation {
    /// The area the annotation covers, in image pixels.
    public var bounds: CGRect {
        let pad = lineWidth / 2
        switch shape {
        case let .arrow(from, to):
            return CGRect(x: min(from.x, to.x), y: min(from.y, to.y), width: abs(to.x - from.x), height: abs(to.y - from.y))
                .insetBy(dx: -pad * 3, dy: -pad * 3)
        case let .rectangle(rect), let .ellipse(rect):
            return rect.insetBy(dx: -pad, dy: -pad)
        case let .line(from, to):
            return CGRect(x: min(from.x, to.x), y: min(from.y, to.y), width: abs(to.x - from.x), height: abs(to.y - from.y))
                .insetBy(dx: -pad, dy: -pad)
        case let .freehand(points):
            let xs = points.map(\.x), ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .null }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -pad, dy: -pad)
        case let .highlight(rect), let .pixelate(rect), let .blur(rect), let .spotlight(rect):
            return rect
        case let .text(origin, string, fontSize):
            let size = AnnotationRenderer.attributedText(string, fontSize: fontSize, color: color).size()
            return CGRect(origin: origin, size: size)
        case let .counter(center, _, radius):
            return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        }
    }

    /// Whether a click at `point` (image pixels) lands on the annotation. Outlines only count on
    /// their stroke, so whatever sits inside a rectangle stays clickable.
    public func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        let reach = lineWidth / 2 + tolerance
        switch shape {
        case let .arrow(from, to):
            return Self.distance(from: point, toSegment: from, to) <= reach
        case let .rectangle(rect):
            return rect.insetBy(dx: -reach, dy: -reach).contains(point)
                && !rect.insetBy(dx: reach, dy: reach).contains(point)
        case let .ellipse(rect):
            // On the outline: inside the ellipse grown by `reach`, outside the one shrunk by it.
            return Self.ellipse(rect.insetBy(dx: -reach, dy: -reach), contains: point)
                && !Self.ellipse(rect.insetBy(dx: reach, dy: reach), contains: point)
        case let .line(from, to):
            return Self.distance(from: point, toSegment: from, to) <= reach
        case let .freehand(points):
            guard points.count > 1 else { return points.first.map { hypot(point.x - $0.x, point.y - $0.y) <= reach } ?? false }
            return zip(points, points.dropFirst()).contains { Self.distance(from: point, toSegment: $0, $1) <= reach }
        case let .highlight(rect), let .pixelate(rect), let .blur(rect), let .spotlight(rect):
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .text:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case let .counter(center, _, radius):
            return hypot(point.x - center.x, point.y - center.y) <= radius + tolerance
        }
    }

    public func moved(by delta: CGVector) -> Annotation {
        func shift(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x + delta.dx, y: point.y + delta.dy) }
        func shift(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: delta.dx, dy: delta.dy) }
        var copy = self
        switch shape {
        case let .arrow(from, to): copy.shape = .arrow(from: shift(from), to: shift(to))
        case let .rectangle(rect): copy.shape = .rectangle(shift(rect))
        case let .ellipse(rect): copy.shape = .ellipse(shift(rect))
        case let .line(from, to): copy.shape = .line(from: shift(from), to: shift(to))
        case let .freehand(points): copy.shape = .freehand(points.map(shift))
        case let .spotlight(rect): copy.shape = .spotlight(shift(rect))
        case let .highlight(rect): copy.shape = .highlight(shift(rect))
        case let .pixelate(rect): copy.shape = .pixelate(shift(rect))
        case let .blur(rect): copy.shape = .blur(shift(rect))
        case let .text(origin, string, fontSize): copy.shape = .text(origin: shift(origin), string: string, fontSize: fontSize)
        case let .counter(center, number, radius): copy.shape = .counter(center: shift(center), number: number, radius: radius)
        }
        return copy
    }

    /// The same annotation drawn at another preset size. `scale` is the capture's pixels per point.
    public func resized(to size: AnnotationSize, scale: CGFloat) -> Annotation {
        var copy = self
        switch shape {
        case let .text(origin, string, _):
            copy.shape = .text(origin: origin, string: string, fontSize: size.fontSize * scale)
        case let .counter(center, number, _):
            copy.shape = .counter(center: center, number: number, radius: size.counterRadius * scale)
        case .arrow, .rectangle, .ellipse, .line, .freehand:
            copy.lineWidth = size.lineWidth * scale
        case .highlight, .pixelate, .blur, .spotlight:
            break
        }
        return copy
    }

    static func ellipse(_ rect: CGRect, contains point: CGPoint) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        let dx = (point.x - rect.midX) / (rect.width / 2)
        let dy = (point.y - rect.midY) / (rect.height / 2)
        return dx * dx + dy * dy <= 1
    }

    static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }
}

extension AnnotationDocument {
    /// The topmost annotation under `point`.
    public func annotation(at point: CGPoint, tolerance: CGFloat) -> Annotation? {
        annotations.last { $0.contains(point, tolerance: tolerance) }
    }
}
