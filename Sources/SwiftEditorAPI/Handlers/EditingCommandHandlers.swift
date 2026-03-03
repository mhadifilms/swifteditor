import Foundation
import CoreMediaPlus
import CommandBus
import TimelineKit

/// Handler for AddClipCommand
public final class AddClipHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = AddClipCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: AddClipCommand) throws {
        // Validate track exists
    }

    public func execute(_ command: AddClipCommand) async throws -> (any Command)? {
        let clipID = timeline.requestAddClip(
            sourceAssetID: command.sourceAssetID,
            trackID: command.trackID,
            at: command.position,
            sourceIn: command.sourceIn,
            sourceOut: command.sourceOut
        )
        guard clipID != nil else {
            throw CommandError.executionFailed("Failed to add clip")
        }
        // Undo is handled by TimelineKit's internal undo manager
        return nil
    }
}

/// Handler for MoveClipCommand
public final class MoveClipHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = MoveClipCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: MoveClipCommand) throws {
        guard timeline.clip(by: command.clipID) != nil else {
            throw CommandError.validationFailed("Clip not found: \(command.clipID)")
        }
    }

    public func execute(_ command: MoveClipCommand) async throws -> (any Command)? {
        let clip = timeline.clip(by: command.clipID)!
        let previousTrackID = clip.trackID
        let previousPosition = clip.startTime

        guard timeline.requestClipMove(clipID: command.clipID, toTrackID: command.toTrackID,
                                        at: command.position) else {
            throw CommandError.executionFailed("Move failed")
        }

        return MoveClipCommand(clipID: command.clipID, toTrackID: previousTrackID,
                               position: previousPosition)
    }
}

/// Handler for TrimClipCommand
public final class TrimClipHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = TrimClipCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: TrimClipCommand) throws {
        guard timeline.clip(by: command.clipID) != nil else {
            throw CommandError.validationFailed("Clip not found: \(command.clipID)")
        }
    }

    public func execute(_ command: TrimClipCommand) async throws -> (any Command)? {
        guard timeline.requestClipResize(clipID: command.clipID, edge: command.edge,
                                          to: command.toTime) else {
            throw CommandError.executionFailed("Trim failed")
        }
        return nil
    }
}

/// Handler for SplitClipCommand
public final class SplitClipHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = SplitClipCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: SplitClipCommand) throws {
        guard timeline.clip(by: command.clipID) != nil else {
            throw CommandError.validationFailed("Clip not found: \(command.clipID)")
        }
    }

    public func execute(_ command: SplitClipCommand) async throws -> (any Command)? {
        guard timeline.requestClipSplit(clipID: command.clipID, at: command.atTime) else {
            throw CommandError.executionFailed("Split failed")
        }
        return nil
    }
}

/// Handler for DeleteClipCommand
public final class DeleteClipHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = DeleteClipCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: DeleteClipCommand) throws {
        guard timeline.clip(by: command.clipID) != nil else {
            throw CommandError.validationFailed("Clip not found: \(command.clipID)")
        }
    }

    public func execute(_ command: DeleteClipCommand) async throws -> (any Command)? {
        guard timeline.requestClipDelete(clipID: command.clipID) else {
            throw CommandError.executionFailed("Delete failed")
        }
        return nil
    }
}

/// Handler for AddTrackCommand
public final class AddTrackHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = AddTrackCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: AddTrackCommand) throws {}

    public func execute(_ command: AddTrackCommand) async throws -> (any Command)? {
        guard let trackID = timeline.requestTrackInsert(at: command.atIndex, type: command.trackType) else {
            throw CommandError.executionFailed("Add track failed")
        }
        return RemoveTrackCommand(trackID: trackID)
    }
}

/// Handler for RemoveTrackCommand
public final class RemoveTrackHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = RemoveTrackCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    public func validate(_ command: RemoveTrackCommand) throws {}

    public func execute(_ command: RemoveTrackCommand) async throws -> (any Command)? {
        guard timeline.requestTrackRemove(trackID: command.trackID) else {
            throw CommandError.executionFailed("Remove track failed")
        }
        return nil
    }
}

/// Handler for RippleOverwriteCommand
public final class RippleOverwriteHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = RippleOverwriteCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) { self.timeline = timeline }
    public func validate(_ command: RippleOverwriteCommand) throws {}

    public func execute(_ command: RippleOverwriteCommand) async throws -> (any Command)? {
        guard timeline.requestRippleOverwrite(
            sourceAssetID: command.sourceAssetID, trackID: command.trackID,
            at: command.atTime, sourceIn: command.sourceIn, sourceOut: command.sourceOut
        ) != nil else {
            throw CommandError.executionFailed("Ripple overwrite failed")
        }
        return nil
    }
}

/// Handler for FitToFillCommand
public final class FitToFillHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = FitToFillCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) { self.timeline = timeline }
    public func validate(_ command: FitToFillCommand) throws {}

    public func execute(_ command: FitToFillCommand) async throws -> (any Command)? {
        guard timeline.requestFitToFill(
            sourceAssetID: command.sourceAssetID, trackID: command.trackID,
            at: command.atTime, sourceIn: command.sourceIn, sourceOut: command.sourceOut,
            fillDuration: command.fillDuration
        ) != nil else {
            throw CommandError.executionFailed("Fit to fill failed")
        }
        return nil
    }
}

/// Handler for ReplaceEditCommand
public final class ReplaceEditHandler: CommandHandler, @unchecked Sendable {
    public typealias CommandType = ReplaceEditCommand
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) { self.timeline = timeline }
    public func validate(_ command: ReplaceEditCommand) throws {}

    public func execute(_ command: ReplaceEditCommand) async throws -> (any Command)? {
        guard timeline.requestReplaceEdit(
            sourceAssetID: command.sourceAssetID, trackID: command.trackID,
            sourcePlayheadTime: command.sourcePlayheadTime,
            timelinePlayheadTime: command.timelinePlayheadTime
        ) != nil else {
            throw CommandError.executionFailed("Replace edit failed")
        }
        return nil
    }
}
