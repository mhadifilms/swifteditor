import SwiftUI
import SwiftEditorAPI
import EffectsEngine
import CoreMediaPlus

/// Color grading panel with lift/gamma/gain color wheels.
/// Shown in the Color workspace below the viewer.
struct ColorGradingView: View {
    let engine: SwiftEditorEngine

    @State private var lift = WheelState()
    @State private var gamma = WheelState()
    @State private var gain = WheelState()
    @State private var colorWheelNodeID: UUID?

    /// The first selected clip ID, if any.
    private var selectedClipID: UUID? {
        engine.selection.selectedClipIDs.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Color Wheels")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Button("Reset") {
                    lift = WheelState()
                    gamma = WheelState()
                    gain = WheelState()
                    pushColorGrading()
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Reset color wheels")
                .accessibilityHint("Reset lift, gamma, and gain color wheels to their default values")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .liquidGlassSidebarHeader()

            Divider()

            if selectedClipID != nil {
                HStack(spacing: 16) {
                    ColorWheelControl(label: "Lift", state: $lift, onChange: pushColorGrading)
                    ColorWheelControl(label: "Gamma", state: $gamma, onChange: pushColorGrading)
                    ColorWheelControl(label: "Gain", state: $gain, onChange: pushColorGrading)
                }
                .padding(12)
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "paintpalette")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Select a clip to grade")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onChange(of: selectedClipID) { _, newClipID in
            loadColorGrading(for: newClipID)
        }
        .onAppear {
            loadColorGrading(for: selectedClipID)
        }
    }

    /// Load color grading state from the backend for the given clip.
    private func loadColorGrading(for clipID: UUID?) {
        guard let clipID else {
            lift = WheelState()
            gamma = WheelState()
            gain = WheelState()
            colorWheelNodeID = nil
            return
        }

        if let graph = engine.colorGrading.graph(for: clipID) {
            // Find existing ColorWheelNode in the graph
            if let wheelNode = findColorWheelNode(in: graph) {
                colorWheelNodeID = wheelNode.id
                let params = wheelNode.effectParameters
                lift = WheelState(
                    offsetX: params.floatValue("liftR"),
                    offsetY: params.floatValue("liftB"),
                    master: params.floatValue("liftMaster")
                )
                gamma = WheelState(
                    offsetX: params.floatValue("gammaR", default: 1.0) - 1.0,
                    offsetY: params.floatValue("gammaB", default: 1.0) - 1.0,
                    master: params.floatValue("gammaMaster")
                )
                gain = WheelState(
                    offsetX: params.floatValue("gainR", default: 1.0) - 1.0,
                    offsetY: params.floatValue("gainB", default: 1.0) - 1.0,
                    master: params.floatValue("gainMaster")
                )
                return
            }
        }

        // No existing graph/node — reset to defaults
        lift = WheelState()
        gamma = WheelState()
        gain = WheelState()
        colorWheelNodeID = nil
    }

    /// Push current wheel state to the backend color grading graph.
    private func pushColorGrading() {
        guard let clipID = selectedClipID else { return }

        // Ensure a ColorWheelNode exists in the graph
        if colorWheelNodeID == nil {
            let nodeID = engine.colorGrading.addColorWheelNode(clipID: clipID, parentNodeID: nil)
            colorWheelNodeID = nodeID
        }

        guard let nodeID = colorWheelNodeID else { return }

        // Map wheel XY offsets to RGB color offsets:
        // X-axis maps to red channel offset, Y-axis maps to blue channel offset,
        // green is derived as the negative sum to maintain balance.
        let params = ParameterValues([
            "liftR": .float(lift.offsetX),
            "liftG": .float(-(lift.offsetX + lift.offsetY) * 0.5),
            "liftB": .float(lift.offsetY),
            "liftMaster": .float(lift.master),
            "gammaR": .float(1.0 + gamma.offsetX),
            "gammaG": .float(1.0 - (gamma.offsetX + gamma.offsetY) * 0.5),
            "gammaB": .float(1.0 + gamma.offsetY),
            "gammaMaster": .float(gamma.master),
            "gainR": .float(1.0 + gain.offsetX),
            "gainG": .float(1.0 - (gain.offsetX + gain.offsetY) * 0.5),
            "gainB": .float(1.0 + gain.offsetY),
            "gainMaster": .float(gain.master),
        ])

        engine.colorGrading.setNodeParameters(clipID: clipID, nodeID: nodeID, parameters: params)
    }

    /// Walk the color grading graph to find a ColorWheelNode.
    private func findColorWheelNode(in graph: ColorGradingGraph) -> ColorWheelNode? {
        guard let root = graph.root else { return nil }
        return findColorWheelNodeRecursive(root)
    }

    private func findColorWheelNodeRecursive(_ node: any ColorNode) -> ColorWheelNode? {
        if let wheelNode = node as? ColorWheelNode { return wheelNode }
        if let serial = node as? SerialNode {
            for child in serial.children {
                if let found = findColorWheelNodeRecursive(child) { return found }
            }
        }
        if let parallel = node as? ParallelNode {
            for layer in parallel.layers {
                if let found = findColorWheelNodeRecursive(layer) { return found }
            }
        }
        return nil
    }
}

/// State for a single color wheel control.
struct WheelState: Equatable {
    var offsetX: CGFloat = 0  // -1 to 1
    var offsetY: CGFloat = 0  // -1 to 1
    var master: CGFloat = 0   // -1 to 1
}

/// Interactive color wheel control with a draggable point and master slider.
struct ColorWheelControl: View {
    let label: String
    @Binding var state: WheelState
    var onChange: () -> Void = {}

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            // Color wheel circle
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let radius = size / 2 - 4

                ZStack {
                    // Wheel background with hue gradient
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                center: .center
                            )
                        )
                        .opacity(0.15)
                        .frame(width: size - 8, height: size - 8)

                    Circle()
                        .stroke(Color.gray.opacity(0.4), lineWidth: 0.5)
                        .frame(width: size - 8, height: size - 8)

                    // Crosshairs
                    Path { p in
                        p.move(to: CGPoint(x: center.x - radius, y: center.y))
                        p.addLine(to: CGPoint(x: center.x + radius, y: center.y))
                    }
                    .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)

                    Path { p in
                        p.move(to: CGPoint(x: center.x, y: center.y - radius))
                        p.addLine(to: CGPoint(x: center.x, y: center.y + radius))
                    }
                    .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)

                    // Control point
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .position(
                            x: center.x + state.offsetX * radius,
                            y: center.y + state.offsetY * radius
                        )
                }
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let dx = (value.location.x - center.x) / radius
                            let dy = (value.location.y - center.y) / radius
                            let dist = sqrt(dx * dx + dy * dy)
                            if dist <= 1 {
                                state.offsetX = dx
                                state.offsetY = dy
                            } else {
                                state.offsetX = dx / dist
                                state.offsetY = dy / dist
                            }
                            onChange()
                        }
                )
            }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label) color wheel")
            .accessibilityHint("Drag to adjust the \(label.lowercased()) color balance")

            // Master slider
            HStack(spacing: 4) {
                Text("M")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Slider(value: $state.master, in: -1...1)
                    .controlSize(.mini)
                    .accessibilityLabel("\(label) master")
                    .accessibilityHint("Adjust the master level for \(label.lowercased())")
                    .onChange(of: state.master) { _, _ in
                        onChange()
                    }
                Text(String(format: "%.2f", state.master))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
            }
        }
    }
}
