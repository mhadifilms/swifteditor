import Foundation

/// Central command dispatcher that routes commands to handlers,
/// manages undo/redo stacks, and runs the middleware pipeline.
public actor CommandDispatcher {
    private var handlers: [String: any ErasedCommandHandler] = [:]
    private var middlewares: [any CommandMiddleware] = []
    private var undoStack: [UndoEntry] = []
    private var redoStack: [UndoEntry] = []
    private let maxUndoLevels: Int

    /// An entry on the undo/redo stack
    public struct UndoEntry: Sendable {
        public let command: any Command
        public let inverse: any Command
        public let description: String
        public let timestamp: Date
    }

    /// Create a dispatcher with a maximum number of undo levels
    public init(maxUndoLevels: Int = 200) {
        self.maxUndoLevels = maxUndoLevels
    }

    /// Register a command handler for its associated command type
    public func register<H: CommandHandler>(_ handler: H) where H.CommandType: Command {
        let key = H.CommandType.typeIdentifier
        handlers[key] = AnyCommandHandler(handler: handler)
    }

    /// Add a middleware to the pipeline
    public func addMiddleware(_ middleware: any CommandMiddleware) {
        middlewares.append(middleware)
    }

    /// Dispatch a command through the middleware pipeline and execute it.
    /// Returns the result and pushes an undo entry if the command is mutating
    /// and provides an inverse.
    @discardableResult
    public func dispatch(_ command: any Command) async throws -> CommandResult {
        let typeId = type(of: command).typeIdentifier

        // Run before-middleware; abort if any returns false
        for middleware in middlewares {
            let proceed = await middleware.beforeExecute(command)
            if !proceed {
                let result = CommandResult.failure(.executionFailed("Aborted by middleware"))
                return result
            }
        }

        guard let handler = handlers[typeId] else {
            throw CommandError.handlerNotFound(
                "No handler registered for command type: \(typeId)"
            )
        }

        // Validate
        try handler.validate(command)

        // Execute
        let inverse = try await handler.execute(command)

        // Build result
        let result = CommandResult.success

        // Push to undo stack if mutating and inverse is available
        if command.isMutating, let inverse = inverse {
            let entry = UndoEntry(
                command: command,
                inverse: inverse,
                description: command.undoDescription,
                timestamp: Date()
            )
            undoStack.append(entry)
            if undoStack.count > maxUndoLevels {
                undoStack.removeFirst()
            }
            // Clear redo stack on new command
            redoStack.removeAll()
        }

        // Run after-middleware
        for middleware in middlewares {
            await middleware.afterExecute(command, result: result)
        }

        return result
    }

    /// Undo the most recent command. Returns true if an undo was performed.
    public func undo() async throws -> Bool {
        guard let entry = undoStack.popLast() else { return false }

        let typeId = type(of: entry.inverse).typeIdentifier
        guard let handler = handlers[typeId] else {
            throw CommandError.undoFailed(
                "No handler registered for inverse command type: \(typeId)"
            )
        }

        try handler.validate(entry.inverse)
        _ = try await handler.execute(entry.inverse)

        redoStack.append(entry)
        return true
    }

    /// Redo the most recently undone command. Returns true if a redo was performed.
    public func redo() async throws -> Bool {
        guard let entry = redoStack.popLast() else { return false }

        let typeId = type(of: entry.command).typeIdentifier
        guard let handler = handlers[typeId] else {
            throw CommandError.undoFailed(
                "No handler registered for command type: \(typeId)"
            )
        }

        try handler.validate(entry.command)
        let inverse = try await handler.execute(entry.command)

        // Rebuild the undo entry with the new inverse (if available)
        let newEntry = UndoEntry(
            command: entry.command,
            inverse: inverse ?? entry.inverse,
            description: entry.description,
            timestamp: Date()
        )
        undoStack.append(newEntry)
        return true
    }

    /// Whether there are commands that can be undone
    public var canUndo: Bool {
        !undoStack.isEmpty
    }

    /// Whether there are commands that can be redone
    public var canRedo: Bool {
        !redoStack.isEmpty
    }

    /// Description of the command that would be undone, for the Edit menu
    public var undoDescription: String? {
        undoStack.last?.description
    }

    /// Description of the command that would be redone, for the Edit menu
    public var redoDescription: String? {
        redoStack.last?.description
    }
}
