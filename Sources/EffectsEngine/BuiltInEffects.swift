import CoreMediaPlus
import Foundation

/// Categories for built-in effects.
public enum BuiltInEffectCategory: String, Sendable, Codable, CaseIterable {
    case colorCorrection
    case blur
    case sharpen
    case stylize
    case distortion
}

/// Describes a built-in effect that can be instantiated as a CIFilterEffect.
public struct BuiltInEffectDescriptor: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let category: BuiltInEffectCategory
    public let parameterDescriptors: [ParameterDescriptor]

    /// Factory closure that creates the corresponding CIFilterEffect.
    public let makeEffect: @Sendable () -> CIFilterEffect

    public init(
        id: String,
        name: String,
        category: BuiltInEffectCategory,
        parameterDescriptors: [ParameterDescriptor],
        makeEffect: @escaping @Sendable () -> CIFilterEffect
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.parameterDescriptors = parameterDescriptors
        self.makeEffect = makeEffect
    }
}

// MARK: - Registry

/// Static registry of all built-in effects.
public enum BuiltInEffects {
    public static let all: [BuiltInEffectDescriptor] = [
        // Color Correction
        BuiltInEffectDescriptor(
            id: "builtin.brightness",
            name: "Brightness",
            category: .colorCorrection,
            parameterDescriptors: [
                .float(name: "brightness", displayName: "Brightness",
                       defaultValue: 0.0, min: -1.0, max: 1.0),
            ],
            makeEffect: { .brightness() }
        ),
        BuiltInEffectDescriptor(
            id: "builtin.contrast",
            name: "Contrast",
            category: .colorCorrection,
            parameterDescriptors: [
                .float(name: "contrast", displayName: "Contrast",
                       defaultValue: 1.0, min: 0.0, max: 4.0),
            ],
            makeEffect: { .contrast() }
        ),
        BuiltInEffectDescriptor(
            id: "builtin.saturation",
            name: "Saturation",
            category: .colorCorrection,
            parameterDescriptors: [
                .float(name: "saturation", displayName: "Saturation",
                       defaultValue: 1.0, min: 0.0, max: 3.0),
            ],
            makeEffect: { .saturation() }
        ),
        BuiltInEffectDescriptor(
            id: "builtin.colorControls",
            name: "Color Controls",
            category: .colorCorrection,
            parameterDescriptors: [
                .float(name: "brightness", displayName: "Brightness",
                       defaultValue: 0.0, min: -1.0, max: 1.0),
                .float(name: "contrast", displayName: "Contrast",
                       defaultValue: 1.0, min: 0.0, max: 4.0),
                .float(name: "saturation", displayName: "Saturation",
                       defaultValue: 1.0, min: 0.0, max: 3.0),
            ],
            makeEffect: { .colorControls() }
        ),
        BuiltInEffectDescriptor(
            id: "builtin.exposure",
            name: "Exposure",
            category: .colorCorrection,
            parameterDescriptors: [
                .float(name: "ev", displayName: "EV",
                       defaultValue: 0.0, min: -10.0, max: 10.0),
            ],
            makeEffect: { .exposure() }
        ),
        BuiltInEffectDescriptor(
            id: "builtin.gamma",
            name: "Gamma",
            category: .colorCorrection,
            parameterDescriptors: [
                .float(name: "gamma", displayName: "Gamma",
                       defaultValue: 1.0, min: 0.25, max: 4.0),
            ],
            makeEffect: { .gamma() }
        ),
        BuiltInEffectDescriptor(
            id: "builtin.hueAdjust",
            name: "Hue Adjust",
            category: .colorCorrection,
            parameterDescriptors: [
                .float(name: "angle", displayName: "Angle (radians)",
                       defaultValue: 0.0, min: -.pi, max: .pi),
            ],
            makeEffect: { .hueAdjust() }
        ),
        BuiltInEffectDescriptor(
            id: "builtin.temperatureAndTint",
            name: "Temperature & Tint",
            category: .colorCorrection,
            parameterDescriptors: [
                .point(name: "neutral", displayName: "Neutral",
                       defaultX: 6500, defaultY: 0),
                .point(name: "targetNeutral", displayName: "Target Neutral",
                       defaultX: 6500, defaultY: 0),
            ],
            makeEffect: { .temperatureAndTint() }
        ),
        BuiltInEffectDescriptor(
            id: "builtin.vibrance",
            name: "Vibrance",
            category: .colorCorrection,
            parameterDescriptors: [
                .float(name: "amount", displayName: "Amount",
                       defaultValue: 0.0, min: -1.0, max: 1.0),
            ],
            makeEffect: { .vibrance() }
        ),

        // Blur
        BuiltInEffectDescriptor(
            id: "builtin.gaussianBlur",
            name: "Gaussian Blur",
            category: .blur,
            parameterDescriptors: [
                .float(name: "radius", displayName: "Radius",
                       defaultValue: 10.0, min: 0.0, max: 100.0),
            ],
            makeEffect: { .gaussianBlur() }
        ),

        // Sharpen
        BuiltInEffectDescriptor(
            id: "builtin.sharpen",
            name: "Sharpen",
            category: .sharpen,
            parameterDescriptors: [
                .float(name: "sharpness", displayName: "Sharpness",
                       defaultValue: 0.4, min: 0.0, max: 2.0),
                .float(name: "radius", displayName: "Radius",
                       defaultValue: 1.69, min: 0.0, max: 20.0),
            ],
            makeEffect: { .sharpen() }
        ),
    ]

    /// Looks up a built-in effect descriptor by its ID.
    public static func descriptor(for id: String) -> BuiltInEffectDescriptor? {
        all.first { $0.id == id }
    }

    /// Returns all descriptors in a given category.
    public static func descriptors(in category: BuiltInEffectCategory) -> [BuiltInEffectDescriptor] {
        all.filter { $0.category == category }
    }

    /// Creates a CIFilterEffect from a descriptor ID.
    public static func createEffect(for id: String) -> CIFilterEffect? {
        descriptor(for: id)?.makeEffect()
    }
}
