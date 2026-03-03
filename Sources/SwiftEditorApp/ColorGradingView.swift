import SwiftUI
import SwiftEditorAPI
import EffectsEngine

/// Color grading panel with lift/gamma/gain color wheels.
/// Shown in the Color workspace below the viewer.
struct ColorGradingView: View {
    let engine: SwiftEditorEngine

    @State private var lift = WheelState()
    @State private var gamma = WheelState()
    @State private var gain = WheelState()

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
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Reset color wheels")
                .accessibilityHint("Reset lift, gamma, and gain color wheels to their default values")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            HStack(spacing: 16) {
                ColorWheelControl(label: "Lift", state: $lift)
                ColorWheelControl(label: "Gamma", state: $gamma)
                ColorWheelControl(label: "Gain", state: $gain)
            }
            .padding(12)
        }
    }
}

/// State for a single color wheel control.
struct WheelState {
    var offsetX: CGFloat = 0  // -1 to 1
    var offsetY: CGFloat = 0  // -1 to 1
    var master: CGFloat = 0   // -1 to 1
}

/// Interactive color wheel control with a draggable point and master slider.
struct ColorWheelControl: View {
    let label: String
    @Binding var state: WheelState

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
                Text(String(format: "%.2f", state.master))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
            }
        }
    }
}
