import Foundation

/// Protocol for command handlers that execute commands
public protocol CommandHandler: Sendable {
    associatedtype CommandType: Command

    /// Validate the command before execution
    func validate(_ command: CommandType) throws

    /// Execute the command and return an inverse command for undo
    func execute(_ command: CommandType) async throws -> (any Command)?
}

/// Type-erased command handler protocol used internally by the dispatcher
protocol ErasedCommandHandler: Sendable {
    func validate(_ command: any Command) throws
    func execute(_ command: any Command) async throws -> (any Command)?
}

/// Wrapper that type-erases a concrete CommandHandler
struct AnyCommandHandler<H: CommandHandler>: ErasedCommandHandler {
    let handler: H

    func validate(_ command: any Command) throws {
        guard let typed = command as? H.CommandType else {
            throw CommandError.executionFailed(
                "Type mismatch: expected \(H.CommandType.self), got \(type(of: command))"
            )
        }
        try handler.validate(typed)
    }

    func execute(_ command: any Command) async throws -> (any Command)? {
        guard let typed = command as? H.CommandType else {
            throw CommandError.executionFailed(
                "Type mismatch: expected \(H.CommandType.self), got \(type(of: command))"
            )
        }
        return try await handler.execute(typed)
    }
}
