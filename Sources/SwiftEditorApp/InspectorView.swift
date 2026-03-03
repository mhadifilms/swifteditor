import SwiftUI
import SwiftEditorAPI
import TimelineKit
import CoreMediaPlus

/// Inspector panel showing properties of the selected clip.
struct InspectorView: View {
    let engine: SwiftEditorEngine

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Inspector")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if let clipID = selectedClipID,
               let clip = engine.timeline.clip(by: clipID) {
                ClipInspector(clip: clip, engine: engine)
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

/// Detailed properties for a selected clip.
struct ClipInspector: View {
    let clip: ClipModel
    let engine: SwiftEditorEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Identity
                GroupBox("Clip Info") {
                    VStack(alignment: .leading, spacing: 8) {
                        propertyRow("ID", value: clip.id.uuidString.prefix(8) + "...")
                        propertyRow("Asset", value: clip.sourceAssetID.uuidString.prefix(8) + "...")
                        propertyRow("Enabled", value: clip.isEnabled ? "Yes" : "No")
                    }
                }

                // Timing
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
