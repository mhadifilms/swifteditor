import Testing
import Foundation
@testable import TimelineKit
@testable import CoreMediaPlus

@Suite("Compound Clip Tests")
struct CompoundClipTests {

    func makeTimeline() -> TimelineModel {
        let timeline = TimelineModel()
        _ = timeline.requestTrackInsert(at: 0, type: .video)
        return timeline
    }

    @Test("Create compound clip from multiple clips")
    func createCompoundClip() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let asset = UUID()

        let clipA = timeline.requestAddClip(sourceAssetID: asset, trackID: trackID,
                                             at: Rational(0, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))!
        let clipB = timeline.requestAddClip(sourceAssetID: asset, trackID: trackID,
                                             at: Rational(24, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))!

        let compoundID = timeline.requestCreateCompoundClip(clipIDs: [clipA, clipB])
        #expect(compoundID != nil)

        // Original clips should be removed
        #expect(timeline.clip(by: clipA) == nil)
        #expect(timeline.clip(by: clipB) == nil)

        // A compound clip should exist
        #expect(timeline.compoundClips[compoundID!] != nil)

        // The compound clip's nested timeline should have the clips
        let nested = timeline.compoundClips[compoundID!]!.nestedTimeline
        let nestedTrack = nested.videoTracks.first!.id
        #expect(nested.clipsOnTrack(nestedTrack).count == 2)

        // Duration should be preserved
        #expect(timeline.duration == Rational(48, 1))
    }

    @Test("Flatten compound clip restores original clips")
    func flattenCompoundClip() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let asset = UUID()

        let clipA = timeline.requestAddClip(sourceAssetID: asset, trackID: trackID,
                                             at: Rational(0, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))!
        let clipB = timeline.requestAddClip(sourceAssetID: asset, trackID: trackID,
                                             at: Rational(24, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))!

        let compoundID = timeline.requestCreateCompoundClip(clipIDs: [clipA, clipB])!

        // Flatten it
        let result = timeline.requestFlattenCompoundClip(compoundClipID: compoundID)
        #expect(result)

        // Compound should be gone
        #expect(timeline.compoundClips[compoundID] == nil)

        // Should have 2 clips again on the track
        let clips = timeline.clipsOnTrack(trackID)
        #expect(clips.count == 2)
        #expect(clips[0].startTime == Rational(0, 1))
        #expect(clips[1].startTime == Rational(24, 1))
    }

    @Test("isCompoundClip identifies compound clips")
    func identifyCompoundClip() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let asset = UUID()

        let clipA = timeline.requestAddClip(sourceAssetID: asset, trackID: trackID,
                                             at: Rational(0, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))!

        // Regular clip
        #expect(!timeline.isCompoundClip(clipA))

        let compoundID = timeline.requestCreateCompoundClip(clipIDs: [clipA])!

        // Find the compound clip on the timeline
        let parentClipID = timeline.compoundClips[compoundID]!.parentClipID!
        #expect(timeline.isCompoundClip(parentClipID))
    }

    @Test("Undo compound clip creation")
    func undoCompoundClip() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let asset = UUID()

        let clipA = timeline.requestAddClip(sourceAssetID: asset, trackID: trackID,
                                             at: Rational(0, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))!

        timeline.requestCreateCompoundClip(clipIDs: [clipA])

        // Undo
        timeline.undoManager.undo()

        // Original clip should be restored
        #expect(timeline.clip(by: clipA) != nil)
        #expect(timeline.clip(by: clipA)?.startTime == Rational(0, 1))
    }
}

@Suite("Multicam Clip Tests")
struct MulticamClipTests {

    func makeTimeline() -> TimelineModel {
        let timeline = TimelineModel()
        _ = timeline.requestTrackInsert(at: 0, type: .video)
        return timeline
    }

    @Test("Create multicam clip with multiple angles")
    func createMulticamClip() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id

        let angles = [
            MulticamAngle(name: "Camera A", sourceAssetID: UUID(),
                          sourceIn: Rational(0, 1), sourceOut: Rational(120, 1)),
            MulticamAngle(name: "Camera B", sourceAssetID: UUID(),
                          sourceIn: Rational(0, 1), sourceOut: Rational(120, 1)),
        ]

        let multicamID = timeline.requestCreateMulticamClip(
            angles: angles, trackID: trackID,
            at: Rational(0, 1), duration: Rational(120, 1)
        )

        #expect(multicamID != nil)
        #expect(timeline.multicamClips[multicamID!]?.angles.count == 2)
        #expect(timeline.duration == Rational(120, 1))
    }

    @Test("Switch active angle")
    func switchAngle() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id

        let angles = [
            MulticamAngle(name: "A", sourceAssetID: UUID(),
                          sourceIn: .zero, sourceOut: Rational(60, 1)),
            MulticamAngle(name: "B", sourceAssetID: UUID(),
                          sourceIn: .zero, sourceOut: Rational(60, 1)),
        ]

        let multicamID = timeline.requestCreateMulticamClip(
            angles: angles, trackID: trackID,
            at: .zero, duration: Rational(60, 1)
        )!

        let multicam = timeline.multicamClips[multicamID]!
        #expect(multicam.activeAngleIndex == 0)

        // Find the clip on the timeline
        let clips = timeline.clipsOnTrack(trackID)
        let clipID = clips.first!.id

        let result = timeline.requestSwitchAngle(clipID: clipID, angleIndex: 1)
        #expect(result)
        #expect(multicam.activeAngleIndex == 1)
    }

    @Test("Angle switching at specific times")
    func angleSwitchAtTime() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id

        let angles = [
            MulticamAngle(name: "A", sourceAssetID: UUID(),
                          sourceIn: .zero, sourceOut: Rational(60, 1)),
            MulticamAngle(name: "B", sourceAssetID: UUID(),
                          sourceIn: .zero, sourceOut: Rational(60, 1)),
        ]

        let multicamID = timeline.requestCreateMulticamClip(
            angles: angles, trackID: trackID,
            at: .zero, duration: Rational(60, 1)
        )!

        let multicam = timeline.multicamClips[multicamID]!
        let clipID = timeline.clipsOnTrack(trackID).first!.id

        // Switch to angle B at time 30
        timeline.requestSwitchAngle(clipID: clipID, angleIndex: 1, at: Rational(30, 1))

        // Before switch: angle 0
        #expect(multicam.angleIndex(at: Rational(10, 1)) == 0)
        // After switch: angle 1
        #expect(multicam.angleIndex(at: Rational(40, 1)) == 1)
    }
}

@Suite("Subtitle Track Tests")
struct SubtitleTrackTests {

    func makeTimeline() -> TimelineModel {
        let timeline = TimelineModel()
        _ = timeline.requestTrackInsert(at: 0, type: .video)
        return timeline
    }

    @Test("Add and remove subtitle track")
    func subtitleTrack() {
        let timeline = makeTimeline()

        let trackID = timeline.requestAddSubtitleTrack(name: "English")
        #expect(timeline.subtitleTracks.count == 1)
        #expect(timeline.subtitleTracks[0].name == "English")

        let removed = timeline.requestRemoveSubtitleTrack(trackID: trackID)
        #expect(removed)
        #expect(timeline.subtitleTracks.count == 0)
    }

    @Test("Add and remove subtitle cues")
    func subtitleCues() {
        let timeline = makeTimeline()
        let trackID = timeline.requestAddSubtitleTrack()

        let cueID = timeline.requestAddSubtitleCue(
            trackID: trackID,
            text: "Hello World",
            startTime: Rational(10, 1),
            endTime: Rational(15, 1)
        )
        #expect(cueID != nil)

        let track = timeline.subtitleTracks.first!
        #expect(track.cues.count == 1)
        #expect(track.cues[0].text == "Hello World")

        // Query cue at time
        let activeCue = track.cue(at: Rational(12, 1))
        #expect(activeCue?.text == "Hello World")

        // No cue at a different time
        let noCue = track.cue(at: Rational(5, 1))
        #expect(noCue == nil)

        // Remove cue
        let removed = timeline.requestRemoveSubtitleCue(trackID: trackID, cueID: cueID!)
        #expect(removed)
        #expect(track.cues.count == 0)
    }

    @Test("Undo subtitle cue addition")
    func undoSubtitleCue() {
        let timeline = makeTimeline()
        let trackID = timeline.requestAddSubtitleTrack()

        timeline.requestAddSubtitleCue(
            trackID: trackID, text: "Test",
            startTime: Rational(0, 1), endTime: Rational(5, 1)
        )

        let track = timeline.subtitleTracks.first!
        #expect(track.cues.count == 1)

        timeline.undoManager.undo()
        #expect(track.cues.count == 0)
    }
}
