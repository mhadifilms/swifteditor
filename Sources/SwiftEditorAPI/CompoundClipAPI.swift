import Foundation
import CoreMediaPlus
import CommandBus
import TimelineKit

/// Facade for compound clip operations.
/// Mutating operations go through CommandBus for undo support.
public final class CompoundClipAPI: @unchecked Sendable {
    private let dispatcher: CommandDispatcher
    private let timeline: TimelineModel

    public init(dispatcher: CommandDispatcher, timeline: TimelineModel) {
        self.dispatcher = dispatcher
        self.timeline = timeline
    }

    // MARK: - Command-Based Operations

    /// Create a compound clip from selected clips.
    @discardableResult
    public func createCompoundClip(clipIDs: Set<UUID>) async throws -> CommandResult {
        let command = CreateCompoundClipCommand(clipIDs: clipIDs)
        return try await dispatcher.dispatch(command)
    }

    /// Flatten (expand) a compound clip back into its component clips.
    @discardableResult
    public func flattenCompoundClip(compoundClipID: UUID) async throws -> CommandResult {
        let command = FlattenCompoundClipCommand(compoundClipID: compoundClipID)
        return try await dispatcher.dispatch(command)
    }

    // MARK: - Query

    /// Check if a clip is a compound clip.
    public func isCompoundClip(_ clipID: UUID) -> Bool {
        timeline.isCompoundClip(clipID)
    }

    /// Access the nested timeline for a compound clip.
    public func nestedTimeline(for clipID: UUID) -> TimelineModel? {
        timeline.nestedTimeline(for: clipID)
    }

    /// All compound clips on the timeline, keyed by compound clip ID.
    public var compoundClips: [UUID: CompoundClipModel] {
        timeline.compoundClips
    }
}
