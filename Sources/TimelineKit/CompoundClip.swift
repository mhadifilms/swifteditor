import Foundation
import Observation
import CoreMediaPlus

/// A compound clip wraps a nested TimelineModel (sub-sequence).
/// On the parent timeline it behaves like a regular clip but its content
/// is an entire mini-timeline that can be opened and edited independently.
@Observable
public final class CompoundClipModel: @unchecked Sendable {
    public let id: UUID
    public var name: String
    public let nestedTimeline: TimelineModel

    /// The clip ID on the parent timeline that represents this compound clip.
    public var parentClipID: UUID?

    public init(id: UUID = UUID(), name: String = "Compound Clip", nestedTimeline: TimelineModel) {
        self.id = id
        self.name = name
        self.nestedTimeline = nestedTimeline
    }
}

// MARK: - Compound Clip Operations on TimelineModel

extension TimelineModel {

    /// Registry of compound clips associated with this timeline.
    /// Keyed by compound clip ID.
    nonisolated(unsafe) private static var _compoundClips: [ObjectIdentifier: [UUID: CompoundClipModel]] = [:]

    public var compoundClips: [UUID: CompoundClipModel] {
        get { Self._compoundClips[ObjectIdentifier(self)] ?? [:] }
        set { Self._compoundClips[ObjectIdentifier(self)] = newValue }
    }

    /// Create a compound clip from selected clips on a single track.
    /// The clips are removed from the parent timeline and replaced by a single
    /// compound clip that contains a nested timeline with those clips.
    @discardableResult
    public func requestCreateCompoundClip(clipIDs: Set<UUID>) -> UUID? {
        guard !clipIDs.isEmpty else { return nil }

        // Gather clips and verify they're all on the same track
        let clips = clipIDs.compactMap { clip(by: $0) }
        guard !clips.isEmpty else { return nil }

        let trackID = clips[0].trackID
        guard clips.allSatisfy({ $0.trackID == trackID }) else { return nil }

        // Sort by start time
        let sorted = clips.sorted { $0.startTime < $1.startTime }
        let earliestStart = sorted.first!.startTime
        let latestEnd = sorted.map { $0.startTime + $0.duration }.max()!
        let compoundDuration = latestEnd - earliestStart

        // Create nested timeline
        let nested = TimelineModel()
        _ = nested.requestTrackInsert(at: 0, type: .video)
        let nestedTrackID = nested.videoTracks.first!.id

        // Add clips to nested timeline (offset to start at 0)
        for clip in sorted {
            let nestedStart = clip.startTime - earliestStart
            nested.requestAddClip(
                sourceAssetID: clip.sourceAssetID,
                trackID: nestedTrackID,
                at: nestedStart,
                sourceIn: clip.sourceIn,
                sourceOut: clip.sourceOut
            )
        }

        // Create compound clip model
        let compoundID = UUID()
        let compound = CompoundClipModel(id: compoundID, name: "Compound Clip", nestedTimeline: nested)

        // Save snapshots for undo
        let clipSnapshots = sorted.map { ($0.snapshot(), $0.trackID) }

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        // Remove original clips
        for clip in sorted {
            let clipID = clip.id
            appendOperation(&redo) { [weak self] in
                self?.performClipRemove(clipID: clipID) ?? false
            }
        }

        // Add compound clip placeholder on the parent timeline
        // We use a sentinel sourceAssetID = compoundID to identify it as a compound clip
        let placeholderClipID = UUID()
        let placeholder = ClipModel(
            id: placeholderClipID,
            sourceAssetID: compoundID, // compound clips use their own ID as the "asset"
            trackID: trackID,
            startTime: earliestStart,
            sourceIn: .zero,
            sourceOut: compoundDuration
        )

        appendOperation(&redo) { [weak self] in
            self?.allClips[placeholderClipID] = placeholder
            self?.compoundClips[compoundID] = compound
            compound.parentClipID = placeholderClipID
            return true
        }

        // Undo: remove placeholder, restore original clips
        prependOperation(&undo) { [weak self] in
            self?.allClips.removeValue(forKey: placeholderClipID)
            self?.compoundClips.removeValue(forKey: compoundID)
            return true
        }
        for (snapshot, tid) in clipSnapshots {
            prependOperation(&undo) { [weak self] in
                self?.performClipRestore(snapshot, trackID: tid) ?? false
            }
        }

        guard redo() else { let _ = undo(); return nil }
        undoManager.record(undo: undo, redo: redo, description: "Create Compound Clip")
        recalculateDuration()
        return compoundID
    }

    /// Flatten (expand) a compound clip back into its component clips.
    @discardableResult
    public func requestFlattenCompoundClip(compoundClipID: UUID) -> Bool {
        guard let compound = compoundClips[compoundClipID],
              let parentClipID = compound.parentClipID,
              let parentClip = allClips[parentClipID] else { return false }

        let trackID = parentClip.trackID
        let insertStart = parentClip.startTime
        let parentSnapshot = parentClip.snapshot()

        // Get clips from nested timeline
        let nestedTrackID = compound.nestedTimeline.videoTracks.first?.id
        let nestedClips: [ClipModel]
        if let ntid = nestedTrackID {
            nestedClips = compound.nestedTimeline.clipsOnTrack(ntid)
        } else {
            nestedClips = []
        }

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        // Remove the compound placeholder
        appendOperation(&redo) { [weak self] in
            self?.performClipRemove(clipID: parentClipID) ?? false
        }
        prependOperation(&undo) { [weak self] in
            self?.allClips[parentClipID] = ClipModel(from: parentSnapshot, trackID: trackID)
            self?.compoundClips[compoundClipID] = compound
            return true
        }

        // Restore individual clips from the nested timeline
        var restoredIDs: [UUID] = []
        for nestedClip in nestedClips {
            let newClipID = UUID()
            let adjustedStart = nestedClip.startTime + insertStart
            let newClip = ClipModel(
                id: newClipID,
                sourceAssetID: nestedClip.sourceAssetID,
                trackID: trackID,
                startTime: adjustedStart,
                sourceIn: nestedClip.sourceIn,
                sourceOut: nestedClip.sourceOut
            )
            restoredIDs.append(newClipID)

            appendOperation(&redo) { [weak self] in
                self?.allClips[newClipID] = newClip
                return true
            }
            prependOperation(&undo) { [weak self] in
                self?.allClips.removeValue(forKey: newClipID) != nil
            }
        }

        // Remove compound from registry on redo
        appendOperation(&redo) { [weak self] in
            self?.compoundClips.removeValue(forKey: compoundClipID)
            return true
        }

        guard redo() else { let _ = undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Flatten Compound Clip")
        recalculateDuration()
        return true
    }

    /// Check if a clip is a compound clip.
    public func isCompoundClip(_ clipID: UUID) -> Bool {
        guard let clip = allClips[clipID] else { return false }
        return compoundClips[clip.sourceAssetID] != nil
    }

    /// Get the nested timeline for a compound clip.
    public func nestedTimeline(for clipID: UUID) -> TimelineModel? {
        guard let clip = allClips[clipID] else { return nil }
        return compoundClips[clip.sourceAssetID]?.nestedTimeline
    }
}
