import SwiftUI
import SwiftEditorAPI
import TimelineKit
import EffectsEngine
import CoreMediaPlus

/// Inspector panel showing properties of the selected clip and its effects.
struct InspectorView: View {
    let engine: SwiftEditorEngine

    @State private var inspectorTab: InspectorTab = .clip

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(InspectorTab.allCases) { tab in
                    Button {
                        inspectorTab = tab
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tab.icon)
                                .font(.caption)
                            Text(tab.rawValue)
                                .font(.system(size: 9))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(inspectorTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(tab.rawValue) inspector")
                    .accessibilityHint("Show \(tab.rawValue.lowercased()) properties for the selected clip")
                    .accessibilityAddTraits(inspectorTab == tab ? .isSelected : [])
                }
            }
            .background(.bar)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Inspector tabs")

            Divider()

            if let clipID = selectedClipID,
               let clip = engine.timeline.clip(by: clipID) {
                switch inspectorTab {
                case .clip:
                    ClipInspector(clip: clip, engine: engine)
                case .effects:
                    EffectsInspector(clipID: clipID, engine: engine)
                case .audio:
                    AudioInspector(clip: clip, engine: engine)
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "square.dashed")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No Selection")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Select a clip to inspect its properties")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var selectedClipID: UUID? {
        engine.timeline.selection.selectedClipIDs.first
    }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case clip = "Clip"
    case effects = "Effects"
    case audio = "Audio"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .clip: return "film"
        case .effects: return "sparkles"
        case .audio: return "waveform"
        }
    }
}

// MARK: - Clip Inspector

struct ClipInspector: View {
    let clip: ClipModel
    let engine: SwiftEditorEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Clip Info") {
                    VStack(alignment: .leading, spacing: 8) {
                        propertyRow("ID", value: clip.id.uuidString.prefix(8) + "...")
                        propertyRow("Asset", value: clip.sourceAssetID.uuidString.prefix(8) + "...")
                        propertyRow("Enabled", value: clip.isEnabled ? "Yes" : "No")
                    }
                }

                GroupBox("Timing") {
                    VStack(alignment: .leading, spacing: 8) {
                        propertyRow("Start", value: formatTime(clip.startTime))
                        propertyRow("Duration", value: formatTime(clip.duration))
                        propertyRow("Source In", value: formatTime(clip.sourceIn))
                        propertyRow("Source Out", value: formatTime(clip.sourceOut))
                        propertyRow("Speed", value: String(format: "%.1fx", clip.speed))
                    }
                }
            }
            .padding(12)
        }
    }

    private func propertyRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }

    private func formatTime(_ time: Rational) -> String {
        let total = time.seconds
        let seconds = Int(total)
        let frames = Int((total - Double(seconds)) * 24)
        return String(format: "%d:%02d:%02d", seconds / 60, seconds % 60, frames)
    }
}

// MARK: - Effects Inspector

struct EffectsInspector: View {
    let clipID: UUID
    let engine: SwiftEditorEngine

    var body: some View {
        let stack = engine.effects.effects(for: clipID)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if stack.effects.isEmpty {
                    VStack(spacing: 8) {
                        Spacer().frame(height: 20)
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No Effects")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Add effects from the Effects browser")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(stack.effects) { effect in
                        EffectCardView(clipID: clipID, effect: effect, engine: engine)
                    }
                }
            }
            .padding(12)
        }
    }
}

struct EffectCardView: View {
    let clipID: UUID
    let effect: EffectInstance
    let engine: SwiftEditorEngine

    @State private var isExpanded = true

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    Button {
                        withAnimation { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "Collapse \(effect.name)" : "Expand \(effect.name)")
                    .accessibilityHint("Show or hide the effect parameters")

                    Text(effect.name)
                        .font(.caption.bold())

                    Spacer()

                    // Enable toggle
                    Toggle("", isOn: Binding(
                        get: { effect.isEnabled },
                        set: { newValue in
                            Task {
                                try? await engine.effects.toggleEffect(clipID: clipID, effectID: effect.id,
                                                                        isEnabled: newValue)
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .scaleEffect(0.65)
                    .labelsHidden()
                    .accessibilityLabel("Enable \(effect.name)")
                    .accessibilityHint("Toggle whether this effect is applied to the clip")

                    // Remove button
                    Button {
                        Task {
                            try? await engine.effects.removeEffect(clipID: clipID, effectID: effect.id)
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(effect.name)")
                    .accessibilityHint("Delete this effect from the clip")
                }

                // Parameters
                if isExpanded {
                    ForEach(Array(effect.parameters.allKeys), id: \.self) { paramName in
                        EffectParameterRow(
                            clipID: clipID,
                            effectID: effect.id,
                            parameterName: paramName,
                            value: effect.parameters[paramName],
                            engine: engine
                        )
                    }
                }
            }
        }
    }
}

struct EffectParameterRow: View {
    let clipID: UUID
    let effectID: UUID
    let parameterName: String
    let value: ParameterValue?
    let engine: SwiftEditorEngine

    var body: some View {
        HStack {
            Text(parameterName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)

            if let value = value {
                switch value {
                case .float(let f):
                    Slider(
                        value: Binding(
                            get: { f },
                            set: { newValue in
                                Task {
                                    try? await engine.effects.setParameter(
                                        clipID: clipID, effectID: effectID,
                                        parameterName: parameterName, value: .float(newValue))
                                }
                            }
                        ),
                        in: -2...2
                    )
                    Text(String(format: "%.2f", f))
                        .font(.caption.monospaced())
                        .frame(width: 40)
                default:
                    Text(String(describing: value))
                        .font(.caption.monospaced())
                }
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Audio Inspector

struct AudioInspector: View {
    let clip: ClipModel
    let engine: SwiftEditorEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Audio") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Volume")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .trailing)
                            Slider(value: .constant(1.0), in: 0...2)
                                .accessibilityLabel("Volume")
                                .accessibilityHint("Adjust the audio volume for this clip")
                            Text("0 dB")
                                .font(.caption.monospaced())
                                .frame(width: 45)
                        }
                        HStack {
                            Text("Pan")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .trailing)
                            Slider(value: .constant(0.0), in: -1...1)
                                .accessibilityLabel("Pan")
                                .accessibilityHint("Adjust the stereo pan position for this clip")
                            Text("C")
                                .font(.caption.monospaced())
                                .frame(width: 45)
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}
