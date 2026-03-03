import SwiftUI
import SwiftEditorAPI
import CoreMediaPlus

/// Full menu bar structure following macOS conventions and NLE standards.
struct AppMenuCommands: Commands {
    let engine: SwiftEditorEngine

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
                // Select all clips
            }
            .keyboardShortcut("a")

            Button("Deselect All") {
                engine.timeline.selection = .empty
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            Divider()

            Button("Delete") {
                deleteSelectedClips()
            }
            .keyboardShortcut(.delete, modifiers: [])
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

            Button("Add Marker") { }
                .keyboardShortcut("m", modifiers: [])
        }

        // Clip menu
        CommandMenu("Clip") {
            Button("Blade") {
                bladeAtPlayhead()
            }
            .keyboardShortcut("b")

            Button("Blade All") {
                // Blade all tracks at playhead
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])

            Divider()

            Button("Enable/Disable") {
                toggleClipEnabled()
            }
            .keyboardShortcut("v", modifiers: [])
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
        }
    }

    private func deleteSelectedClips() {
        let ids = engine.timeline.selection.selectedClipIDs
        for id in ids {
            engine.timeline.requestClipDelete(clipID: id)
        }
        engine.timeline.selection = .empty
    }

    private func bladeAtPlayhead() {
        let time = engine.transport.currentTime
        // Split clip at playhead on the first video track that has a clip at this time
        for track in engine.timeline.videoTracks {
            if let clip = engine.timeline.clipAt(time: time, trackID: track.id) {
                engine.timeline.requestClipSplit(clipID: clip.id, at: time)
                break
            }
        }
    }

    private func toggleClipEnabled() {
        for id in engine.timeline.selection.selectedClipIDs {
            if let clip = engine.timeline.clip(by: id) {
                clip.isEnabled.toggle()
            }
        }
    }
}
