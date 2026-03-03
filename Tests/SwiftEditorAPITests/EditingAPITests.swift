import Testing
import Foundation
@testable import SwiftEditorAPI
@testable import TimelineKit
@testable import CoreMediaPlus
@testable import CommandBus
@testable import ProjectModel

@Suite("EditingAPI Tests")
struct EditingAPITests {

    /// Create a fully wired engine and wait for handler registration.
    private func makeEngine() async throws -> SwiftEditorEngine {
        let engine = SwiftEditorEngine(projectName: "EditingTest")
        // Wait for async handler registration
        try await Task.sleep(for: .milliseconds(100))
        return engine
    }

    /// Ensure the engine has at least one video and one audio track, returning the video track ID.
    private func ensureTrack(_ engine: SwiftEditorEngine, type: TrackType = .video) async throws -> UUID {
        if type == .video, let existing = engine.timeline.videoTracks.first {
            return existing.id
        }
        if type == .audio, let existing = engine.timeline.audioTracks.first {
            return existing.id
        }
        _ = try await engine.editing.addTrack(type: type, at: 0)
        if type == .video {
            return engine.timeline.videoTracks.first!.id
        } else {
            return engine.timeline.audioTracks.first!.id
        }
    }

    @Test("Add clip through EditingAPI")
    func addClip() async throws {
        let engine = try await makeEngine()
        let trackID = try await ensureTrack(engine, type: .video)
        let assetID = UUID()

        let result = try await engine.editing.addClip(
            sourceAssetID: assetID, trackID: trackID,
            at: Rational(0, 1), sourceIn: Rational(0, 1),
            sourceOut: Rational(24, 1)
        )
        guard case .success = result else {
            Issue.record("Expected success from addClip")
            return
        }
        #expect(engine.timeline.duration == Rational(24, 1))
        #expect(engine.timeline.clipsOnTrack(trackID).count == 1)
    }

    @Test("Move clip through EditingAPI")
    func moveClip() async throws {
        let engine = try await makeEngine()
        let trackID = try await ensureTrack(engine, type: .video)
        let assetID = UUID()

        try await engine.editing.addClip(
            sourceAssetID: assetID, trackID: trackID,
            at: Rational(0, 1), sourceIn: Rational(0, 1),
            sourceOut: Rational(24, 1)
        )

        let clipID = engine.timeline.clipsOnTrack(trackID).first!.id

        let result = try await engine.editing.moveClip(
            clipID, toTrack: trackID, at: Rational(48, 1)
        )
        guard case .success = result else {
            Issue.record("Expected success from moveClip")
            return
        }
        #expect(engine.timeline.clip(by: clipID)?.startTime == Rational(48, 1))
    }

    @Test("Trim clip through EditingAPI")
    func trimClip() async throws {
        let engine = try await makeEngine()
        let trackID = try await ensureTrack(engine, type: .video)
        let assetID = UUID()

        try await engine.editing.addClip(
            sourceAssetID: assetID, trackID: trackID,
            at: Rational(0, 1), sourceIn: Rational(0, 1),
            sourceOut: Rational(48, 1)
        )

        let clipID = engine.timeline.clipsOnTrack(trackID).first!.id

        let result = try await engine.editing.trimClip(
            clipID, edge: .leading, to: Rational(12, 1)
        )
        guard case .success = result else {
            Issue.record("Expected success from trimClip")
            return
        }

        let clip = engine.timeline.clip(by: clipID)!
        #expect(clip.startTime == Rational(12, 1))
        #expect(clip.sourceIn == Rational(12, 1))
    }

    @Test("Split clip through EditingAPI")
    func splitClip() async throws {
        let engine = try await makeEngine()
        let trackID = try await ensureTrack(engine, type: .video)
        let assetID = UUID()

        try await engine.editing.addClip(
            sourceAssetID: assetID, trackID: trackID,
            at: Rational(0, 1), sourceIn: Rational(0, 1),
            sourceOut: Rational(48, 1)
        )

        let clipID = engine.timeline.clipsOnTrack(trackID).first!.id

        let result = try await engine.editing.splitClip(clipID, at: Rational(24, 1))
        guard case .success = result else {
            Issue.record("Expected success from splitClip")
            return
        }

        // After split, original clip should end at the split point
        let clip = engine.timeline.clip(by: clipID)!
        #expect(clip.sourceOut == Rational(24, 1))
        // There should now be 2 clips on the track
        #expect(engine.timeline.clipsOnTrack(trackID).count == 2)
    }

    @Test("Delete clip through EditingAPI")
    func deleteClip() async throws {
        let engine = try await makeEngine()
        let trackID = try await ensureTrack(engine, type: .video)
        let assetID = UUID()

        try await engine.editing.addClip(
            sourceAssetID: assetID, trackID: trackID,
            at: Rational(0, 1), sourceIn: Rational(0, 1),
            sourceOut: Rational(24, 1)
        )

        let clipID = engine.timeline.clipsOnTrack(trackID).first!.id

        let result = try await engine.editing.deleteClip(clipID)
        guard case .success = result else {
            Issue.record("Expected success from deleteClip")
            return
        }
        #expect(engine.timeline.clip(by: clipID) == nil)
        #expect(engine.timeline.clipsOnTrack(trackID).isEmpty)
    }

    @Test("Add and remove track through EditingAPI")
    func addRemoveTrack() async throws {
        let engine = try await makeEngine()
        let initialVideoCount = engine.timeline.videoTracks.count

        let result = try await engine.editing.addTrack(type: .video, at: 0)
        guard case .success = result else {
            Issue.record("Expected success from addTrack")
            return
        }
        #expect(engine.timeline.videoTracks.count == initialVideoCount + 1)

        let trackID = engine.timeline.videoTracks.first!.id
        let removeResult = try await engine.editing.removeTrack(trackID)
        guard case .success = removeResult else {
            Issue.record("Expected success from removeTrack")
            return
        }
        #expect(engine.timeline.videoTracks.count == initialVideoCount)
    }

    @Test("Clip query methods through EditingAPI")
    func clipQueries() async throws {
        let engine = try await makeEngine()
        let trackID = try await ensureTrack(engine, type: .video)
        let assetID = UUID()

        try await engine.editing.addClip(
            sourceAssetID: assetID, trackID: trackID,
            at: Rational(0, 1), sourceIn: Rational(0, 1),
            sourceOut: Rational(24, 1)
        )

        let clipID = engine.timeline.clipsOnTrack(trackID).first!.id

        // Test clip(by:)
        let clip = engine.editing.clip(by: clipID)
        #expect(clip != nil)
        #expect(clip?.sourceAssetID == assetID)

        // Test clipsOnTrack
        let clips = engine.editing.clipsOnTrack(trackID)
        #expect(clips.count == 1)

        // Test clipAt(time:trackID:)
        let clipAtTime = engine.editing.clipAt(time: Rational(12, 1), trackID: trackID)
        #expect(clipAtTime?.id == clipID)

        // Test clipAt outside clip range
        let noClip = engine.editing.clipAt(time: Rational(30, 1), trackID: trackID)
        #expect(noClip == nil)

        // Test timelineDuration
        #expect(engine.editing.timelineDuration == Rational(24, 1))
    }

    @Test("Multiple clips on same track")
    func multipleClips() async throws {
        let engine = try await makeEngine()
        let trackID = try await ensureTrack(engine, type: .video)

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
        #expect(engine.editing.timelineDuration == Rational(20, 1))
    }
}
