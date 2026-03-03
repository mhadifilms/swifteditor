import Foundation
import CoreMediaPlus
import ProjectModel

// MARK: - Advanced Edit Operations Extension on TimelineModel

extension TimelineModel {

    // MARK: - Insert Edit (with Ripple)
    // Splits timeline at position, pushes everything downstream, inserts new clip

    @discardableResult
    public func requestInsertEdit(
        sourceAssetID: UUID, trackID: UUID,
        at position: Rational,
        sourceIn: Rational, sourceOut: Rational,
        syncLockedTrackIDs: Set<UUID> = []
    ) -> UUID? {
        let insertDuration = sourceOut - sourceIn
        guard insertDuration > .zero else { return nil }

        let clipID = UUID()
        let clip = ClipModel(id: clipID, sourceAssetID: sourceAssetID,
                             trackID: trackID, startTime: position,
                             sourceIn: sourceIn, sourceOut: sourceOut)

        // Capture clips that need to shift right
        let affectedTracks = syncLockedTrackIDs.union([trackID])
        let shiftedClips = captureClipsToShift(rightOf: position, onTracks: affectedTracks)
        // Also capture clips that get split at the insert point
        let splitTargets = captureSplitTargets(at: position, onTracks: affectedTracks)

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        // Split clips at insertion point
        for target in splitTargets {
            appendOperation(&redo) { [weak self] in
                self?.performClipSplit(clipID: target.clipID, newClipID: target.splitID, at: position) ?? false
            }
            prependOperation(&undo) { [weak self] in
                self?.performClipUnsplit(originalID: target.clipID, splitID: target.splitID) ?? false
            }
        }

        // Shift downstream clips right (includes clips that already start at or after the position)
        appendOperation(&redo) { [weak self] in
            self?.shiftClips(shiftedClips.map(\.clipID), by: insertDuration) ?? false
        }
        prependOperation(&undo) { [weak self] in
            self?.shiftClips(shiftedClips.map(\.clipID), by: .zero - insertDuration) ?? false
        }

        // Also shift the newly split right-halves
        for target in splitTargets {
            appendOperation(&redo) { [weak self] in
                guard let clip = self?.allClips[target.splitID] else { return true }
                clip.startTime = clip.startTime + insertDuration
                return true
            }
            prependOperation(&undo) { [weak self] in
                guard let clip = self?.allClips[target.splitID] else { return true }
                clip.startTime = clip.startTime - insertDuration
                return true
            }
        }

        // Insert the new clip
        appendOperation(&redo) { [weak self] in
            self?.allClips[clipID] = clip
            return true
        }
        prependOperation(&undo) { [weak self] in
            self?.allClips.removeValue(forKey: clipID) != nil
        }

        guard redo() else { let _ = undo(); return nil }
        undoManager.record(undo: undo, redo: redo, description: "Insert Edit")
        recalculateDuration()
        events.send(.clipAdded(clipID: clipID, trackID: trackID))
        return clipID
    }

    // MARK: - Overwrite Edit
    // Replaces content at position, no ripple

    @discardableResult
    public func requestOverwriteEdit(
        sourceAssetID: UUID, trackID: UUID,
        at position: Rational,
        sourceIn: Rational, sourceOut: Rational
    ) -> UUID? {
        let overwriteDuration = sourceOut - sourceIn
        guard overwriteDuration > .zero else { return nil }

        let clipID = UUID()
        let clip = ClipModel(id: clipID, sourceAssetID: sourceAssetID,
                             trackID: trackID, startTime: position,
                             sourceIn: sourceIn, sourceOut: sourceOut)

        let overwriteRange = TimeRange(start: position, duration: overwriteDuration)

        // Remove any clips fully within the overwrite range, trim partials
        let removals = captureOverwriteRemovals(in: overwriteRange, onTrack: trackID)

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        // Handle removals and partial trims
        for removal in removals {
            switch removal {
            case .fullRemoval(let snapshot, let tid):
                appendOperation(&redo) { [weak self] in
                    self?.performClipRemove(clipID: snapshot.id) ?? false
                }
                prependOperation(&undo) { [weak self] in
                    self?.performClipRestore(snapshot, trackID: tid) ?? false
                }
            case .trimLeading(let cid, let oldStart, let oldSourceIn, let newStart, let newSourceIn):
                appendOperation(&redo) { [weak self] in
                    guard let c = self?.allClips[cid] else { return false }
                    c.startTime = newStart
                    c.sourceIn = newSourceIn
                    return true
                }
                prependOperation(&undo) { [weak self] in
                    guard let c = self?.allClips[cid] else { return false }
                    c.startTime = oldStart
                    c.sourceIn = oldSourceIn
                    return true
                }
            case .trimTrailing(let cid, let oldSourceOut, let newSourceOut):
                appendOperation(&redo) { [weak self] in
                    guard let c = self?.allClips[cid] else { return false }
                    c.sourceOut = newSourceOut
                    return true
                }
                prependOperation(&undo) { [weak self] in
                    guard let c = self?.allClips[cid] else { return false }
                    c.sourceOut = oldSourceOut
                    return true
                }
            case .splitMiddle(let cid, let snapshot, let tid, let trimToSourceOut, let rightStartTime):
                // Trim the original clip's trailing edge to just before the overwrite range
                let origSourceOut = snapshot.sourceOut
                appendOperation(&redo) { [weak self] in
                    guard let c = self?.allClips[cid] else { return false }
                    c.sourceOut = trimToSourceOut
                    return true
                }
                prependOperation(&undo) { [weak self] in
                    guard let c = self?.allClips[cid] else { return false }
                    c.sourceOut = origSourceOut
                    return true
                }
                // Create a new clip for the right portion (after the overwrite range)
                let rightClipID = UUID()
                let rightSourceIn = snapshot.sourceIn + (rightStartTime - snapshot.startTime)
                let rightClip = ClipModel(id: rightClipID, sourceAssetID: snapshot.sourceAssetID,
                                          trackID: tid, startTime: rightStartTime,
                                          sourceIn: rightSourceIn, sourceOut: snapshot.sourceOut)
                appendOperation(&redo) { [weak self] in
                    self?.allClips[rightClipID] = rightClip
                    return true
                }
                prependOperation(&undo) { [weak self] in
                    self?.allClips.removeValue(forKey: rightClipID) != nil
                }
            }
        }

        // Place new clip
        appendOperation(&redo) { [weak self] in
            self?.allClips[clipID] = clip
            return true
        }
        prependOperation(&undo) { [weak self] in
            self?.allClips.removeValue(forKey: clipID) != nil
        }

        guard redo() else { let _ = undo(); return nil }
        undoManager.record(undo: undo, redo: redo, description: "Overwrite Edit")
        recalculateDuration()
        events.send(.clipAdded(clipID: clipID, trackID: trackID))
        return clipID
    }

    // MARK: - Append at End

    @discardableResult
    public func requestAppendAtEnd(
        sourceAssetID: UUID, trackID: UUID,
        sourceIn: Rational, sourceOut: Rational
    ) -> UUID? {
        let trackEnd = clipsOnTrack(trackID).reduce(Rational.zero) { max($0, $1.startTime + $1.duration) }
        return requestAddClip(sourceAssetID: sourceAssetID, trackID: trackID,
                              at: trackEnd, sourceIn: sourceIn, sourceOut: sourceOut)
    }

    // MARK: - Place on Top
    // Places clip on next available track above

    @discardableResult
    public func requestPlaceOnTop(
        sourceAssetID: UUID,
        at position: Rational,
        sourceIn: Rational, sourceOut: Rational
    ) -> UUID? {
        // Find the first video track where the clip doesn't overlap
        let placeDuration = sourceOut - sourceIn
        let placeRange = TimeRange(start: position, duration: placeDuration)

        for track in videoTracks {
            let overlapping = clipsOnTrack(track.id).contains { clip in
                let clipRange = TimeRange(start: clip.startTime, duration: clip.duration)
                return clipRange.overlaps(placeRange)
            }
            if !overlapping {
                return requestAddClip(sourceAssetID: sourceAssetID, trackID: track.id,
                                      at: position, sourceIn: sourceIn, sourceOut: sourceOut)
            }
        }

        // No free track; create a new one
        guard let newTrackID = requestTrackInsert(at: videoTracks.count, type: .video) else { return nil }
        return requestAddClip(sourceAssetID: sourceAssetID, trackID: newTrackID,
                              at: position, sourceIn: sourceIn, sourceOut: sourceOut)
    }

    // MARK: - Lift (remove clip, leave gap)

    @discardableResult
    public func requestLift(clipID: UUID) -> Bool {
        // Same as delete — in a track-based NLE, delete = lift (leaves gap)
        requestClipDelete(clipID: clipID)
    }

    // MARK: - Extract / Ripple Delete (remove clip, close gap)

    @discardableResult
    public func requestRippleDelete(
        clipID: UUID,
        syncLockedTrackIDs: Set<UUID> = []
    ) -> Bool {
        guard let clip = allClips[clipID] else { return false }

        let trackID = clip.trackID
        let clipStart = clip.startTime
        let clipDuration = clip.duration
        let clipData = clip.snapshot()

        let affectedTracks = syncLockedTrackIDs.union([trackID])
        let shiftedClips = captureClipsToShift(rightOf: clipStart + clipDuration, onTracks: affectedTracks)

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        // Remove the clip
        appendOperation(&redo) { [weak self] in
            self?.performClipRemove(clipID: clipID) ?? false
        }
        prependOperation(&undo) { [weak self] in
            self?.performClipRestore(clipData, trackID: trackID) ?? false
        }

        // Shift downstream clips left
        appendOperation(&redo) { [weak self] in
            self?.shiftClips(shiftedClips.map(\.clipID), by: .zero - clipDuration) ?? false
        }
        prependOperation(&undo) { [weak self] in
            self?.shiftClips(shiftedClips.map(\.clipID), by: clipDuration) ?? false
        }

        guard redo() else { let _ = undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Ripple Delete")
        recalculateDuration()
        events.send(.clipRemoved(clipID: clipID, trackID: trackID))
        return true
    }

    // MARK: - Ripple Trim

    @discardableResult
    public func requestRippleTrim(
        clipID: UUID, edge: TrimEdge, to newTime: Rational,
        syncLockedTrackIDs: Set<UUID> = []
    ) -> Bool {
        guard let clip = allClips[clipID] else { return false }

        let oldStart = clip.startTime
        let oldSourceIn = clip.sourceIn
        let oldSourceOut = clip.sourceOut
        let oldEnd = clip.startTime + clip.duration

        let affectedTracks = syncLockedTrackIDs.union([clip.trackID])

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        switch edge {
        case .leading:
            let delta = newTime - oldStart
            let shiftedClips = captureClipsToShift(rightOf: oldEnd, onTracks: affectedTracks)

            appendOperation(&redo) { [weak self] in
                self?.performClipResize(clipID: clipID, edge: .leading, to: newTime) ?? false
            }
            prependOperation(&undo) { [weak self] in
                self?.performClipRestoreTrim(clipID: clipID, startTime: oldStart,
                                             sourceIn: oldSourceIn, sourceOut: oldSourceOut) ?? false
            }

            // Shift downstream clips by -delta (trimming in = gap closes, trimming out = gap opens)
            appendOperation(&redo) { [weak self] in
                self?.shiftClips(shiftedClips.map(\.clipID), by: delta) ?? false
            }
            prependOperation(&undo) { [weak self] in
                self?.shiftClips(shiftedClips.map(\.clipID), by: .zero - delta) ?? false
            }

        case .trailing:
            let newEnd = newTime
            let delta = newEnd - oldEnd
            let shiftedClips = captureClipsToShift(rightOf: oldEnd, onTracks: affectedTracks)

            appendOperation(&redo) { [weak self] in
                self?.performClipResize(clipID: clipID, edge: .trailing, to: newTime) ?? false
            }
            prependOperation(&undo) { [weak self] in
                self?.performClipRestoreTrim(clipID: clipID, startTime: oldStart,
                                             sourceIn: oldSourceIn, sourceOut: oldSourceOut) ?? false
            }

            appendOperation(&redo) { [weak self] in
                self?.shiftClips(shiftedClips.map(\.clipID), by: delta) ?? false
            }
            prependOperation(&undo) { [weak self] in
                self?.shiftClips(shiftedClips.map(\.clipID), by: .zero - delta) ?? false
            }
        }

        guard redo() else { let _ = undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Ripple Trim")
        recalculateDuration()
        events.send(.clipResized(clipID: clipID))
        return true
    }

    // MARK: - Roll Trim
    // Move edit point between two adjacent clips; one shortens, other extends

    @discardableResult
    public func requestRollTrim(
        leftClipID: UUID, rightClipID: UUID, to newEditPoint: Rational
    ) -> Bool {
        guard let leftClip = allClips[leftClipID],
              let rightClip = allClips[rightClipID] else { return false }

        let oldLeftSourceOut = leftClip.sourceOut
        let oldRightStart = rightClip.startTime
        let oldRightSourceIn = rightClip.sourceIn

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak self] in
            guard let left = self?.allClips[leftClipID],
                  let right = self?.allClips[rightClipID] else { return false }
            // Extend/shorten left clip
            let leftDelta = newEditPoint - (left.startTime + left.duration)
            left.sourceOut = left.sourceOut + leftDelta
            // Adjust right clip
            let rightDelta = newEditPoint - right.startTime
            right.sourceIn = right.sourceIn + rightDelta
            right.startTime = newEditPoint
            return true
        }
        prependOperation(&undo) { [weak self] in
            guard let left = self?.allClips[leftClipID],
                  let right = self?.allClips[rightClipID] else { return false }
            left.sourceOut = oldLeftSourceOut
            right.startTime = oldRightStart
            right.sourceIn = oldRightSourceIn
            return true
        }

        guard redo() else { let _ = undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Roll Trim")
        events.send(.clipResized(clipID: leftClipID))
        events.send(.clipResized(clipID: rightClipID))
        return true
    }

    // MARK: - Slip
    // Changes source in/out without moving clip or changing duration

    @discardableResult
    public func requestSlip(clipID: UUID, by offset: Rational) -> Bool {
        guard let clip = allClips[clipID] else { return false }

        let oldSourceIn = clip.sourceIn
        let oldSourceOut = clip.sourceOut

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak self] in
            guard let c = self?.allClips[clipID] else { return false }
            c.sourceIn = c.sourceIn + offset
            c.sourceOut = c.sourceOut + offset
            return true
        }
        prependOperation(&undo) { [weak self] in
            guard let c = self?.allClips[clipID] else { return false }
            c.sourceIn = oldSourceIn
            c.sourceOut = oldSourceOut
            return true
        }

        guard redo() else { let _ = undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Slip")
        events.send(.clipResized(clipID: clipID))
        return true
    }

    // MARK: - Slide
    // Moves clip between neighbors; neighbors' durations adjust

    @discardableResult
    public func requestSlide(
        clipID: UUID, by offset: Rational,
        leftNeighborID: UUID?, rightNeighborID: UUID?
    ) -> Bool {
        guard let clip = allClips[clipID] else { return false }

        let oldStart = clip.startTime
        let capturedLeftOut: Rational? = leftNeighborID.flatMap { allClips[$0]?.sourceOut }
        let capturedRightStart: Rational? = rightNeighborID.flatMap { allClips[$0]?.startTime }
        let capturedRightIn: Rational? = rightNeighborID.flatMap { allClips[$0]?.sourceIn }

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak self] in
            guard let c = self?.allClips[clipID] else { return false }
            c.startTime = c.startTime + offset

            // Adjust left neighbor's out point
            if let leftID = leftNeighborID, let left = self?.allClips[leftID] {
                left.sourceOut = left.sourceOut + offset
            }
            // Adjust right neighbor's in point and start
            if let rightID = rightNeighborID, let right = self?.allClips[rightID] {
                right.sourceIn = right.sourceIn + offset
                right.startTime = right.startTime + offset
            }
            return true
        }
        prependOperation(&undo) { [weak self] in
            guard let c = self?.allClips[clipID] else { return false }
            c.startTime = oldStart

            if let leftID = leftNeighborID, let left = self?.allClips[leftID],
               let out = capturedLeftOut {
                left.sourceOut = out
            }
            if let rightID = rightNeighborID, let right = self?.allClips[rightID] {
                if let start = capturedRightStart { right.startTime = start }
                if let inPt = capturedRightIn { right.sourceIn = inPt }
            }
            return true
        }

        guard redo() else { let _ = undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Slide")
        events.send(.clipMoved(clipID: clipID, toTrack: clip.trackID, at: clip.startTime))
        return true
    }

    // MARK: - Blade All (split all tracks at time)

    @discardableResult
    public func requestBladeAll(at time: Rational) -> Bool {
        var splitAny = false
        let allTrackIDs = videoTracks.map(\.id) + audioTracks.map(\.id)

        for trackID in allTrackIDs {
            if let clip = clipAt(time: time, trackID: trackID) {
                if requestClipSplit(clipID: clip.id, at: time) {
                    splitAny = true
                }
            }
        }
        return splitAny
    }

    // MARK: - Speed Change

    @discardableResult
    public func requestSpeedChange(clipID: UUID, newSpeed: Double) -> Bool {
        guard let clip = allClips[clipID], newSpeed > 0 else { return false }

        let oldSpeed = clip.speed
        let oldSourceOut = clip.sourceOut

        // Changing speed changes the effective duration
        // New sourceOut = sourceIn + (originalDuration * oldSpeed / newSpeed)
        let originalSourceDuration = clip.sourceOut - clip.sourceIn
        let speedRatio = oldSpeed / newSpeed
        let newDurationSeconds = originalSourceDuration.seconds * speedRatio
        let newSourceOut = clip.sourceIn + Rational(Int64(newDurationSeconds * 600), 600)

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak self] in
            guard let c = self?.allClips[clipID] else { return false }
            c.speed = newSpeed
            c.sourceOut = newSourceOut
            return true
        }
        prependOperation(&undo) { [weak self] in
            guard let c = self?.allClips[clipID] else { return false }
            c.speed = oldSpeed
            c.sourceOut = oldSourceOut
            return true
        }

        guard redo() else { let _ = undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Speed Change")
        recalculateDuration()
        events.send(.clipResized(clipID: clipID))
        return true
    }

    // MARK: - Speed Ramp (Variable Speed)

    /// Sets or clears a speed ramp curve on a clip.
    /// When a speed ramp is active, the clip's output duration is determined by the curve
    /// and the compositor uses remapped time to fetch source frames.
    @discardableResult
    public func requestSetSpeedRamp(clipID: UUID, curve: TimeRemapCurve?) -> Bool {
        guard let clip = allClips[clipID] else { return false }

        let oldSpeedRamp = clip.speedRamp

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak self] in
            guard let c = self?.allClips[clipID] else { return false }
            c.speedRamp = curve
            return true
        }
        prependOperation(&undo) { [weak self] in
            guard let c = self?.allClips[clipID] else { return false }
            c.speedRamp = oldSpeedRamp
            return true
        }

        guard redo() else { let _ = undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Speed Ramp")
        recalculateDuration()
        events.send(.clipResized(clipID: clipID))
        return true
    }

    // MARK: - Ripple Overwrite
    // Replace a clip AND adjust timeline duration

    @discardableResult
    public func requestRippleOverwrite(
        sourceAssetID: UUID, trackID: UUID,
        at position: Rational,
        sourceIn: Rational, sourceOut: Rational,
        syncLockedTrackIDs: Set<UUID> = []
    ) -> UUID? {
        // Find the clip at this position to replace
        guard let existingClip = clipAt(time: position, trackID: trackID) else {
            // No clip to replace — just do a regular overwrite
            return requestOverwriteEdit(sourceAssetID: sourceAssetID, trackID: trackID,
                                         at: position, sourceIn: sourceIn, sourceOut: sourceOut)
        }

        let newDuration = sourceOut - sourceIn
        let oldDuration = existingClip.duration
        let durationDelta = newDuration - oldDuration
        let existingClipID = existingClip.id
        let existingClipData = existingClip.snapshot()
        let existingTrackID = existingClip.trackID

        let affectedTracks = syncLockedTrackIDs.union([trackID])
        let shiftedClips = captureClipsToShift(rightOf: existingClip.startTime + oldDuration, onTracks: affectedTracks)

        let clipID = UUID()
        let clip = ClipModel(id: clipID, sourceAssetID: sourceAssetID,
                             trackID: trackID, startTime: existingClip.startTime,
                             sourceIn: sourceIn, sourceOut: sourceOut)

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        // Remove existing clip
        appendOperation(&redo) { [weak self] in
            self?.performClipRemove(clipID: existingClipID) ?? false
        }
        prependOperation(&undo) { [weak self] in
            self?.performClipRestore(existingClipData, trackID: existingTrackID) ?? false
        }

        // Add new clip
        appendOperation(&redo) { [weak self] in
            self?.allClips[clipID] = clip
            return true
        }
        prependOperation(&undo) { [weak self] in
            self?.allClips.removeValue(forKey: clipID) != nil
        }

        // Shift downstream clips by the duration difference
        if durationDelta != .zero {
            appendOperation(&redo) { [weak self] in
                self?.shiftClips(shiftedClips.map(\.clipID), by: durationDelta) ?? false
            }
            prependOperation(&undo) { [weak self] in
                self?.shiftClips(shiftedClips.map(\.clipID), by: .zero - durationDelta) ?? false
            }
        }

        guard redo() else { let _ = undo(); return nil }
        undoManager.record(undo: undo, redo: redo, description: "Ripple Overwrite")
        recalculateDuration()
        events.send(.clipAdded(clipID: clipID, trackID: trackID))
        return clipID
    }

    // MARK: - Fit to Fill
    // Apply speed change to source so it fills a given timeline duration

    @discardableResult
    public func requestFitToFill(
        sourceAssetID: UUID, trackID: UUID,
        at position: Rational,
        sourceIn: Rational, sourceOut: Rational,
        fillDuration: Rational
    ) -> UUID? {
        guard fillDuration > .zero else { return nil }

        let sourceDuration = sourceOut - sourceIn
        guard sourceDuration > .zero else { return nil }

        // Calculate speed needed to fit source into fill duration
        let speed = sourceDuration.seconds / fillDuration.seconds

        let clipID = requestAddClip(sourceAssetID: sourceAssetID, trackID: trackID,
                                     at: position, sourceIn: sourceIn, sourceOut: sourceOut)
        if let clipID = clipID {
            requestSpeedChange(clipID: clipID, newSpeed: speed)
        }
        return clipID
    }

    // MARK: - Replace Edit
    // Replace the clip under the playhead, matching at playhead frame

    @discardableResult
    public func requestReplaceEdit(
        sourceAssetID: UUID, trackID: UUID,
        sourcePlayheadTime: Rational,
        timelinePlayheadTime: Rational
    ) -> UUID? {
        guard let existingClip = clipAt(time: timelinePlayheadTime, trackID: trackID) else { return nil }

        let existingStart = existingClip.startTime
        let existingDuration = existingClip.duration

        // Calculate source in/out to match duration, centered on playhead
        let timelineOffset = timelinePlayheadTime - existingStart
        let newSourceIn = sourcePlayheadTime - timelineOffset
        let newSourceOut = newSourceIn + existingDuration

        // Remove existing clip and add new one
        let existingID = existingClip.id
        requestClipDelete(clipID: existingID)

        return requestAddClip(sourceAssetID: sourceAssetID, trackID: trackID,
                              at: existingStart, sourceIn: newSourceIn, sourceOut: newSourceOut)
    }

    // MARK: - Helper: Shift Clips

    struct ShiftCapture {
        let clipID: UUID
        let originalStart: Rational
    }

    func captureClipsToShift(rightOf position: Rational, onTracks trackIDs: Set<UUID>) -> [ShiftCapture] {
        allClips.values
            .filter { trackIDs.contains($0.trackID) && $0.startTime >= position }
            .map { ShiftCapture(clipID: $0.id, originalStart: $0.startTime) }
    }

    @discardableResult
    func shiftClips(_ clipIDs: [UUID], by offset: Rational) -> Bool {
        for id in clipIDs {
            if let clip = allClips[id] {
                clip.startTime = clip.startTime + offset
            }
        }
        return true
    }

    // MARK: - Helper: Split Targets at Insert Point

    private struct SplitTarget {
        let clipID: UUID
        let splitID: UUID
    }

    private func captureSplitTargets(at position: Rational, onTracks trackIDs: Set<UUID>) -> [SplitTarget] {
        var targets: [SplitTarget] = []
        for trackID in trackIDs {
            if let clip = clipAt(time: position, trackID: trackID) {
                // Only split if position is strictly inside the clip (not at start)
                if position > clip.startTime && position < clip.startTime + clip.duration {
                    targets.append(SplitTarget(clipID: clip.id, splitID: UUID()))
                }
            }
        }
        return targets
    }

    // MARK: - Helper: Overwrite Removals

    enum OverwriteRemoval {
        case fullRemoval(ClipModel.Snapshot, UUID) // snapshot, trackID
        case trimLeading(UUID, Rational, Rational, Rational, Rational) // clipID, oldStart, oldSourceIn, newStart, newSourceIn
        case trimTrailing(UUID, Rational, Rational) // clipID, oldSourceOut, newSourceOut
        case splitMiddle(UUID, ClipModel.Snapshot, UUID, Rational, Rational) // clipID, snapshot, trackID, trimToSourceOut, rightStartTime
    }

    func captureOverwriteRemovals(in range: TimeRange, onTrack trackID: UUID) -> [OverwriteRemoval] {
        var removals: [OverwriteRemoval] = []

        for clip in clipsOnTrack(trackID) {
            let clipStart = clip.startTime
            let clipEnd = clipStart + clip.duration

            // Fully within range — remove entirely
            if clipStart >= range.start && clipEnd <= range.end {
                removals.append(.fullRemoval(clip.snapshot(), trackID))
            }
            // Clip extends before and after range — trim left portion, create right portion
            else if clipStart < range.start && clipEnd > range.end {
                let trimToSourceOut = clip.sourceIn + (range.start - clipStart)
                removals.append(.splitMiddle(clip.id, clip.snapshot(), clip.trackID, trimToSourceOut, range.end))
            }
            // Clip starts before range, ends within — trim trailing
            else if clipStart < range.start && clipEnd > range.start {
                let newSourceOut = clip.sourceIn + (range.start - clipStart)
                removals.append(.trimTrailing(clip.id, clip.sourceOut, newSourceOut))
            }
            // Clip starts within range, ends after — trim leading
            else if clipStart < range.end && clipEnd > range.end {
                let delta = range.end - clipStart
                let newStart = range.end
                let newSourceIn = clip.sourceIn + delta
                removals.append(.trimLeading(clip.id, clip.startTime, clip.sourceIn, newStart, newSourceIn))
            }
        }

        return removals
    }
}
