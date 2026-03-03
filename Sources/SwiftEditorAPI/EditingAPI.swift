import Foundation
import CoreMediaPlus
import CommandBus
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

    /// Undo last operation
    public func undo() async throws -> Bool {
        try await dispatcher.undo()
    }

    /// Redo last undone operation
    public func redo() async throws -> Bool {
        try await dispatcher.redo()
    }
}
