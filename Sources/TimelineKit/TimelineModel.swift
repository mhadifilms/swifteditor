import Foundation
import Observation
import CoreMediaPlus
import ProjectModel

/// The central editing model. All mutations go through request*() methods.
/// Inspired by Kdenlive's TimelineModel with lambda undo/redo composition.
@Observable
public final class TimelineModel: @unchecked Sendable {
    // MARK: - Published State

    public private(set) var videoTracks: [VideoTrackModel] = []
    public private(set) var audioTracks: [AudioTrackModel] = []
    public private(set) var duration: Rational = .zero
    public var selection: SelectionState = .empty

    // Compound, multicam, and subtitle storage — stored directly to avoid
    // ObjectIdentifier-keyed static dictionary crashes with @Observable.
    public var compoundClips: [UUID: CompoundClipModel] = [:]
    public var multicamClips: [UUID: MulticamClipModel] = [:]
    public var subtitleTracks: [SubtitleTrackModel] = []

    // MARK: - Subsystems

    public let undoManager = TimelineUndoManager()
    public let groupsModel = GroupsModel()
    public let snapModel = SnapModel()
    public let events = TimelineEventBus()
    public let markerManager = MarkerManager()

    // MARK: - Internal State

    var allClips: [UUID: ClipModel] = [:]

    public init() {}

    // MARK: - Load from ProjectModel

    public func load(from sequence: ProjectModel.Sequence) {
        videoTracks = sequence.tracks.filter { $0.trackType == .video }.map { VideoTrackModel(from: $0) }
        audioTracks = sequence.tracks.filter { $0.trackType == .audio }.map { AudioTrackModel(from: $0) }
        rebuildInternalState(from: sequence)
    }

    /// Export current state back to a Sequence for saving.
    public func exportToSequence() -> ProjectModel.Sequence {
        var allTrackData: [TrackData] = []
        for track in videoTracks {
            var td = TrackData(name: track.name, trackType: .video)
            td.id = track.id
            td.isMuted = track.isMuted
            td.isLocked = track.isLocked
            td.clips = clipsOnTrack(track.id).map { clip in
                ClipData(id: clip.id, sourceAssetID: clip.sourceAssetID,
                         startTime: clip.startTime,
                         sourceIn: clip.sourceIn,
                         sourceOut: clip.sourceOut,
                         speed: Rational(Int64(clip.speed * 1000), 1000),
                         isEnabled: clip.isEnabled,
                         speedRamp: clip.speedRamp)
            }
            allTrackData.append(td)
        }
        for track in audioTracks {
            var td = TrackData(name: track.name, trackType: .audio)
            td.id = track.id
            td.isMuted = track.isMuted
            td.isLocked = track.isLocked
            td.clips = clipsOnTrack(track.id).map { clip in
                ClipData(id: clip.id, sourceAssetID: clip.sourceAssetID,
                         startTime: clip.startTime,
                         sourceIn: clip.sourceIn,
                         sourceOut: clip.sourceOut,
                         speed: Rational(Int64(clip.speed * 1000), 1000),
                         isEnabled: clip.isEnabled,
                         speedRamp: clip.speedRamp)
            }
            allTrackData.append(td)
        }
        return ProjectModel.Sequence(name: "Exported", tracks: allTrackData)
    }

    // MARK: - Query Methods

    public func clip(by id: UUID) -> ClipModel? {
        allClips[id]
    }

    public func clipsOnTrack(_ trackID: UUID) -> [ClipModel] {
        allClips.values
            .filter { $0.trackID == trackID }
            .sorted { $0.startTime < $1.startTime }
    }

    public func clipAt(time: Rational, trackID: UUID) -> ClipModel? {
        allClips.values.first { clip in
            clip.trackID == trackID &&
            time >= clip.startTime &&
            time < clip.startTime + clip.duration
        }
    }

    // MARK: - Request Methods (Single Entry Point for All Mutations)

    @discardableResult
    public func requestAddClip(sourceAssetID: UUID, trackID: UUID,
                                at position: Rational,
                                sourceIn: Rational, sourceOut: Rational) -> UUID? {
        let clipID = UUID()
        let clip = ClipModel(id: clipID, sourceAssetID: sourceAssetID,
                             trackID: trackID, startTime: position,
                             sourceIn: sourceIn, sourceOut: sourceOut)

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak self] in
            self?.allClips[clipID] = clip
            return true
        }
        prependOperation(&undo) { [weak self] in
            self?.allClips.removeValue(forKey: clipID) != nil
        }

        guard redo() else { let _ = undo(); return nil }
        undoManager.record(undo: undo, redo: redo, description: "Add Clip")
        recalculateDuration()
        events.send(.clipAdded(clipID: clipID, trackID: trackID))
        return clipID
    }

    @discardableResult
    public func requestClipMove(clipID: UUID, toTrackID: UUID, at position: Rational) -> Bool {
        guard let clip = allClips[clipID] else { return false }

        let sourceTrackID = clip.trackID
        let sourcePosition = clip.startTime

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak self] in
            self?.performClipMove(clipID: clipID, toTrack: toTrackID, at: position) ?? false
        }
        prependOperation(&undo) { [weak self] in
            self?.performClipMove(clipID: clipID, toTrack: sourceTrackID, at: sourcePosition) ?? false
        }

        guard redo() else { let _ = undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Move Clip")
        recalculateDuration()
        events.send(.clipMoved(clipID: clipID, toTrack: toTrackID, at: position))
        return true
    }

    @discardableResult
    public func requestClipResize(clipID: UUID, edge: TrimEdge, to newTime: Rational) -> Bool {
        guard let clip = allClips[clipID] else { return false }

        let oldStart = clip.startTime
        let oldSourceIn = clip.sourceIn
        let oldSourceOut = clip.sourceOut

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak self] in
            self?.performClipResize(clipID: clipID, edge: edge, to: newTime) ?? false
        }
        prependOperation(&undo) { [weak self] in
            self?.performClipRestoreTrim(clipID: clipID, startTime: oldStart,
                                         sourceIn: oldSourceIn, sourceOut: oldSourceOut) ?? false
        }

        guard redo() else { let _ = undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Trim Clip")
        recalculateDuration()
        events.send(.clipResized(clipID: clipID))
        return true
    }

    @discardableResult
    public func requestClipSplit(clipID: UUID, at time: Rational) -> Bool {
        guard let clip = allClips[clipID],
              time > clip.startTime,
              time < clip.startTime + clip.duration else { return false }

        let newClipID = UUID()

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak self] in
            self?.performClipSplit(clipID: clipID, newClipID: newClipID, at: time) ?? false
        }
        prependOperation(&undo) { [weak self] in
            self?.performClipUnsplit(originalID: clipID, splitID: newClipID) ?? false
        }

        guard redo() else { let _ = undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Split Clip")
        events.send(.clipSplit(clipID: clipID, newClipID: newClipID, at: time))
        return true
    }

    @discardableResult
    public func requestClipDelete(clipID: UUID) -> Bool {
        guard let clip = allClips[clipID] else { return false }

        let trackID = clip.trackID
        let clipData = clip.snapshot()

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak self] in
            self?.performClipRemove(clipID: clipID) ?? false
        }
        prependOperation(&undo) { [weak self] in
            self?.performClipRestore(clipData, trackID: trackID) ?? false
        }

        guard redo() else { let _ = undo(); return false }
        undoManager.record(undo: undo, redo: redo, description: "Delete Clip")
        recalculateDuration()
        events.send(.clipRemoved(clipID: clipID, trackID: trackID))
        return true
    }

    @discardableResult
    public func requestTrackInsert(at index: Int, type: TrackType) -> UUID? {
        let trackID = UUID()
        let name = type == .video ? "V\(videoTracks.count + 1)" : "A\(audioTracks.count + 1)"

        var undo: UndoAction = { true }
        var redo: UndoAction = { true }

        appendOperation(&redo) { [weak self] in
            self?.performTrackInsert(id: trackID, name: name, type: type, at: index) ?? false
        }
        prependOperation(&undo) { [weak self] in
            self?.performTrackRemove(trackID: trackID, type: type) ?? false
        }

        guard redo() else { let _ = undo(); return nil }
        undoManager.record(undo: undo, redo: redo, description: "Add Track")
        events.send(.trackAdded(trackID: trackID, type: type, at: index))
        return trackID
    }

    @discardableResult
    public func requestTrackRemove(trackID: UUID) -> Bool {
        // Find the track type and index
        if let index = videoTracks.firstIndex(where: { $0.id == trackID }) {
            let track = videoTracks[index]
            let savedClips = clipsOnTrack(trackID).map { $0.snapshot() }

            var undo: UndoAction = { true }
            var redo: UndoAction = { true }

            appendOperation(&redo) { [weak self] in
                guard let self else { return false }
                for clip in self.clipsOnTrack(trackID) {
                    self.allClips.removeValue(forKey: clip.id)
                }
                return self.performTrackRemove(trackID: trackID, type: .video)
            }
            prependOperation(&undo) { [weak self] in
                guard let self else { return false }
                guard self.performTrackInsert(id: trackID, name: track.name, type: .video, at: index) else { return false }
                for clipSnap in savedClips {
                    self.performClipRestore(clipSnap, trackID: trackID)
                }
                return true
            }

            guard redo() else { let _ = undo(); return false }
            undoManager.record(undo: undo, redo: redo, description: "Remove Track")
            recalculateDuration()
            events.send(.trackRemoved(trackID: trackID))
            return true
        }

        if let index = audioTracks.firstIndex(where: { $0.id == trackID }) {
            let track = audioTracks[index]
            let savedClips = clipsOnTrack(trackID).map { $0.snapshot() }

            var undo: UndoAction = { true }
            var redo: UndoAction = { true }

            appendOperation(&redo) { [weak self] in
                guard let self else { return false }
                for clip in self.clipsOnTrack(trackID) {
                    self.allClips.removeValue(forKey: clip.id)
                }
                return self.performTrackRemove(trackID: trackID, type: .audio)
            }
            prependOperation(&undo) { [weak self] in
                guard let self else { return false }
                guard self.performTrackInsert(id: trackID, name: track.name, type: .audio, at: index) else { return false }
                for clipSnap in savedClips {
                    self.performClipRestore(clipSnap, trackID: trackID)
                }
                return true
            }

            guard redo() else { let _ = undo(); return false }
            undoManager.record(undo: undo, redo: redo, description: "Remove Track")
            recalculateDuration()
            events.send(.trackRemoved(trackID: trackID))
            return true
        }

        return false
    }

    // MARK: - Internal Mutation Methods

    func performClipMove(clipID: UUID, toTrack: UUID, at position: Rational) -> Bool {
        guard let clip = allClips[clipID] else { return false }
        clip.trackID = toTrack
        clip.startTime = position
        return true
    }

    func performClipResize(clipID: UUID, edge: TrimEdge, to newTime: Rational) -> Bool {
        guard let clip = allClips[clipID] else { return false }
        switch edge {
        case .leading:
            let delta = newTime - clip.startTime
            clip.sourceIn = clip.sourceIn + delta
            clip.startTime = newTime
        case .trailing:
            clip.sourceOut = clip.sourceIn + (newTime - clip.startTime)
        }
        return true
    }

    func performClipRestoreTrim(clipID: UUID, startTime: Rational,
                                         sourceIn: Rational, sourceOut: Rational) -> Bool {
        guard let clip = allClips[clipID] else { return false }
        clip.startTime = startTime
        clip.sourceIn = sourceIn
        clip.sourceOut = sourceOut
        return true
    }

    func performClipSplit(clipID: UUID, newClipID: UUID, at time: Rational) -> Bool {
        guard let clip = allClips[clipID] else { return false }
        let splitSourceTime = clip.sourceIn + (time - clip.startTime)

        let newClip = ClipModel(
            id: newClipID,
            sourceAssetID: clip.sourceAssetID,
            trackID: clip.trackID,
            startTime: time,
            sourceIn: splitSourceTime,
            sourceOut: clip.sourceOut
        )

        clip.sourceOut = splitSourceTime
        allClips[newClipID] = newClip
        return true
    }

    func performClipUnsplit(originalID: UUID, splitID: UUID) -> Bool {
        guard let original = allClips[originalID],
              let split = allClips[splitID] else { return false }
        original.sourceOut = split.sourceOut
        allClips.removeValue(forKey: splitID)
        return true
    }

    func performClipRemove(clipID: UUID) -> Bool {
        allClips.removeValue(forKey: clipID) != nil
    }

    @discardableResult
    func performClipRestore(_ data: ClipModel.Snapshot, trackID: UUID) -> Bool {
        let clip = ClipModel(from: data, trackID: trackID)
        allClips[clip.id] = clip
        return true
    }

    func performTrackInsert(id: UUID, name: String, type: TrackType, at index: Int) -> Bool {
        switch type {
        case .video:
            let track = VideoTrackModel(id: id, name: name)
            let safeIndex = min(index, videoTracks.count)
            videoTracks.insert(track, at: safeIndex)
        case .audio:
            let track = AudioTrackModel(id: id, name: name)
            let safeIndex = min(index, audioTracks.count)
            audioTracks.insert(track, at: safeIndex)
        case .subtitle:
            return false
        }
        return true
    }

    func performTrackRemove(trackID: UUID, type: TrackType) -> Bool {
        switch type {
        case .video: videoTracks.removeAll { $0.id == trackID }
        case .audio: audioTracks.removeAll { $0.id == trackID }
        case .subtitle: return false
        }
        return true
    }

    func recalculateDuration() {
        var maxEnd = Rational.zero
        for clip in allClips.values {
            let clipEnd = clip.startTime + clip.duration
            if clipEnd > maxEnd { maxEnd = clipEnd }
        }
        duration = maxEnd
    }

    func rebuildInternalState(from sequence: ProjectModel.Sequence) {
        allClips.removeAll()
        for track in sequence.tracks {
            for clipData in track.clips {
                let clip = ClipModel(
                    id: clipData.id,
                    sourceAssetID: clipData.sourceAssetID,
                    trackID: track.id,
                    startTime: clipData.startTime,
                    sourceIn: clipData.sourceIn,
                    sourceOut: clipData.sourceOut
                )
                clip.speed = clipData.speed.seconds
                clip.isEnabled = clipData.isEnabled
                clip.speedRamp = clipData.speedRamp
                allClips[clip.id] = clip
            }
        }
        recalculateDuration()
    }
}
