import CoreMediaPlus
import Foundation

/// Keyframe sequence with interpolation for animating effect parameters over time.
public struct KeyframeTrack: Sendable {
    public var keyframes: [Keyframe] = []

    public init() {}

    public struct Keyframe: Sendable {
        public var time: Rational
        public var value: ParameterValue
        public var interpolation: InterpolationType

        public init(time: Rational, value: ParameterValue, interpolation: InterpolationType = .linear) {
            self.time = time
            self.value = value
            self.interpolation = interpolation
        }

        public enum InterpolationType: Sendable {
            case linear
            case hold
            case bezier(inTangent: CGPoint, outTangent: CGPoint)
        }
    }

    /// Adds a keyframe, maintaining sorted order by time.
    /// If a keyframe already exists at the same time, it is replaced.
    public mutating func addKeyframe(_ keyframe: Keyframe) {
        if let existingIndex = keyframes.firstIndex(where: { $0.time == keyframe.time }) {
            keyframes[existingIndex] = keyframe
            return
        }
        let insertionIndex = keyframes.firstIndex(where: { $0.time > keyframe.time }) ?? keyframes.endIndex
        keyframes.insert(keyframe, at: insertionIndex)
    }

    /// Removes the keyframe at the given time, if one exists.
    public mutating func removeKeyframe(at time: Rational) {
        keyframes.removeAll { $0.time == time }
    }

    /// Returns the interpolated parameter value at the given time.
    ///
    /// - Before first keyframe: returns first keyframe's value.
    /// - After last keyframe: returns last keyframe's value.
    /// - Hold interpolation: returns previous keyframe's value.
    /// - Linear interpolation: lerps for float values, snaps at midpoint for others.
    /// - Bezier interpolation: currently treated as linear (placeholder).
    public func value(at time: Rational) -> ParameterValue? {
        guard !keyframes.isEmpty else { return nil }

        // Before or at first keyframe
        guard let first = keyframes.first else { return nil }
        if time <= first.time { return first.value }

        // After or at last keyframe
        guard let last = keyframes.last else { return nil }
        if time >= last.time { return last.value }

        // Find the surrounding keyframes
        var lowerIndex = 0
        for i in 0..<keyframes.count {
            if keyframes[i].time <= time {
                lowerIndex = i
            } else {
                break
            }
        }
        let upperIndex = lowerIndex + 1
        guard upperIndex < keyframes.count else { return keyframes[lowerIndex].value }

        let lower = keyframes[lowerIndex]
        let upper = keyframes[upperIndex]

        switch lower.interpolation {
        case .hold:
            return lower.value
        case .linear, .bezier:
            // Bezier treated as linear for now
            return interpolateLinear(from: lower.value, to: upper.value,
                                     time: time, startTime: lower.time, endTime: upper.time)
        }
    }

    // MARK: - Private

    private func interpolateLinear(
        from: ParameterValue, to: ParameterValue,
        time: Rational, startTime: Rational, endTime: Rational
    ) -> ParameterValue {
        let duration = endTime - startTime
        guard duration.numerator != 0 else { return from }

        let elapsed = time - startTime
        let t = elapsed.seconds / duration.seconds

        switch (from, to) {
        case (.float(let a), .float(let b)):
            return .float(a + (b - a) * t)

        case (.int(let a), .int(let b)):
            return .int(a + Int(Double(b - a) * t))

        case (.color(let r1, let g1, let b1, let a1), .color(let r2, let g2, let b2, let a2)):
            return .color(
                r: r1 + (r2 - r1) * t,
                g: g1 + (g2 - g1) * t,
                b: b1 + (b2 - b1) * t,
                a: a1 + (a2 - a1) * t
            )

        case (.point(let x1, let y1), .point(let x2, let y2)):
            return .point(
                x: x1 + (x2 - x1) * t,
                y: y1 + (y2 - y1) * t
            )

        case (.size(let w1, let h1), .size(let w2, let h2)):
            return .size(
                width: w1 + (w2 - w1) * t,
                height: h1 + (h2 - h1) * t
            )

        default:
            // For non-interpolatable types (bool, string, mismatched), snap at midpoint
            return t < 0.5 ? from : to
        }
    }
}
