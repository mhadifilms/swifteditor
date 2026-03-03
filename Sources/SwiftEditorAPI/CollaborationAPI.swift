import Foundation
import CollaborationKit

/// Facade for real-time collaboration sessions.
public final class CollaborationAPI: @unchecked Sendable {

    public init() {}

    /// Create a new sync session with a unique site ID.
    public func createSession() -> SyncSession {
        SyncSession()
    }

    /// Connect a session to a collaboration server.
    public func connect(session: SyncSession, to host: String, port: UInt16) async {
        await session.connect(host: host, port: port)
    }

    /// Disconnect a session from the server.
    public func disconnect(session: SyncSession) async {
        await session.disconnect()
    }

    /// Send a timeline operation to the connected server.
    public func send(operation: TimelineOperation, session: SyncSession) async {
        await session.send(operation: operation)
    }

    /// Generate a new CRDT identifier from the session's Lamport clock.
    public func nextIdentifier(session: SyncSession) async -> CRDTIdentifier {
        await session.nextIdentifier()
    }

    /// Get the current Lamport clock value for a session.
    public func currentClock(session: SyncSession) async -> UInt64 {
        await session.currentClock()
    }
}
