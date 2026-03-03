import Foundation
import CoreMediaPlus
import CommandBus
import ProjectModel
import TimelineKit

/// Facade for timeline editing operations.
/// All operations create Command structs and dispatch through CommandBus.
public final class EditingAPI: @unchecked Sendable {
    private let dispatcher: CommandDispatcher
    private let timeline: TimelineModel

    public init(dispatcher: CommandDispatcher, timeline: TimelineModel) {
        self.dispatcher = dispatcher
        self.timeline = timeline
    }

    /// Add a clip to a track
    @discardableResult
    public func addClip(sourceAssetID: UUID, trackID: UUID, at position: Rational,
                         sourceIn: Rational, sourceOut: Rational) async throws -> CommandResult {
        let command = AddClipCommand(sourceAssetID: sourceAssetID, trackID: trackID,
                                      position: position, sourceIn: sourceIn, sourceOut: sourceOut)
        return try await dispatcher.dispatch(command)
    }

    /// Move a clip to a new track/position
    @discardableResult
    public func moveClip(_ clipID: UUID, toTrack: UUID, at position: Rational) async throws -> CommandResult {
        let command = MoveClipCommand(clipID: clipID, toTrackID: toTrack, position: position)
        return try await dispatcher.dispatch(command)
    }

    /// Trim a clip edge
    @discardableResult
    public func trimClip(_ clipID: UUID, edge: TrimEdge, to time: Rational) async throws -> CommandResult {
        let command = TrimClipCommand(clipID: clipID, edge: edge, toTime: time)
        return try await dispatcher.dispatch(command)
    }

    /// Split a clip at the given time
    @discardableResult
    public func splitClip(_ clipID: UUID, at time: Rational) async throws -> CommandResult {
        let command = SplitClipCommand(clipID: clipID, atTime: time)
        return try await dispatcher.dispatch(command)
    }

    /// Delete a clip
    @discardableResult
    public func deleteClip(_ clipID: UUID) async throws -> CommandResult {
        let command = DeleteClipCommand(clipID: clipID)
        return try await dispatcher.dispatch(command)
    }

    /// Add a track
    @discardableResult
    public func addTrack(type: TrackType, at index: Int) async throws -> CommandResult {
        let command = AddTrackCommand(trackType: type, atIndex: index)
        return try await dispatcher.dispatch(command)
    }

    /// Remove a track
    @discardableResult
    public func removeTrack(_ trackID: UUID) async throws -> CommandResult {
        let command = RemoveTrackCommand(trackID: trackID)
        return try await dispatcher.dispatch(command)
    }

    // MARK: - Advanced Editing Operations

    /// Insert edit — splits at position, inserts clip, pushes downstream
    @discardableResult
    public func insertEdit(sourceAssetID: UUID, trackID: UUID, at time: Rational,
                            sourceIn: Rational, sourceOut: Rational) async throws -> CommandResult {
        let command = InsertEditCommand(sourceAssetID: sourceAssetID, trackID: trackID,
                                         atTime: time, sourceIn: sourceIn, sourceOut: sourceOut)
        return try await dispatcher.dispatch(command)
    }

    /// Overwrite edit — replaces content at position without ripple
    @discardableResult
    public func overwriteEdit(sourceAssetID: UUID, trackID: UUID, at time: Rational,
                               sourceIn: Rational, sourceOut: Rational) async throws -> CommandResult {
        let command = OverwriteEditCommand(sourceAssetID: sourceAssetID, trackID: trackID,
                                            atTime: time, sourceIn: sourceIn, sourceOut: sourceOut)
        return try await dispatcher.dispatch(command)
    }

    /// Ripple delete — removes clip and closes gap
    @discardableResult
    public func rippleDelete(_ clipID: UUID) async throws -> CommandResult {
        let command = RippleDeleteCommand(clipID: clipID)
        return try await dispatcher.dispatch(command)
    }

    /// Ripple trim — trims clip and shifts downstream
    @discardableResult
    public func rippleTrim(_ clipID: UUID, edge: TrimEdge, to time: Rational) async throws -> CommandResult {
        let command = RippleTrimCommand(clipID: clipID, edge: edge, toTime: time)
        return try await dispatcher.dispatch(command)
    }

    /// Roll trim — adjusts edit point between two adjacent clips
    @discardableResult
    public func rollTrim(leftClipID: UUID, rightClipID: UUID, to time: Rational) async throws -> CommandResult {
        let command = RollTrimCommand(leftClipID: leftClipID, rightClipID: rightClipID, toTime: time)
        return try await dispatcher.dispatch(command)
    }

    /// Slip — changes source in/out without moving clip
    @discardableResult
    public func slip(_ clipID: UUID, by offset: Rational) async throws -> CommandResult {
        let command = SlipCommand(clipID: clipID, offset: offset)
        return try await dispatcher.dispatch(command)
    }

    /// Slide — moves clip, adjusts neighbors
    @discardableResult
    public func slide(_ clipID: UUID, by offset: Rational,
                       leftNeighborID: UUID?, rightNeighborID: UUID?) async throws -> CommandResult {
        let command = SlideCommand(clipID: clipID, offset: offset,
                                    leftNeighborID: leftNeighborID, rightNeighborID: rightNeighborID)
        return try await dispatcher.dispatch(command)
    }

    /// Blade all — splits all clips on all tracks at a time
    @discardableResult
    public func bladeAll(at time: Rational) async throws -> CommandResult {
        let command = BladeAllCommand(atTime: time)
        return try await dispatcher.dispatch(command)
    }

    /// Speed change
    @discardableResult
    public func setSpeed(_ clipID: UUID, newSpeed: Double) async throws -> CommandResult {
        let command = SpeedChangeCommand(clipID: clipID, newSpeed: newSpeed)
        return try await dispatcher.dispatch(command)
    }

    /// Append at end — adds clip after the last clip on a track
    @discardableResult
    public func appendAtEnd(sourceAssetID: UUID, trackID: UUID,
                             sourceIn: Rational, sourceOut: Rational) async throws -> CommandResult {
        let command = AppendAtEndCommand(sourceAssetID: sourceAssetID, trackID: trackID,
                                          sourceIn: sourceIn, sourceOut: sourceOut)
        return try await dispatcher.dispatch(command)
    }

    /// Place on top — finds or creates a free track
    @discardableResult
    public func placeOnTop(sourceAssetID: UUID, at position: Rational,
                            sourceIn: Rational, sourceOut: Rational) async throws -> CommandResult {
        let command = PlaceOnTopCommand(sourceAssetID: sourceAssetID, position: position,
                                         sourceIn: sourceIn, sourceOut: sourceOut)
        return try await dispatcher.dispatch(command)
    }

    // MARK: - Lift / Extract

    /// Lift — removes clip and leaves gap (same as delete in track-based NLE)
    @discardableResult
    public func lift(_ clipID: UUID) async throws -> CommandResult {
        let command = DeleteClipCommand(clipID: clipID)
        return try await dispatcher.dispatch(command)
    }

    /// Ripple overwrite — replace clip at position and adjust timeline duration
    @discardableResult
    public func rippleOverwrite(sourceAssetID: UUID, trackID: UUID, at time: Rational,
                                 sourceIn: Rational, sourceOut: Rational) async throws -> CommandResult {
        let command = RippleOverwriteCommand(sourceAssetID: sourceAssetID, trackID: trackID,
                                              atTime: time, sourceIn: sourceIn, sourceOut: sourceOut)
        return try await dispatcher.dispatch(command)
    }

    /// Fit to fill — speed-adjusts source to fill a given duration
    @discardableResult
    public func fitToFill(sourceAssetID: UUID, trackID: UUID, at position: Rational,
                           sourceIn: Rational, sourceOut: Rational,
                           fillDuration: Rational) async throws -> CommandResult {
        let command = FitToFillCommand(sourceAssetID: sourceAssetID, trackID: trackID,
                                        atTime: position, sourceIn: sourceIn, sourceOut: sourceOut,
                                        fillDuration: fillDuration)
        return try await dispatcher.dispatch(command)
    }

    /// Replace edit — replaces clip under playhead, matching at playhead frame
    @discardableResult
    public func replaceEdit(sourceAssetID: UUID, trackID: UUID,
                             sourcePlayheadTime: Rational,
                             timelinePlayheadTime: Rational) async throws -> CommandResult {
        let command = ReplaceEditCommand(sourceAssetID: sourceAssetID, trackID: trackID,
                                          sourcePlayheadTime: sourcePlayheadTime,
                                          timelinePlayheadTime: timelinePlayheadTime)
        return try await dispatcher.dispatch(command)
    }

    // MARK: - Markers

    /// Add a marker to the timeline
    @discardableResult
    public func addMarker(name: String, at time: Rational, color: String = "blue") async throws -> CommandResult {
        let command = AddMarkerCommand(name: name, atTime: time, color: color)
        return try await dispatcher.dispatch(command)
    }

    /// Remove a marker
    @discardableResult
    public func removeMarker(_ markerID: UUID) async throws -> CommandResult {
        let command = RemoveMarkerCommand(markerID: markerID)
        return try await dispatcher.dispatch(command)
    }

    /// Update a marker's properties
    public func updateMarker(id: UUID, name: String? = nil, color: String? = nil, notes: String? = nil) {
        let markerColor: ProjectModel.Marker.MarkerColor? = color.flatMap { ProjectModel.Marker.MarkerColor(rawValue: $0) }
        timeline.markerManager.updateMarker(id: id, name: name, color: markerColor, notes: notes)
    }

    /// Get all markers, sorted by time
    public var markers: [TimelineMarker] {
        timeline.markerManager.sortedMarkers
    }

    /// Get markers of a specific type
    public func markers(ofType type: MarkerType) -> [TimelineMarker] {
        timeline.markerManager.markers(ofType: type)
    }

    /// Get markers attached to a specific clip
    public func markers(forClip clipID: UUID) -> [TimelineMarker] {
        timeline.markerManager.markers(forClip: clipID)
    }

    /// Get timeline-level markers only (not clip-attached)
    public var timelineMarkers: [TimelineMarker] {
        timeline.markerManager.timelineMarkers
    }

    /// Navigate to the next marker after a given time
    public func nextMarker(after time: Rational) -> TimelineMarker? {
        timeline.markerManager.nextMarker(after: time)
    }

    /// Navigate to the previous marker before a given time
    public func previousMarker(before time: Rational) -> TimelineMarker? {
        timeline.markerManager.previousMarker(before: time)
    }

    // MARK: - Timeline Query

    /// Get a clip by ID
    public func clip(by id: UUID) -> ClipModel? {
        timeline.clip(by: id)
    }

    /// Get all clips on a track, sorted by start time
    public func clipsOnTrack(_ trackID: UUID) -> [ClipModel] {
        timeline.clipsOnTrack(trackID)
    }

    /// Get the clip at a specific time on a specific track
    public func clipAt(time: Rational, trackID: UUID) -> ClipModel? {
        timeline.clipAt(time: time, trackID: trackID)
    }

    /// The total duration of the timeline
    public var timelineDuration: Rational {
        timeline.duration
    }

    /// Export the current timeline state to a ProjectModel.Sequence
    public func exportToSequence() -> ProjectModel.Sequence {
        timeline.exportToSequence()
    }

    /// Load timeline state from a ProjectModel.Sequence
    public func loadFromSequence(_ sequence: ProjectModel.Sequence) {
        timeline.load(from: sequence)
    }

    // MARK: - Undo / Redo

    /// Undo last operation
    public func undo() async throws -> Bool {
        try await dispatcher.undo()
    }

    /// Redo last undone operation
    public func redo() async throws -> Bool {
        try await dispatcher.redo()
    }

    /// Whether undo is available
    public var canUndo: Bool {
        get async { await dispatcher.canUndo }
    }

    /// Whether redo is available
    public var canRedo: Bool {
        get async { await dispatcher.canRedo }
    }

    /// Description of the command that would be undone
    public var undoDescription: String? {
        get async { await dispatcher.undoDescription }
    }

    /// Description of the command that would be redone
    public var redoDescription: String? {
        get async { await dispatcher.redoDescription }
    }
}
