import CoreImage
import CoreMediaPlus
import Foundation

/// Chroma key (green/blue screen) effect using a CIFilter pipeline.
///
/// The effect converts to HSV color space to isolate a target hue range,
/// then creates a matte based on hue proximity with configurable tolerance and edge softness.
public final class ChromaKeyEffect: Sendable {
    public init() {}

    /// Applies chroma keying to the input image.
    ///
    /// Parameters:
    ///   - keyColor: The target key color as (r, g, b, a) via ParameterValue.color
    ///   - tolerance: How wide the hue range is (0..1, default 0.1)
    ///   - softness: Edge softness for the matte (0..1, default 0.1)
    ///   - spillSuppression: Amount of spill color removal (0..1, default 0.5)
    public func apply(to image: CIImage, parameters: ParameterValues) -> CIImage {
        let tolerance = parameters.floatValue("tolerance", default: 0.1)
        let softness = parameters.floatValue("softness", default: 0.1)

        // Extract key color components, default to green
        let keyR: Double
        let keyG: Double
        let keyB: Double
        if case .color(let r, let g, let b, _) = parameters["keyColor"] {
            keyR = r
            keyG = g
            keyB = b
        } else {
            keyR = 0; keyG = 1; keyB = 0  // default green
        }

        let targetHue = rgbToHue(r: keyR, g: keyG, b: keyB)

        // Build a color cube that maps the key color range to transparent
        let size = 64
        let count = size * size * size
        var cubeData = [Float](repeating: 0, count: count * 4)

        for bIdx in 0..<size {
            for gIdx in 0..<size {
                for rIdx in 0..<size {
                    let index = (bIdx * size * size + gIdx * size + rIdx) * 4
                    let rNorm = Float(rIdx) / Float(size - 1)
                    let gNorm = Float(gIdx) / Float(size - 1)
                    let bNorm = Float(bIdx) / Float(size - 1)

                    let hue = rgbToHue(r: Double(rNorm), g: Double(gNorm), b: Double(bNorm))

                    // Calculate hue distance (wrapping around 0/1 boundary)
                    var hueDist = abs(hue - targetHue)
                    if hueDist > 0.5 { hueDist = 1.0 - hueDist }

                    // Calculate alpha based on hue distance, tolerance, and softness
                    let alpha: Float
                    let innerEdge = Float(tolerance)
                    let outerEdge = Float(tolerance + softness)

                    if Float(hueDist) < innerEdge {
                        alpha = 0.0  // fully transparent (keyed out)
                    } else if Float(hueDist) < outerEdge {
                        // Smooth transition
                        alpha = (Float(hueDist) - innerEdge) / max(outerEdge - innerEdge, 0.001)
                    } else {
                        alpha = 1.0  // fully opaque (keep)
                    }

                    // Also factor in saturation — low saturation pixels should not be keyed
                    let maxC = max(rNorm, gNorm, bNorm)
                    let minC = min(rNorm, gNorm, bNorm)
                    let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
                    let satFactor = min(saturation / 0.2, 1.0)  // ramp: low sat = keep
                    let finalAlpha = 1.0 - (1.0 - alpha) * satFactor

                    // Premultiplied alpha
                    cubeData[index + 0] = rNorm * finalAlpha
                    cubeData[index + 1] = gNorm * finalAlpha
                    cubeData[index + 2] = bNorm * finalAlpha
                    cubeData[index + 3] = finalAlpha
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

    // MARK: - Private

    private func rgbToHue(r: Double, g: Double, b: Double) -> Double {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        guard delta > 0.001 else { return 0 }

        var hue: Double
        if maxC == r {
            hue = (g - b) / delta
            if hue < 0 { hue += 6 }
        } else if maxC == g {
            hue = 2 + (b - r) / delta
        } else {
            hue = 4 + (r - g) / delta
        }

        return hue / 6.0  // normalize to 0..1
    }
}
