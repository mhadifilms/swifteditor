import SwiftUI
import SwiftEditorAPI
import TimelineKit
import CoreMediaPlus
import ViewerKit

/// The primary workspace layout driven by WorkspaceManager.
/// Adapts panel visibility based on the active workspace (Edit, Color, Audio, Effects, Deliver).
struct MainWindowView: View {
    let engine: SwiftEditorEngine

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var workspace = WorkspaceManager()
    @State private var selectedTool: EditingTool = .selection
    @State private var sidebarTab: SidebarTab = .media

    var body: some View {
        VStack(spacing: 0) {
            // Workspace tab bar
            WorkspaceTabBar(workspace: workspace)

            // Main content
            workspaceContent
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    if reduceMotion {
                        workspace.configuration.showSidebar.toggle()
                    } else {
                        withAnimation { workspace.configuration.showSidebar.toggle() }
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Sidebar")
                .accessibilityLabel("Toggle Sidebar")
                .accessibilityHint("Shows or hides the media and effects browser panel")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    if reduceMotion {
                        workspace.configuration.showInspector.toggle()
                    } else {
                        withAnimation { workspace.configuration.showInspector.toggle() }
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle Inspector")
                .accessibilityLabel("Toggle Inspector")
                .accessibilityHint("Shows or hides the clip properties inspector")
            }
        }
        .onChange(of: workspace.currentWorkspace) { _, newValue in
            sidebarTab = workspace.configuration.sidebarTab
        }
        .focusedSceneValue(\.workspaceManager, workspace)
    }

    // MARK: - Workspace Content

    @ViewBuilder
    private var workspaceContent: some View {
        switch workspace.currentWorkspace {
        case .edit:
            editWorkspace
        case .color:
            colorWorkspace
        case .audio:
            audioWorkspace
        case .effects:
            effectsWorkspace
        case .deliver:
            deliverWorkspace
        }
    }

    // MARK: - Edit Workspace

    private var editWorkspace: some View {
        VSplitView {
            HSplitView {
                if workspace.configuration.showSidebar {
                    sidebarPanel
                }

                viewerRegion

                if workspace.configuration.showInspector {
                    InspectorView(engine: engine)
                        .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)
                }
            }
            .frame(minHeight: 300)

            timelineRegion
        }
    }

    // MARK: - Color Workspace

    private var colorWorkspace: some View {
        VSplitView {
            HSplitView {
                // Viewer
                VStack(spacing: 0) {
                    ViewerView(engine: engine)
                        .frame(minWidth: 320)
                    TransportBarView(engine: engine)
                }

                // Scopes
                if workspace.configuration.showScopes {
                    ScopeView(engine: engine)
                        .frame(minWidth: 200, idealWidth: 300, maxWidth: 500)
                }
            }
            .frame(minHeight: 250)

            // Color grading wheels
            if workspace.configuration.showColorGrading {
                ColorGradingView(engine: engine)
                    .frame(minHeight: 150, idealHeight: 200, maxHeight: 300)
            }

            timelineRegion
        }
    }

    // MARK: - Audio Workspace

    private var audioWorkspace: some View {
        VSplitView {
            HSplitView {
                viewerRegion

                if workspace.configuration.showAudioMixer {
                    AudioMixerView(engine: engine)
                        .frame(minWidth: 300, idealWidth: 450, maxWidth: 700)
                }
            }
            .frame(minHeight: 250)

            timelineRegion
        }
    }

    // MARK: - Effects Workspace

    private var effectsWorkspace: some View {
        VSplitView {
            HSplitView {
                if workspace.configuration.showSidebar {
                    VStack(spacing: 0) {
                        Picker("", selection: $sidebarTab) {
                            ForEach(SidebarTab.allCases) { tab in
                                Image(systemName: tab.icon)
                                    .help(tab.rawValue)
                                    .tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(6)

                        switch sidebarTab {
                        case .media:
                            MediaBrowserView(engine: engine)
                        case .effects:
                            EffectsBrowserView(engine: engine)
                        }
                    }
                    .frame(minWidth: 200, idealWidth: 280, maxWidth: 400)
                }

                viewerRegion

                if workspace.configuration.showInspector {
                    InspectorView(engine: engine)
                        .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)
                }
            }
            .frame(minHeight: 300)

            timelineRegion
        }
    }

    // MARK: - Deliver Workspace

    private var deliverWorkspace: some View {
        HSplitView {
            VStack(spacing: 0) {
                ViewerView(engine: engine)
                    .frame(minWidth: 320)
                TransportBarView(engine: engine)
            }

            DeliverView(engine: engine)
                .frame(minWidth: 300, idealWidth: 400, maxWidth: 600)
        }
    }

    // MARK: - Shared Components

    private var sidebarPanel: some View {
        VStack(spacing: 0) {
            Picker("", selection: $sidebarTab) {
                ForEach(SidebarTab.allCases) { tab in
                    Image(systemName: tab.icon)
                        .help(tab.rawValue)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(6)

            switch sidebarTab {
            case .media:
                MediaBrowserView(engine: engine)
            case .effects:
                EffectsBrowserView(engine: engine)
            }
        }
        .frame(minWidth: 200, idealWidth: 280, maxWidth: 400)
    }

    private var viewerRegion: some View {
        VStack(spacing: 0) {
            ViewerView(engine: engine)
                .frame(minWidth: 320)
            TransportBarView(engine: engine)
        }
    }

    private var timelineRegion: some View {
        VStack(spacing: 0) {
            ToolbarView(selectedTool: $selectedTool, engine: engine)
            TimelinePanelView(engine: engine, selectedTool: selectedTool)
        }
        .frame(minHeight: 200)
    }
}

// MARK: - Workspace Tab Bar

/// Horizontal tab bar for switching between workspaces (Shift+1 through Shift+5).
struct WorkspaceTabBar: View {
    @Bindable var workspace: WorkspaceManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(WorkspaceType.allCases) { type in
                Button {
                    if reduceMotion {
                        workspace.switchTo(type)
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            workspace.switchTo(type)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: type.icon)
                            .font(.system(size: 10))
                        Text(type.rawValue)
                            .font(.system(size: 11, weight: workspace.currentWorkspace == type ? .semibold : .regular))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(
                        workspace.currentWorkspace == type
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
                }
                .buttonStyle(.plain)
                .help("\(type.rawValue) (Shift+\(type.shortcutNumber))")
                .accessibilityLabel("\(type.rawValue) workspace")
                .accessibilityHint("Switch to the \(type.rawValue) workspace. Shortcut: Shift+\(type.shortcutNumber)")
                .accessibilityAddTraits(workspace.currentWorkspace == type ? .isSelected : [])
            }
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace tabs")
    }
}

// MARK: - Editing Tools

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

// MARK: - Focus Values

/// Allows AppMenuCommands to access the workspace manager.
struct WorkspaceManagerKey: FocusedValueKey {
    typealias Value = WorkspaceManager
}

extension FocusedValues {
    var workspaceManager: WorkspaceManager? {
        get { self[WorkspaceManagerKey.self] }
        set { self[WorkspaceManagerKey.self] = newValue }
    }
}
