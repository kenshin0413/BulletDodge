import CoreGraphics
import Foundation

extension CGVector {
    static let zero = CGVector(dx: 0, dy: 0)

    var length: CGFloat {
        sqrt(dx * dx + dy * dy)
    }

    var normalized: CGVector {
        let length = length
        guard length > 0 else { return .zero }
        return CGVector(dx: dx / length, dy: dy / length)
    }

    func rotated(by angle: CGFloat) -> CGVector {
        let cosValue = cos(angle)
        let sinValue = sin(angle)
        return CGVector(
            dx: dx * cosValue - dy * sinValue,
            dy: dx * sinValue + dy * cosValue
        )
    }

    func perpendicular(sign: CGFloat) -> CGVector {
        CGVector(dx: -dy * sign, dy: dx * sign).normalized
    }

    static func * (lhs: CGVector, rhs: CGFloat) -> CGVector {
        CGVector(dx: lhs.dx * rhs, dy: lhs.dy * rhs)
    }

    static func + (lhs: CGVector, rhs: CGVector) -> CGVector {
        CGVector(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy)
    }

}

extension CGPoint {
    func clamped(in rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(x, rect.minX), rect.maxX),
            y: min(max(y, rect.minY), rect.maxY)
        )
    }

    static func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        sqrt(pow(end.x - start.x, 2) + pow(end.y - start.y, 2))
    }
}
