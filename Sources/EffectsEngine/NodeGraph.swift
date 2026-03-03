import CoreImage
import CoreMediaPlus
import Foundation
import Observation

// MARK: - Node Protocol

/// A compositing node in the node graph.
/// Each node has typed input/output ports and processes CIImages.
public protocol CompositorNode: AnyObject, Sendable, Identifiable where ID == UUID {
    var id: UUID { get }
    var name: String { get set }
    var isEnabled: Bool { get set }

    /// Descriptors for this node's input ports.
    var inputDescriptors: [NodePortDescriptor] { get }

    /// Descriptors for this node's output ports.
    var outputDescriptors: [NodePortDescriptor] { get }

    /// Process the node given resolved input images.
    /// `inputs` is keyed by port name from `inputDescriptors`.
    func process(inputs: [String: CIImage], parameters: ParameterValues, at time: Rational) -> [String: CIImage]
}

// MARK: - Port Descriptor

/// Describes an input or output port on a compositor node.
public struct NodePortDescriptor: Sendable, Hashable {
    public let name: String
    public let label: String

    public init(name: String, label: String) {
        self.name = name
        self.label = label
    }
}

// MARK: - Node Connection

/// A connection between an output port of one node and an input port of another.
public struct NodeConnection: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public let sourceNodeID: UUID
    public let sourcePort: String
    public let destNodeID: UUID
    public let destPort: String

    public init(
        id: UUID = UUID(),
        sourceNodeID: UUID,
        sourcePort: String,
        destNodeID: UUID,
        destPort: String
    ) {
        self.id = id
        self.sourceNodeID = sourceNodeID
        self.sourcePort = sourcePort
        self.destNodeID = destNodeID
        self.destPort = destPort
    }
}

// MARK: - Node Graph

/// Directed acyclic graph of compositor nodes with arbitrary connections.
/// Supports multi-input compositing, branching, and merging.
@Observable
public final class NodeGraph: @unchecked Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var isEnabled: Bool = true

    public private(set) var nodes: [any CompositorNode] = []
    public private(set) var connections: [NodeConnection] = []

    /// The node whose output is the final composited result.
    public var outputNodeID: UUID?

    public init(id: UUID = UUID(), name: String = "Node Graph") {
        self.id = id
        self.name = name
    }

    // MARK: - Node Management

    public func addNode(_ node: any CompositorNode) {
        nodes.append(node)
    }

    public func removeNode(_ nodeID: UUID) {
        nodes.removeAll { $0.id == nodeID }
        connections.removeAll { $0.sourceNodeID == nodeID || $0.destNodeID == nodeID }
        if outputNodeID == nodeID { outputNodeID = nil }
    }

    public func node(byID id: UUID) -> (any CompositorNode)? {
        nodes.first { $0.id == id }
    }

    // MARK: - Connection Management

    /// Connects a source node's output port to a destination node's input port.
    /// Returns false if the connection would create a cycle.
    @discardableResult
    public func connect(
        from sourceNodeID: UUID,
        sourcePort: String,
        to destNodeID: UUID,
        destPort: String
    ) -> Bool {
        // Prevent self-loops
        guard sourceNodeID != destNodeID else { return false }

        let connection = NodeConnection(
            sourceNodeID: sourceNodeID,
            sourcePort: sourcePort,
            destNodeID: destNodeID,
            destPort: destPort
        )

        // Remove existing connection to this input port (only one source per input)
        connections.removeAll { $0.destNodeID == destNodeID && $0.destPort == destPort }

        // Temporarily add and check for cycles
        connections.append(connection)
        if hasCycle() {
            connections.removeLast()
            return false
        }

        return true
    }

    public func disconnect(_ connectionID: UUID) {
        connections.removeAll { $0.id == connectionID }
    }

    public func disconnectAll(from nodeID: UUID) {
        connections.removeAll { $0.sourceNodeID == nodeID || $0.destNodeID == nodeID }
    }

    // MARK: - Evaluation

    /// Evaluates the graph and returns the output image from the output node.
    public func evaluate(at time: Rational, parameters: ParameterValues = ParameterValues()) -> CIImage? {
        guard isEnabled, let outputNodeID else { return nil }

        let order = topologicalSort()
        guard !order.isEmpty else { return nil }

        // Cache of computed outputs per node
        var outputCache: [UUID: [String: CIImage]] = [:]

        for nodeID in order {
            guard let node = node(byID: nodeID) else { continue }

            // Gather inputs from connected source nodes
            var inputs: [String: CIImage] = [:]
            let incomingConnections = connections.filter { $0.destNodeID == nodeID }
            for conn in incomingConnections {
                if let sourceOutputs = outputCache[conn.sourceNodeID],
                   let image = sourceOutputs[conn.sourcePort] {
                    inputs[conn.destPort] = image
                }
            }

            if node.isEnabled {
                let outputs = node.process(inputs: inputs, parameters: parameters, at: time)
                outputCache[nodeID] = outputs
            } else {
                // Pass through first input if disabled
                let firstInput = inputs.values.first
                let passthroughOutputs = node.outputDescriptors.reduce(into: [String: CIImage]()) { dict, desc in
                    dict[desc.name] = firstInput
                }
                outputCache[nodeID] = passthroughOutputs
            }
        }

        return outputCache[outputNodeID]?["output"]
    }

    // MARK: - Topological Sort

    /// Returns node IDs in evaluation order (topological sort).
    /// Returns empty array if the graph contains a cycle.
    public func topologicalSort() -> [UUID] {
        var inDegree: [UUID: Int] = [:]
        var adjacency: [UUID: [UUID]] = [:]

        for node in nodes {
            inDegree[node.id] = 0
            adjacency[node.id] = []
        }

        for conn in connections {
            adjacency[conn.sourceNodeID, default: []].append(conn.destNodeID)
            inDegree[conn.destNodeID, default: 0] += 1
        }

        var queue: [UUID] = []
        for (nodeID, degree) in inDegree where degree == 0 {
            queue.append(nodeID)
        }

        var sorted: [UUID] = []
        while !queue.isEmpty {
            let current = queue.removeFirst()
            sorted.append(current)

            for neighbor in adjacency[current, default: []] {
                inDegree[neighbor, default: 0] -= 1
                if inDegree[neighbor] == 0 {
                    queue.append(neighbor)
                }
            }
        }

        return sorted.count == nodes.count ? sorted : []
    }

    // MARK: - Cycle Detection

    /// Returns true if the graph contains a cycle.
    public func hasCycle() -> Bool {
        topologicalSort().isEmpty && !nodes.isEmpty
    }

    // MARK: - Query

    /// Returns connections feeding into a specific node.
    public func incomingConnections(for nodeID: UUID) -> [NodeConnection] {
        connections.filter { $0.destNodeID == nodeID }
    }

    /// Returns connections going out from a specific node.
    public func outgoingConnections(for nodeID: UUID) -> [NodeConnection] {
        connections.filter { $0.sourceNodeID == nodeID }
    }
}
