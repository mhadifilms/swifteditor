import Foundation

/// Registry that maps type identifier strings to Command types for deserialization.
/// Thread-safe via NSLock for use from any isolation context.
public final class CommandRegistry: @unchecked Sendable {
    public static let shared = CommandRegistry()

    private var types: [String: any Command.Type] = [:]
    private let lock = NSLock()

    public init() {}

    /// Register a command type for serialization/deserialization
    public func register<C: Command>(_ type: C.Type) {
        lock.lock()
        defer { lock.unlock() }
        types[C.typeIdentifier] = type
    }

    /// Look up a command type by its identifier
    public func commandType(for identifier: String) -> (any Command.Type)? {
        lock.lock()
        defer { lock.unlock() }
        return types[identifier]
    }
}
