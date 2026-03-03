import Foundation

/// A range of time on the timeline defined by start + duration.
public struct TimeRange: Sendable, Hashable, Codable {
    public let start: Rational
    public let duration: Rational

    public var end: Rational { start + duration }

    public init(start: Rational, duration: Rational) {
        self.start = start
        self.duration = duration
    }

    public init(start: Rational, end: Rational) {
        self.start = start
        self.duration = end - start
    }

    public static let zero = TimeRange(start: .zero, duration: .zero)

    public func contains(_ time: Rational) -> Bool {
        time >= start && time < end
    }

    public func overlaps(_ other: TimeRange) -> Bool {
        start < other.end && other.start < end
    }

    public func intersection(_ other: TimeRange) -> TimeRange? {
        let overlapStart = Swift.max(start, other.start)
        let overlapEnd = Swift.min(end, other.end)
        guard overlapStart < overlapEnd else { return nil }
        return TimeRange(start: overlapStart, end: overlapEnd)
    }

    public func union(_ other: TimeRange) -> TimeRange {
        let unionStart = Swift.min(start, other.start)
        let unionEnd = Swift.max(end, other.end)
        return TimeRange(start: unionStart, end: unionEnd)
    }
}
