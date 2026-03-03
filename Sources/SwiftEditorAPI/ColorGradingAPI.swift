import CoreImage
import Foundation
import CoreMediaPlus
import EffectsEngine
import Observation

/// Thread-safe store for color grading graphs keyed by clip ID.
@Observable
public final class ColorGradingStore: @unchecked Sendable {
    private var graphs: [UUID: ColorGradingGraph] = [:]

    public init() {}

    /// Get or create the color grading graph for a clip.
    public func graph(for clipID: UUID) -> ColorGradingGraph {
        if let existing = graphs[clipID] {
            return existing
        }
        let newGraph = ColorGradingGraph()
        graphs[clipID] = newGraph
        return newGraph
    }

    /// Get existing graph without creating one.
    public func existingGraph(for clipID: UUID) -> ColorGradingGraph? {
        graphs[clipID]
    }

    /// Remove the color grading graph for a clip.
    public func removeGraph(for clipID: UUID) {
        graphs.removeValue(forKey: clipID)
    }

    /// All clip IDs that have color grading graphs.
    public var clipIDs: Set<UUID> {
        Set(graphs.keys)
    }
}

/// Facade for color grading operations.
/// Manages per-clip color grading node graphs.
public final class ColorGradingAPI: @unchecked Sendable {
    public let store: ColorGradingStore
    private let lutLoader = LUTLoader()

    public init(store: ColorGradingStore) {
        self.store = store
    }

    /// Create or get the color grading graph for a clip.
    public func createGraph(for clipID: UUID) -> ColorGradingGraph {
        store.graph(for: clipID)
    }

    /// Get existing graph for a clip.
    public func graph(for clipID: UUID) -> ColorGradingGraph? {
        store.existingGraph(for: clipID)
    }

    /// Remove the color grading graph for a clip.
    public func removeGraph(for clipID: UUID) {
        store.removeGraph(for: clipID)
    }

    /// Add a serial node to the graph root. Returns the node ID.
    @discardableResult
    public func addSerialNode(clipID: UUID, name: String) -> UUID {
        let graph = store.graph(for: clipID)
        let node = SerialNode(name: name)
        if let root = graph.root as? SerialNode {
            root.append(node)
        } else {
            let serial = SerialNode(name: "Root")
            if let existingRoot = graph.root {
                serial.append(existingRoot)
            }
            serial.append(node)
            graph.root = serial
        }
        return node.id
    }

    /// Add a parallel node to the graph root. Returns the node ID.
    @discardableResult
    public func addParallelNode(clipID: UUID, name: String, blendMode: BlendMode) -> UUID {
        let graph = store.graph(for: clipID)
        let node = ParallelNode(name: name, blendMode: blendMode)
        if let root = graph.root as? SerialNode {
            root.append(node)
        } else {
            let serial = SerialNode(name: "Root")
            if let existingRoot = graph.root {
                serial.append(existingRoot)
            }
            serial.append(node)
            graph.root = serial
        }
        return node.id
    }

    /// Add a color wheel node. If parentNodeID is nil, adds to root serial chain.
    @discardableResult
    public func addColorWheelNode(clipID: UUID, parentNodeID: UUID?) -> UUID {
        let graph = store.graph(for: clipID)
        let node = ColorWheelNode()
        appendNode(node, to: graph, parentNodeID: parentNodeID)
        return node.id
    }

    /// Add a curves node. If parentNodeID is nil, adds to root serial chain.
    @discardableResult
    public func addCurvesNode(clipID: UUID, parentNodeID: UUID?) -> UUID {
        let graph = store.graph(for: clipID)
        let node = CurvesNode()
        appendNode(node, to: graph, parentNodeID: parentNodeID)
        return node.id
    }

    /// Add a CIFilter node. If parentNodeID is nil, adds to root serial chain.
    @discardableResult
    public func addFilterNode(clipID: UUID, filterName: String, parentNodeID: UUID?) -> UUID {
        let graph = store.graph(for: clipID)
        let effect = CIFilterEffect(filterName: filterName)
        let node = FilterNode(name: filterName, effect: effect)
        appendNode(node, to: graph, parentNodeID: parentNodeID)
        return node.id
    }

    /// Toggle a node's enabled state.
    public func setNodeEnabled(clipID: UUID, nodeID: UUID, enabled: Bool) {
        guard let graph = store.existingGraph(for: clipID) else { return }
        if let found = findColorNode(nodeID, in: graph) {
            setEnabledOnNode(found, enabled: enabled)
        }
    }

    /// Set parameters on a node.
    public func setNodeParameters(clipID: UUID, nodeID: UUID, parameters: ParameterValues) {
        guard let graph = store.existingGraph(for: clipID) else { return }
        if let found = findColorNode(nodeID, in: graph) {
            setParametersOnNode(found, parameters: parameters)
        }
    }

    /// Load a LUT file from disk.
    public func loadLUT(from url: URL) throws -> CIFilter {
        let lutData = try lutLoader.load(from: url)
        guard let filter = lutLoader.createFilter(from: lutData) else {
            throw LUTError.invalidFormat("Failed to create CIFilter from LUT data")
        }
        return filter
    }

    /// Apply a LUT as a filter node in the clip's grading graph. Returns the node ID.
    @discardableResult
    public func applyLUT(clipID: UUID, lutFilter: CIFilter, name: String) -> UUID {
        let graph = store.graph(for: clipID)
        let filterName = lutFilter.name
        let effect = CIFilterEffect(filterName: filterName)
        let node = FilterNode(name: name, effect: effect)
        appendNode(node, to: graph, parentNodeID: nil)
        return node.id
    }

    /// Process an image through a clip's color grading graph.
    public func processImage(_ image: CIImage, clipID: UUID, parameters: ParameterValues) -> CIImage {
        guard let graph = store.existingGraph(for: clipID) else { return image }
        return graph.process(image, parameters: parameters)
    }

    // MARK: - Private Helpers

    private func appendNode(_ node: any ColorNode, to graph: ColorGradingGraph, parentNodeID: UUID?) {
        if let parentID = parentNodeID, let parent = findColorNode(parentID, in: graph) {
            if let serial = parent as? SerialNode {
                serial.append(node)
            } else if let parallel = parent as? ParallelNode {
                parallel.addLayer(node)
            }
        } else {
            // Add to root serial chain
            if let root = graph.root as? SerialNode {
                root.append(node)
            } else {
                let serial = SerialNode(name: "Root")
                if let existingRoot = graph.root {
                    serial.append(existingRoot)
                }
                serial.append(node)
                graph.root = serial
            }
        }
    }

    private func findColorNode(_ nodeID: UUID, in graph: ColorGradingGraph) -> (any ColorNode)? {
        guard let root = graph.root else { return nil }
        return findColorNodeRecursive(nodeID, in: root)
    }

    private func findColorNodeRecursive(_ nodeID: UUID, in node: any ColorNode) -> (any ColorNode)? {
        if node.id == nodeID { return node }
        if let serial = node as? SerialNode {
            for child in serial.children {
                if let found = findColorNodeRecursive(nodeID, in: child) { return found }
            }
        }
        if let parallel = node as? ParallelNode {
            for layer in parallel.layers {
                if let found = findColorNodeRecursive(nodeID, in: layer) { return found }
            }
        }
        return nil
    }

    private func setEnabledOnNode(_ node: any ColorNode, enabled: Bool) {
        if let serial = node as? SerialNode { serial.isEnabled = enabled }
        else if let parallel = node as? ParallelNode { parallel.isEnabled = enabled }
        else if let filter = node as? FilterNode { filter.isEnabled = enabled }
        else if let wheel = node as? ColorWheelNode { wheel.isEnabled = enabled }
        else if let curves = node as? CurvesNode { curves.isEnabled = enabled }
    }

    private func setParametersOnNode(_ node: any ColorNode, parameters: ParameterValues) {
        if let filter = node as? FilterNode {
            for key in parameters.allKeys {
                filter.effectParameters[key] = parameters[key]
            }
        } else if let wheel = node as? ColorWheelNode {
            for key in parameters.allKeys {
                wheel.effectParameters[key] = parameters[key]
            }
        } else if let curves = node as? CurvesNode {
            for key in parameters.allKeys {
                curves.effectParameters[key] = parameters[key]
            }
        }
    }
}
