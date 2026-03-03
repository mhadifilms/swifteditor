import SwiftUI
import SwiftEditorAPI
import CoreMediaPlus

/// Toolbar above the timeline with editing tool buttons and zoom controls.
struct ToolbarView: View {
    @Binding var selectedTool: EditingTool
    let engine: SwiftEditorEngine

    @State private var pixelsPerSecond: CGFloat = 40

    var body: some View {
        HStack(spacing: 12) {
            // Editing tools
            HStack(spacing: 2) {
                ForEach(EditingTool.allCases) { tool in
                    Button {
                        selectedTool = tool
                    } label: {
                        Image(systemName: tool.systemImage)
                            .frame(width: 28, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(selectedTool == tool
                                  ? Color.accentColor.opacity(0.2)
                                  : Color.clear)
                    )
                    .help("\(tool.rawValue) (\(tool.shortcut))")
                    .accessibilityLabel("\(tool.rawValue) tool")
                    .accessibilityHint("Activate the \(tool.rawValue.lowercased()) editing tool. Shortcut: \(tool.shortcut)")
                    .accessibilityAddTraits(selectedTool == tool ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Editing tools")

            Divider()
                .frame(height: 18)

            // Snapping toggle
            Button {
                // Toggle snapping
            } label: {
                Image(systemName: "magnet")
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Toggle Snapping (N)")
            .accessibilityLabel("Toggle Snapping")
            .accessibilityHint("Enable or disable timeline snapping. Shortcut: N")

            Spacer()

            // Track actions
            Menu {
                Button("Add Video Track") {
                    engine.timeline.requestTrackInsert(at: engine.timeline.videoTracks.count, type: .video)
                }
                Button("Add Audio Track") {
                    engine.timeline.requestTrackInsert(at: engine.timeline.audioTracks.count, type: .audio)
                }
            } label: {
                Image(systemName: "plus.rectangle.on.rectangle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .help("Add Track")
            .accessibilityLabel("Add Track")
            .accessibilityHint("Open menu to add a new video or audio track")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }
}
