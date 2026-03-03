import Foundation
import Observation

/// Manages clip grouping. Linked clips move together.
@Observable
public final class GroupsModel: @unchecked Sendable {
    private var downLinks: [UUID: Set<UUID>] = [:]
    private var upLink: [UUID: UUID] = [:]

    public init() {}

    @discardableResult
    public func group(_ itemIDs: Set<UUID>) -> UUID {
        let groupID = UUID()
        downLinks[groupID] = itemIDs
        for itemID in itemIDs {
            if let oldParent = upLink[itemID] {
                downLinks[oldParent]?.remove(itemID)
            }
            upLink[itemID] = groupID
        }
        return groupID
    }

    public func ungroup(_ groupID: UUID) {
        guard let children = downLinks[groupID] else { return }
        for child in children { upLink.removeValue(forKey: child) }
        downLinks.removeValue(forKey: groupID)
    }

    public func rootGroup(for itemID: UUID) -> UUID {
        var current = itemID
        while let parent = upLink[current] { current = parent }
        return current
    }

    public func leaves(of groupID: UUID) -> Set<UUID> {
        guard let children = downLinks[groupID] else { return [groupID] }
        var result = Set<UUID>()
        for child in children { result.formUnion(leaves(of: child)) }
        return result
    }

    public func isGrouped(_ itemID: UUID) -> Bool {
        upLink[itemID] != nil
    }
}
