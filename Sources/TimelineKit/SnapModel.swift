import Foundation
import Observation
import CoreMediaPlus

/// Reference-counted snap points on the timeline.
@Observable
public final class SnapModel: @unchecked Sendable {
    private var points: [Rational: Int] = [:]
    public var snapThreshold: Rational = Rational(1, 10)
    public var isEnabled: Bool = true

    public init() {}

    public func addPoint(_ position: Rational) {
        points[position, default: 0] += 1
    }

    public func removePoint(_ position: Rational) {
        guard let count = points[position] else { return }
        if count <= 1 { points.removeValue(forKey: position) }
        else { points[position] = count - 1 }
    }

    public func snap(_ position: Rational) -> Rational {
        guard isEnabled else { return position }
        var closest: Rational?
        var minDistance = snapThreshold
        for point in points.keys {
            let distance = (point - position).abs
            if distance < minDistance {
                minDistance = distance
                closest = point
            }
        }
        return closest ?? position
    }

    public func rebuild(clipEdges: [(start: Rational, end: Rational)]) {
        points.removeAll()
        for edge in clipEdges {
            addPoint(edge.start)
            addPoint(edge.end)
        }
    }
}
