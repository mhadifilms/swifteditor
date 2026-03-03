import SwiftUI
import SwiftEditorAPI
import TimelineKit
import CoreMediaPlus

// MARK: - Panel Identifiers

/// Identifiers for detachable panels used in Window scenes.
enum DetachablePanelID: String, CaseIterable {
    case inspector = "detached-inspector"
    case browser = "detached-browser"
    case scopes = "detached-scopes"
    case multicamViewer = "detached-multicam"

    var title: String {
        switch self {
        case .inspector: return "Inspector"
        case .browser: return "Media Browser"
        case .scopes: return "Video Scopes"
        case .multicamViewer: return "Multicam Viewer"
        }
    }
}

// MARK: - Detached Panel State

/// Tracks which panels are currently detached from the main window.
@Observable
final class DetachedPanelState {
    var isInspectorDetached = false
    var isBrowserDetached = false
    var isScopesDetached = false
    var isMulticamViewerOpen = false
}

// MARK: - Detached Inspector Window

struct DetachedInspectorView: View {
    let engine: SwiftEditorEngine
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Inspector")
                    .font(.headline)
                Spacer()
                Button("Re-dock") {
                    dismissWindow(id: DetachablePanelID.inspector.rawValue)
                }
                .buttonStyle(.borderless)
                .help("Return inspector to main window")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .liquidGlassSidebarHeader()

            Divider()

            InspectorView(engine: engine)
        }
        .frame(minWidth: 280, idealWidth: 320, minHeight: 400)
    }
}

// MARK: - Detached Browser Window

struct DetachedBrowserView: View {
    let engine: SwiftEditorEngine
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Media Browser")
                    .font(.headline)
                Spacer()
                Button("Re-dock") {
                    dismissWindow(id: DetachablePanelID.browser.rawValue)
                }
                .buttonStyle(.borderless)
                .help("Return browser to main window")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .liquidGlassSidebarHeader()

            Divider()

            MediaBrowserView(engine: engine)
        }
        .frame(minWidth: 280, idealWidth: 350, minHeight: 400)
    }
}

// MARK: - Detached Scopes Window

struct DetachedScopesView: View {
    let engine: SwiftEditorEngine
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Video Scopes")
                    .font(.headline)
                Spacer()
                Button("Re-dock") {
                    dismissWindow(id: DetachablePanelID.scopes.rawValue)
                }
                .buttonStyle(.borderless)
                .help("Return scopes to main window")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .liquidGlassSidebarHeader()

            Divider()

            ScopeView(engine: engine)
        }
        .frame(minWidth: 300, idealWidth: 400, minHeight: 300)
    }
}

// MARK: - Multicam Viewer Window

/// Grid viewer showing all multicam angles; click to switch the active angle.
struct MulticamViewerView: View {
    let engine: SwiftEditorEngine
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Multicam Viewer")
                    .font(.headline)
                Spacer()
                Button {
                    dismissWindow(id: DetachablePanelID.multicamViewer.rawValue)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Close multicam viewer")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .liquidGlassBar()

            Divider()

            if let multicamClipID = selectedMulticamClipID,
               let multicam = engine.multicam.multicamModel(for: multicamClipID) {
                multicamGrid(multicam: multicam, clipID: multicamClipID)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "rectangle.split.2x2")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No Multicam Clip Selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Select a multicam clip on the timeline")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 500, idealWidth: 640, minHeight: 400)
    }

    private var selectedMulticamClipID: UUID? {
        for clipID in engine.timeline.selection.selectedClipIDs {
            if engine.multicam.isMulticamClip(clipID) {
                return clipID
            }
        }
        return nil
    }

    @ViewBuilder
    private func multicamGrid(multicam: MulticamClipModel, clipID: UUID) -> some View {
        let columns = multicam.angles.count <= 4
            ? Array(repeating: GridItem(.flexible(), spacing: 2), count: 2)
            : Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(multicam.angles.enumerated()), id: \.element.id) { index, angle in
                    AngleTileView(
                        angle: angle,
                        index: index,
                        isActive: multicam.angleIndex(at: engine.transport.currentTime) == index,
                        onSelect: {
                            engine.timeline.requestSwitchAngle(
                                clipID: clipID,
                                angleIndex: index,
                                at: engine.transport.currentTime
                            )
                        }
                    )
                }
            }
            .padding(4)
        }
    }
}

struct AngleTileView: View {
    let angle: MulticamAngle
    let index: Int
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                // Placeholder for video preview
                Rectangle()
                    .fill(Color(hue: Double(index) * 0.15, saturation: 0.3, brightness: 0.3))
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay {
                        Image(systemName: "video")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .overlay(alignment: .topLeading) {
                        Text("Angle \(index + 1)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(4)
                    }

                Text(angle.name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Angle \(index + 1): \(angle.name)\(isActive ? ", active" : "")")
        .accessibilityHint("Click to switch to this camera angle")
    }
}
