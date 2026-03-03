// CollaborationKit — Network sync transport using WebSocket (Network.framework)
import Foundation
import Network

// MARK: - SyncSession

/// Actor that manages a WebSocket connection to a collaboration server,
/// serializing outbound operations and deserializing inbound ones.
public actor SyncSession {
    public let siteID: UUID
    private let clock: LamportClock
    private var connection: NWConnection?
    private var isConnected: Bool = false
    private var pendingOutbound: [OperationEnvelope] = []
    private var sequenceCounter: UInt64 = 0

    /// Called when a remote operation is received and deserialized.
    public var onRemoteOperation: (@Sendable (OperationEnvelope) -> Void)?

    /// Called when the connection state changes.
    public var onConnectionStateChanged: (@Sendable (ConnectionState) -> Void)?

    public enum ConnectionState: Sendable {
        case connecting
        case connected
        case disconnected(Error?)
    }

    public init(siteID: UUID = UUID()) {
        self.siteID = siteID
        self.clock = LamportClock(siteID: siteID)
    }

    // MARK: - Connection Lifecycle

    /// Connect to a collaboration server via WebSocket.
    /// - Parameters:
    ///   - host: The server hostname or IP.
    ///   - port: The server port.
    ///   - path: The WebSocket endpoint path (default "/sync").
    public func connect(host: String, port: UInt16, path: String = "/sync") {
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true

        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let conn = NWConnection(to: endpoint, using: parameters)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handleStateUpdate(state) }
        }

        conn.start(queue: DispatchQueue(label: "com.swifteditor.sync"))
        onConnectionStateChanged?(.connecting)
    }

    /// Disconnect from the server.
    public func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        onConnectionStateChanged?(.disconnected(nil))
    }

    // MARK: - Send Operations

    /// Enqueue a local operation to be sent to the server.
    public func send(operation: TimelineOperation) async {
        sequenceCounter += 1
        let envelope = OperationEnvelope(
            senderID: siteID,
            sequenceNumber: sequenceCounter,
            operation: operation
        )

        if isConnected {
            await writeEnvelope(envelope)
        } else {
            pendingOutbound.append(envelope)
        }
    }

    /// Returns the current Lamport clock value.
    public func currentClock() async -> UInt64 {
        await clock.value
    }

    /// Generates a new CRDTIdentifier by ticking the Lamport clock.
    public func nextIdentifier() async -> CRDTIdentifier {
        await clock.tick()
    }

    // MARK: - Private

    private func handleStateUpdate(_ state: NWConnection.State) {
        switch state {
        case .ready:
            isConnected = true
            onConnectionStateChanged?(.connected)
            flushPending()
            startReceiving()
        case .failed(let error):
            isConnected = false
            onConnectionStateChanged?(.disconnected(error))
        case .cancelled:
            isConnected = false
            onConnectionStateChanged?(.disconnected(nil))
        default:
            break
        }
    }

    private func flushPending() {
        let pending = pendingOutbound
        pendingOutbound.removeAll()
        for envelope in pending {
            Task { await writeEnvelope(envelope) }
        }
    }

    private func writeEnvelope(_ envelope: OperationEnvelope) async {
        guard let connection else { return }
        do {
            let data = try JSONEncoder().encode(envelope)
            let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
            let context = NWConnection.ContentContext(
                identifier: "sync",
                metadata: [metadata]
            )
            connection.send(
                content: data,
                contentContext: context,
                isComplete: true,
                completion: .contentProcessed { _ in }
            )
        } catch {
            pendingOutbound.append(envelope)
        }
    }

    private func startReceiving() {
        guard let connection else { return }
        connection.receiveMessage { [weak self] content, _, _, error in
            guard let self else { return }
            if let data = content {
                Task { await self.handleReceivedData(data) }
            }
            if error == nil {
                Task { await self.startReceiving() }
            }
        }
    }

    private func handleReceivedData(_ data: Data) async {
        do {
            let envelope = try JSONDecoder().decode(OperationEnvelope.self, from: data)
            await clock.merge(remoteClock: envelope.sequenceNumber)
            onRemoteOperation?(envelope)
        } catch {
            // Malformed message — skip
        }
    }
}
