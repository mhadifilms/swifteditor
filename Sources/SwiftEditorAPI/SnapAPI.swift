import Foundation
import CoreMediaPlus
import TimelineKit

/// Facade for snap/magnet functionality on the timeline.
/// Snap state is managed directly by the SnapModel (no commands needed).
public final class SnapAPI: @unchecked Sendable {
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    /// Enable or disable snapping.
    public func setEnabled(_ enabled: Bool) {
        timeline.snapModel.isEnabled = enabled
    }

    /// Whether snapping is currently enabled.
    public var isEnabled: Bool {
        timeline.snapModel.isEnabled
    }

    /// Set the snap threshold distance.
    public func setThreshold(_ threshold: Rational) {
        timeline.snapModel.snapThreshold = threshold
    }

    /// The current snap threshold distance.
    public var threshold: Rational {
        timeline.snapModel.snapThreshold
    }

    /// Compute the snapped position for a given position.
    /// Returns the nearest snap point if within threshold, otherwise the original position.
    public func snap(_ position: Rational) -> Rational {
        timeline.snapModel.snap(position)
    }

    /// Rebuild snap points from current clip edges on the timeline.
    public func rebuildSnapPoints() {
        let allTrackIDs = timeline.videoTracks.map(\.id) + timeline.audioTracks.map(\.id)
        var edges: [(start: Rational, end: Rational)] = []
        for trackID in allTrackIDs {
            for clip in timeline.clipsOnTrack(trackID) {
                edges.append((start: clip.startTime, end: clip.startTime + clip.duration))
            }
        }
        timeline.snapModel.rebuild(clipEdges: edges)
    }
}
