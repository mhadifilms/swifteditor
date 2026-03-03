import Foundation

/// Middleware that logs command execution to stdout
public final class LoggingMiddleware: CommandMiddleware {
    public init() {}

    public func beforeExecute(_ command: any Command) async -> Bool {
        print("[CommandBus] Executing: \(type(of: command).typeIdentifier)")
        return true
    }

    public func afterExecute(_ command: any Command, result: CommandResult) async {
        switch result {
        case .success:
            print("[CommandBus] Completed: \(type(of: command).typeIdentifier)")
        case .successWithValue:
            print("[CommandBus] Completed with value: \(type(of: command).typeIdentifier)")
        case .failure(let error):
            print("[CommandBus] Failed: \(type(of: command).typeIdentifier) - \(error)")
        }
    }
}
