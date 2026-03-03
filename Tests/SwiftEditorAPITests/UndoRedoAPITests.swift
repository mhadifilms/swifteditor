import Testing
import Foundation
@testable import SwiftEditorAPI
@testable import TimelineKit
@testable import CoreMediaPlus
@testable import CommandBus

@Suite("Undo/Redo API Tests")
struct UndoRedoAPITests {

    private func makeEngine() async throws -> SwiftEditorEngine {
        let engine = SwiftEditorEngine(projectName: "UndoTest")
        try await Task.sleep(for: .milliseconds(100))
        return engine
    }

    private func ensureVideoTrack(_ engine: SwiftEditorEngine) async throws -> UUID {
        if let existing = engine.timeline.videoTracks.first {
            return existing.id
        }
        _ = try await engine.editing.addTrack(type: .video, at: 0)
        return engine.timeline.videoTracks.first!.id
    }

    // MARK: - CommandDispatcher-level undo (for commands that return undo commands)

    @Test("canUndo and canRedo start as false on dispatcher")
    func initialState() async throws {
        let engine = try await makeEngine()
        #expect(await !engine.editing.canUndo)
        #expect(await !engine.editing.canRedo)
    }

    @Test("Undo returns false when nothing to undo on dispatcher")
    func undoEmptyStack() async throws {
        let engine = try await makeEngine()
        let didUndo = try await engine.editing.undo()
        #expect(!didUndo)
    }

    @Test("Redo returns false when nothing to redo on dispatcher")
    func redoEmptyStack() async throws {
        let engine = try await makeEngine()
        let didRedo = try await engine.editing.redo()
        #expect(!didRedo)
    }

    @Test("Undo move clip through dispatcher restores position")
    func undoMoveClipViaDispatcher() async throws {
        let engine = try await makeEngine()
        let trackID = try await ensureVideoTrack(engine)
        let assetID = UUID()

        try await engine.editing.addClip(
            sourceAssetID: assetID, trackID: trackID,
            at: Rational(0, 1), sourceIn: Rational(0, 1),
            sourceOut: Rational(24, 1)
        )

        let clipID = engine.timeline.clipsOnTrack(trackID).first!.id

        try await engine.editing.moveClip(clipID, toTrack: trackID, at: Rational(48, 1))
        #expect(engine.timeline.clip(by: clipID)?.startTime == Rational(48, 1))

        // MoveClipHandler returns an undo command, so dispatcher undo works
        _ = try await engine.editing.undo()
        #expect(engine.timeline.clip(by: clipID)?.startTime == Rational(0, 1))
    }

    // MARK: - TimelineKit undo manager tests (for all operations)

    @Test("Timeline undo manager: undo add clip")
    func timelineUndoAddClip() async throws {
        let engine = try await makeEngine()
        let trackID = try await ensureVideoTrack(engine)

        try await engine.editing.addClip(
            sourceAssetID: UUID(), trackID: trackID,
            at: Rational(0, 1), sourceIn: Rational(0, 1),
            sourceOut: Rational(24, 1)
        )
        #expect(engine.timeline.clipsOnTrack(trackID).count == 1)

        // Timeline undo manager handles add/delete/split/trim
        let didUndo = engine.timeline.undoManager.undo()
        #expect(didUndo)
        #expect(engine.timeline.clipsOnTrack(trackID).isEmpty)
    }

    @Test("Timeline undo manager: redo add clip")
    func timelineRedoAddClip() async throws {
        let engine = try await makeEngine()
        let trackID = try await ensureVideoTrack(engine)

        try await engine.editing.addClip(
            sourceAssetID: UUID(), trackID: trackID,
            at: Rational(0, 1), sourceIn: Rational(0, 1),
            sourceOut: Rational(24, 1)
        )

        let clipID = engine.timeline.clipsOnTrack(trackID).first!.id

        engine.timeline.undoManager.undo()
        #expect(engine.timeline.clipsOnTrack(trackID).isEmpty)

        let didRedo = engine.timeline.undoManager.redo()
        #expect(didRedo)
        #expect(engine.timeline.clip(by: clipID) != nil)
    }

    @Test("Timeline undo manager: undo delete clip restores it")
    func timelineUndoDeleteClip() async throws {
        let engine = try await makeEngine()
        let trackID = try await ensureVideoTrack(engine)

        try await engine.editing.addClip(
            sourceAssetID: UUID(), trackID: trackID,
            at: Rational(0, 1), sourceIn: Rational(0, 1),
            sourceOut: Rational(24, 1)
        )

        let clipID = engine.timeline.clipsOnTrack(trackID).first!.id

        try await engine.editing.deleteClip(clipID)
        #expect(engine.timeline.clip(by: clipID) == nil)

        engine.timeline.undoManager.undo()
        #expect(engine.timeline.clip(by: clipID) != nil)
    }

    @Test("Timeline undo manager: undo split restores original clip")
    func timelineUndoSplit() async throws {
        let engine = try await makeEngine()
        let trackID = try await ensureVideoTrack(engine)

        try await engine.editing.addClip(
            sourceAssetID: UUID(), trackID: trackID,
            at: Rational(0, 1), sourceIn: Rational(0, 1),
            sourceOut: Rational(48, 1)
        )

        let clipID = engine.timeline.clipsOnTrack(trackID).first!.id

        try await engine.editing.splitClip(clipID, at: Rational(24, 1))
        #expect(engine.timeline.clip(by: clipID)?.sourceOut == Rational(24, 1))
        #expect(engine.timeline.clipsOnTrack(trackID).count == 2)

        engine.timeline.undoManager.undo()
        #expect(engine.timeline.clip(by: clipID)?.sourceOut == Rational(48, 1))
        #expect(engine.timeline.clipsOnTrack(trackID).count == 1)
    }

    @Test("Timeline undo manager: multiple undo/redo cycles")
    func timelineMultipleUndoRedo() async throws {
        let engine = try await makeEngine()
        let trackID = try await ensureVideoTrack(engine)

        try await engine.editing.addClip(
            sourceAssetID: UUID(), trackID: trackID,
            at: Rational(0, 1), sourceIn: Rational(0, 1),
            sourceOut: Rational(10, 1)
        )
        try await engine.editing.addClip(
            sourceAssetID: UUID(), trackID: trackID,
            at: Rational(10, 1), sourceIn: Rational(0, 1),
            sourceOut: Rational(10, 1)
        )

        #expect(engine.timeline.clipsOnTrack(trackID).count == 2)

        // Undo clip 2
        engine.timeline.undoManager.undo()
        #expect(engine.timeline.clipsOnTrack(trackID).count == 1)

        // Undo clip 1
        engine.timeline.undoManager.undo()
        #expect(engine.timeline.clipsOnTrack(trackID).count == 0)

        // Redo clip 1
        engine.timeline.undoManager.redo()
        #expect(engine.timeline.clipsOnTrack(trackID).count == 1)

        // Redo clip 2
        engine.timeline.undoManager.redo()
        #expect(engine.timeline.clipsOnTrack(trackID).count == 2)
    }

    @Test("Timeline undo manager: canUndo and canRedo")
    func timelineCanUndoCanRedo() async throws {
        let engine = try await makeEngine()
        let trackID = try await ensureVideoTrack(engine)

        // After track add, timeline has undo state
        let hadUndoAfterTrack = engine.timeline.undoManager.canUndo

        try await engine.editing.addClip(
            sourceAssetID: UUID(), trackID: trackID,
            at: Rational(0, 1), sourceIn: Rational(0, 1),
            sourceOut: Rational(10, 1)
        )
        #expect(engine.timeline.undoManager.canUndo)

        engine.timeline.undoManager.undo()
        #expect(engine.timeline.undoManager.canRedo)
    }
}
