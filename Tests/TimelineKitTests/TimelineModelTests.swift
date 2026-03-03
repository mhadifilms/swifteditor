import Testing
import Foundation
@testable import TimelineKit
@testable import CoreMediaPlus
@testable import ProjectModel

@Suite("TimelineModel Tests")
struct TimelineModelTests {

    func makeTimeline() -> TimelineModel {
        let timeline = TimelineModel()
        _ = timeline.requestTrackInsert(at: 0, type: .video)
        _ = timeline.requestTrackInsert(at: 0, type: .audio)
        // Clear undo stack from track creation
        return timeline
    }

    @Test("Add track")
    func addTrack() {
        let timeline = TimelineModel()
        let trackID = timeline.requestTrackInsert(at: 0, type: .video)
        #expect(trackID != nil)
        #expect(timeline.videoTracks.count == 1)
    }

    @Test("Add and remove track")
    func addRemoveTrack() {
        let timeline = TimelineModel()
        guard let trackID = timeline.requestTrackInsert(at: 0, type: .video) else {
            Issue.record("Failed to add track")
            return
        }
        #expect(timeline.videoTracks.count == 1)

        let removed = timeline.requestTrackRemove(trackID: trackID)
        #expect(removed)
        #expect(timeline.videoTracks.count == 0)
    }

    @Test("Add clip")
    func addClip() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let assetID = UUID()

        let clipID = timeline.requestAddClip(
            sourceAssetID: assetID, trackID: trackID,
            at: Rational(0, 1), sourceIn: Rational(0, 1),
            sourceOut: Rational(24, 1)
        )
        #expect(clipID != nil)
        #expect(timeline.duration == Rational(24, 1))
    }

    @Test("Move clip")
    func moveClip() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let assetID = UUID()

        guard let clipID = timeline.requestAddClip(
            sourceAssetID: assetID, trackID: trackID,
            at: Rational(0, 1), sourceIn: Rational(0, 1),
            sourceOut: Rational(24, 1)
        ) else {
            Issue.record("Failed to add clip")
            return
        }

        let moved = timeline.requestClipMove(clipID: clipID, toTrackID: trackID,
                                              at: Rational(48, 1))
        #expect(moved)
        #expect(timeline.clip(by: clipID)?.startTime == Rational(48, 1))
    }

    @Test("Trim clip leading edge")
    func trimLeading() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let assetID = UUID()

        guard let clipID = timeline.requestAddClip(
            sourceAssetID: assetID, trackID: trackID,
            at: Rational(0, 1), sourceIn: Rational(0, 1),
            sourceOut: Rational(48, 1)
        ) else {
            Issue.record("Failed to add clip")
            return
        }

        let trimmed = timeline.requestClipResize(clipID: clipID, edge: .leading,
                                                  to: Rational(12, 1))
        #expect(trimmed)
        let clip = timeline.clip(by: clipID)!
        #expect(clip.startTime == Rational(12, 1))
        #expect(clip.sourceIn == Rational(12, 1))
    }

    @Test("Split clip")
    func splitClip() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let assetID = UUID()

        guard let clipID = timeline.requestAddClip(
            sourceAssetID: assetID, trackID: trackID,
            at: Rational(0, 1), sourceIn: Rational(0, 1),
            sourceOut: Rational(48, 1)
        ) else {
            Issue.record("Failed to add clip")
            return
        }

        let split = timeline.requestClipSplit(clipID: clipID, at: Rational(24, 1))
        #expect(split)

        let originalClip = timeline.clip(by: clipID)!
        #expect(originalClip.sourceOut == Rational(24, 1))
    }

    @Test("Delete clip")
    func deleteClip() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let assetID = UUID()

        guard let clipID = timeline.requestAddClip(
            sourceAssetID: assetID, trackID: trackID,
            at: Rational(0, 1), sourceIn: Rational(0, 1),
            sourceOut: Rational(24, 1)
        ) else {
            Issue.record("Failed to add clip")
            return
        }

        let deleted = timeline.requestClipDelete(clipID: clipID)
        #expect(deleted)
        #expect(timeline.clip(by: clipID) == nil)
        #expect(timeline.duration == Rational.zero)
    }

    @Test("Undo and redo clip move")
    func undoRedoMove() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let assetID = UUID()

        guard let clipID = timeline.requestAddClip(
            sourceAssetID: assetID, trackID: trackID,
            at: Rational(0, 1), sourceIn: Rational(0, 1),
            sourceOut: Rational(24, 1)
        ) else {
            Issue.record("Failed to add clip")
            return
        }

        // Move
        timeline.requestClipMove(clipID: clipID, toTrackID: trackID, at: Rational(48, 1))
        #expect(timeline.clip(by: clipID)?.startTime == Rational(48, 1))

        // Undo move
        let undone = timeline.undoManager.undo()
        #expect(undone)
        #expect(timeline.clip(by: clipID)?.startTime == Rational(0, 1))

        // Redo move
        let redone = timeline.undoManager.redo()
        #expect(redone)
        #expect(timeline.clip(by: clipID)?.startTime == Rational(48, 1))
    }

    @Test("Undo split restores original clip")
    func undoSplit() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let assetID = UUID()

        guard let clipID = timeline.requestAddClip(
            sourceAssetID: assetID, trackID: trackID,
            at: Rational(0, 1), sourceIn: Rational(0, 1),
            sourceOut: Rational(48, 1)
        ) else {
            Issue.record("Failed to add clip")
            return
        }

        timeline.requestClipSplit(clipID: clipID, at: Rational(24, 1))
        #expect(timeline.clip(by: clipID)?.sourceOut == Rational(24, 1))

        // Undo
        timeline.undoManager.undo()
        #expect(timeline.clip(by: clipID)?.sourceOut == Rational(48, 1))
    }

    @Test("Load from ProjectModel Sequence")
    func loadFromSequence() {
        let timeline = TimelineModel()
        let assetID = UUID()
        let clipData = ClipData(sourceAssetID: assetID,
                                startTime: Rational(0, 1),
                                sourceIn: Rational(0, 1),
                                sourceOut: Rational(24, 1))
        let track = TrackData(name: "V1", trackType: .video, clips: [clipData])
        let sequence = ProjectModel.Sequence(name: "Test", tracks: [track])

        timeline.load(from: sequence)
        #expect(timeline.videoTracks.count == 1)
    }
}
