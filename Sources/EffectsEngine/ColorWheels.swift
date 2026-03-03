import CoreImage
import CoreMediaPlus
import Foundation

/// RGB+master offset for a single color wheel (lift, gamma, or gain).
public struct ColorWheelOffset: Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var master: Double

    public init(red: Double = 0, green: Double = 0, blue: Double = 0, master: Double = 0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.master = master
    }

    /// Returns the effective per-channel values (channel offset + master).
    public var effectiveRed: Double { red + master }
    public var effectiveGreen: Double { green + master }
    public var effectiveBlue: Double { blue + master }
}

/// Three-wheel color grading with lift (shadows), gamma (midtones), and gain (highlights).
public struct ColorWheel: Sendable {
    public var lift: ColorWheelOffset
    public var gamma: ColorWheelOffset
    public var gain: ColorWheelOffset

    public init(
        lift: ColorWheelOffset = ColorWheelOffset(),
        gamma: ColorWheelOffset = ColorWheelOffset(),
        gain: ColorWheelOffset = ColorWheelOffset()
    ) {
        self.lift = lift
        self.gamma = gamma
        self.gain = gain
    }
}

/// Applies lift/gamma/gain color wheel grading using CIColorMatrix filters.
///
/// The color math follows the standard lift/gamma/gain formula:
///   output = pow(gain * (input + lift * (1 - input)), 1/gamma)
///
/// This is approximated using three CIColorMatrix passes:
///   1. Lift: adds an offset to the shadows (bias per channel).
///   2. Gain: scales each channel.
///   3. Gamma: applied via CIGammaAdjust per-channel approximation using CIColorMatrix power curve.
public final class ColorWheelEffect: Sendable {
    public init() {}

    /// Applies the color wheel grading to the input image.
    public func apply(to image: CIImage, parameters: ParameterValues) -> CIImage {
        let wheel = extractWheel(from: parameters)
        var result = image

        // Pass 1: Gain — scale each channel
        result = applyGain(to: result, gain: wheel.gain)

        // Pass 2: Lift — add offset to shadows via bias vector
        result = applyLift(to: result, lift: wheel.lift)

        // Pass 3: Gamma — power curve approximation
        result = applyGamma(to: result, gamma: wheel.gamma)

        return result
    }

    /// Creates a CIFilterEffect-compatible wrapper for use in EffectChain.
    public static func asFilterEffect() -> CIFilterEffect {
        CIFilterEffect(
            filterName: "CIColorMatrix",
            parameterMapping: [
                "liftR": "inputRVector",
                "liftG": "inputGVector",
                "liftB": "inputBVector",
            ]
        )
    }

    // MARK: - Private

    private func extractWheel(from parameters: ParameterValues) -> ColorWheel {
        ColorWheel(
            lift: ColorWheelOffset(
                red: parameters.floatValue("liftR"),
                green: parameters.floatValue("liftG"),
                blue: parameters.floatValue("liftB"),
                master: parameters.floatValue("liftMaster")
            ),
            gamma: ColorWheelOffset(
                red: parameters.floatValue("gammaR", default: 1.0),
                green: parameters.floatValue("gammaG", default: 1.0),
                blue: parameters.floatValue("gammaB", default: 1.0),
                master: parameters.floatValue("gammaMaster")
            ),
            gain: ColorWheelOffset(
                red: parameters.floatValue("gainR", default: 1.0),
                green: parameters.floatValue("gainG", default: 1.0),
                blue: parameters.floatValue("gainB", default: 1.0),
                master: parameters.floatValue("gainMaster")
            )
        )
    }

    private func applyGain(to image: CIImage, gain: ColorWheelOffset) -> CIImage {
        guard let filter = CIFilter(name: "CIColorMatrix") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: gain.effectiveRed, y: 0, z: 0, w: 0), forKey: "inputRVector")
        filter.setValue(CIVector(x: 0, y: gain.effectiveGreen, z: 0, w: 0), forKey: "inputGVector")
        filter.setValue(CIVector(x: 0, y: 0, z: gain.effectiveBlue, w: 0), forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
        return filter.outputImage ?? image
    }

    private func applyLift(to image: CIImage, lift: ColorWheelOffset) -> CIImage {
        guard let filter = CIFilter(name: "CIColorMatrix") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        filter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        filter.setValue(
            CIVector(x: lift.effectiveRed, y: lift.effectiveGreen, z: lift.effectiveBlue, w: 0),
            forKey: "inputBiasVector"
        )
        return filter.outputImage ?? image
    }

    private func applyGamma(to image: CIImage, gamma: ColorWheelOffset) -> CIImage {
        // CIGammaAdjust only has a single power value, so we approximate per-channel gamma
        // by using CIColorPolynomial which allows per-channel curve control.
        guard let filter = CIFilter(name: "CIColorPolynomial") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)

        // CIColorPolynomial uses coefficients: output = c0 + c1*input + c2*input^2 + c3*input^3
        // To approximate gamma, we use a simple power curve expansion.
        // For gamma near 1.0, a linear approximation suffices for real-time preview.
        let rGamma = gamma.effectiveRed
        let gGamma = gamma.effectiveGreen
        let bGamma = gamma.effectiveBlue

        // Polynomial coefficients approximating pow(x, 1/gamma) around gamma=1:
        // Using Taylor expansion: x^(1/g) ≈ x + (1/g - 1)*x*(1-x) for g near 1
        // Simplified: c0=0, c1 = 2/g - 1, c2 = 2 - 2/g, c3 = 0
        func coefficients(for g: Double) -> CIVector {
            let invG = 1.0 / max(g, 0.01)
            let c1 = 2.0 * invG - 1.0
            let c2 = 2.0 - 2.0 * invG
            return CIVector(x: 0, y: c1, z: c2, w: 0)
        }

        filter.setValue(coefficients(for: rGamma), forKey: "inputRedCoefficients")
        filter.setValue(coefficients(for: gGamma), forKey: "inputGreenCoefficients")
        filter.setValue(coefficients(for: bGamma), forKey: "inputBlueCoefficients")
        filter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputAlphaCoefficients")

        return filter.outputImage ?? image
    }
}
