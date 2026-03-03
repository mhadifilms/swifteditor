import SwiftUI
import SwiftEditorAPI
import ProjectModel
import CoreMediaPlus

@main
struct SwiftEditorApp: App {
    @State private var engine = SwiftEditorEngine(projectName: "Untitled")
    @State private var panelState = DetachedPanelState()
    @StateObject private var updateManager = UpdateManager()

    var body: some Scene {
        WindowGroup {
            MainWindowView(engine: engine)
                .environment(panelState)
                .frame(minWidth: 1200, minHeight: 700)
        }
        .commands {
            AppMenuCommands(engine: engine)
            CheckForUpdatesCommand(updateManager: updateManager)
        }

        // Detachable panel windows
        Window(DetachablePanelID.inspector.title, id: DetachablePanelID.inspector.rawValue) {
            DetachedInspectorView(engine: engine)
                .onAppear { panelState.isInspectorDetached = true }
                .onDisappear { panelState.isInspectorDetached = false }
        }
        .defaultSize(width: 320, height: 600)

        Window(DetachablePanelID.browser.title, id: DetachablePanelID.browser.rawValue) {
            DetachedBrowserView(engine: engine)
                .onAppear { panelState.isBrowserDetached = true }
                .onDisappear { panelState.isBrowserDetached = false }
        }
        .defaultSize(width: 350, height: 500)

        Window(DetachablePanelID.scopes.title, id: DetachablePanelID.scopes.rawValue) {
            DetachedScopesView(engine: engine)
                .onAppear { panelState.isScopesDetached = true }
                .onDisappear { panelState.isScopesDetached = false }
        }
        .defaultSize(width: 400, height: 350)

        Window(DetachablePanelID.multicamViewer.title, id: DetachablePanelID.multicamViewer.rawValue) {
            MulticamViewerView(engine: engine)
                .onAppear { panelState.isMulticamViewerOpen = true }
                .onDisappear { panelState.isMulticamViewerOpen = false }
        }
        .defaultSize(width: 640, height: 480)

        // Preferences window (Cmd+,)
        Settings {
            SettingsView()
        }

        // Keyboard shortcuts reference sheet
        Window("Keyboard Shortcuts", id: "keyboard-shortcuts-reference") {
            KeyboardShortcutsHelpView()
        }
        .defaultSize(width: 600, height: 500)
    }
}
