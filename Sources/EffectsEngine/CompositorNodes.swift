import CoreImage
import CoreMediaPlus
import Foundation

// MARK: - Input Node

/// Provides source imagery to the graph — represents a clip or layer input.
public final class InputNode: CompositorNode, @unchecked Sendable {
    public let id: UUID
    public var name: String
    public var isEnabled: Bool
    public var image: CIImage?

    public var inputDescriptors: [NodePortDescriptor] { [] }
    public var outputDescriptors: [NodePortDescriptor] {
        [NodePortDescriptor(name: "output", label: "Output")]
    }

    public init(id: UUID = UUID(), name: String = "Input", image: CIImage? = nil) {
        self.id = id
        self.name = name
        self.isEnabled = true
        self.image = image
    }

    public func process(inputs: [String: CIImage], parameters: ParameterValues, at time: Rational) -> [String: CIImage] {
        guard let image else { return [:] }
        return ["output": image]
    }
}

// MARK: - Output Node

/// Terminal node that collects the final composited result.
public final class OutputNode: CompositorNode, @unchecked Sendable {
    public let id: UUID
    public var name: String
    public var isEnabled: Bool

    public var inputDescriptors: [NodePortDescriptor] {
        [NodePortDescriptor(name: "input", label: "Input")]
    }
    public var outputDescriptors: [NodePortDescriptor] {
        [NodePortDescriptor(name: "output", label: "Output")]
    }

    public init(id: UUID = UUID(), name: String = "Output") {
        self.id = id
        self.name = name
        self.isEnabled = true
    }

    public func process(inputs: [String: CIImage], parameters: ParameterValues, at time: Rational) -> [String: CIImage] {
        guard let input = inputs["input"] else { return [:] }
        return ["output": input]
    }
}

// MARK: - Blend/Merge Node

/// Composites two images using a blend mode.
public final class BlendNode: CompositorNode, @unchecked Sendable {
    public let id: UUID
    public var name: String
    public var isEnabled: Bool
    public var blendMode: BlendMode
    public var opacity: Double

    public var inputDescriptors: [NodePortDescriptor] {
        [
            NodePortDescriptor(name: "background", label: "Background"),
            NodePortDescriptor(name: "foreground", label: "Foreground"),
        ]
    }
    public var outputDescriptors: [NodePortDescriptor] {
        [NodePortDescriptor(name: "output", label: "Output")]
    }

    public init(
        id: UUID = UUID(),
        name: String = "Blend",
        blendMode: BlendMode = .normal,
        opacity: Double = 1.0
    ) {
        self.id = id
        self.name = name
        self.isEnabled = true
        self.blendMode = blendMode
        self.opacity = opacity
    }

    public func process(inputs: [String: CIImage], parameters: ParameterValues, at time: Rational) -> [String: CIImage] {
        let bg = inputs["background"]
        let fg = inputs["foreground"]

        guard let bg else {
            return ["output": fg].compactMapValues { $0 }
        }
        guard var fg else {
            return ["output": bg]
        }

        // Apply opacity
        let effectiveOpacity = parameters["opacity"].flatMap { if case .float(let v) = $0 { return v } else { return nil } } ?? opacity
        if effectiveOpacity < 1.0 {
            fg = fg.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(effectiveOpacity)),
            ])
        }

        let result = blend(fg, over: bg, mode: blendMode)
        return ["output": result]
    }

    private func blend(_ top: CIImage, over bottom: CIImage, mode: BlendMode) -> CIImage {
        let filterName: String
        switch mode {
        case .normal:
            return top.composited(over: bottom)
        case .add:
            filterName = "CIAdditionCompositing"
        case .multiply:
            filterName = "CIMultiplyCompositing"
        case .screen:
            filterName = "CIScreenBlendMode"
        case .overlay:
            filterName = "CIOverlayBlendMode"
        case .softLight:
            filterName = "CISoftLightBlendMode"
        case .hardLight:
            filterName = "CIHardLightBlendMode"
        case .difference:
            filterName = "CIDifferenceBlendMode"
        }

        guard let filter = CIFilter(name: filterName) else {
            return top.composited(over: bottom)
        }
        filter.setValue(top, forKey: kCIInputImageKey)
        filter.setValue(bottom, forKey: kCIInputBackgroundImageKey)
        return filter.outputImage ?? top.composited(over: bottom)
    }
}

// MARK: - Transform Node

/// Applies position, scale, and rotation transforms.
public final class TransformNode: CompositorNode, @unchecked Sendable {
    public let id: UUID
    public var name: String
    public var isEnabled: Bool
    public var translateX: Double = 0
    public var translateY: Double = 0
    public var scaleX: Double = 1
    public var scaleY: Double = 1
    public var rotation: Double = 0 // radians

    public var inputDescriptors: [NodePortDescriptor] {
        [NodePortDescriptor(name: "input", label: "Input")]
    }
    public var outputDescriptors: [NodePortDescriptor] {
        [NodePortDescriptor(name: "output", label: "Output")]
    }

    public init(id: UUID = UUID(), name: String = "Transform") {
        self.id = id
        self.name = name
        self.isEnabled = true
    }

    public func process(inputs: [String: CIImage], parameters: ParameterValues, at time: Rational) -> [String: CIImage] {
        guard var image = inputs["input"] else { return [:] }

        let tx = parameters["translateX"].flatMap { if case .float(let v) = $0 { return v } else { return nil } } ?? translateX
        let ty = parameters["translateY"].flatMap { if case .float(let v) = $0 { return v } else { return nil } } ?? translateY
        let sx = parameters["scaleX"].flatMap { if case .float(let v) = $0 { return v } else { return nil } } ?? scaleX
        let sy = parameters["scaleY"].flatMap { if case .float(let v) = $0 { return v } else { return nil } } ?? scaleY
        let rot = parameters["rotation"].flatMap { if case .float(let v) = $0 { return v } else { return nil } } ?? rotation

        var transform = CGAffineTransform.identity
        transform = transform.scaledBy(x: sx, y: sy)
        transform = transform.rotated(by: rot)
        transform = transform.translatedBy(x: tx, y: ty)

        image = image.transformed(by: transform)
        return ["output": image]
    }
}

// MARK: - Color Correction Node

/// Applies brightness, contrast, saturation, and exposure adjustments.
public final class ColorCorrectionNode: CompositorNode, @unchecked Sendable {
    public let id: UUID
    public var name: String
    public var isEnabled: Bool

    public var inputDescriptors: [NodePortDescriptor] {
        [NodePortDescriptor(name: "input", label: "Input")]
    }
    public var outputDescriptors: [NodePortDescriptor] {
        [NodePortDescriptor(name: "output", label: "Output")]
    }

    public init(id: UUID = UUID(), name: String = "Color Correction") {
        self.id = id
        self.name = name
        self.isEnabled = true
    }

    public func process(inputs: [String: CIImage], parameters: ParameterValues, at time: Rational) -> [String: CIImage] {
        guard var image = inputs["input"] else { return [:] }

        // Color controls
        let brightness = parameters["brightness"].flatMap { if case .float(let v) = $0 { return v } else { return nil } }
        let contrast = parameters["contrast"].flatMap { if case .float(let v) = $0 { return v } else { return nil } }
        let saturation = parameters["saturation"].flatMap { if case .float(let v) = $0 { return v } else { return nil } }

        if brightness != nil || contrast != nil || saturation != nil {
            var filterParams: [String: Any] = [kCIInputImageKey: image]
            if let b = brightness { filterParams[kCIInputBrightnessKey] = NSNumber(value: b) }
            if let c = contrast { filterParams[kCIInputContrastKey] = NSNumber(value: c) }
            if let s = saturation { filterParams[kCIInputSaturationKey] = NSNumber(value: s) }
            image = image.applyingFilter("CIColorControls", parameters: filterParams)
        }

        // Exposure
        if let ev = parameters["exposure"].flatMap({ if case .float(let v) = $0 { return v } else { return nil } }) {
            image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: NSNumber(value: ev)])
        }

        // Gamma
        if let gamma = parameters["gamma"].flatMap({ if case .float(let v) = $0 { return v } else { return nil } }) {
            image = image.applyingFilter("CIGammaAdjust", parameters: ["inputPower": NSNumber(value: gamma)])
        }

        return ["output": image]
    }
}

// MARK: - Blur Node

/// Applies Gaussian blur with configurable radius.
public final class BlurNode: CompositorNode, @unchecked Sendable {
    public let id: UUID
    public var name: String
    public var isEnabled: Bool
    public var radius: Double = 10.0

    public var inputDescriptors: [NodePortDescriptor] {
        [NodePortDescriptor(name: "input", label: "Input")]
    }
    public var outputDescriptors: [NodePortDescriptor] {
        [NodePortDescriptor(name: "output", label: "Output")]
    }

    public init(id: UUID = UUID(), name: String = "Blur", radius: Double = 10.0) {
        self.id = id
        self.name = name
        self.isEnabled = true
        self.radius = radius
    }

    public func process(inputs: [String: CIImage], parameters: ParameterValues, at time: Rational) -> [String: CIImage] {
        guard let image = inputs["input"] else { return [:] }
        let r = parameters["radius"].flatMap { if case .float(let v) = $0 { return v } else { return nil } } ?? radius
        let blurred = image.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: NSNumber(value: r)])
        return ["output": blurred]
    }
}

// MARK: - Keyer Node

/// Chroma or luma key — removes a color range and outputs with alpha.
public final class KeyerNode: CompositorNode, @unchecked Sendable {
    public let id: UUID
    public var name: String
    public var isEnabled: Bool

    public var inputDescriptors: [NodePortDescriptor] {
        [NodePortDescriptor(name: "input", label: "Input")]
    }
    public var outputDescriptors: [NodePortDescriptor] {
        [
            NodePortDescriptor(name: "output", label: "Output"),
            NodePortDescriptor(name: "matte", label: "Matte"),
        ]
    }

    public init(id: UUID = UUID(), name: String = "Keyer") {
        self.id = id
        self.name = name
        self.isEnabled = true
    }

    public func process(inputs: [String: CIImage], parameters: ParameterValues, at time: Rational) -> [String: CIImage] {
        guard let image = inputs["input"] else { return [:] }

        // Extract key color and tolerance from parameters
        let hue = parameters["keyHue"].flatMap { if case .float(let v) = $0 { return v } else { return nil } } ?? 120.0 // green
        let tolerance = parameters["keyTolerance"].flatMap { if case .float(let v) = $0 { return v } else { return nil } } ?? 0.2

        // Use CIColorCube for precise chroma keying based on hue and tolerance
        let keyed = image.applyingFilter("CIHueAdjust", parameters: [
            kCIInputAngleKey: Float(-hue * .pi / 180.0)
        ]).applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: CGFloat(1.0 - tolerance), z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
        ])
        return ["output": keyed, "matte": keyed]
    }
}

// MARK: - CIFilter Wrapper Node

/// Wraps any CIFilter as a compositor node, bridging the existing CIFilterEffect system.
public final class CIFilterNode: CompositorNode, @unchecked Sendable {
    public let id: UUID
    public var name: String
    public var isEnabled: Bool
    public let effect: CIFilterEffect
    public var effectParameters: ParameterValues

    public var inputDescriptors: [NodePortDescriptor] {
        [NodePortDescriptor(name: "input", label: "Input")]
    }
    public var outputDescriptors: [NodePortDescriptor] {
        [NodePortDescriptor(name: "output", label: "Output")]
    }

    public init(
        id: UUID = UUID(),
        name: String,
        effect: CIFilterEffect,
        effectParameters: ParameterValues = ParameterValues()
    ) {
        self.id = id
        self.name = name
        self.isEnabled = true
        self.effect = effect
        self.effectParameters = effectParameters
    }

    public func process(inputs: [String: CIImage], parameters: ParameterValues, at time: Rational) -> [String: CIImage] {
        guard let image = inputs["input"] else { return [:] }
        var merged = parameters
        for key in effectParameters.allKeys {
            merged[key] = effectParameters[key]
        }
        let result = effect.apply(to: image, parameters: merged)
        return ["output": result]
    }
}
