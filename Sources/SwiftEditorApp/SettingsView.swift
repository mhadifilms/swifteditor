import SwiftUI

/// Settings window accessible via Cmd+, following macOS conventions.
/// Provides General, Keyboard, Playback, and Appearance preference tabs.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            KeyboardSettingsTab()
                .tabItem {
                    Label("Keyboard", systemImage: "keyboard")
                }

            PlaybackSettingsTab()
                .tabItem {
                    Label("Playback", systemImage: "play.rectangle")
                }

            AppearanceSettingsTab()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
        }
        .frame(width: 550, height: 420)
    }
}

// MARK: - General Settings

struct GeneralSettingsTab: View {
    @AppStorage("autoSaveEnabled") private var autoSaveEnabled = true
    @AppStorage("autoSaveIntervalMinutes") private var autoSaveInterval = 5
    @AppStorage("showWelcomeOnLaunch") private var showWelcome = true
    @AppStorage("defaultProjectLocation") private var defaultProjectLocation = "~/Documents/SwiftEditor"

    var body: some View {
        Form {
            Section("Project") {
                Toggle("Auto-save projects", isOn: $autoSaveEnabled)
                    .accessibilityLabel("Auto-save projects")

                if autoSaveEnabled {
                    Picker("Auto-save interval", selection: $autoSaveInterval) {
                        Text("1 minute").tag(1)
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("15 minutes").tag(15)
                    }
                    .accessibilityLabel("Auto-save interval")
                }

                HStack {
                    TextField("Default project location", text: $defaultProjectLocation)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        browseProjectLocation()
                    }
                }
            }

            Section("Startup") {
                Toggle("Show welcome window on launch", isOn: $showWelcome)
                    .accessibilityLabel("Show welcome window on launch")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func browseProjectLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.title = "Choose Default Project Location"
        if panel.runModal() == .OK, let url = panel.url {
            defaultProjectLocation = url.path
        }
    }
}

// MARK: - Keyboard Settings

struct KeyboardSettingsTab: View {
    @State private var shortcutManager = KeyboardShortcutManager.shared
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil

    private var categories: [String] {
        let cats = Set(ActionID.allCases.map(\.category))
        return cats.sorted()
    }

    private var filteredActions: [ActionID] {
        var actions = ActionID.allCases.filter { action in
            if let category = selectedCategory {
                return action.category == category
            }
            return true
        }
        if !searchText.isEmpty {
            actions = actions.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
        return actions
    }

    var body: some View {
        VStack(spacing: 0) {
            // Preset selector
            HStack {
                Text("Preset:")
                    .font(.subheadline)
                Picker("", selection: Binding(
                    get: { shortcutManager.activePreset },
                    set: { shortcutManager.applyPreset($0) }
                )) {
                    ForEach(NLEPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
                .accessibilityLabel("Keyboard preset")

                Spacer()

                Button("Reset All") {
                    shortcutManager.resetAllToPreset()
                }
                .accessibilityLabel("Reset all shortcuts")
                .accessibilityHint("Revert all keyboard shortcuts to the selected preset defaults")
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Category filter + search
            HStack {
                Picker("Category", selection: $selectedCategory) {
                    Text("All").tag(nil as String?)
                    ForEach(categories, id: \.self) { category in
                        Text(category).tag(category as String?)
                    }
                }
                .frame(maxWidth: 160)
                .accessibilityLabel("Filter by category")

                Spacer()

                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                    .accessibilityLabel("Search shortcuts")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Shortcuts list
            List {
                ForEach(filteredActions) { action in
                    ShortcutRow(action: action, manager: shortcutManager)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
}

/// A single row displaying an action name and its current shortcut.
struct ShortcutRow: View {
    let action: ActionID
    let manager: KeyboardShortcutManager

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.displayName)
                    .font(.subheadline)
                Text(action.category)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(manager.displayString(for: action))
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(manager.isCustomized(action) ? Color.accentColor : Color.primary)
                .frame(minWidth: 80, alignment: .trailing)

            if manager.isCustomized(action) {
                Button {
                    manager.resetShortcut(for: action)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reset \(action.displayName) to preset default")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(action.displayName): \(manager.displayString(for: action))")
    }
}

// MARK: - Playback Settings

struct PlaybackSettingsTab: View {
    @AppStorage("defaultFrameRate") private var defaultFrameRate = 24
    @AppStorage("preRollDuration") private var preRollDuration = 3
    @AppStorage("loopPlayback") private var loopPlayback = false
    @AppStorage("audioScrubbing") private var audioScrubbing = true
    @AppStorage("proxyPlayback") private var proxyPlayback = false

    var body: some View {
        Form {
            Section("Timeline") {
                Picker("Default frame rate", selection: $defaultFrameRate) {
                    Text("23.976 fps").tag(23)
                    Text("24 fps").tag(24)
                    Text("25 fps").tag(25)
                    Text("29.97 fps").tag(29)
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .accessibilityLabel("Default frame rate")

                Picker("Pre-roll duration", selection: $preRollDuration) {
                    Text("None").tag(0)
                    Text("2 seconds").tag(2)
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                }
                .accessibilityLabel("Pre-roll duration")

                Toggle("Loop playback", isOn: $loopPlayback)
                    .accessibilityLabel("Loop playback")
            }

            Section("Audio") {
                Toggle("Audio scrubbing", isOn: $audioScrubbing)
                    .accessibilityLabel("Audio scrubbing")
                    .accessibilityHint("Play audio when scrubbing the timeline")
            }

            Section("Performance") {
                Toggle("Use proxy media for playback", isOn: $proxyPlayback)
                    .accessibilityLabel("Use proxy media for playback")
                    .accessibilityHint("Use lower resolution proxy files for smoother playback")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsTab: View {
    @AppStorage("timelineTrackHeight") private var trackHeight = 48
    @AppStorage("showThumbnails") private var showThumbnails = true
    @AppStorage("showWaveforms") private var showWaveforms = true
    @AppStorage("timelineOverlayOpacity") private var overlayOpacity = 0.7
    @AppStorage("viewerOverlayTimecode") private var showTimecodeOverlay = true

    var body: some View {
        Form {
            Section("Timeline") {
                Picker("Track height", selection: $trackHeight) {
                    Text("Small").tag(32)
                    Text("Medium").tag(48)
                    Text("Large").tag(64)
                }
                .accessibilityLabel("Track height")

                Toggle("Show video thumbnails", isOn: $showThumbnails)
                    .accessibilityLabel("Show video thumbnails in timeline")

                Toggle("Show audio waveforms", isOn: $showWaveforms)
                    .accessibilityLabel("Show audio waveforms in timeline")
            }

            Section("Viewer") {
                Toggle("Show timecode overlay", isOn: $showTimecodeOverlay)
                    .accessibilityLabel("Show timecode overlay on viewer")

                Slider(value: $overlayOpacity, in: 0.3...1.0) {
                    Text("Overlay opacity")
                }
                .accessibilityLabel("Overlay opacity")
                .accessibilityValue(String(format: "%.0f percent", overlayOpacity * 100))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
