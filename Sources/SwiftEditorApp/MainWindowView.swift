import SwiftUI
import SwiftEditorAPI
import TimelineKit
import CoreMediaPlus
import ViewerKit

/// The primary workspace layout: sidebar | viewer | inspector over timeline.
struct MainWindowView: View {
    let engine: SwiftEditorEngine

    @State private var showMediaBrowser = true
    @State private var showInspector = false
    @State private var selectedTool: EditingTool = .selection

    var body: some View {
        VSplitView {
            // Top region: browser | viewer | inspector
            HSplitView {
                if showMediaBrowser {
                    MediaBrowserView(engine: engine)
                        .frame(minWidth: 200, idealWidth: 280, maxWidth: 400)
                }

                VStack(spacing: 0) {
                    ViewerView(engine: engine)
                        .frame(minWidth: 320)
                    TransportBarView(engine: engine)
                }

                if showInspector {
                    InspectorView(engine: engine)
                        .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)
                }
            }
            .frame(minHeight: 300)

            // Bottom region: toolbar + timeline
            VStack(spacing: 0) {
                ToolbarView(selectedTool: $selectedTool, engine: engine)
                TimelinePanelView(engine: engine, selectedTool: selectedTool)
            }
            .frame(minHeight: 200)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    withAnimation { showMediaBrowser.toggle() }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Media Browser")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    withAnimation { showInspector.toggle() }
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle Inspector")
            }
        }
    }
}

/// Editing tools available in the toolbar.
enum EditingTool: String, CaseIterable, Identifiable {
    case selection = "Selection"
    case trim = "Trim"
    case blade = "Blade"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .selection: return "arrow.up.left.and.arrow.down.right"
        case .trim: return "scissors"
        case .blade: return "line.diagonal"
        }
    }

    var shortcut: String {
        switch self {
        case .selection: return "A"
        case .trim: return "T"
        case .blade: return "B"
        }
    }
}
