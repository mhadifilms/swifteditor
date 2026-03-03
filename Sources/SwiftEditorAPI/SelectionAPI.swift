import Foundation
import CoreMediaPlus
import TimelineKit

/// Facade for timeline selection operations.
/// Selection is transient UI state, so operations go directly to the model.
public final class SelectionAPI: @unchecked Sendable {
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    // MARK: - Mutation

    /// Set the selection to a specific set of clip IDs.
    public func select(clipIDs: Set<UUID>) {
        timeline.selection = SelectionState(selectedClipIDs: clipIDs)
    }

    /// Add a clip to the current selection.
    public func addToSelection(clipID: UUID) {
        var sel = timeline.selection
        sel.selectedClipIDs.insert(clipID)
        timeline.selection = sel
    }

    /// Remove a clip from the current selection.
    public func removeFromSelection(clipID: UUID) {
        var sel = timeline.selection
        sel.selectedClipIDs.remove(clipID)
        timeline.selection = sel
    }

    /// Select all clips on the timeline.
    public func selectAll() {
        let allTrackIDs = timeline.videoTracks.map(\.id) + timeline.audioTracks.map(\.id)
        var allIDs = Set<UUID>()
        for trackID in allTrackIDs {
            for clip in timeline.clipsOnTrack(trackID) {
                allIDs.insert(clip.id)
            }
        }
        timeline.selection = SelectionState(selectedClipIDs: allIDs)
    }

    /// Clear all selection.
    public func deselectAll() {
        timeline.selection = .empty
    }

    /// Select all clips that overlap the given time range, optionally restricted to a track.
    public func selectClipsInRange(start: Rational, end: Rational, trackID: UUID? = nil) {
        var matching = Set<UUID>()
        let trackIDs: [UUID]
        if let tid = trackID {
            trackIDs = [tid]
        } else {
            trackIDs = timeline.videoTracks.map(\.id) + timeline.audioTracks.map(\.id)
        }
        for tid in trackIDs {
            for clip in timeline.clipsOnTrack(tid) {
                let clipEnd = clip.startTime + clip.duration
                if clip.startTime < end && clipEnd > start {
                    matching.insert(clip.id)
                }
            }
        }
        timeline.selection = SelectionState(selectedClipIDs: matching)
    }

    // MARK: - Query

    /// The currently selected clip IDs.
    public var selectedClipIDs: Set<UUID> {
        timeline.selection.selectedClipIDs
    }

    /// Check if a specific clip is selected.
    public func isSelected(_ clipID: UUID) -> Bool {
        timeline.selection.selectedClipIDs.contains(clipID)
    }

    /// Get the ClipModel objects for the current selection.
    public var selectedClips: [ClipModel] {
        timeline.selection.selectedClipIDs.compactMap { timeline.clip(by: $0) }
    }
}
