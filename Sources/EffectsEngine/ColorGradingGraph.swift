import CoreImage
import CoreMediaPlus
import Foundation

/// Protocol for a node in the color grading graph.
/// Each node processes a CIImage and returns a transformed CIImage.
public protocol ColorNode: Sendable {
    var id: UUID { get }
    var name: String { get }
    var isEnabled: Bool { get }
    func process(_ image: CIImage, parameters: ParameterValues) -> CIImage
}

/// A serial chain of color nodes — output of one feeds into the next.
public final class SerialNode: ColorNode, @unchecked Sendable {
    public let id: UUID
    public let name: String
    public var isEnabled: Bool
    public private(set) var children: [any ColorNode]

    public init(
        id: UUID = UUID(),
        name: String = "Serial",
        isEnabled: Bool = true,
        children: [any ColorNode] = []
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.children = children
    }

    public func append(_ node: any ColorNode) {
        children.append(node)
    }

    public func remove(at index: Int) {
        children.remove(at: index)
    }

    public func process(_ image: CIImage, parameters: ParameterValues) -> CIImage {
        guard isEnabled else { return image }
        var current = image
        for child in children where child.isEnabled {
            current = child.process(current, parameters: parameters)
        }
        return current
    }
}

/// A parallel node that processes the same input through multiple branches
/// and blends them together using a specified blend mode.
public final class ParallelNode: ColorNode, @unchecked Sendable {
    public let id: UUID
    public let name: String
    public var isEnabled: Bool
    public var blendMode: BlendMode
    public private(set) var layers: [any ColorNode]

    public init(
        id: UUID = UUID(),
        name: String = "Parallel",
        isEnabled: Bool = true,
        blendMode: BlendMode = .normal,
        layers: [any ColorNode] = []
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.blendMode = blendMode
        self.layers = layers
    }

    public func addLayer(_ node: any ColorNode) {
        layers.append(node)
    }

    public func removeLayer(at index: Int) {
        layers.remove(at: index)
    }

    public func process(_ image: CIImage, parameters: ParameterValues) -> CIImage {
        guard isEnabled else { return image }
        guard !layers.isEmpty else { return image }

        let enabledLayers = layers.filter { $0.isEnabled }
        guard !enabledLayers.isEmpty else { return image }

        // Process first layer as base
        var result = enabledLayers[0].process(image, parameters: parameters)

        // Composite subsequent layers
        for i in 1..<enabledLayers.count {
            let layerOutput = enabledLayers[i].process(image, parameters: parameters)
            result = blend(layerOutput, over: result, mode: blendMode)
        }

        return result
    }

    // MARK: - Private

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

/// A leaf node that wraps a CIFilterEffect for use in the grading graph.
public final class FilterNode: ColorNode, @unchecked Sendable {
    public let id: UUID
    public let name: String
    public var isEnabled: Bool
    public let effect: CIFilterEffect
    public var effectParameters: ParameterValues

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        effect: CIFilterEffect,
        effectParameters: ParameterValues = ParameterValues()
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.effect = effect
        self.effectParameters = effectParameters
    }

    public func process(_ image: CIImage, parameters: ParameterValues) -> CIImage {
        guard isEnabled else { return image }
        // Use the node's own parameters, falling back to graph-level parameters
        var merged = parameters
        for key in effectParameters.allKeys {
            merged[key] = effectParameters[key]
        }
        return effect.apply(to: image, parameters: merged)
    }
}

/// A leaf node that wraps a ColorWheelEffect.
public final class ColorWheelNode: ColorNode, @unchecked Sendable {
    public let id: UUID
    public let name: String
    public var isEnabled: Bool
    private let effect = ColorWheelEffect()
    public var effectParameters: ParameterValues

    public init(
        id: UUID = UUID(),
        name: String = "Color Wheels",
        isEnabled: Bool = true,
        effectParameters: ParameterValues = ParameterValues()
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.effectParameters = effectParameters
    }

    public func process(_ image: CIImage, parameters: ParameterValues) -> CIImage {
        guard isEnabled else { return image }
        var merged = parameters
        for key in effectParameters.allKeys {
            merged[key] = effectParameters[key]
        }
        return effect.apply(to: image, parameters: merged)
    }
}

/// A leaf node that wraps a CurvesEffect.
public final class CurvesNode: ColorNode, @unchecked Sendable {
    public let id: UUID
    public let name: String
    public var isEnabled: Bool
    private let effect = CurvesEffect()
    public var effectParameters: ParameterValues

    public init(
        id: UUID = UUID(),
        name: String = "Curves",
        isEnabled: Bool = true,
        effectParameters: ParameterValues = ParameterValues()
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.effectParameters = effectParameters
    }

    public func process(_ image: CIImage, parameters: ParameterValues) -> CIImage {
        guard isEnabled else { return image }
        var merged = parameters
        for key in effectParameters.allKeys {
            merged[key] = effectParameters[key]
        }
        return effect.apply(to: image, parameters: merged)
    }
}

/// Manages a directed acyclic graph (DAG) of color grading nodes.
///
/// The graph has a single root node that can be a SerialNode, ParallelNode,
/// or any ColorNode. Processing starts at the root and flows through the tree.
public final class ColorGradingGraph: @unchecked Sendable {
    public var root: (any ColorNode)?
    public var isEnabled: Bool = true

    public init(root: (any ColorNode)? = nil) {
        self.root = root
    }

    /// Processes an image through the entire grading graph.
    public func process(_ image: CIImage, parameters: ParameterValues = ParameterValues()) -> CIImage {
        guard isEnabled, let root = root else { return image }
        return root.process(image, parameters: parameters)
    }

    /// Convenience: creates a simple serial pipeline from the given nodes.
    public static func serialPipeline(name: String = "Pipeline", nodes: [any ColorNode]) -> ColorGradingGraph {
        let serial = SerialNode(name: name, children: nodes)
        return ColorGradingGraph(root: serial)
    }
}
