import Foundation
import CoreMediaPlus

/// Protocol for all commands in the system.
/// Commands are value types that describe an operation to perform.
public protocol Command: Codable, Sendable {
    /// Unique type identifier for serialization/deserialization
    static var typeIdentifier: String { get }
    /// Human-readable description for undo menu
    var undoDescription: String { get }
    /// Whether this command mutates state (vs read-only queries)
    var isMutating: Bool { get }
}
