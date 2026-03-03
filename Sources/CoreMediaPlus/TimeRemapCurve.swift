import CoreMedia
import Foundation

/// A time remapping curve that maps output (timeline) time to source (media) time.
/// Used for variable speed effects (speed ramps) on clips.
///
/// Each keyframe maps an output time offset to a source time offset, with bezier
/// interpolation between keyframes for smooth speed transitions.
public struct TimeRemapCurve: Sendable, Codable, Hashable {
    /// Keyframes mapping output time offset (seconds) to source time offset (seconds).
    /// Both times are relative to the clip's start/source-in point.
    public var keyframes: [RemapKeyframe]

    public init(keyframes: [RemapKeyframe] = []) {
        self.keyframes = keyframes.sorted { $0.outputTime < $1.outputTime }
    }

    public struct RemapKeyframe: Sendable, Codable, Hashable {
        /// Output time offset in seconds (timeline-relative from clip start).
        public var outputTime: Double
        /// Source time offset in seconds (source-relative from clip sourceIn).
        public var sourceTime: Double
        /// Bezier control point leaving this keyframe (normalized, x=time fraction, y=value fraction).
        public var outTangent: CodablePoint
        /// Bezier control point entering the next keyframe (normalized).
        public var inTangent: CodablePoint

        public init(outputTime: Double, sourceTime: Double,
                    outTangent: CodablePoint = CodablePoint(x: 0.333, y: 0.333),
                    inTangent: CodablePoint = CodablePoint(x: 0.667, y: 0.667)) {
            self.outputTime = outputTime
            self.sourceTime = sourceTime
            self.outTangent = outTangent
            self.inTangent = inTangent
        }
    }

    /// The total output duration of the clip with this remap curve applied.
    public var outputDuration: Double? {
        keyframes.last?.outputTime
    }

    /// Maps an output time offset to a source time offset using bezier interpolation.
    public func sourceTime(at outputTime: Double) -> Double {
        guard !keyframes.isEmpty else { return outputTime }
        guard keyframes.count > 1 else { return keyframes[0].sourceTime }

        // Before first keyframe
        if outputTime <= keyframes[0].outputTime {
            return keyframes[0].sourceTime
        }

        // After last keyframe: hold at last source time
        if outputTime >= keyframes[keyframes.count - 1].outputTime {
            return keyframes[keyframes.count - 1].sourceTime
        }

        // Find the surrounding keyframes
        var lowerIndex = 0
        for i in 0..<keyframes.count {
            if keyframes[i].outputTime <= outputTime {
                lowerIndex = i
            } else {
                break
            }
        }
        let upperIndex = lowerIndex + 1
        guard upperIndex < keyframes.count else { return keyframes[lowerIndex].sourceTime }

        let lower = keyframes[lowerIndex]
        let upper = keyframes[upperIndex]

        let segmentDuration = upper.outputTime - lower.outputTime
        guard segmentDuration > 0 else { return lower.sourceTime }

        let timeFraction = (outputTime - lower.outputTime) / segmentDuration

        // Solve the bezier curve in the time domain
        let u = solveCubicBezierX(timeFraction: timeFraction,
                                   p1x: lower.outTangent.x, p2x: upper.inTangent.x)
        let valueFraction = cubicBezierY(u: u, p1y: lower.outTangent.y, p2y: upper.inTangent.y)

        let sourceDuration = upper.sourceTime - lower.sourceTime
        return lower.sourceTime + sourceDuration * valueFraction
    }

    /// Creates a simple constant-speed remap curve (equivalent to uniform speed change).
    public static func constantSpeed(_ speed: Double, sourceDuration: Double) -> TimeRemapCurve {
        guard speed > 0 else { return TimeRemapCurve() }
        let outputDuration = sourceDuration / speed
        return TimeRemapCurve(keyframes: [
            RemapKeyframe(outputTime: 0, sourceTime: 0),
            RemapKeyframe(outputTime: outputDuration, sourceTime: sourceDuration),
        ])
    }

    // MARK: - Private Bezier Solving

    private func solveCubicBezierX(timeFraction: Double, p1x: Double, p2x: Double) -> Double {
        let t = min(max(timeFraction, 0.0), 1.0)
        let cx = 3.0 * p1x
        let bx = 3.0 * (p2x - p1x) - cx
        let ax = 1.0 - cx - bx

        // Newton-Raphson iteration
        var u = t
        for _ in 0..<8 {
            let xValue = ((ax * u + bx) * u + cx) * u - t
            if Swift.abs(xValue) < 1e-7 { return u }
            let derivative = (3.0 * ax * u + 2.0 * bx) * u + cx
            if Swift.abs(derivative) < 1e-7 { break }
            u -= xValue / derivative
        }

        // Bisection fallback
        var lo = 0.0
        var hi = 1.0
        u = t
        for _ in 0..<20 {
            let xValue = ((ax * u + bx) * u + cx) * u
            if Swift.abs(xValue - t) < 1e-7 { return u }
            if t > xValue { lo = u } else { hi = u }
            u = (lo + hi) * 0.5
        }
        return u
    }

    private func cubicBezierY(u: Double, p1y: Double, p2y: Double) -> Double {
        let cy = 3.0 * p1y
        let by = 3.0 * (p2y - p1y) - cy
        let ay = 1.0 - cy - by
        return ((ay * u + by) * u + cy) * u
    }
}

/// A simple Codable, Hashable, Sendable 2D point.
/// Used instead of CGPoint to avoid CoreGraphics dependency in data model types.
public struct CodablePoint: Sendable, Codable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
