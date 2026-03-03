import Foundation
import CollaborationKit
import TimelineKit

/// Facade for real-time collaboration sessions.
public final class CollaborationAPI: @unchecked Sendable {

    private let timeline: TimelineModel?

    /// The active collaboration bridge, if a session is running.
    public private(set) var bridge: CollaborationBridge?

    /// The active sync session, if connected.
    public private(set) var activeSession: SyncSession?

    public init(timeline: TimelineModel? = nil) {
        self.timeline = timeline
    }

    /// Create a new sync session with a unique site ID.
    public func createSession() -> SyncSession {
        SyncSession()
    }

    /// Start a collaboration session: creates a bridge, connects to the server,
    /// and begins syncing local/remote operations.
    public func startSession(host: String, port: UInt16) async -> SyncSession? {
        guard let timeline else { return nil }

        let session = SyncSession()
        let newBridge = CollaborationBridge(timeline: timeline, session: session)
        await newBridge.start()
        await session.connect(host: host, port: port)

        self.activeSession = session
        self.bridge = newBridge
        return session
    }

    /// Stop the active collaboration session.
    public func stopSession() async {
        bridge?.stop()
        if let session = activeSession {
            await session.disconnect()
        }
        bridge = nil
        activeSession = nil
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
