import CoreImage
import CoreMediaPlus
import Foundation

/// A control point on a color curve.
public struct CurveControlPoint: Sendable, Codable {
    public var x: Double  // input value 0..1
    public var y: Double  // output value 0..1

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A color curve defined by control points with cubic bezier interpolation.
public struct ColorCurve: Sendable {
    public var controlPoints: [CurveControlPoint]

    public init(controlPoints: [CurveControlPoint] = [
        CurveControlPoint(x: 0, y: 0),
        CurveControlPoint(x: 0.25, y: 0.25),
        CurveControlPoint(x: 0.5, y: 0.5),
        CurveControlPoint(x: 0.75, y: 0.75),
        CurveControlPoint(x: 1, y: 1),
    ]) {
        self.controlPoints = controlPoints
    }

    /// Evaluates the curve at a given input using piecewise cubic interpolation.
    public func evaluate(at input: Double) -> Double {
        let clamped = min(max(input, 0), 1)
        let sorted = controlPoints.sorted { $0.x < $1.x }

        guard sorted.count >= 2 else {
            return sorted.first?.y ?? clamped
        }

        // Find the segment
        if clamped <= sorted[0].x { return sorted[0].y }
        if clamped >= sorted[sorted.count - 1].x { return sorted[sorted.count - 1].y }

        var lower = 0
        for i in 0..<sorted.count {
            if sorted[i].x <= clamped {
                lower = i
            } else {
                break
            }
        }
        let upper = min(lower + 1, sorted.count - 1)

        let p0 = sorted[lower]
        let p1 = sorted[upper]
        let range = p1.x - p0.x
        guard range > 0 else { return p0.y }

        let t = (clamped - p0.x) / range

        // Hermite spline interpolation for smooth curves
        let t2 = t * t
        let t3 = t2 * t

        // Calculate tangents from neighboring points
        let m0 = tangent(at: lower, points: sorted)
        let m1 = tangent(at: upper, points: sorted)

        let scaledM0 = m0 * range
        let scaledM1 = m1 * range

        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2

        return h00 * p0.y + h10 * scaledM0 + h01 * p1.y + h11 * scaledM1
    }

    /// Generates a lookup table with the specified number of entries.
    public func generateLUT(size: Int = 256) -> [Double] {
        (0..<size).map { i in
            let x = Double(i) / Double(size - 1)
            return min(max(evaluate(at: x), 0), 1)
        }
    }

    // MARK: - Private

    private func tangent(at index: Int, points: [CurveControlPoint]) -> Double {
        if index == 0 && points.count > 1 {
            return (points[1].y - points[0].y) / max(points[1].x - points[0].x, 0.001)
        } else if index == points.count - 1 && points.count > 1 {
            let last = points.count - 1
            return (points[last].y - points[last - 1].y) / max(points[last].x - points[last - 1].x, 0.001)
        } else if index > 0 && index < points.count - 1 {
            return (points[index + 1].y - points[index - 1].y) / max(points[index + 1].x - points[index - 1].x, 0.001)
        }
        return 0
    }
}

/// Applies color curves per channel using CIToneCurve.
///
/// Supports independent curves for Red, Green, Blue, and a Master (luminance) curve.
/// The master curve is applied first, then per-channel curves.
public final class CurvesEffect: Sendable {
    public init() {}

    /// Applies curves to the input image based on parameter values.
    ///
    /// Parameters are expected in the form:
    ///   - masterP0..masterP4: master curve control points as (x,y) pairs
    ///   - redP0..redP4, greenP0..greenP4, blueP0..blueP4: per-channel points
    ///
    /// CIToneCurve requires exactly 5 control points.
    public func apply(to image: CIImage, parameters: ParameterValues) -> CIImage {
        var result = image

        // Apply master curve
        let masterPoints = extractPoints(prefix: "master", from: parameters)
        result = applyToneCurve(to: result, points: masterPoints)

        // Apply per-channel curves using a color cube lookup
        let redCurve = ColorCurve(controlPoints: extractCurvePoints(prefix: "red", from: parameters))
        let greenCurve = ColorCurve(controlPoints: extractCurvePoints(prefix: "green", from: parameters))
        let blueCurve = ColorCurve(controlPoints: extractCurvePoints(prefix: "blue", from: parameters))

        if !isIdentity(redCurve) || !isIdentity(greenCurve) || !isIdentity(blueCurve) {
            result = applyPerChannelCurves(to: result, red: redCurve, green: greenCurve, blue: blueCurve)
        }

        return result
    }

    // MARK: - Private

    private func applyToneCurve(to image: CIImage, points: [CIVector]) -> CIImage {
        guard points.count == 5 else { return image }

        // Check if all points are identity
        let isIdentityCurve = points.enumerated().allSatisfy { i, v in
            let expected = Double(i) / 4.0
            return abs(v.x - expected) < 0.001 && abs(v.y - expected) < 0.001
        }
        guard !isIdentityCurve else { return image }

        guard let filter = CIFilter(name: "CIToneCurve") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(points[0], forKey: "inputPoint0")
        filter.setValue(points[1], forKey: "inputPoint1")
        filter.setValue(points[2], forKey: "inputPoint2")
        filter.setValue(points[3], forKey: "inputPoint3")
        filter.setValue(points[4], forKey: "inputPoint4")
        return filter.outputImage ?? image
    }

    private func applyPerChannelCurves(
        to image: CIImage,
        red: ColorCurve, green: ColorCurve, blue: ColorCurve
    ) -> CIImage {
        let size = 64
        let count = size * size * size
        var cubeData = [Float](repeating: 0, count: count * 4)

        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let index = (b * size * size + g * size + r) * 4
                    let rNorm = Double(r) / Double(size - 1)
                    let gNorm = Double(g) / Double(size - 1)
                    let bNorm = Double(b) / Double(size - 1)

                    cubeData[index + 0] = Float(red.evaluate(at: rNorm))
                    cubeData[index + 1] = Float(green.evaluate(at: gNorm))
                    cubeData[index + 2] = Float(blue.evaluate(at: bNorm))
                    cubeData[index + 3] = 1.0
                }
            }
        }

        let data = cubeData.withUnsafeBufferPointer { Data(buffer: $0) }

        guard let filter = CIFilter(name: "CIColorCube") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(size, forKey: "inputCubeDimension")
        filter.setValue(data, forKey: "inputCubeData")
        return filter.outputImage ?? image
    }

    private func extractPoints(prefix: String, from parameters: ParameterValues) -> [CIVector] {
        (0..<5).map { i in
            let key = "\(prefix)P\(i)"
            if case .point(let x, let y) = parameters[key] {
                return CIVector(x: x, y: y)
            }
            let defaultVal = Double(i) / 4.0
            return CIVector(x: defaultVal, y: defaultVal)
        }
    }

    private func extractCurvePoints(prefix: String, from parameters: ParameterValues) -> [CurveControlPoint] {
        (0..<5).map { i in
            let key = "\(prefix)P\(i)"
            if case .point(let x, let y) = parameters[key] {
                return CurveControlPoint(x: x, y: y)
            }
            let defaultVal = Double(i) / 4.0
            return CurveControlPoint(x: defaultVal, y: defaultVal)
        }
    }

    private func isIdentity(_ curve: ColorCurve) -> Bool {
        curve.controlPoints.allSatisfy { abs($0.x - $0.y) < 0.001 }
    }
}
