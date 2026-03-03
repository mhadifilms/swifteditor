import SwiftUI
import SwiftEditorAPI
import EffectsEngine
import CoreMediaPlus

// MARK: - Node Layout Model

/// Stores the 2D position of each node in the editor canvas.
@Observable
final class NodeEditorLayout {
    var positions: [UUID: CGPoint] = [:]
    var selectedNodeID: UUID?
    var selectedConnectionID: UUID?

    func position(for nodeID: UUID) -> CGPoint {
        positions[nodeID] ?? CGPoint(x: 100, y: 100)
    }

    func setPosition(_ point: CGPoint, for nodeID: UUID) {
        positions[nodeID] = point
    }
}

// MARK: - Node Editor Constants

private enum NodeEditorConstants {
    static let nodeWidth: CGFloat = 160
    static let nodeHeaderHeight: CGFloat = 28
    static let portHeight: CGFloat = 20
    static let portRadius: CGFloat = 5
    static let portInset: CGFloat = 8
    static let canvasSize: CGFloat = 4000
}

// MARK: - Node Editor View

/// Visual node graph editor using SwiftUI Canvas.
/// Renders nodes as rounded rects with input/output ports, connections as bezier curves,
/// and supports drag-to-reposition, drag-to-connect, and selection.
struct NodeEditorView: View {
    let engine: SwiftEditorEngine

    @State private var layout = NodeEditorLayout()
    @State private var graph: NodeGraph?
    @State private var dragConnection: DragConnectionState?
    @State private var scrollOffset: CGPoint = .zero

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar for adding nodes
            nodeToolbar

            Divider()

            // Canvas
            if let graph {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    nodeCanvas(graph: graph)
                        .frame(
                            width: NodeEditorConstants.canvasSize,
                            height: NodeEditorConstants.canvasSize
                        )
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .onAppear { initializeLayout(graph: graph) }
            } else {
                emptyState
            }
        }
        .onAppear {
            graph = engine.nodeGraph.createNodeGraph()
        }
    }

    // MARK: - Toolbar

    private var nodeToolbar: some View {
        HStack(spacing: 12) {
            Text("Node Graph")
                .font(.headline)

            Spacer()

            Menu {
                Button("Input") { addNode(type: .input) }
                Button("Output") { addNode(type: .output) }
                Divider()
                Button("Blend") { addNode(type: .blend) }
                Button("Transform") { addNode(type: .transform) }
                Button("Color Correction") { addNode(type: .colorCorrection) }
                Button("Blur") { addNode(type: .blur) }
                Button("Keyer") { addNode(type: .keyer) }
            } label: {
                Label("Add Node", systemImage: "plus.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Add node")
            .accessibilityHint("Add a new compositor node to the graph")

            Button {
                deleteSelected()
            } label: {
                Image(systemName: "trash")
            }
            .liquidGlassButton()
            .disabled(layout.selectedNodeID == nil && layout.selectedConnectionID == nil)
            .help("Delete selected node or connection")
            .accessibilityLabel("Delete selected")
            .accessibilityHint("Remove the selected node or connection from the graph")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .liquidGlassBar()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No Node Graph")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Use the toolbar to add nodes")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Canvas

    private func nodeCanvas(graph: NodeGraph) -> some View {
        ZStack(alignment: .topLeading) {
            // Grid background
            Canvas { context, size in
                drawGrid(context: context, size: size)
            }

            // Connections layer
            Canvas { context, size in
                drawConnections(context: context, graph: graph)
                if let drag = dragConnection {
                    drawDragConnection(context: context, drag: drag)
                }
            }
            .allowsHitTesting(false)

            // Node views
            ForEach(graph.nodes.map(NodeWrapper.init), id: \.id) { wrapper in
                NodeView(
                    node: wrapper.node,
                    isSelected: layout.selectedNodeID == wrapper.id,
                    onSelect: { layout.selectedNodeID = wrapper.id; layout.selectedConnectionID = nil },
                    onPortDragStarted: { port, isOutput in
                        startConnectionDrag(nodeID: wrapper.id, port: port, isOutput: isOutput)
                    },
                    onPortDragEnded: { port, isOutput in
                        endConnectionDrag(graph: graph, targetNodeID: wrapper.id, targetPort: port, isInput: !isOutput)
                    }
                )
                .position(layout.position(for: wrapper.id))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            layout.positions[wrapper.id] = value.location
                        }
                )
            }

            // Connection hit targets (invisible rects on midpoints for selection)
            ForEach(graph.connections) { connection in
                connectionHitTarget(connection: connection, graph: graph)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            layout.selectedNodeID = nil
            layout.selectedConnectionID = nil
        }
    }

    // MARK: - Grid Drawing

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 40
        let color = Color.secondary.opacity(0.08)

        for x in stride(from: 0, through: size.width, by: spacing) {
            let path = Path { p in
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(path, with: .color(color), lineWidth: 0.5)
        }
        for y in stride(from: 0, through: size.height, by: spacing) {
            let path = Path { p in
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(color), lineWidth: 0.5)
        }
    }

    // MARK: - Connection Drawing

    private func drawConnections(context: GraphicsContext, graph: NodeGraph) {
        for connection in graph.connections {
            let sourcePos = outputPortPosition(nodeID: connection.sourceNodeID, port: connection.sourcePort, graph: graph)
            let destPos = inputPortPosition(nodeID: connection.destNodeID, port: connection.destPort, graph: graph)

            let isSelected = layout.selectedConnectionID == connection.id
            let path = bezierPath(from: sourcePos, to: destPos)
            context.stroke(
                path,
                with: .color(isSelected ? Color.accentColor : Color.orange),
                lineWidth: isSelected ? 3 : 2
            )
        }
    }

    private func drawDragConnection(context: GraphicsContext, drag: DragConnectionState) {
        let path = bezierPath(from: drag.startPoint, to: drag.currentPoint)
        context.stroke(path, with: .color(Color.yellow.opacity(0.7)), style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
    }

    private func bezierPath(from start: CGPoint, to end: CGPoint) -> Path {
        let controlOffset = abs(end.x - start.x) * 0.5
        return Path { p in
            p.move(to: start)
            p.addCurve(
                to: end,
                control1: CGPoint(x: start.x + controlOffset, y: start.y),
                control2: CGPoint(x: end.x - controlOffset, y: end.y)
            )
        }
    }

    // MARK: - Port Positions

    private func outputPortPosition(nodeID: UUID, port: String, graph: NodeGraph) -> CGPoint {
        guard let node = graph.node(byID: nodeID) else { return .zero }
        let origin = layout.position(for: nodeID)
        let nc = NodeEditorConstants.self
        let portIndex = node.outputDescriptors.firstIndex(where: { $0.name == port }) ?? 0
        let inputCount = node.inputDescriptors.count
        let y = origin.y - nodeHeight(for: node) / 2 + nc.nodeHeaderHeight + CGFloat(inputCount) * nc.portHeight + CGFloat(portIndex) * nc.portHeight + nc.portHeight / 2
        let x = origin.x + nc.nodeWidth / 2
        return CGPoint(x: x, y: y)
    }

    private func inputPortPosition(nodeID: UUID, port: String, graph: NodeGraph) -> CGPoint {
        guard let node = graph.node(byID: nodeID) else { return .zero }
        let origin = layout.position(for: nodeID)
        let nc = NodeEditorConstants.self
        let portIndex = node.inputDescriptors.firstIndex(where: { $0.name == port }) ?? 0
        let y = origin.y - nodeHeight(for: node) / 2 + nc.nodeHeaderHeight + CGFloat(portIndex) * nc.portHeight + nc.portHeight / 2
        let x = origin.x - nc.nodeWidth / 2
        return CGPoint(x: x, y: y)
    }

    private func nodeHeight(for node: any CompositorNode) -> CGFloat {
        let portCount = max(node.inputDescriptors.count + node.outputDescriptors.count, 1)
        return NodeEditorConstants.nodeHeaderHeight + CGFloat(portCount) * NodeEditorConstants.portHeight + 8
    }

    // MARK: - Connection Hit Targets

    private func connectionHitTarget(connection: NodeConnection, graph: NodeGraph) -> some View {
        let sourcePos = outputPortPosition(nodeID: connection.sourceNodeID, port: connection.sourcePort, graph: graph)
        let destPos = inputPortPosition(nodeID: connection.destNodeID, port: connection.destPort, graph: graph)
        let midpoint = CGPoint(x: (sourcePos.x + destPos.x) / 2, y: (sourcePos.y + destPos.y) / 2)

        return Rectangle()
            .fill(Color.clear)
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
            .position(midpoint)
            .onTapGesture {
                layout.selectedConnectionID = connection.id
                layout.selectedNodeID = nil
            }
    }

    // MARK: - Actions

    private enum NodeType {
        case input, output, blend, transform, colorCorrection, blur, keyer
    }

    private func addNode(type: NodeType) {
        guard let graph else { return }
        let node: any CompositorNode
        switch type {
        case .input:
            node = engine.nodeGraph.makeInputNode(name: "Input \(graph.nodes.count + 1)")
        case .output:
            node = engine.nodeGraph.makeOutputNode(name: "Output")
        case .blend:
            node = engine.nodeGraph.makeBlendNode(mode: .normal)
        case .transform:
            node = engine.nodeGraph.makeTransformNode()
        case .colorCorrection:
            node = engine.nodeGraph.makeColorCorrectionNode()
        case .blur:
            node = engine.nodeGraph.makeBlurNode()
        case .keyer:
            node = engine.nodeGraph.makeKeyerNode()
        }
        engine.nodeGraph.addNode(node, to: graph)

        // Place new node at a visible default position offset from existing nodes
        let offset = CGFloat(graph.nodes.count - 1) * 40
        layout.positions[node.id] = CGPoint(x: 300 + offset, y: 200 + offset)

        if type == .output {
            graph.outputNodeID = node.id
        }
    }

    private func deleteSelected() {
        guard let graph else { return }
        if let connectionID = layout.selectedConnectionID {
            graph.disconnect(connectionID)
            layout.selectedConnectionID = nil
        } else if let nodeID = layout.selectedNodeID {
            engine.nodeGraph.removeNode(nodeID, from: graph)
            layout.positions.removeValue(forKey: nodeID)
            layout.selectedNodeID = nil
        }
    }

    private func initializeLayout(graph: NodeGraph) {
        for (index, node) in graph.nodes.enumerated() {
            if layout.positions[node.id] == nil {
                layout.positions[node.id] = CGPoint(
                    x: 200 + CGFloat(index) * 200,
                    y: 300
                )
            }
        }
    }

    // MARK: - Connection Dragging

    private func startConnectionDrag(nodeID: UUID, port: String, isOutput: Bool) {
        guard let graph else { return }
        let point: CGPoint
        if isOutput {
            point = outputPortPosition(nodeID: nodeID, port: port, graph: graph)
        } else {
            point = inputPortPosition(nodeID: nodeID, port: port, graph: graph)
        }
        dragConnection = DragConnectionState(
            sourceNodeID: nodeID,
            sourcePort: port,
            isFromOutput: isOutput,
            startPoint: point,
            currentPoint: point
        )
    }

    private func endConnectionDrag(graph: NodeGraph, targetNodeID: UUID, targetPort: String, isInput: Bool) {
        guard let drag = dragConnection else { return }
        defer { dragConnection = nil }

        if drag.isFromOutput && isInput {
            try? engine.nodeGraph.connect(
                from: drag.sourceNodeID,
                outputPort: drag.sourcePort,
                to: targetNodeID,
                inputPort: targetPort,
                in: graph
            )
        } else if !drag.isFromOutput && !isInput {
            try? engine.nodeGraph.connect(
                from: targetNodeID,
                outputPort: targetPort,
                to: drag.sourceNodeID,
                inputPort: drag.sourcePort,
                in: graph
            )
        }
    }
}

// MARK: - Drag Connection State

private struct DragConnectionState {
    let sourceNodeID: UUID
    let sourcePort: String
    let isFromOutput: Bool
    let startPoint: CGPoint
    var currentPoint: CGPoint
}

// MARK: - Node Wrapper (for ForEach with existential)

/// Wraps `any CompositorNode` for use in ForEach (needs concrete Identifiable).
private struct NodeWrapper: Identifiable {
    let node: any CompositorNode
    var id: UUID { node.id }
}

// MARK: - Individual Node View

/// Renders a single compositor node as a rounded rect with port circles.
private struct NodeView: View {
    let node: any CompositorNode
    let isSelected: Bool
    let onSelect: () -> Void
    let onPortDragStarted: (String, Bool) -> Void
    let onPortDragEnded: (String, Bool) -> Void

    private var nodeHeight: CGFloat {
        let portCount = max(node.inputDescriptors.count + node.outputDescriptors.count, 1)
        return NodeEditorConstants.nodeHeaderHeight + CGFloat(portCount) * NodeEditorConstants.portHeight + 8
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(node.isEnabled ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(node.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: NodeEditorConstants.nodeHeaderHeight)
            .background(headerColor)

            // Ports
            VStack(spacing: 0) {
                // Input ports
                ForEach(node.inputDescriptors, id: \.name) { port in
                    PortRow(label: port.label, isOutput: false)
                        .frame(height: NodeEditorConstants.portHeight)
                        .onTapGesture {
                            onPortDragEnded(port.name, false)
                        }
                        .gesture(
                            DragGesture(minimumDistance: 5)
                                .onChanged { _ in
                                    onPortDragStarted(port.name, false)
                                }
                        )
                }

                // Output ports
                ForEach(node.outputDescriptors, id: \.name) { port in
                    PortRow(label: port.label, isOutput: true)
                        .frame(height: NodeEditorConstants.portHeight)
                        .onTapGesture {
                            onPortDragEnded(port.name, true)
                        }
                        .gesture(
                            DragGesture(minimumDistance: 5)
                                .onChanged { _ in
                                    onPortDragStarted(port.name, true)
                                }
                        )
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: NodeEditorConstants.nodeWidth)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .onTapGesture { onSelect() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(node.name) node\(isSelected ? ", selected" : "")\(node.isEnabled ? "" : ", disabled")")
        .accessibilityHint("Tap to select, drag to reposition")
    }

    private var headerColor: Color {
        if node is InputNode { return .blue.opacity(0.3) }
        if node is OutputNode { return .green.opacity(0.3) }
        if node is BlendNode { return .orange.opacity(0.3) }
        if node is TransformNode { return .purple.opacity(0.3) }
        if node is ColorCorrectionNode { return .yellow.opacity(0.3) }
        if node is BlurNode { return .cyan.opacity(0.3) }
        if node is KeyerNode { return .mint.opacity(0.3) }
        return .gray.opacity(0.3)
    }
}

// MARK: - Port Row

/// A single input or output port row in a node.
private struct PortRow: View {
    let label: String
    let isOutput: Bool

    var body: some View {
        HStack(spacing: 4) {
            if !isOutput {
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.5))
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Spacer()
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Circle()
                    .fill(Color.orange)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.5))
            }
        }
        .padding(.horizontal, NodeEditorConstants.portInset)
        .contentShape(Rectangle())
        .accessibilityLabel("\(isOutput ? "Output" : "Input") port: \(label)")
        .accessibilityHint("Drag to create a connection, or tap to connect to an active drag")
    }
}
