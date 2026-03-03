import CoreImage
import CoreMediaPlus
import Foundation

/// High-level evaluator that processes a NodeGraph with optimized texture routing.
/// Handles intermediate result management and caching between evaluations.
public final class NodeGraphEvaluator: @unchecked Sendable {
    private let ciContext: CIContext
    private var resultCache: [UUID: [String: CIImage]] = [:]
    private var lastEvaluationTime: Rational?

    public init(ciContext: CIContext? = nil) {
        self.ciContext = ciContext ?? CIContext(options: [
            .cacheIntermediates: false,
            .priorityRequestLow: false,
        ])
    }

    /// Evaluates the graph and returns the final output image.
    /// Caches intermediate results for nodes whose inputs haven't changed.
    public func evaluate(
        graph: NodeGraph,
        inputImages: [UUID: CIImage],
        at time: Rational,
        parameters: ParameterValues = ParameterValues()
    ) -> CIImage? {
        guard graph.isEnabled else { return nil }

        // Set input images on InputNodes
        for node in graph.nodes {
            if let inputNode = node as? InputNode, let image = inputImages[inputNode.id] {
                inputNode.image = image
            }
        }

        // Invalidate cache if time changed
        if lastEvaluationTime != time {
            resultCache.removeAll()
            lastEvaluationTime = time
        }

        let order = graph.topologicalSort()
        guard !order.isEmpty else { return nil }

        for nodeID in order {
            guard let node = graph.node(byID: nodeID) else { continue }

            // Gather inputs from connections
            var inputs: [String: CIImage] = [:]
            let incomingConnections = graph.incomingConnections(for: nodeID)
            for conn in incomingConnections {
                if let sourceOutputs = resultCache[conn.sourceNodeID],
                   let image = sourceOutputs[conn.sourcePort] {
                    inputs[conn.destPort] = image
                }
            }

            if node.isEnabled {
                let outputs = node.process(inputs: inputs, parameters: parameters, at: time)
                resultCache[nodeID] = outputs
            } else {
                // Pass-through first input
                let firstImage = inputs.values.first
                var passthroughOutputs: [String: CIImage] = [:]
                for desc in node.outputDescriptors {
                    if let img = firstImage {
                        passthroughOutputs[desc.name] = img
                    }
                }
                resultCache[nodeID] = passthroughOutputs
            }
        }

        // Return output from designated output node
        if let outputNodeID = graph.outputNodeID {
            return resultCache[outputNodeID]?["output"]
        }

        // Fallback: return output from the last node in evaluation order
        if let lastNodeID = order.last {
            return resultCache[lastNodeID]?.values.first
        }

        return nil
    }

    /// Clears the intermediate result cache.
    public func invalidateCache() {
        resultCache.removeAll()
        lastEvaluationTime = nil
    }

    /// Returns the number of cached node results.
    public var cacheSize: Int {
        resultCache.count
    }
}

// MARK: - NodeGraph Builder Helpers

extension NodeGraph {
    /// Creates a simple two-layer composite graph.
    /// Background → BlendNode ← Foreground → Output
    public static func simpleComposite(
        name: String = "Composite",
        blendMode: BlendMode = .normal,
        opacity: Double = 1.0
    ) -> (graph: NodeGraph, backgroundInput: InputNode, foregroundInput: InputNode) {
        let graph = NodeGraph(name: name)

        let bgInput = InputNode(name: "Background")
        let fgInput = InputNode(name: "Foreground")
        let blendNode = BlendNode(name: "Blend", blendMode: blendMode, opacity: opacity)
        let output = OutputNode()

        graph.addNode(bgInput)
        graph.addNode(fgInput)
        graph.addNode(blendNode)
        graph.addNode(output)

        graph.connect(from: bgInput.id, sourcePort: "output", to: blendNode.id, destPort: "background")
        graph.connect(from: fgInput.id, sourcePort: "output", to: blendNode.id, destPort: "foreground")
        graph.connect(from: blendNode.id, sourcePort: "output", to: output.id, destPort: "input")

        graph.outputNodeID = output.id

        return (graph, bgInput, fgInput)
    }

    /// Creates a linear chain: Input → [effects...] → Output
    public static func linearChain(
        name: String = "Effect Chain",
        effects: [any CompositorNode]
    ) -> (graph: NodeGraph, input: InputNode) {
        let graph = NodeGraph(name: name)

        let input = InputNode(name: "Input")
        let output = OutputNode()

        graph.addNode(input)

        var previousNodeID = input.id
        var previousPort = "output"

        for effect in effects {
            graph.addNode(effect)
            let inputPort = effect.inputDescriptors.first?.name ?? "input"
            graph.connect(from: previousNodeID, sourcePort: previousPort, to: effect.id, destPort: inputPort)
            previousNodeID = effect.id
            previousPort = effect.outputDescriptors.first?.name ?? "output"
        }

        graph.addNode(output)
        graph.connect(from: previousNodeID, sourcePort: previousPort, to: output.id, destPort: "input")
        graph.outputNodeID = output.id

        return (graph, input)
    }
}
