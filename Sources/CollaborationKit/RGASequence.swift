// CollaborationKit — RGA (Replicated Growable Array) sequence CRDT
import Foundation

// MARK: - RGANode

/// A single node in the RGA linked structure.
/// Deleted nodes are tombstoned (value set to nil) rather than removed,
/// so that concurrent operations referencing them can still be applied.
public final class RGANode<T: Sendable & Codable>: Sendable {
    public let id: CRDTIdentifier
    public let afterID: CRDTIdentifier?
    // nonisolated(unsafe) because mutation only happens through RGASequence
    // which is not meant to be shared across isolation domains directly.
    nonisolated(unsafe) var _value: T?
    nonisolated(unsafe) var _isDeleted: Bool

    public var value: T? { _value }
    public var isDeleted: Bool { _isDeleted }

    public init(id: CRDTIdentifier, afterID: CRDTIdentifier?, value: T) {
        self.id = id
        self.afterID = afterID
        self._value = value
        self._isDeleted = false
    }
}

// MARK: - RGASequence

/// Replicated Growable Array — an ordered sequence CRDT that supports
/// concurrent insert and delete without conflicts.
///
/// Insertion position is specified by an anchor node (afterID). When two sites
/// concurrently insert after the same anchor, the node with the *higher*
/// CRDTIdentifier is placed first (closer to the anchor), ensuring a
/// deterministic total order across all replicas.
public final class RGASequence<T: Sendable & Codable>: Sendable {
    // nonisolated(unsafe) because this type is designed to be used within
    // a single actor / isolation context (e.g. SyncSession).
    nonisolated(unsafe) var nodes: [CRDTIdentifier: RGANode<T>] = [:]
    nonisolated(unsafe) var ordering: [CRDTIdentifier] = []

    public init() {}

    /// The number of live (non-tombstoned) elements.
    public var count: Int {
        ordering.reduce(0) { sum, id in
            if let node = nodes[id], !node.isDeleted { return sum + 1 }
            return sum
        }
    }

    /// Total number of nodes including tombstones.
    public var totalCount: Int { ordering.count }

    /// Insert a new element after the given anchor.
    /// Pass `nil` for `afterID` to insert at the head of the sequence.
    public func insert(id: CRDTIdentifier, afterID: CRDTIdentifier?, value: T) {
        guard nodes[id] == nil else { return } // idempotent

        let node = RGANode(id: id, afterID: afterID, value: value)
        nodes[id] = node

        if let afterID = afterID, let afterIndex = ordering.firstIndex(of: afterID) {
            var insertIndex = afterIndex + 1
            // Skip past concurrent inserts with the same anchor that have higher priority.
            while insertIndex < ordering.count {
                let existingID = ordering[insertIndex]
                guard let existing = nodes[existingID] else { break }
                if existing.afterID == afterID && existingID > id {
                    insertIndex += 1
                } else {
                    break
                }
            }
            ordering.insert(id, at: insertIndex)
        } else {
            // Insert at head — skip past concurrent head inserts with higher priority.
            var insertIndex = 0
            while insertIndex < ordering.count {
                let existingID = ordering[insertIndex]
                guard let existing = nodes[existingID] else { break }
                if existing.afterID == nil && existingID > id {
                    insertIndex += 1
                } else {
                    break
                }
            }
            ordering.insert(id, at: insertIndex)
        }
    }

    /// Tombstone-delete the node with the given id.
    /// The node remains in the ordering so that future inserts referencing it
    /// can still be positioned correctly.
    public func delete(id: CRDTIdentifier) {
        guard let node = nodes[id] else { return }
        node._isDeleted = true
        node._value = nil
    }

    /// Returns all live (non-tombstoned) elements in order.
    public var liveElements: [(id: CRDTIdentifier, value: T)] {
        ordering.compactMap { id in
            guard let node = nodes[id], !node.isDeleted, let value = node.value else {
                return nil
            }
            return (id, value)
        }
    }

    /// Returns the live element at the given logical index (skipping tombstones).
    public func element(at logicalIndex: Int) -> (id: CRDTIdentifier, value: T)? {
        var seen = 0
        for id in ordering {
            guard let node = nodes[id], !node.isDeleted, let value = node.value else {
                continue
            }
            if seen == logicalIndex { return (id, value) }
            seen += 1
        }
        return nil
    }

    /// Whether a node with the given id exists (including tombstones).
    public func contains(_ id: CRDTIdentifier) -> Bool {
        nodes[id] != nil
    }
}
