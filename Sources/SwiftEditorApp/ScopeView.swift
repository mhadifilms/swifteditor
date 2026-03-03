import SwiftUI
import SwiftEditorAPI
import RenderEngine

/// Displays video scopes (histogram, waveform, RGB parade, vectorscope).
/// Used in the Color workspace.
struct ScopeView: View {
    let engine: SwiftEditorEngine

    @State private var selectedScope: ScopeConfiguration.ScopeType = .waveform
    @State private var showGraticule = true
    @State private var showSkinTone = false

    var body: some View {
        VStack(spacing: 0) {
            // Scope type selector
            HStack(spacing: 0) {
                ForEach(ScopeConfiguration.ScopeType.allCases, id: \.rawValue) { scope in
                    Button {
                        selectedScope = scope
                    } label: {
                        Text(scope.displayName)
                            .font(.system(size: 10))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .background(selectedScope == scope ? Color.accentColor.opacity(0.2) : Color.clear)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(scope.displayName) scope")
                    .accessibilityHint("Display the \(scope.displayName.lowercased()) video scope")
                    .accessibilityAddTraits(selectedScope == scope ? .isSelected : [])
                }
            }
            .background(.bar)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Scope type selector")

            Divider()

            // Scope display area
            ZStack {
                Color(nsColor: NSColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1))

                // Placeholder visualization — in production this wraps a Metal-rendered scope texture
                ScopePlaceholderView(scopeType: selectedScope)
            }
            .aspectRatio(selectedScope == .vectorscope ? 1.0 : 2.0, contentMode: .fit)

            // Scope controls
            HStack(spacing: 12) {
                Toggle("Graticule", isOn: $showGraticule)
                    .toggleStyle(.checkbox)
                    .font(.caption2)
                    .accessibilityLabel("Show graticule")
                    .accessibilityHint("Toggle the graticule overlay on the scope display")

                if selectedScope == .vectorscope {
                    Toggle("Skin Tone", isOn: $showSkinTone)
                        .toggleStyle(.checkbox)
                        .font(.caption2)
                        .accessibilityLabel("Show skin tone line")
                        .accessibilityHint("Toggle the skin tone reference line on the vectorscope")
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.bar)
        }
    }
}

/// Placeholder visualization for scopes before Metal integration.
struct ScopePlaceholderView: View {
    let scopeType: ScopeConfiguration.ScopeType

    var body: some View {
        Canvas { context, size in
            switch scopeType {
            case .histogram:
                drawHistogram(context: context, size: size)
            case .waveform:
                drawWaveform(context: context, size: size)
            case .rgbParade:
                drawRGBParade(context: context, size: size)
            case .vectorscope:
                drawVectorscope(context: context, size: size)
            }
        }
    }

    private func drawHistogram(context: GraphicsContext, size: CGSize) {
        let bins = 64
        for i in 0..<bins {
            let x = CGFloat(i) / CGFloat(bins) * size.width
            let w = size.width / CGFloat(bins)

            // Simulated bell-curve distribution
            let center = Double(bins) / 2.0
            let dist = abs(Double(i) - center) / center
            let heightFrac = exp(-dist * dist * 3) * 0.8 + 0.05

            let rh = heightFrac * (0.7 + sin(Double(i) * 0.3) * 0.3)
            let gh = heightFrac * (0.8 + cos(Double(i) * 0.2) * 0.2)
            let bh = heightFrac * (0.6 + sin(Double(i) * 0.5) * 0.3)

            let rRect = CGRect(x: x, y: size.height * (1 - rh), width: w, height: size.height * rh)
            context.fill(Path(rRect), with: .color(.red.opacity(0.4)))

            let gRect = CGRect(x: x, y: size.height * (1 - gh), width: w, height: size.height * gh)
            context.fill(Path(gRect), with: .color(.green.opacity(0.4)))

            let bRect = CGRect(x: x, y: size.height * (1 - bh), width: w, height: size.height * bh)
            context.fill(Path(bRect), with: .color(.blue.opacity(0.4)))
        }
    }

    private func drawWaveform(context: GraphicsContext, size: CGSize) {
        // Simulated waveform scatter
        for col in stride(from: 0.0, to: size.width, by: 2) {
            let x = col / size.width
            let midY = 0.4 + sin(x * .pi * 4) * 0.15
            let spread = 0.2 + cos(x * .pi * 2) * 0.1

            for _ in 0..<8 {
                let y = midY + (Double.random(in: -spread...spread))
                let point = CGRect(x: col, y: size.height * (1 - y), width: 2, height: 2)
                context.fill(Path(point), with: .color(.green.opacity(0.3)))
            }
        }
    }

    private func drawRGBParade(context: GraphicsContext, size: CGSize) {
        let thirdW = size.width / 3
        let colors: [Color] = [.red, .green, .blue]

        for (index, color) in colors.enumerated() {
            let offsetX = CGFloat(index) * thirdW

            for col in stride(from: 0.0, to: thirdW, by: 2) {
                let x = col / thirdW
                let midY = 0.5 + sin(x * .pi * 3 + Double(index)) * 0.15

                for _ in 0..<6 {
                    let y = midY + Double.random(in: -0.2...0.2)
                    let point = CGRect(x: offsetX + col, y: size.height * (1 - y), width: 2, height: 2)
                    context.fill(Path(point), with: .color(color.opacity(0.4)))
                }
            }

            // Separator lines
            if index > 0 {
                let sepX = CGFloat(index) * thirdW
                let line = Path { p in
                    p.move(to: CGPoint(x: sepX, y: 0))
                    p.addLine(to: CGPoint(x: sepX, y: size.height))
                }
                context.stroke(line, with: .color(.gray.opacity(0.3)), lineWidth: 0.5)
            }
        }
    }

    private func drawVectorscope(context: GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 4

        // Circle outline
        let circle = Path(ellipseIn: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        ))
        context.stroke(circle, with: .color(.gray.opacity(0.3)), lineWidth: 0.5)

        // Crosshairs
        let hLine = Path { p in
            p.move(to: CGPoint(x: center.x - radius, y: center.y))
            p.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        }
        let vLine = Path { p in
            p.move(to: CGPoint(x: center.x, y: center.y - radius))
            p.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        }
        context.stroke(hLine, with: .color(.gray.opacity(0.15)), lineWidth: 0.5)
        context.stroke(vLine, with: .color(.gray.opacity(0.15)), lineWidth: 0.5)

        // Simulated data cluster near center
        for _ in 0..<200 {
            let angle = Double.random(in: 0...(2 * .pi))
            let dist = Double.random(in: 0...0.3) * radius
            let px = center.x + cos(angle) * dist
            let py = center.y + sin(angle) * dist

            let hue = (angle / (2 * .pi))
            let point = CGRect(x: px - 1, y: py - 1, width: 2, height: 2)
            context.fill(Path(point), with: .color(Color(hue: hue, saturation: 0.8, brightness: 0.7).opacity(0.5)))
        }
    }
}

// MARK: - ScopeType Display Name

extension ScopeConfiguration.ScopeType {
    var displayName: String {
        switch self {
        case .histogram: return "Histogram"
        case .waveform: return "Waveform"
        case .rgbParade: return "Parade"
        case .vectorscope: return "Vector"
        }
    }
}
