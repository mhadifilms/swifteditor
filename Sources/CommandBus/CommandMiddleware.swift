import Foundation

/// Middleware that can intercept commands before/after execution
public protocol CommandMiddleware: Sendable {
    /// Called before command execution. Return false to abort.
    func beforeExecute(_ command: any Command) async -> Bool
    /// Called after successful command execution
    func afterExecute(_ command: any Command, result: CommandResult) async
}
