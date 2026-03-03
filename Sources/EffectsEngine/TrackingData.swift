import CoreMediaPlus
import Foundation

/// Stores a sequence of tracking results and provides temporal interpolation.
///
/// Tracking data is produced by `MotionTracker` and consumed by `LinkedEffect`
/// to drive effect parameters from tracked object motion.
public struct TrackingData: Sendable, Codable, Equatable {
    /// Ordered keyframes from the tracker (must be sorted by time ascending).
    public var samples: [TrackingResult]

    public init(samples: [TrackingResult] = []) {
        self.samples = samples
    }

    /// Whether this tracking data contains any samples.
    public var isEmpty: Bool { samples.isEmpty }

    /// Time range covered by the tracking data.
    public var timeRange: (start: Rational, end: Rational)? {
        guard let first = samples.first, let last = samples.last else { return nil }
        return (first.time, last.time)
    }

    // MARK: - Interpolation

    /// Linearly interpolated position (center of bounding box) at the given time.
    public func positionAt(time: Rational) -> CGPoint {
        let box = boundingBoxAt(time: time)
        return CGPoint(x: box.midX, y: box.midY)
    }

    /// Interpolated scale derived from the bounding box dimensions at the given time.
    public func scaleAt(time: Rational) -> CGSize {
        let box = boundingBoxAt(time: time)
        return CGSize(width: box.width, height: box.height)
    }

    /// Linearly interpolated bounding box at the given time.
    ///
    /// - Before the first sample: returns the first sample's bounding box.
    /// - After the last sample: returns the last sample's bounding box.
    /// - Between samples: linearly interpolates origin and size.
    public func boundingBoxAt(time: Rational) -> CGRect {
        guard !samples.isEmpty else { return .zero }
        guard samples.count > 1 else { return samples[0].boundingBox }

        let first = samples[0]
        if time <= first.time { return first.boundingBox }

        let last = samples[samples.count - 1]
        if time >= last.time { return last.boundingBox }

        // Find surrounding samples
        var lowerIndex = 0
        for i in 0..<samples.count {
            if samples[i].time <= time {
                lowerIndex = i
            } else {
                break
            }
        }
        let upperIndex = lowerIndex + 1
        guard upperIndex < samples.count else { return samples[lowerIndex].boundingBox }

        let lower = samples[lowerIndex]
        let upper = samples[upperIndex]

        let duration = upper.time - lower.time
        guard duration.seconds > 0 else { return lower.boundingBox }

        let elapsed = time - lower.time
        let t = elapsed.seconds / duration.seconds

        return CGRect(
            x: lerp(lower.boundingBox.origin.x, upper.boundingBox.origin.x, t),
            y: lerp(lower.boundingBox.origin.y, upper.boundingBox.origin.y, t),
            width: lerp(lower.boundingBox.size.width, upper.boundingBox.size.width, t),
            height: lerp(lower.boundingBox.size.height, upper.boundingBox.size.height, t)
        )
    }

    /// Interpolated confidence at the given time.
    public func confidenceAt(time: Rational) -> Float {
        guard !samples.isEmpty else { return 0 }
        guard samples.count > 1 else { return samples[0].confidence }

        let first = samples[0]
        if time <= first.time { return first.confidence }

        let last = samples[samples.count - 1]
        if time >= last.time { return last.confidence }

        var lowerIndex = 0
        for i in 0..<samples.count {
            if samples[i].time <= time {
                lowerIndex = i
            } else {
                break
            }
        }
        let upperIndex = lowerIndex + 1
        guard upperIndex < samples.count else { return samples[lowerIndex].confidence }

        let lower = samples[lowerIndex]
        let upper = samples[upperIndex]

        let duration = upper.time - lower.time
        guard duration.seconds > 0 else { return lower.confidence }

        let elapsed = time - lower.time
        let t = Float(elapsed.seconds / duration.seconds)
        return lower.confidence + (upper.confidence - lower.confidence) * t
    }
}

// MARK: - Private Helpers

private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}
