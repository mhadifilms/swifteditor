import Foundation
import CoreMediaPlus
import CommandBus
import TimelineKit

/// Facade for network server control — enables remote/programmatic control of the editor.
public final class NetworkAPI: @unchecked Sendable {
    private var server: NetworkServer?
    private let dispatcher: CommandDispatcher
    private let timelineProvider: @Sendable () -> TimelineModel?
    private let transportStateProvider: @Sendable () -> NetworkTransportState
    private let importHandler: (@Sendable ([URL]) async throws -> [[String: String]])?
    private let rebuildHandler: (@Sendable () async -> Void)?
    private let effectsHandler: (@Sendable (NetworkServer.EffectsAction) async throws -> [String: Any])?

    public init(dispatcher: CommandDispatcher,
                timelineProvider: @escaping @Sendable () -> TimelineModel?,
                transportStateProvider: @escaping @Sendable () -> NetworkTransportState,
                importHandler: (@Sendable ([URL]) async throws -> [[String: String]])? = nil,
                rebuildHandler: (@Sendable () async -> Void)? = nil,
                effectsHandler: (@Sendable (NetworkServer.EffectsAction) async throws -> [String: Any])? = nil) {
        self.dispatcher = dispatcher
        self.timelineProvider = timelineProvider
        self.transportStateProvider = transportStateProvider
        self.importHandler = importHandler
        self.rebuildHandler = rebuildHandler
        self.effectsHandler = effectsHandler
    }

    /// Start the network server with the given configuration.
    public func start(configuration: NetworkServerConfiguration = NetworkServerConfiguration()) throws {
        let server = NetworkServer(
            configuration: configuration,
            dispatcher: dispatcher,
            timelineProvider: timelineProvider,
            transportStateProvider: transportStateProvider,
            importHandler: importHandler,
            rebuildHandler: rebuildHandler,
            effectsHandler: effectsHandler
        )
        try server.start()
        self.server = server
    }

    /// Stop the network server.
    public func stop() {
        server?.stop()
        server = nil
    }

    /// Whether the network server is currently running.
    public var isRunning: Bool {
        server?.isRunning ?? false
    }
}
