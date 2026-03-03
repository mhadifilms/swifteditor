import XCTest
@testable import TimelineKit
@testable import CoreMediaPlus
@testable import ProjectModel

/// Performance benchmarks for timeline operations at scale.
final class TimelineBenchmarks: XCTestCase {

    // MARK: - Helpers

    private func makeTimeline(videoTrackCount: Int = 1, audioTrackCount: Int = 0) -> TimelineModel {
        let timeline = TimelineModel()
        for _ in 0..<videoTrackCount {
            _ = timeline.requestTrackInsert(at: 0, type: .video)
        }
        for _ in 0..<audioTrackCount {
            _ = timeline.requestTrackInsert(at: 0, type: .audio)
        }
        return timeline
    }

    // MARK: - Add Clips

    func testAdd1000Clips() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let assetID = UUID()

        measure {
            for i in 0..<1000 {
                let position = Rational(Int64(i * 24), 1)
                timeline.requestAddClip(
                    sourceAssetID: assetID,
                    trackID: trackID,
                    at: position,
                    sourceIn: Rational(0, 1),
                    sourceOut: Rational(24, 1)
                )
            }
        }
    }

    func testAdd1000ClipsAcross10Tracks() {
        let timeline = makeTimeline(videoTrackCount: 10)
        let assetID = UUID()

        measure {
            for i in 0..<1000 {
                let trackIndex = i % timeline.videoTracks.count
                let trackID = timeline.videoTracks[trackIndex].id
                let position = Rational(Int64((i / 10) * 24), 1)
                timeline.requestAddClip(
                    sourceAssetID: assetID,
                    trackID: trackID,
                    at: position,
                    sourceIn: Rational(0, 1),
                    sourceOut: Rational(24, 1)
                )
            }
        }
    }

    // MARK: - Undo/Redo Cycles

    func testUndoRedo100Cycles() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let assetID = UUID()

        // Set up: add 100 clips
        for i in 0..<100 {
            let position = Rational(Int64(i * 24), 1)
            timeline.requestAddClip(
                sourceAssetID: assetID,
                trackID: trackID,
                at: position,
                sourceIn: Rational(0, 1),
                sourceOut: Rational(24, 1)
            )
        }

        measure {
            // Undo all 100
            for _ in 0..<100 {
                timeline.undoManager.undo()
            }
            // Redo all 100
            for _ in 0..<100 {
                timeline.undoManager.redo()
            }
        }
    }

    // MARK: - Split Operations

    func testSplitAllClipsAt500Positions() {
        // Build a timeline with 500 long clips, then split each one
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let assetID = UUID()

        // Add 500 clips of 100 frames each
        var clipIDs: [UUID] = []
        for i in 0..<500 {
            let position = Rational(Int64(i * 100), 1)
            if let clipID = timeline.requestAddClip(
                sourceAssetID: assetID,
                trackID: trackID,
                at: position,
                sourceIn: Rational(0, 1),
                sourceOut: Rational(100, 1)
            ) {
                clipIDs.append(clipID)
            }
        }

        measure {
            // Split each clip at its midpoint
            for clipID in clipIDs {
                if let clip = timeline.clip(by: clipID) {
                    let midpoint = clip.startTime + Rational(50, 1)
                    timeline.requestClipSplit(clipID: clipID, at: midpoint)
                }
            }
        }
    }

    // MARK: - Query Performance

    func testClipQueryWithManyClips() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let assetID = UUID()

        // Add 1000 clips
        for i in 0..<1000 {
            let position = Rational(Int64(i * 24), 1)
            timeline.requestAddClip(
                sourceAssetID: assetID,
                trackID: trackID,
                at: position,
                sourceIn: Rational(0, 1),
                sourceOut: Rational(24, 1)
            )
        }

        measure {
            // Query clipsOnTrack 100 times
            for _ in 0..<100 {
                let _ = timeline.clipsOnTrack(trackID)
            }
        }
    }

    func testClipAtTimeQueryWith1000Clips() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let assetID = UUID()

        for i in 0..<1000 {
            let position = Rational(Int64(i * 24), 1)
            timeline.requestAddClip(
                sourceAssetID: assetID,
                trackID: trackID,
                at: position,
                sourceIn: Rational(0, 1),
                sourceOut: Rational(24, 1)
            )
        }

        measure {
            // Search for clips at 500 different times
            for i in 0..<500 {
                let time = Rational(Int64(i * 48), 1)
                let _ = timeline.clipAt(time: time, trackID: trackID)
            }
        }
    }

    // MARK: - Load from Sequence

    func testLoadFrom1000ClipSequence() {
        let assetID = UUID()
        var clips: [ClipData] = []
        for i in 0..<1000 {
            clips.append(ClipData(
                sourceAssetID: assetID,
                startTime: Rational(Int64(i * 24), 1),
                sourceIn: Rational(0, 1),
                sourceOut: Rational(24, 1)
            ))
        }
        let track = TrackData(name: "V1", trackType: .video, clips: clips)
        let sequence = ProjectModel.Sequence(name: "Bench", tracks: [track])

        measure {
            let timeline = TimelineModel()
            timeline.load(from: sequence)
        }
    }

    // MARK: - Move Clips

    func testMove500Clips() {
        let timeline = makeTimeline()
        let trackID = timeline.videoTracks.first!.id
        let assetID = UUID()

        var clipIDs: [UUID] = []
        for i in 0..<500 {
            let position = Rational(Int64(i * 24), 1)
            if let clipID = timeline.requestAddClip(
                sourceAssetID: assetID,
                trackID: trackID,
                at: position,
                sourceIn: Rational(0, 1),
                sourceOut: Rational(24, 1)
            ) {
                clipIDs.append(clipID)
            }
        }

        measure {
            for clipID in clipIDs {
                timeline.requestClipMove(
                    clipID: clipID,
                    toTrackID: trackID,
                    at: Rational(Int64.random(in: 0...50000), 1)
                )
            }
        }
    }

    // MARK: - Export to Sequence

    func testExport1000ClipTimeline() {
        let timeline = makeTimeline(videoTrackCount: 5, audioTrackCount: 3)
        let assetID = UUID()

        // Add clips across all tracks
        let allTracks = timeline.videoTracks.map(\.id) + timeline.audioTracks.map(\.id)
        for i in 0..<1000 {
            let trackID = allTracks[i % allTracks.count]
            let position = Rational(Int64((i / allTracks.count) * 24), 1)
            timeline.requestAddClip(
                sourceAssetID: assetID,
                trackID: trackID,
                at: position,
                sourceIn: Rational(0, 1),
                sourceOut: Rational(24, 1)
            )
        }

        measure {
            let _ = timeline.exportToSequence()
        }
    }
}
