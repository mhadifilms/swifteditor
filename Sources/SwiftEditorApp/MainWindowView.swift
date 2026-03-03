import SwiftUI
import AppKit
import SwiftEditorAPI
import TimelineKit
import CoreMediaPlus
import ViewerKit

// MARK: - Keyboard Event Handler

/// Routes low-level NSEvent key-down events through KeyboardShortcutManager
/// to dispatch editor actions. This captures bare-key shortcuts (A/T/B, J/K/L,
/// Space, arrow keys) that SwiftUI menu shortcuts may not reliably intercept.
@MainActor
final class KeyboardEventHandler {
    private var monitor: Any?
    private weak var engine: SwiftEditorEngine?
    private var toolBinding: ((EditingTool) -> Void)?
    private var workspaceBinding: ((WorkspaceType) -> Void)?

    func install(engine: SwiftEditorEngine,
                 onToolChange: @escaping (EditingTool) -> Void,
                 onWorkspaceChange: @escaping (WorkspaceType) -> Void) {
        self.engine = engine
        self.toolBinding = onToolChange
        self.workspaceBinding = onWorkspaceChange

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let engine = self.engine else { return event }
            // Don't intercept when a text field has focus
            if let responder = event.window?.firstResponder,
               responder is NSTextView || responder is NSTextField {
                return event
            }
            let handled = self.handleKeyEvent(event, engine: engine)
            return handled ? nil : event
        }
    }

    func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handleKeyEvent(_ event: NSEvent, engine: SwiftEditorEngine) -> Bool {
        let shortcuts = KeyboardShortcutManager.shared
        let modifiers = keyModifiers(from: event)
        let key = normalizedKey(from: event)

        // Look up which action matches this key + modifiers
        guard let action = shortcuts.shortcuts.first(where: { _, combo in
            combo.key == key && combo.modifiers == modifiers
        })?.key else {
            return false
        }

        return dispatchAction(action, engine: engine)
    }

    private func dispatchAction(_ action: ActionID, engine: SwiftEditorEngine) -> Bool {
        switch action {
        // Tools
        case .selectionTool:
            toolBinding?(.selection)
        case .trimTool:
            toolBinding?(.trim)
        case .bladeTool:
            toolBinding?(.blade)

        // Playback
        case .playPause:
            if engine.transport.isPlaying {
                engine.transport.pause()
            } else {
                engine.transport.play()
            }
        case .stop:
            engine.transport.stop()
        case .stepForward:
            engine.transport.stepForward()
        case .stepBackward:
            engine.transport.stepBackward()
        case .goToStart:
            Task { await engine.transport.seek(to: .zero) }
        case .goToEnd:
            Task { await engine.transport.seek(to: engine.timeline.duration) }

        // JKL shuttle
        case .shuttleReverse:
            engine.viewer.pressJ()
        case .shuttleStop:
            engine.viewer.pressK()
        case .shuttleForward:
            engine.viewer.pressL()

        // Workspace
        case .workspaceEdit:
            workspaceBinding?(.edit)
        case .workspaceColor:
            workspaceBinding?(.color)
        case .workspaceAudio:
            workspaceBinding?(.audio)
        case .workspaceEffects:
            workspaceBinding?(.effects)
        case .workspaceDeliver:
            workspaceBinding?(.deliver)

        // Mark
        case .setInPoint:
            engine.viewer.setInPoint(engine.transport.currentTime)
        case .setOutPoint:
            engine.viewer.setOutPoint(engine.transport.currentTime)
        case .clearInPoint:
            engine.viewer.clearInPoint()
        case .clearOutPoint:
            engine.viewer.clearOutPoint()
        case .addMarker:
            engine.timeline.requestAddMarker(name: "", at: engine.transport.currentTime)
        case .nextMarker:
            if let next = engine.timeline.markerManager.nextMarker(after: engine.transport.currentTime) {
                Task { await engine.transport.seek(to: next.time) }
            }
        case .previousMarker:
            if let prev = engine.timeline.markerManager.previousMarker(before: engine.transport.currentTime) {
                Task { await engine.transport.seek(to: prev.time) }
            }

        // Clip operations
        case .blade:
            let time = engine.transport.currentTime
            for track in engine.timeline.videoTracks {
                if let clip = engine.timeline.clipAt(time: time, trackID: track.id) {
                    engine.timeline.requestClipSplit(clipID: clip.id, at: time)
                    break
                }
            }
        case .bladeAll:
            engine.timeline.requestBladeAll(at: engine.transport.currentTime)
        case .toggleClipEnabled:
            for id in engine.timeline.selection.selectedClipIDs {
                if let clip = engine.timeline.clip(by: id) {
                    clip.isEnabled.toggle()
                }
            }

        // Edit operations
        case .delete:
            for id in engine.timeline.selection.selectedClipIDs {
                engine.timeline.requestClipDelete(clipID: id)
            }
            engine.timeline.selection = .empty
        case .rippleDelete:
            for id in engine.timeline.selection.selectedClipIDs {
                engine.timeline.requestRippleDelete(clipID: id)
            }
            engine.timeline.selection = .empty
        case .undo:
            Task { try? await engine.editing.undo() }
        case .redo:
            Task { try? await engine.editing.redo() }
        case .selectAll:
            var allIDs = Set<UUID>()
            for track in engine.timeline.videoTracks {
                for clip in engine.timeline.clipsOnTrack(track.id) {
                    allIDs.insert(clip.id)
                }
            }
            for track in engine.timeline.audioTracks {
                for clip in engine.timeline.clipsOnTrack(track.id) {
                    allIDs.insert(clip.id)
                }
            }
            engine.timeline.selection = SelectionState(selectedClipIDs: allIDs)
        case .deselectAll:
            engine.timeline.selection = .empty

        // Toggle UI panels
        case .toggleSnapping:
            engine.snap.setEnabled(!engine.snap.isEnabled)
        case .toggleSidebar, .toggleInspector:
            // Handled by toolbar buttons; allow event to propagate
            return false

        default:
            return false
        }
        return true
    }

    // MARK: - Key Normalization

    private func normalizedKey(from event: NSEvent) -> String {
        // Handle special keys by keyCode
        switch event.keyCode {
        case 49: return "space"
        case 51: return "delete"
        case 53: return "escape"
        case 123: return "left"
        case 124: return "right"
        case 125: return "down"
        case 126: return "up"
        case 115: return "home"
        case 119: return "end"
        default:
            return event.charactersIgnoringModifiers?.lowercased() ?? ""
        }
    }

    private func keyModifiers(from event: NSEvent) -> KeyCombo.KeyModifiers {
        var mods: KeyCombo.KeyModifiers = []
        if event.modifierFlags.contains(.command) { mods.insert(.command) }
        if event.modifierFlags.contains(.shift) { mods.insert(.shift) }
        if event.modifierFlags.contains(.option) { mods.insert(.option) }
        if event.modifierFlags.contains(.control) { mods.insert(.control) }
        return mods
    }
}

/// The primary workspace layout driven by WorkspaceManager.
/// Adapts panel visibility based on the active workspace (Edit, Color, Audio, Effects, Deliver).
struct MainWindowView: View {
    let engine: SwiftEditorEngine

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @Environment(DetachedPanelState.self) private var panelState: DetachedPanelState?
    @State private var workspace = WorkspaceManager()
    @State private var selectedTool: EditingTool = .selection
    @State private var sidebarTab: SidebarTab = .media
    @State private var keyboardHandler = KeyboardEventHandler()

    var body: some View {
        VStack(spacing: 0) {
            // Workspace tab bar
            WorkspaceTabBar(workspace: workspace)

            // Main content
            workspaceContent
        }
        .onAppear {
            keyboardHandler.install(
                engine: engine,
                onToolChange: { tool in selectedTool = tool },
                onWorkspaceChange: { type in
                    if reduceMotion {
                        workspace.switchTo(type)
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            workspace.switchTo(type)
                        }
                    }
                }
            )
        }
        .onDisappear {
            keyboardHandler.uninstall()
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
                // Detach panel buttons
                Menu {
                    Button("Detach Inspector") {
                        openWindow(id: DetachablePanelID.inspector.rawValue)
                    }
                    Button("Detach Browser") {
                        openWindow(id: DetachablePanelID.browser.rawValue)
                    }
                    Button("Detach Scopes") {
                        openWindow(id: DetachablePanelID.scopes.rawValue)
                    }
                    Divider()
                    Button("Multicam Viewer") {
                        openWindow(id: DetachablePanelID.multicamViewer.rawValue)
                    }
                } label: {
                    Image(systemName: "uiwindow.split.2x1")
                }
                .help("Detach Panels")
                .accessibilityLabel("Detach Panels")
                .accessibilityHint("Open panels in separate windows")

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

                // Viewer + Node Editor stacked vertically
                VSplitView {
                    viewerRegion
                    NodeEditorView(engine: engine)
                        .frame(minHeight: 200)
                }

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
    @Namespace private var tabNamespace

    var body: some View {
        LiquidGlassContainer(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(WorkspaceType.allCases) { type in
                    Button {
                        if reduceMotion {
                            workspace.switchTo(type)
                        } else {
                            withAnimation(.bouncy) {
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
                    .liquidGlassButton()
                    .modifier(GlassEffectIDModifier(id: type.rawValue, namespace: tabNamespace))
                    .help("\(type.rawValue) (Shift+\(type.shortcutNumber))")
                    .accessibilityLabel("\(type.rawValue) workspace")
                    .accessibilityHint("Switch to the \(type.rawValue) workspace. Shortcut: Shift+\(type.shortcutNumber)")
                    .accessibilityAddTraits(workspace.currentWorkspace == type ? .isSelected : [])
                }
            }
        }
        .liquidGlassTabBar()
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
