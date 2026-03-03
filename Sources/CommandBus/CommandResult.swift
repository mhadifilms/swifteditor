import Foundation

/// Result of executing a command
public enum CommandResult: Sendable {
    case success
    case successWithValue(any Sendable)
    case failure(CommandError)
}

/// Errors that can occur during command execution
public enum CommandError: Error, Sendable {
    case handlerNotFound(String)
    case validationFailed(String)
    case executionFailed(String)
    case undoFailed(String)
    case serializationFailed(String)
}
