import SwiftUI
import SwiftEditorAPI
import CoreMediaPlus

/// Full menu bar structure following macOS conventions and NLE standards.
struct AppMenuCommands: Commands {
    let engine: SwiftEditorEngine
    @FocusedValue(\.workspaceManager) var workspace
    @Environment(\.openWindow) var openWindow

    var body: some Commands {
        // Replace default New/Open with our project commands
        CommandGroup(replacing: .newItem) {
            Button("New Project") {
                // Create new project
            }
            .keyboardShortcut("n")

            Button("Open Project...") {
                // Open file dialog
            }
            .keyboardShortcut("o")

            Divider()

            Button("Import Media...") {
                // Import media
            }
            .keyboardShortcut("i")
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                Task { try? await engine.projectAPI.save(to: URL(filePath: "/tmp/project.json")) }
            }
            .keyboardShortcut("s")

            Button("Save As...") {
                // Save As dialog
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        // Edit menu additions
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                Task { try? await engine.editing.undo() }
            }
            .keyboardShortcut("z")
            .disabled(!engine.timeline.undoManager.canUndo)

            Button("Redo") {
                Task { try? await engine.editing.redo() }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!engine.timeline.undoManager.canRedo)
        }

        CommandGroup(after: .pasteboard) {
            Divider()

            Button("Select All") {
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
            }
            .keyboardShortcut("a")

            Button("Deselect All") {
                engine.timeline.selection = .empty
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            Divider()

            Button("Delete (Lift)") {
                liftSelectedClips()
            }
            .keyboardShortcut(.delete, modifiers: [])

            Button("Ripple Delete") {
                rippleDeleteSelectedClips()
            }
            .keyboardShortcut(.delete, modifiers: .shift)
        }

        // Mark menu
        CommandMenu("Mark") {
            Button("Set In Point") { }
                .keyboardShortcut("i", modifiers: [])

            Button("Set Out Point") { }
                .keyboardShortcut("o", modifiers: [])

            Button("Clear In Point") { }
                .keyboardShortcut("i", modifiers: .option)

            Button("Clear Out Point") { }
                .keyboardShortcut("o", modifiers: .option)

            Divider()

            Button("Add Marker") {
                addMarkerAtPlayhead()
            }
            .keyboardShortcut("m", modifiers: [])

            Button("Next Marker") {
                navigateToNextMarker()
            }
            .keyboardShortcut(.downArrow, modifiers: .shift)

            Button("Previous Marker") {
                navigateToPreviousMarker()
            }
            .keyboardShortcut(.upArrow, modifiers: .shift)
        }

        // Clip menu
        CommandMenu("Clip") {
            Button("Blade") {
                bladeAtPlayhead()
            }
            .keyboardShortcut("b")

            Button("Blade All") {
                bladeAllAtPlayhead()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])

            Divider()

            Button("Enable/Disable") {
                toggleClipEnabled()
            }
            .keyboardShortcut("v", modifiers: [])

            Divider()

            Button("Speed...") {
                // Speed change dialog
            }

            Button("Slip +1 Frame") {
                slipSelected(by: Rational(1, 1))
            }

            Button("Slip -1 Frame") {
                slipSelected(by: Rational(-1, 1))
            }
        }

        // Timeline menu
        CommandMenu("Timeline") {
            Button("Add Video Track") {
                engine.timeline.requestTrackInsert(at: engine.timeline.videoTracks.count, type: .video)
            }

            Button("Add Audio Track") {
                engine.timeline.requestTrackInsert(at: engine.timeline.audioTracks.count, type: .audio)
            }

            Divider()

            Button("Toggle Snapping") { }
                .keyboardShortcut("n", modifiers: [])
        }

        // Playback commands
        CommandGroup(after: .toolbar) {
            Divider()

            Button("Play/Pause") {
                if engine.transport.isPlaying {
                    engine.transport.pause()
                } else {
                    engine.transport.play()
                }
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("Stop") {
                engine.transport.stop()
            }

            Button("Step Forward") {
                engine.transport.stepForward()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            Button("Step Backward") {
                engine.transport.stepBackward()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            Divider()

            Button("Go to Start") {
                Task { await engine.transport.seek(to: .zero) }
            }
            .keyboardShortcut(.home, modifiers: [])

            Button("Go to End") {
                Task { await engine.transport.seek(to: engine.timeline.duration) }
            }
            .keyboardShortcut(.end, modifiers: [])
        }

        // Workspace menu
        CommandMenu("Workspace") {
            ForEach(WorkspaceType.allCases) { type in
                Button(type.rawValue) {
                    workspace?.switchTo(type)
                }
                .keyboardShortcut(KeyEquivalent(Character(type.shortcutNumber)), modifiers: .shift)
            }
        }

        // Help menu
        CommandGroup(replacing: .help) {
            Button("SwiftEditor Help") {
                // Open documentation (placeholder)
                NSWorkspace.shared.open(URL(string: "https://swifteditor.dev/docs")!)
            }

            Divider()

            Button("Keyboard Shortcuts") {
                openWindow(id: "keyboard-shortcuts-reference")
            }
            .keyboardShortcut("/", modifiers: [.command])

            Divider()

            Button("Release Notes") {
                NSWorkspace.shared.open(URL(string: "https://swifteditor.dev/releases")!)
            }
        }
    }

    // MARK: - Editing Actions

    private func liftSelectedClips() {
        let ids = engine.timeline.selection.selectedClipIDs
        for id in ids {
            engine.timeline.requestClipDelete(clipID: id)
        }
        engine.timeline.selection = .empty
    }

    private func rippleDeleteSelectedClips() {
        let ids = engine.timeline.selection.selectedClipIDs
        for id in ids {
            engine.timeline.requestRippleDelete(clipID: id)
        }
        engine.timeline.selection = .empty
    }

    private func bladeAtPlayhead() {
        let time = engine.transport.currentTime
        for track in engine.timeline.videoTracks {
            if let clip = engine.timeline.clipAt(time: time, trackID: track.id) {
                engine.timeline.requestClipSplit(clipID: clip.id, at: time)
                break
            }
        }
    }

    private func bladeAllAtPlayhead() {
        let time = engine.transport.currentTime
        engine.timeline.requestBladeAll(at: time)
    }

    private func toggleClipEnabled() {
        for id in engine.timeline.selection.selectedClipIDs {
            if let clip = engine.timeline.clip(by: id) {
                clip.isEnabled.toggle()
            }
        }
    }

    private func slipSelected(by offset: Rational) {
        for id in engine.timeline.selection.selectedClipIDs {
            engine.timeline.requestSlip(clipID: id, by: offset)
        }
    }

    private func addMarkerAtPlayhead() {
        let time = engine.transport.currentTime
        engine.timeline.requestAddMarker(name: "", at: time)
    }

    private func navigateToNextMarker() {
        let currentTime = engine.transport.currentTime
        if let next = engine.timeline.markerManager.nextMarker(after: currentTime) {
            Task { await engine.transport.seek(to: next.time) }
        }
    }

    private func navigateToPreviousMarker() {
        let currentTime = engine.transport.currentTime
        if let prev = engine.timeline.markerManager.previousMarker(before: currentTime) {
            Task { await engine.transport.seek(to: prev.time) }
        }
    }
}
