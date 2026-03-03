import CoreImage
import Foundation
import CoreMediaPlus
import EffectsEngine

/// Facade for compositor node graph operations.
/// Provides factories for nodes and convenience methods for building graphs.
public final class NodeGraphAPI: @unchecked Sendable {
    private let evaluator: NodeGraphEvaluator

    public init(evaluator: NodeGraphEvaluator = NodeGraphEvaluator()) {
        self.evaluator = evaluator
    }

    // MARK: - Graph Lifecycle

    /// Create a new empty node graph.
    public func createNodeGraph() -> NodeGraph {
        NodeGraph()
    }

    /// Add a node to a graph.
    public func addNode(_ node: any CompositorNode, to graph: NodeGraph) {
        graph.addNode(node)
    }

    /// Remove a node from a graph by ID.
    public func removeNode(_ nodeID: UUID, from graph: NodeGraph) {
        graph.removeNode(nodeID)
    }

    /// Connect an output port of one node to an input port of another.
    public func connect(
        from outputNodeID: UUID,
        outputPort: String,
        to inputNodeID: UUID,
        inputPort: String,
        in graph: NodeGraph
    ) throws {
        let success = graph.connect(
            from: outputNodeID,
            sourcePort: outputPort,
            to: inputNodeID,
            destPort: inputPort
        )
        if !success {
            throw NodeGraphError.connectionFailed("Connection would create a cycle or is invalid")
        }
    }

    /// Disconnect an input port on a node.
    public func disconnect(inputNodeID: UUID, inputPort: String, in graph: NodeGraph) {
        let incoming = graph.incomingConnections(for: inputNodeID)
        for conn in incoming where conn.destPort == inputPort {
            graph.disconnect(conn.id)
        }
    }

    /// Evaluate a graph and return all output images.
    public func evaluate(graph: NodeGraph, at time: Rational) -> [String: CIImage] {
        guard let outputNodeID = graph.outputNodeID else { return [:] }
        let order = graph.topologicalSort()
        guard !order.isEmpty else { return [:] }

        var outputCache: [UUID: [String: CIImage]] = [:]

        for nodeID in order {
            guard let node = graph.node(byID: nodeID) else { continue }

            var inputs: [String: CIImage] = [:]
            let incomingConnections = graph.incomingConnections(for: nodeID)
            for conn in incomingConnections {
                if let sourceOutputs = outputCache[conn.sourceNodeID],
                   let image = sourceOutputs[conn.sourcePort] {
                    inputs[conn.destPort] = image
                }
            }

            if node.isEnabled {
                let outputs = node.process(inputs: inputs, parameters: ParameterValues(), at: time)
                outputCache[nodeID] = outputs
            } else {
                let firstInput = inputs.values.first
                var passthroughOutputs: [String: CIImage] = [:]
                for desc in node.outputDescriptors {
                    if let img = firstInput {
                        passthroughOutputs[desc.name] = img
                    }
                }
                outputCache[nodeID] = passthroughOutputs
            }
        }

        return outputCache[outputNodeID] ?? [:]
    }

    // MARK: - Node Factories

    /// Create an input node.
    public func makeInputNode(name: String) -> InputNode {
        InputNode(name: name)
    }

    /// Create an output node.
    public func makeOutputNode(name: String) -> OutputNode {
        OutputNode(name: name)
    }

    /// Create a blend node with the specified mode.
    public func makeBlendNode(mode: BlendMode) -> BlendNode {
        BlendNode(blendMode: mode)
    }

    /// Create a transform node.
    public func makeTransformNode() -> TransformNode {
        TransformNode()
    }

    /// Create a color correction node.
    public func makeColorCorrectionNode() -> ColorCorrectionNode {
        ColorCorrectionNode()
    }

    /// Create a blur node.
    public func makeBlurNode() -> BlurNode {
        BlurNode()
    }

    /// Create a keyer node.
    public func makeKeyerNode() -> KeyerNode {
        KeyerNode()
    }

    /// Create a CIFilter wrapper node.
    public func makeCIFilterNode(filterName: String) -> CIFilterNode {
        let effect = CIFilterEffect(filterName: filterName)
        return CIFilterNode(name: filterName, effect: effect)
    }

    // MARK: - Convenience Builders

    /// Create a simple multi-layer composite graph.
    /// Each layer is a pair of a node and its blend mode over the previous layer.
    public func simpleComposite(layers: [(any CompositorNode, BlendMode)]) -> NodeGraph {
        let graph = NodeGraph(name: "Composite")
        guard !layers.isEmpty else { return graph }

        let output = OutputNode()
        graph.addNode(output)

        if layers.count == 1 {
            let (node, _) = layers[0]
            graph.addNode(node)
            let outPort = node.outputDescriptors.first?.name ?? "output"
            graph.connect(from: node.id, sourcePort: outPort, to: output.id, destPort: "input")
        } else {
            // Build a chain of blend nodes
            let (firstNode, _) = layers[0]
            graph.addNode(firstNode)

            var previousID = firstNode.id
            var previousPort = firstNode.outputDescriptors.first?.name ?? "output"

            for i in 1..<layers.count {
                let (node, blendMode) = layers[i]
                graph.addNode(node)

                let blend = BlendNode(blendMode: blendMode)
                graph.addNode(blend)

                graph.connect(from: previousID, sourcePort: previousPort, to: blend.id, destPort: "background")
                let nodeOutPort = node.outputDescriptors.first?.name ?? "output"
                graph.connect(from: node.id, sourcePort: nodeOutPort, to: blend.id, destPort: "foreground")

                previousID = blend.id
                previousPort = "output"
            }

            graph.connect(from: previousID, sourcePort: previousPort, to: output.id, destPort: "input")
        }

        graph.outputNodeID = output.id
        return graph
    }

    /// Create a linear chain: nodes connected in sequence.
    public func linearChain(nodes: [any CompositorNode]) -> NodeGraph {
        let graph = NodeGraph(name: "Linear Chain")
        let input = InputNode(name: "Input")
        let output = OutputNode()

        graph.addNode(input)

        var previousNodeID = input.id
        var previousPort = "output"

        for node in nodes {
            graph.addNode(node)
            let inputPort = node.inputDescriptors.first?.name ?? "input"
            graph.connect(from: previousNodeID, sourcePort: previousPort, to: node.id, destPort: inputPort)
            previousNodeID = node.id
            previousPort = node.outputDescriptors.first?.name ?? "output"
        }

        graph.addNode(output)
        graph.connect(from: previousNodeID, sourcePort: previousPort, to: output.id, destPort: "input")
        graph.outputNodeID = output.id

        return graph
    }
}

// MARK: - Errors

public enum NodeGraphError: Error, Sendable {
    case connectionFailed(String)
}
