import SwiftUI
import Observation

/// Workspace presets following DaVinci Resolve conventions.
public enum WorkspaceType: String, CaseIterable, Identifiable {
    case edit = "Edit"
    case color = "Color"
    case audio = "Audio"
    case effects = "Effects"
    case deliver = "Deliver"

    public var id: String { rawValue }

    var icon: String {
        switch self {
        case .edit: return "film"
        case .color: return "paintpalette"
        case .audio: return "waveform"
        case .effects: return "sparkles"
        case .deliver: return "square.and.arrow.up"
        }
    }

    var shortcutNumber: String {
        switch self {
        case .edit: return "1"
        case .color: return "2"
        case .audio: return "3"
        case .effects: return "4"
        case .deliver: return "5"
        }
    }
}

/// Configuration for what panels are visible in a workspace.
public struct WorkspaceConfiguration {
    var showSidebar: Bool
    var showInspector: Bool
    var showViewer: Bool
    var showTimeline: Bool
    var showScopes: Bool
    var showColorGrading: Bool
    var showAudioMixer: Bool
    var showEffectsBrowser: Bool
    var showDeliverPanel: Bool
    var sidebarTab: SidebarTab

    static func configuration(for workspace: WorkspaceType) -> WorkspaceConfiguration {
        switch workspace {
        case .edit:
            return WorkspaceConfiguration(
                showSidebar: true, showInspector: false, showViewer: true,
                showTimeline: true, showScopes: false, showColorGrading: false,
                showAudioMixer: false, showEffectsBrowser: false, showDeliverPanel: false,
                sidebarTab: .media
            )
        case .color:
            return WorkspaceConfiguration(
                showSidebar: false, showInspector: false, showViewer: true,
                showTimeline: true, showScopes: true, showColorGrading: true,
                showAudioMixer: false, showEffectsBrowser: false, showDeliverPanel: false,
                sidebarTab: .media
            )
        case .audio:
            return WorkspaceConfiguration(
                showSidebar: false, showInspector: false, showViewer: true,
                showTimeline: true, showScopes: false, showColorGrading: false,
                showAudioMixer: true, showEffectsBrowser: false, showDeliverPanel: false,
                sidebarTab: .media
            )
        case .effects:
            return WorkspaceConfiguration(
                showSidebar: true, showInspector: true, showViewer: true,
                showTimeline: true, showScopes: false, showColorGrading: false,
                showAudioMixer: false, showEffectsBrowser: true, showDeliverPanel: false,
                sidebarTab: .effects
            )
        case .deliver:
            return WorkspaceConfiguration(
                showSidebar: false, showInspector: false, showViewer: true,
                showTimeline: false, showScopes: false, showColorGrading: false,
                showAudioMixer: false, showEffectsBrowser: false, showDeliverPanel: true,
                sidebarTab: .media
            )
        }
    }
}

/// Manages the current workspace state.
@Observable
public final class WorkspaceManager {
    public var currentWorkspace: WorkspaceType = .edit
    public var configuration: WorkspaceConfiguration

    public init() {
        self.configuration = WorkspaceConfiguration.configuration(for: .edit)
    }

    public func switchTo(_ workspace: WorkspaceType) {
        currentWorkspace = workspace
        configuration = WorkspaceConfiguration.configuration(for: workspace)
    }
}

/// Sidebar tabs for the browser panel.
enum SidebarTab: String, CaseIterable, Identifiable {
    case media = "Media"
    case effects = "Effects"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .media: return "photo.on.rectangle"
        case .effects: return "sparkles"
        }
    }
}
