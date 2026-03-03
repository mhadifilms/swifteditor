import SwiftUI
import Observation

// MARK: - Action IDs

/// All editor actions that can be bound to keyboard shortcuts.
enum ActionID: String, CaseIterable, Identifiable, Sendable {
    // File
    case newProject = "file.new"
    case openProject = "file.open"
    case save = "file.save"
    case saveAs = "file.saveAs"
    case importMedia = "file.import"

    // Edit
    case undo = "edit.undo"
    case redo = "edit.redo"
    case selectAll = "edit.selectAll"
    case deselectAll = "edit.deselectAll"
    case delete = "edit.delete"
    case rippleDelete = "edit.rippleDelete"

    // Playback
    case playPause = "playback.playPause"
    case stop = "playback.stop"
    case stepForward = "playback.stepForward"
    case stepBackward = "playback.stepBackward"
    case goToStart = "playback.goToStart"
    case goToEnd = "playback.goToEnd"
    case shuttleReverse = "playback.shuttleReverse"
    case shuttleStop = "playback.shuttleStop"
    case shuttleForward = "playback.shuttleForward"

    // Tools
    case selectionTool = "tool.selection"
    case trimTool = "tool.trim"
    case bladeTool = "tool.blade"

    // Mark
    case setInPoint = "mark.setIn"
    case setOutPoint = "mark.setOut"
    case clearInPoint = "mark.clearIn"
    case clearOutPoint = "mark.clearOut"
    case addMarker = "mark.addMarker"
    case nextMarker = "mark.nextMarker"
    case previousMarker = "mark.previousMarker"

    // Clip
    case blade = "clip.blade"
    case bladeAll = "clip.bladeAll"
    case toggleClipEnabled = "clip.toggleEnabled"

    // Timeline
    case addVideoTrack = "timeline.addVideoTrack"
    case addAudioTrack = "timeline.addAudioTrack"
    case toggleSnapping = "timeline.toggleSnapping"

    // Workspace
    case workspaceEdit = "workspace.edit"
    case workspaceColor = "workspace.color"
    case workspaceAudio = "workspace.audio"
    case workspaceEffects = "workspace.effects"
    case workspaceDeliver = "workspace.deliver"

    // View
    case toggleSidebar = "view.toggleSidebar"
    case toggleInspector = "view.toggleInspector"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newProject: return "New Project"
        case .openProject: return "Open Project"
        case .save: return "Save"
        case .saveAs: return "Save As"
        case .importMedia: return "Import Media"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .selectAll: return "Select All"
        case .deselectAll: return "Deselect All"
        case .delete: return "Delete (Lift)"
        case .rippleDelete: return "Ripple Delete"
        case .playPause: return "Play/Pause"
        case .stop: return "Stop"
        case .stepForward: return "Step Forward"
        case .stepBackward: return "Step Backward"
        case .goToStart: return "Go to Start"
        case .goToEnd: return "Go to End"
        case .shuttleReverse: return "Shuttle Reverse (J)"
        case .shuttleStop: return "Shuttle Stop (K)"
        case .shuttleForward: return "Shuttle Forward (L)"
        case .selectionTool: return "Selection Tool"
        case .trimTool: return "Trim Tool"
        case .bladeTool: return "Blade Tool"
        case .setInPoint: return "Set In Point"
        case .setOutPoint: return "Set Out Point"
        case .clearInPoint: return "Clear In Point"
        case .clearOutPoint: return "Clear Out Point"
        case .addMarker: return "Add Marker"
        case .nextMarker: return "Next Marker"
        case .previousMarker: return "Previous Marker"
        case .blade: return "Blade"
        case .bladeAll: return "Blade All"
        case .toggleClipEnabled: return "Toggle Clip Enabled"
        case .addVideoTrack: return "Add Video Track"
        case .addAudioTrack: return "Add Audio Track"
        case .toggleSnapping: return "Toggle Snapping"
        case .workspaceEdit: return "Edit Workspace"
        case .workspaceColor: return "Color Workspace"
        case .workspaceAudio: return "Audio Workspace"
        case .workspaceEffects: return "Effects Workspace"
        case .workspaceDeliver: return "Deliver Workspace"
        case .toggleSidebar: return "Toggle Sidebar"
        case .toggleInspector: return "Toggle Inspector"
        }
    }

    var category: String {
        let prefix = rawValue.split(separator: ".").first ?? ""
        switch prefix {
        case "file": return "File"
        case "edit": return "Edit"
        case "playback": return "Playback"
        case "tool": return "Tools"
        case "mark": return "Mark"
        case "clip": return "Clip"
        case "timeline": return "Timeline"
        case "workspace": return "Workspace"
        case "view": return "View"
        default: return "General"
        }
    }
}

// MARK: - Key Combo

/// A serializable key combination (key + modifiers).
struct KeyCombo: Codable, Equatable, Sendable {
    let key: String
    let modifiers: KeyModifiers

    struct KeyModifiers: OptionSet, Codable, Sendable {
        let rawValue: Int

        static let command  = KeyModifiers(rawValue: 1 << 0)
        static let shift    = KeyModifiers(rawValue: 1 << 1)
        static let option   = KeyModifiers(rawValue: 1 << 2)
        static let control  = KeyModifiers(rawValue: 1 << 3)

        static let none     = KeyModifiers([])
    }

    /// Human-readable representation for display (e.g. "Cmd+Shift+B").
    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.option) { parts.append("Opt") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Cmd") }
        parts.append(key.uppercased())
        return parts.joined(separator: "+")
    }

    /// Convert to SwiftUI EventModifiers.
    var eventModifiers: SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        return result
    }
}

// MARK: - NLE Preset

/// Preset keyboard shortcut layouts matching popular NLE applications.
enum NLEPreset: String, CaseIterable, Identifiable, Sendable {
    case davinciResolve = "DaVinci Resolve"
    case premierePro = "Premiere Pro"
    case finalCutPro = "Final Cut Pro"

    var id: String { rawValue }

    var shortcuts: [ActionID: KeyCombo] {
        switch self {
        case .davinciResolve:
            return Self.davinciResolveShortcuts
        case .premierePro:
            return Self.premiereProShortcuts
        case .finalCutPro:
            return Self.finalCutProShortcuts
        }
    }

    // MARK: DaVinci Resolve defaults

    private static let davinciResolveShortcuts: [ActionID: KeyCombo] = [
        .newProject:        KeyCombo(key: "n", modifiers: .command),
        .openProject:       KeyCombo(key: "o", modifiers: .command),
        .save:              KeyCombo(key: "s", modifiers: .command),
        .saveAs:            KeyCombo(key: "s", modifiers: [.command, .shift]),
        .importMedia:       KeyCombo(key: "i", modifiers: .command),
        .undo:              KeyCombo(key: "z", modifiers: .command),
        .redo:              KeyCombo(key: "z", modifiers: [.command, .shift]),
        .selectAll:         KeyCombo(key: "a", modifiers: .command),
        .deselectAll:       KeyCombo(key: "a", modifiers: [.command, .shift]),
        .delete:            KeyCombo(key: "delete", modifiers: .none),
        .rippleDelete:      KeyCombo(key: "delete", modifiers: .shift),
        .playPause:         KeyCombo(key: "space", modifiers: .none),
        .stop:              KeyCombo(key: "escape", modifiers: .none),
        .stepForward:       KeyCombo(key: "right", modifiers: .none),
        .stepBackward:      KeyCombo(key: "left", modifiers: .none),
        .goToStart:         KeyCombo(key: "home", modifiers: .none),
        .goToEnd:           KeyCombo(key: "end", modifiers: .none),
        .shuttleReverse:    KeyCombo(key: "j", modifiers: .none),
        .shuttleStop:       KeyCombo(key: "k", modifiers: .none),
        .shuttleForward:    KeyCombo(key: "l", modifiers: .none),
        .selectionTool:     KeyCombo(key: "a", modifiers: .none),
        .trimTool:          KeyCombo(key: "t", modifiers: .none),
        .bladeTool:         KeyCombo(key: "b", modifiers: .none),
        .setInPoint:        KeyCombo(key: "i", modifiers: .none),
        .setOutPoint:       KeyCombo(key: "o", modifiers: .none),
        .clearInPoint:      KeyCombo(key: "i", modifiers: .option),
        .clearOutPoint:     KeyCombo(key: "o", modifiers: .option),
        .addMarker:         KeyCombo(key: "m", modifiers: .none),
        .nextMarker:        KeyCombo(key: "down", modifiers: .shift),
        .previousMarker:    KeyCombo(key: "up", modifiers: .shift),
        .blade:             KeyCombo(key: "b", modifiers: .command),
        .bladeAll:          KeyCombo(key: "b", modifiers: [.command, .shift]),
        .toggleClipEnabled: KeyCombo(key: "v", modifiers: .none),
        .toggleSnapping:    KeyCombo(key: "n", modifiers: .none),
        .workspaceEdit:     KeyCombo(key: "1", modifiers: .shift),
        .workspaceColor:    KeyCombo(key: "2", modifiers: .shift),
        .workspaceAudio:    KeyCombo(key: "3", modifiers: .shift),
        .workspaceEffects:  KeyCombo(key: "4", modifiers: .shift),
        .workspaceDeliver:  KeyCombo(key: "5", modifiers: .shift),
        .toggleSidebar:     KeyCombo(key: "s", modifiers: [.command, .option]),
        .toggleInspector:   KeyCombo(key: "i", modifiers: [.command, .option]),
    ]

    // MARK: Premiere Pro defaults

    private static let premiereProShortcuts: [ActionID: KeyCombo] = [
        .newProject:        KeyCombo(key: "n", modifiers: .command),
        .openProject:       KeyCombo(key: "o", modifiers: .command),
        .save:              KeyCombo(key: "s", modifiers: .command),
        .saveAs:            KeyCombo(key: "s", modifiers: [.command, .shift]),
        .importMedia:       KeyCombo(key: "i", modifiers: .command),
        .undo:              KeyCombo(key: "z", modifiers: .command),
        .redo:              KeyCombo(key: "z", modifiers: [.command, .shift]),
        .selectAll:         KeyCombo(key: "a", modifiers: .command),
        .deselectAll:       KeyCombo(key: "a", modifiers: [.command, .shift]),
        .delete:            KeyCombo(key: "delete", modifiers: .none),
        .rippleDelete:      KeyCombo(key: "delete", modifiers: .shift),
        .playPause:         KeyCombo(key: "space", modifiers: .none),
        .stop:              KeyCombo(key: "s", modifiers: .none),
        .stepForward:       KeyCombo(key: "right", modifiers: .none),
        .stepBackward:      KeyCombo(key: "left", modifiers: .none),
        .goToStart:         KeyCombo(key: "home", modifiers: .none),
        .goToEnd:           KeyCombo(key: "end", modifiers: .none),
        .shuttleReverse:    KeyCombo(key: "j", modifiers: .none),
        .shuttleStop:       KeyCombo(key: "k", modifiers: .none),
        .shuttleForward:    KeyCombo(key: "l", modifiers: .none),
        .selectionTool:     KeyCombo(key: "v", modifiers: .none),
        .trimTool:          KeyCombo(key: "t", modifiers: .none),
        .bladeTool:         KeyCombo(key: "c", modifiers: .none),
        .setInPoint:        KeyCombo(key: "i", modifiers: .none),
        .setOutPoint:       KeyCombo(key: "o", modifiers: .none),
        .clearInPoint:      KeyCombo(key: "i", modifiers: .option),
        .clearOutPoint:     KeyCombo(key: "o", modifiers: .option),
        .addMarker:         KeyCombo(key: "m", modifiers: .none),
        .nextMarker:        KeyCombo(key: "m", modifiers: .shift),
        .previousMarker:    KeyCombo(key: "m", modifiers: [.command, .shift]),
        .blade:             KeyCombo(key: "k", modifiers: .command),
        .bladeAll:          KeyCombo(key: "k", modifiers: [.command, .shift]),
        .toggleClipEnabled: KeyCombo(key: "e", modifiers: .shift),
        .toggleSnapping:    KeyCombo(key: "s", modifiers: .command),
        .workspaceEdit:     KeyCombo(key: "1", modifiers: .shift),
        .workspaceColor:    KeyCombo(key: "2", modifiers: .shift),
        .workspaceAudio:    KeyCombo(key: "3", modifiers: .shift),
        .workspaceEffects:  KeyCombo(key: "4", modifiers: .shift),
        .workspaceDeliver:  KeyCombo(key: "5", modifiers: .shift),
        .toggleSidebar:     KeyCombo(key: "s", modifiers: [.command, .option]),
        .toggleInspector:   KeyCombo(key: "i", modifiers: [.command, .option]),
    ]

    // MARK: Final Cut Pro defaults

    private static let finalCutProShortcuts: [ActionID: KeyCombo] = [
        .newProject:        KeyCombo(key: "n", modifiers: .command),
        .openProject:       KeyCombo(key: "o", modifiers: .command),
        .save:              KeyCombo(key: "s", modifiers: .command),
        .saveAs:            KeyCombo(key: "s", modifiers: [.command, .shift]),
        .importMedia:       KeyCombo(key: "i", modifiers: .command),
        .undo:              KeyCombo(key: "z", modifiers: .command),
        .redo:              KeyCombo(key: "z", modifiers: [.command, .shift]),
        .selectAll:         KeyCombo(key: "a", modifiers: .command),
        .deselectAll:       KeyCombo(key: "a", modifiers: [.command, .shift]),
        .delete:            KeyCombo(key: "delete", modifiers: .none),
        .rippleDelete:      KeyCombo(key: "delete", modifiers: .shift),
        .playPause:         KeyCombo(key: "space", modifiers: .none),
        .stop:              KeyCombo(key: "escape", modifiers: .none),
        .stepForward:       KeyCombo(key: "right", modifiers: .none),
        .stepBackward:      KeyCombo(key: "left", modifiers: .none),
        .goToStart:         KeyCombo(key: "home", modifiers: .none),
        .goToEnd:           KeyCombo(key: "end", modifiers: .none),
        .shuttleReverse:    KeyCombo(key: "j", modifiers: .none),
        .shuttleStop:       KeyCombo(key: "k", modifiers: .none),
        .shuttleForward:    KeyCombo(key: "l", modifiers: .none),
        .selectionTool:     KeyCombo(key: "a", modifiers: .none),
        .trimTool:          KeyCombo(key: "t", modifiers: .none),
        .bladeTool:         KeyCombo(key: "b", modifiers: .none),
        .setInPoint:        KeyCombo(key: "i", modifiers: .none),
        .setOutPoint:       KeyCombo(key: "o", modifiers: .none),
        .clearInPoint:      KeyCombo(key: "i", modifiers: .option),
        .clearOutPoint:     KeyCombo(key: "o", modifiers: .option),
        .addMarker:         KeyCombo(key: "m", modifiers: .none),
        .nextMarker:        KeyCombo(key: "'", modifiers: .control),
        .previousMarker:    KeyCombo(key: ";", modifiers: .control),
        .blade:             KeyCombo(key: "b", modifiers: .command),
        .bladeAll:          KeyCombo(key: "b", modifiers: [.command, .shift]),
        .toggleClipEnabled: KeyCombo(key: "v", modifiers: .none),
        .toggleSnapping:    KeyCombo(key: "n", modifiers: .none),
        .workspaceEdit:     KeyCombo(key: "1", modifiers: .shift),
        .workspaceColor:    KeyCombo(key: "2", modifiers: .shift),
        .workspaceAudio:    KeyCombo(key: "3", modifiers: .shift),
        .workspaceEffects:  KeyCombo(key: "4", modifiers: .shift),
        .workspaceDeliver:  KeyCombo(key: "5", modifiers: .shift),
        .toggleSidebar:     KeyCombo(key: "0", modifiers: .command),
        .toggleInspector:   KeyCombo(key: "4", modifiers: .command),
    ]
}

// MARK: - Keyboard Shortcut Manager

/// Manages customizable keyboard shortcuts with NLE preset support.
/// Persists user customizations to UserDefaults.
@Observable
final class KeyboardShortcutManager: @unchecked Sendable {
    static let shared = KeyboardShortcutManager()

    private static let userDefaultsKey = "com.swifteditor.customShortcuts"
    private static let presetDefaultsKey = "com.swifteditor.activePreset"

    /// The currently active NLE preset.
    private(set) var activePreset: NLEPreset

    /// Per-action overrides on top of the active preset.
    private var customOverrides: [ActionID: KeyCombo]

    /// The resolved shortcut map (preset + overrides).
    var shortcuts: [ActionID: KeyCombo] {
        var result = activePreset.shortcuts
        for (action, combo) in customOverrides {
            result[action] = combo
        }
        return result
    }

    private init() {
        // Load saved preset
        if let savedPreset = UserDefaults.standard.string(forKey: Self.presetDefaultsKey),
           let preset = NLEPreset(rawValue: savedPreset) {
            self.activePreset = preset
        } else {
            self.activePreset = .davinciResolve
        }

        // Load custom overrides
        if let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: KeyCombo].self, from: data) {
            var overrides: [ActionID: KeyCombo] = [:]
            for (key, value) in decoded {
                if let actionID = ActionID(rawValue: key) {
                    overrides[actionID] = value
                }
            }
            self.customOverrides = overrides
        } else {
            self.customOverrides = [:]
        }
    }

    /// Look up the shortcut for a given action.
    func shortcut(for action: ActionID) -> KeyCombo? {
        if let override = customOverrides[action] {
            return override
        }
        return activePreset.shortcuts[action]
    }

    /// Get the display string for a shortcut (e.g. "Cmd+B").
    func displayString(for action: ActionID) -> String {
        shortcut(for: action)?.displayString ?? ""
    }

    /// Switch to a different NLE preset, clearing custom overrides.
    func applyPreset(_ preset: NLEPreset) {
        activePreset = preset
        customOverrides.removeAll()
        persist()
    }

    /// Set a custom shortcut for an action.
    func setShortcut(_ combo: KeyCombo, for action: ActionID) {
        customOverrides[action] = combo
        persist()
    }

    /// Remove custom override for an action, reverting to the preset default.
    func resetShortcut(for action: ActionID) {
        customOverrides.removeValue(forKey: action)
        persist()
    }

    /// Reset all customizations back to the active preset defaults.
    func resetAllToPreset() {
        customOverrides.removeAll()
        persist()
    }

    /// Check if an action has a user-customized shortcut.
    func isCustomized(_ action: ActionID) -> Bool {
        customOverrides[action] != nil
    }

    // MARK: - Persistence

    private func persist() {
        // Save preset
        UserDefaults.standard.set(activePreset.rawValue, forKey: Self.presetDefaultsKey)

        // Save overrides
        var encoded: [String: KeyCombo] = [:]
        for (action, combo) in customOverrides {
            encoded[action.rawValue] = combo
        }
        if let data = try? JSONEncoder().encode(encoded) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
}
