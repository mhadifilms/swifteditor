import CoreImage
import CoreMediaPlus
import Foundation

/// A CIFilter wrapper that maps ParameterValues to CIFilter input keys and applies the filter.
public final class CIFilterEffect: Sendable {
    public let filterName: String
    public let parameterMapping: [String: String] // effect param name -> CIFilter input key

    public init(filterName: String, parameterMapping: [String: String] = [:]) {
        self.filterName = filterName
        self.parameterMapping = parameterMapping
    }

    /// Applies the filter to an input image with the given parameter values.
    /// Returns the filtered image, or the original if the filter cannot be created.
    public func apply(to image: CIImage, parameters: ParameterValues) -> CIImage {
        guard let filter = CIFilter(name: filterName) else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)

        for (paramName, ciKey) in parameterMapping {
            guard let value = parameters[paramName] else { continue }
            switch value {
            case .float(let v):
                filter.setValue(NSNumber(value: v), forKey: ciKey)
            case .int(let v):
                filter.setValue(NSNumber(value: v), forKey: ciKey)
            case .bool(let v):
                filter.setValue(NSNumber(value: v), forKey: ciKey)
            case .string(let v):
                filter.setValue(v, forKey: ciKey)
            case .color(let r, let g, let b, let a):
                filter.setValue(CIColor(red: r, green: g, blue: b, alpha: a), forKey: ciKey)
            case .point(let x, let y):
                filter.setValue(CIVector(x: x, y: y), forKey: ciKey)
            case .size(let w, let h):
                filter.setValue(CIVector(x: w, y: h), forKey: ciKey)
            }
        }

        return filter.outputImage ?? image
    }
}

// MARK: - Factory Methods

extension CIFilterEffect {
    /// Brightness adjustment via CIColorControls (inputBrightness).
    public static func brightness() -> CIFilterEffect {
        CIFilterEffect(
            filterName: "CIColorControls",
            parameterMapping: ["brightness": kCIInputBrightnessKey]
        )
    }

    /// Contrast adjustment via CIColorControls (inputContrast).
    public static func contrast() -> CIFilterEffect {
        CIFilterEffect(
            filterName: "CIColorControls",
            parameterMapping: ["contrast": kCIInputContrastKey]
        )
    }

    /// Saturation adjustment via CIColorControls (inputSaturation).
    public static func saturation() -> CIFilterEffect {
        CIFilterEffect(
            filterName: "CIColorControls",
            parameterMapping: ["saturation": kCIInputSaturationKey]
        )
    }

    /// Full color controls: brightness, contrast, saturation.
    public static func colorControls() -> CIFilterEffect {
        CIFilterEffect(
            filterName: "CIColorControls",
            parameterMapping: [
                "brightness": kCIInputBrightnessKey,
                "contrast": kCIInputContrastKey,
                "saturation": kCIInputSaturationKey,
            ]
        )
    }

    /// Gamma adjustment via CIGammaAdjust.
    public static func gamma() -> CIFilterEffect {
        CIFilterEffect(
            filterName: "CIGammaAdjust",
            parameterMapping: ["gamma": "inputPower"]
        )
    }

    /// Gaussian blur.
    public static func gaussianBlur() -> CIFilterEffect {
        CIFilterEffect(
            filterName: "CIGaussianBlur",
            parameterMapping: ["radius": kCIInputRadiusKey]
        )
    }

    /// Luminance sharpening.
    public static func sharpen() -> CIFilterEffect {
        CIFilterEffect(
            filterName: "CISharpenLuminance",
            parameterMapping: [
                "sharpness": kCIInputSharpnessKey,
                "radius": kCIInputRadiusKey,
            ]
        )
    }

    /// Exposure adjustment via CIExposureAdjust.
    public static func exposure() -> CIFilterEffect {
        CIFilterEffect(
            filterName: "CIExposureAdjust",
            parameterMapping: ["ev": kCIInputEVKey]
        )
    }

    /// Hue rotation via CIHueAdjust.
    public static func hueAdjust() -> CIFilterEffect {
        CIFilterEffect(
            filterName: "CIHueAdjust",
            parameterMapping: ["angle": kCIInputAngleKey]
        )
    }

    /// Temperature and tint via CITemperatureAndTint.
    public static func temperatureAndTint() -> CIFilterEffect {
        CIFilterEffect(
            filterName: "CITemperatureAndTint",
            parameterMapping: [
                "neutral": "inputNeutral",
                "targetNeutral": "inputTargetNeutral",
            ]
        )
    }

    /// Vibrance adjustment via CIVibrance.
    public static func vibrance() -> CIFilterEffect {
        CIFilterEffect(
            filterName: "CIVibrance",
            parameterMapping: ["amount": "inputAmount"]
        )
    }
}
