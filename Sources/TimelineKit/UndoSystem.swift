import Foundation
import Observation

/// A closure that performs an undoable operation. Returns true on success.
public typealias UndoAction = @Sendable () -> Bool

/// Append an operation to a redo chain.
public func appendOperation(_ chain: inout UndoAction, _ operation: @escaping UndoAction) {
    let previous = chain
    chain = { previous() && operation() }
}

/// Prepend an operation to an undo chain (undo runs in reverse order).
public func prependOperation(_ chain: inout UndoAction, _ operation: @escaping UndoAction) {
    let previous = chain
    chain = { operation() && previous() }
}

/// An entry in the undo stack.
public struct UndoEntry: Sendable {
    public let undo: UndoAction
    public let redo: UndoAction
    public let description: String
    public let timestamp: Date
}

/// Lambda-based undo/redo manager (Kdenlive-inspired).
@Observable
public final class TimelineUndoManager: @unchecked Sendable {
    public private(set) var undoStack: [UndoEntry] = []
    public private(set) var redoStack: [UndoEntry] = []
    public private(set) var canUndo: Bool = false
    public private(set) var canRedo: Bool = false
    public var maxUndoLevels: Int = 200

    public init() {}

    public func record(undo: @escaping UndoAction, redo: @escaping UndoAction,
                       description: String) {
        let entry = UndoEntry(undo: undo, redo: redo,
                              description: description, timestamp: .now)
        undoStack.append(entry)
        redoStack.removeAll()
        if undoStack.count > maxUndoLevels {
            undoStack.removeFirst()
        }
        canUndo = true
        canRedo = false
    }

    @discardableResult
    public func undo() -> Bool {
        guard let entry = undoStack.popLast() else { return false }
        guard entry.undo() else {
            undoStack.append(entry)
            return false
        }
        redoStack.append(entry)
        canUndo = !undoStack.isEmpty
        canRedo = true
        return true
    }

    @discardableResult
    public func redo() -> Bool {
        guard let entry = redoStack.popLast() else { return false }
        guard entry.redo() else {
            redoStack.append(entry)
            return false
        }
        undoStack.append(entry)
        canUndo = true
        canRedo = !redoStack.isEmpty
        return true
    }

    public var undoDescription: String? {
        undoStack.last?.description
    }

    public var redoDescription: String? {
        redoStack.last?.description
    }
}
