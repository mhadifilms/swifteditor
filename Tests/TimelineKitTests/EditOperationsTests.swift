import Testing
import Foundation
@testable import TimelineKit
@testable import CoreMediaPlus
@testable import ProjectModel

@Suite("Edit Operations Tests")
struct EditOperationsTests {

    func makeTimeline() -> TimelineModel {
        let timeline = TimelineModel()
        _ = timeline.requestTrackInsert(at: 0, type: .video)
        _ = timeline.requestTrackInsert(at: 0, type: .audio)
        return timeline
    }

    // MARK: - Insert Edit

    @Test("Insert edit splits and pushes downstream")
    func insertEdit() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let asset1 = UUID()
        let asset2 = UUID()

        // Add a clip from 0 to 24
        let clipA = timeline.requestAddClip(sourceAssetID: asset1, trackID: trackID,
                                             at: Rational(0, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))!

        // Insert at frame 12 — should split clipA and push second half right
        let clipB = timeline.requestInsertEdit(
            sourceAssetID: asset2, trackID: trackID,
            at: Rational(12, 1), sourceIn: Rational(0, 1), sourceOut: Rational(10, 1)
        )

        #expect(clipB != nil)
        #expect(timeline.duration == Rational(34, 1)) // 24 + 10 inserted
    }

    // MARK: - Overwrite Edit

    @Test("Overwrite edit replaces content without ripple")
    func overwriteEdit() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let asset1 = UUID()
        let asset2 = UUID()

        // Add a clip from 0 to 48
        timeline.requestAddClip(sourceAssetID: asset1, trackID: trackID,
                                 at: Rational(0, 1), sourceIn: Rational(0, 1), sourceOut: Rational(48, 1))

        // Overwrite from 10 to 20
        let clipB = timeline.requestOverwriteEdit(
            sourceAssetID: asset2, trackID: trackID,
            at: Rational(10, 1), sourceIn: Rational(0, 1), sourceOut: Rational(10, 1)
        )

        #expect(clipB != nil)
        // Duration should remain 48 (overwrite doesn't extend)
        #expect(timeline.duration == Rational(48, 1))
    }

    // MARK: - Append at End

    @Test("Append at end places clip after last")
    func appendAtEnd() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let asset = UUID()

        timeline.requestAddClip(sourceAssetID: asset, trackID: trackID,
                                 at: Rational(0, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))

        let clipB = timeline.requestAppendAtEnd(sourceAssetID: UUID(), trackID: trackID,
                                                  sourceIn: Rational(0, 1), sourceOut: Rational(12, 1))

        #expect(clipB != nil)
        let appended = timeline.clip(by: clipB!)!
        #expect(appended.startTime == Rational(24, 1))
        #expect(timeline.duration == Rational(36, 1))
    }

    // MARK: - Place on Top

    @Test("Place on top finds free track")
    func placeOnTop() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let asset = UUID()

        // Fill the first track at 0-24
        timeline.requestAddClip(sourceAssetID: asset, trackID: trackID,
                                 at: Rational(0, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))

        // Place on top at 0-12 should create a new track since track 1 is occupied
        let clipB = timeline.requestPlaceOnTop(sourceAssetID: UUID(),
                                                at: Rational(0, 1),
                                                sourceIn: Rational(0, 1), sourceOut: Rational(12, 1))

        #expect(clipB != nil)
        #expect(timeline.videoTracks.count == 2) // New track created
    }

    // MARK: - Ripple Delete

    @Test("Ripple delete removes clip and closes gap")
    func rippleDelete() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let asset = UUID()

        let clipA = timeline.requestAddClip(sourceAssetID: asset, trackID: trackID,
                                             at: Rational(0, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))!
        let clipB = timeline.requestAddClip(sourceAssetID: asset, trackID: trackID,
                                             at: Rational(24, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))!

        // Ripple delete clipA — clipB should shift left
        let result = timeline.requestRippleDelete(clipID: clipA)
        #expect(result)
        #expect(timeline.clip(by: clipB)?.startTime == Rational(0, 1))
        #expect(timeline.duration == Rational(24, 1))
    }

    // MARK: - Roll Trim

    @Test("Roll trim adjusts edit point between clips")
    func rollTrim() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let asset = UUID()

        let clipA = timeline.requestAddClip(sourceAssetID: asset, trackID: trackID,
                                             at: Rational(0, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))!
        let clipB = timeline.requestAddClip(sourceAssetID: asset, trackID: trackID,
                                             at: Rational(24, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))!

        // Roll trim: move edit point from 24 to 20
        let result = timeline.requestRollTrim(leftClipID: clipA, rightClipID: clipB, to: Rational(20, 1))
        #expect(result)

        let a = timeline.clip(by: clipA)!
        let b = timeline.clip(by: clipB)!
        #expect(a.duration == Rational(20, 1))
        #expect(b.startTime == Rational(20, 1))
        // Total duration unchanged
        #expect(timeline.duration == Rational(48, 1))
    }

    // MARK: - Slip

    @Test("Slip changes source in/out without moving clip")
    func slip() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let asset = UUID()

        let clipID = timeline.requestAddClip(sourceAssetID: asset, trackID: trackID,
                                              at: Rational(10, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))!

        let result = timeline.requestSlip(clipID: clipID, by: Rational(5, 1))
        #expect(result)

        let clip = timeline.clip(by: clipID)!
        #expect(clip.startTime == Rational(10, 1)) // Position unchanged
        #expect(clip.duration == Rational(24, 1))   // Duration unchanged
        #expect(clip.sourceIn == Rational(5, 1))    // Source shifted
        #expect(clip.sourceOut == Rational(29, 1))   // Source shifted
    }

    // MARK: - Slide

    @Test("Slide moves clip and adjusts neighbors")
    func slide() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let asset = UUID()

        let clipA = timeline.requestAddClip(sourceAssetID: asset, trackID: trackID,
                                             at: Rational(0, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))!
        let clipB = timeline.requestAddClip(sourceAssetID: asset, trackID: trackID,
                                             at: Rational(24, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))!
        let clipC = timeline.requestAddClip(sourceAssetID: asset, trackID: trackID,
                                             at: Rational(48, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))!

        // Slide clipB right by 5 frames
        let result = timeline.requestSlide(clipID: clipB, by: Rational(5, 1),
                                            leftNeighborID: clipA, rightNeighborID: clipC)
        #expect(result)

        let b = timeline.clip(by: clipB)!
        #expect(b.startTime == Rational(29, 1))
        #expect(b.duration == Rational(24, 1)) // B's content unchanged
    }

    // MARK: - Blade All

    @Test("Blade all splits clips on all tracks")
    func bladeAll() {
        let timeline = makeTimeline()
        let vTrack = timeline.videoTracks.first!.id
        let aTrack = timeline.audioTracks.first!.id
        let asset = UUID()

        timeline.requestAddClip(sourceAssetID: asset, trackID: vTrack,
                                 at: Rational(0, 1), sourceIn: Rational(0, 1), sourceOut: Rational(48, 1))
        timeline.requestAddClip(sourceAssetID: asset, trackID: aTrack,
                                 at: Rational(0, 1), sourceIn: Rational(0, 1), sourceOut: Rational(48, 1))

        let result = timeline.requestBladeAll(at: Rational(24, 1))
        #expect(result)

        // Each track should now have 2 clips
        #expect(timeline.clipsOnTrack(vTrack).count == 2)
        #expect(timeline.clipsOnTrack(aTrack).count == 2)
    }

    // MARK: - Speed Change

    @Test("Speed change adjusts clip duration")
    func speedChange() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let asset = UUID()

        let clipID = timeline.requestAddClip(sourceAssetID: asset, trackID: trackID,
                                              at: Rational(0, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))!

        let result = timeline.requestSpeedChange(clipID: clipID, newSpeed: 2.0)
        #expect(result)

        let clip = timeline.clip(by: clipID)!
        #expect(clip.speed == 2.0)
        // Duration should be approximately halved
        #expect(abs(clip.duration.seconds - 12.0) < 0.1)
    }

    // MARK: - Ripple Trim

    @Test("Ripple trim shifts downstream clips")
    func rippleTrim() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let asset = UUID()

        let clipA = timeline.requestAddClip(sourceAssetID: asset, trackID: trackID,
                                             at: Rational(0, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))!
        let clipB = timeline.requestAddClip(sourceAssetID: asset, trackID: trackID,
                                             at: Rational(24, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))!

        // Ripple trim clipA's trailing edge from 24 to 20 (shorten by 4)
        let result = timeline.requestRippleTrim(clipID: clipA, edge: .trailing, to: Rational(20, 1))
        #expect(result)

        // clipB should have shifted left by 4
        let b = timeline.clip(by: clipB)!
        #expect(b.startTime == Rational(20, 1))
    }

    // MARK: - Markers

    @Test("Add and remove markers")
    func markers() {
        let timeline = makeTimeline()

        let markerID = timeline.requestAddMarker(
            name: "Scene Start",
            at: Rational(10, 1),
            color: .green
        )

        #expect(timeline.markerManager.markers.count == 1)
        #expect(timeline.markerManager.markers[0].name == "Scene Start")

        let removed = timeline.requestRemoveMarker(id: markerID)
        #expect(removed)
        #expect(timeline.markerManager.markers.count == 0)
    }

    @Test("Navigate markers")
    func navigateMarkers() {
        let timeline = makeTimeline()

        timeline.requestAddMarker(name: "A", at: Rational(10, 1))
        timeline.requestAddMarker(name: "B", at: Rational(20, 1))
        timeline.requestAddMarker(name: "C", at: Rational(30, 1))

        let next = timeline.markerManager.nextMarker(after: Rational(15, 1))
        #expect(next?.name == "B")

        let prev = timeline.markerManager.previousMarker(before: Rational(25, 1))
        #expect(prev?.name == "B")
    }

    // MARK: - Undo Integration

    @Test("Undo ripple delete restores clip and positions")
    func undoRippleDelete() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let asset = UUID()

        let clipA = timeline.requestAddClip(sourceAssetID: asset, trackID: trackID,
                                             at: Rational(0, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))!
        let clipB = timeline.requestAddClip(sourceAssetID: asset, trackID: trackID,
                                             at: Rational(24, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))!

        timeline.requestRippleDelete(clipID: clipA)
        #expect(timeline.clip(by: clipA) == nil)
        #expect(timeline.clip(by: clipB)?.startTime == Rational(0, 1))

        // Undo
        timeline.undoManager.undo()
        #expect(timeline.clip(by: clipA) != nil)
        #expect(timeline.clip(by: clipB)?.startTime == Rational(24, 1))
    }

    @Test("Undo slip restores source points")
    func undoSlip() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id

        let clipID = timeline.requestAddClip(sourceAssetID: UUID(), trackID: trackID,
                                              at: Rational(0, 1), sourceIn: Rational(0, 1), sourceOut: Rational(24, 1))!

        timeline.requestSlip(clipID: clipID, by: Rational(10, 1))
        #expect(timeline.clip(by: clipID)?.sourceIn == Rational(10, 1))

        timeline.undoManager.undo()
        #expect(timeline.clip(by: clipID)?.sourceIn == Rational(0, 1))
    }
}
