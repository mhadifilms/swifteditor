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

    public init(dispatcher: CommandDispatcher,
                timelineProvider: @escaping @Sendable () -> TimelineModel?,
                transportStateProvider: @escaping @Sendable () -> NetworkTransportState) {
        self.dispatcher = dispatcher
        self.timelineProvider = timelineProvider
        self.transportStateProvider = transportStateProvider
    }

    /// Start the network server with the given configuration.
    public func start(configuration: NetworkServerConfiguration = NetworkServerConfiguration()) throws {
        let server = NetworkServer(
            configuration: configuration,
            dispatcher: dispatcher,
            timelineProvider: timelineProvider,
            transportStateProvider: transportStateProvider
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
