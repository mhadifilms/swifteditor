import Foundation
import TimelineKit

/// Facade for clip grouping operations.
/// Groups are managed directly by the GroupsModel (no commands needed).
public final class GroupsAPI: @unchecked Sendable {
    private let timeline: TimelineModel

    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }

    /// Create a group from the given clip IDs. Returns the new group ID.
    @discardableResult
    public func group(clipIDs: Set<UUID>) -> UUID {
        timeline.groupsModel.group(clipIDs)
    }

    /// Dissolve a group, ungrouping all its children.
    public func ungroup(groupID: UUID) {
        timeline.groupsModel.ungroup(groupID)
    }

    /// Find the root group for a clip. Returns the clip itself if not grouped.
    public func rootGroup(for clipID: UUID) -> UUID {
        timeline.groupsModel.rootGroup(for: clipID)
    }

    /// Get all leaf clip IDs under a group.
    public func leaves(of groupID: UUID) -> Set<UUID> {
        timeline.groupsModel.leaves(of: groupID)
    }

    /// Check if a clip belongs to any group.
    public func isGrouped(_ clipID: UUID) -> Bool {
        timeline.groupsModel.isGrouped(clipID)
    }
}
