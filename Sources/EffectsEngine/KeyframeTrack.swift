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
            /// Cubic bezier with control points in normalized (0...1) space.
            /// outTangent belongs to the left keyframe, inTangent belongs to the right keyframe.
            /// The x-axis represents time fraction and the y-axis represents value fraction.
            case bezier(inTangent: CGPoint, outTangent: CGPoint)
        }
    }

    // MARK: - Preset Bezier Curves

    /// Ease-in: slow start, fast end.
    public static let easeIn = (
        outTangent: CGPoint(x: 0.42, y: 0.0),
        inTangent: CGPoint(x: 1.0, y: 1.0)
    )

    /// Ease-out: fast start, slow end.
    public static let easeOut = (
        outTangent: CGPoint(x: 0.0, y: 0.0),
        inTangent: CGPoint(x: 0.58, y: 1.0)
    )

    /// Ease-in-out: slow start and end.
    public static let easeInOut = (
        outTangent: CGPoint(x: 0.42, y: 0.0),
        inTangent: CGPoint(x: 0.58, y: 1.0)
    )

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
    /// - Bezier interpolation: cubic bezier curve evaluated in the time domain.
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
        case .linear:
            return interpolateLinear(from: lower.value, to: upper.value,
                                     time: time, startTime: lower.time, endTime: upper.time)
        case .bezier(let inTangent, let outTangent):
            return interpolateBezier(from: lower.value, to: upper.value,
                                     time: time, startTime: lower.time, endTime: upper.time,
                                     outTangent: outTangent, inTangent: inTangent)
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

        return lerpValues(from: from, to: to, t: t)
    }

    /// Evaluates the cubic bezier curve to find the value-domain interpolation factor
    /// for a given time, then applies that factor to interpolate between values.
    private func interpolateBezier(
        from: ParameterValue, to: ParameterValue,
        time: Rational, startTime: Rational, endTime: Rational,
        outTangent: CGPoint, inTangent: CGPoint
    ) -> ParameterValue {
        let duration = endTime - startTime
        guard duration.numerator != 0 else { return from }

        let elapsed = time - startTime
        let timeFraction = elapsed.seconds / duration.seconds

        // The bezier curve has 4 control points in normalized space:
        // P0 = (0, 0), P1 = outTangent, P2 = inTangent, P3 = (1, 1)
        // We need to find the curve parameter 'u' such that bezierX(u) = timeFraction,
        // then evaluate bezierY(u) as the value interpolation factor.
        let u = solveCubicBezierX(timeFraction: timeFraction,
                                   p1x: outTangent.x, p2x: inTangent.x)
        let valueFraction = cubicBezierY(u: u, p1y: outTangent.y, p2y: inTangent.y)

        return lerpValues(from: from, to: to, t: valueFraction)
    }

    /// Solves for the curve parameter u where the x-component of the cubic bezier
    /// equals the given time fraction. Uses Newton-Raphson with bisection fallback.
    ///
    /// The cubic bezier x-component: B_x(u) = 3(1-u)^2 * u * p1x + 3(1-u) * u^2 * p2x + u^3
    private func solveCubicBezierX(timeFraction: Double, p1x: Double, p2x: Double) -> Double {
        // Clamp to valid range
        let t = min(max(timeFraction, 0.0), 1.0)

        // Coefficients of the cubic polynomial: ax*u^3 + bx*u^2 + cx*u = t
        let cx = 3.0 * p1x
        let bx = 3.0 * (p2x - p1x) - cx
        let ax = 1.0 - cx - bx

        // Newton-Raphson iteration
        var u = t  // Initial guess
        for _ in 0..<8 {
            let xValue = ((ax * u + bx) * u + cx) * u - t
            if Swift.abs(xValue) < 1e-7 { return u }
            let derivative = (3.0 * ax * u + 2.0 * bx) * u + cx
            if Swift.abs(derivative) < 1e-7 { break }
            u -= xValue / derivative
        }

        // If Newton-Raphson didn't converge, fall back to bisection
        var lo = 0.0
        var hi = 1.0
        u = t
        for _ in 0..<20 {
            let xValue = ((ax * u + bx) * u + cx) * u
            if Swift.abs(xValue - t) < 1e-7 { return u }
            if t > xValue {
                lo = u
            } else {
                hi = u
            }
            u = (lo + hi) * 0.5
        }

        return u
    }

    /// Evaluates the y-component of the cubic bezier at parameter u.
    /// B_y(u) = 3(1-u)^2 * u * p1y + 3(1-u) * u^2 * p2y + u^3
    private func cubicBezierY(u: Double, p1y: Double, p2y: Double) -> Double {
        let cy = 3.0 * p1y
        let by = 3.0 * (p2y - p1y) - cy
        let ay = 1.0 - cy - by
        return ((ay * u + by) * u + cy) * u
    }

    /// Linear interpolation between two parameter values at factor t.
    private func lerpValues(from: ParameterValue, to: ParameterValue, t: Double) -> ParameterValue {
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

